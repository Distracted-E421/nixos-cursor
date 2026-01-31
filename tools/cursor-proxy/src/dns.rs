//! DNS utilities for cursor-proxy
//!
//! Handles DNS resolution and interception for proxy targets.

use crate::error::{ProxyError, ProxyResult};
use std::net::IpAddr;

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
