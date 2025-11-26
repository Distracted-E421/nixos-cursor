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

fn format_size(bytes: u64) -> String {
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
