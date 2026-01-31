//! Error types for cursor-proxy

use thiserror::Error;

/// Proxy error type
#[derive(Debug, Error)]
pub enum ProxyError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("TLS error: {0}")]
    Tls(String),

    #[error("HTTP error: {0}")]
    Http(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Certificate error: {0}")]
    Certificate(String),

    #[error("DNS error: {0}")]
    Dns(String),

    #[error("IPTables error: {0}")]
    Iptables(String),

    #[error("Upstream connection error: {0}")]
    Upstream(String),

    #[error("Injection error: {0}")]
    Injection(String),
}

/// Result type for proxy operations
pub type ProxyResult<T> = Result<T, ProxyError>;
