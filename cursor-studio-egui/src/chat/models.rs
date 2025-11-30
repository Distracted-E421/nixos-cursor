//! Data models for Cursor chat history.
//!
//! These structures map to Cursor's internal SQLite schema in `state.vscdb`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Message type in a conversation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "u8", into = "u8")]
pub enum MessageType {
    /// User message (type = 1)
    User = 1,
    /// Assistant response (type = 2)
    Assistant = 2,
    /// System message (type = 3, rare)
    System = 3,
}

impl TryFrom<u8> for MessageType {
    type Error = String;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(MessageType::User),
            2 => Ok(MessageType::Assistant),
            3 => Ok(MessageType::System),
            _ => Err(format!("Unknown message type: {}", value)),
        }
    }
}

impl From<MessageType> for u8 {
    fn from(mt: MessageType) -> u8 {
        mt as u8
    }
}

/// Token usage for a message
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenCount {
    pub input_tokens: u64,
    pub output_tokens: u64,
}

/// Model information
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub model_name: Option<String>,
}

/// A single message bubble in a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    /// Schema version (currently 3)
    #[serde(rename = "_v")]
    pub version: u8,

    /// Message type (1 = user, 2 = assistant)
    #[serde(rename = "type")]
    pub message_type: u8,

    /// Unique bubble ID
    pub bubble_id: String,

    /// Request ID for API tracking
    #[serde(default)]
    pub request_id: Option<String>,

    /// Plain text content
    #[serde(default)]
    pub text: String,

    /// Rich text in Lexical editor format (JSON string)
    #[serde(default)]
    pub rich_text: Option<String>,

    /// When this message was created
    #[serde(default)]
    pub created_at: Option<DateTime<Utc>>,

    /// Token usage
    #[serde(default)]
    pub token_count: TokenCount,

    /// Model information
    #[serde(default)]
    pub model_info: ModelInfo,

    /// Whether this is an agentic conversation
    #[serde(default)]
    pub is_agentic: bool,

    /// Tool results from MCP/function calls
    #[serde(default)]
    pub tool_results: Vec<serde_json::Value>,

    /// Suggested code blocks
    #[serde(default)]
    pub suggested_code_blocks: Vec<serde_json::Value>,

    /// Code chunks attached to the message
    #[serde(default)]
    pub attached_code_chunks: Vec<serde_json::Value>,

    /// Git diffs
    #[serde(default)]
    pub git_diffs: Vec<serde_json::Value>,

    /// Images attached
    #[serde(default)]
    pub images: Vec<serde_json::Value>,

    /// Documentation references
    #[serde(default)]
    pub docs_references: Vec<serde_json::Value>,

    /// Web references
    #[serde(default)]
    pub web_references: Vec<serde_json::Value>,

    /// MCP server descriptors
    #[serde(default)]
    pub mcp_descriptors: Vec<serde_json::Value>,

    /// Cursor rules applied
    #[serde(default)]
    pub cursor_rules: Vec<serde_json::Value>,
}

impl Message {
    /// Get the message type as an enum
    pub fn get_type(&self) -> MessageType {
        MessageType::try_from(self.message_type).unwrap_or(MessageType::User)
    }

    /// Check if this is a user message
    pub fn is_user(&self) -> bool {
        self.message_type == 1
    }

    /// Check if this is an assistant message
    pub fn is_assistant(&self) -> bool {
        self.message_type == 2
    }

    /// Get total token count
    pub fn total_tokens(&self) -> u64 {
        self.token_count.input_tokens + self.token_count.output_tokens
    }

    /// Get the model name if available
    pub fn model_name(&self) -> Option<&str> {
        self.model_info.model_name.as_deref()
    }
}

/// A conversation (chat thread) containing multiple messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    /// Conversation ID (UUID)
    pub id: Uuid,

    /// Source device ID (for sync)
    #[serde(default)]
    pub device_id: Option<String>,

    /// Workspace path this conversation belongs to (hashed)
    #[serde(default)]
    pub workspace_hash: Option<String>,

    /// Title (auto-generated from first message or user-set)
    #[serde(default)]
    pub title: Option<String>,

    /// Messages in chronological order
    pub messages: Vec<Message>,

    /// When the conversation was created (first message timestamp)
    pub created_at: DateTime<Utc>,

    /// When the conversation was last updated
    pub updated_at: DateTime<Utc>,

    /// Total input tokens across all messages
    pub total_input_tokens: u64,

    /// Total output tokens across all messages
    pub total_output_tokens: u64,

    /// Number of messages
    pub message_count: usize,

    /// Whether this conversation uses agentic features
    pub is_agentic: bool,

    /// Models used in this conversation
    pub models_used: Vec<String>,
}

impl Conversation {
    /// Create a new conversation from a collection of messages
    pub fn from_messages(id: Uuid, messages: Vec<Message>) -> Self {
        let mut sorted_messages = messages;
        sorted_messages.sort_by(|a, b| {
            a.created_at
                .unwrap_or_default()
                .cmp(&b.created_at.unwrap_or_default())
        });

        let created_at = sorted_messages
            .first()
            .and_then(|m| m.created_at)
            .unwrap_or_else(Utc::now);

        let updated_at = sorted_messages
            .last()
            .and_then(|m| m.created_at)
            .unwrap_or_else(Utc::now);

        let total_input_tokens: u64 = sorted_messages
            .iter()
            .map(|m| m.token_count.input_tokens)
            .sum();

        let total_output_tokens: u64 = sorted_messages
            .iter()
            .map(|m| m.token_count.output_tokens)
            .sum();

        let is_agentic = sorted_messages.iter().any(|m| m.is_agentic);

        let models_used: Vec<String> = sorted_messages
            .iter()
            .filter_map(|m| m.model_info.model_name.clone())
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();

        // Generate title from first user message
        let title = sorted_messages
            .iter()
            .find(|m| m.is_user() && !m.text.is_empty())
            .map(|m| {
                let text = &m.text;
                if text.len() > 80 {
                    format!("{}...", &text[..77])
                } else {
                    text.clone()
                }
            });

        let message_count = sorted_messages.len();

        Self {
            id,
            device_id: None,
            workspace_hash: None,
            title,
            messages: sorted_messages,
            created_at,
            updated_at,
            total_input_tokens,
            total_output_tokens,
            message_count,
            is_agentic,
            models_used,
        }
    }

    /// Get total tokens (input + output)
    pub fn total_tokens(&self) -> u64 {
        self.total_input_tokens + self.total_output_tokens
    }

    /// Get conversation duration (time from first to last message)
    pub fn duration(&self) -> chrono::Duration {
        self.updated_at - self.created_at
    }
}

/// Statistics about parsed conversations
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ConversationStats {
    /// Total number of conversations
    pub total_conversations: usize,

    /// Total number of messages
    pub total_messages: usize,

    /// Total input tokens
    pub total_input_tokens: u64,

    /// Total output tokens
    pub total_output_tokens: u64,

    /// Number of agentic conversations
    pub agentic_conversations: usize,

    /// Models used and their message counts
    pub models: HashMap<String, usize>,

    /// Date range (oldest, newest)
    pub date_range: Option<(DateTime<Utc>, DateTime<Utc>)>,
}

impl ConversationStats {
    /// Calculate stats from a list of conversations
    pub fn from_conversations(conversations: &[Conversation]) -> Self {
        let mut stats = ConversationStats {
            total_conversations: conversations.len(),
            ..Default::default()
        };

        let mut oldest: Option<DateTime<Utc>> = None;
        let mut newest: Option<DateTime<Utc>> = None;

        for conv in conversations {
            stats.total_messages += conv.message_count;
            stats.total_input_tokens += conv.total_input_tokens;
            stats.total_output_tokens += conv.total_output_tokens;

            if conv.is_agentic {
                stats.agentic_conversations += 1;
            }

            for model in &conv.models_used {
                *stats.models.entry(model.clone()).or_insert(0) += 1;
            }

            // Track date range
            if oldest.is_none() || conv.created_at < oldest.unwrap() {
                oldest = Some(conv.created_at);
            }
            if newest.is_none() || conv.updated_at > newest.unwrap() {
                newest = Some(conv.updated_at);
            }
        }

        if let (Some(o), Some(n)) = (oldest, newest) {
            stats.date_range = Some((o, n));
        }

        stats
    }

    /// Get total tokens
    pub fn total_tokens(&self) -> u64 {
        self.total_input_tokens + self.total_output_tokens
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_type_conversion() {
        assert_eq!(MessageType::try_from(1).unwrap(), MessageType::User);
        assert_eq!(MessageType::try_from(2).unwrap(), MessageType::Assistant);
        assert!(MessageType::try_from(99).is_err());
    }

    #[test]
    fn test_conversation_from_messages() {
        let messages = vec![
            Message {
                version: 3,
                message_type: 1,
                bubble_id: "test-1".to_string(),
                request_id: None,
                text: "Hello, how are you?".to_string(),
                rich_text: None,
                created_at: Some(Utc::now()),
                token_count: TokenCount {
                    input_tokens: 10,
                    output_tokens: 0,
                },
                model_info: ModelInfo { model_name: None },
                is_agentic: false,
                tool_results: vec![],
                suggested_code_blocks: vec![],
                attached_code_chunks: vec![],
                git_diffs: vec![],
                images: vec![],
                docs_references: vec![],
                web_references: vec![],
                mcp_descriptors: vec![],
                cursor_rules: vec![],
            },
            Message {
                version: 3,
                message_type: 2,
                bubble_id: "test-2".to_string(),
                request_id: None,
                text: "I'm doing well, thanks!".to_string(),
                rich_text: None,
                created_at: Some(Utc::now()),
                token_count: TokenCount {
                    input_tokens: 0,
                    output_tokens: 15,
                },
                model_info: ModelInfo {
                    model_name: Some("claude-3.5-sonnet".to_string()),
                },
                is_agentic: false,
                tool_results: vec![],
                suggested_code_blocks: vec![],
                attached_code_chunks: vec![],
                git_diffs: vec![],
                images: vec![],
                docs_references: vec![],
                web_references: vec![],
                mcp_descriptors: vec![],
                cursor_rules: vec![],
            },
        ];

        let conv = Conversation::from_messages(Uuid::new_v4(), messages);

        assert_eq!(conv.message_count, 2);
        assert_eq!(conv.total_input_tokens, 10);
        assert_eq!(conv.total_output_tokens, 15);
        assert_eq!(conv.title, Some("Hello, how are you?".to_string()));
        assert_eq!(conv.models_used, vec!["claude-3.5-sonnet".to_string()]);
    }
}
