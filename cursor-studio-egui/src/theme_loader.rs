//! VS Code Theme Loader
//!
//! Discovers and loads VS Code themes from Cursor extensions directory.

use crate::theme::Theme;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// A discovered VS Code theme
#[derive(Debug, Clone)]
pub struct ThemeInfo {
    /// Display name of the theme
    pub name: String,
    
    /// Path to the theme JSON file
    pub path: PathBuf,
    
    /// Extension ID that provides this theme
    pub extension_id: String,
    
    /// Whether this is a light theme
    pub is_light: bool,
    
    /// Theme type (dark, light, hc, hc-light)
    pub theme_type: String,
}

/// Theme loader for discovering VS Code themes
pub struct ThemeLoader {
    /// Discovered themes indexed by name
    themes: HashMap<String, ThemeInfo>,
    
    /// Search paths for themes
    search_paths: Vec<PathBuf>,
}

impl Default for ThemeLoader {
    fn default() -> Self {
        Self::new()
    }
}

impl ThemeLoader {
    /// Create a new theme loader with default search paths
    pub fn new() -> Self {
        let mut search_paths = Vec::new();
        
        // Add standard Cursor/VS Code extension paths
        if let Some(home) = dirs::home_dir() {
            // Cursor extensions
            search_paths.push(home.join(".cursor/extensions"));
            
            // VS Code extensions (fallback)
            search_paths.push(home.join(".vscode/extensions"));
            
            // Local data locations
            search_paths.push(home.join(".local/share/cursor/extensions"));
            search_paths.push(home.join(".local/share/vscode/extensions"));
        }
        
        Self {
            themes: HashMap::new(),
            search_paths,
        }
    }
    
    /// Add a custom search path
    pub fn add_search_path(&mut self, path: impl Into<PathBuf>) {
        self.search_paths.push(path.into());
    }
    
    /// Scan for available themes
    pub fn scan(&mut self) -> &HashMap<String, ThemeInfo> {
        self.themes.clear();
        
        for search_path in &self.search_paths.clone() {
            if search_path.exists() {
                self.scan_extensions_dir(search_path);
            }
        }
        
        &self.themes
    }
    
    /// Scan an extensions directory
    fn scan_extensions_dir(&mut self, dir: &Path) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    self.scan_extension(&path);
                }
            }
        }
    }
    
    /// Scan a single extension for themes
    fn scan_extension(&mut self, extension_path: &Path) {
        let extension_id = extension_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        // Check for package.json to get theme contributions
        let package_json = extension_path.join("package.json");
        if package_json.exists() {
            if let Ok(content) = std::fs::read_to_string(&package_json) {
                self.parse_package_json(&content, extension_path, &extension_id);
            }
        }
        
        // Also scan themes directory directly
        let themes_dir = extension_path.join("themes");
        if themes_dir.exists() {
            self.scan_themes_dir(&themes_dir, &extension_id);
        }
    }
    
    /// Parse package.json to find theme contributions
    fn parse_package_json(&mut self, content: &str, extension_path: &Path, extension_id: &str) {
        // Try to parse as JSON
        let json: serde_json::Value = match serde_json::from_str(content) {
            Ok(v) => v,
            Err(_) => return,
        };
        
        // Look for contributes.themes
        if let Some(contributes) = json.get("contributes") {
            if let Some(themes) = contributes.get("themes").and_then(|t| t.as_array()) {
                for theme in themes {
                    let label = theme.get("label").and_then(|l| l.as_str()).unwrap_or("Unknown");
                    let path_str = theme.get("path").and_then(|p| p.as_str()).unwrap_or("");
                    let ui_theme = theme.get("uiTheme").and_then(|u| u.as_str()).unwrap_or("vs-dark");
                    
                    let theme_path = extension_path.join(path_str);
                    if theme_path.exists() {
                        let theme_type = match ui_theme {
                            "vs" => "light",
                            "vs-dark" => "dark",
                            "hc-black" => "hc",
                            "hc-light" => "hc-light",
                            _ => "dark",
                        };
                        
                        let info = ThemeInfo {
                            name: label.to_string(),
                            path: theme_path,
                            extension_id: extension_id.to_string(),
                            is_light: theme_type == "light" || theme_type == "hc-light",
                            theme_type: theme_type.to_string(),
                        };
                        
                        self.themes.insert(label.to_string(), info);
                    }
                }
            }
        }
    }
    
    /// Scan a themes directory for JSON files
    fn scan_themes_dir(&mut self, dir: &Path, extension_id: &str) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "json").unwrap_or(false) {
                    // Try to determine theme name from filename
                    let name = path
                        .file_stem()
                        .and_then(|n| n.to_str())
                        .unwrap_or("Unknown")
                        .replace("-color-theme", "")
                        .replace("_color_theme", "")
                        .replace("-theme", "")
                        .replace("_theme", "");
                    
                    // Try to determine if light theme
                    let is_light = name.to_lowercase().contains("light");
                    
                    // Only add if not already registered via package.json
                    if !self.themes.contains_key(&name) {
                        let info = ThemeInfo {
                            name: name.clone(),
                            path,
                            extension_id: extension_id.to_string(),
                            is_light,
                            theme_type: if is_light { "light".to_string() } else { "dark".to_string() },
                        };
                        
                        self.themes.insert(name, info);
                    }
                }
            }
        }
    }
    
    /// Get list of all discovered themes
    pub fn list_themes(&self) -> Vec<&ThemeInfo> {
        let mut themes: Vec<_> = self.themes.values().collect();
        themes.sort_by(|a, b| a.name.cmp(&b.name));
        themes
    }
    
    /// Get list of dark themes
    pub fn dark_themes(&self) -> Vec<&ThemeInfo> {
        self.themes.values().filter(|t| !t.is_light).collect()
    }
    
    /// Get list of light themes
    pub fn light_themes(&self) -> Vec<&ThemeInfo> {
        self.themes.values().filter(|t| t.is_light).collect()
    }
    
    /// Load a theme by name
    pub fn load_theme(&self, name: &str) -> Option<Theme> {
        self.themes.get(name).and_then(|info| Theme::from_vscode_file(&info.path))
    }
    
    /// Load a theme directly from path
    pub fn load_theme_from_path(&self, path: &Path) -> Option<Theme> {
        Theme::from_vscode_file(path)
    }
    
    /// Get theme info by name
    pub fn get_theme_info(&self, name: &str) -> Option<&ThemeInfo> {
        self.themes.get(name)
    }
    
    /// Find themes by extension ID
    pub fn themes_by_extension(&self, extension_id: &str) -> Vec<&ThemeInfo> {
        self.themes.values()
            .filter(|t| t.extension_id.contains(extension_id))
            .collect()
    }
    
    /// Search themes by name pattern
    pub fn search_themes(&self, pattern: &str) -> Vec<&ThemeInfo> {
        let pattern_lower = pattern.to_lowercase();
        self.themes.values()
            .filter(|t| t.name.to_lowercase().contains(&pattern_lower))
            .collect()
    }
}

/// Get the currently active theme from Cursor settings
pub fn get_active_cursor_theme() -> Option<String> {
    let settings_path = dirs::home_dir()?
        .join(".config/Cursor/User/settings.json");
    
    let content = std::fs::read_to_string(settings_path).ok()?;
    let json: serde_json::Value = serde_json::from_str(&content).ok()?;
    
    json.get("workbench.colorTheme")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_theme_loader_creation() {
        let loader = ThemeLoader::new();
        assert!(!loader.search_paths.is_empty());
    }
    
    #[test]
    fn test_scan_extensions() {
        let mut loader = ThemeLoader::new();
        let themes = loader.scan();
        // This will find themes if Cursor/VS Code is installed
        println!("Found {} themes", themes.len());
        for (name, info) in themes {
            println!("  - {} ({})", name, info.extension_id);
        }
    }
}
