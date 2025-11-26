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

    fn download_url(&self, version: &str) -> String {
        format!(
            "https://downloads.cursor.com/production/linux/x64/Cursor-{}.AppImage",
            version
        )
    }
}
