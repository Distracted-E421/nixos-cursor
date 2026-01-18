//! Cursor AI Transparent Proxy with Context Injection
//!
//! A transparent HTTP/2 proxy designed to intercept Cursor IDE's AI traffic
//! for context injection and custom modes.
//!
//! Architecture:
//! 1. Transparent proxy via iptables NAT redirect
//! 2. TLS termination with dynamic certificate generation
//! 3. HTTP/2 frame inspection using h2 crate
//! 4. gRPC stream capture and modification
//! 5. Context injection into chat requests

mod injection;

use anyhow::{Context, Result};
use bytes::{Bytes, BytesMut};
use clap::{Parser, Subcommand};
use dashmap::DashMap;
use h2::server::{self, SendResponse};
use h2::{client, SendStream};
use http::{Request, Response, StatusCode, Method};
use injection::{InjectionConfig, InjectionEngine};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tokio::io::{AsyncRead, AsyncWrite, AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_rustls::rustls::{self, ServerConfig, ClientConfig};
use tokio_rustls::{TlsAcceptor, TlsConnector};
use tracing::{debug, error, info, warn, Level};
use tracing_subscriber::FmtSubscriber;
use std::convert::TryInto; // Ensure TryInto is available

/// Cursor AI Transparent Proxy
#[derive(Parser)]
#[command(name = "cursor-proxy")]
#[command(about = "Transparent HTTP/2 proxy for Cursor AI streaming interception")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the proxy server
    Start {
        /// Port to listen on
        #[arg(short, long, default_value = "8443")]
        port: u16,

        /// Path to CA certificate
        #[arg(long, default_value = "~/.cursor-proxy/ca-cert.pem")]
        ca_cert: PathBuf,

        /// Path to CA private key
        #[arg(long, default_value = "~/.cursor-proxy/ca-key.pem")]
        ca_key: PathBuf,

        /// Enable verbose logging
        #[arg(short, long)]
        verbose: bool,
        
        /// Save captured payloads to directory
        #[arg(long)]
        capture_dir: Option<PathBuf>,
        
        /// Enable injection
        #[arg(long)]
        inject: bool,
        
        /// System prompt to inject (for quick testing)
        #[arg(long)]
        inject_prompt: Option<String>,
        
        /// Path to injection config file (TOML)
        #[arg(long)]
        inject_config: Option<PathBuf>,
        
        /// Context files to inject (can be specified multiple times)
        #[arg(long = "inject-context")]
        inject_context: Vec<PathBuf>,
    },

    /// Generate CA certificate for TLS interception
    GenerateCa {
        /// Output directory
        #[arg(short, long, default_value = "~/.cursor-proxy")]
        output: PathBuf,
    },

    /// Show status and statistics
    Status,
}

/// Captured stream data
#[derive(Debug, Clone)]
struct CapturedStream {
    stream_id: u32,
    service: String,
    method: String,
    request_headers: Vec<(String, String)>,
    request_data: BytesMut,
    response_headers: Vec<(String, String)>,
    response_data: BytesMut,
    started: Instant,
}

impl CapturedStream {
    fn new(stream_id: u32) -> Self {
        Self {
            stream_id,
            service: String::new(),
            method: String::new(),
            request_headers: Vec::new(),
            request_data: BytesMut::new(),
            response_headers: Vec::new(),
            response_data: BytesMut::new(),
            started: Instant::now(),
        }
    }
}

/// Global proxy state
struct ProxyState {
    /// Active streams being captured
    streams: DashMap<(u64, u32), CapturedStream>,
    /// Connection counter
    conn_counter: std::sync::atomic::AtomicU64,
    /// CA certificate for signing
    ca_cert: rcgen::Certificate,
    ca_key: rcgen::KeyPair,
    /// Capture directory
    capture_dir: Option<PathBuf>,
    /// Injection engine
    injection: Arc<InjectionEngine>,
}

impl ProxyState {
    fn next_conn_id(&self) -> u64 {
        self.conn_counter
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
    }
    
    /// Generate a certificate for a specific domain, signed by our CA
    fn generate_cert_for_domain(&self, domain: &str) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>)> {
        use rcgen::{CertificateParams, DistinguishedName, DnType, KeyPair, SanType};
        
        let mut params = CertificateParams::default();
        
        // Set distinguished name
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, domain);
        params.distinguished_name = dn;
        
        // Add subject alternative names
        params.subject_alt_names = vec![
            SanType::DnsName(domain.try_into()?),
        ];
        
        // Valid for 1 day (short-lived)
        params.not_before = time::OffsetDateTime::now_utc();
        params.not_after = time::OffsetDateTime::now_utc() + time::Duration::days(1);
        
        // Generate key pair for this cert
        let key_pair = KeyPair::generate()?;
        
        // Sign with CA
        let cert = params.signed_by(&key_pair, &self.ca_cert, &self.ca_key)?;
        
        // Convert to rustls types
        let cert_der = CertificateDer::from(cert.der().to_vec());
        let ca_cert_der = CertificateDer::from(self.ca_cert.der().to_vec());
        
        let key_der = PrivateKeyDer::try_from(key_pair.serialize_der())
            .map_err(|e| anyhow::anyhow!("Failed to convert key: {:?}", e))?;
        
        Ok((vec![cert_der, ca_cert_der], key_der))
    }
}

/// Get original destination from socket (for transparent proxy)
#[cfg(target_os = "linux")]
fn get_original_dst(stream: &TcpStream) -> Result<SocketAddr> {
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
        return Err(anyhow::anyhow!(
            "Failed to get original destination: {}",
            std::io::Error::last_os_error()
        ));
    }

    let ip = std::net::Ipv4Addr::from(u32::from_be(addr.sin_addr.s_addr));
    let port = u16::from_be(addr.sin_port);

    Ok(SocketAddr::new(std::net::IpAddr::V4(ip), port))
}

#[cfg(not(target_os = "linux"))]
fn get_original_dst(_stream: &TcpStream) -> Result<SocketAddr> {
    Err(anyhow::anyhow!("Transparent proxy only supported on Linux"))
}

/// Load CA certificate and key for signing
fn load_ca(cert_path: &PathBuf, key_path: &PathBuf) -> Result<(rcgen::Certificate, rcgen::KeyPair)> {
    let cert_expanded = shellexpand::tilde(&cert_path.to_string_lossy()).to_string();
    let key_expanded = shellexpand::tilde(&key_path.to_string_lossy()).to_string();
    
    let cert_pem = std::fs::read_to_string(&cert_expanded)
        .with_context(|| format!("Failed to read CA cert: {}", cert_expanded))?;
    let key_pem = std::fs::read_to_string(&key_expanded)
        .with_context(|| format!("Failed to read CA key: {}", key_expanded))?;
    
    // Load the existing key
    let key_pair = rcgen::KeyPair::from_pem(&key_pem)?;
    
    // CRITICAL: Load the EXISTING CA certificate params to preserve serial, dates, etc.
    // This ensures the cert we use matches what is in the trust store
    let params = rcgen::CertificateParams::from_ca_cert_pem(&cert_pem)
        .with_context(|| "Failed to parse existing CA certificate")?;
    
    // Re-sign with the same key to get a Certificate object
    let cert = params.self_signed(&key_pair)?;
    
    Ok((cert, key_pair))
}

/// Parse gRPC path to extract service and method
fn parse_grpc_path(path: &str) -> (String, String) {
    let parts: Vec<&str> = path.trim_start_matches('/').split('/').collect();
    if parts.len() >= 2 {
        (parts[0].to_string(), parts[1].to_string())
    } else {
        (path.to_string(), String::new())
    }
}

/// Helper to send request data in chunks that respect HTTP/2 frame size limits
fn send_chunked_request(
    sender: &mut SendStream<Bytes>,
    data: Bytes,
    end_stream: bool,
) -> Result<(), h2::Error> {
    // 16KB is the safe default maximum frame size for HTTP/2.
    // While we can negotiate larger sizes, using the minimum guarantees compatibility
    // with peers that haven't explicitly allowed larger frames.
    const MAX_CHUNK_SIZE: usize = 16384;
    
    if data.len() <= MAX_CHUNK_SIZE {
        sender.send_data(data, end_stream)?;
    } else {
        let mut offset = 0;
        let total_len = data.len();
        while offset < total_len {
            let end = std::cmp::min(offset + MAX_CHUNK_SIZE, total_len);
            let chunk = data.slice(offset..end);
            offset = end;
            let is_last = offset == total_len;
            sender.send_data(chunk, is_last && end_stream)?;
        }
    }
    Ok(())
}

/// Helper to send response data in chunks that respect HTTP/2 frame size limits
fn send_chunked_response(
    sender: &mut SendStream<Bytes>,
    data: Bytes,
    end_stream: bool,
) -> Result<(), h2::Error> {
    const MAX_CHUNK_SIZE: usize = 16384;
    
    if data.len() <= MAX_CHUNK_SIZE {
        sender.send_data(data, end_stream)?;
    } else {
        let mut offset = 0;
        let total_len = data.len();
        while offset < total_len {
            let end = std::cmp::min(offset + MAX_CHUNK_SIZE, total_len);
            let chunk = data.slice(offset..end);
            offset = end;
            let is_last = offset == total_len;
            sender.send_data(chunk, is_last && end_stream)?;
        }
    }
    Ok(())
}

/// Handle a single HTTP/2 stream with INJECTION support
async fn handle_stream(
    conn_id: u64,
    stream_id: u32,
    request: Request<()>,
    mut recv_body: h2::RecvStream,
    mut send_response: SendResponse<Bytes>,
    upstream_sender: &mut client::SendRequest<Bytes>,
    state: Arc<ProxyState>,
) -> Result<()> {
    let path = request.uri().path().to_string();
    let (service, method) = parse_grpc_path(&path);
    
    let is_chat_service = service.contains("ChatService");
    let is_ai_service = service.contains("AiService");
    let is_interesting = is_chat_service || is_ai_service;
    let should_inject = is_chat_service && state.injection.is_enabled().await;
    
    if is_interesting {
        info!(
            "[{}/{}] 🎯 {} {}/{} {}",
            conn_id, stream_id,
            request.method(),
            service,
            method,
            if should_inject { "[INJECT]" } else { "" }
        );
        for (name, value) in request.headers() {
            info!("[{}/{}] Header: {} = {:?}", conn_id, stream_id, name, value);
        }
    } else {
        debug!(
            "[{}/{}] {} {}/{}",
            conn_id, stream_id,
            request.method(),
            service,
            method
        );
    }
    
    let (response_future, upstream_task, injected_bytes) = if should_inject {
        // --- INJECTION PATH (Framing-Aware) ---
        debug!("[{}/{}] Smart buffering for gRPC injection...", conn_id, stream_id);
        
        let mut request_buffer = BytesMut::new();
        let mut first_message_len = None;
        let mut stream_ended = false;
        
        // Read until we have a full message
        loop {
            // Check if we have header to determine length
            if first_message_len.is_none() && request_buffer.len() >= 5 {
                let len_bytes = &request_buffer[1..5];
                // gRPC length is Big Endian 4 bytes
                let msg_len = u32::from_be_bytes(len_bytes.try_into().unwrap()) as usize;
                let total_len = 5 + msg_len;
                first_message_len = Some(total_len);
                debug!("[{}/{}] Detected gRPC message length: {} (total frame: {})", conn_id, stream_id, msg_len, total_len);
            }
            
            // Check if we have the full first message
            if let Some(total_len) = first_message_len {
                if request_buffer.len() >= total_len {
                    debug!("[{}/{}] Captured full gRPC message", conn_id, stream_id);
                    break; 
                }
            }
            
            match recv_body.data().await {
                Some(Ok(chunk)) => {
                    let len = chunk.len();
                    let _ = recv_body.flow_control().release_capacity(len);
                    request_buffer.extend_from_slice(&chunk);
                }
                Some(Err(e)) => {
                    warn!("[{}/{}] Error reading from client: {}", conn_id, stream_id, e);
                    return Err(e.into());
                }
                None => {
                    debug!("[{}/{}] Client stream ended early", conn_id, stream_id);
                    stream_ended = true;
                    break;
                }
            }
        }
        
        // Split the buffer into First Message and Remaining
        let total_len = first_message_len.unwrap_or(request_buffer.len());
        
        let (first_msg, remaining) = if request_buffer.len() >= total_len && total_len > 0 {
            let msg = request_buffer.split_to(total_len).freeze();
            (msg, request_buffer) // request_buffer now contains only remaining bytes
        } else {
            (request_buffer.freeze(), BytesMut::new())
        };
        
        let endpoint = format!("{}/{}", service, method);
        
        // Inject into the first message
        let final_data = match state.injection.modify_chat_request(&first_msg, &endpoint).await {
            Some(modified) => {
                info!(
                    "[{}/{}] ✨ Injected context: {} → {} bytes",
                    conn_id, stream_id, first_msg.len(), modified.len()
                );
                modified
            }
            None => first_msg,
        };
        
        let final_len = final_data.len();
        
        // Build upstream request headers
        let mut upstream_req_builder = Request::builder()
            .method(request.method())
            .uri(request.uri())
            .version(http::Version::HTTP_2);
            
        for (name, value) in request.headers() {
            let name_str = name.as_str();
            // Skip content-length because we changed the size AND we are likely streaming
            // Skip x-cursor-checksum because we modified the body
            if !name_str.starts_with(':') && name_str != "host" && name_str != "connection" && name_str != "content-length"  {
                upstream_req_builder = upstream_req_builder.header(name, value);
            }
        }
        
        let upstream_request = upstream_req_builder.body(())?;
        
        // Send request headers (DO NOT end stream, we might have more data or be open)
        let (response_future, mut send_to_upstream) = upstream_sender.send_request(upstream_request, false)?;
        
        // Send injected message
        let send_remaining = !remaining.is_empty();
        let end_after_msg = stream_ended && !send_remaining;
        
        send_chunked_request(&mut send_to_upstream, final_data, end_after_msg)?;
        
        // Send any remaining bytes from buffer
        if send_remaining {
            send_chunked_request(&mut send_to_upstream, remaining.freeze(), stream_ended)?;
        }
        
        // Spawn task to forward FUTURE chunks from client (if stream not ended)
        let task = if !stream_ended {
            let conn_id = conn_id;
            let stream_id = stream_id;
            let is_interesting = is_interesting;
            
            Some(tokio::spawn(async move {
                let mut streamed_bytes = 0usize;
                loop {
                    match recv_body.data().await {
                        Some(Ok(chunk)) => {
                            let len = chunk.len();
                            streamed_bytes += len;
                            let _ = recv_body.flow_control().release_capacity(len);
                            
                            if is_interesting && len > 0 {
                                debug!("[{}/{}] 📤 Forwarding extra chunk: {} bytes", conn_id, stream_id, len);
                            }
                            
                            if let Err(e) = send_chunked_request(&mut send_to_upstream, chunk, false) {
                                warn!("[{}/{}] Failed to forward to upstream: {}", conn_id, stream_id, e);
                                break;
                            }
                        }
                        Some(Err(e)) => {
                            warn!("[{}/{}] Error reading from client: {}", conn_id, stream_id, e);
                            break;
                        }
                        None => {
                            debug!("[{}/{}] Client stream ended (streaming)", conn_id, stream_id);
                            let _ = send_chunked_request(&mut send_to_upstream, Bytes::new(), true);
                            break;
                        }
                    }
                }
                streamed_bytes
            }))
        } else {
            None
        };
        
        (response_future, task, final_len)
        
    } else {
        // --- STREAMING PATH (Original Logic) ---
        let mut upstream_request = Request::builder()
            .method(request.method())
            .uri(request.uri())
            .version(http::Version::HTTP_2);
            
        for (name, value) in request.headers() {
            let name_str = name.as_str();
            // REMOVED content-length here too
            if !name_str.starts_with(':') && name_str != "host" && name_str != "connection" && name_str != "content-length" {
                upstream_request = upstream_request.header(name, value);
            }
        }
        let upstream_request = upstream_request.body(())?;
        
        let request_has_body = !recv_body.is_end_stream();
        let (response_future, mut send_to_upstream) = upstream_sender.send_request(upstream_request, !request_has_body)?;
        
        // Spawn background task
        let task = if request_has_body {
            let conn_id = conn_id;
            let stream_id = stream_id;
            let is_interesting = is_interesting;
            
            Some(tokio::spawn(async move {
                let mut total_bytes = 0usize;
                loop {
                    match recv_body.data().await {
                        Some(Ok(chunk)) => {
                            let len = chunk.len();
                            total_bytes += len;
                            let _ = recv_body.flow_control().release_capacity(len);
                            if is_interesting && len > 0 {
                                debug!("[{}/{}] 📤 Client chunk: {} bytes", conn_id, stream_id, len);
                            }
                            // For streaming request body, use chunked sender to be safe
                            if let Err(e) = send_chunked_request(&mut send_to_upstream, chunk, false) {
                                warn!("[{}/{}] Failed to forward: {}", conn_id, stream_id, e);
                                break;
                            }
                        }
                        Some(Err(e)) => {
                            warn!("[{}/{}] Error reading: {}", conn_id, stream_id, e);
                            break;
                        }
                        None => {
                            debug!("[{}/{}] Client stream ended", conn_id, stream_id);
                            let _ = send_chunked_request(&mut send_to_upstream, Bytes::new(), true);
                            break;
                        }
                    }
                }
                total_bytes
            }))
        } else {
            if !request_has_body {
                debug!("[{}/{}] Request has no body", conn_id, stream_id);
            }
            None
        };
        
        (response_future, task, 0)
    };
    
    // Wait for response headers from upstream
    let response = response_future.await?;
    let (parts, mut upstream_recv_body) = response.into_parts();
    
    // Get response status and headers
    let status = parts.status;
    let headers = parts.headers;
    
    if is_interesting {
        info!("[{}/{}] 📥 Response status: {}", conn_id, stream_id, status);
    }
    
    // Build response to send to client IMMEDIATELY
    let mut client_response = Response::builder().status(status);
    for (name, value) in &headers {
        let name_str = name.as_str();
        if !name_str.starts_with(':') && name_str != "content-length"  {
            client_response = client_response.header(name, value);
        }
    }
    
    let client_response = client_response.body(())?;
    // Send response headers - DON'T end stream (false = more data coming)
    debug!("[{}/{}] Sending response headers to client...", conn_id, stream_id);
    let mut send_to_client = match send_response.send_response(client_response, false) {
        Ok(s) => s,
        Err(e) => {
            error!("[{}/{}] Failed to send response headers: {}", conn_id, stream_id, e);
            return Err(e.into());
        }
    };
    debug!("[{}/{}] Response headers sent", conn_id, stream_id);
    
    // Stream response body from upstream to client in real-time
    let mut total_response_bytes = 0usize;
    let started = Instant::now();
    
    loop {
        match upstream_recv_body.data().await {
            Some(Ok(chunk)) => {
                let len = chunk.len();
                total_response_bytes += len;
                // Release flow control capacity immediately
                let _ = upstream_recv_body.flow_control().release_capacity(len);
                
                if is_interesting {
                    info!("[{}/{}] 📥 Chunk: {} bytes (total: {})", conn_id, stream_id, len, total_response_bytes);
                }
                
                // Forward to client immediately
                if let Err(e) = send_chunked_response(&mut send_to_client, chunk, false) {
                    warn!("[{}/{}] Failed to forward to client: {}", conn_id, stream_id, e);
                    break;
                }
            }
            Some(Err(e)) => {
                warn!("[{}/{}] Error reading from upstream: {}", conn_id, stream_id, e);
                break;
            }
            None => {
                // End of upstream data - signal end of stream to client
                debug!("[{}/{}] Upstream ended, sending end-of-stream to client", conn_id, stream_id);
                let _ = send_chunked_response(&mut send_to_client, Bytes::new(), true);
                break;
            }
        }
    }
    
    // Wait for client->upstream task to complete (if one exists)
    let request_bytes = if let Some(task) = upstream_task {
        task.await.unwrap_or(0)
    } else {
        injected_bytes
    };
    
    if is_interesting {
        let duration = started.elapsed();
        info!(
            "[{}/{}] ✅ Stream complete: {} bytes up, {} bytes down in {:?}",
            conn_id, stream_id,
            request_bytes,
            total_response_bytes,
            duration
        );
    }
    
    Ok(())
}

/// Save captured stream to disk
async fn save_captured_stream(stream: &CapturedStream, dir: &PathBuf, conn_id: u64) {
    let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S_%3f");
    let filename = format!(
        "{}_{}_{}_{}.bin",
        timestamp,
        stream.service.replace('.', "_"),
        stream.method,
        conn_id
    );
    
    let expanded = shellexpand::tilde(&dir.to_string_lossy()).to_string();
    let dir = PathBuf::from(expanded);
    
    if let Err(e) = tokio::fs::create_dir_all(&dir).await {
        warn!("Failed to create capture dir: {}", e);
        return;
    }
    
    // Save request
    let req_path = dir.join(format!("req_{}", filename));
    if let Err(e) = tokio::fs::write(&req_path, &stream.request_data).await {
        warn!("Failed to save request: {}", e);
    }
    
    // Save response
    let resp_path = dir.join(format!("resp_{}", filename));
    if let Err(e) = tokio::fs::write(&resp_path, &stream.response_data).await {
        warn!("Failed to save response: {}", e);
    }
    
    // Save metadata
    let meta = serde_json::json!({
        "service": stream.service,
        "method": stream.method,
        "request_headers": stream.request_headers,
        "response_headers": stream.response_headers,
        "request_size": stream.request_data.len(),
        "response_size": stream.response_data.len(),
        "duration_ms": stream.started.elapsed().as_millis(),
    });
    
    let meta_path = dir.join(format!("meta_{}.json", filename.replace(".bin", "")));
    if let Err(e) = tokio::fs::write(&meta_path, serde_json::to_string_pretty(&meta).unwrap()).await {
        warn!("Failed to save metadata: {}", e);
    }
}

/// Handle an incoming connection with full HTTP/2 parsing
async fn handle_connection(
    stream: TcpStream,
    state: Arc<ProxyState>,
) -> Result<()> {
    let conn_id = state.next_conn_id();
    let peer_addr = stream.peer_addr()?;
    
    // Determine the domain for certificate generation
    let domain = "api2.cursor.sh".to_string();

    // Resolve domain to IP for upstream connection
    let upstream_addr = {
        use std::net::ToSocketAddrs;
        format!("{}:443", domain)
            .to_socket_addrs()
            .with_context(|| format!("Failed to resolve {}", domain))?
            .next()
            .ok_or_else(|| anyhow::anyhow!("No addresses for {}", domain))?
    };

    // Get original destination with loop detection
    let original_dst = match get_original_dst(&stream) {
        Ok(dst) => {
            // Check for loop: if destination is our proxy, use DNS instead
            let is_loop = dst.ip().is_loopback() 
                || dst.port() == 8443
                || (dst.ip() == std::net::IpAddr::V4(std::net::Ipv4Addr::new(10, 200, 1, 1)));
            
            if is_loop {
                warn!("[{}] Loop detected (dst={}), using DNS: {}", conn_id, dst, upstream_addr);
                upstream_addr
            } else {
                dst
            }
        }
        Err(e) => {
            warn!("[{}] Using DNS fallback ({}): {}", conn_id, e, upstream_addr);
            upstream_addr
        }
    };
    
    info!(
        "[{}] New connection from {} -> {}",
        conn_id, peer_addr, original_dst
    );
    
    // Generate dynamic certificate for this domain
    let (certs, key) = state.generate_cert_for_domain(&domain)
        .with_context(|| format!("Failed to generate cert for {}", domain))?;
    
    debug!("[{}] Generated certificate for {}", conn_id, domain);
    
    // Create TLS config with the dynamic cert
    let mut server_config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;
    
    // IMPORTANT: Advertise HTTP/2 via ALPN
    server_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    
    let tls_acceptor = TlsAcceptor::from(Arc::new(server_config));
    
    // Accept TLS from client
    let tls_stream = match tls_acceptor.accept(stream).await {
        Ok(s) => s,
        Err(e) => {
            warn!("[{}] TLS handshake failed: {}", conn_id, e);
            return Ok(());
        }
    };
    
    // Check what ALPN protocol was negotiated
    let negotiated_alpn = tls_stream.get_ref().1.alpn_protocol();
    let is_h2 = match negotiated_alpn {
        Some(proto) => {
            let proto_str = String::from_utf8_lossy(proto);
            info!("[{}] Client TLS complete, ALPN: {}", conn_id, proto_str);
            proto == b"h2"
        }
        None => {
            info!("[{}] Client TLS complete, NO ALPN - detecting protocol...", conn_id);
            false  // Reject non-ALPN connections to force reconnect
        }
    };
    
    if !is_h2 {
        info!("[{}] Client using HTTP/1.1, not supported - closing", conn_id);
        return Ok(());
    }
    
    // Connect to upstream with TLS
    let upstream_tcp = TcpStream::connect(original_dst).await
        .with_context(|| format!("Failed to connect to upstream {}", original_dst))?;
    
    // Disable Nagle algorithm for low-latency streaming
    upstream_tcp.set_nodelay(true)?;
    
    // Set SO_MARK on the upstream socket to bypass iptables redirect
    #[cfg(target_os = "linux")]
    {
        use std::os::unix::io::AsRawFd;
        const SO_MARK: libc::c_int = 36;
        const PROXY_MARK: u32 = 0x1337;
        let fd = upstream_tcp.as_raw_fd();
        let mark = PROXY_MARK;
        unsafe {
            let ret = libc::setsockopt(
                fd,
                libc::SOL_SOCKET,
                SO_MARK,
                &mark as *const _ as *const libc::c_void,
                std::mem::size_of::<u32>() as libc::socklen_t,
            );
            if ret != 0 {
                warn!("[{}] Failed to set SO_MARK: {}", conn_id, std::io::Error::last_os_error());
            } else {
                debug!("[{}] Set SO_MARK=0x{:x} on upstream socket", conn_id, PROXY_MARK);
            }
        }
    }
    
    let mut root_store = rustls::RootCertStore::empty();
    root_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    
    let mut client_config = ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth();
    
    // Request HTTP/2 from upstream via ALPN
    client_config.alpn_protocols = vec![b"h2".to_vec()];
    
    let connector = TlsConnector::from(Arc::new(client_config));
    let server_name = ServerName::try_from(domain.clone())?;
    
    let upstream_tls = connector.connect(server_name, upstream_tcp).await
        .with_context(|| "Upstream TLS handshake failed")?;
    
    // Check upstream ALPN
    let upstream_alpn = upstream_tls.get_ref().1.alpn_protocol();
    match upstream_alpn {
        Some(proto) => {
            info!("[{}] Upstream TLS complete, ALPN: {}", conn_id, String::from_utf8_lossy(proto));
        }
        None => {
            warn!("[{}] Upstream TLS complete but NO ALPN", conn_id);
        }
    }
    
    // HTTP/2 handshake with client - use builder for larger frame sizes
    // Configure to accept larger frames that Cursor might send
    let h2_result = server::Builder::new()
        .initial_window_size(65535)
        .initial_connection_window_size(65535 * 16)
        .max_frame_size(16384)  // 16KB - safe HTTP/2 default
        .max_concurrent_streams(128)
        .handshake(tls_stream).await;
    
    let mut h2_server = match h2_result {
        Ok(h2) => {
            info!("[{}] ✅ HTTP/2 handshake complete - can intercept gRPC!", conn_id);
            h2
        }
        Err(e) => {
            warn!("[{}] HTTP/2 handshake failed: {} - closing connection", conn_id, e);
            return Ok(());
        }
    };
    
    // Create h2 client connection to upstream with default settings
    // Don't customize - let h2 crate use safe defaults to avoid frame size issues
    let (h2_client, h2_conn) = client::Builder::new()
        .initial_window_size(65536)
        .initial_connection_window_size(1024 * 1024)
        .initial_max_send_buffer_size(1024 * 1024)
        .max_frame_size(16384)
        .handshake(upstream_tls).await
        .with_context(|| "HTTP/2 client handshake failed")?;
    
    debug!("[{}] HTTP/2 client handshake complete", conn_id);
    
    // Spawn task to drive the upstream connection
    let conn_id_clone = conn_id;
    tokio::spawn(async move {
        if let Err(e) = h2_conn.await {
            debug!("[{}] Upstream connection ended: {}", conn_id_clone, e);
        }
    });
    
    // Wait for the connection to be ready AND give time for SETTINGS exchange
    let h2_client = h2_client.ready().await?;
    
    // Wait for SETTINGS exchange to complete before forwarding requests
    // The upstream needs ~50ms to process our SETTINGS and send theirs
    // Without this, fast requests (like NetworkService/IsConnected) fail with FRAME_SIZE_ERROR
    tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;

    // Re-check connection is ready after settings exchange
    let h2_client = h2_client.ready().await?;
    
    // Process incoming streams from client
    loop {
        let accept_result = h2_server.accept().await;
        
        match accept_result {
            Some(Ok((request, send_response))) => {
                let (parts, recv_body) = request.into_parts();
                let request = Request::from_parts(parts, ());
                
                let stream_id = recv_body.stream_id().as_u32();
                let state = state.clone();
                let mut h2_client_clone = h2_client.clone();
                
                tokio::spawn(async move {
                    if let Err(e) = handle_stream(
                        conn_id,
                        stream_id,
                        request,
                        recv_body,
                        send_response,
                        &mut h2_client_clone,
                        state,
                    ).await {
                        warn!("[{}/{}] Stream error: {}", conn_id, stream_id, e);
                    }
                });
            }
            Some(Err(e)) => {
                warn!("[{}] Accept error: {}", conn_id, e);
                break;
            }
            None => {
                // Connection closed
                break;
            }
        }
    }
    
    info!("[{}] Connection closed", conn_id);
    Ok(())
}

/// Generate CA certificate
fn generate_ca(output_dir: &PathBuf) -> Result<()> {
    let expanded = shellexpand::tilde(&output_dir.to_string_lossy()).to_string();
    let output_dir = PathBuf::from(expanded);
    
    std::fs::create_dir_all(&output_dir)?;
    
    use rcgen::{
        BasicConstraints, CertificateParams, DistinguishedName, DnType,
        IsCa, KeyPair, KeyUsagePurpose,
    };
    
    let mut params = CertificateParams::default();
    
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, "Cursor Proxy CA");
    dn.push(DnType::OrganizationName, "Cursor Proxy");
    params.distinguished_name = dn;
    
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
        KeyUsagePurpose::DigitalSignature,
    ];
    
    params.not_before = time::OffsetDateTime::now_utc();
    params.not_after = time::OffsetDateTime::now_utc() + time::Duration::days(3650);
    
    let key_pair = KeyPair::generate()?;
    let cert = params.self_signed(&key_pair)?;
    
    let cert_path = output_dir.join("ca-cert.pem");
    std::fs::write(&cert_path, cert.pem())?;
    info!("CA certificate written to {:?}", cert_path);
    
    let key_path = output_dir.join("ca-key.pem");
    std::fs::write(&key_path, key_pair.serialize_pem())?;
    info!("CA private key written to {:?}", key_path);
    
    println!("\n✅ CA certificate generated!");
    println!("\nTo trust this CA:");
    println!("  1. Import {:?} into your browser/system", cert_path);
    println!("  2. Or set NODE_EXTRA_CA_CERTS={:?}", cert_path);
    
    Ok(())
}

/// Build injection config from CLI args
fn build_injection_config(
    inject: bool,
    inject_prompt: Option<String>,
    inject_config: Option<PathBuf>,
    inject_context: Vec<PathBuf>,
) -> InjectionConfig {
    // If a config file is specified, load it
    if let Some(config_path) = inject_config {
        let expanded = shellexpand::tilde(&config_path.to_string_lossy()).to_string();
        match injection::load_config(std::path::Path::new(&expanded)) {
            Ok(mut config) => {
                // CLI args can override config file
                if inject_prompt.is_some() {
                    config.system_prompt = inject_prompt;
                }
                if !inject_context.is_empty() {
                    config.context_files = inject_context;
                }
                // --inject flag forces enable
                if inject {
                    config.enabled = true;
                }
                return config;
            }
            Err(e) => {
                warn!("Failed to load injection config: {}", e);
            }
        }
    }
    
    // Build from CLI args
    InjectionConfig {
        enabled: inject || inject_prompt.is_some() || !inject_context.is_empty(),
        system_prompt: inject_prompt,
        context_files: inject_context,
        headers: Default::default(),
        spoof_version: None,
    }
}

/// Start the proxy server
async fn start_proxy(
    port: u16,
    ca_cert: PathBuf,
    ca_key: PathBuf,
    verbose: bool,
    capture_dir: Option<PathBuf>,
    inject: bool,
    inject_prompt: Option<String>,
    inject_config: Option<PathBuf>,
    inject_context: Vec<PathBuf>,
) -> Result<()> {
    let level = if verbose { Level::DEBUG } else { Level::INFO };
    let subscriber = FmtSubscriber::builder()
        .with_max_level(level)
        .with_target(false)
        .finish();
    tracing::subscriber::set_global_default(subscriber)?;
    
    info!("Cursor AI Transparent Proxy starting...");
    info!("Port: {}", port);
    
    // Load CA for dynamic cert generation
    let (ca_cert_obj, ca_key_obj) = load_ca(&ca_cert, &ca_key)?;
    info!("CA certificate loaded");
    
    // Build injection config
    let injection_config = build_injection_config(inject, inject_prompt, inject_config, inject_context);
    if injection_config.enabled {
        info!("🔧 Injection ENABLED");
        if let Some(ref prompt) = injection_config.system_prompt {
            let preview: String = prompt.chars().take(50).collect();
            info!("   System prompt: {}...", preview);
        }
        if !injection_config.context_files.is_empty() {
            info!("   Context files: {:?}", injection_config.context_files);
        }
    } else {
        info!("Injection: disabled");
    }
    
    let injection_engine = Arc::new(InjectionEngine::new(injection_config));
    
    let state = Arc::new(ProxyState {
        streams: DashMap::new(),
        conn_counter: std::sync::atomic::AtomicU64::new(0),
        ca_cert: ca_cert_obj,
        ca_key: ca_key_obj,
        capture_dir: capture_dir.clone(),
        injection: injection_engine,
    });
    
    if let Some(ref dir) = capture_dir {
        info!("Capture directory: {:?}", dir);
    }
    
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = TcpListener::bind(addr).await?;
    
    info!("🚀 Proxy listening on {}", addr);
    info!("");
    info!("Setup iptables with:");
    info!("  # Get Cursor API IPs");
    info!("  for ip in api2geo.cursor.sh.
api2direct.cursor.sh.
98.91.109.132
3.220.28.60
13.217.125.230
34.225.145.156
18.214.173.216
54.235.168.53
100.26.120.153
54.204.45.196; do");
    info!("    sudo iptables -t nat -A OUTPUT -p tcp -d  --dport 443 -j REDIRECT --to-port {}", port);
    info!("  done");
    info!("");
    info!("Or for testing without iptables, configure Cursor with:");
    info!("  NODE_EXTRA_CA_CERTS={}", shellexpand::tilde(&ca_cert.to_string_lossy()));
    info!("");
    
    loop {
        let (stream, _) = listener.accept().await?;
        let _ = stream.set_nodelay(true);
        let state = state.clone();
        
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, state).await {
                error!("Connection error: {}", e);
            }
        });
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");
    
    let cli = Cli::parse();
    
    match cli.command {
        Commands::Start {
            port,
            ca_cert,
            ca_key,
            verbose,
            capture_dir,
            inject,
            inject_prompt,
            inject_config,
            inject_context,
        } => {
            start_proxy(
                port,
                ca_cert,
                ca_key,
                verbose,
                capture_dir,
                inject,
                inject_prompt,
                inject_config,
                inject_context,
            ).await?;
        }
        Commands::GenerateCa { output } => {
            generate_ca(&output)?;
        }
        Commands::Status => {
            println!("Cursor Proxy Status");
            println!("==================");
            println!("Not implemented yet");
        }
    }
    
    Ok(())
}
