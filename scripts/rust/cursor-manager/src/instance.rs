//! Instance management for isolated Cursor environments
//! 
//! NOTE: This module is infrastructure for future multi-instance support.
//! Currently unused but kept for planned features.

#![allow(dead_code)]

use std::path::PathBuf;
use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::config::Config;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Instance {
    pub name: String,
    pub version: String,
    pub data_dir: PathBuf,
    pub created_at: String,
}

pub struct InstanceManager {
    config: Config,
}

impl InstanceManager {
    pub fn new() -> Result<Self> {
        let config = Config::load()?;
        Ok(Self { config })
    }

    /// Create an InstanceManager with a custom config (useful for testing)
    pub fn with_config(config: Config) -> Self {
        Self { config }
    }

    pub fn list(&self) -> Result<Vec<Instance>> {
        let instances_dir = self.instances_dir();
        
        if !instances_dir.exists() {
            return Ok(Vec::new());
        }

        let mut instances = Vec::new();
        
        for entry in std::fs::read_dir(instances_dir)? {
            let entry = entry?;
            let path = entry.path();
            
            if path.is_dir() {
                let manifest_path = path.join("instance.json");
                if manifest_path.exists() {
                    let content = std::fs::read_to_string(&manifest_path)?;
                    let instance: Instance = serde_json::from_str(&content)?;
                    instances.push(instance);
                }
            }
        }

        Ok(instances)
    }

    pub fn create(&self, name: &str, version: &str) -> Result<Instance> {
        let instance_dir = self.instance_dir(name);
        
        std::fs::create_dir_all(&instance_dir)?;
        
        let data_dir = instance_dir.join("data");
        std::fs::create_dir_all(&data_dir)?;

        let instance = Instance {
            name: name.to_string(),
            version: version.to_string(),
            data_dir,
            created_at: chrono_now(),
        };

        let manifest_path = instance_dir.join("instance.json");
        let content = serde_json::to_string_pretty(&instance)?;
        std::fs::write(manifest_path, content)?;

        Ok(instance)
    }

    pub fn delete(&self, name: &str) -> Result<()> {
        let instance_dir = self.instance_dir(name);
        
        if instance_dir.exists() {
            std::fs::remove_dir_all(instance_dir)?;
        }

        Ok(())
    }

    pub fn get(&self, name: &str) -> Result<Option<Instance>> {
        let manifest_path = self.instance_dir(name).join("instance.json");
        
        if manifest_path.exists() {
            let content = std::fs::read_to_string(&manifest_path)?;
            let instance: Instance = serde_json::from_str(&content)?;
            Ok(Some(instance))
        } else {
            Ok(None)
        }
    }

    fn instances_dir(&self) -> PathBuf {
        self.config.install_dir.join("instances")
    }

    fn instance_dir(&self, name: &str) -> PathBuf {
        self.instances_dir().join(name)
    }
}

fn chrono_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{}", secs)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn create_test_config(temp_dir: &TempDir) -> Config {
        Config {
            install_dir: temp_dir.path().join("versions"),
            data_dir: temp_dir.path().join("data"),
            cache_dir: temp_dir.path().join("cache"),
            auto_cleanup: false,
            keep_versions: 3,
        }
    }

    #[test]
    fn test_instance_serialization() {
        let instance = Instance {
            name: "test-instance".to_string(),
            version: "2.1.34".to_string(),
            data_dir: PathBuf::from("/test/data"),
            created_at: "12345".to_string(),
        };
        
        let json = serde_json::to_string(&instance).unwrap();
        let parsed: Instance = serde_json::from_str(&json).unwrap();
        
        assert_eq!(instance.name, parsed.name);
        assert_eq!(instance.version, parsed.version);
        assert_eq!(instance.data_dir, parsed.data_dir);
    }

    #[test]
    fn test_list_empty() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        let instances = manager.list().unwrap();
        assert!(instances.is_empty());
    }

    #[test]
    fn test_create_instance() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        let instance = manager.create("test-instance", "2.1.34").unwrap();
        
        assert_eq!(instance.name, "test-instance");
        assert_eq!(instance.version, "2.1.34");
        assert!(instance.data_dir.exists());
    }

    #[test]
    fn test_get_instance() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        // Create an instance
        manager.create("test-instance", "2.1.34").unwrap();
        
        // Get it back
        let instance = manager.get("test-instance").unwrap();
        assert!(instance.is_some());
        
        let instance = instance.unwrap();
        assert_eq!(instance.name, "test-instance");
        assert_eq!(instance.version, "2.1.34");
    }

    #[test]
    fn test_get_nonexistent_instance() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        let instance = manager.get("nonexistent").unwrap();
        assert!(instance.is_none());
    }

    #[test]
    fn test_delete_instance() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        // Create and then delete
        manager.create("test-instance", "2.1.34").unwrap();
        assert!(manager.get("test-instance").unwrap().is_some());
        
        manager.delete("test-instance").unwrap();
        assert!(manager.get("test-instance").unwrap().is_none());
    }

    #[test]
    fn test_delete_nonexistent_instance() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        // Should not error when deleting non-existent instance
        let result = manager.delete("nonexistent");
        assert!(result.is_ok());
    }

    #[test]
    fn test_list_instances() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = InstanceManager::with_config(config);
        
        // Create multiple instances
        manager.create("instance-1", "2.1.34").unwrap();
        manager.create("instance-2", "2.0.77").unwrap();
        
        let instances = manager.list().unwrap();
        assert_eq!(instances.len(), 2);
        
        let names: Vec<_> = instances.iter().map(|i| &i.name).collect();
        assert!(names.contains(&&"instance-1".to_string()));
        assert!(names.contains(&&"instance-2".to_string()));
    }

    #[test]
    fn test_chrono_now() {
        let now = chrono_now();
        let parsed: u64 = now.parse().unwrap();
        
        // Should be a reasonable timestamp (after 2020)
        assert!(parsed > 1577836800); // Jan 1, 2020
    }
}
