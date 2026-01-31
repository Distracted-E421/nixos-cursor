//! Version management

use std::path::PathBuf;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::config::Config;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Version {
    pub version: String,
    pub path: PathBuf,
    pub disk_size: u64,
    pub installed_at: String,
}

impl Version {
    pub fn disk_size_human(&self) -> String {
        format_size(self.disk_size)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionInfo {
    pub installed: bool,
    pub path: PathBuf,
    pub disk_size_human: String,
    pub installed_at: String,
    pub download_url: String,
}

pub struct VersionManager {
    config: Config,
}

impl VersionManager {
    pub fn new() -> Result<Self> {
        let config = Config::load()?;
        Ok(Self { config })
    }

    /// Create a VersionManager with a custom config (useful for testing)
    pub fn with_config(config: Config) -> Self {
        Self { config }
    }

    pub fn list_installed(&self) -> Result<Vec<Version>> {
        let install_dir = &self.config.install_dir;
        
        if !install_dir.exists() {
            return Ok(Vec::new());
        }

        let mut versions = Vec::new();
        
        for entry in std::fs::read_dir(install_dir)? {
            let entry = entry?;
            let path = entry.path();
            
            if path.is_dir() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.starts_with("cursor-") {
                        let version = name.strip_prefix("cursor-").unwrap_or(name).to_string();
                        let disk_size = calculate_dir_size(&path);
                        let metadata = std::fs::metadata(&path)?;
                        let installed_at = format_time(metadata.modified()?);
                        
                        versions.push(Version {
                            version,
                            path,
                            disk_size,
                            installed_at,
                        });
                    }
                }
            }
        }

        versions.sort_by(|a, b| b.version.cmp(&a.version));
        Ok(versions)
    }

    pub async fn list_available(&self) -> Result<Vec<String>> {
        // This would fetch from the Cursor releases API or our version list
        // For now, return a static list of known versions
        Ok(vec![
            "2.1.34".into(), "2.1.32".into(), "2.1.26".into(),
            "2.0.77".into(), "2.0.71".into(), "2.0.64".into(),
            "1.7.59".into(), "1.6.45".into(),
        ])
    }

    pub async fn resolve_version(&self, version: &str) -> Result<String> {
        match version {
            "latest" | "stable" => {
                let available = self.list_available().await?;
                available.first()
                    .cloned()
                    .context("No versions available")
            }
            v => Ok(v.to_string())
        }
    }

    pub fn is_installed(&self, version: &str) -> Result<bool> {
        let path = self.version_path(version);
        Ok(path.exists())
    }

    pub fn current_version(&self) -> Result<Option<Version>> {
        let current_link = self.config.install_dir.join("current");
        
        if !current_link.exists() {
            return Ok(None);
        }

        let target = std::fs::read_link(&current_link)?;
        
        if let Some(name) = target.file_name().and_then(|n| n.to_str()) {
            let version = name.strip_prefix("cursor-").unwrap_or(name).to_string();
            let disk_size = calculate_dir_size(&target);
            let metadata = std::fs::metadata(&target)?;
            let installed_at = format_time(metadata.modified()?);
            
            Ok(Some(Version {
                version,
                path: target,
                disk_size,
                installed_at,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn set_current(&self, version: &str) -> Result<()> {
        let version_path = self.version_path(version);
        let current_link = self.config.install_dir.join("current");
        
        if !version_path.exists() {
            bail!("Version {} is not installed", version);
        }

        if current_link.exists() || current_link.is_symlink() {
            std::fs::remove_file(&current_link)?;
        }

        #[cfg(unix)]
        std::os::unix::fs::symlink(&version_path, &current_link)?;
        
        #[cfg(windows)]
        std::os::windows::fs::symlink_dir(&version_path, &current_link)?;

        Ok(())
    }

    pub fn install(&self, version: &str, appimage_path: &PathBuf) -> Result<()> {
        let version_path = self.version_path(version);
        
        std::fs::create_dir_all(&version_path)?;
        
        // Copy AppImage
        let dest = version_path.join(format!("Cursor-{}.AppImage", version));
        std::fs::copy(appimage_path, &dest)?;
        
        // Make executable
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&dest)?.permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&dest, perms)?;
        }

        Ok(())
    }

    pub fn uninstall(&self, version: &str, _keep_data: bool) -> Result<()> {
        let version_path = self.version_path(version);
        
        if version_path.exists() {
            std::fs::remove_dir_all(&version_path)?;
        }

        // If this was current, remove the link
        let current_link = self.config.install_dir.join("current");
        if current_link.is_symlink() {
            if let Ok(target) = std::fs::read_link(&current_link) {
                if target == version_path {
                    std::fs::remove_file(&current_link)?;
                }
            }
        }

        Ok(())
    }

    pub fn get_version_info(&self, version: &str) -> Result<VersionInfo> {
        let path = self.version_path(version);
        let installed = path.exists();
        
        let (disk_size_human, installed_at) = if installed {
            let size = calculate_dir_size(&path);
            let metadata = std::fs::metadata(&path)?;
            (format_size(size), format_time(metadata.modified()?))
        } else {
            ("N/A".into(), "N/A".into())
        };

        Ok(VersionInfo {
            installed,
            path,
            disk_size_human,
            installed_at,
            download_url: format!(
                "https://downloads.cursor.com/production/linux/x64/Cursor-{}.AppImage",
                version
            ),
        })
    }

    pub fn get_cleanup_candidates(&self, older_than: Option<u32>) -> Result<Vec<Version>> {
        let installed = self.list_installed()?;
        let current = self.current_version()?;
        
        let candidates: Vec<_> = installed
            .into_iter()
            .filter(|v| {
                // Never delete current version
                if Some(v) == current.as_ref() {
                    return false;
                }
                
                // Filter by age if specified
                if let Some(_days) = older_than {
                    // TODO: Implement age filtering
                    true
                } else {
                    true
                }
            })
            .collect();

        Ok(candidates)
    }

    fn version_path(&self, version: &str) -> PathBuf {
        self.config.install_dir.join(format!("cursor-{}", version))
    }
}

fn calculate_dir_size(path: &PathBuf) -> u64 {
    WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}

pub fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

fn format_time(time: std::time::SystemTime) -> String {
    use std::time::UNIX_EPOCH;
    let secs = time.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    // Simple formatting - in production use chrono
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
    fn test_format_size_bytes() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1023), "1023 B");
    }

    #[test]
    fn test_format_size_kilobytes() {
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1536), "1.5 KB");
        assert_eq!(format_size(10240), "10.0 KB");
    }

    #[test]
    fn test_format_size_megabytes() {
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(1024 * 1024 * 10), "10.0 MB");
        assert_eq!(format_size(1024 * 1024 * 100), "100.0 MB");
    }

    #[test]
    fn test_format_size_gigabytes() {
        assert_eq!(format_size(1024 * 1024 * 1024), "1.0 GB");
        assert_eq!(format_size(1024 * 1024 * 1024 * 2), "2.0 GB");
    }

    #[test]
    fn test_version_disk_size_human() {
        let version = Version {
            version: "2.1.34".to_string(),
            path: PathBuf::from("/test"),
            disk_size: 1024 * 1024 * 150, // 150 MB
            installed_at: "0".to_string(),
        };
        assert_eq!(version.disk_size_human(), "150.0 MB");
    }

    #[test]
    fn test_version_serialization() {
        let version = Version {
            version: "2.1.34".to_string(),
            path: PathBuf::from("/test/path"),
            disk_size: 1024,
            installed_at: "12345".to_string(),
        };
        
        let json = serde_json::to_string(&version).unwrap();
        let parsed: Version = serde_json::from_str(&json).unwrap();
        
        assert_eq!(version.version, parsed.version);
        assert_eq!(version.path, parsed.path);
        assert_eq!(version.disk_size, parsed.disk_size);
    }

    #[test]
    fn test_list_installed_empty() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let versions = manager.list_installed().unwrap();
        assert!(versions.is_empty());
    }

    #[test]
    fn test_list_installed_with_versions() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create version directories
        let versions_dir = temp_dir.path().join("versions");
        std::fs::create_dir_all(&versions_dir).unwrap();
        std::fs::create_dir_all(versions_dir.join("cursor-2.1.34")).unwrap();
        std::fs::create_dir_all(versions_dir.join("cursor-2.0.77")).unwrap();
        std::fs::create_dir_all(versions_dir.join("other-dir")).unwrap(); // Should be ignored
        
        let manager = VersionManager::with_config(config);
        let versions = manager.list_installed().unwrap();
        
        assert_eq!(versions.len(), 2);
        // Versions should be sorted descending
        assert_eq!(versions[0].version, "2.1.34");
        assert_eq!(versions[1].version, "2.0.77");
    }

    #[test]
    fn test_is_installed() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        let versions_dir = temp_dir.path().join("versions");
        std::fs::create_dir_all(versions_dir.join("cursor-2.1.34")).unwrap();
        
        let manager = VersionManager::with_config(config);
        
        assert!(manager.is_installed("2.1.34").unwrap());
        assert!(!manager.is_installed("2.0.77").unwrap());
    }

    #[test]
    fn test_get_version_info_not_installed() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let info = manager.get_version_info("2.1.34").unwrap();
        assert!(!info.installed);
        assert_eq!(info.disk_size_human, "N/A");
        assert!(info.download_url.contains("2.1.34"));
    }

    #[test]
    fn test_get_version_info_installed() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        let versions_dir = temp_dir.path().join("versions");
        let version_dir = versions_dir.join("cursor-2.1.34");
        std::fs::create_dir_all(&version_dir).unwrap();
        
        // Create a test file
        std::fs::write(version_dir.join("test.txt"), "test content").unwrap();
        
        let manager = VersionManager::with_config(config);
        let info = manager.get_version_info("2.1.34").unwrap();
        
        assert!(info.installed);
        assert_ne!(info.disk_size_human, "N/A");
    }

    #[tokio::test]
    async fn test_resolve_version_latest() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let resolved = manager.resolve_version("latest").await.unwrap();
        assert_eq!(resolved, "2.1.34");
    }

    #[tokio::test]
    async fn test_resolve_version_stable() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let resolved = manager.resolve_version("stable").await.unwrap();
        assert_eq!(resolved, "2.1.34");
    }

    #[tokio::test]
    async fn test_resolve_version_specific() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let resolved = manager.resolve_version("2.0.77").await.unwrap();
        assert_eq!(resolved, "2.0.77");
    }

    #[tokio::test]
    async fn test_list_available() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let manager = VersionManager::with_config(config);
        
        let available = manager.list_available().await.unwrap();
        assert!(!available.is_empty());
        assert!(available.contains(&"2.1.34".to_string()));
    }

    #[test]
    fn test_install_and_uninstall() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create versions directory
        std::fs::create_dir_all(&config.install_dir).unwrap();
        
        // Create a fake AppImage
        let appimage_path = temp_dir.path().join("Cursor.AppImage");
        std::fs::write(&appimage_path, "fake appimage content").unwrap();
        
        let manager = VersionManager::with_config(config.clone());
        
        // Install
        manager.install("2.1.34", &appimage_path).unwrap();
        assert!(manager.is_installed("2.1.34").unwrap());
        
        // Verify file exists
        let installed_appimage = config.install_dir
            .join("cursor-2.1.34")
            .join("Cursor-2.1.34.AppImage");
        assert!(installed_appimage.exists());
        
        // Uninstall
        manager.uninstall("2.1.34", false).unwrap();
        assert!(!manager.is_installed("2.1.34").unwrap());
    }

    #[test]
    fn test_set_current() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create version directory
        let versions_dir = temp_dir.path().join("versions");
        std::fs::create_dir_all(versions_dir.join("cursor-2.1.34")).unwrap();
        
        let manager = VersionManager::with_config(config);
        
        // Set current
        manager.set_current("2.1.34").unwrap();
        
        // Verify symlink exists
        let current_link = temp_dir.path().join("versions").join("current");
        assert!(current_link.is_symlink());
    }

    #[test]
    fn test_set_current_not_installed() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        std::fs::create_dir_all(&config.install_dir).unwrap();
        
        let manager = VersionManager::with_config(config);
        
        // Should fail for non-installed version
        let result = manager.set_current("2.1.34");
        assert!(result.is_err());
    }

    #[test]
    fn test_get_cleanup_candidates() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create version directories
        let versions_dir = temp_dir.path().join("versions");
        std::fs::create_dir_all(versions_dir.join("cursor-2.1.34")).unwrap();
        std::fs::create_dir_all(versions_dir.join("cursor-2.0.77")).unwrap();
        std::fs::create_dir_all(versions_dir.join("cursor-1.7.59")).unwrap();
        
        let manager = VersionManager::with_config(config);
        
        // All versions should be candidates (no current set)
        let candidates = manager.get_cleanup_candidates(None).unwrap();
        assert_eq!(candidates.len(), 3);
    }

    #[test]
    fn test_cleanup_excludes_current() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create version directories
        let versions_dir = temp_dir.path().join("versions");
        std::fs::create_dir_all(versions_dir.join("cursor-2.1.34")).unwrap();
        std::fs::create_dir_all(versions_dir.join("cursor-2.0.77")).unwrap();
        
        let manager = VersionManager::with_config(config);
        
        // Set current version
        manager.set_current("2.1.34").unwrap();
        
        // Current version should be excluded from cleanup
        let candidates = manager.get_cleanup_candidates(None).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].version, "2.0.77");
    }
}
