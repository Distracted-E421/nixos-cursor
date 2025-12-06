//! Cursor Data Sync Module
//!
//! Watches Cursor's SQLite databases for changes and syncs
//! conversations to an external database for backup and analysis.
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────┐
//! │              SyncDaemon                      │
//! │  ┌──────────┐  ┌──────────────────────────┐ │
//! │  │ Watcher  │─▶│  ┌─────────┐  ┌───────┐  │ │
//! │  │ (notify) │  │  │ Reader  │─▶│Writer │  │ │
//! │  └──────────┘  │  │(Cursor) │  │(Ext)  │  │ │
//! │                │  └─────────┘  └───────┘  │ │
//! │                └──────────────────────────┘ │
//! └─────────────────────────────────────────────┘
//! ```

pub mod daemon;
pub mod watcher;
pub mod cursor_db;
pub mod external_db;
pub mod models;
pub mod config;
pub mod pipe_client;
pub mod ui;

pub use daemon::{SyncDaemon, SyncEvent, SyncStats};
pub use watcher::DatabaseWatcher;
pub use cursor_db::CursorDatabaseReader;
pub use external_db::ExternalDatabaseWriter;
pub use models::{Conversation, Message, ToolCall, SyncState};
pub use config::SyncConfig;
pub use pipe_client::{PipeClient, AsyncPipeClient, DaemonCommand, DaemonResponse, DaemonEvent, DaemonStatus, ClientError};
pub use ui::{SyncStatusPanel, SyncStatusIndicator};
