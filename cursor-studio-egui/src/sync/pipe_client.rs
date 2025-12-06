//! Named Pipe IPC Client for Elixir Sync Daemon
//!
//! Communicates with the Elixir sync daemon via named pipes.
//!
//! ## Protocol
//!
//! Commands are JSON messages sent to `/tmp/cursor-sync-cmd.pipe`:
//! ```json
//! {"cmd": "sync"}
//! {"cmd": "status"}
//! {"cmd": "stats"}
//! {"cmd": "stop"}
//! ```
//!
//! Responses come from `/tmp/cursor-sync-resp.pipe`:
//! ```json
//! {"ok": true, "data": {...}}
//! {"ok": false, "error": "message"}
//! ```

use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::Duration;
use serde::{Deserialize, Serialize};

/// Default pipe paths
const DEFAULT_CMD_PIPE: &str = "/tmp/cursor-sync-cmd.pipe";
const DEFAULT_RESP_PIPE: &str = "/tmp/cursor-sync-resp.pipe";

/// Command to send to the daemon
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "cmd", rename_all = "lowercase")]
pub enum DaemonCommand {
    /// Sync all databases
    Sync { workspace: Option<String> },
    /// Get daemon status
    Status,
    /// Get sync statistics
    Stats,
    /// Graceful shutdown
    Stop,
}

/// Response from the daemon
#[derive(Debug, Clone, Deserialize)]
pub struct DaemonResponse {
    pub ok: bool,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
    #[serde(default)]
    pub error: Option<String>,
}

/// Sync statistics from the daemon
#[derive(Debug, Clone, Deserialize, Default)]
pub struct SyncStats {
    pub total_syncs: u64,
    pub successful_syncs: u64,
    pub failed_syncs: u64,
    pub messages_synced: u64,
    pub conversations_synced: u64,
    #[serde(default)]
    pub last_sync: Option<String>,
    #[serde(default)]
    pub last_error: Option<String>,
    #[serde(default)]
    pub avg_duration_ms: f64,
}

/// Daemon status
#[derive(Debug, Clone, Deserialize, Default)]
pub struct DaemonStatus {
    pub syncing: bool,
    #[serde(default)]
    pub last_sync: Option<String>,
    pub workspaces_synced: usize,
    pub total_syncs: u64,
}

/// Events from the daemon (for async responses)
#[derive(Debug, Clone)]
pub enum DaemonEvent {
    /// Response received
    Response(DaemonResponse),
    /// Connection established
    Connected,
    /// Connection lost
    Disconnected,
    /// Error occurred
    Error(String),
}

/// Client errors
#[derive(Debug, Clone)]
pub enum ClientError {
    /// Pipe not found (daemon not running?)
    PipeNotFound(String),
    /// Failed to write command
    WriteError(String),
    /// Failed to read response
    ReadError(String),
    /// Invalid response JSON
    ParseError(String),
    /// Timeout waiting for response
    Timeout,
    /// Daemon returned an error
    DaemonError(String),
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::PipeNotFound(p) => write!(f, "Pipe not found: {} (is daemon running?)", p),
            ClientError::WriteError(e) => write!(f, "Failed to write command: {}", e),
            ClientError::ReadError(e) => write!(f, "Failed to read response: {}", e),
            ClientError::ParseError(e) => write!(f, "Failed to parse response: {}", e),
            ClientError::Timeout => write!(f, "Timeout waiting for response"),
            ClientError::DaemonError(e) => write!(f, "Daemon error: {}", e),
        }
    }
}

impl std::error::Error for ClientError {}

/// Sync daemon IPC client
pub struct PipeClient {
    cmd_pipe: PathBuf,
    resp_pipe: PathBuf,
    timeout: Duration,
}

impl Default for PipeClient {
    fn default() -> Self {
        Self::new()
    }
}

impl PipeClient {
    /// Create a new client with default pipe paths
    pub fn new() -> Self {
        Self {
            cmd_pipe: PathBuf::from(DEFAULT_CMD_PIPE),
            resp_pipe: PathBuf::from(DEFAULT_RESP_PIPE),
            timeout: Duration::from_secs(5),
        }
    }

    /// Create with custom pipe paths
    pub fn with_pipes(cmd_pipe: impl Into<PathBuf>, resp_pipe: impl Into<PathBuf>) -> Self {
        Self {
            cmd_pipe: cmd_pipe.into(),
            resp_pipe: resp_pipe.into(),
            timeout: Duration::from_secs(5),
        }
    }

    /// Set timeout for responses
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Check if the daemon is running (pipes exist)
    pub fn is_daemon_running(&self) -> bool {
        self.cmd_pipe.exists() && self.resp_pipe.exists()
    }

    /// Send a command and wait for response
    pub fn send_command(&self, command: DaemonCommand) -> Result<DaemonResponse, ClientError> {
        // Check if pipes exist
        if !self.cmd_pipe.exists() {
            return Err(ClientError::PipeNotFound(self.cmd_pipe.display().to_string()));
        }

        // Serialize command
        let json = serde_json::to_string(&command)
            .map_err(|e| ClientError::WriteError(e.to_string()))?;

        // Write to command pipe (this will block until daemon reads)
        let mut cmd_file = OpenOptions::new()
            .write(true)
            .open(&self.cmd_pipe)
            .map_err(|e| ClientError::WriteError(e.to_string()))?;

        writeln!(cmd_file, "{}", json)
            .map_err(|e| ClientError::WriteError(e.to_string()))?;

        cmd_file.flush()
            .map_err(|e| ClientError::WriteError(e.to_string()))?;

        drop(cmd_file); // Close the pipe to signal EOF

        // Read response (with timeout via thread)
        self.read_response()
    }

    /// Read response from the response pipe
    fn read_response(&self) -> Result<DaemonResponse, ClientError> {
        let resp_pipe = self.resp_pipe.clone();
        let (tx, rx) = channel();

        // Spawn thread to read (File::open on named pipe blocks)
        thread::spawn(move || {
            let result = File::open(&resp_pipe)
                .map_err(|e| ClientError::ReadError(e.to_string()))
                .and_then(|file| {
                    let reader = BufReader::new(file);
                    let mut lines = reader.lines();
                    
                    match lines.next() {
                        Some(Ok(line)) => {
                            serde_json::from_str(&line)
                                .map_err(|e| ClientError::ParseError(e.to_string()))
                        }
                        Some(Err(e)) => Err(ClientError::ReadError(e.to_string())),
                        None => Err(ClientError::ReadError("Empty response".to_string())),
                    }
                });
            
            let _ = tx.send(result);
        });

        // Wait with timeout
        rx.recv_timeout(self.timeout)
            .map_err(|_| ClientError::Timeout)?
    }

    // ============================================
    // Convenience Methods
    // ============================================

    /// Trigger a sync operation
    pub fn sync(&self, workspace: Option<String>) -> Result<DaemonResponse, ClientError> {
        self.send_command(DaemonCommand::Sync { workspace })
    }

    /// Sync all databases
    pub fn sync_all(&self) -> Result<DaemonResponse, ClientError> {
        self.sync(None)
    }

    /// Get daemon status
    pub fn status(&self) -> Result<DaemonStatus, ClientError> {
        let response = self.send_command(DaemonCommand::Status)?;
        
        if !response.ok {
            return Err(ClientError::DaemonError(
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        response.data
            .ok_or_else(|| ClientError::ParseError("No data in response".to_string()))
            .and_then(|data| {
                serde_json::from_value(data)
                    .map_err(|e| ClientError::ParseError(e.to_string()))
            })
    }

    /// Get sync statistics
    pub fn stats(&self) -> Result<SyncStats, ClientError> {
        let response = self.send_command(DaemonCommand::Stats)?;
        
        if !response.ok {
            return Err(ClientError::DaemonError(
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        response.data
            .ok_or_else(|| ClientError::ParseError("No data in response".to_string()))
            .and_then(|data| {
                serde_json::from_value(data)
                    .map_err(|e| ClientError::ParseError(e.to_string()))
            })
    }

    /// Request daemon shutdown
    pub fn stop(&self) -> Result<DaemonResponse, ClientError> {
        self.send_command(DaemonCommand::Stop)
    }
}

/// Async client that runs in a background thread
pub struct AsyncPipeClient {
    command_tx: Option<Sender<DaemonCommand>>,
}

impl AsyncPipeClient {
    /// Create a new async client
    pub fn new() -> Self {
        Self {
            command_tx: None,
        }
    }

    /// Start the background communication thread
    pub fn start(&mut self) -> Receiver<DaemonEvent> {
        let (event_tx, event_rx) = channel();
        let (command_tx, command_rx) = channel::<DaemonCommand>();

        let client = PipeClient::new();

        thread::spawn(move || {
            // Check if daemon is running
            if !client.is_daemon_running() {
                let _ = event_tx.send(DaemonEvent::Error(
                    "Daemon not running (pipes not found)".to_string()
                ));
                return;
            }

            let _ = event_tx.send(DaemonEvent::Connected);

            // Process commands
            while let Ok(command) = command_rx.recv() {
                match client.send_command(command) {
                    Ok(response) => {
                        let _ = event_tx.send(DaemonEvent::Response(response));
                    }
                    Err(e) => {
                        let _ = event_tx.send(DaemonEvent::Error(e.to_string()));
                    }
                }
            }

            let _ = event_tx.send(DaemonEvent::Disconnected);
        });

        self.command_tx = Some(command_tx);
        
        // Return the receiver - caller owns it
        event_rx
    }

    /// Send a command asynchronously
    pub fn send(&self, command: DaemonCommand) -> bool {
        if let Some(ref tx) = self.command_tx {
            tx.send(command).is_ok()
        } else {
            false
        }
    }

}

impl Default for AsyncPipeClient {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_serialization() {
        let cmd = DaemonCommand::Sync { workspace: None };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("\"cmd\":\"sync\""));

        let cmd = DaemonCommand::Status;
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("\"cmd\":\"status\""));
    }

    #[test]
    fn test_client_creation() {
        let client = PipeClient::new();
        assert_eq!(client.cmd_pipe, PathBuf::from(DEFAULT_CMD_PIPE));
        assert_eq!(client.resp_pipe, PathBuf::from(DEFAULT_RESP_PIPE));
    }
}
