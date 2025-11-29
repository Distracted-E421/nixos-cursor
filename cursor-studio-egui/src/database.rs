//! Database module for Cursor versions and chat history

use anyhow::{Context, Result};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

/// Extract message content from various possible JSON structures in Cursor's database
fn extract_message_content(data: &Value) -> (String, Option<ToolCallInfo>, Option<String>) {
    let mut content = String::new();
    let mut tool_call: Option<ToolCallInfo> = None;
    let mut thinking: Option<String> = None;

    // Extract thinking block if present
    if let Some(thinking_obj) = data.get("thinking") {
        if let Some(t) = thinking_obj.get("text").and_then(|v| v.as_str()) {
            if !t.is_empty() {
                thinking = Some(t.to_string());
            }
        }
    }

    // Extract tool call if present (toolFormerData)
    if let Some(tool_data) = data.get("toolFormerData") {
        let name = tool_data
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let raw_args = tool_data
            .get("rawArgs")
            .and_then(|v| v.as_str())
            .unwrap_or("{}")
            .to_string();

        let status = tool_data
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let tool_id = tool_data
            .get("toolCallId")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        // Parse the args to get a preview
        let args_preview = if let Ok(args) = serde_json::from_str::<Value>(&raw_args) {
            // Create a readable preview of the args (show more data)
            if let Some(obj) = args.as_object() {
                obj.iter()
                    .take(5) // Show up to 5 args
                    .map(|(k, v)| {
                        let v_str = match v {
                            Value::String(s) => {
                                // Use chars() to safely truncate at character boundaries
                                let truncated: String = s.chars().take(100).collect();
                                if truncated.len() < s.len() {
                                    format!("{}...", truncated)
                                } else {
                                    truncated
                                }
                            }
                            _ => {
                                let s = v.to_string();
                                let truncated: String = s.chars().take(100).collect();
                                if truncated.len() < s.len() {
                                    format!("{}...", truncated)
                                } else {
                                    truncated
                                }
                            }
                        };
                        format!("{}: {}", k, v_str)
                    })
                    .collect::<Vec<_>>()
                    .join(", ")
            } else {
                raw_args.chars().take(100).collect()
            }
        } else {
            raw_args.chars().take(100).collect()
        };

        tool_call = Some(ToolCallInfo {
            name,
            args: raw_args,
            args_preview,
            status,
            tool_id,
        });

        // For tool calls, content might be empty - that's OK
    }

    // Try to get text content
    // Order: text -> richText (parsed) -> message -> rawText -> fullText
    if let Some(s) = data.get("text").and_then(|v| v.as_str()) {
        if !s.is_empty() {
            content = s.to_string();
        }
    }

    // If no text, try richText (Lexical editor format)
    if content.is_empty() {
        if let Some(rich_text_str) = data.get("richText").and_then(|v| v.as_str()) {
            if let Ok(rich_text) = serde_json::from_str::<Value>(rich_text_str) {
                content = extract_lexical_text(&rich_text);
            }
        }
    }

    // Fallback fields
    if content.is_empty() {
        for field in ["message", "rawText", "fullText", "content"] {
            if let Some(s) = data.get(field).and_then(|v| v.as_str()) {
                if !s.is_empty() {
                    content = s.to_string();
                    break;
                }
            }
        }
    }

    (content, tool_call, thinking)
}

/// Extract plain text from Lexical editor JSON format
fn extract_lexical_text(root: &Value) -> String {
    let mut parts = Vec::new();
    extract_lexical_text_recursive(root, &mut parts);
    parts.join("")
}

fn extract_lexical_text_recursive(node: &Value, parts: &mut Vec<String>) {
    // If this node has "text" field, it's a text node
    if let Some(text) = node.get("text").and_then(|v| v.as_str()) {
        parts.push(text.to_string());
    }

    // Check for code block
    if let Some(node_type) = node.get("type").and_then(|v| v.as_str()) {
        if node_type == "code" {
            if let Some(code) = node.get("code").and_then(|v| v.as_str()) {
                let lang = node.get("language").and_then(|v| v.as_str()).unwrap_or("");
                parts.push(format!("\n```{}\n{}\n```\n", lang, code));
            }
        }
    }

    // Recurse into children
    if let Some(children) = node.get("children").and_then(|v| v.as_array()) {
        for child in children {
            extract_lexical_text_recursive(child, parts);
        }
    }

    // Add newline after paragraphs
    if let Some(node_type) = node.get("type").and_then(|v| v.as_str()) {
        if node_type == "paragraph" {
            parts.push("\n".to_string());
        }
    }
}

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    color TEXT DEFAULT '#808080',
    description TEXT,
    sort_order INTEGER DEFAULT 0
);

INSERT OR IGNORE INTO categories (id, name, color, description, sort_order) VALUES
    (1, 'Uncategorized', '#6e6e6e', 'Not yet categorized', 0);

CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    source_version TEXT NOT NULL,
    imported_at TEXT DEFAULT (datetime('now')),
    original_title TEXT,
    category_id INTEGER DEFAULT 1,
    user_tags TEXT DEFAULT '[]',
    message_count INTEGER DEFAULT 0,
    is_favorite INTEGER DEFAULT 0,
    is_archived INTEGER DEFAULT 0,
    content_hash TEXT
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    role TEXT NOT NULL,
    content TEXT,
    raw_json TEXT,
    tool_name TEXT,
    tool_args TEXT,
    tool_status TEXT,
    thinking TEXT,
    content_type TEXT DEFAULT 'text',
    has_code_blocks INTEGER DEFAULT 0,
    has_terminal_output INTEGER DEFAULT 0,
    files_edited TEXT DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id);

-- Bookmarks table - persists across cache clears
CREATE TABLE IF NOT EXISTS bookmarks (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    message_id TEXT NOT NULL,
    message_sequence INTEGER NOT NULL,
    label TEXT,
    note TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    color TEXT DEFAULT '#ffd700'
);

CREATE INDEX IF NOT EXISTS idx_bookmark_conv ON bookmarks(conversation_id);

-- User request segments - groups of messages per user turn
CREATE TABLE IF NOT EXISTS request_segments (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    segment_index INTEGER NOT NULL,
    user_message_id TEXT NOT NULL,
    response_message_ids TEXT DEFAULT '[]',
    tool_call_ids TEXT DEFAULT '[]',
    files_edited TEXT DEFAULT '[]',
    started_at TEXT,
    ended_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_segment_conv ON request_segments(conversation_id);

-- Display preferences per content type
CREATE TABLE IF NOT EXISTS display_preferences (
    content_type TEXT PRIMARY KEY,
    alignment TEXT DEFAULT 'left',
    style TEXT DEFAULT 'default',
    collapsed_by_default INTEGER DEFAULT 0
);

INSERT OR IGNORE INTO display_preferences (content_type, alignment, style) VALUES
    ('user', 'right', 'bubble'),
    ('assistant', 'left', 'default'),
    ('thinking', 'left', 'collapsed'),
    ('tool_call', 'left', 'compact'),
    ('tool_result', 'left', 'compact'),
    ('code_block', 'left', 'highlight'),
    ('terminal', 'left', 'monospace');
"#;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorVersion {
    pub version: String,
    pub path: PathBuf,
    pub is_installed: bool,
    pub is_default: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub source_version: String,
    pub title: String,
    pub category: String,
    pub message_count: usize,
    pub is_favorite: bool,
    pub user_tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallInfo {
    pub name: String,
    pub args: String,
    pub args_preview: String,
    pub status: String,
    pub tool_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub sequence: usize,
    pub role: MessageRole,
    pub content: String,
    pub tool_call: Option<ToolCallInfo>,
    pub thinking: Option<String>,
    pub content_type: ContentType,
    pub has_code_blocks: bool,
    pub has_terminal_output: bool,
    pub files_edited: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageRole {
    User,
    Assistant,
    ToolCall,
    ToolResult,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum ContentType {
    #[default]
    Text,
    Code,
    Terminal,
    Markdown,
    Mixed,
}

impl ContentType {
    pub fn from_str(s: &str) -> Self {
        match s {
            "code" => ContentType::Code,
            "terminal" => ContentType::Terminal,
            "markdown" => ContentType::Markdown,
            "mixed" => ContentType::Mixed,
            _ => ContentType::Text,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            ContentType::Text => "text",
            ContentType::Code => "code",
            ContentType::Terminal => "terminal",
            ContentType::Markdown => "markdown",
            ContentType::Mixed => "mixed",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bookmark {
    pub id: String,
    pub conversation_id: String,
    pub message_id: String,
    pub message_sequence: usize,
    pub label: Option<String>,
    pub note: Option<String>,
    pub created_at: String,
    pub color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestSegment {
    pub id: String,
    pub conversation_id: String,
    pub segment_index: usize,
    pub user_message_id: String,
    pub response_message_ids: Vec<String>,
    pub tool_call_ids: Vec<String>,
    pub files_edited: Vec<String>,
    pub started_at: Option<String>,
    pub ended_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayPreference {
    pub content_type: String,
    pub alignment: String, // "left", "right", "center"
    pub style: String,     // "default", "bubble", "compact", "collapsed", "highlight", "monospace"
    pub collapsed_by_default: bool,
}

/// Statistics about message types for analytics
#[derive(Debug, Clone, Default)]
pub struct MessageStats {
    pub user_messages: usize,
    pub assistant_messages: usize,
    pub tool_calls: usize,
    pub with_thinking: usize,
    pub with_code: usize,
    pub bookmarks: usize,
}

pub struct ChatDatabase {
    conn: Arc<Mutex<Connection>>,
    #[allow(dead_code)]
    data_dir: PathBuf,
}

impl ChatDatabase {
    /// Create a new database with a custom data directory (for testing)
    #[cfg(test)]
    pub fn new_with_path(data_dir: PathBuf) -> Result<Self> {
        std::fs::create_dir_all(&data_dir)?;
        let db_path = data_dir.join("studio.db");
        let conn = Connection::open(&db_path)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            data_dir,
        })
    }

    pub fn new() -> Result<Self> {
        let data_dir = dirs::config_dir()
            .context("No config directory")?
            .join("cursor-studio");

        std::fs::create_dir_all(&data_dir)?;

        let db_path = data_dir.join("studio.db");
        let conn = Connection::open(&db_path)?;
        conn.execute_batch(SCHEMA)?;

        // Migration: add new columns if they don't exist
        let _ = conn.execute("ALTER TABLE messages ADD COLUMN tool_name TEXT", []);
        let _ = conn.execute("ALTER TABLE messages ADD COLUMN tool_args TEXT", []);
        let _ = conn.execute("ALTER TABLE messages ADD COLUMN tool_status TEXT", []);
        let _ = conn.execute("ALTER TABLE messages ADD COLUMN thinking TEXT", []);
        let _ = conn.execute("ALTER TABLE messages ADD COLUMN raw_json TEXT", []);

        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            data_dir,
        })
    }

    /// Get the path to the database file
    pub fn get_path(&self) -> PathBuf {
        self.data_dir.join("studio.db")
    }

    /// Open an existing database (for use in background threads)
    pub fn open(path: &PathBuf) -> Result<Self> {
        let data_dir = path.parent().unwrap_or(path).to_path_buf();
        let conn = Connection::open(path)?;

        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            data_dir,
        })
    }

    pub fn get_versions(&self) -> Result<Vec<CursorVersion>> {
        let home = dirs::home_dir().context("No home directory")?;
        let mut versions = Vec::new();

        let main_cursor = home.join(".config/Cursor");
        if main_cursor.exists() {
            versions.push(CursorVersion {
                version: "default".to_string(),
                path: main_cursor,
                is_installed: true,
                is_default: true,
            });
        }

        for entry in std::fs::read_dir(&home)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();

            if name.starts_with(".cursor-") && entry.file_type()?.is_dir() {
                let version = name.strip_prefix(".cursor-").unwrap_or(&name).to_string();
                versions.push(CursorVersion {
                    version,
                    path: entry.path(),
                    is_installed: true,
                    is_default: false,
                });
            }
        }

        Ok(versions)
    }

    pub fn get_conversations(&self, limit: usize) -> Result<Vec<Conversation>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT c.id, c.source_version, c.original_title, cat.name, c.message_count, 
                    c.is_favorite, c.user_tags
             FROM conversations c
             LEFT JOIN categories cat ON c.category_id = cat.id
             WHERE c.is_archived = 0
             ORDER BY c.imported_at DESC
             LIMIT ?",
        )?;

        let rows = stmt.query_map(params![limit], |row| {
            let tags_json: String = row
                .get::<_, Option<String>>(6)?
                .unwrap_or_else(|| "[]".to_string());
            let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();

            Ok(Conversation {
                id: row.get(0)?,
                source_version: row.get(1)?,
                title: row
                    .get::<_, Option<String>>(2)?
                    .unwrap_or_else(|| "Untitled".to_string()),
                category: row
                    .get::<_, Option<String>>(3)?
                    .unwrap_or_else(|| "Uncategorized".to_string()),
                message_count: row.get(4)?,
                is_favorite: row.get::<_, i32>(5)? != 0,
                user_tags: tags,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn get_messages(&self, conversation_id: &str) -> Result<Vec<Message>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, sequence, role, content, 
                    tool_name, tool_args, tool_status, thinking
             FROM messages WHERE conversation_id = ? ORDER BY sequence",
        )?;

        let rows = stmt.query_map(params![conversation_id], |row| {
            let role_str: String = row.get(3)?;
            let role = match role_str.as_str() {
                "assistant" => MessageRole::Assistant,
                "tool_call" => MessageRole::ToolCall,
                "tool_result" => MessageRole::ToolResult,
                _ => MessageRole::User,
            };

            // Reconstruct tool call info if present
            let tool_name: Option<String> = row.get(5)?;
            let tool_call = tool_name.map(|name| {
                let args: String = row
                    .get::<_, Option<String>>(6)
                    .ok()
                    .flatten()
                    .unwrap_or_default();
                let status: String = row
                    .get::<_, Option<String>>(7)
                    .ok()
                    .flatten()
                    .unwrap_or_default();

                // Create preview from args
                let args_preview = if let Ok(parsed) = serde_json::from_str::<Value>(&args) {
                    if let Some(obj) = parsed.as_object() {
                        obj.iter()
                            .take(2)
                            .map(|(k, v)| {
                                format!(
                                    "{}: {}",
                                    k,
                                    v.to_string().chars().take(30).collect::<String>()
                                )
                            })
                            .collect::<Vec<_>>()
                            .join(", ")
                    } else {
                        args.chars().take(100).collect()
                    }
                } else {
                    args.chars().take(100).collect()
                };

                ToolCallInfo {
                    name,
                    args,
                    args_preview,
                    status,
                    tool_id: String::new(),
                }
            });

            // Detect content type based on content
            let content: String = row.get::<_, Option<String>>(4)?.unwrap_or_default();
            let has_code = content.contains("```");
            let has_terminal = content.contains("$ ")
                || content.contains("❯ ")
                || content.contains("[e421@")
                || content.contains("Command output:");

            let content_type = if has_code && has_terminal {
                ContentType::Mixed
            } else if has_code {
                ContentType::Code
            } else if has_terminal {
                ContentType::Terminal
            } else if content.contains('#') || content.contains("**") || content.contains("- ") {
                ContentType::Markdown
            } else {
                ContentType::Text
            };

            Ok(Message {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                sequence: row.get(2)?,
                role,
                content,
                tool_call,
                thinking: row.get(8)?,
                content_type,
                has_code_blocks: has_code,
                has_terminal_output: has_terminal,
                files_edited: Vec::new(), // TODO: Parse from raw_json
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn search_conversations(&self, query: &str) -> Result<Vec<Conversation>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT c.id, c.source_version, c.original_title, cat.name, c.message_count, 
                    c.is_favorite, c.user_tags
             FROM conversations c
             LEFT JOIN categories cat ON c.category_id = cat.id
             WHERE c.is_archived = 0 AND c.original_title LIKE ?
             ORDER BY c.imported_at DESC
             LIMIT 50",
        )?;

        let pattern = format!("%{}%", query);
        let rows = stmt.query_map(params![pattern], |row| {
            let tags_json: String = row
                .get::<_, Option<String>>(6)?
                .unwrap_or_else(|| "[]".to_string());
            let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();

            Ok(Conversation {
                id: row.get(0)?,
                source_version: row.get(1)?,
                title: row
                    .get::<_, Option<String>>(2)?
                    .unwrap_or_else(|| "Untitled".to_string()),
                category: row
                    .get::<_, Option<String>>(3)?
                    .unwrap_or_else(|| "Uncategorized".to_string()),
                message_count: row.get(4)?,
                is_favorite: row.get::<_, i32>(5)? != 0,
                user_tags: tags,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn get_stats(&self) -> Result<(usize, usize, usize)> {
        let conn = self.conn.lock().unwrap();

        let total: usize = conn.query_row(
            "SELECT COUNT(*) FROM conversations WHERE is_archived = 0",
            [],
            |row| row.get(0),
        )?;

        let messages: usize =
            conn.query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))?;

        let favorites: usize = conn.query_row(
            "SELECT COUNT(*) FROM conversations WHERE is_favorite = 1",
            [],
            |row| row.get(0),
        )?;

        Ok((total, messages, favorites))
    }

    /// Get detailed message type statistics
    pub fn get_detailed_stats(&self) -> Result<MessageStats> {
        let conn = self.conn.lock().unwrap();

        let user_messages: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM messages WHERE role = 'user'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let assistant_messages: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM messages WHERE role = 'assistant'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let tool_calls: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM messages WHERE tool_name IS NOT NULL AND tool_name != ''",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let with_thinking: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM messages WHERE thinking IS NOT NULL AND thinking != ''",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let with_code: usize = conn
            .query_row(
                "SELECT COUNT(*) FROM messages WHERE content LIKE '%```%'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let bookmarks: usize = conn
            .query_row("SELECT COUNT(*) FROM bookmarks", [], |row| row.get(0))
            .unwrap_or(0);

        Ok(MessageStats {
            user_messages,
            assistant_messages,
            tool_calls,
            with_thinking,
            with_code,
            bookmarks,
        })
    }

    pub fn toggle_favorite(&self, conversation_id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE conversations SET is_favorite = NOT is_favorite WHERE id = ?",
            params![conversation_id],
        )?;
        Ok(())
    }

    /// Clear all imported data (for re-import)
    pub fn clear_all(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        // First, save favorites to a temp structure
        let mut favorites: Vec<String> = Vec::new();
        {
            let mut stmt = conn.prepare("SELECT id FROM conversations WHERE is_favorite = 1")?;
            let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
            for id in rows.flatten() {
                favorites.push(id);
            }
        }

        // Store favorites in config table for persistence
        if !favorites.is_empty() {
            let favorites_json = serde_json::to_string(&favorites).unwrap_or_default();
            conn.execute(
                "INSERT OR REPLACE INTO config (key, value) VALUES ('preserved_favorites', ?1)",
                [&favorites_json],
            )?;
        }

        conn.execute("DELETE FROM messages", [])?;
        conn.execute("DELETE FROM conversations", [])?;
        // Note: Bookmarks are NOT cleared - they persist across cache clears
        Ok(())
    }

    // ==================== CONFIG/SETTINGS ====================

    pub fn get_config(&self, key: &str) -> Option<String> {
        let conn = self.conn.lock().unwrap();
        conn.query_row("SELECT value FROM config WHERE key = ?1", [key], |row| {
            row.get(0)
        })
        .ok()
    }

    pub fn set_config(&self, key: &str, value: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO config (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn get_config_f32(&self, key: &str, default: f32) -> f32 {
        self.get_config(key)
            .and_then(|s| s.parse().ok())
            .unwrap_or(default)
    }

    pub fn get_config_usize(&self, key: &str, default: usize) -> usize {
        self.get_config(key)
            .and_then(|s| s.parse().ok())
            .unwrap_or(default)
    }

    pub fn get_config_bool(&self, key: &str, default: bool) -> bool {
        self.get_config(key)
            .map(|s| s == "true" || s == "1")
            .unwrap_or(default)
    }

    /// Restore favorites after reimport
    pub fn restore_favorites(&self) -> Result<usize> {
        let conn = self.conn.lock().unwrap();

        // Get preserved favorites from config
        let favorites_json: Option<String> = conn
            .query_row(
                "SELECT value FROM config WHERE key = 'preserved_favorites'",
                [],
                |row| row.get(0),
            )
            .ok();

        let mut restored = 0;
        if let Some(json) = favorites_json {
            if let Ok(favorites) = serde_json::from_str::<Vec<String>>(&json) {
                for conv_id in favorites {
                    if conn
                        .execute(
                            "UPDATE conversations SET is_favorite = 1 WHERE id = ?1",
                            [&conv_id],
                        )
                        .is_ok()
                    {
                        restored += 1;
                    }
                }
            }
            // Clear the preserved favorites after restoring
            let _ = conn.execute("DELETE FROM config WHERE key = 'preserved_favorites'", []);
        }

        Ok(restored)
    }

    // ==================== BOOKMARK METHODS ====================

    pub fn add_bookmark(
        &self,
        conv_id: &str,
        msg_id: &str,
        msg_seq: usize,
        label: Option<&str>,
        note: Option<&str>,
        color: &str,
    ) -> Result<String> {
        let conn = self.conn.lock().unwrap();
        let id = uuid::Uuid::new_v4().to_string();

        conn.execute(
            "INSERT INTO bookmarks (id, conversation_id, message_id, message_sequence, label, note, color)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![id, conv_id, msg_id, msg_seq, label, note, color],
        )?;

        Ok(id)
    }

    pub fn get_bookmarks(&self, conv_id: &str) -> Result<Vec<Bookmark>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, message_id, message_sequence, label, note, created_at, color
             FROM bookmarks WHERE conversation_id = ?1 ORDER BY message_sequence"
        )?;

        let rows = stmt.query_map([conv_id], |row| {
            Ok(Bookmark {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                message_id: row.get(2)?,
                message_sequence: row.get(3)?,
                label: row.get(4)?,
                note: row.get(5)?,
                created_at: row.get(6)?,
                color: row.get(7)?,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn get_all_bookmarks(&self) -> Result<Vec<Bookmark>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, message_id, message_sequence, label, note, created_at, color
             FROM bookmarks ORDER BY created_at DESC"
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(Bookmark {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                message_id: row.get(2)?,
                message_sequence: row.get(3)?,
                label: row.get(4)?,
                note: row.get(5)?,
                created_at: row.get(6)?,
                color: row.get(7)?,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn update_bookmark(
        &self,
        bookmark_id: &str,
        label: Option<&str>,
        note: Option<&str>,
        color: Option<&str>,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        if let Some(l) = label {
            conn.execute(
                "UPDATE bookmarks SET label = ?1 WHERE id = ?2",
                params![l, bookmark_id],
            )?;
        }
        if let Some(n) = note {
            conn.execute(
                "UPDATE bookmarks SET note = ?1 WHERE id = ?2",
                params![n, bookmark_id],
            )?;
        }
        if let Some(c) = color {
            conn.execute(
                "UPDATE bookmarks SET color = ?1 WHERE id = ?2",
                params![c, bookmark_id],
            )?;
        }

        Ok(())
    }

    pub fn delete_bookmark(&self, bookmark_id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM bookmarks WHERE id = ?1", [bookmark_id])?;
        Ok(())
    }

    /// Reattach bookmarks after reimport - finds new message IDs by sequence number
    pub fn reattach_bookmarks(&self, conv_id: &str) -> Result<Vec<(String, bool)>> {
        let conn = self.conn.lock().unwrap();

        // Get all bookmarks for this conversation
        let mut stmt =
            conn.prepare("SELECT id, message_sequence FROM bookmarks WHERE conversation_id = ?1")?;

        let bookmarks: Vec<(String, usize)> = stmt
            .query_map([conv_id], |row| Ok((row.get(0)?, row.get(1)?)))?
            .collect::<Result<Vec<_>, _>>()?;

        let mut results = Vec::new();

        for (bookmark_id, seq) in bookmarks {
            // Try to find a message with this sequence
            let new_msg_id: Option<String> = conn
                .query_row(
                    "SELECT id FROM messages WHERE conversation_id = ?1 AND sequence = ?2",
                    params![conv_id, seq],
                    |row| row.get(0),
                )
                .ok();

            if let Some(msg_id) = new_msg_id {
                conn.execute(
                    "UPDATE bookmarks SET message_id = ?1 WHERE id = ?2",
                    params![msg_id, bookmark_id],
                )?;
                results.push((bookmark_id, true));
            } else {
                results.push((bookmark_id, false));
            }
        }

        Ok(results)
    }

    // ==================== DISPLAY PREFERENCES ====================

    pub fn get_display_preferences(&self) -> Result<Vec<DisplayPreference>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT content_type, alignment, style, collapsed_by_default FROM display_preferences",
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(DisplayPreference {
                content_type: row.get(0)?,
                alignment: row.get(1)?,
                style: row.get(2)?,
                collapsed_by_default: row.get::<_, i32>(3)? != 0,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    pub fn set_display_preference(
        &self,
        content_type: &str,
        alignment: &str,
        style: &str,
        collapsed: bool,
    ) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO display_preferences (content_type, alignment, style, collapsed_by_default)
             VALUES (?1, ?2, ?3, ?4)",
            params![content_type, alignment, style, collapsed as i32],
        )?;
        Ok(())
    }

    pub fn import_from_cursor(&self, db_path: PathBuf, version: &str) -> Result<(usize, usize)> {
        let src_conn =
            Connection::open_with_flags(&db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;

        let mut imported = 0;
        let mut skipped = 0;

        // Find all conversation IDs from bubbleId keys
        let mut stmt = src_conn.prepare(
            "SELECT DISTINCT substr(key, 10, 36) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'",
        )?;
        let conv_ids: Vec<String> = stmt
            .query_map([], |row| row.get(0))?
            .filter_map(|r| r.ok())
            .collect();

        let dst_conn = self.conn.lock().unwrap();

        for conv_id in conv_ids {
            let exists: i32 = dst_conn.query_row(
                "SELECT COUNT(*) FROM conversations WHERE id = ?",
                params![&conv_id],
                |row| row.get(0),
            )?;

            if exists > 0 {
                skipped += 1;
                continue;
            }

            let mut msg_stmt = src_conn
                .prepare("SELECT key, value FROM cursorDiskKV WHERE key LIKE ? ORDER BY key")?;
            let pattern = format!("bubbleId:{}:%", conv_id);

            let mut messages: Vec<(
                String,
                String,
                String,
                usize,
                Option<ToolCallInfo>,
                Option<String>,
            )> = Vec::new();
            let mut title_candidates = Vec::new();

            // Query and handle value as either BLOB or TEXT
            let rows = msg_stmt.query_map(params![pattern], |row| {
                let key: String = row.get(0)?;
                let value_bytes: Vec<u8> = row
                    .get::<_, Vec<u8>>(1)
                    .or_else(|_| row.get::<_, String>(1).map(|s| s.into_bytes()))?;
                Ok((key, value_bytes))
            })?;

            for row_result in rows {
                let (key, value) = match row_result {
                    Ok(r) => r,
                    Err(_) => continue,
                };

                let msg_id = key.split(':').last().unwrap_or("").to_string();

                if let Ok(data) = serde_json::from_slice::<Value>(&value) {
                    let msg_type = data.get("type").and_then(|v| v.as_i64()).unwrap_or(0);

                    // Determine role based on type and toolFormerData presence
                    let (base_role, is_tool_call) = if data.get("toolFormerData").is_some() {
                        ("tool_call", true)
                    } else if msg_type == 1 {
                        ("user", false)
                    } else {
                        ("assistant", false)
                    };

                    let (content, tool_call, thinking) = extract_message_content(&data);

                    // Skip completely empty messages (unless they're tool calls)
                    if content.is_empty() && !is_tool_call && thinking.is_none() {
                        continue;
                    }

                    // Collect title candidates from user messages
                    if base_role == "user" && !content.is_empty() && title_candidates.len() < 3 {
                        title_candidates.push(content.chars().take(100).collect::<String>());
                    }

                    messages.push((
                        msg_id,
                        base_role.to_string(),
                        content,
                        messages.len(),
                        tool_call,
                        thinking,
                    ));
                }
            }

            if messages.is_empty() {
                continue;
            }

            let title = title_candidates
                .first()
                .map(|t| {
                    let truncated: String = t.chars().take(60).collect();
                    if truncated.len() < t.len() {
                        format!("{}...", truncated)
                    } else {
                        truncated
                    }
                })
                .unwrap_or_else(|| "Untitled".to_string());

            dst_conn.execute(
                "INSERT INTO conversations (id, source_version, original_title, message_count, category_id, imported_at)
                 VALUES (?, ?, ?, ?, 1, datetime('now'))",
                params![conv_id, version, title, messages.len()],
            )?;

            for (msg_id, role, content, seq, tool_call, thinking) in messages {
                let (tool_name, tool_args, tool_status) = match &tool_call {
                    Some(tc) => (
                        Some(tc.name.clone()),
                        Some(tc.args.clone()),
                        Some(tc.status.clone()),
                    ),
                    None => (None, None, None),
                };

                dst_conn.execute(
                    "INSERT OR IGNORE INTO messages (id, conversation_id, sequence, role, content, tool_name, tool_args, tool_status, thinking)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    params![msg_id, conv_id, seq, role, content, tool_name, tool_args, tool_status, thinking],
                )?;
            }

            imported += 1;
        }

        Ok((imported, skipped))
    }

    pub fn import_all(&self) -> Result<(usize, usize)> {
        let home = dirs::home_dir().context("No home directory")?;
        let mut total_imported = 0;
        let mut total_skipped = 0;

        let main_db = home.join(".config/Cursor/User/globalStorage/state.vscdb");
        if main_db.exists() {
            let (i, s) = self.import_from_cursor(main_db, "default")?;
            total_imported += i;
            total_skipped += s;
        }

        for entry in std::fs::read_dir(&home)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();

            if name.starts_with(".cursor-") && entry.file_type()?.is_dir() {
                let version = name.strip_prefix(".cursor-").unwrap_or(&name).to_string();
                let db_path = entry.path().join("User/globalStorage/state.vscdb");

                if db_path.exists() {
                    let (i, s) = self.import_from_cursor(db_path, &version)?;
                    total_imported += i;
                    total_skipped += s;
                }
            }
        }

        Ok((total_imported, total_skipped))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_db() -> ChatDatabase {
        let temp_dir =
            std::env::temp_dir().join(format!("cursor-studio-test-{}", uuid::Uuid::new_v4()));
        ChatDatabase::new_with_path(temp_dir).unwrap()
    }

    #[test]
    fn test_database_creation() {
        let db = create_test_db();
        assert!(db.get_path().parent().unwrap().exists());
    }

    #[test]
    fn test_config_get_set() {
        let db = create_test_db();

        // Set a config value
        db.set_config("test.key", "test_value").unwrap();

        // Get it back
        let value = db.get_config("test.key");
        assert_eq!(value, Some("test_value".to_string()));
    }

    #[test]
    fn test_config_f32() {
        let db = create_test_db();

        // Set a float config
        db.set_config("test.float", "3.14").unwrap();

        // Get it back
        let value = db.get_config_f32("test.float", 0.0);
        assert!((value - 3.14).abs() < 0.001);

        // Default for missing key
        let default = db.get_config_f32("missing.key", 42.0);
        assert!((default - 42.0).abs() < 0.001);
    }

    #[test]
    fn test_config_usize() {
        let db = create_test_db();

        db.set_config("test.count", "100").unwrap();

        let value = db.get_config_usize("test.count", 0);
        assert_eq!(value, 100);

        let default = db.get_config_usize("missing.key", 50);
        assert_eq!(default, 50);
    }

    #[test]
    fn test_config_bool() {
        let db = create_test_db();

        db.set_config("test.enabled", "true").unwrap();
        assert!(db.get_config_bool("test.enabled", false));

        db.set_config("test.disabled", "false").unwrap();
        assert!(!db.get_config_bool("test.disabled", true));

        // Default for missing
        assert!(db.get_config_bool("missing.key", true));
    }

    #[test]
    fn test_display_preferences() {
        let db = create_test_db();

        // Set a preference (content_type, alignment, style, collapsed)
        db.set_display_preference("user", "right", "default", false)
            .unwrap();

        // Get all preferences
        let prefs = db.get_display_preferences().unwrap();
        let user_pref = prefs.iter().find(|p| p.content_type == "user");
        assert!(user_pref.is_some());
        assert_eq!(user_pref.unwrap().alignment, "right");
    }

    #[test]
    fn test_bookmarks() {
        let db = create_test_db();

        // Add a bookmark (conv_id, msg_id, msg_seq, label, note, color)
        let result = db.add_bookmark("conv123", "msg456", 1, Some("Test Label"), None, "gold");
        assert!(result.is_ok());

        // Get bookmarks
        let bookmarks = db.get_bookmarks("conv123").unwrap();
        assert_eq!(bookmarks.len(), 1);
        assert_eq!(bookmarks[0].conversation_id, "conv123");
        assert_eq!(bookmarks[0].message_id, "msg456");
        assert_eq!(bookmarks[0].label, Some("Test Label".to_string()));
    }

    #[test]
    fn test_delete_bookmark() {
        let db = create_test_db();

        // Add a bookmark
        db.add_bookmark("conv123", "msg456", 1, None, None, "gold")
            .unwrap();

        // Verify it exists
        let bookmarks = db.get_bookmarks("conv123").unwrap();
        assert_eq!(bookmarks.len(), 1);
        let bookmark_id = &bookmarks[0].id;

        // Delete it
        db.delete_bookmark(bookmark_id).unwrap();

        // Verify it's gone
        let bookmarks = db.get_bookmarks("conv123").unwrap();
        assert_eq!(bookmarks.len(), 0);
    }
}
