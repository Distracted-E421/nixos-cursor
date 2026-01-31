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
    Config(#[from] ConfigError),

    #[error("Certificate error: {0}")]
    Certificate(String),

    #[error("DNS error: {0}")]
    Dns(String),

    #[error("IPTables error: {0}")]
    Iptables(String),

    #[error("Upstream connection error: {0}")]
    Upstream(String),

    #[error("Upstream connection failed to {target}: {reason}")]
    UpstreamConnection { target: String, reason: String },

    #[error("Upstream TLS error for {target}: {reason}")]
    UpstreamTls { target: String, reason: String },

    #[error("Client TLS error: {0}")]
    ClientTls(String),

    #[error("Injection error: {0}")]
    Injection(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Invalid config: {field}={value}: {reason}")]
    InvalidConfig {
        field: String,
        value: String,
        reason: String,
    },

    #[error("Failed to bind to port {port}: {reason}")]
    BindFailed { port: u16, reason: String },

    #[error("Hyper error: {0}")]
    Hyper(String),
}

impl ProxyError {
    /// Check if this error is recoverable (connection should continue)
    pub fn is_recoverable(&self) -> bool {
        match self {
            ProxyError::UpstreamConnection { .. } => true,
            ProxyError::UpstreamTls { .. } => true,
            ProxyError::Upstream(_) => true,
            ProxyError::Hyper(_) => true,
            _ => false,
        }
    }

    /// Get a user-friendly error message
    pub fn display_for_user(&self) -> String {
        match self {
            ProxyError::Io(e) => format!("IO error: {}", e),
            ProxyError::Certificate(s) => format!("Certificate error: {}", s),
            ProxyError::UpstreamConnection { target, reason } => {
                format!("Could not connect to {}: {}", target, reason)
            }
            ProxyError::BindFailed { port, reason } => {
                format!("Could not bind to port {}: {}", port, reason)
            }
            ProxyError::Config(e) => format!("Configuration error: {}", e),
            _ => self.to_string(),
        }
    }
}

/// Configuration-specific errors
#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("Config not found: {0}")]
    NotFound(String),

    #[error("Parse error: {0}")]
    Parse(String),

    #[error("Write error: {0}")]
    Write(String),
}

/// Result type for proxy operations
pub type ProxyResult<T> = Result<T, ProxyError>;
