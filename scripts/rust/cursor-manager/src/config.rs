//! Configuration management

use std::path::PathBuf;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub install_dir: PathBuf,
    pub data_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub auto_cleanup: bool,
    pub keep_versions: u32,
}

impl Default for Config {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        
        Self {
            install_dir: home.join(".cursor-versions"),
            data_dir: home.join(".config/Cursor"),
            cache_dir: home.join(".cache/cursor-manager"),
            auto_cleanup: false,
            keep_versions: 3,
        }
    }
}

impl Config {
    pub fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path)
                .context("Failed to read config file")?;
            let config: Config = serde_json::from_str(&content)
                .context("Failed to parse config file")?;
            Ok(config)
        } else {
            Ok(Self::default())
        }
    }

    pub fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        
        if let Some(parent) = config_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&config_path, content)?;
        
        Ok(())
    }

    pub fn get(&self, key: &str) -> Result<String> {
        match key {
            "install_dir" => Ok(self.install_dir.display().to_string()),
            "data_dir" => Ok(self.data_dir.display().to_string()),
            "cache_dir" => Ok(self.cache_dir.display().to_string()),
            "auto_cleanup" => Ok(self.auto_cleanup.to_string()),
            "keep_versions" => Ok(self.keep_versions.to_string()),
            _ => bail!("Unknown config key: {}", key),
        }
    }

    pub fn set(&mut self, key: &str, value: &str) -> Result<()> {
        match key {
            "install_dir" => self.install_dir = PathBuf::from(value),
            "data_dir" => self.data_dir = PathBuf::from(value),
            "cache_dir" => self.cache_dir = PathBuf::from(value),
            "auto_cleanup" => self.auto_cleanup = value.parse()?,
            "keep_versions" => self.keep_versions = value.parse()?,
            _ => bail!("Unknown config key: {}", key),
        }
        Ok(())
    }

    fn config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .context("Could not determine config directory")?;
        Ok(config_dir.join("cursor-manager").join("config.json"))
    }
}
