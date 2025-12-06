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

pub mod config;
pub mod cursor_db;
pub mod daemon;
pub mod external_db;
pub mod models;
pub mod pipe_client;
pub mod ui;
pub mod watcher;

pub use config::SyncConfig;
pub use cursor_db::CursorDatabaseReader;
pub use daemon::{SyncDaemon, SyncEvent, SyncStats};
pub use external_db::ExternalDatabaseWriter;
pub use models::{Conversation, Message, SyncState, ToolCall};
pub use pipe_client::{
    AsyncPipeClient, ClientError, DaemonCommand, DaemonEvent, DaemonResponse, DaemonStatus,
    PipeClient,
};
pub use ui::{SyncStatusIndicator, SyncStatusPanel};
pub use watcher::DatabaseWatcher;
