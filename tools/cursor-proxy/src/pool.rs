//! HTTP/2 Connection Pool for upstream connections
//!
//! Maintains persistent HTTP/2 connections to upstream servers,
//! allowing request multiplexing over a single connection.

use bytes::Bytes;
use dashmap::DashMap;
use http::{Request, Response};
use http_body_util::Full;
use hyper::body::Incoming;
use hyper_util::rt::TokioIo;
use rustls::pki_types::ServerName;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::net::TcpStream;
use tokio::sync::Mutex;
use tokio_rustls::rustls::ClientConfig;
use tokio_rustls::TlsConnector;
use tracing::{debug, info, warn};

use crate::dns::ExternalDnsResolver;
use crate::error::{ProxyError, ProxyResult};

/// Maximum number of entries in the pool before cleanup is forced
const MAX_POOL_ENTRIES: usize = 100;

/// How often to run cleanup (in requests)
const CLEANUP_INTERVAL: u64 = 50;

/// A pooled HTTP/2 connection
struct PooledConnection {
    sender: hyper::client::conn::http2::SendRequest<Full<Bytes>>,
    created_at: Instant,
    request_count: u64,
    last_used: Instant,
}

impl PooledConnection {
    fn is_healthy(&self) -> bool {
        // Connection is healthy if:
        // 1. It's less than 5 minutes old
        // 2. The sender is not closed
        // 3. It hasn't been idle for more than 2 minutes
        self.created_at.elapsed() < Duration::from_secs(300) 
            && !self.sender.is_closed()
            && self.last_used.elapsed() < Duration::from_secs(120)
    }
    
    fn touch(&mut self) {
        self.last_used = Instant::now();
    }
}

/// Connection pool for HTTP/2 upstream connections
pub struct Http2Pool {
    /// Active connections keyed by (domain, port)
    connections: DashMap<String, Arc<Mutex<Option<PooledConnection>>>>,
    /// DNS resolver
    dns: Arc<ExternalDnsResolver>,
    /// TLS connector (shared)
    tls_config: Arc<ClientConfig>,
    /// Request counter for periodic cleanup
    request_counter: AtomicU64,
    /// Last cleanup time
    last_cleanup: Mutex<Instant>,
}

impl Http2Pool {
    /// Create a new connection pool
    pub fn new(dns: Arc<ExternalDnsResolver>) -> ProxyResult<Self> {
        // Setup TLS config once
        let mut root_store = rustls::RootCertStore::empty();
        let native_certs = rustls_native_certs::load_native_certs();
        for cert in native_certs.certs {
            root_store.add(cert).ok();
        }
        
        let mut client_config = ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();
        
        // Enable HTTP/2 ALPN
        client_config.alpn_protocols = vec![b"h2".to_vec()];
        
        Ok(Self {
            connections: DashMap::new(),
            dns,
            tls_config: Arc::new(client_config),
            request_counter: AtomicU64::new(0),
            last_cleanup: Mutex::new(Instant::now()),
        })
    }
    
    /// Clean up stale pool entries
    pub async fn cleanup(&self) {
        let mut guard = self.last_cleanup.lock().await;
        
        // Don't clean up more than once per 10 seconds
        if guard.elapsed() < Duration::from_secs(10) {
            return;
        }
        *guard = Instant::now();
        drop(guard);
        
        let mut to_remove = Vec::new();
        
        // Find entries to remove
        for entry in self.connections.iter() {
            let key = entry.key().clone();
            if let Ok(guard) = entry.value().try_lock() {
                match &*guard {
                    Some(conn) if !conn.is_healthy() => {
                        to_remove.push(key);
                    }
                    None => {
                        to_remove.push(key);
                    }
                    _ => {}
                }
            }
        }
        
        // Remove stale entries
        let removed = to_remove.len();
        for key in to_remove {
            self.connections.remove(&key);
        }
        
        if removed > 0 {
            debug!("Pool cleanup: removed {} stale entries, {} remaining", 
                   removed, self.connections.len());
        }
    }
    
    /// Force cleanup if pool is too large
    async fn maybe_force_cleanup(&self) {
        let count = self.request_counter.fetch_add(1, Ordering::Relaxed);
        
        // Periodic cleanup every N requests
        if count % CLEANUP_INTERVAL == 0 || self.connections.len() > MAX_POOL_ENTRIES {
            self.cleanup().await;
        }
    }
    
    /// Get or create a connection to the upstream server
    pub async fn get_connection(
        &self,
        domain: &str,
        port: u16,
    ) -> ProxyResult<hyper::client::conn::http2::SendRequest<Full<Bytes>>> {
        // Trigger cleanup if needed
        self.maybe_force_cleanup().await;
        
        let key = format!("{}:{}", domain, port);
        
        // Get or create the connection slot
        let conn_slot = self.connections
            .entry(key.clone())
            .or_insert_with(|| Arc::new(Mutex::new(None)))
            .clone();
        
        let mut guard = conn_slot.lock().await;
        
        // Check if we have a healthy existing connection
        if let Some(ref mut conn) = *guard {
            if conn.is_healthy() {
                debug!("Reusing pooled connection to {} (requests: {})", key, conn.request_count);
                conn.touch(); // Update last used time
                // Clone the sender (HTTP/2 senders can be cloned for multiplexing)
                return Ok(conn.sender.clone());
            } else {
                debug!("Pooled connection to {} is unhealthy, creating new", key);
            }
        }
        
        // Create new connection
        info!("Creating new pooled connection to {}", key);
        let conn = self.create_connection(domain, port).await?;
        
        let sender = conn.sender.clone();
        *guard = Some(conn);
        
        Ok(sender)
    }
    
    /// Create a new HTTP/2 connection
    async fn create_connection(
        &self,
        domain: &str,
        port: u16,
    ) -> ProxyResult<PooledConnection> {
        // Resolve DNS
        let ips = self.dns.resolve(domain).await?;
        if ips.is_empty() {
            return Err(ProxyError::Internal(format!("No IPs for {}", domain)));
        }
        
        // Try each IP until one works
        let mut last_error = None;
        for ip in &ips {
            let addr = SocketAddr::new(*ip, port);
            
            match self.try_connect(domain, addr).await {
                Ok(conn) => return Ok(conn),
                Err(e) => {
                    debug!("Failed to connect to {}: {}", addr, e);
                    last_error = Some(e);
                }
            }
        }
        
        Err(last_error.unwrap_or_else(|| {
            ProxyError::Internal(format!("All IPs failed for {}", domain))
        }))
    }
    
    /// Try to connect to a specific address
    async fn try_connect(
        &self,
        domain: &str,
        addr: SocketAddr,
    ) -> ProxyResult<PooledConnection> {
        // TCP connect with timeout
        let tcp = tokio::time::timeout(
            Duration::from_secs(10),
            TcpStream::connect(addr)
        ).await
            .map_err(|_| ProxyError::UpstreamConnection {
                target: addr.to_string(),
                reason: "TCP connection timeout".to_string(),
            })?
            .map_err(|e| ProxyError::UpstreamConnection {
                target: addr.to_string(),
                reason: e.to_string(),
            })?;
        
        // TLS handshake
        let connector = TlsConnector::from(Arc::clone(&self.tls_config));
        let server_name = ServerName::try_from(domain.to_string())
            .map_err(|e| ProxyError::UpstreamTls {
                target: domain.to_string(),
                reason: format!("Invalid server name: {:?}", e),
            })?;
        
        let tls = tokio::time::timeout(
            Duration::from_secs(10),
            connector.connect(server_name, tcp)
        ).await
            .map_err(|_| ProxyError::UpstreamTls {
                target: domain.to_string(),
                reason: "TLS handshake timeout".to_string(),
            })?
            .map_err(|e| ProxyError::UpstreamTls {
                target: domain.to_string(),
                reason: e.to_string(),
            })?;
        
        let io = TokioIo::new(tls);
        
        // HTTP/2 handshake
        let (sender, conn) = hyper::client::conn::http2::handshake(
            hyper_util::rt::TokioExecutor::new(),
            io
        ).await
            .map_err(|e| ProxyError::UpstreamConnection {
                target: domain.to_string(),
                reason: format!("HTTP/2 handshake failed: {}", e),
            })?;
        
        // Spawn connection driver
        let domain_clone = domain.to_string();
        tokio::spawn(async move {
            if let Err(e) = conn.await {
                debug!("Connection to {} closed: {}", domain_clone, e);
            }
        });
        
        Ok(PooledConnection {
            sender,
            created_at: Instant::now(),
            request_count: 0,
            last_used: Instant::now(),
        })
    }
    
    /// Send a request using a pooled connection
    pub async fn send_request(
        &self,
        domain: &str,
        port: u16,
        request: Request<Full<Bytes>>,
    ) -> ProxyResult<Response<Incoming>> {
        // Try with existing/new connection
        for attempt in 0..2 {
            let mut sender = self.get_connection(domain, port).await?;
            
            match sender.send_request(request.clone()).await {
                Ok(response) => {
                    // Update request count
                    let key = format!("{}:{}", domain, port);
                    if let Some(slot) = self.connections.get(&key) {
                        if let Ok(mut guard) = slot.try_lock() {
                            if let Some(ref mut conn) = *guard {
                                conn.request_count += 1;
                            }
                        }
                    }
                    return Ok(response);
                }
                Err(e) => {
                    if attempt == 0 {
                        warn!("Request failed, clearing pool and retrying: {}", e);
                        // Clear the bad connection
                        let key = format!("{}:{}", domain, port);
                        if let Some(slot) = self.connections.get(&key) {
                            if let Ok(mut guard) = slot.try_lock() {
                                *guard = None;
                            }
                        }
                    } else {
                        return Err(ProxyError::UpstreamConnection {
                            target: domain.to_string(),
                            reason: e.to_string(),
                        });
                    }
                }
            }
        }
        
        Err(ProxyError::Internal("Request failed after retries".to_string()))
    }
    
    /// Get pool statistics
    pub fn stats(&self) -> (usize, usize) {
        let total = self.connections.len();
        let healthy = self.connections.iter()
            .filter(|entry| {
                if let Ok(guard) = entry.value().try_lock() {
                    guard.as_ref().map(|c| c.is_healthy()).unwrap_or(false)
                } else {
                    false
                }
            })
            .count();
        (total, healthy)
    }
    
    /// Clear all connections (for shutdown/disable)
    pub fn clear(&self) {
        self.connections.clear();
        info!("Connection pool cleared");
    }
    
    /// Get the number of entries in the pool
    pub fn len(&self) -> usize {
        self.connections.len()
    }
    
    /// Check if pool is empty
    pub fn is_empty(&self) -> bool {
        self.connections.is_empty()
    }
}

