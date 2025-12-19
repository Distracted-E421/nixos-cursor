//! Hyper-based proxy server handling HTTP/1.1 and HTTP/2
//!
//! This is the core proxy implementation that intercepts Cursor traffic.

use crate::capture::{PayloadCapturer, ExchangeBuilder};
use crate::cert::CertificateAuthority;
use crate::config::Config;
use crate::dns::ExternalDnsResolver;
use crate::error::{ProxyError, ProxyResult};
use crate::injection::{InjectionEngine, InjectionConfig};
use crate::iptables::IptablesManager;
use crate::pool::Http2Pool;

use bytes::Bytes;
use http::{Request, Response, StatusCode};
use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::rustls::ServerConfig;
use tokio_rustls::TlsAcceptor;
use tracing::{debug, error, info, warn};

/// Proxy server state
pub struct ProxyServer {
    /// Configuration
    config: Config,
    /// Certificate authority
    ca: Arc<CertificateAuthority>,
    /// HTTP/2 connection pool for upstream
    pool: Arc<Http2Pool>,
    /// Payload capturer
    capturer: Arc<PayloadCapturer>,
    /// Injection engine for request/response modification
    injector: Arc<InjectionEngine>,
    /// iptables manager (if transparent mode - legacy)
    iptables: Option<Arc<IptablesManager>>,
    /// Connection counter
    conn_counter: AtomicU64,
    /// Request counter
    req_counter: AtomicU64,
    /// Whether server is running
    running: std::sync::atomic::AtomicBool,
    /// Event broadcaster for dashboard
    events: crate::events::EventBroadcaster,
}

/// Connection context
struct ConnectionContext {
    conn_id: u64,
    #[allow(dead_code)]
    peer_addr: SocketAddr,
    target_domain: String,
}

impl ProxyServer {
    /// Create a new proxy server
    pub async fn new(config: Config, ca: CertificateAuthority) -> ProxyResult<Self> {
        // Initialize external DNS resolver and connection pool
        let dns = Arc::new(ExternalDnsResolver::new().await?);
        let pool = Arc::new(Http2Pool::new(dns)?);
        
        // Initialize payload capturer with retention
        let capturer = Arc::new(PayloadCapturer::with_retention(
            &config.capture.directory,
            config.capture.max_payload_size,
            config.capture.enabled,
            config.capture.retention_days,
        )?);
        
        // Initialize injection engine with config
        let injection_config = InjectionConfig {
            enabled: config.injection.enabled,
            system_prompt: config.injection.system_prompt.clone(),
            custom_mode: config.injection.custom_mode.clone(),
            context_files: config.injection.context_files.clone(),
            headers: config.injection.headers.clone(),
            spoof_version: config.injection.spoof_version.clone(),
            rules_file: config.injection.rules_file.clone(),
        };
        let injector = Arc::new(InjectionEngine::new(injection_config));
        
        Ok(Self {
            config,
            ca: Arc::new(ca),
            pool,
            capturer,
            injector,
            iptables: None,
            conn_counter: AtomicU64::new(0),
            req_counter: AtomicU64::new(0),
            running: std::sync::atomic::AtomicBool::new(false),
            events: crate::events::EventBroadcaster::new(),
        })
    }
    
    /// Get event broadcaster (for IPC server)
    pub fn event_broadcaster(&self) -> crate::events::EventBroadcaster {
        self.events.clone()
    }
    
    /// Setup iptables for transparent mode
    pub fn setup_transparent(&mut self) -> ProxyResult<()> {
        if !self.config.iptables.auto_manage {
            info!("iptables auto-management disabled");
            return Ok(());
        }
        
        let manager = IptablesManager::new(
            self.config.proxy.port,
            self.config.iptables.cleanup_on_exit,
        )?;
        
        // Add rules for configured targets
        for target in &self.config.iptables.targets {
            match manager.add_domain(target) {
                Ok(ips) => {
                    if ips.is_empty() {
                        warn!("No IPs found for target: {}", target);
                    }
                }
                Err(e) => {
                    warn!("Failed to add iptables rules for {}: {}", target, e);
                }
            }
        }
        
        self.iptables = Some(Arc::new(manager));
        Ok(())
    }
    
    /// Start the proxy server
    pub async fn start(self: Arc<Self>) -> ProxyResult<()> {
        let addr = SocketAddr::from(([0, 0, 0, 0], self.config.proxy.port));
        
        let listener = TcpListener::bind(addr).await
            .map_err(|e| ProxyError::BindFailed { 
                port: self.config.proxy.port, 
                reason: e.to_string() 
            })?;
        
        info!("🚀 Cursor Proxy listening on {}", addr);
        self.running.store(true, Ordering::SeqCst);
        
        // Print setup instructions
        self.print_setup_instructions();
        
        // Start periodic cleanup task
        let cleanup_server = Arc::clone(&self);
        tokio::spawn(async move {
            let mut cleanup_interval = tokio::time::interval(std::time::Duration::from_secs(60));
            while cleanup_server.running.load(Ordering::SeqCst) {
                cleanup_interval.tick().await;
                // Clean up connection pool
                cleanup_server.pool.cleanup().await;
                // Clean up old captures (runs every minute, but only deletes old files)
                let _ = cleanup_server.capturer.cleanup_old_captures();
            }
        });
        
        while self.running.load(Ordering::SeqCst) {
            match listener.accept().await {
                Ok((stream, peer_addr)) => {
                    let server = Arc::clone(&self);
                    tokio::spawn(async move {
                        if let Err(e) = server.handle_connection(stream, peer_addr).await {
                            if !e.is_recoverable() {
                                error!("Connection error: {}", e);
                            } else {
                                debug!("Connection closed: {}", e);
                            }
                        }
                    });
                }
                Err(e) => {
                    warn!("Failed to accept connection: {}", e);
                }
            }
        }
        
        info!("Proxy server stopped");
        Ok(())
    }
    
    /// Stop the proxy server
    pub fn stop(&self) {
        info!("Stopping proxy server...");
        self.running.store(false, Ordering::SeqCst);
        // Clear connection pool to release resources
        self.pool.clear();
    }
    
    /// Get next connection ID
    fn next_conn_id(&self) -> u64 {
        self.conn_counter.fetch_add(1, Ordering::SeqCst)
    }
    
    /// Handle a single connection
    async fn handle_connection(
        &self,
        stream: TcpStream,
        peer_addr: SocketAddr,
    ) -> ProxyResult<()> {
        use crate::events::ProxyEvent;
        use chrono::Utc;
        
        let conn_id = self.next_conn_id();
        let conn_start = std::time::Instant::now();
        
        // For cursor traffic, domain is always api2.cursor.sh
        let domain = "api2.cursor.sh".to_string();
        
        let ctx = ConnectionContext {
            conn_id,
            peer_addr,
            target_domain: domain.clone(),
        };
        
        debug!("[{}] New connection from {}", conn_id, peer_addr);
        
        // Emit ConnectionOpened event
        self.events.emit(ProxyEvent::ConnectionOpened {
            conn_id,
            peer_addr: peer_addr.to_string(),
            timestamp: Utc::now(),
        });
        
        // Generate certificate for this domain
        let (certs, key) = self.ca.generate_cert_for_domain(&ctx.target_domain)?;
        
        // Create TLS server config with ALPN for HTTP/2
        let mut server_config = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, key)
            .map_err(|e| ProxyError::Certificate(e.to_string()))?;
        
        // Support both HTTP/1.1 and HTTP/2
        server_config.alpn_protocols = vec![
            b"h2".to_vec(),
            b"http/1.1".to_vec(),
        ];
        
        let tls_acceptor = TlsAcceptor::from(Arc::new(server_config));
        
        // Accept TLS connection
        let tls_stream = tls_acceptor.accept(stream).await
            .map_err(|e| ProxyError::ClientTls(e.to_string()))?;
        
        // Check what protocol was negotiated
        let alpn = tls_stream.get_ref().1.alpn_protocol();
        let protocol = match alpn {
            Some(b"h2") => "h2",
            Some(b"http/1.1") => "http/1.1",
            Some(other) => {
                let proto = String::from_utf8_lossy(other);
                debug!("[{}] Unknown ALPN: {}", conn_id, proto);
                "http/1.1" // Default to HTTP/1.1
            }
            None => "http/1.1", // No ALPN means HTTP/1.1
        };
        
        debug!("[{}] Negotiated protocol: {}", conn_id, protocol);
        
        // Handle based on protocol
        let result = match protocol {
            "h2" => self.handle_h2_connection(ctx, tls_stream).await,
            _ => self.handle_http1_connection(ctx, tls_stream).await,
        };
        
        // Emit ConnectionClosed event
        self.events.emit(ProxyEvent::ConnectionClosed {
            conn_id,
            timestamp: Utc::now(),
            duration_ms: conn_start.elapsed().as_millis() as u64,
        });
        
        result
    }
    
    /// Handle HTTP/1.1 connection
    async fn handle_http1_connection<S>(&self, ctx: ConnectionContext, stream: S) -> ProxyResult<()>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let conn_id = ctx.conn_id;
        let target_domain = ctx.target_domain.clone();
        let pool = Arc::clone(&self.pool);
        let capturer = Arc::clone(&self.capturer);
        let injector = Arc::clone(&self.injector);
        let events = self.events.clone();
        let req_counter = Arc::new(AtomicU64::new(self.req_counter.load(Ordering::Relaxed)));
        
        let io = TokioIo::new(stream);
        
        let service = service_fn(move |req: Request<Incoming>| {
            let domain = target_domain.clone();
            let pool = Arc::clone(&pool);
            let capturer = Arc::clone(&capturer);
            let injector = Arc::clone(&injector);
            let events = events.clone();
            let req_counter = Arc::clone(&req_counter);
            
            async move {
                Self::handle_request(conn_id, req, &domain, pool, capturer, injector, events, req_counter).await
            }
        });
        
        http1::Builder::new()
            .serve_connection(io, service)
            .await
            .map_err(|e| ProxyError::Http(e.to_string()))?;
        
        debug!("[{}] HTTP/1.1 connection closed", conn_id);
        Ok(())
    }
    
    /// Handle HTTP/2 connection (using hyper's H2 support)
    async fn handle_h2_connection<S>(&self, ctx: ConnectionContext, stream: S) -> ProxyResult<()>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let conn_id = ctx.conn_id;
        let target_domain = ctx.target_domain.clone();
        let pool = Arc::clone(&self.pool);
        let capturer = Arc::clone(&self.capturer);
        let injector = Arc::clone(&self.injector);
        let events = self.events.clone();
        let req_counter = Arc::new(AtomicU64::new(self.req_counter.load(Ordering::Relaxed)));
        
        let io = TokioIo::new(stream);
        
        let service = service_fn(move |req: Request<Incoming>| {
            let domain = target_domain.clone();
            let pool = Arc::clone(&pool);
            let capturer = Arc::clone(&capturer);
            let injector = Arc::clone(&injector);
            let events = events.clone();
            let req_counter = Arc::clone(&req_counter);
            
            async move {
                Self::handle_request(conn_id, req, &domain, pool, capturer, injector, events, req_counter).await
            }
        });
        
        // Use HTTP/2 server
        hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
            .serve_connection(io, service)
            .await
            .map_err(|e| ProxyError::Http(e.to_string()))?;
        
        debug!("[{}] HTTP/2 connection closed", conn_id);
        Ok(())
    }
    
    /// Handle a single HTTP request (works for both HTTP/1.1 and HTTP/2)
    async fn handle_request(
        conn_id: u64,
        req: Request<Incoming>,
        target_domain: &str,
        pool: Arc<Http2Pool>,
        capturer: Arc<PayloadCapturer>,
        injector: Arc<InjectionEngine>,
        events: crate::events::EventBroadcaster,
        req_counter: Arc<AtomicU64>,
    ) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
        use crate::events::{ProxyEvent, parse_path};
        use chrono::Utc;
        
        let request_id = req_counter.fetch_add(1, Ordering::Relaxed);
        let start_time = std::time::Instant::now();
        
        let method = req.method().clone();
        let uri = req.uri().clone();
        let path = uri.path().to_string();
        
        // Parse service and endpoint
        let (service, endpoint) = parse_path(&path);
        
        // Check if this is an interesting endpoint (worth capturing)
        let is_chat = path.contains("ChatService");
        let is_ai = path.contains("AiService");
        let should_capture = is_chat || is_ai;
        
        if should_capture {
            info!("[{}] 🎯 {} {}", conn_id, method, path);
        } else {
            debug!("[{}] {} {}", conn_id, method, path);
        }
        
        // Emit RequestStarted event
        events.emit(ProxyEvent::RequestStarted {
            conn_id,
            request_id,
            method: method.to_string(),
            path: path.clone(),
            service: service.clone(),
            endpoint: endpoint.clone(),
            timestamp: Utc::now(),
        });
        
        // Start capture if enabled and this is an interesting request
        let capture_builder = if should_capture && capturer.is_enabled() {
            Some(capturer.start_capture(conn_id, method.as_str(), &path))
        } else {
            None
        };
        
        // Forward to upstream using connection pool with optional injection
        match Self::forward_to_upstream_with_capture(
            conn_id, 
            req, 
            target_domain, 
            pool, 
            &capturer,
            capture_builder.flatten(),
            injector,
            &endpoint,
        ).await {
            Ok(response) => {
                let status = response.status();
                let duration_ms = start_time.elapsed().as_millis() as u64;
                
                if should_capture {
                    info!("[{}] ← {} {} ({}ms)", conn_id, status, path, duration_ms);
                }
                
                // Emit RequestCompleted event
                events.emit(ProxyEvent::RequestCompleted {
                    conn_id,
                    request_id,
                    status: status.as_u16(),
                    duration_ms,
                    request_size: 0, // TODO: track actual size
                    response_size: None, // TODO: track actual size
                    timestamp: Utc::now(),
                });
                
                Ok(response)
            }
            Err(e) => {
                let duration_ms = start_time.elapsed().as_millis() as u64;
                error!("[{}] Upstream error ({}ms): {}", conn_id, duration_ms, e);
                
                // Emit RequestFailed event
                events.emit(ProxyEvent::RequestFailed {
                    conn_id,
                    request_id,
                    error: e.to_string(),
                    timestamp: Utc::now(),
                });
                // Return 502 Bad Gateway
                let response = Response::builder()
                    .status(StatusCode::BAD_GATEWAY)
                    .body(Self::full_body(Bytes::from(format!("Upstream error: {}", e))))
                    .unwrap();
                Ok(response)
            }
        }
    }
    
    /// Forward request to upstream server with optional capture and injection
    async fn forward_to_upstream_with_capture(
        conn_id: u64,
        req: Request<Incoming>,
        target_domain: &str,
        pool: Arc<Http2Pool>,
        capturer: &PayloadCapturer,
        capture_builder: Option<ExchangeBuilder>,
        injector: Arc<InjectionEngine>,
        endpoint: &str,
    ) -> ProxyResult<Response<BoxBody<Bytes, hyper::Error>>> {
        // Buffer the request body (required for retries and HTTP/2 framing)
        let (mut parts, body) = req.into_parts();
        let mut body_bytes = body.collect().await
            .map_err(|e| ProxyError::Http(format!("Failed to read request body: {}", e)))?
            .to_bytes();
        
        // Apply injection modifications if enabled
        if injector.is_enabled().await {
            // Modify headers (version spoofing, custom headers)
            injector.modify_headers(&mut parts.headers).await;
            
            // Modify chat request body (system prompt, context injection)
            if let Some(modified) = injector.modify_chat_request(&body_bytes, endpoint).await {
                body_bytes = modified;
                info!("[{}] 🔧 Injected content into request", conn_id);
            }
        }
        
        // Capture request if builder exists
        let builder = if let Some(b) = capture_builder {
            // Capture request headers
            let headers: Vec<(String, String)> = parts.headers.iter()
                .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("<binary>").to_string()))
                .collect();
            
            // Get content type for body capture
            let content_type = parts.headers.get("content-type")
                .and_then(|v| v.to_str().ok());
            
            // Capture request body
            let captured_body = capturer.capture_body(&body_bytes, content_type);
            
            Some(b.request_headers(headers).request_body(captured_body))
        } else {
            None
        };
        
        // Build upstream request
        let mut upstream_req = Request::builder()
            .method(parts.method.clone())
            .uri(format!("https://{}{}", target_domain, parts.uri.path_and_query().map(|pq| pq.as_str()).unwrap_or("/")))
            .version(http::Version::HTTP_2);
        
        // Copy headers (filtering out connection-specific ones)
        for (name, value) in parts.headers.iter() {
            let name_str = name.as_str();
            if !name_str.eq_ignore_ascii_case("host") 
                && !name_str.eq_ignore_ascii_case("connection")
                && !name_str.eq_ignore_ascii_case("transfer-encoding")
            {
                upstream_req = upstream_req.header(name, value);
            }
        }
        
        // Add host header
        upstream_req = upstream_req.header("host", target_domain);
        
        let upstream_req = upstream_req.body(Full::new(body_bytes))
            .map_err(|e| ProxyError::Http(e.to_string()))?;
        
        // Send request through connection pool (handles connection reuse and retries)
        let response = pool.send_request(target_domain, 443, upstream_req).await?;
        
        // Get response parts for capture
        let (resp_parts, body) = response.into_parts();
        let status = resp_parts.status;
        
        // Capture response if builder exists
        if let Some(mut b) = builder {
            // Capture response headers
            let headers: Vec<(String, String)> = resp_parts.headers.iter()
                .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("<binary>").to_string()))
                .collect();
            
            b = b.response_status(status.as_u16())
                .response_headers(headers);
            
            // Note: We can't easily capture streaming response body without buffering
            // For now, just save what we have. Full streaming capture would require
            // wrapping the body stream.
            
            // Build and save the capture
            let exchange = b.build();
            let capturer_clone = capturer.clone();
            tokio::spawn(async move {
                if let Err(e) = capturer_clone.save(exchange).await {
                    warn!("Failed to save capture: {}", e);
                }
            });
        }
        
        // Build response
        let mut response_builder = Response::builder().status(status);
        
        for (name, value) in resp_parts.headers.iter() {
            response_builder = response_builder.header(name, value);
        }
        
        // Convert the incoming body to a boxed stream body for proper streaming
        let stream_body = body.map_err(|e| e).boxed();
        
        let response = response_builder.body(stream_body)
            .map_err(|e| ProxyError::Http(e.to_string()))?;
        
        Ok(response)
    }
    
    /// Create a full body from bytes
    fn full_body(bytes: Bytes) -> BoxBody<Bytes, hyper::Error> {
        Full::new(bytes)
            .map_err(|never| match never {})
            .boxed()
    }
    
    /// Get original destination from socket (transparent proxy)
    #[cfg(target_os = "linux")]
    #[allow(dead_code)]
    fn get_original_dst(stream: &TcpStream) -> ProxyResult<SocketAddr> {
        use std::os::unix::io::AsRawFd;

        let fd = stream.as_raw_fd();
        const SO_ORIGINAL_DST: libc::c_int = 80;

        let mut addr: libc::sockaddr_in = unsafe { std::mem::zeroed() };
        let mut len: libc::socklen_t = std::mem::size_of::<libc::sockaddr_in>() as libc::socklen_t;

        let ret = unsafe {
            libc::getsockopt(
                fd,
                libc::SOL_IP,
                SO_ORIGINAL_DST,
                &mut addr as *mut _ as *mut libc::c_void,
                &mut len,
            )
        };

        if ret != 0 {
            // Fallback for non-transparent mode
            warn!("Not in transparent mode, using fallback destination");
            return Ok("52.41.57.32:443".parse().unwrap());
        }

        let ip = std::net::Ipv4Addr::from(u32::from_be(addr.sin_addr.s_addr));
        let port = u16::from_be(addr.sin_port);

        Ok(SocketAddr::new(std::net::IpAddr::V4(ip), port))
    }
    
    #[cfg(not(target_os = "linux"))]
    #[allow(dead_code)]
    fn get_original_dst(_stream: &TcpStream) -> ProxyResult<SocketAddr> {
        // Fallback for non-Linux
        Ok("52.41.57.32:443".parse().unwrap())
    }
    
    /// Print setup instructions
    fn print_setup_instructions(&self) {
        info!("");
        info!("╔══════════════════════════════════════════════════════════════╗");
        info!("║              Cursor Proxy v{} Ready                        ║", env!("CARGO_PKG_VERSION"));
        info!("╠══════════════════════════════════════════════════════════════╣");
        
        if self.iptables.is_some() {
            info!("║ ✓ Transparent mode active (iptables configured)             ║");
        } else {
            info!("║ ⚠ Explicit proxy mode (set NODE_EXTRA_CA_CERTS)             ║");
        }
        
        if self.capturer.is_enabled() {
            info!("║ ✓ Payload capture ENABLED                                   ║");
        } else {
            info!("║ ⚠ Payload capture DISABLED (enable in config)               ║");
        }
        
        info!("║                                                              ║");
        info!("║ Launch Cursor with:                                          ║");
        info!("║   cursor-studio --proxy                                      ║");
        info!("║                                                              ║");
        info!("║ Or trust the CA:                                             ║");
        info!("║   cursor-studio proxy trust-ca                               ║");
        info!("╚══════════════════════════════════════════════════════════════╝");
        info!("");
    }
}
