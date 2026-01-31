//! DNS utilities for cursor-proxy
//!
//! Handles DNS resolution and interception for proxy targets.

use crate::error::{ProxyError, ProxyResult};
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

/// Resolve a hostname to an IP address
pub async fn resolve_host(hostname: &str) -> ProxyResult<IpAddr> {
    use tokio::net::lookup_host;

    let addrs: Vec<_> = lookup_host(format!("{}:443", hostname))
        .await
        .map_err(|e| ProxyError::Dns(e.to_string()))?
        .collect();

    addrs
        .first()
        .map(|a| a.ip())
        .ok_or_else(|| ProxyError::Dns(format!("No address found for {}", hostname)))
}

/// Known Cursor API hosts
pub const CURSOR_HOSTS: &[&str] = &[
    "api2.cursor.sh",
    "cursor.sh",
    "api.cursor.sh",
    "telemetry.cursor.sh",
];

/// Check if a host is a Cursor API host
pub fn is_cursor_host(host: &str) -> bool {
    CURSOR_HOSTS.iter().any(|h| host.contains(h))
}

/// External DNS resolver with caching
pub struct ExternalDnsResolver {
    /// DNS cache
    cache: Arc<RwLock<HashMap<String, (Vec<SocketAddr>, std::time::Instant)>>>,
    /// Cache TTL
    ttl: std::time::Duration,
}

impl ExternalDnsResolver {
    /// Create a new DNS resolver
    pub async fn new() -> ProxyResult<Self> {
        Ok(Self {
            cache: Arc::new(RwLock::new(HashMap::new())),
            ttl: std::time::Duration::from_secs(300), // 5 minute cache
        })
    }

    /// Resolve a hostname to socket addresses
    pub async fn resolve(&self, host: &str, port: u16) -> ProxyResult<Vec<SocketAddr>> {
        // Check cache first
        {
            let cache = self.cache.read().await;
            if let Some((addrs, cached_at)) = cache.get(host) {
                if cached_at.elapsed() < self.ttl {
                    return Ok(addrs.clone());
                }
            }
        }

        // Resolve using system DNS
        let lookup = format!("{}:{}", host, port);
        let addrs: Vec<SocketAddr> = tokio::net::lookup_host(&lookup)
            .await
            .map_err(|e| ProxyError::Dns(e.to_string()))?
            .collect();

        if addrs.is_empty() {
            return Err(ProxyError::Dns(format!("No addresses found for {}", host)));
        }

        // Update cache
        {
            let mut cache = self.cache.write().await;
            cache.insert(host.to_string(), (addrs.clone(), std::time::Instant::now()));
        }

        Ok(addrs)
    }

    /// Clear the cache
    pub async fn clear_cache(&self) {
        let mut cache = self.cache.write().await;
        cache.clear();
    }
}
