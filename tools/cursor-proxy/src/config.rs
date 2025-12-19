//! Configuration management for cursor-proxy

use crate::error::{ConfigError, ProxyError, ProxyResult};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tracing::{debug, info};

/// Main configuration structure
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub proxy: ProxyConfig,
    pub ca: CaConfig,
    pub capture: CaptureConfig,
    pub iptables: IptablesConfig,
    pub injection: InjectionConfigFile,
}

/// Injection configuration (file-based)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct InjectionConfigFile {
    /// Enable injection
    pub enabled: bool,
    /// System prompt to prepend to conversations
    pub system_prompt: Option<String>,
    /// Custom mode name (replaces default)
    pub custom_mode: Option<String>,
    /// Additional context files to inject
    pub context_files: Vec<PathBuf>,
    /// Header overrides
    pub headers: std::collections::HashMap<String, String>,
    /// Version to spoof (if any)
    pub spoof_version: Option<String>,
    /// Rules file path (for dynamic reloading)
    pub rules_file: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ProxyConfig {
    /// Whether proxy is enabled
    pub enabled: bool,
    /// Port to listen on
    pub port: u16,
    /// Alternative ports to try if primary is in use
    pub fallback_ports: Vec<u16>,
    /// Enable verbose logging
    pub verbose: bool,
    /// Timeout for upstream connections (ms)
    pub upstream_timeout_ms: u64,
    /// Maximum concurrent connections
    pub max_connections: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct CaConfig {
    /// Path to CA certificate
    pub cert_path: PathBuf,
    /// Path to CA private key
    pub key_path: PathBuf,
    /// Whether to add CA to system trust store
    pub trust_system_wide: bool,
    /// Certificate validity days
    pub cert_validity_days: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct CaptureConfig {
    /// Enable payload capture
    pub enabled: bool,
    /// Directory for captured payloads
    pub directory: PathBuf,
    /// Days to retain captures
    pub retention_days: u32,
    /// Capture request bodies
    pub capture_requests: bool,
    /// Capture response bodies
    pub capture_responses: bool,
    /// Maximum payload size to capture (bytes)
    pub max_payload_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct IptablesConfig {
    /// Automatically manage iptables rules
    pub auto_manage: bool,
    /// Clean up rules on exit
    pub cleanup_on_exit: bool,
    /// Target domains/IPs for redirection
    pub targets: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        let proxy_dir = home.join(".cursor-proxy");
        
        Self {
            proxy: ProxyConfig::default(),
            ca: CaConfig {
                cert_path: proxy_dir.join("ca-cert.pem"),
                key_path: proxy_dir.join("ca-key.pem"),
                trust_system_wide: true,
                cert_validity_days: 3650,
            },
            capture: CaptureConfig {
                enabled: true,
                directory: proxy_dir.join("captures"),
                retention_days: 7,
                capture_requests: true,
                capture_responses: true,
                max_payload_size: 10 * 1024 * 1024, // 10MB
            },
            iptables: IptablesConfig::default(),
            injection: InjectionConfigFile::default(),
        }
    }
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            port: 8443,
            fallback_ports: vec![8444, 8445, 8446],
            verbose: false,
            upstream_timeout_ms: 30000,
            max_connections: 1000,
        }
    }
}

impl Default for IptablesConfig {
    fn default() -> Self {
        Self {
            auto_manage: true,
            cleanup_on_exit: true,
            targets: vec![
                "api2.cursor.sh".to_string(),
            ],
        }
    }
}

impl Config {
    /// Get default config path
    pub fn default_path() -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cursor-studio")
            .join("proxy.toml")
    }
    
    /// Load configuration from file, or create default
    pub fn load() -> ProxyResult<Self> {
        let path = Self::default_path();
        Self::load_from(&path)
    }
    
    /// Load configuration from specific path
    pub fn load_from(path: &Path) -> ProxyResult<Self> {
        if path.exists() {
            debug!("Loading config from {:?}", path);
            let content = std::fs::read_to_string(path)
                .map_err(|e| ConfigError::NotFound(format!("{}: {}", path.display(), e)))?;
            
            let config: Config = toml::from_str(&content)
                .map_err(|e| ConfigError::Parse(e.to_string()))?;
            
            Ok(config)
        } else {
            debug!("Config not found at {:?}, using defaults", path);
            Ok(Self::default())
        }
    }
    
    /// Save configuration to file
    pub fn save(&self) -> ProxyResult<()> {
        let path = Self::default_path();
        self.save_to(&path)
    }
    
    /// Save configuration to specific path
    pub fn save_to(&self, path: &Path) -> ProxyResult<()> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| ConfigError::Write(format!("Failed to create directory: {}", e)))?;
        }
        
        let content = toml::to_string_pretty(self)
            .map_err(|e| ConfigError::Write(e.to_string()))?;
        
        std::fs::write(path, content)
            .map_err(|e| ConfigError::Write(format!("{}: {}", path.display(), e)))?;
        
        info!("Saved config to {:?}", path);
        Ok(())
    }
    
    /// Expand paths (resolve ~ and environment variables)
    pub fn expand_paths(&mut self) {
        self.ca.cert_path = expand_path(&self.ca.cert_path);
        self.ca.key_path = expand_path(&self.ca.key_path);
        self.capture.directory = expand_path(&self.capture.directory);
    }
    
    /// Validate configuration
    pub fn validate(&self) -> ProxyResult<()> {
        if self.proxy.port == 0 {
            return Err(ProxyError::InvalidConfig {
                field: "proxy.port".into(),
                value: "0".into(),
                reason: "Port must be > 0".into(),
            });
        }
        
        if self.proxy.upstream_timeout_ms == 0 {
            return Err(ProxyError::InvalidConfig {
                field: "proxy.upstream_timeout_ms".into(),
                value: "0".into(),
                reason: "Timeout must be > 0".into(),
            });
        }
        
        Ok(())
    }
    
    /// Ensure required directories exist
    pub fn ensure_directories(&self) -> ProxyResult<()> {
        // CA directory
        if let Some(parent) = self.ca.cert_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        // Capture directory
        if self.capture.enabled {
            std::fs::create_dir_all(&self.capture.directory)?;
        }
        
        Ok(())
    }
}

/// Expand path with ~ and environment variables
fn expand_path(path: &Path) -> PathBuf {
    let path_str = path.to_string_lossy();
    let expanded = shellexpand::tilde(&path_str);
    PathBuf::from(expanded.as_ref())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.proxy.port, 8443);
        assert!(!config.proxy.enabled);
    }
    
    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let toml = toml::to_string(&config).unwrap();
        let parsed: Config = toml::from_str(&toml).unwrap();
        assert_eq!(config.proxy.port, parsed.proxy.port);
    }
}

