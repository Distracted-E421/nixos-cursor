//! Chat history parsing and synchronization module.
//!
//! This module provides functionality to:
//! - Parse Cursor IDE's SQLite database to extract conversations
//! - Store conversations in SurrealDB for sync and search
//! - Merge conversations from multiple devices using CRDTs

pub mod models;
pub mod cursor_parser;

pub use models::*;
pub use cursor_parser::CursorParser;
