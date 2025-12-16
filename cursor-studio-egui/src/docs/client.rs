//! Client for communicating with cursor-docs backend
//!
//! Supports two modes:
//! 1. Direct SQLite access (when cursor-docs is not running as a server)
//! 2. HTTP API (when cursor-docs server is running)

use super::models::*;
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

/// Client for cursor-docs backend
pub struct DocsClient {
    /// Path to cursor-docs SQLite database
    db_path: PathBuf,
    /// Cached connection (for direct SQLite mode)
    connection: Arc<Mutex<Option<Connection>>>,
    /// HTTP client (for API mode)
    #[allow(dead_code)]
    http_client: Option<reqwest::blocking::Client>,
    /// Backend base URL (if using HTTP mode)
    #[allow(dead_code)]
    base_url: Option<String>,
}

impl DocsClient {
    /// Create a new client using direct SQLite access
    pub fn new_sqlite(db_path: PathBuf) -> Self {
        Self {
            db_path,
            connection: Arc::new(Mutex::new(None)),
            http_client: None,
            base_url: None,
        }
    }

    /// Create a new client using HTTP API
    #[allow(dead_code)]
    pub fn new_http(base_url: &str) -> Self {
        Self {
            db_path: PathBuf::new(),
            connection: Arc::new(Mutex::new(None)),
            http_client: Some(reqwest::blocking::Client::new()),
            base_url: Some(base_url.to_string()),
        }
    }

    /// Get or create a database connection
    fn get_connection(&self) -> Result<Connection, String> {
        // Use read-only mode to avoid interfering with cursor-docs
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;

        Connection::open_with_flags(&self.db_path, flags)
            .map_err(|e| format!("Failed to open database: {}", e))
    }

    /// Check if the backend is available
    pub fn check_connection(&self) -> BackendStatus {
        if self.db_path.exists() {
            match self.get_connection() {
                Ok(_) => BackendStatus::Connected,
                Err(_) => BackendStatus::Error,
            }
        } else {
            BackendStatus::Disconnected
        }
    }

    /// Get all documentation sources
    pub fn get_sources(&self) -> Result<Vec<DocSource>, String> {
        let conn = self.get_connection()?;

        let mut stmt = conn
            .prepare(
                r#"
                SELECT 
                    id, url, name, status, 
                    COALESCE(chunks_count, 0) as chunks_count,
                    last_indexed, created_at
                FROM doc_sources
                ORDER BY created_at DESC
                "#,
            )
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let sources = stmt
            .query_map([], |row| {
                let status_str: String = row.get(3)?;
                let status = match status_str.as_str() {
                    "indexed" => SourceStatus::Indexed,
                    "indexing" => SourceStatus::Indexing,
                    "failed" => SourceStatus::Failed,
                    _ => SourceStatus::Pending,
                };

                Ok(DocSource {
                    id: row.get(0)?,
                    url: row.get(1)?,
                    name: row.get(2)?,
                    status,
                    chunks_count: row.get::<_, i64>(4)? as usize,
                    last_indexed: row.get(5)?,
                    created_at: row.get(6)?,
                    security_tier: None,
                    alerts_count: 0,
                })
            })
            .map_err(|e| format!("Failed to execute query: {}", e))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Failed to collect results: {}", e))?;

        Ok(sources)
    }

    /// Get aggregate statistics
    pub fn get_stats(&self) -> Result<DocsStats, String> {
        let conn = self.get_connection()?;

        // Get source counts
        let mut stmt = conn
            .prepare(
                r#"
                SELECT 
                    COUNT(*) as total,
                    SUM(CASE WHEN status = 'indexed' THEN 1 ELSE 0 END) as indexed,
                    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
                    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
                    SUM(COALESCE(chunks_count, 0)) as total_chunks
                FROM doc_sources
                "#,
            )
            .map_err(|e| format!("Failed to prepare stats query: {}", e))?;

        let stats = stmt
            .query_row([], |row| {
                Ok(DocsStats {
                    total_sources: row.get::<_, i64>(0)? as usize,
                    indexed_sources: row.get::<_, i64>(1)? as usize,
                    pending_sources: row.get::<_, i64>(2)? as usize,
                    failed_sources: row.get::<_, i64>(3)? as usize,
                    total_chunks: row.get::<_, i64>(4)? as usize,
                    total_alerts: 0,  // Would need security_alerts table
                    recent_alerts: 0, // Would need security_alerts table
                })
            })
            .map_err(|e| format!("Failed to get stats: {}", e))?;

        Ok(stats)
    }

    /// Get a single source by ID
    pub fn get_source(&self, source_id: &str) -> Result<Option<DocSource>, String> {
        let conn = self.get_connection()?;

        let mut stmt = conn
            .prepare(
                r#"
                SELECT 
                    id, url, name, status,
                    COALESCE(chunks_count, 0) as chunks_count,
                    last_indexed, created_at
                FROM doc_sources
                WHERE id = ?
                "#,
            )
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let source = stmt
            .query_row([source_id], |row| {
                let status_str: String = row.get(3)?;
                let status = match status_str.as_str() {
                    "indexed" => SourceStatus::Indexed,
                    "indexing" => SourceStatus::Indexing,
                    "failed" => SourceStatus::Failed,
                    _ => SourceStatus::Pending,
                };

                Ok(DocSource {
                    id: row.get(0)?,
                    url: row.get(1)?,
                    name: row.get(2)?,
                    status,
                    chunks_count: row.get::<_, i64>(4)? as usize,
                    last_indexed: row.get(5)?,
                    created_at: row.get(6)?,
                    security_tier: None,
                    alerts_count: 0,
                })
            })
            .optional()
            .map_err(|e| format!("Failed to execute query: {}", e))?;

        Ok(source)
    }

    /// Search indexed content using FTS5
    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>, String> {
        let conn = self.get_connection()?;

        // Using FTS5 match query
        let mut stmt = conn
            .prepare(
                r#"
                SELECT 
                    c.id, c.source_id, c.url, c.title, c.content, c.position,
                    s.name as source_name,
                    bm25(doc_chunks_fts) as score
                FROM doc_chunks_fts f
                JOIN doc_chunks c ON f.rowid = c.rowid
                JOIN doc_sources s ON c.source_id = s.id
                WHERE doc_chunks_fts MATCH ?
                ORDER BY score
                LIMIT ?
                "#,
            )
            .map_err(|e| format!("Failed to prepare search query: {}", e))?;

        let results = stmt
            .query_map([query, &limit.to_string()], |row| {
                let content: String = row.get(4)?;
                let snippet = create_snippet(&content, query, 150);

                Ok(SearchResult {
                    chunk: DocChunk {
                        id: row.get(0)?,
                        source_id: row.get(1)?,
                        url: row.get(2)?,
                        title: row.get(3)?,
                        content,
                        position: row.get::<_, i64>(5)? as usize,
                    },
                    source_name: row.get(6)?,
                    score: row.get(7)?,
                    snippet,
                })
            })
            .map_err(|e| format!("Failed to execute search: {}", e))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Failed to collect search results: {}", e))?;

        Ok(results)
    }

    /// Get chunks for a specific source
    pub fn get_chunks(&self, source_id: &str, limit: usize) -> Result<Vec<DocChunk>, String> {
        let conn = self.get_connection()?;

        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, source_id, url, title, content, position
                FROM doc_chunks
                WHERE source_id = ?
                ORDER BY position
                LIMIT ?
                "#,
            )
            .map_err(|e| format!("Failed to prepare query: {}", e))?;

        let chunks = stmt
            .query_map([source_id, &limit.to_string()], |row| {
                Ok(DocChunk {
                    id: row.get(0)?,
                    source_id: row.get(1)?,
                    url: row.get(2)?,
                    title: row.get(3)?,
                    content: row.get(4)?,
                    position: row.get::<_, i64>(5)? as usize,
                })
            })
            .map_err(|e| format!("Failed to execute query: {}", e))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Failed to collect results: {}", e))?;

        Ok(chunks)
    }

    /// Get the default database path, trying multiple locations.
    /// Priority:
    /// 1. cursor-docs-dev (development)
    /// 2. cursor-docs (production)
    pub fn default_db_path() -> PathBuf {
        let base = dirs::data_local_dir().unwrap_or_else(|| PathBuf::from("."));

        // Try dev path first (for development workflow)
        let dev_path = base.join("cursor-docs-dev").join("cursor_docs.db");
        if dev_path.exists() {
            return dev_path;
        }

        // Fall back to production path
        let prod_path = base.join("cursor-docs").join("cursor_docs.db");
        if prod_path.exists() {
            return prod_path;
        }

        // Default to dev path (will be created when cursor-docs runs)
        dev_path
    }
}

/// Create a snippet with the search term highlighted
fn create_snippet(content: &str, query: &str, max_len: usize) -> String {
    let lower_content = content.to_lowercase();
    let lower_query = query.to_lowercase();

    // Find the first occurrence of the query
    if let Some(pos) = lower_content.find(&lower_query) {
        let start = pos.saturating_sub(max_len / 2);
        let end = (pos + query.len() + max_len / 2).min(content.len());

        let mut snippet = String::new();
        if start > 0 {
            snippet.push_str("...");
        }
        snippet.push_str(&content[start..end]);
        if end < content.len() {
            snippet.push_str("...");
        }
        snippet
    } else {
        // No match found, return beginning of content
        if content.len() > max_len {
            format!("{}...", &content[..max_len])
        } else {
            content.to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_snippet() {
        let content = "This is a test content with some important information about Elixir and NixOS.";
        let snippet = create_snippet(content, "important", 40);
        assert!(snippet.contains("important"));
    }

    #[test]
    fn test_default_db_path() {
        let path = DocsClient::default_db_path();
        assert!(path.to_string_lossy().contains("cursor-docs"));
    }
}

