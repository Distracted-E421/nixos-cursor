//! Parser for Cursor IDE's SQLite database.
//!
//! Cursor stores chat history in `~/.config/Cursor/User/globalStorage/state.vscdb`
//! as a key-value store with JSON blobs.
//!
//! Key format: `bubbleId:{conversation-uuid}:{message-uuid}`
//! Value format: JSON blob with message data

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use rusqlite::{Connection, OpenFlags};
use uuid::Uuid;

use super::models::{Conversation, ConversationStats, Message};

/// Parser for Cursor's SQLite database
pub struct CursorParser {
    /// Path to the state.vscdb file
    db_path: PathBuf,
}

impl CursorParser {
    /// Create a new parser for the default Cursor database location
    pub fn new_default() -> Result<Self> {
        let db_path = Self::default_db_path()?;
        Self::new(db_path)
    }

    /// Create a new parser for a specific database path
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let db_path = db_path.as_ref().to_path_buf();
        if !db_path.exists() {
            anyhow::bail!("Cursor database not found at: {}", db_path.display());
        }
        Ok(Self { db_path })
    }

    /// Get the default database path for the current platform
    pub fn default_db_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .context("Could not determine config directory")?;
        
        // Linux: ~/.config/Cursor/User/globalStorage/state.vscdb
        let db_path = config_dir
            .join("Cursor")
            .join("User")
            .join("globalStorage")
            .join("state.vscdb");

        Ok(db_path)
    }

    /// List all workspace storage databases (per-workspace chat history)
    pub fn list_workspace_dbs() -> Result<Vec<PathBuf>> {
        let config_dir = dirs::config_dir()
            .context("Could not determine config directory")?;
        
        let workspace_dir = config_dir
            .join("Cursor")
            .join("User")
            .join("workspaceStorage");

        let mut dbs = Vec::new();

        if workspace_dir.exists() {
            for entry in std::fs::read_dir(&workspace_dir)? {
                let entry = entry?;
                let db_path = entry.path().join("state.vscdb");
                if db_path.exists() {
                    dbs.push(db_path);
                }
            }
        }

        Ok(dbs)
    }

    /// Open a read-only connection to the database
    fn open_connection(&self) -> Result<Connection> {
        let conn = Connection::open_with_flags(
            &self.db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .context("Failed to open Cursor database")?;

        // Set pragmas for better performance
        conn.execute_batch(
            "PRAGMA query_only = ON;
             PRAGMA temp_store = MEMORY;
             PRAGMA mmap_size = 268435456;", // 256MB mmap
        )?;

        Ok(conn)
    }

    /// Parse all conversations from the database
    pub fn parse_all(&self) -> Result<Vec<Conversation>> {
        let conn = self.open_connection()?;

        // Group messages by conversation ID
        let mut conversations_map: HashMap<Uuid, Vec<Message>> = HashMap::new();

        let mut stmt = conn.prepare(
            "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'"
        )?;

        let rows = stmt.query_map([], |row| {
            let key: String = row.get(0)?;
            let value: String = row.get(1)?;
            Ok((key, value))
        })?;

        for row_result in rows {
            let (key, value) = row_result?;
            
            // Parse key: bubbleId:{conv-id}:{msg-id}
            if let Some((conv_id, _msg_id)) = parse_bubble_key(&key) {
                // Parse JSON value
                match serde_json::from_str::<Message>(&value) {
                    Ok(message) => {
                        conversations_map
                            .entry(conv_id)
                            .or_default()
                            .push(message);
                    }
                    Err(e) => {
                        log::warn!("Failed to parse message {}: {}", key, e);
                    }
                }
            }
        }

        // Convert to Conversation structs
        let conversations: Vec<Conversation> = conversations_map
            .into_iter()
            .map(|(id, messages)| Conversation::from_messages(id, messages))
            .collect();

        log::info!(
            "Parsed {} conversations with {} total messages from {}",
            conversations.len(),
            conversations.iter().map(|c| c.message_count).sum::<usize>(),
            self.db_path.display()
        );

        Ok(conversations)
    }

    /// Parse conversations and return with stats
    pub fn parse_with_stats(&self) -> Result<(Vec<Conversation>, ConversationStats)> {
        let conversations = self.parse_all()?;
        let stats = ConversationStats::from_conversations(&conversations);
        Ok((conversations, stats))
    }

    /// Get a single conversation by ID
    pub fn get_conversation(&self, id: Uuid) -> Result<Option<Conversation>> {
        let conn = self.open_connection()?;
        let id_str = id.to_string();

        let mut stmt = conn.prepare(
            "SELECT key, value FROM cursorDiskKV WHERE key LIKE ?"
        )?;

        let pattern = format!("bubbleId:{}:%", id_str);
        let rows = stmt.query_map([&pattern], |row| {
            let _key: String = row.get(0)?;
            let value: String = row.get(1)?;
            Ok(value)
        })?;

        let mut messages = Vec::new();
        for row_result in rows {
            let value = row_result?;
            if let Ok(message) = serde_json::from_str::<Message>(&value) {
                messages.push(message);
            }
        }

        if messages.is_empty() {
            Ok(None)
        } else {
            Ok(Some(Conversation::from_messages(id, messages)))
        }
    }

    /// List conversation IDs without loading full content
    pub fn list_conversation_ids(&self) -> Result<Vec<Uuid>> {
        let conn = self.open_connection()?;

        let mut stmt = conn.prepare(
            "SELECT DISTINCT substr(key, 10, 36) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'"
        )?;

        let ids: Vec<Uuid> = stmt
            .query_map([], |row| {
                let id_str: String = row.get(0)?;
                Ok(id_str)
            })?
            .filter_map(|r| r.ok())
            .filter_map(|id_str| Uuid::parse_str(&id_str).ok())
            .collect();

        Ok(ids)
    }

    /// Get the count of conversations without parsing them
    pub fn conversation_count(&self) -> Result<usize> {
        let conn = self.open_connection()?;

        let count: i64 = conn.query_row(
            "SELECT COUNT(DISTINCT substr(key, 10, 36)) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'",
            [],
            |row| row.get(0),
        )?;

        Ok(count as usize)
    }

    /// Get the message count without parsing
    pub fn message_count(&self) -> Result<usize> {
        let conn = self.open_connection()?;

        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'",
            [],
            |row| row.get(0),
        )?;

        Ok(count as usize)
    }

    /// Search conversations by text content
    pub fn search(&self, query: &str) -> Result<Vec<Conversation>> {
        let conversations = self.parse_all()?;
        let query_lower = query.to_lowercase();

        let matching: Vec<Conversation> = conversations
            .into_iter()
            .filter(|conv| {
                conv.messages.iter().any(|msg| {
                    msg.text.to_lowercase().contains(&query_lower)
                })
            })
            .collect();

        Ok(matching)
    }

    /// Get database path
    pub fn db_path(&self) -> &Path {
        &self.db_path
    }
}

/// Parse a bubble key into (conversation_id, message_id)
fn parse_bubble_key(key: &str) -> Option<(Uuid, Uuid)> {
    // Format: bubbleId:{conv-uuid}:{msg-uuid}
    let parts: Vec<&str> = key.splitn(3, ':').collect();
    if parts.len() != 3 || parts[0] != "bubbleId" {
        return None;
    }

    let conv_id = Uuid::parse_str(parts[1]).ok()?;
    let msg_id = Uuid::parse_str(parts[2]).ok()?;

    Some((conv_id, msg_id))
}

/// Parse all Cursor databases (global + workspace)
pub fn parse_all_databases() -> Result<(Vec<Conversation>, ConversationStats)> {
    let mut all_conversations = Vec::new();

    // Parse global database
    if let Ok(parser) = CursorParser::new_default() {
        match parser.parse_all() {
            Ok(convs) => {
                log::info!("Parsed {} conversations from global storage", convs.len());
                all_conversations.extend(convs);
            }
            Err(e) => {
                log::warn!("Failed to parse global database: {}", e);
            }
        }
    }

    // Parse workspace databases
    if let Ok(workspace_dbs) = CursorParser::list_workspace_dbs() {
        for db_path in workspace_dbs {
            if let Ok(parser) = CursorParser::new(&db_path) {
                match parser.parse_all() {
                    Ok(convs) => {
                        log::info!(
                            "Parsed {} conversations from {}",
                            convs.len(),
                            db_path.display()
                        );
                        all_conversations.extend(convs);
                    }
                    Err(e) => {
                        log::warn!("Failed to parse {}: {}", db_path.display(), e);
                    }
                }
            }
        }
    }

    // Deduplicate by conversation ID (in case same conversation appears in multiple DBs)
    let mut seen_ids = std::collections::HashSet::new();
    all_conversations.retain(|conv| seen_ids.insert(conv.id));

    let stats = ConversationStats::from_conversations(&all_conversations);

    log::info!(
        "Total: {} conversations, {} messages, {} tokens",
        stats.total_conversations,
        stats.total_messages,
        stats.total_tokens()
    );

    Ok((all_conversations, stats))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_bubble_key() {
        let key = "bubbleId:419a3f6b-ca2d-4982-aabf-55b4d767f364:ff231e68-a109-4bfb-a729-ae641802448f";
        let (conv_id, msg_id) = parse_bubble_key(key).unwrap();
        
        assert_eq!(
            conv_id.to_string(),
            "419a3f6b-ca2d-4982-aabf-55b4d767f364"
        );
        assert_eq!(
            msg_id.to_string(),
            "ff231e68-a109-4bfb-a729-ae641802448f"
        );
    }

    #[test]
    fn test_parse_bubble_key_invalid() {
        assert!(parse_bubble_key("invalid").is_none());
        assert!(parse_bubble_key("bubbleId:invalid").is_none());
        assert!(parse_bubble_key("other:uuid:uuid").is_none());
    }

    #[test]
    fn test_default_db_path() {
        let path = CursorParser::default_db_path().unwrap();
        assert!(path.to_string_lossy().contains("Cursor"));
        assert!(path.to_string_lossy().contains("state.vscdb"));
    }

    /// Integration test - only runs if Cursor database exists
    #[test]
    fn test_parse_real_database() {
        // Skip if database doesn't exist
        let db_path = match CursorParser::default_db_path() {
            Ok(p) if p.exists() => p,
            _ => {
                eprintln!("Skipping integration test: Cursor database not found");
                return;
            }
        };

        let parser = CursorParser::new(&db_path).expect("Failed to create parser");

        // Test conversation count
        let count = parser.conversation_count().expect("Failed to count");
        println!("Found {} conversations", count);
        assert!(count > 0, "Expected at least one conversation");

        // Test message count
        let msg_count = parser.message_count().expect("Failed to count messages");
        println!("Found {} messages", msg_count);
        assert!(msg_count > 0, "Expected at least one message");

        // Test listing IDs
        let ids = parser.list_conversation_ids().expect("Failed to list IDs");
        println!("Listed {} conversation IDs", ids.len());
        assert_eq!(ids.len(), count);

        // Test parsing all
        let conversations = parser.parse_all().expect("Failed to parse");
        println!("Parsed {} conversations", conversations.len());

        // Print some stats
        let mut total_tokens: u64 = 0;
        let mut models_seen = std::collections::HashSet::new();
        let mut agentic_count = 0;

        for conv in &conversations {
            total_tokens += conv.total_tokens();
            if conv.is_agentic {
                agentic_count += 1;
            }
            for model in &conv.models_used {
                models_seen.insert(model.clone());
            }
        }

        println!("\n=== Chat History Stats ===");
        println!("Conversations: {}", conversations.len());
        println!("Total messages: {}", conversations.iter().map(|c| c.message_count).sum::<usize>());
        println!("Total tokens: {}", total_tokens);
        println!("Agentic conversations: {}", agentic_count);
        println!("Models used: {:?}", models_seen);

        // Print first conversation title
        if let Some(first) = conversations.first() {
            println!("\nFirst conversation:");
            println!("  Title: {:?}", first.title);
            println!("  Messages: {}", first.message_count);
            println!("  Created: {}", first.created_at);
        }
    }
}
