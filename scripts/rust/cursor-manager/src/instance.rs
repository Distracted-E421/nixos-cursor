//! Instance management for isolated Cursor environments
//! 
//! NOTE: This module is infrastructure for future multi-instance support.
//! Currently unused but kept for planned features.

#![allow(dead_code)]

use std::path::PathBuf;
use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::config::Config;

#[derive(Debug, Clone, Serialize, Deserialize)]
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
