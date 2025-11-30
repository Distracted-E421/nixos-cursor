//! Sync Client - HTTP client for communicating with the sync server.
//!
//! Provides methods to:
//! - Push local conversations to server
//! - Pull conversations from server
//! - Bidirectional sync

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::crdt::VectorClock;
use super::surreal::SyncedConversation;

/// Client configuration
#[derive(Debug, Clone)]
pub struct ClientConfig {
    /// Server URL
    pub server_url: String,
    /// Device ID for this client
    pub device_id: String,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            server_url: "http://localhost:8420".to_string(),
            device_id: String::new(),
        }
    }
}

/// Sync client for communicating with the server
pub struct SyncClient {
    config: ClientConfig,
    http_client: ureq::Agent,
}

/// Server health response
#[derive(Debug, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub device_id: String,
    pub conversations: usize,
}

/// API response wrapper
#[derive(Debug, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

/// Sync request
#[derive(Debug, Serialize)]
pub struct SyncRequest {
    pub device_id: String,
    pub vector_clock: Option<VectorClock>,
    pub conversations: Option<Vec<SyncedConversation>>,
}

/// Sync response
#[derive(Debug, Deserialize)]
pub struct SyncResponse {
    pub server_device_id: String,
    pub updated: usize,
    pub conversations: Vec<SyncedConversation>,
    pub server_clock: VectorClock,
}

impl SyncClient {
    /// Create a new sync client
    pub fn new(config: ClientConfig) -> Self {
        Self {
            config,
            http_client: ureq::Agent::new(),
        }
    }

    /// Check if the server is healthy
    pub fn health(&self) -> Result<HealthResponse> {
        let url = format!("{}/health", self.config.server_url);
        let response: ApiResponse<HealthResponse> = self.http_client
            .get(&url)
            .call()
            .context("Failed to connect to server")?
            .into_json()
            .context("Failed to parse response")?;

        response.data.context("Server returned error")
    }

    /// Get server stats
    pub fn stats(&self) -> Result<serde_json::Value> {
        let url = format!("{}/stats", self.config.server_url);
        let response: ApiResponse<serde_json::Value> = self.http_client
            .get(&url)
            .call()
            .context("Failed to connect to server")?
            .into_json()
            .context("Failed to parse response")?;

        response.data.context("Server returned error")
    }

    /// Pull conversations from the server
    pub fn pull(&self, limit: Option<usize>) -> Result<Vec<SyncedConversation>> {
        let url = format!(
            "{}/sync/pull?limit={}",
            self.config.server_url,
            limit.unwrap_or(100)
        );
        
        let response: ApiResponse<Vec<SyncedConversation>> = self.http_client
            .get(&url)
            .call()
            .context("Failed to connect to server")?
            .into_json()
            .context("Failed to parse response")?;

        response.data.context("Server returned error")
    }

    /// Push conversations to the server
    pub fn push(&self, conversations: Vec<SyncedConversation>) -> Result<serde_json::Value> {
        let url = format!("{}/sync/push", self.config.server_url);
        
        let response: ApiResponse<serde_json::Value> = self.http_client
            .post(&url)
            .send_json(&conversations)
            .context("Failed to connect to server")?
            .into_json()
            .context("Failed to parse response")?;

        response.data.context("Server returned error")
    }

    /// Full bidirectional sync
    pub fn sync(&self, conversations: Option<Vec<SyncedConversation>>) -> Result<SyncResponse> {
        let url = format!("{}/sync", self.config.server_url);
        
        let request = SyncRequest {
            device_id: self.config.device_id.clone(),
            vector_clock: None, // TODO: Track vector clock
            conversations,
        };

        let response: ApiResponse<SyncResponse> = self.http_client
            .post(&url)
            .send_json(&request)
            .context("Failed to connect to server")?
            .into_json()
            .context("Failed to parse response")?;

        response.data.context("Server returned error")
    }
}
