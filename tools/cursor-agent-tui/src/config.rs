//! Configuration management for cursor-agent-tui

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// API configuration
    pub api: ApiConfig,
    /// Authentication configuration
    pub auth: AuthConfig,
    /// Tool execution configuration
    pub tools: ToolsConfig,
    /// State management configuration
    pub state: StateConfig,
    /// TUI configuration
    pub tui: TuiConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ApiConfig {
    /// API base URL
    pub base_url: String,
    /// Request timeout in seconds
    pub timeout_secs: u64,
    /// Default model to use
    pub default_model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct AuthConfig {
    /// Path to Cursor's credential storage
    pub cursor_storage_path: Option<PathBuf>,
    /// Path to our own token storage
    pub token_path: PathBuf,
    /// Allow token from environment variable
    pub allow_env_token: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ToolsConfig {
    /// Allowed paths for file operations (empty = cwd only)
    pub allowed_paths: Vec<PathBuf>,
    /// Command execution policy
    pub command_policy: CommandPolicy,
    /// Maximum file size to read (bytes)
    pub max_file_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CommandPolicy {
    /// Whether to allow command execution
    pub enabled: bool,
    /// Require confirmation for commands
    pub require_confirmation: bool,
    /// Blocked commands (patterns)
    pub blocked_patterns: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct StateConfig {
    /// Path to state storage
    pub storage_path: PathBuf,
    /// Maximum history entries
    pub max_history: usize,
    /// Maximum state file size (bytes)
    pub max_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct TuiConfig {
    /// Color theme
    pub theme: String,
    /// Show file tree panel
    pub show_files: bool,
    /// Syntax highlighting
    pub syntax_highlight: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            api: ApiConfig::default(),
            auth: AuthConfig::default(),
            tools: ToolsConfig::default(),
            state: StateConfig::default(),
            tui: TuiConfig::default(),
        }
    }
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            base_url: "https://api2.cursor.sh".to_string(),
            timeout_secs: 300,
            default_model: "claude-3-5-sonnet-20241022".to_string(),
        }
    }
}

impl Default for AuthConfig {
    fn default() -> Self {
        let config_dir = dirs::config_dir().unwrap_or_else(|| PathBuf::from("."));
        Self {
            cursor_storage_path: Some(config_dir.join("Cursor")),
            token_path: config_dir.join("cursor-agent").join("token"),
            allow_env_token: true,
        }
    }
}

impl Default for ToolsConfig {
    fn default() -> Self {
        Self {
            allowed_paths: vec![],
            command_policy: CommandPolicy::default(),
            max_file_size: 10 * 1024 * 1024, // 10MB
        }
    }
}

impl Default for CommandPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            require_confirmation: true,
            blocked_patterns: vec![
                "rm -rf /".to_string(),
                "sudo rm".to_string(),
                ":(){:|:&};:".to_string(), // Fork bomb
            ],
        }
    }
}

impl Default for StateConfig {
    fn default() -> Self {
        let data_dir = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
        Self {
            storage_path: data_dir.join("cursor-agent").join("state"),
            max_history: 100,
            max_size: 50 * 1024 * 1024, // 50MB
        }
    }
}

impl Default for TuiConfig {
    fn default() -> Self {
        Self {
            theme: "default".to_string(),
            show_files: true,
            syntax_highlight: true,
        }
    }
}

impl Config {
    /// Get default configuration file path
    pub fn default_path() -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cursor-agent")
            .join("config.toml")
    }

    /// Load configuration from file
    pub fn load(path: Option<&Path>) -> Result<Self> {
        let path = path.map(PathBuf::from).unwrap_or_else(Self::default_path);

        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            let config: Config = toml::from_str(&content)?;
            Ok(config)
        } else {
            Ok(Self::default())
        }
    }

    /// Save configuration to file
    pub fn save(&self, path: Option<&Path>) -> Result<()> {
        let path = path.map(PathBuf::from).unwrap_or_else(Self::default_path);

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let content = toml::to_string_pretty(self)?;
        std::fs::write(&path, content)?;

        Ok(())
    }
}

