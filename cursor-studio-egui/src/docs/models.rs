//! Data models for cursor-docs integration

use serde::{Deserialize, Serialize};

/// Status of a documentation source
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SourceStatus {
    Pending,
    Indexing,
    Indexed,
    Failed,
}

impl SourceStatus {
    pub fn icon(&self) -> &'static str {
        match self {
            SourceStatus::Pending => "⏸️",
            SourceStatus::Indexing => "⏳",
            SourceStatus::Indexed => "✅",
            SourceStatus::Failed => "❌",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            SourceStatus::Pending => "Pending",
            SourceStatus::Indexing => "Indexing",
            SourceStatus::Indexed => "Indexed",
            SourceStatus::Failed => "Failed",
        }
    }
}

impl Default for SourceStatus {
    fn default() -> Self {
        SourceStatus::Pending
    }
}

/// A documentation source (website/API docs)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocSource {
    pub id: String,
    pub url: String,
    pub name: String,
    pub status: SourceStatus,
    pub chunks_count: usize,
    pub last_indexed: Option<String>,
    pub created_at: String,
    #[serde(default)]
    pub security_tier: Option<String>,
    #[serde(default)]
    pub alerts_count: usize,
}

impl DocSource {
    pub fn display_name(&self) -> &str {
        if self.name.is_empty() {
            &self.url
        } else {
            &self.name
        }
    }
}

/// A chunk of indexed content
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocChunk {
    pub id: String,
    pub source_id: String,
    pub url: String,
    pub title: String,
    pub content: String,
    pub position: usize,
}

/// Search result with relevance score
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub chunk: DocChunk,
    pub score: f32,
    pub snippet: String,
    pub source_name: String,
}

/// Add source options
#[derive(Debug, Clone, Default)]
pub struct AddSourceOptions {
    pub name: Option<String>,
    pub max_pages: usize,
    pub follow_links: bool,
    pub force: bool,
}

/// Security alert from cursor-docs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityAlert {
    pub id: String,
    pub source_id: String,
    pub source_url: String,
    #[serde(rename = "type")]
    pub alert_type: String,
    pub severity: u8,
    pub severity_label: String,
    pub description: String,
    pub created_at: String,
}

impl SecurityAlert {
    pub fn severity_icon(&self) -> &'static str {
        match self.severity {
            5 => "🚨",
            4 => "⚠️",
            3 => "⚡",
            2 => "ℹ️",
            _ => "📝",
        }
    }

    pub fn severity_color(&self) -> [u8; 3] {
        match self.severity {
            5 => [239, 68, 68],   // Red
            4 => [249, 115, 22],  // Orange
            3 => [234, 179, 8],   // Yellow
            2 => [59, 130, 246],  // Blue
            _ => [156, 163, 175], // Gray
        }
    }
}

/// Stats from cursor-docs
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DocsStats {
    pub total_sources: usize,
    pub total_chunks: usize,
    pub indexed_sources: usize,
    pub pending_sources: usize,
    pub failed_sources: usize,
    pub total_alerts: usize,
    pub recent_alerts: usize,
}

/// Quarantined item pending review
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuarantinedItem {
    pub id: String,
    pub source_name: String,
    pub source_url: String,
    pub tier: String,
    pub alerts: Vec<SecurityAlert>,
    pub validated_at: String,
}

/// Backend connection status
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

impl BackendStatus {
    pub fn icon(&self) -> &'static str {
        match self {
            BackendStatus::Disconnected => "⚪",
            BackendStatus::Connecting => "🔄",
            BackendStatus::Connected => "🟢",
            BackendStatus::Error => "🔴",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            BackendStatus::Disconnected => "Disconnected",
            BackendStatus::Connecting => "Connecting...",
            BackendStatus::Connected => "Connected",
            BackendStatus::Error => "Error",
        }
    }
}

