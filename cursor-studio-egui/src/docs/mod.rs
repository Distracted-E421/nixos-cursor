//! Index Module - Documentation Indexer Interface
//!
//! Provides a GUI for managing cursor-docs:
//! - Add documentation sources by URL
//! - View indexed sources and their status
//! - Search indexed content
//! - Manage (refresh, delete) sources

mod client;
mod models;
pub mod ui;

pub use client::DocsClient;
pub use models::*;
pub use ui::{DocsPanel, DocsPanelEvent, DocsTheme};

