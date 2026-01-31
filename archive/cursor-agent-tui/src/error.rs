//! Error types for cursor-agent-tui

use thiserror::Error;

#[derive(Error, Debug)]
pub enum AgentError {
    #[error("Authentication error: {0}")]
    Auth(String),

    #[error("API error: {0}")]
    Api(String),

    #[error("API request failed with status {status}: {message}")]
    ApiRequest { status: u16, message: String },

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Tool execution error: {0}")]
    Tool(String),

    #[error("Context error: {0}")]
    Context(String),

    #[error("State error: {0}")]
    State(String),

    #[error("TUI error: {0}")]
    Tui(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    #[error("Protobuf encode error: {0}")]
    ProtoEncode(#[from] prost::EncodeError),

    #[error("Protobuf decode error: {0}")]
    ProtoDecode(#[from] prost::DecodeError),

    #[error("Token not found - please login to Cursor IDE first")]
    TokenNotFound,

    #[error("Token expired")]
    TokenExpired,
    
    #[error("Protobuf schema unknown for endpoint {endpoint}: {hint}")]
    ProtobufSchemaUnknown { endpoint: String, hint: String },
}

pub type Result<T> = std::result::Result<T, AgentError>;

