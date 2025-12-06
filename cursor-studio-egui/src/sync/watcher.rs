//! File System Watcher
//!
//! Watches Cursor's database files for changes using the `notify` crate.
//! Debounces events and triggers sync operations.

use std::path::{Path, PathBuf};
use std::time::Duration;
use std::sync::mpsc::{channel, Receiver, Sender};

/// Database change event
#[derive(Debug, Clone)]
pub enum WatchEvent {
    /// A database file was modified
    Modified(PathBuf),
    /// A new database file was created
    Created(PathBuf),
    /// A database file was deleted
    Deleted(PathBuf),
    /// Watcher error
    Error(String),
}

/// Database file watcher
pub struct DatabaseWatcher {
    /// Paths being watched
    watched_paths: Vec<PathBuf>,
    
    /// Event receiver
    rx: Option<Receiver<WatchEvent>>,
    
    /// Event sender (for internal use)
    tx: Sender<WatchEvent>,
    
    /// Debounce duration
    debounce: Duration,
    
    /// Whether watcher is active
    active: bool,
}

impl DatabaseWatcher {
    /// Create a new database watcher
    pub fn new() -> Self {
        let (tx, rx) = channel();
        
        Self {
            watched_paths: Vec::new(),
            rx: Some(rx),
            tx,
            debounce: Duration::from_millis(500),
            active: false,
        }
    }
    
    /// Set debounce duration
    pub fn with_debounce(mut self, debounce: Duration) -> Self {
        self.debounce = debounce;
        self
    }
    
    /// Add a path to watch
    pub fn watch(&mut self, path: impl AsRef<Path>) -> Result<(), WatchError> {
        let path = path.as_ref().to_path_buf();
        
        if !path.exists() {
            return Err(WatchError::PathNotFound(path.display().to_string()));
        }
        
        self.watched_paths.push(path);
        Ok(())
    }
    
    /// Start watching
    pub fn start(&mut self) -> Result<(), WatchError> {
        if self.active {
            return Err(WatchError::AlreadyWatching);
        }
        
        // TODO: Initialize notify watcher
        // For now, just mark as active
        self.active = true;
        
        Ok(())
    }
    
    /// Stop watching
    pub fn stop(&mut self) {
        self.active = false;
    }
    
    /// Check if watcher is active
    pub fn is_active(&self) -> bool {
        self.active
    }
    
    /// Take the event receiver (can only be called once)
    pub fn take_receiver(&mut self) -> Option<Receiver<WatchEvent>> {
        self.rx.take()
    }
    
    /// Get watched paths
    pub fn watched_paths(&self) -> &[PathBuf] {
        &self.watched_paths
    }
}

impl Default for DatabaseWatcher {
    fn default() -> Self {
        Self::new()
    }
}

/// Watch errors
#[derive(Debug, Clone)]
pub enum WatchError {
    /// Path not found
    PathNotFound(String),
    /// Already watching
    AlreadyWatching,
    /// Notify error
    NotifyError(String),
}

impl std::fmt::Display for WatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WatchError::PathNotFound(p) => write!(f, "Path not found: {}", p),
            WatchError::AlreadyWatching => write!(f, "Already watching"),
            WatchError::NotifyError(e) => write!(f, "Notify error: {}", e),
        }
    }
}

impl std::error::Error for WatchError {}
