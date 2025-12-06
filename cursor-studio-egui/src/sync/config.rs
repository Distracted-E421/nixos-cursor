//! Sync Daemon Configuration
//!
//! Configuration can be loaded from:
//! - Default values
//! - Config file (~/.config/cursor-studio/sync.toml)
//! - Environment variables
//! - Home Manager (NixOS)

use std::path::PathBuf;
use std::time::Duration;
use serde::{Deserialize, Serialize};

/// Sync daemon configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    /// Whether sync is enabled
    pub enabled: bool,
    
    /// Path to external database for synced data
    pub external_db_path: PathBuf,
    
    /// Paths to watch for Cursor databases
    pub cursor_paths: CursorPaths,
    
    /// Debounce duration for file changes
    pub debounce_ms: u64,
    
    /// How often to check for changes (polling fallback)
    pub poll_interval_secs: u64,
    
    /// Maximum retries on sync failure
    pub max_retries: u32,
    
    /// Retry backoff multiplier
    pub retry_backoff_ms: u64,
    
    /// Whether to sync on startup
    pub sync_on_start: bool,
    
    /// Log level for sync operations
    pub log_level: LogLevel,
    
    /// Export settings
    pub export: ExportConfig,
}

/// Paths to Cursor data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorPaths {
    /// Global storage path (state.vscdb)
    pub global_storage: PathBuf,
    
    /// Workspace storage base path
    pub workspace_storage: PathBuf,
    
    /// Settings path
    pub settings: PathBuf,
}

/// Export configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportConfig {
    /// Export directory
    pub output_dir: PathBuf,
    
    /// Default export format
    pub default_format: ExportFormat,
    
    /// Whether to include raw JSON
    pub include_raw: bool,
}

/// Export formats
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ExportFormat {
    /// SQLite database file
    Database,
    /// Markdown files
    Markdown,
    /// HTML report
    Html,
    /// JSON export
    Json,
}

/// Log levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Default for SyncConfig {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let config_dir = dirs::config_dir().unwrap_or_else(|| home.join(".config"));
        
        Self {
            enabled: true,
            external_db_path: config_dir.join("cursor-studio/conversations.db"),
            cursor_paths: CursorPaths::default(),
            debounce_ms: 500,
            poll_interval_secs: 30,
            max_retries: 3,
            retry_backoff_ms: 1000,
            sync_on_start: true,
            log_level: LogLevel::Info,
            export: ExportConfig::default(),
        }
    }
}

impl Default for CursorPaths {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let config_dir = home.join(".config/Cursor");
        
        Self {
            global_storage: config_dir.join("User/globalStorage/state.vscdb"),
            workspace_storage: config_dir.join("User/workspaceStorage"),
            settings: config_dir.join("User/settings.json"),
        }
    }
}

impl Default for ExportConfig {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        
        Self {
            output_dir: home.join("cursor-exports"),
            default_format: ExportFormat::Markdown,
            include_raw: false,
        }
    }
}

impl SyncConfig {
    /// Load configuration from file, falling back to defaults
    pub fn load() -> Self {
        let config_path = dirs::config_dir()
            .map(|d| d.join("cursor-studio/sync.toml"))
            .unwrap_or_else(|| PathBuf::from("sync.toml"));
        
        if config_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&config_path) {
                if let Ok(config) = toml::from_str(&content) {
                    return config;
                }
            }
        }
        
        Self::default()
    }
    
    /// Save configuration to file
    pub fn save(&self) -> std::io::Result<()> {
        let config_path = dirs::config_dir()
            .map(|d| d.join("cursor-studio/sync.toml"))
            .unwrap_or_else(|| PathBuf::from("sync.toml"));
        
        if let Some(parent) = config_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let content = toml::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        
        std::fs::write(config_path, content)
    }
    
    /// Get debounce duration
    pub fn debounce_duration(&self) -> Duration {
        Duration::from_millis(self.debounce_ms)
    }
    
    /// Get poll interval
    pub fn poll_interval(&self) -> Duration {
        Duration::from_secs(self.poll_interval_secs)
    }
    
    /// Get retry backoff duration
    pub fn retry_backoff(&self) -> Duration {
        Duration::from_millis(self.retry_backoff_ms)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_config() {
        let config = SyncConfig::default();
        assert!(config.enabled);
        assert!(config.sync_on_start);
        assert_eq!(config.max_retries, 3);
    }
}
