//! Main Sync Daemon
//!
//! Orchestrates file watching, database reading, and syncing.
//! Designed to run in a background thread.

use super::config::SyncConfig;
use super::models::SyncState;
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use std::time::{Duration, Instant};
use parking_lot::RwLock;

/// Sync daemon events
#[derive(Debug, Clone)]
pub enum SyncEvent {
    /// Daemon started
    Started,
    /// File change detected
    FileChanged { path: String },
    /// Sync started
    SyncStarted { workspace: Option<String> },
    /// Sync completed
    SyncCompleted { 
        conversations: usize, 
        messages: usize,
        duration_ms: u64,
    },
    /// Sync failed
    SyncFailed { error: String },
    /// Daemon stopped
    Stopped,
}

/// Statistics about sync operations
#[derive(Debug, Clone, Default)]
pub struct SyncStats {
    /// Total syncs performed
    pub total_syncs: u64,
    /// Successful syncs
    pub successful_syncs: u64,
    /// Failed syncs
    pub failed_syncs: u64,
    /// Total conversations synced
    pub conversations_synced: u64,
    /// Total messages synced
    pub messages_synced: u64,
    /// Last sync time
    pub last_sync: Option<Instant>,
    /// Last error
    pub last_error: Option<String>,
    /// Average sync duration in ms
    pub avg_sync_duration_ms: f64,
}

/// The main sync daemon
pub struct SyncDaemon {
    /// Configuration
    config: SyncConfig,
    
    /// Running flag
    running: Arc<AtomicBool>,
    
    /// Current sync state
    state: Arc<RwLock<SyncState>>,
    
    /// Statistics
    stats: Arc<RwLock<SyncStats>>,
    
    /// Event callback
    event_callback: Option<Box<dyn Fn(SyncEvent) + Send + Sync>>,
}

impl SyncDaemon {
    /// Create a new sync daemon with default config
    pub fn new() -> Self {
        Self::with_config(SyncConfig::default())
    }
    
    /// Create with custom config
    pub fn with_config(config: SyncConfig) -> Self {
        Self {
            config,
            running: Arc::new(AtomicBool::new(false)),
            state: Arc::new(RwLock::new(SyncState::default())),
            stats: Arc::new(RwLock::new(SyncStats::default())),
            event_callback: None,
        }
    }
    
    /// Set event callback
    pub fn on_event<F>(&mut self, callback: F) 
    where 
        F: Fn(SyncEvent) + Send + Sync + 'static 
    {
        self.event_callback = Some(Box::new(callback));
    }
    
    /// Check if daemon is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }
    
    /// Get current stats
    pub fn stats(&self) -> SyncStats {
        self.stats.read().clone()
    }
    
    /// Get current state
    pub fn state(&self) -> SyncState {
        self.state.read().clone()
    }
    
    /// Start the sync daemon
    pub fn start(&self) -> Result<(), SyncError> {
        if self.running.load(Ordering::Relaxed) {
            return Err(SyncError::AlreadyRunning);
        }
        
        if !self.config.enabled {
            return Err(SyncError::Disabled);
        }
        
        self.running.store(true, Ordering::Relaxed);
        self.emit_event(SyncEvent::Started);
        
        // Sync on start if configured
        if self.config.sync_on_start {
            self.sync_all()?;
        }
        
        Ok(())
    }
    
    /// Stop the sync daemon
    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
        self.emit_event(SyncEvent::Stopped);
    }
    
    /// Perform a full sync of all databases
    pub fn sync_all(&self) -> Result<SyncResult, SyncError> {
        let start = Instant::now();
        self.emit_event(SyncEvent::SyncStarted { workspace: None });
        
        let mut total_conversations = 0;
        let mut total_messages = 0;
        
        // Sync global database
        match self.sync_global_database() {
            Ok((convs, msgs)) => {
                total_conversations += convs;
                total_messages += msgs;
            }
            Err(e) => {
                self.record_error(&e);
                self.emit_event(SyncEvent::SyncFailed { error: e.to_string() });
                return Err(e);
            }
        }
        
        // Sync workspace databases
        match self.sync_workspace_databases() {
            Ok((convs, msgs)) => {
                total_conversations += convs;
                total_messages += msgs;
            }
            Err(e) => {
                self.record_error(&e);
                // Don't fail completely for workspace errors
            }
        }
        
        let duration = start.elapsed();
        let duration_ms = duration.as_millis() as u64;
        
        // Update stats
        {
            let mut stats = self.stats.write();
            stats.total_syncs += 1;
            stats.successful_syncs += 1;
            stats.conversations_synced += total_conversations as u64;
            stats.messages_synced += total_messages as u64;
            stats.last_sync = Some(Instant::now());
            
            // Update rolling average
            let n = stats.total_syncs as f64;
            stats.avg_sync_duration_ms = 
                (stats.avg_sync_duration_ms * (n - 1.0) + duration_ms as f64) / n;
        }
        
        // Update state
        {
            let mut state = self.state.write();
            state.last_sync = Some(chrono::Utc::now().timestamp_millis());
            state.conversations_synced = total_conversations;
            state.messages_synced = total_messages;
        }
        
        self.emit_event(SyncEvent::SyncCompleted { 
            conversations: total_conversations, 
            messages: total_messages,
            duration_ms,
        });
        
        Ok(SyncResult {
            conversations_synced: total_conversations,
            messages_synced: total_messages,
            duration,
        })
    }
    
    /// Sync the global database
    fn sync_global_database(&self) -> Result<(usize, usize), SyncError> {
        let db_path = &self.config.cursor_paths.global_storage;
        
        if !db_path.exists() {
            return Err(SyncError::DatabaseNotFound(db_path.display().to_string()));
        }
        
        // TODO: Implement actual sync logic using CursorDatabaseReader
        // For now, return placeholder values
        Ok((0, 0))
    }
    
    /// Sync all workspace databases
    fn sync_workspace_databases(&self) -> Result<(usize, usize), SyncError> {
        let ws_path = &self.config.cursor_paths.workspace_storage;
        
        if !ws_path.exists() {
            return Ok((0, 0)); // Not an error if no workspaces
        }
        
        let total_convs = 0;
        let total_msgs = 0;
        
        // Iterate workspace directories
        if let Ok(entries) = std::fs::read_dir(ws_path) {
            for entry in entries.flatten() {
                let db_path = entry.path().join("state.vscdb");
                if db_path.exists() {
                    // TODO: Sync this workspace
                    // For now, just count it
                }
            }
        }
        
        Ok((total_convs, total_msgs))
    }
    
    /// Record an error
    fn record_error(&self, error: &SyncError) {
        let mut stats = self.stats.write();
        stats.failed_syncs += 1;
        stats.last_error = Some(error.to_string());
        
        let mut state = self.state.write();
        state.last_errors.push(error.to_string());
        if state.last_errors.len() > 10 {
            state.last_errors.remove(0);
        }
    }
    
    /// Emit an event
    fn emit_event(&self, event: SyncEvent) {
        if let Some(ref callback) = self.event_callback {
            callback(event);
        }
    }
}

impl Default for SyncDaemon {
    fn default() -> Self {
        Self::new()
    }
}

/// Result of a sync operation
#[derive(Debug, Clone)]
pub struct SyncResult {
    pub conversations_synced: usize,
    pub messages_synced: usize,
    pub duration: Duration,
}

/// Sync errors
#[derive(Debug, Clone)]
pub enum SyncError {
    /// Daemon is already running
    AlreadyRunning,
    /// Sync is disabled in config
    Disabled,
    /// Database file not found
    DatabaseNotFound(String),
    /// Database read error
    DatabaseError(String),
    /// Write error
    WriteError(String),
    /// IO error
    IoError(String),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncError::AlreadyRunning => write!(f, "Sync daemon is already running"),
            SyncError::Disabled => write!(f, "Sync is disabled in configuration"),
            SyncError::DatabaseNotFound(path) => write!(f, "Database not found: {}", path),
            SyncError::DatabaseError(e) => write!(f, "Database error: {}", e),
            SyncError::WriteError(e) => write!(f, "Write error: {}", e),
            SyncError::IoError(e) => write!(f, "IO error: {}", e),
        }
    }
}

impl std::error::Error for SyncError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_daemon_creation() {
        let daemon = SyncDaemon::new();
        assert!(!daemon.is_running());
    }
    
    #[test]
    fn test_stats_default() {
        let stats = SyncStats::default();
        assert_eq!(stats.total_syncs, 0);
        assert_eq!(stats.successful_syncs, 0);
    }
}
