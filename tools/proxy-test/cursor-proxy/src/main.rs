//! Cursor AI Transparent Proxy
//!
//! A transparent HTTP/2 proxy designed to intercept Cursor IDE's AI traffic
//! for context injection and custom modes.
//!
//! Architecture:
//! 1. Transparent proxy via iptables NAT redirect
//! 2. TLS termination with dynamic certificate generation
//! 3. HTTP/2 frame inspection using h2 crate
//! 4. gRPC stream capture and modification
//! 5. Context injection hooks

use anyhow::{Context, Result};
use bytes::{Bytes, BytesMut};
use clap::{Parser, Subcommand};
use dashmap::DashMap;
use h2::server::{self, SendResponse};
use h2::client;
use http::{Request, Response, StatusCode, Method};
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
    
    let _cert_pem = std::fs::read_to_string(&cert_expanded)
        .with_context(|| format!("Failed to read CA cert: {}", cert_expanded))?;
    let key_pem = std::fs::read_to_string(&key_expanded)
        .with_context(|| format!("Failed to read CA key: {}", key_expanded))?;
    
    let key_pair = rcgen::KeyPair::from_pem(&key_pem)?;
    
    // Recreate CA certificate from key (we have the key, that's what matters for signing)
    use rcgen::{BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa, KeyUsagePurpose};
    
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

/// Handle a single HTTP/2 stream (request/response pair)
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
    
    if is_interesting {
        info!(
            "[{}/{}] 🎯 {} {}/{}",
            conn_id, stream_id,
            request.method(),
            service,
            method
        );
    } else {
        debug!(
            "[{}/{}] {} {}/{}",
            conn_id, stream_id,
            request.method(),
            service,
            method
        );
    }
    
    // Create captured stream for interesting requests
    let mut captured = if is_interesting {
        let mut cap = CapturedStream::new(stream_id);
        cap.service = service.clone();
        cap.method = method.clone();
        
        // Capture headers
        for (name, value) in request.headers() {
            cap.request_headers.push((
                name.to_string(),
                value.to_str().unwrap_or("<binary>").to_string(),
            ));
        }
        Some(cap)
    } else {
        None
    };
    
    // Read request body
    let mut request_body = BytesMut::new();
    while let Some(chunk_result) = recv_body.data().await {
        let chunk: Bytes = chunk_result?;
        request_body.extend_from_slice(&chunk);
        let _ = recv_body.flow_control().release_capacity(chunk.len());
    }
    
    if let Some(ref mut cap) = captured {
        cap.request_data = request_body.clone();
        
        if is_chat_service {
            info!(
                "[{}/{}] 📤 Request body: {} bytes",
                conn_id, stream_id, request_body.len()
            );
        }
    }
    
    // Forward request to upstream
    let upstream_request = Request::builder()
        .method(request.method())
        .uri(request.uri())
        .version(http::Version::HTTP_2);
    
    // Copy headers
    let mut upstream_request = upstream_request;
    for (name, value) in request.headers() {
        // Skip pseudo-headers and connection-specific headers
        let name_str = name.as_str();
        if !name_str.starts_with(':') && name_str != "host" && name_str != "connection" {
            upstream_request = upstream_request.header(name, value);
        }
    }
    
    let upstream_request = upstream_request.body(())?;
    
    // Send request to upstream
    let (response_future, mut send_stream_to_upstream) = upstream_sender
        .send_request(upstream_request, false)?;
    
    // Send request body to upstream
    if !request_body.is_empty() {
        send_stream_to_upstream.send_data(request_body.clone().freeze(), false)?;
    }
    send_stream_to_upstream.send_data(Bytes::new(), true)?;
    
    // Wait for response
    let response = response_future.await?;
    let (parts, mut upstream_recv_body) = response.into_parts();
    
    // Send request body
    // Note: For h2, we need to send body separately, but our current setup
    // uses end_of_stream=false in send_request, so we need to handle this
    
    // Get response status and headers
    let status = parts.status;
    let headers = parts.headers;
    
    if let Some(ref mut cap) = captured {
        for (name, value) in &headers {
            cap.response_headers.push((
                name.to_string(),
                value.to_str().unwrap_or("<binary>").to_string(),
            ));
        }
    }
    
    // Build response to send to client
    let mut client_response = Response::builder().status(status);
    for (name, value) in &headers {
        let name_str = name.as_str();
        if !name_str.starts_with(':') {
            client_response = client_response.header(name, value);
        }
    }
    
    let client_response = client_response.body(())?;
    let mut send_stream = send_response.send_response(client_response, false)?;
    
    // Stream response body
    let mut response_body = BytesMut::new();
    while let Some(chunk_result) = upstream_recv_body.data().await {
        let chunk: Bytes = chunk_result?;
        response_body.extend_from_slice(&chunk);
        let _ = upstream_recv_body.flow_control().release_capacity(chunk.len());
        
        // Forward to client
        send_stream.send_data(chunk, false)?;
    }
    
    // End stream
    send_stream.send_data(Bytes::new(), true)?;
    
    if let Some(mut cap) = captured {
        cap.response_data = response_body;
        
        let duration = cap.started.elapsed();
        info!(
            "[{}/{}] 📥 Response: {} {} bytes in {:?}",
            conn_id, stream_id,
            status,
            cap.response_data.len(),
            duration
        );
        
        // Save if capture_dir is set
        if let Some(ref capture_dir) = state.capture_dir {
            save_captured_stream(&cap, capture_dir, conn_id).await;
        }
        
        // Store for later analysis
        state.streams.insert((conn_id, stream_id), cap);
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
    
    // Get original destination
    let original_dst = match get_original_dst(&stream) {
        Ok(dst) => dst,
        Err(e) => {
            // Fallback for testing - assume api2.cursor.sh
            warn!("[{}] Using fallback destination (not transparent mode): {}", conn_id, e);
            "52.41.57.32:443".parse()?  // api2.cursor.sh IP
        }
    };
    
    info!(
        "[{}] New connection from {} -> {}",
        conn_id, peer_addr, original_dst
    );
    
    // Determine the domain for certificate generation
    // For transparent proxy, we use api2.cursor.sh since that's the Cursor API
    // In the future, we could use SNI from the TLS handshake
    let domain = "api2.cursor.sh".to_string();
    
    // Generate dynamic certificate for this domain
    let (certs, key) = state.generate_cert_for_domain(&domain)
        .with_context(|| format!("Failed to generate cert for {}", domain))?;
    
    debug!("[{}] Generated certificate for {}", conn_id, domain);
    
    // Create TLS config with the dynamic cert
    let server_config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)?;
    
    let tls_acceptor = TlsAcceptor::from(Arc::new(server_config));
    
    // Accept TLS from client
    let tls_stream = match tls_acceptor.accept(stream).await {
        Ok(s) => s,
        Err(e) => {
            warn!("[{}] TLS handshake failed: {}", conn_id, e);
            return Ok(());
        }
    };
    
    debug!("[{}] Client TLS handshake complete", conn_id);
    
    // Connect to upstream with TLS
    let upstream_tcp = TcpStream::connect(original_dst).await
        .with_context(|| format!("Failed to connect to upstream {}", original_dst))?;
    
    let mut root_store = rustls::RootCertStore::empty();
    root_store.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    
    let client_config = ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth();
    
    let connector = TlsConnector::from(Arc::new(client_config));
    let server_name = ServerName::try_from(domain.clone())?;
    
    let upstream_tls = connector.connect(server_name, upstream_tcp).await
        .with_context(|| "Upstream TLS handshake failed")?;
    
    debug!("[{}] Upstream TLS handshake complete", conn_id);
    
    // Now we have two TLS streams - we need to handle HTTP/2 on both
    // Using h2 crate for proper HTTP/2 frame handling
    
    // Create h2 server connection from client
    let mut h2_server = server::handshake(tls_stream).await
        .with_context(|| "HTTP/2 server handshake failed")?;
    
    debug!("[{}] HTTP/2 server handshake complete", conn_id);
    
    // Create h2 client connection to upstream
    let (h2_client, h2_conn) = client::handshake(upstream_tls).await
        .with_context(|| "HTTP/2 client handshake failed")?;
    
    debug!("[{}] HTTP/2 client handshake complete", conn_id);
    
    // Spawn task to drive the upstream connection
    let conn_id_clone = conn_id;
    tokio::spawn(async move {
        if let Err(e) = h2_conn.await {
            debug!("[{}] Upstream connection ended: {}", conn_id_clone, e);
        }
    });
    
    let mut h2_client = h2_client.ready().await?;
    
    // Process incoming streams from client
    while let Some(result) = h2_server.accept().await {
        let (request, send_response) = result?;
        
        // Split the request into parts and body
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

/// Start the proxy server
async fn start_proxy(
    port: u16,
    ca_cert: PathBuf,
    ca_key: PathBuf,
    verbose: bool,
    capture_dir: Option<PathBuf>,
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
    
    let state = Arc::new(ProxyState {
        streams: DashMap::new(),
        conn_counter: std::sync::atomic::AtomicU64::new(0),
        ca_cert: ca_cert_obj,
        ca_key: ca_key_obj,
        capture_dir: capture_dir.clone(),
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
    info!("  for ip in $(dig +short api2.cursor.sh); do");
    info!("    sudo iptables -t nat -A OUTPUT -p tcp -d $ip --dport 443 -j REDIRECT --to-port {}", port);
    info!("  done");
    info!("");
    info!("Or for testing without iptables, configure Cursor with:");
    info!("  NODE_EXTRA_CA_CERTS={}", shellexpand::tilde(&ca_cert.to_string_lossy()));
    info!("");
    
    loop {
        let (stream, _) = listener.accept().await?;
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
        } => {
            start_proxy(port, ca_cert, ca_key, verbose, capture_dir).await?;
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
