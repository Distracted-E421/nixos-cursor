//! IPC module for cursor-proxy
//!
//! Enables external clients to connect to the proxy and receive events.
//! Uses Unix domain sockets for efficient local communication.

use crate::events::{EventBroadcaster, EventReceiver, ProxyEvent};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

/// Default socket path for IPC
pub const DEFAULT_SOCKET_PATH: &str = "/tmp/cursor-proxy.sock";

/// Commands that can be sent to the proxy via IPC
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcCommand {
    /// Request current status
    GetStatus,
    /// Enable/disable capture
    SetCapture { enabled: bool },
    /// Enable/disable injection
    SetInjection { enabled: bool },
    /// Update injection configuration
    UpdateInjectionConfig { config: String },
    /// Reload configuration from file
    ReloadConfig,
    /// Request proxy shutdown
    Shutdown,
    /// Subscribe to events
    Subscribe,
    /// Unsubscribe from events
    Unsubscribe,
}

/// Response from proxy to IPC commands
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcResponse {
    /// Operation succeeded
    Ok,
    /// Operation succeeded with data
    OkWithData { data: String },
    /// Operation failed
    Error { message: String },
    /// Proxy status
    Status {
        running: bool,
        port: u16,
        capture_enabled: bool,
        injection_enabled: bool,
        active_connections: usize,
        total_requests: u64,
    },
    /// Event notification (when subscribed)
    Event(ProxyEvent),
}

/// IPC server for handling external connections
pub struct IpcServer {
    socket_path: PathBuf,
    broadcaster: EventBroadcaster,
}

impl IpcServer {
    /// Create a new IPC server
    pub fn new(socket_path: Option<PathBuf>, broadcaster: EventBroadcaster) -> Self {
        let socket_path = socket_path.unwrap_or_else(|| PathBuf::from(DEFAULT_SOCKET_PATH));
        Self {
            socket_path,
            broadcaster,
        }
    }

    /// Start the IPC server
    pub async fn start(&self) -> Result<(), std::io::Error> {
        // Remove existing socket file if present
        if self.socket_path.exists() {
            std::fs::remove_file(&self.socket_path)?;
        }

        let listener = UnixListener::bind(&self.socket_path)?;
        info!("IPC server listening on {:?}", self.socket_path);

        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let broadcaster = self.broadcaster.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_client(stream, broadcaster).await {
                            error!("Client error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    error!("Accept error: {}", e);
                }
            }
        }
    }

    /// Get the socket path
    pub fn socket_path(&self) -> &PathBuf {
        &self.socket_path
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        // Clean up socket file
        if self.socket_path.exists() {
            let _ = std::fs::remove_file(&self.socket_path);
        }
    }
}

/// Handle a connected client
async fn handle_client(
    stream: UnixStream,
    broadcaster: EventBroadcaster,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    debug!("New IPC client connected");

    loop {
        line.clear();
        let bytes_read = reader.read_line(&mut line).await?;
        
        if bytes_read == 0 {
            debug!("IPC client disconnected");
            break;
        }

        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        match serde_json::from_str::<IpcCommand>(line) {
            Ok(command) => {
                let response = handle_command(command, &broadcaster).await;
                let response_json = serde_json::to_string(&response)?;
                writer.write_all(response_json.as_bytes()).await?;
                writer.write_all(b"\n").await?;
                writer.flush().await?;

                // If subscribed, start streaming events
                if matches!(response, IpcResponse::Ok) {
                    // TODO: Start event streaming
                }
            }
            Err(e) => {
                let response = IpcResponse::Error {
                    message: format!("Invalid command: {}", e),
                };
                let response_json = serde_json::to_string(&response)?;
                writer.write_all(response_json.as_bytes()).await?;
                writer.write_all(b"\n").await?;
                writer.flush().await?;
            }
        }
    }

    Ok(())
}

/// Handle an IPC command
async fn handle_command(command: IpcCommand, broadcaster: &EventBroadcaster) -> IpcResponse {
    match command {
        IpcCommand::GetStatus => {
            // TODO: Get actual status from proxy
            IpcResponse::Status {
                running: true,
                port: 8443,
                capture_enabled: false,
                injection_enabled: false,
                active_connections: 0,
                total_requests: 0,
            }
        }
        IpcCommand::SetCapture { enabled } => {
            info!("Capture {}", if enabled { "enabled" } else { "disabled" });
            IpcResponse::Ok
        }
        IpcCommand::SetInjection { enabled } => {
            info!("Injection {}", if enabled { "enabled" } else { "disabled" });
            IpcResponse::Ok
        }
        IpcCommand::UpdateInjectionConfig { config } => {
            info!("Updating injection config");
            debug!("New config: {}", config);
            IpcResponse::Ok
        }
        IpcCommand::ReloadConfig => {
            info!("Reloading configuration");
            IpcResponse::Ok
        }
        IpcCommand::Shutdown => {
            info!("Shutdown requested via IPC");
            IpcResponse::Ok
        }
        IpcCommand::Subscribe => {
            info!("Client subscribed to events");
            IpcResponse::Ok
        }
        IpcCommand::Unsubscribe => {
            info!("Client unsubscribed from events");
            IpcResponse::Ok
        }
    }
}

/// IPC client for connecting to a running proxy
pub struct IpcClient {
    socket_path: PathBuf,
}

impl IpcClient {
    /// Create a new IPC client
    pub fn new() -> Self {
        Self {
            socket_path: PathBuf::from(DEFAULT_SOCKET_PATH),
        }
    }

    /// Create with custom socket path
    pub fn with_socket_path(socket_path: PathBuf) -> Self {
        Self { socket_path }
    }

    /// Connect to the proxy
    pub async fn connect(&self) -> Result<IpcConnection, std::io::Error> {
        let stream = UnixStream::connect(&self.socket_path).await?;
        Ok(IpcConnection { stream })
    }
}

impl Default for IpcClient {
    fn default() -> Self {
        Self::new()
    }
}

/// Active connection to the proxy
pub struct IpcConnection {
    stream: UnixStream,
}

impl IpcConnection {
    /// Send a command and receive a response
    pub async fn send_command(
        &mut self,
        command: IpcCommand,
    ) -> Result<IpcResponse, Box<dyn std::error::Error + Send + Sync>> {
        let command_json = serde_json::to_string(&command)?;
        self.stream.write_all(command_json.as_bytes()).await?;
        self.stream.write_all(b"\n").await?;
        self.stream.flush().await?;

        let mut reader = BufReader::new(&mut self.stream);
        let mut line = String::new();
        reader.read_line(&mut line).await?;

        let response: IpcResponse = serde_json::from_str(line.trim())?;
        Ok(response)
    }

    /// Subscribe to events and return an event stream
    pub async fn subscribe(
        mut self,
    ) -> Result<IpcEventStream, Box<dyn std::error::Error + Send + Sync>> {
        self.send_command(IpcCommand::Subscribe).await?;
        Ok(IpcEventStream { connection: self })
    }
}

/// Stream of proxy events
pub struct IpcEventStream {
    connection: IpcConnection,
}

impl IpcEventStream {
    /// Receive the next event
    pub async fn next(&mut self) -> Option<ProxyEvent> {
        let mut reader = BufReader::new(&mut self.connection.stream);
        let mut line = String::new();

        match reader.read_line(&mut line).await {
            Ok(0) => None, // Connection closed
            Ok(_) => {
                match serde_json::from_str::<IpcResponse>(line.trim()) {
                    Ok(IpcResponse::Event(event)) => Some(event),
                    _ => None,
                }
            }
            Err(_) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_serialization() {
        let cmd = IpcCommand::GetStatus;
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("GetStatus"));
    }

    #[test]
    fn test_response_serialization() {
        let resp = IpcResponse::Status {
            running: true,
            port: 8443,
            capture_enabled: true,
            injection_enabled: false,
            active_connections: 5,
            total_requests: 100,
        };
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("running"));
    }
}
