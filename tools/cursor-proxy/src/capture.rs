//! Payload capture for cursor-proxy
//!
//! Saves request and response payloads to disk for analysis.

use crate::error::ProxyResult;
use bytes::Bytes;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::sync::Semaphore;
use tracing::{debug, error, info, warn};

/// Maximum concurrent capture save operations
const MAX_CONCURRENT_SAVES: usize = 10;

/// Captured request/response pair
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapturedExchange {
    /// Unique ID
    pub id: String,
    /// Timestamp
    pub timestamp: DateTime<Utc>,
    /// Connection ID from proxy
    pub conn_id: u64,
    /// Request method
    pub method: String,
    /// Request path
    pub path: String,
    /// Request headers
    pub request_headers: Vec<(String, String)>,
    /// Request body (base64 encoded if binary)
    pub request_body: Option<CapturedBody>,
    /// Response status
    pub response_status: Option<u16>,
    /// Response headers
    pub response_headers: Option<Vec<(String, String)>>,
    /// Response body (base64 encoded if binary)  
    pub response_body: Option<CapturedBody>,
    /// Duration in milliseconds
    pub duration_ms: Option<u64>,
}

/// Captured body content
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapturedBody {
    /// Content type
    pub content_type: Option<String>,
    /// Size in bytes
    pub size: usize,
    /// Body content (text or base64)
    pub data: String,
    /// Whether data is base64 encoded
    pub is_base64: bool,
    /// Whether body was truncated
    pub truncated: bool,
}

/// Payload capturer
#[derive(Clone)]
pub struct PayloadCapturer {
    /// Directory to store captures
    capture_dir: PathBuf,
    /// Maximum payload size to capture
    max_size: usize,
    /// Whether capture is enabled
    enabled: bool,
    /// Semaphore to limit concurrent save operations
    save_semaphore: Arc<Semaphore>,
    /// Counter for pending saves (for monitoring)
    pending_saves: Arc<AtomicU64>,
    /// Retention period in days
    retention_days: u32,
}

impl PayloadCapturer {
    /// Create a new capturer
    pub fn new(capture_dir: impl AsRef<Path>, max_size: usize, enabled: bool) -> ProxyResult<Self> {
        Self::with_retention(capture_dir, max_size, enabled, 7)
    }
    
    /// Create a new capturer with custom retention
    pub fn with_retention(capture_dir: impl AsRef<Path>, max_size: usize, enabled: bool, retention_days: u32) -> ProxyResult<Self> {
        let capture_dir = capture_dir.as_ref().to_path_buf();
        
        if enabled {
            // Create capture directory
            fs::create_dir_all(&capture_dir)?;
            info!("Payload capture enabled: {:?} (max {}KB, retention {}d)", 
                  capture_dir, max_size / 1024, retention_days);
        }
        
        Ok(Self {
            capture_dir,
            max_size,
            enabled,
            save_semaphore: Arc::new(Semaphore::new(MAX_CONCURRENT_SAVES)),
            pending_saves: Arc::new(AtomicU64::new(0)),
            retention_days,
        })
    }
    
    /// Get number of pending save operations
    pub fn pending_saves(&self) -> u64 {
        self.pending_saves.load(Ordering::Relaxed)
    }
    
    /// Check if capture is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }
    
    /// Start a new capture for a request
    pub fn start_capture(&self, conn_id: u64, method: &str, path: &str) -> Option<ExchangeBuilder> {
        if !self.enabled {
            return None;
        }
        
        Some(ExchangeBuilder::new(conn_id, method, path))
    }
    
    /// Save a completed exchange (rate-limited to prevent memory accumulation)
    pub async fn save(&self, exchange: CapturedExchange) -> ProxyResult<PathBuf> {
        if !self.enabled {
            return Err(crate::error::ProxyError::Internal("Capture not enabled".into()));
        }
        
        // Acquire semaphore permit (blocks if too many concurrent saves)
        let _permit = self.save_semaphore.acquire().await
            .map_err(|_| crate::error::ProxyError::Internal("Save semaphore closed".into()))?;
        
        self.pending_saves.fetch_add(1, Ordering::Relaxed);
        let result = self.save_inner(exchange).await;
        self.pending_saves.fetch_sub(1, Ordering::Relaxed);
        
        result
    }
    
    /// Inner save implementation
    async fn save_inner(&self, exchange: CapturedExchange) -> ProxyResult<PathBuf> {
        // Create filename: YYYY-MM-DD_HH-MM-SS_connid_service_method.json
        let service = extract_service(&exchange.path);
        let method_name = extract_method(&exchange.path);
        let filename = format!(
            "{}_{:06}_{}.json",
            exchange.timestamp.format("%Y-%m-%d_%H-%M-%S"),
            exchange.conn_id,
            sanitize_filename(&format!("{}_{}", service, method_name))
        );
        
        let filepath = self.capture_dir.join(&filename);
        
        // Serialize to JSON
        let json = serde_json::to_string_pretty(&exchange)?;
        
        // Write to file
        let mut file = tokio::fs::File::create(&filepath).await?;
        file.write_all(json.as_bytes()).await?;
        file.flush().await?;
        
        debug!("Captured: {}", filename);
        Ok(filepath)
    }
    
    /// Clean up old captures based on retention policy
    pub fn cleanup_old_captures(&self) -> ProxyResult<usize> {
        if !self.enabled || self.retention_days == 0 {
            return Ok(0);
        }
        
        let cutoff = chrono::Utc::now() - chrono::Duration::days(self.retention_days as i64);
        let mut removed = 0;
        
        if let Ok(entries) = fs::read_dir(&self.capture_dir) {
            for entry in entries.flatten() {
                if let Ok(metadata) = entry.metadata() {
                    if let Ok(modified) = metadata.modified() {
                        let modified_dt: DateTime<Utc> = modified.into();
                        if modified_dt < cutoff {
                            if fs::remove_file(entry.path()).is_ok() {
                                removed += 1;
                            }
                        }
                    }
                }
            }
        }
        
        if removed > 0 {
            info!("Cleaned up {} old capture files", removed);
        }
        
        Ok(removed)
    }
    
    /// Capture a body, respecting size limits
    pub fn capture_body(&self, body: &Bytes, content_type: Option<&str>) -> Option<CapturedBody> {
        if !self.enabled {
            return None;
        }
        
        let size = body.len();
        let truncated = size > self.max_size;
        let data_to_capture = if truncated {
            &body[..self.max_size]
        } else {
            &body[..]
        };
        
        // Determine if we should base64 encode (binary content)
        let is_binary = is_binary_content(content_type, data_to_capture);
        
        let (data, is_base64) = if is_binary {
            (base64::Engine::encode(&base64::engine::general_purpose::STANDARD, data_to_capture), true)
        } else {
            (String::from_utf8_lossy(data_to_capture).to_string(), false)
        };
        
        Some(CapturedBody {
            content_type: content_type.map(String::from),
            size,
            data,
            is_base64,
            truncated,
        })
    }
    
    /// List recent captures
    pub fn list_captures(&self, limit: usize) -> ProxyResult<Vec<PathBuf>> {
        let mut files: Vec<_> = fs::read_dir(&self.capture_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map_or(false, |ext| ext == "json"))
            .collect();
        
        // Sort by modification time (newest first)
        files.sort_by(|a, b| {
            let a_time = a.metadata().and_then(|m| m.modified()).ok();
            let b_time = b.metadata().and_then(|m| m.modified()).ok();
            b_time.cmp(&a_time)
        });
        
        Ok(files.into_iter().take(limit).map(|e| e.path()).collect())
    }
    
    /// Get capture statistics
    pub fn stats(&self) -> ProxyResult<CaptureStats> {
        let files: Vec<_> = fs::read_dir(&self.capture_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map_or(false, |ext| ext == "json"))
            .collect();
        
        let total_size: u64 = files.iter()
            .filter_map(|e| e.metadata().ok())
            .map(|m| m.len())
            .sum();
        
        Ok(CaptureStats {
            total_files: files.len(),
            total_size_bytes: total_size,
        })
    }
}

/// Statistics about captures
#[derive(Debug)]
pub struct CaptureStats {
    pub total_files: usize,
    pub total_size_bytes: u64,
}

/// Builder for constructing a captured exchange
pub struct ExchangeBuilder {
    exchange: CapturedExchange,
    start_time: std::time::Instant,
}

impl ExchangeBuilder {
    fn new(conn_id: u64, method: &str, path: &str) -> Self {
        Self {
            exchange: CapturedExchange {
                id: uuid::Uuid::new_v4().to_string(),
                timestamp: Utc::now(),
                conn_id,
                method: method.to_string(),
                path: path.to_string(),
                request_headers: Vec::new(),
                request_body: None,
                response_status: None,
                response_headers: None,
                response_body: None,
                duration_ms: None,
            },
            start_time: std::time::Instant::now(),
        }
    }
    
    /// Add request headers
    pub fn request_headers(mut self, headers: Vec<(String, String)>) -> Self {
        self.exchange.request_headers = headers;
        self
    }
    
    /// Add request body
    pub fn request_body(mut self, body: Option<CapturedBody>) -> Self {
        self.exchange.request_body = body;
        self
    }
    
    /// Add response status
    pub fn response_status(mut self, status: u16) -> Self {
        self.exchange.response_status = Some(status);
        self
    }
    
    /// Add response headers
    pub fn response_headers(mut self, headers: Vec<(String, String)>) -> Self {
        self.exchange.response_headers = Some(headers);
        self
    }
    
    /// Add response body
    pub fn response_body(mut self, body: Option<CapturedBody>) -> Self {
        self.exchange.response_body = body;
        self
    }
    
    /// Finalize and get the exchange
    pub fn build(mut self) -> CapturedExchange {
        self.exchange.duration_ms = Some(self.start_time.elapsed().as_millis() as u64);
        self.exchange
    }
}

/// Extract gRPC service name from path
fn extract_service(path: &str) -> &str {
    // Path format: /aiserver.v1.ChatService/MethodName
    path.split('/').nth(1).unwrap_or("unknown")
}

/// Extract method name from path
fn extract_method(path: &str) -> &str {
    // Path format: /aiserver.v1.ChatService/MethodName
    path.split('/').last().unwrap_or("unknown")
}

/// Sanitize filename
fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' || c == '.' { c } else { '_' })
        .collect()
}

/// Check if content appears to be binary
fn is_binary_content(content_type: Option<&str>, data: &[u8]) -> bool {
    // Check content type first
    if let Some(ct) = content_type {
        if ct.contains("text/") || ct.contains("application/json") || ct.contains("application/grpc") {
            return false;
        }
        if ct.contains("image/") || ct.contains("audio/") || ct.contains("video/") || ct.contains("octet-stream") {
            return true;
        }
    }
    
    // Check for null bytes or high byte count
    let high_bytes = data.iter().take(1024).filter(|&&b| b < 32 && b != b'\n' && b != b'\r' && b != b'\t').count();
    high_bytes > 10
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_extract_service() {
        assert_eq!(extract_service("/aiserver.v1.ChatService/StreamChat"), "aiserver.v1.ChatService");
        assert_eq!(extract_service("/aiserver.v1.AiService/CheckStatus"), "aiserver.v1.AiService");
    }
    
    #[test]
    fn test_extract_method() {
        assert_eq!(extract_method("/aiserver.v1.ChatService/StreamChat"), "StreamChat");
        assert_eq!(extract_method("/aiserver.v1.AiService/CheckStatus"), "CheckStatus");
    }
    
    #[test]
    fn test_sanitize_filename() {
        assert_eq!(sanitize_filename("ChatService/Method"), "ChatService_Method");
        assert_eq!(sanitize_filename("hello:world"), "hello_world");
    }
}

