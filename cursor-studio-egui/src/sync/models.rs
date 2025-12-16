//! Data Models for Cursor Sync
//!
//! These structures represent the data extracted from Cursor's
//! internal databases and synced to the external database.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A conversation (composer) from Cursor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    /// Unique conversation ID
    pub id: String,
    
    /// Display name/title
    pub name: String,
    
    /// Workspace hash (if workspace-specific)
    pub workspace: Option<String>,
    
    /// Creation timestamp (Unix ms)
    pub created_at: Option<i64>,
    
    /// Last update timestamp (Unix ms)
    pub updated_at: Option<i64>,
    
    /// Whether conversation is archived
    pub is_archived: bool,
    
    /// Total messages in conversation
    pub message_count: usize,
    
    /// Model used (if consistent)
    pub model: Option<String>,
    
    /// Whether this is an agentic conversation
    pub is_agentic: bool,
    
    /// Total tokens used
    pub total_tokens: u64,
    
    /// Lines of code added
    pub lines_added: u64,
    
    /// Lines of code removed
    pub lines_removed: u64,
    
    /// Raw JSON data (for full fidelity)
    pub raw_data: Option<String>,
}

/// A message (bubble) from a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// Unique message ID (bubbleId)
    pub id: String,
    
    /// Parent conversation ID
    pub conversation_id: String,
    
    /// Message type (1 = user, 2 = assistant, etc.)
    pub message_type: i32,
    
    /// Creation timestamp (Unix ms)
    pub created_at: Option<i64>,
    
    /// Model name used for this message
    pub model: Option<String>,
    
    /// Token count for this message
    pub token_count: u64,
    
    /// Whether message has thinking blocks
    pub has_thinking: bool,
    
    /// Whether message has tool calls
    pub has_tool_calls: bool,
    
    /// Whether message has code changes
    pub has_code_changes: bool,
    
    /// Attached files count
    pub attached_files_count: usize,
    
    /// Tool calls in this message
    pub tool_calls: Vec<ToolCall>,
    
    /// Raw JSON data
    pub raw_data: Option<String>,
}

/// A tool call from a message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    /// Tool name
    pub name: String,
    
    /// Server/MCP name
    pub server: Option<String>,
    
    /// Whether the call succeeded
    pub success: bool,
    
    /// Duration in milliseconds
    pub duration_ms: Option<u64>,
    
    /// Error message if failed
    pub error: Option<String>,
}

/// Context provided to a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationContext {
    /// Active cursor rules
    pub cursor_rules: Vec<String>,
    
    /// Selected files (@file mentions)
    pub file_selections: Vec<String>,
    
    /// Selected folders
    pub folder_selections: Vec<String>,
    
    /// Selected docs (@docs)
    pub selected_docs: Vec<String>,
    
    /// Web references
    pub web_references: Vec<String>,
    
    /// Terminal selections
    pub terminal_selections: Vec<String>,
}

/// Sync state for tracking what's been synced
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncState {
    /// Last sync timestamp
    pub last_sync: Option<i64>,
    
    /// Last synced message IDs per conversation
    pub last_message_ids: HashMap<String, String>,
    
    /// Total conversations synced
    pub conversations_synced: usize,
    
    /// Total messages synced
    pub messages_synced: usize,
    
    /// Errors during last sync
    pub last_errors: Vec<String>,
}

impl Default for SyncState {
    fn default() -> Self {
        Self {
            last_sync: None,
            last_message_ids: HashMap::new(),
            conversations_synced: 0,
            messages_synced: 0,
            last_errors: Vec::new(),
        }
    }
}

impl Conversation {
    /// Create a new conversation with minimal data
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            workspace: None,
            created_at: None,
            updated_at: None,
            is_archived: false,
            message_count: 0,
            model: None,
            is_agentic: false,
            total_tokens: 0,
            lines_added: 0,
            lines_removed: 0,
            raw_data: None,
        }
    }
}

impl Message {
    /// Create a new message
    pub fn new(id: impl Into<String>, conversation_id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            conversation_id: conversation_id.into(),
            message_type: 0,
            created_at: None,
            model: None,
            token_count: 0,
            has_thinking: false,
            has_tool_calls: false,
            has_code_changes: false,
            attached_files_count: 0,
            tool_calls: Vec::new(),
            raw_data: None,
        }
    }
    
    /// Check if this is a user message
    pub fn is_user(&self) -> bool {
        self.message_type == 1
    }
    
    /// Check if this is an assistant message
    pub fn is_assistant(&self) -> bool {
        self.message_type == 2
    }
}

/// Message type constants
pub mod message_types {
    pub const USER: i32 = 1;
    pub const ASSISTANT: i32 = 2;
    pub const SYSTEM: i32 = 3;
    pub const TOOL_RESULT: i32 = 4;
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_conversation_creation() {
        let conv = Conversation::new("test-id", "Test Conversation");
        assert_eq!(conv.id, "test-id");
        assert_eq!(conv.name, "Test Conversation");
        assert!(!conv.is_archived);
    }
    
    #[test]
    fn test_message_type_checks() {
        let mut msg = Message::new("msg-1", "conv-1");
        msg.message_type = message_types::USER;
        assert!(msg.is_user());
        assert!(!msg.is_assistant());
        
        msg.message_type = message_types::ASSISTANT;
        assert!(!msg.is_user());
        assert!(msg.is_assistant());
    }
}
