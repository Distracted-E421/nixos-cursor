//! Custom Modes System for Cursor Studio
//! 
//! Replaces Cursor's removed custom modes feature with an external system that:
//! - Controls system prompts
//! - Locks/unlocks tools per mode
//! - Selects models per mode
//! - Works with any Cursor version
//!
//! Implementation Strategy:
//! - Store modes in ~/.config/cursor-studio/modes/
//! - Generate .cursorrules files from mode definitions
//! - Provide UI for mode switching in Cursor Studio

mod config;
mod injection;

pub use config::{CustomMode, ModeConfig, ToolAccess, ModelConfig};
pub use injection::{ModeInjector, InjectionTarget};

use std::collections::HashMap;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Registry of all available custom modes
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModeRegistry {
    /// Active mode name
    pub active_mode: Option<String>,
    
    /// All registered modes
    pub modes: HashMap<String, CustomMode>,
    
    /// Path to modes directory
    #[serde(skip)]
    pub modes_dir: PathBuf,
}

impl ModeRegistry {
    /// Load registry from disk
    pub fn load(modes_dir: PathBuf) -> Self {
        let registry_path = modes_dir.join("registry.json");
        
        let mut registry: Self = std::fs::read_to_string(&registry_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        
        registry.modes_dir = modes_dir.clone();
        
        // Load individual mode files
        if let Ok(entries) = std::fs::read_dir(&modes_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map_or(false, |e| e == "json") 
                    && path.file_stem().map_or(false, |s| s != "registry") 
                {
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        if let Ok(mode) = serde_json::from_str::<CustomMode>(&content) {
                            registry.modes.insert(mode.name.clone(), mode);
                        }
                    }
                }
            }
        }
        
        // Ensure built-in modes exist
        registry.ensure_builtin_modes();
        
        registry
    }
    
    /// Save registry to disk
    pub fn save(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.modes_dir)?;
        
        // Save registry index
        let registry_path = self.modes_dir.join("registry.json");
        let index = serde_json::json!({
            "active_mode": self.active_mode,
            "mode_names": self.modes.keys().collect::<Vec<_>>(),
        });
        std::fs::write(&registry_path, serde_json::to_string_pretty(&index)?)?;
        
        // Save individual mode files
        for (name, mode) in &self.modes {
            let mode_path = self.modes_dir.join(format!("{}.json", name.to_lowercase().replace(' ', "-")));
            std::fs::write(&mode_path, serde_json::to_string_pretty(mode)?)?;
        }
        
        Ok(())
    }
    
    /// Get active mode
    pub fn active(&self) -> Option<&CustomMode> {
        self.active_mode.as_ref().and_then(|name| self.modes.get(name))
    }
    
    /// Set active mode
    pub fn set_active(&mut self, name: &str) -> bool {
        if self.modes.contains_key(name) {
            self.active_mode = Some(name.to_string());
            true
        } else {
            false
        }
    }
    
    /// Add or update a mode
    pub fn upsert(&mut self, mode: CustomMode) {
        self.modes.insert(mode.name.clone(), mode);
    }
    
    /// Remove a mode
    pub fn remove(&mut self, name: &str) -> Option<CustomMode> {
        if let Some(active) = &self.active_mode {
            if active == name {
                self.active_mode = None;
            }
        }
        self.modes.remove(name)
    }
    
    /// Ensure built-in modes exist
    fn ensure_builtin_modes(&mut self) {
        // Default Agent mode
        if !self.modes.contains_key("Agent") {
            self.modes.insert("Agent".into(), CustomMode::agent_default());
        }
        
        // Code Review mode (read-only)
        if !self.modes.contains_key("Code Review") {
            self.modes.insert("Code Review".into(), CustomMode::code_review());
        }
        
        // Maxim mode (from your custom setup)
        if !self.modes.contains_key("Maxim") {
            self.modes.insert("Maxim".into(), CustomMode::maxim_obsidian());
        }
        
        // Planning mode (think before acting)
        if !self.modes.contains_key("Planning") {
            self.modes.insert("Planning".into(), CustomMode::planning());
        }
    }
    
    /// List all mode names
    pub fn list_names(&self) -> Vec<&str> {
        self.modes.keys().map(|s| s.as_str()).collect()
    }
}

