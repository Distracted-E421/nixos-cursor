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

pub mod crdt;
pub mod cursor_parser;
pub mod models;
pub mod surreal;

pub use crdt::{ClockOrdering, DeviceId, SyncState, VectorClock};
pub use cursor_parser::CursorParser;
pub use models::*;
pub use surreal::{MergeResult, SurrealStore, SyncedConversation};
