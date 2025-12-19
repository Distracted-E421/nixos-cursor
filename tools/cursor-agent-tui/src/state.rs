//! State management for cursor-agent-tui
//! 
//! Unlike Cursor's 2GB+ SQLite database, we use bounded, efficient storage.

use crate::config::Config;
use crate::error::{AgentError, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::PathBuf;
use uuid::Uuid;

/// A single message in a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: Uuid,
    pub role: MessageRole,
    pub content: String,
    pub timestamp: DateTime<Utc>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub tool_calls: Vec<ToolCallRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Tool,
}

/// Record of a tool call
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallRecord {
    pub name: String,
    pub args: serde_json::Value,
    pub result: Option<String>,
    pub success: bool,
}

/// A conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: Uuid,
    pub title: Option<String>,
    pub messages: Vec<ChatMessage>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub model: String,
}

impl Conversation {
    /// Create a new conversation
    pub fn new(model: &str) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: None,
            messages: Vec::new(),
            created_at: now,
            updated_at: now,
            model: model.to_string(),
        }
    }

    /// Add a message
    pub fn add_message(&mut self, role: MessageRole, content: String) -> &ChatMessage {
        let message = ChatMessage {
            id: Uuid::new_v4(),
            role,
            content,
            timestamp: Utc::now(),
            tool_calls: Vec::new(),
        };
        self.updated_at = Utc::now();
        self.messages.push(message);
        self.messages.last().unwrap()
    }

    /// Add a tool call to the last assistant message
    pub fn add_tool_call(&mut self, name: String, args: serde_json::Value, result: Option<String>, success: bool) {
        if let Some(last) = self.messages.last_mut() {
            if last.role == MessageRole::Assistant {
                last.tool_calls.push(ToolCallRecord {
                    name,
                    args,
                    result,
                    success,
                });
            }
        }
    }

    /// Generate a title from the first message
    pub fn generate_title(&mut self) {
        if self.title.is_none() && !self.messages.is_empty() {
            let first_content = &self.messages[0].content;
            self.title = Some(
                first_content
                    .chars()
                    .take(50)
                    .collect::<String>()
                    .trim()
                    .to_string()
            );
        }
    }
}

/// Summary of a conversation for history
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationSummary {
    pub id: Uuid,
    pub title: Option<String>,
    pub message_count: usize,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub model: String,
}

impl From<&Conversation> for ConversationSummary {
    fn from(conv: &Conversation) -> Self {
        Self {
            id: conv.id,
            title: conv.title.clone(),
            message_count: conv.messages.len(),
            created_at: conv.created_at,
            updated_at: conv.updated_at,
            model: conv.model.clone(),
        }
    }
}

/// State manager - bounded, efficient state storage
pub struct StateManager {
    /// Current conversation
    current: Option<Conversation>,
    /// Conversation history (bounded)
    history: VecDeque<ConversationSummary>,
    /// Storage path
    storage_path: PathBuf,
    /// Maximum history entries
    max_history: usize,
    /// Maximum total storage size
    max_size: usize,
}

impl StateManager {
    /// Create a new state manager
    pub fn new(config: &Config) -> Result<Self> {
        let storage_path = config.state.storage_path.clone();
        
        // Create storage directory
        std::fs::create_dir_all(&storage_path)?;

        let mut manager = Self {
            current: None,
            history: VecDeque::new(),
            storage_path,
            max_history: config.state.max_history,
            max_size: config.state.max_size,
        };

        // Load history index
        manager.load_history_index()?;

        Ok(manager)
    }

    /// Start a new conversation
    pub fn new_conversation(&mut self, model: &str) {
        // Save current if exists
        if let Some(conv) = self.current.take() {
            let _ = self.save_conversation(&conv);
        }

        self.current = Some(Conversation::new(model));
    }

    /// Get current conversation
    pub fn current(&self) -> Option<&Conversation> {
        self.current.as_ref()
    }

    /// Get current conversation mutably
    pub fn current_mut(&mut self) -> Option<&mut Conversation> {
        self.current.as_mut()
    }

    /// Save current conversation
    pub fn save_current(&mut self) -> Result<()> {
        if let Some(conv) = self.current.clone() {
            self.save_conversation(&conv)?;
        }
        Ok(())
    }

    /// Save a conversation to disk
    fn save_conversation(&mut self, conv: &Conversation) -> Result<()> {
        let path = self.storage_path.join(format!("{}.json", conv.id));
        let content = serde_json::to_string_pretty(conv)?;
        
        // Check size limit
        if content.len() > self.max_size / 10 {
            // Single conversation too large, truncate messages
            let mut truncated = conv.clone();
            while serde_json::to_string(&truncated)?.len() > self.max_size / 10 
                && truncated.messages.len() > 1 
            {
                truncated.messages.remove(0);
            }
            let content = serde_json::to_string_pretty(&truncated)?;
            std::fs::write(&path, content)?;
        } else {
            std::fs::write(&path, content)?;
        }

        // Update history
        let summary = ConversationSummary::from(conv);
        self.history.retain(|s| s.id != conv.id);
        self.history.push_front(summary);
        
        // Prune history
        self.prune_history()?;
        
        // Save history index
        self.save_history_index()?;

        Ok(())
    }

    /// Load a conversation by ID
    pub fn load_conversation(&mut self, id: Uuid) -> Result<()> {
        let path = self.storage_path.join(format!("{}.json", id));
        
        if !path.exists() {
            return Err(AgentError::State(format!(
                "Conversation not found: {}",
                id
            )));
        }

        let content = std::fs::read_to_string(&path)?;
        let conv: Conversation = serde_json::from_str(&content)?;
        
        // Save current first (if different)
        if let Some(current) = self.current.take() {
            if current.id != id {
                let _ = self.save_conversation(&current);
            }
        }
        
        self.current = Some(conv);
        Ok(())
    }

    /// Get conversation history
    pub fn history(&self) -> impl Iterator<Item = &ConversationSummary> {
        self.history.iter()
    }

    /// Prune old history
    fn prune_history(&mut self) -> Result<()> {
        while self.history.len() > self.max_history {
            if let Some(old) = self.history.pop_back() {
                let path = self.storage_path.join(format!("{}.json", old.id));
                let _ = std::fs::remove_file(path);
            }
        }

        // Also check total size
        let mut total_size = 0u64;
        for summary in &self.history {
            let path = self.storage_path.join(format!("{}.json", summary.id));
            if let Ok(meta) = std::fs::metadata(&path) {
                total_size += meta.len();
            }
        }

        while total_size > self.max_size as u64 && self.history.len() > 1 {
            if let Some(old) = self.history.pop_back() {
                let path = self.storage_path.join(format!("{}.json", old.id));
                if let Ok(meta) = std::fs::metadata(&path) {
                    total_size -= meta.len();
                }
                let _ = std::fs::remove_file(path);
            }
        }

        Ok(())
    }

    /// Load history index from disk
    fn load_history_index(&mut self) -> Result<()> {
        let index_path = self.storage_path.join("index.json");
        
        if index_path.exists() {
            let content = std::fs::read_to_string(&index_path)?;
            let history: Vec<ConversationSummary> = serde_json::from_str(&content)?;
            self.history = VecDeque::from(history);
        }
        
        Ok(())
    }

    /// Save history index to disk
    fn save_history_index(&self) -> Result<()> {
        let index_path = self.storage_path.join("index.json");
        let history: Vec<_> = self.history.iter().cloned().collect();
        let content = serde_json::to_string_pretty(&history)?;
        std::fs::write(index_path, content)?;
        Ok(())
    }

    /// Get storage statistics
    pub fn stats(&self) -> StateStats {
        let mut total_size = 0u64;
        let mut file_count = 0;

        if let Ok(entries) = std::fs::read_dir(&self.storage_path) {
            for entry in entries.flatten() {
                if let Ok(meta) = entry.metadata() {
                    total_size += meta.len();
                    file_count += 1;
                }
            }
        }

        StateStats {
            conversation_count: self.history.len(),
            file_count,
            total_size,
            max_size: self.max_size as u64,
        }
    }
}

/// State storage statistics
#[derive(Debug)]
pub struct StateStats {
    pub conversation_count: usize,
    pub file_count: usize,
    pub total_size: u64,
    pub max_size: u64,
}

impl Drop for StateManager {
    fn drop(&mut self) {
        // Save current conversation on exit
        if let Some(conv) = self.current.take() {
            let _ = self.save_conversation(&conv);
        }
    }
}

