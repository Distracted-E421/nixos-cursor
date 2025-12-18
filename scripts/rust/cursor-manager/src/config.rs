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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_config_default() {
        let config = Config::default();
        assert!(!config.auto_cleanup);
        assert_eq!(config.keep_versions, 3);
        assert!(config.install_dir.to_string_lossy().contains(".cursor-versions"));
    }

    #[test]
    fn test_config_get_valid_keys() {
        let config = Config::default();
        
        assert!(config.get("install_dir").is_ok());
        assert!(config.get("data_dir").is_ok());
        assert!(config.get("cache_dir").is_ok());
        assert!(config.get("auto_cleanup").is_ok());
        assert!(config.get("keep_versions").is_ok());
    }

    #[test]
    fn test_config_get_invalid_key() {
        let config = Config::default();
        assert!(config.get("invalid_key").is_err());
    }

    #[test]
    fn test_config_set_valid_keys() {
        let mut config = Config::default();
        
        assert!(config.set("install_dir", "/tmp/test").is_ok());
        assert_eq!(config.install_dir, PathBuf::from("/tmp/test"));
        
        assert!(config.set("auto_cleanup", "true").is_ok());
        assert!(config.auto_cleanup);
        
        assert!(config.set("keep_versions", "5").is_ok());
        assert_eq!(config.keep_versions, 5);
    }

    #[test]
    fn test_config_set_invalid_key() {
        let mut config = Config::default();
        assert!(config.set("invalid_key", "value").is_err());
    }

    #[test]
    fn test_config_set_invalid_value() {
        let mut config = Config::default();
        // "not_a_bool" should fail to parse as bool
        assert!(config.set("auto_cleanup", "not_a_bool").is_err());
        // "not_a_number" should fail to parse as u32
        assert!(config.set("keep_versions", "not_a_number").is_err());
    }

    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let json = serde_json::to_string(&config).unwrap();
        let parsed: Config = serde_json::from_str(&json).unwrap();
        
        assert_eq!(config.install_dir, parsed.install_dir);
        assert_eq!(config.auto_cleanup, parsed.auto_cleanup);
        assert_eq!(config.keep_versions, parsed.keep_versions);
    }

    #[test]
    fn test_config_save_and_load() {
        let temp_dir = TempDir::new().unwrap();
        let config_path = temp_dir.path().join("config.json");
        
        // Create a config with custom values
        let mut config = Config::default();
        config.install_dir = PathBuf::from("/custom/install");
        config.auto_cleanup = true;
        config.keep_versions = 10;
        
        // Save to temp location
        let content = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&config_path, &content).unwrap();
        
        // Load and verify
        let loaded_content = std::fs::read_to_string(&config_path).unwrap();
        let loaded: Config = serde_json::from_str(&loaded_content).unwrap();
        
        assert_eq!(loaded.install_dir, PathBuf::from("/custom/install"));
        assert!(loaded.auto_cleanup);
        assert_eq!(loaded.keep_versions, 10);
    }
}
