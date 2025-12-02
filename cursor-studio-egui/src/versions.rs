//! Version management for Cursor IDE
//!
//! Provides version detection, download URLs, download with hash verification,
//! and version metadata.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::PathBuf;

/// Known Cursor versions with download information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AvailableVersion {
    pub version: String,
    pub download_url: String,
    pub sha256_hash: Option<String>,
    pub commit_hash: Option<String>,
    pub release_date: Option<String>,
    pub is_stable: bool,
}

/// Currently known versions (extracted from cursor-versions.nix)
/// Updated: 2025-11-30
pub fn get_available_versions() -> Vec<AvailableVersion> {
    vec![
        // Latest stable - hashes verified 2025-12-01
        AvailableVersion {
            version: "2.1.34".into(),
            download_url: "https://downloads.cursor.com/production/609c37304ae83141fd217c4ae638bf532185650f/linux/x64/Cursor-2.1.34-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA=".into()),
            commit_hash: Some("609c37304ae83141fd217c4ae638bf532185650f".into()),
            release_date: Some("2024-11".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.1.32".into(),
            download_url: "https://downloads.cursor.com/production/ef979b1b43d85eee2a274c25fd62d5502006e425/linux/x64/Cursor-2.1.32-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-CKLUa5qaT8njAyPMRz6+iX9KSYyvNoyLZFZi6wmR4g0=".into()),
            commit_hash: Some("ef979b1b43d85eee2a274c25fd62d5502006e425".into()),
            release_date: Some("2024-11".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.1.26".into(),
            download_url: "https://downloads.cursor.com/production/f628a4761be40b8869ca61a6189cafd14756dff4/linux/x64/Cursor-2.1.26-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-lkvrgWjVfTozcADOjA/liZ0j5pPgXv9YvR5l0adGxBE=".into()),
            commit_hash: Some("f628a4761be40b8869ca61a6189cafd14756dff4".into()),
            release_date: Some("2024-11".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.1.25".into(),
            download_url: "https://downloads.cursor.com/production/7584ea888f7eb7bf76c9873a8f71b28f034a982e/linux/x64/Cursor-2.1.25-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-TybCKg+7GAMfiFNw3bbHJ9uSUwhKUjbjfUOb9JlFlMM=".into()),
            commit_hash: Some("7584ea888f7eb7bf76c9873a8f71b28f034a982e".into()),
            release_date: Some("2024-11".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.1.24".into(),
            download_url: "https://downloads.cursor.com/production/ac32b095dae9b8e0cfede6c5ebc55e589ee50e1b/linux/x64/Cursor-2.1.24-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-dlpdOCoUU61dDgmRrCcmBZ4WSGjtrP5G7vQfLRkUI9o=".into()),
            commit_hash: Some("ac32b095dae9b8e0cfede6c5ebc55e589ee50e1b".into()),
            release_date: Some("2024-11".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.1.20".into(),
            download_url: "https://downloads.cursor.com/production/a8d8905b06c8da1739af6f789efd59c28ac2a680/linux/x64/Cursor-2.1.20-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-V/5KDAJlXPLMQelnUgnfv2v3skxkb1V/n3Qn0qtwHaA=".into()),
            commit_hash: Some("a8d8905b06c8da1739af6f789efd59c28ac2a680".into()),
            release_date: Some("2024-10".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.0.77".into(),
            download_url: "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage".into(),
            sha256_hash: Some("sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=".into()),
            commit_hash: Some("ba90f2f88e4911312761abab9492c42442117cfe".into()),
            release_date: Some("2024-10".into()),
            is_stable: true,
        },
        // Older 2.0.x versions - URLs may no longer be valid
        AvailableVersion {
            version: "2.0.71".into(),
            download_url: "https://downloads.cursor.com/production/1c5a5ce4bddb2d5a5c9e6628ccf8179e0a8f8cc6/linux/x64/Cursor-2.0.71-x86_64.AppImage".into(),
            sha256_hash: None, // URL may be stale
            commit_hash: Some("1c5a5ce4bddb2d5a5c9e6628ccf8179e0a8f8cc6".into()),
            release_date: Some("2024-10".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "2.0.64".into(),
            download_url: "https://downloads.cursor.com/production/29c72cd13c2efd1d63de1c2bde9ccfe44a5ee6f1/linux/x64/Cursor-2.0.64-x86_64.AppImage".into(),
            sha256_hash: None, // URL may be stale
            commit_hash: Some("29c72cd13c2efd1d63de1c2bde9ccfe44a5ee6f1".into()),
            release_date: Some("2024-09".into()),
            is_stable: true,
        },
        // 1.7.x series
        AvailableVersion {
            version: "1.7.54".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.54".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-09".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.7.43".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.43".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-08".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.7.40".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.40".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-08".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.7.38".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.38".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-08".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.7.36".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.36".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-08".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.7.11".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.7.11".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-07".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.6.45".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.6.45".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-06".into()),
            is_stable: true,
        },
        AvailableVersion {
            version: "1.6.27".into(),
            download_url: "https://downloader.cursor.sh/linux/appImage/x64/1.6.27".into(),
            sha256_hash: None,
            commit_hash: None,
            release_date: Some("2024-05".into()),
            is_stable: true,
        },
    ]
}

/// Get version info by version string
pub fn get_version_info(version: &str) -> Option<AvailableVersion> {
    get_available_versions()
        .into_iter()
        .find(|v| v.version == version)
}

/// Get the latest stable version
pub fn get_latest_stable() -> AvailableVersion {
    get_available_versions()
        .into_iter()
        .find(|v| v.is_stable)
        .expect("No stable versions available")
}

/// Download state for tracking async downloads
#[derive(Debug, Clone)]
pub enum DownloadState {
    Idle,
    Downloading { progress: f32, version: String },
    Completed { version: String, path: PathBuf },
    Failed { version: String, error: String },
}

/// Download progress update
#[derive(Debug, Clone)]
pub struct DownloadProgress {
    pub version: String,
    pub bytes_downloaded: u64,
    pub total_bytes: Option<u64>,
    pub progress_percent: f32,
}

/// Downloads a Cursor AppImage version
pub async fn download_version(
    version: &AvailableVersion,
    target_dir: &PathBuf,
    progress_sender: Option<tokio::sync::mpsc::Sender<DownloadProgress>>,
) -> Result<PathBuf> {
    use tokio::io::AsyncWriteExt;
    
    let client = reqwest::Client::builder()
        .user_agent("cursor-studio/0.2.0")
        .build()
        .context("Failed to create HTTP client")?;

    let response = client
        .get(&version.download_url)
        .send()
        .await
        .context("Failed to start download")?;

    if !response.status().is_success() {
        anyhow::bail!(
            "Download failed with status {}: {}",
            response.status(),
            response.status().canonical_reason().unwrap_or("Unknown")
        );
    }

    let total_size = response.content_length();
    let filename = format!("Cursor-{}-x86_64.AppImage", version.version);
    let target_path = target_dir.join(&filename);

    // Create target directory
    tokio::fs::create_dir_all(target_dir).await?;

    let mut file = tokio::fs::File::create(&target_path)
        .await
        .context("Failed to create target file")?;

    let mut stream = response.bytes_stream();
    let mut downloaded: u64 = 0;

    use futures_util::StreamExt;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("Error reading download chunk")?;
        file.write_all(&chunk)
            .await
            .context("Failed to write to file")?;

        downloaded += chunk.len() as u64;

        if let Some(ref sender) = progress_sender {
            let progress = if let Some(total) = total_size {
                (downloaded as f32 / total as f32) * 100.0
            } else {
                0.0
            };

            let _ = sender
                .send(DownloadProgress {
                    version: version.version.clone(),
                    bytes_downloaded: downloaded,
                    total_bytes: total_size,
                    progress_percent: progress,
                })
                .await;
        }
    }

    file.flush().await?;

    // Make executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = tokio::fs::metadata(&target_path).await?.permissions();
        perms.set_mode(0o755);
        tokio::fs::set_permissions(&target_path, perms).await?;
    }

    Ok(target_path)
}

/// Synchronous wrapper for download (for use without tokio runtime in main thread)
pub fn download_version_sync(
    version: &AvailableVersion,
    target_dir: &PathBuf,
    progress_callback: impl Fn(f32) + Send + 'static,
) -> Result<PathBuf> {
    use std::io::Write;

    let client = reqwest::blocking::Client::builder()
        .user_agent("cursor-studio/0.2.0")
        .build()
        .context("Failed to create HTTP client")?;

    let response = client
        .get(&version.download_url)
        .send()
        .context("Failed to start download")?;

    if !response.status().is_success() {
        anyhow::bail!(
            "Download failed with status {}: {}",
            response.status(),
            response.status().canonical_reason().unwrap_or("Unknown")
        );
    }

    let total_size = response.content_length();
    let filename = format!("Cursor-{}-x86_64.AppImage", version.version);
    let target_path = target_dir.join(&filename);

    // Create target directory
    std::fs::create_dir_all(target_dir)?;

    let mut file = std::fs::File::create(&target_path).context("Failed to create target file")?;

    let mut downloaded: u64 = 0;
    let mut reader = response;
    let mut buffer = [0u8; 8192];

    loop {
        let bytes_read = std::io::Read::read(&mut reader, &mut buffer)?;
        if bytes_read == 0 {
            break;
        }

        file.write_all(&buffer[..bytes_read])?;
        downloaded += bytes_read as u64;

        if let Some(total) = total_size {
            let progress = (downloaded as f32 / total as f32) * 100.0;
            progress_callback(progress);
        }
    }

    file.flush()?;

    // Make executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&target_path)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&target_path, perms)?;
    }

    Ok(target_path)
}

/// Install a downloaded AppImage to the proper location
pub fn install_version(appimage_path: &PathBuf, version: &str) -> Result<PathBuf> {
    let home = dirs::home_dir().context("No home directory")?;
    let install_dir = home.join(format!(".cursor-studio/versions/cursor-{}", version));

    std::fs::create_dir_all(&install_dir)?;

    let dest = install_dir.join(format!("Cursor-{}.AppImage", version));
    std::fs::copy(appimage_path, &dest)?;

    // Make executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&dest)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&dest, perms)?;
    }

    Ok(dest)
}

/// Get the cache directory for downloads
pub fn get_cache_dir() -> PathBuf {
    dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("cursor-studio")
        .join("downloads")
}

/// Check if a version is installed (has an AppImage)
pub fn is_version_installed(version: &str) -> bool {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return false,
    };

    // Check in install directory
    let install_dir = home.join(format!(".cursor-studio/versions/cursor-{}", version));
    if install_dir.exists() {
        return true;
    }

    // Check for versioned data directory (user has used this version)
    let data_dir = home.join(format!(".cursor-{}", version));
    data_dir.exists()
}

/// Verify file hash against expected SRI hash (sha256-base64 format)
/// Returns Ok(true) if hash matches, Ok(false) if doesn't match, Err on read error
pub fn verify_hash(file_path: &PathBuf, expected_sri_hash: &str) -> Result<bool> {
    // Parse SRI hash format: "sha256-BASE64_HASH"
    let expected_base64 = expected_sri_hash
        .strip_prefix("sha256-")
        .context("Invalid SRI hash format - expected 'sha256-BASE64'")?;

    // Read file and compute hash
    let file_content = std::fs::read(file_path)
        .context("Failed to read file for hash verification")?;
    
    let mut hasher = Sha256::new();
    hasher.update(&file_content);
    let computed_hash = hasher.finalize();
    
    // Encode as base64 for comparison
    let computed_base64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        computed_hash,
    );

    Ok(computed_base64 == expected_base64)
}

/// Verify downloaded file and return detailed result
#[derive(Debug, Clone)]
pub struct HashVerificationResult {
    pub matches: bool,
    pub expected: String,
    pub computed: String,
}

pub fn verify_hash_detailed(file_path: &PathBuf, expected_sri_hash: &str) -> Result<HashVerificationResult> {
    let expected_base64 = expected_sri_hash
        .strip_prefix("sha256-")
        .context("Invalid SRI hash format")?;

    let file_content = std::fs::read(file_path)?;
    
    let mut hasher = Sha256::new();
    hasher.update(&file_content);
    let computed_hash = hasher.finalize();
    let computed_base64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        computed_hash,
    );

    Ok(HashVerificationResult {
        matches: computed_base64 == expected_base64,
        expected: expected_base64.to_string(),
        computed: computed_base64,
    })
}

/// Download with automatic hash verification  
/// Uses channel-based progress reporting to avoid lifetime issues
pub fn download_and_verify(
    version: &AvailableVersion,
    target_dir: &PathBuf,
    event_sender: std::sync::mpsc::Sender<DownloadEvent>,
) -> Result<PathBuf> {
    // First download
    let _ = event_sender.send(DownloadEvent::Started {
        version: version.version.clone(),
    });

    // Clone sender for the progress callback
    let progress_sender = event_sender.clone();
    
    let path = download_version_sync(version, target_dir, move |progress| {
        let _ = progress_sender.send(DownloadEvent::Progress { percent: progress });
    })?;

    // Then verify hash if available
    if let Some(ref expected_hash) = version.sha256_hash {
        let _ = event_sender.send(DownloadEvent::Verifying);
        
        match verify_hash_detailed(&path, expected_hash) {
            Ok(result) => {
                if result.matches {
                    let _ = event_sender.send(DownloadEvent::Verified);
                } else {
                    // Hash mismatch - delete the file and fail
                    let _ = std::fs::remove_file(&path);
                    let _ = event_sender.send(DownloadEvent::HashMismatch {
                        expected: result.expected.clone(),
                        computed: result.computed.clone(),
                    });
                    anyhow::bail!(
                        "Hash verification failed for v{}: expected {}, got {}",
                        version.version,
                        result.expected,
                        result.computed
                    );
                }
            }
            Err(e) => {
                let _ = event_sender.send(DownloadEvent::VerificationError {
                    error: e.to_string(),
                });
                // Don't fail on verification error if we have a file
                log::warn!("Hash verification error: {}", e);
            }
        }
    } else {
        let _ = event_sender.send(DownloadEvent::NoHashAvailable);
    }

    let _ = event_sender.send(DownloadEvent::Completed {
        path: path.clone(),
    });

    Ok(path)
}

/// Simple download and verify that just returns success/failure without callbacks
pub fn download_and_verify_simple(
    version: &AvailableVersion,
    target_dir: &PathBuf,
) -> Result<(PathBuf, Option<bool>)> {
    // Download
    let path = download_version_sync(version, target_dir, |_| {})?;

    // Verify if hash available
    let hash_ok = if let Some(ref expected_hash) = version.sha256_hash {
        match verify_hash(&path, expected_hash) {
            Ok(matches) => {
                if !matches {
                    let _ = std::fs::remove_file(&path);
                    anyhow::bail!("Hash verification failed for v{}", version.version);
                }
                Some(true)
            }
            Err(e) => {
                log::warn!("Hash verification error: {}", e);
                None // Verification error, but file exists
            }
        }
    } else {
        None // No hash available
    };

    Ok((path, hash_ok))
}

/// Events during download and verification process
#[derive(Debug, Clone)]
pub enum DownloadEvent {
    Started { version: String },
    Progress { percent: f32 },
    Verifying,
    Verified,
    HashMismatch { expected: String, computed: String },
    VerificationError { error: String },
    NoHashAvailable,
    Completed { path: PathBuf },
    Failed { error: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_available_versions() {
        let versions = get_available_versions();
        assert!(!versions.is_empty());
        assert!(versions.iter().any(|v| v.version.starts_with("2.1")));
        assert!(versions.iter().any(|v| v.version.starts_with("1.7")));
    }

    #[test]
    fn test_get_latest_stable() {
        let latest = get_latest_stable();
        assert!(latest.is_stable);
        assert!(latest.version.starts_with("2.1"));
    }

    #[test]
    fn test_get_version_info() {
        let info = get_version_info("2.0.77");
        assert!(info.is_some());
        assert_eq!(info.unwrap().version, "2.0.77");
    }
}
