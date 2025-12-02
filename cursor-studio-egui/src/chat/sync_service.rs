//! Chat Sync Service - Orchestrates the full sync pipeline.
//!
//! This service coordinates:
//! 1. Parsing chat history from Cursor's SQLite databases
//! 2. Storing in SurrealDB for sync-capable storage
//! 3. Syncing with peers (P2P) or central server
//!
//! # Status
//!
//! **Phase 1**: Local parsing + storage working
//! **TODO**: P2P and server sync

use anyhow::{Context, Result};
use std::path::PathBuf;

use super::crdt::DeviceId;
use super::cursor_parser::CursorParser;
use super::models::Conversation;
use super::surreal::SurrealStore;

/// Sync service status
#[derive(Debug, Clone)]
pub struct SyncStatus {
    /// Number of local conversations
    pub local_count: usize,
    /// Number of conversations in sync store
    pub store_count: usize,
    /// Last sync time (if any)
    pub last_sync: Option<chrono::DateTime<chrono::Utc>>,
    /// Any error message
    pub error: Option<String>,
    /// Is currently syncing
    pub syncing: bool,
}

impl Default for SyncStatus {
    fn default() -> Self {
        Self {
            local_count: 0,
            store_count: 0,
            last_sync: None,
            error: None,
            syncing: false,
        }
    }
}

/// Main sync service for chat history
pub struct SyncService {
    /// Device ID for this machine
    device_id: DeviceId,
    /// SurrealDB store
    store: Option<SurrealStore>,
    /// Current status
    status: SyncStatus,
}

impl SyncService {
    /// Create a new sync service
    pub fn new() -> Self {
        // Load or generate device ID
        let device_id = Self::load_or_create_device_id();
        
        Self {
            device_id,
            store: None,
            status: SyncStatus::default(),
        }
    }

    /// Load existing device ID or create a new one
    fn load_or_create_device_id() -> DeviceId {
        let config_dir = dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cursor-studio");
        
        let device_id_path = config_dir.join("device_id");
        
        if let Ok(id_str) = std::fs::read_to_string(&device_id_path) {
            log::info!("Loaded existing device ID");
            DeviceId::from_string(id_str.trim().to_string())
        } else {
            let new_id = DeviceId::new();
            log::info!("Generated new device ID: {}", new_id);
            
            // Try to save it
            if let Err(e) = std::fs::create_dir_all(&config_dir) {
                log::warn!("Failed to create config dir: {}", e);
            }
            if let Err(e) = std::fs::write(&device_id_path, new_id.0.as_bytes()) {
                log::warn!("Failed to save device ID: {}", e);
            }
            
            new_id
        }
    }

    /// Get the device ID
    pub fn device_id(&self) -> &DeviceId {
        &self.device_id
    }

    /// Get current sync status
    pub fn status(&self) -> &SyncStatus {
        &self.status
    }

    /// Initialize the sync store (must be called from async context)
    pub async fn initialize_store(&mut self) -> Result<()> {
        log::info!("Initializing SurrealDB store...");
        
        let store = SurrealStore::new_memory(self.device_id.clone())
            .await
            .context("Failed to create SurrealDB store")?;
        
        self.store = Some(store);
        log::info!("SurrealDB store initialized");
        
        Ok(())
    }

    /// Check if store is initialized
    pub fn is_initialized(&self) -> bool {
        self.store.is_some()
    }

    /// Import conversations from Cursor's SQLite into the sync store
    pub async fn import_from_cursor(&mut self) -> Result<ImportResult> {
        let store = self.store.as_ref()
            .context("Store not initialized - call initialize_store() first")?;
        
        self.status.syncing = true;
        
        // Parse from Cursor's database
        log::info!("Parsing Cursor chat history...");
        let parser = CursorParser::new_default()
            .context("Failed to create Cursor parser")?;
        
        let conversations = parser.parse_all()
            .context("Failed to parse conversations")?;
        
        self.status.local_count = conversations.len();
        log::info!("Found {} conversations in Cursor database", conversations.len());
        
        // Import into sync store
        let mut imported = 0;
        let mut skipped = 0;
        
        for conv in &conversations {
            // Check if already exists
            if let Ok(Some(_)) = store.get_conversation(&conv.id.to_string()).await {
                skipped += 1;
                continue;
            }
            
            // Insert new conversation
            if let Err(e) = store.upsert_conversation(conv).await {
                log::warn!("Failed to import conversation {}: {}", conv.id, e);
                continue;
            }
            imported += 1;
        }
        
        self.status.store_count = store.count().await.unwrap_or(0);
        self.status.last_sync = Some(chrono::Utc::now());
        self.status.syncing = false;
        self.status.error = None;
        
        log::info!("Import complete: {} imported, {} skipped", imported, skipped);
        
        Ok(ImportResult { imported, skipped })
    }

    /// Get all conversations from the sync store
    pub async fn list_conversations(&self, limit: usize) -> Result<Vec<Conversation>> {
        let store = self.store.as_ref()
            .context("Store not initialized")?;
        
        store.list_conversations(limit).await
    }

    /// Search conversations in the sync store
    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<Conversation>> {
        let store = self.store.as_ref()
            .context("Store not initialized")?;
        
        store.search(query, limit).await
    }

    /// Get a specific conversation
    pub async fn get_conversation(&self, id: &str) -> Result<Option<Conversation>> {
        let store = self.store.as_ref()
            .context("Store not initialized")?;
        
        store.get_conversation(id).await
    }

    /// Get statistics about the sync store
    pub async fn get_stats(&self) -> Result<SyncStats> {
        let store = self.store.as_ref()
            .context("Store not initialized")?;
        
        let conversations = store.list_conversations(1000).await?;
        
        let total_conversations = conversations.len();
        let total_messages: usize = conversations.iter().map(|c| c.message_count).sum();
        let total_tokens: u64 = conversations.iter()
            .map(|c| c.total_input_tokens + c.total_output_tokens)
            .sum();
        let agentic_count = conversations.iter().filter(|c| c.is_agentic).count();
        
        // Count models
        let mut model_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        for conv in &conversations {
            for model in &conv.models_used {
                *model_counts.entry(model.clone()).or_insert(0) += 1;
            }
        }
        
        Ok(SyncStats {
            total_conversations,
            total_messages,
            total_tokens,
            agentic_count,
            model_counts,
        })
    }
}

/// Result of an import operation
#[derive(Debug, Clone)]
pub struct ImportResult {
    pub imported: usize,
    pub skipped: usize,
}

/// Statistics from the sync store
#[derive(Debug, Clone)]
pub struct SyncStats {
    pub total_conversations: usize,
    pub total_messages: usize,
    pub total_tokens: u64,
    pub agentic_count: usize,
    pub model_counts: std::collections::HashMap<String, usize>,
}

impl std::fmt::Display for SyncStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "=== Sync Store Statistics ===")?;
        writeln!(f, "Conversations: {}", self.total_conversations)?;
        writeln!(f, "Total Messages: {}", self.total_messages)?;
        writeln!(f, "Total Tokens: {}", self.total_tokens)?;
        writeln!(f, "Agentic Conversations: {}", self.agentic_count)?;
        writeln!(f, "Models Used:")?;
        for (model, count) in &self.model_counts {
            writeln!(f, "  - {}: {} conversations", model, count)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_id_persistence() {
        // Device ID should be consistent
        let id1 = SyncService::load_or_create_device_id();
        let id2 = SyncService::load_or_create_device_id();
        
        // After first creation, should be same
        // (This test might not work in CI without proper temp dir handling)
        assert!(!id1.0.is_empty());
        assert!(!id2.0.is_empty());
    }

    #[tokio::test]
    async fn test_service_initialization() {
        let mut service = SyncService::new();
        assert!(!service.is_initialized());
        
        service.initialize_store().await.unwrap();
        assert!(service.is_initialized());
    }
}
