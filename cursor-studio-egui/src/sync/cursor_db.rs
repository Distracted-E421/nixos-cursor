//! Cursor Database Reader
//!
//! Reads conversation and message data from Cursor's SQLite databases.
//! Handles both global storage and workspace-specific databases.

use super::models::{Conversation, Message, ConversationContext};
use std::path::{Path, PathBuf};

/// Reader for Cursor's internal databases
pub struct CursorDatabaseReader {
    /// Global database path
    global_db: Option<PathBuf>,
    
    /// Workspace database paths
    workspace_dbs: Vec<PathBuf>,
}

impl CursorDatabaseReader {
    /// Create a new reader
    pub fn new() -> Self {
        Self {
            global_db: None,
            workspace_dbs: Vec::new(),
        }
    }
    
    /// Set the global database path
    pub fn with_global_db(mut self, path: impl AsRef<Path>) -> Self {
        self.global_db = Some(path.as_ref().to_path_buf());
        self
    }
    
    /// Add a workspace database
    pub fn add_workspace_db(&mut self, path: impl AsRef<Path>) {
        self.workspace_dbs.push(path.as_ref().to_path_buf());
    }
    
    /// Discover workspace databases from base path
    pub fn discover_workspaces(&mut self, base_path: impl AsRef<Path>) -> Result<usize, ReaderError> {
        let base = base_path.as_ref();
        
        if !base.exists() {
            return Err(ReaderError::PathNotFound(base.display().to_string()));
        }
        
        let mut count = 0;
        
        if let Ok(entries) = std::fs::read_dir(base) {
            for entry in entries.flatten() {
                let db_path = entry.path().join("state.vscdb");
                if db_path.exists() {
                    self.workspace_dbs.push(db_path);
                    count += 1;
                }
            }
        }
        
        Ok(count)
    }
    
    /// Read all messages from global database
    pub fn read_messages(&self) -> Result<Vec<Message>, ReaderError> {
        let db_path = self.global_db.as_ref()
            .ok_or_else(|| ReaderError::NoDatabaseConfigured)?;
        
        if !db_path.exists() {
            return Err(ReaderError::PathNotFound(db_path.display().to_string()));
        }
        
        // TODO: Implement actual SQLite reading
        // For now, return empty vec
        Ok(Vec::new())
    }
    
    /// Read conversations from workspace databases
    pub fn read_conversations(&self) -> Result<Vec<Conversation>, ReaderError> {
        let conversations = Vec::new();
        
        for db_path in &self.workspace_dbs {
            if !db_path.exists() {
                continue;
            }
            
            // TODO: Implement actual SQLite reading
            // For now, skip
        }
        
        Ok(conversations)
    }
    
    /// Read a specific conversation with all messages
    pub fn read_conversation_full(&self, id: &str) -> Result<(Conversation, Vec<Message>), ReaderError> {
        // TODO: Implement
        Err(ReaderError::NotFound(id.to_string()))
    }
    
    /// Read context for a conversation
    pub fn read_context(&self, _conversation_id: &str) -> Result<ConversationContext, ReaderError> {
        // TODO: Implement
        Ok(ConversationContext {
            cursor_rules: Vec::new(),
            file_selections: Vec::new(),
            folder_selections: Vec::new(),
            selected_docs: Vec::new(),
            web_references: Vec::new(),
            terminal_selections: Vec::new(),
        })
    }
}

impl Default for CursorDatabaseReader {
    fn default() -> Self {
        Self::new()
    }
}

/// Reader errors
#[derive(Debug, Clone)]
pub enum ReaderError {
    /// No database configured
    NoDatabaseConfigured,
    /// Path not found
    PathNotFound(String),
    /// Item not found
    NotFound(String),
    /// Database error
    DatabaseError(String),
    /// Parse error
    ParseError(String),
}

impl std::fmt::Display for ReaderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReaderError::NoDatabaseConfigured => write!(f, "No database configured"),
            ReaderError::PathNotFound(p) => write!(f, "Path not found: {}", p),
            ReaderError::NotFound(id) => write!(f, "Not found: {}", id),
            ReaderError::DatabaseError(e) => write!(f, "Database error: {}", e),
            ReaderError::ParseError(e) => write!(f, "Parse error: {}", e),
        }
    }
}

impl std::error::Error for ReaderError {}
