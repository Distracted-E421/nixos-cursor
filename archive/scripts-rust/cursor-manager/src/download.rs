//! Download management with progress reporting

use std::path::PathBuf;
use anyhow::{Context, Result};
use sha2::{Sha256, Digest};
use base64::Engine;

use crate::config::Config;

pub struct Downloader {
    config: Config,
    client: reqwest::Client,
}

impl Downloader {
    pub fn new() -> Result<Self> {
        let config = Config::load()?;
        let client = reqwest::Client::builder()
            .user_agent("cursor-manager/0.1.0")
            .build()?;
        
        Ok(Self { config, client })
    }

    /// Create a Downloader with a custom config (useful for testing)
    pub fn with_config(config: Config) -> Result<Self> {
        let client = reqwest::Client::builder()
            .user_agent("cursor-manager/0.1.0")
            .build()?;
        
        Ok(Self { config, client })
    }

    pub async fn download<F>(&self, version: &str, mut progress_callback: F) -> Result<PathBuf>
    where
        F: FnMut(u32),
    {
        let url = self.download_url(version);
        let filename = format!("Cursor-{}.AppImage", version);
        let cache_path = self.config.cache_dir.join(&filename);
        
        // Create cache directory
        std::fs::create_dir_all(&self.config.cache_dir)?;
        
        // Check if already cached
        if cache_path.exists() {
            tracing::info!("Using cached download: {}", cache_path.display());
            return Ok(cache_path);
        }

        // Download
        let response = self.client.get(&url)
            .send()
            .await
            .context("Failed to start download")?;
        
        let total_size = response.content_length().unwrap_or(0);
        let mut downloaded: u64 = 0;
        
        let mut file = std::fs::File::create(&cache_path)?;
        let mut stream = response.bytes_stream();
        
        use futures_util::StreamExt;
        use std::io::Write;
        
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.context("Error downloading chunk")?;
            file.write_all(&chunk)?;
            
            downloaded += chunk.len() as u64;
            if total_size > 0 {
                let progress = ((downloaded as f64 / total_size as f64) * 100.0) as u32;
                progress_callback(progress);
            }
        }

        Ok(cache_path)
    }

    pub async fn verify_hash(&self, path: &PathBuf, expected_hash: &str) -> Result<bool> {
        let content = std::fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let result = hasher.finalize();
        
        let computed_hash = format!(
            "sha256-{}",
            base64::engine::general_purpose::STANDARD.encode(result)
        );
        
        Ok(computed_hash == expected_hash)
    }

    /// Get the download URL for a version
    pub fn download_url(&self, version: &str) -> String {
        format!(
            "https://downloads.cursor.com/production/linux/x64/Cursor-{}.AppImage",
            version
        )
    }

    /// Compute SHA256 hash of a file (for verification)
    pub fn compute_hash(path: &PathBuf) -> Result<String> {
        let content = std::fs::read(path)?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        let result = hasher.finalize();
        
        Ok(format!(
            "sha256-{}",
            base64::engine::general_purpose::STANDARD.encode(result)
        ))
    }
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
    fn test_download_url_format() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let downloader = Downloader::with_config(config).unwrap();
        
        let url = downloader.download_url("2.1.34");
        assert_eq!(
            url,
            "https://downloads.cursor.com/production/linux/x64/Cursor-2.1.34.AppImage"
        );
    }

    #[test]
    fn test_download_url_various_versions() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let downloader = Downloader::with_config(config).unwrap();
        
        assert!(downloader.download_url("2.0.77").contains("2.0.77"));
        assert!(downloader.download_url("1.7.59").contains("1.7.59"));
        assert!(downloader.download_url("0.42.3").contains("0.42.3"));
    }

    #[test]
    fn test_compute_hash() {
        let temp_dir = TempDir::new().unwrap();
        let test_file = temp_dir.path().join("test.txt");
        
        // Write known content
        std::fs::write(&test_file, "hello world").unwrap();
        
        let hash = Downloader::compute_hash(&test_file).unwrap();
        
        // Verify it starts with sha256-
        assert!(hash.starts_with("sha256-"));
        
        // Should be consistent
        let hash2 = Downloader::compute_hash(&test_file).unwrap();
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_compute_hash_different_content() {
        let temp_dir = TempDir::new().unwrap();
        let file1 = temp_dir.path().join("file1.txt");
        let file2 = temp_dir.path().join("file2.txt");
        
        std::fs::write(&file1, "content1").unwrap();
        std::fs::write(&file2, "content2").unwrap();
        
        let hash1 = Downloader::compute_hash(&file1).unwrap();
        let hash2 = Downloader::compute_hash(&file2).unwrap();
        
        assert_ne!(hash1, hash2);
    }

    #[tokio::test]
    async fn test_verify_hash_correct() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let downloader = Downloader::with_config(config).unwrap();
        
        let test_file = temp_dir.path().join("test.txt");
        std::fs::write(&test_file, "test content").unwrap();
        
        // Compute the correct hash
        let correct_hash = Downloader::compute_hash(&test_file).unwrap();
        
        // Verify should return true
        let result = downloader.verify_hash(&test_file, &correct_hash).await.unwrap();
        assert!(result);
    }

    #[tokio::test]
    async fn test_verify_hash_incorrect() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        let downloader = Downloader::with_config(config).unwrap();
        
        let test_file = temp_dir.path().join("test.txt");
        std::fs::write(&test_file, "test content").unwrap();
        
        // Verify should return false for wrong hash
        let result = downloader.verify_hash(&test_file, "sha256-wronghash").await.unwrap();
        assert!(!result);
    }

    #[tokio::test]
    async fn test_download_uses_cache() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        // Create cache directory and fake cached file
        let cache_dir = temp_dir.path().join("cache");
        std::fs::create_dir_all(&cache_dir).unwrap();
        
        let cached_file = cache_dir.join("Cursor-2.1.34.AppImage");
        std::fs::write(&cached_file, "fake cached content").unwrap();
        
        let downloader = Downloader::with_config(config).unwrap();
        
        // Should return cached path without downloading
        let progress_count = std::cell::Cell::new(0);
        let result = downloader.download("2.1.34", |_| {
            progress_count.set(progress_count.get() + 1);
        }).await.unwrap();
        
        assert_eq!(result, cached_file);
        // No progress callbacks should have been called (used cache)
        assert_eq!(progress_count.get(), 0);
    }

    #[test]
    fn test_downloader_creation_with_config() {
        let temp_dir = TempDir::new().unwrap();
        let config = create_test_config(&temp_dir);
        
        let downloader = Downloader::with_config(config.clone());
        assert!(downloader.is_ok());
        
        let downloader = downloader.unwrap();
        assert_eq!(downloader.config.cache_dir, config.cache_dir);
    }
}
