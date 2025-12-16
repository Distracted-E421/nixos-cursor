//! Conversation Browser Component
//!
//! This module provides a rich conversation browser for cursor-studio,
//! allowing users to view, search, and export synced Cursor conversations.
//!
//! Part of the Data Pipeline Control objectives for v0.3.0.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use chrono::{DateTime, Utc};
use eframe::egui;
use parking_lot::RwLock;
use rusqlite::{Connection, Result as SqlResult};
use serde::{Deserialize, Serialize};

/// A synced conversation from Cursor
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub name: String,
    pub workspace: Option<String>,
    pub model: Option<String>,
    pub created_at: Option<i64>,
    pub updated_at: Option<i64>,
    pub message_count: i32,
    pub is_agentic: bool,
    pub is_archived: bool,
    pub context_usage_percent: f32,
    pub total_lines_added: i32,
    pub total_lines_removed: i32,
}

/// A message within a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub message_type: MessageType,
    pub created_at: Option<i64>,
    pub model_name: Option<String>,
    pub token_count: i32,
    pub has_thinking: bool,
    pub has_tool_calls: bool,
    pub has_code_changes: bool,
    pub content: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageType {
    User,
    Assistant,
    System,
}

impl From<i32> for MessageType {
    fn from(value: i32) -> Self {
        match value {
            1 => MessageType::User,
            2 => MessageType::Assistant,
            _ => MessageType::System,
        }
    }
}

/// Filter options for conversation list
#[derive(Debug, Clone, Default)]
pub struct ConversationFilter {
    pub search_query: String,
    pub workspace: Option<String>,
    pub model: Option<String>,
    pub only_agentic: bool,
    pub include_archived: bool,
    pub date_from: Option<DateTime<Utc>>,
    pub date_to: Option<DateTime<Utc>>,
}

/// Statistics about synced data
#[derive(Debug, Clone, Default)]
pub struct SyncStats {
    pub total_conversations: i32,
    pub total_messages: i32,
    pub total_tool_calls: i32,
    pub database_size_bytes: u64,
    pub last_sync: Option<String>,
}

/// The conversation browser state
pub struct ConversationBrowser {
    /// Path to the sync database
    db_path: PathBuf,
    
    /// Cached conversations
    conversations: Vec<Conversation>,
    
    /// Currently selected conversation
    selected: Option<usize>,
    
    /// Messages for selected conversation
    messages: Vec<Message>,
    
    /// Current filter
    filter: ConversationFilter,
    
    /// Sync statistics
    stats: SyncStats,
    
    /// Available workspaces
    workspaces: Vec<String>,
    
    /// Available models
    models: Vec<String>,
    
    /// Error message to display
    error: Option<String>,
    
    /// Whether data needs refresh
    needs_refresh: bool,
}

impl Default for ConversationBrowser {
    fn default() -> Self {
        let db_path = dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cursor-studio")
            .join("conversations.db");
        
        Self {
            db_path,
            conversations: Vec::new(),
            selected: None,
            messages: Vec::new(),
            filter: ConversationFilter::default(),
            stats: SyncStats::default(),
            workspaces: Vec::new(),
            models: Vec::new(),
            error: None,
            needs_refresh: true,
        }
    }
}

impl ConversationBrowser {
    /// Create a new conversation browser with custom db path
    pub fn new(db_path: PathBuf) -> Self {
        Self {
            db_path,
            needs_refresh: true,
            ..Default::default()
        }
    }
    
    /// Load conversations from database
    pub fn load_conversations(&mut self) -> SqlResult<()> {
        let conn = Connection::open(&self.db_path)?;
        
        // Build query with filters
        let mut sql = String::from(
            "SELECT id, name, workspace, model, created_at, updated_at, 
                    message_count, is_agentic, is_archived, raw_data
             FROM conversations WHERE 1=1"
        );
        let mut params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
        
        if !self.filter.search_query.is_empty() {
            sql.push_str(" AND name LIKE ?");
            params.push(Box::new(format!("%{}%", self.filter.search_query)));
        }
        
        if let Some(ref workspace) = self.filter.workspace {
            sql.push_str(" AND workspace = ?");
            params.push(Box::new(workspace.clone()));
        }
        
        if !self.filter.include_archived {
            sql.push_str(" AND is_archived = 0");
        }
        
        sql.push_str(" ORDER BY updated_at DESC");
        
        let mut stmt = conn.prepare(&sql)?;
        let param_refs: Vec<&dyn rusqlite::ToSql> = params.iter().map(|p| p.as_ref()).collect();
        
        let rows = stmt.query_map(param_refs.as_slice(), |row| {
            // Parse raw_data JSON for additional fields
            let raw_data: String = row.get(9)?;
            let extra: serde_json::Value = serde_json::from_str(&raw_data)
                .unwrap_or(serde_json::Value::Null);
            
            Ok(Conversation {
                id: row.get(0)?,
                name: row.get(1)?,
                workspace: row.get(2)?,
                model: row.get(3)?,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
                message_count: row.get::<_, Option<i32>>(6)?.unwrap_or(0),
                is_agentic: row.get::<_, i32>(7)? != 0,
                is_archived: row.get::<_, i32>(8)? != 0,
                context_usage_percent: extra["contextUsagePercent"]
                    .as_f64()
                    .unwrap_or(0.0) as f32,
                total_lines_added: extra["totalLinesAdded"]
                    .as_i64()
                    .unwrap_or(0) as i32,
                total_lines_removed: extra["totalLinesRemoved"]
                    .as_i64()
                    .unwrap_or(0) as i32,
            })
        })?;
        
        self.conversations = rows.filter_map(|r| r.ok()).collect();
        self.needs_refresh = false;
        
        // Update stats
        self.load_stats(&conn)?;
        
        // Load unique workspaces and models
        self.load_metadata(&conn)?;
        
        Ok(())
    }
    
    /// Load messages for a conversation
    pub fn load_messages(&mut self, conversation_id: &str) -> SqlResult<()> {
        let conn = Connection::open(&self.db_path)?;
        
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, type, created_at, model_name,
                    token_count, has_thinking, has_tool_calls, has_code_changes, raw_data
             FROM messages
             WHERE conversation_id = ?
             ORDER BY created_at"
        )?;
        
        let rows = stmt.query_map([conversation_id], |row| {
            Ok(Message {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                message_type: MessageType::from(row.get::<_, i32>(2)?),
                created_at: row.get(3)?,
                model_name: row.get(4)?,
                token_count: row.get::<_, Option<i32>>(5)?.unwrap_or(0),
                has_thinking: row.get::<_, i32>(6)? != 0,
                has_tool_calls: row.get::<_, i32>(7)? != 0,
                has_code_changes: row.get::<_, i32>(8)? != 0,
                content: None, // Load on demand from raw_data
            })
        })?;
        
        self.messages = rows.filter_map(|r| r.ok()).collect();
        Ok(())
    }
    
    /// Load sync statistics
    fn load_stats(&mut self, conn: &Connection) -> SqlResult<()> {
        self.stats.total_conversations = conn.query_row(
            "SELECT COUNT(*) FROM conversations",
            [],
            |row| row.get(0),
        )?;
        
        self.stats.total_messages = conn.query_row(
            "SELECT COUNT(*) FROM messages",
            [],
            |row| row.get(0),
        )?;
        
        self.stats.total_tool_calls = conn.query_row(
            "SELECT COUNT(*) FROM tool_calls",
            [],
            |row| row.get(0),
        ).unwrap_or(0);
        
        self.stats.last_sync = conn.query_row(
            "SELECT value FROM sync_metadata WHERE key = 'last_sync'",
            [],
            |row| row.get(0),
        ).ok();
        
        // Get database file size
        if let Ok(metadata) = std::fs::metadata(&self.db_path) {
            self.stats.database_size_bytes = metadata.len();
        }
        
        Ok(())
    }
    
    /// Load unique workspaces and models
    fn load_metadata(&mut self, conn: &Connection) -> SqlResult<()> {
        let mut stmt = conn.prepare(
            "SELECT DISTINCT workspace FROM conversations WHERE workspace IS NOT NULL"
        )?;
        self.workspaces = stmt.query_map([], |row| row.get(0))?
            .filter_map(|r| r.ok())
            .collect();
        
        let mut stmt = conn.prepare(
            "SELECT DISTINCT model_name FROM messages WHERE model_name IS NOT NULL"
        )?;
        self.models = stmt.query_map([], |row| row.get(0))?
            .filter_map(|r| r.ok())
            .collect();
        
        Ok(())
    }
    
    /// Render the conversation browser UI
    pub fn ui(&mut self, ui: &mut egui::Ui) {
        // Refresh data if needed
        if self.needs_refresh {
            if let Err(e) = self.load_conversations() {
                self.error = Some(format!("Failed to load: {}", e));
            }
        }
        
        ui.horizontal(|ui| {
            // Left panel: Conversation list
            ui.vertical(|ui| {
                ui.set_min_width(300.0);
                ui.set_max_width(400.0);
                
                self.render_filter_panel(ui);
                ui.separator();
                self.render_conversation_list(ui);
            });
            
            ui.separator();
            
            // Right panel: Selected conversation
            ui.vertical(|ui| {
                if let Some(idx) = self.selected {
                    if idx < self.conversations.len() {
                        self.render_conversation_detail(ui, idx);
                    }
                } else {
                    ui.centered_and_justified(|ui| {
                        ui.label("Select a conversation to view details");
                    });
                }
            });
        });
        
        // Stats panel at bottom
        ui.separator();
        self.render_stats_panel(ui);
    }
    
    /// Render the filter/search panel
    fn render_filter_panel(&mut self, ui: &mut egui::Ui) {
        ui.heading("🔍 Filter");
        
        ui.horizontal(|ui| {
            ui.label("Search:");
            if ui.text_edit_singleline(&mut self.filter.search_query).changed() {
                self.needs_refresh = true;
            }
        });
        
        ui.horizontal(|ui| {
            ui.checkbox(&mut self.filter.only_agentic, "Agentic only");
            ui.checkbox(&mut self.filter.include_archived, "Include archived");
        });
        
        if ui.button("🔄 Refresh").clicked() {
            self.needs_refresh = true;
        }
    }
    
    /// Render the conversation list
    fn render_conversation_list(&mut self, ui: &mut egui::Ui) {
        ui.heading(format!("💬 Conversations ({})", self.conversations.len()));
        
        egui::ScrollArea::vertical()
            .max_height(400.0)
            .show(ui, |ui| {
                for (idx, conv) in self.conversations.iter().enumerate() {
                    let is_selected = self.selected == Some(idx);
                    
                    let response = ui.selectable_label(
                        is_selected,
                        format!(
                            "{} {} ({})",
                            if conv.is_agentic { "🤖" } else { "💬" },
                            conv.name,
                            conv.message_count
                        ),
                    );
                    
                    if response.clicked() {
                        self.selected = Some(idx);
                        if let Err(e) = self.load_messages(&conv.id) {
                            self.error = Some(format!("Failed to load messages: {}", e));
                        }
                    }
                    
                    // Show context bar
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing.x = 0.0;
                        let bar_width = 150.0;
                        let filled = bar_width * (conv.context_usage_percent / 100.0);
                        
                        let color = if conv.context_usage_percent > 80.0 {
                            egui::Color32::RED
                        } else if conv.context_usage_percent > 50.0 {
                            egui::Color32::YELLOW
                        } else {
                            egui::Color32::GREEN
                        };
                        
                        let (rect, _) = ui.allocate_exact_size(
                            egui::vec2(bar_width, 4.0),
                            egui::Sense::hover(),
                        );
                        
                        ui.painter().rect_filled(
                            rect,
                            2.0,
                            egui::Color32::DARK_GRAY,
                        );
                        
                        let filled_rect = egui::Rect::from_min_size(
                            rect.min,
                            egui::vec2(filled, 4.0),
                        );
                        ui.painter().rect_filled(filled_rect, 2.0, color);
                        
                        ui.label(format!(" {:.0}%", conv.context_usage_percent));
                    });
                    
                    ui.add_space(4.0);
                }
            });
    }
    
    /// Render conversation detail view
    fn render_conversation_detail(&self, ui: &mut egui::Ui, idx: usize) {
        let conv = &self.conversations[idx];
        
        ui.heading(format!("📋 {}", conv.name));
        
        ui.horizontal(|ui| {
            ui.label(format!("Model: {}", conv.model.as_deref().unwrap_or("Unknown")));
            if conv.is_agentic {
                ui.colored_label(egui::Color32::GREEN, "🤖 Agentic");
            }
            if conv.is_archived {
                ui.colored_label(egui::Color32::GRAY, "📦 Archived");
            }
        });
        
        ui.label(format!(
            "Lines: +{} / -{}",
            conv.total_lines_added, conv.total_lines_removed
        ));
        
        ui.separator();
        ui.heading("Messages");
        
        egui::ScrollArea::vertical().show(ui, |ui| {
            for msg in &self.messages {
                let (icon, color) = match msg.message_type {
                    MessageType::User => ("👤", egui::Color32::LIGHT_BLUE),
                    MessageType::Assistant => ("🤖", egui::Color32::LIGHT_GREEN),
                    MessageType::System => ("⚙️", egui::Color32::GRAY),
                };
                
                ui.horizontal(|ui| {
                    ui.colored_label(color, icon);
                    if let Some(ref model) = msg.model_name {
                        ui.label(format!("[{}]", model));
                    }
                    if msg.has_thinking {
                        ui.label("💭");
                    }
                    if msg.has_tool_calls {
                        ui.label("🔧");
                    }
                    if msg.has_code_changes {
                        ui.label("📝");
                    }
                    ui.label(format!("({}t)", msg.token_count));
                });
                
                ui.add_space(2.0);
            }
        });
    }
    
    /// Render stats panel
    fn render_stats_panel(&self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.label(format!("💬 {} conversations", self.stats.total_conversations));
            ui.separator();
            ui.label(format!("📝 {} messages", self.stats.total_messages));
            ui.separator();
            ui.label(format!("🔧 {} tool calls", self.stats.total_tool_calls));
            ui.separator();
            ui.label(format!(
                "💾 {:.2} MB",
                self.stats.database_size_bytes as f64 / 1024.0 / 1024.0
            ));
            if let Some(ref last_sync) = self.stats.last_sync {
                ui.separator();
                ui.label(format!("🕐 {}", last_sync));
            }
        });
        
        if let Some(ref error) = self.error {
            ui.colored_label(egui::Color32::RED, format!("❌ {}", error));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_message_type_from() {
        assert_eq!(MessageType::from(1), MessageType::User);
        assert_eq!(MessageType::from(2), MessageType::Assistant);
        assert_eq!(MessageType::from(0), MessageType::System);
        assert_eq!(MessageType::from(99), MessageType::System);
    }
    
    #[test]
    fn test_default_browser() {
        let browser = ConversationBrowser::default();
        assert!(browser.conversations.is_empty());
        assert!(browser.needs_refresh);
    }
}
