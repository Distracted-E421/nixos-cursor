//! Chat history parsing and synchronization module.
//!
//! This module provides functionality to:
//! - Parse Cursor IDE's SQLite database to extract conversations
//! - Store conversations in SurrealDB for sync and search
//! - Merge conversations from multiple devices using CRDTs
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
//! │  Cursor SQLite  │────▶│  CursorParser   │────▶│  SurrealStore   │
//! │  (state.vscdb)  │     │  (read-only)    │     │  (sync-capable) │
//! └─────────────────┘     └─────────────────┘     └─────────────────┘
//!                                                         │
//!                                                         ▼
//!                                                 ┌─────────────────┐
//!                                                 │   P2P / Server  │
//!                                                 │   Sync Layer    │
//!                                                 └─────────────────┘
//! ```

pub mod client;
pub mod crdt;
pub mod cursor_parser;
pub mod models;
pub mod p2p;
pub mod server;
pub mod surreal;
pub mod sync_service;

pub use client::{ClientConfig, SyncClient};
pub use crdt::{ClockOrdering, DeviceId, SyncState, VectorClock};
pub use cursor_parser::CursorParser;
pub use models::*;
pub use p2p::{P2PConfig, P2PEvent, P2PService, SyncRequest as P2PSyncRequest, SyncResponse as P2PSyncResponse};
pub use server::{start_server, ServerConfig};
pub use surreal::{MergeResult, SurrealStore, SyncedConversation};
pub use sync_service::{ImportResult, SyncService, SyncStats, SyncStatus};
