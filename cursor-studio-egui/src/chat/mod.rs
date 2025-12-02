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

// Core modules - always available
pub mod crdt;
pub mod cursor_parser;
pub mod models;

// Sync modules - require surrealdb
#[cfg(feature = "surrealdb-store")]
pub mod client;
#[cfg(feature = "surrealdb-store")]
pub mod sync_service;

// Optional modules based on features
#[cfg(feature = "p2p-sync")]
pub mod p2p;

#[cfg(feature = "server-sync")]
pub mod server;

#[cfg(feature = "surrealdb-store")]
pub mod surreal;

// Core exports - always available
pub use crdt::{ClockOrdering, DeviceId, SyncState, VectorClock};
pub use cursor_parser::CursorParser;
pub use models::*;

// Sync exports - require surrealdb
#[cfg(feature = "surrealdb-store")]
pub use client::{ClientConfig, SyncClient};
#[cfg(feature = "surrealdb-store")]
pub use sync_service::{ImportResult, SyncService, SyncStats, SyncStatus};

// Conditional exports
#[cfg(feature = "p2p-sync")]
pub use p2p::{P2PConfig, P2PEvent, P2PService, SyncRequest as P2PSyncRequest, SyncResponse as P2PSyncResponse};

#[cfg(feature = "server-sync")]
pub use server::{start_server, ServerConfig};

#[cfg(feature = "surrealdb-store")]
pub use surreal::{MergeResult, SurrealStore, SyncedConversation};
