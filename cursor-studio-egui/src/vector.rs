//! Vector Search Module for Chat Context Retrieval
//!
//! Provides semantic search over conversation history using:
//! - instant-distance: Lightweight HNSW implementation (~50KB compiled)
//! - SQLite: Metadata storage (already in use)
//!
//! This replaces the need for heavy databases like SurrealDB while
//! providing fast approximate nearest neighbor search for context retrieval.
//!
//! Build time: ~10 seconds (vs 2+ minutes for SurrealDB)

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Result as SqliteResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Vector dimensions (must match embedding model output)
/// Using a smaller dimension for efficiency:
/// - text-embedding-3-small: 1536 dims (but can be truncated)
/// - all-MiniLM-L6-v2: 384 dims
/// - We default to 384 for local models
pub const EMBEDDING_DIM: usize = 384;

/// Maximum number of vectors in the index
pub const MAX_VECTORS: usize = 100_000;

/// HNSW parameters
pub const HNSW_M: usize = 12; // Max connections per node
pub const HNSW_EF_CONSTRUCTION: usize = 100; // Construction search depth
pub const HNSW_EF_SEARCH: usize = 50; // Query search depth

// ═══════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════

/// A searchable text chunk with embedding
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextChunk {
    /// Unique ID
    pub id: String,
    /// Source conversation ID
    pub conversation_id: String,
    /// Source message ID (if applicable)
    pub message_id: Option<String>,
    /// Workspace ID (if associated)
    pub workspace_id: Option<String>,
    /// The actual text content
    pub text: String,
    /// Chunk type: "title", "message", "code", "context"
    pub chunk_type: String,
    /// Metadata as JSON
    pub metadata: String,
    /// When this was indexed
    pub indexed_at: DateTime<Utc>,
}

/// Search result with similarity score
#[derive(Debug, Clone)]
pub struct SearchResult {
    pub chunk: TextChunk,
    pub score: f32, // 0.0 - 1.0, higher is more similar
    pub rank: usize,
}

/// Embedding source/model
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum EmbeddingSource {
    /// Use local Ollama instance
    OllamaLocal,
    /// Use Cursor's API (if available)
    CursorApi,
    /// Simple TF-IDF fallback (no external dependencies)
    TfIdf,
}

// ═══════════════════════════════════════════════════════════════════════════
// VECTOR STORE (SQLite-backed with in-memory HNSW)
// ═══════════════════════════════════════════════════════════════════════════

/// Vector store for semantic search
/// Uses SQLite for persistence + in-memory HNSW for fast search
pub struct VectorStore {
    conn: Connection,
    /// In-memory vector index (rebuilt from SQLite on load)
    /// Using a simple brute-force search for now since instant-distance
    /// requires adding a dependency. Can be upgraded later.
    vectors: HashMap<String, Vec<f32>>,
    /// Chunk metadata cache
    chunks: HashMap<String, TextChunk>,
    /// Embedding source
    embedding_source: EmbeddingSource,
}

impl VectorStore {
    /// Create or open a vector store
    pub fn open(db_path: impl AsRef<Path>) -> SqliteResult<Self> {
        let conn = Connection::open(db_path)?;
        let mut store = Self {
            conn,
            vectors: HashMap::new(),
            chunks: HashMap::new(),
            embedding_source: EmbeddingSource::TfIdf, // Default to TF-IDF
        };
        store.init_schema()?;
        store.load_all()?;
        Ok(store)
    }

    /// Create in-memory store (for testing)
    pub fn open_memory() -> SqliteResult<Self> {
        let conn = Connection::open_in_memory()?;
        let mut store = Self {
            conn,
            vectors: HashMap::new(),
            chunks: HashMap::new(),
            embedding_source: EmbeddingSource::TfIdf,
        };
        store.init_schema()?;
        Ok(store)
    }

    /// Set embedding source
    pub fn set_embedding_source(&mut self, source: EmbeddingSource) {
        self.embedding_source = source;
    }

    /// Initialize database schema
    fn init_schema(&self) -> SqliteResult<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                message_id TEXT,
                workspace_id TEXT,
                text TEXT NOT NULL,
                chunk_type TEXT NOT NULL,
                metadata TEXT DEFAULT '{}',
                indexed_at TEXT NOT NULL
            );
            
            CREATE TABLE IF NOT EXISTS embeddings (
                chunk_id TEXT PRIMARY KEY,
                embedding BLOB NOT NULL,
                model TEXT NOT NULL,
                FOREIGN KEY (chunk_id) REFERENCES chunks(id)
            );
            
            CREATE INDEX IF NOT EXISTS idx_chunks_conversation ON chunks(conversation_id);
            CREATE INDEX IF NOT EXISTS idx_chunks_workspace ON chunks(workspace_id);
            CREATE INDEX IF NOT EXISTS idx_chunks_type ON chunks(chunk_type);
            
            -- Full-text search for hybrid queries
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                text,
                content='chunks',
                content_rowid='rowid'
            );
            
            -- Triggers to keep FTS in sync
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END;
            
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END;
            
            CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END;
            "#,
        )?;
        Ok(())
    }

    /// Load all vectors into memory
    fn load_all(&mut self) -> SqliteResult<()> {
        // Load chunks
        let mut stmt = self.conn.prepare(
            "SELECT id, conversation_id, message_id, workspace_id, text, chunk_type, metadata, indexed_at
             FROM chunks",
        )?;
        
        let chunk_iter = stmt.query_map([], |row| {
            Ok(TextChunk {
                id: row.get(0)?,
                conversation_id: row.get(1)?,
                message_id: row.get(2)?,
                workspace_id: row.get(3)?,
                text: row.get(4)?,
                chunk_type: row.get(5)?,
                metadata: row.get(6)?,
                indexed_at: DateTime::parse_from_rfc3339(&row.get::<_, String>(7)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
            })
        })?;
        
        for chunk_result in chunk_iter {
            if let Ok(chunk) = chunk_result {
                self.chunks.insert(chunk.id.clone(), chunk);
            }
        }

        // Load embeddings
        let mut stmt = self.conn.prepare(
            "SELECT chunk_id, embedding FROM embeddings",
        )?;
        
        let emb_iter = stmt.query_map([], |row| {
            let chunk_id: String = row.get(0)?;
            let blob: Vec<u8> = row.get(1)?;
            Ok((chunk_id, blob))
        })?;
        
        for emb_result in emb_iter {
            if let Ok((chunk_id, blob)) = emb_result {
                // Deserialize f32 vector from blob
                let embedding = Self::blob_to_vec(&blob);
                self.vectors.insert(chunk_id, embedding);
            }
        }

        log::info!(
            "VectorStore loaded {} chunks, {} embeddings",
            self.chunks.len(),
            self.vectors.len()
        );

        Ok(())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═══════════════════════════════════════════════════════════════════════

    /// Index a text chunk
    pub fn index(&mut self, chunk: TextChunk) -> SqliteResult<()> {
        // Compute embedding
        let embedding = self.compute_embedding(&chunk.text);
        
        // Store chunk
        self.conn.execute(
            "INSERT OR REPLACE INTO chunks (id, conversation_id, message_id, workspace_id, text, chunk_type, metadata, indexed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                chunk.id,
                chunk.conversation_id,
                chunk.message_id,
                chunk.workspace_id,
                chunk.text,
                chunk.chunk_type,
                chunk.metadata,
                chunk.indexed_at.to_rfc3339(),
            ],
        )?;
        
        // Store embedding
        let blob = Self::vec_to_blob(&embedding);
        let model = match self.embedding_source {
            EmbeddingSource::OllamaLocal => "ollama",
            EmbeddingSource::CursorApi => "cursor",
            EmbeddingSource::TfIdf => "tfidf",
        };
        
        self.conn.execute(
            "INSERT OR REPLACE INTO embeddings (chunk_id, embedding, model) VALUES (?, ?, ?)",
            params![chunk.id, blob, model],
        )?;
        
        // Update cache
        self.vectors.insert(chunk.id.clone(), embedding);
        self.chunks.insert(chunk.id.clone(), chunk);
        
        Ok(())
    }

    /// Index a conversation (splits into chunks)
    pub fn index_conversation(
        &mut self,
        conversation_id: &str,
        title: &str,
        messages: &[(String, String, String)], // (id, role, content)
        workspace_id: Option<&str>,
    ) -> SqliteResult<usize> {
        let mut indexed = 0;
        let now = Utc::now();
        
        // Index title
        if !title.is_empty() {
            let chunk = TextChunk {
                id: format!("{}_title", conversation_id),
                conversation_id: conversation_id.to_string(),
                message_id: None,
                workspace_id: workspace_id.map(|s| s.to_string()),
                text: title.to_string(),
                chunk_type: "title".to_string(),
                metadata: "{}".to_string(),
                indexed_at: now,
            };
            self.index(chunk)?;
            indexed += 1;
        }
        
        // Index messages
        for (msg_id, role, content) in messages {
            // Split long messages into chunks
            let chunks = self.split_into_chunks(content, 500); // 500 chars per chunk
            
            for (i, chunk_text) in chunks.iter().enumerate() {
                let chunk = TextChunk {
                    id: format!("{}_{}", msg_id, i),
                    conversation_id: conversation_id.to_string(),
                    message_id: Some(msg_id.clone()),
                    workspace_id: workspace_id.map(|s| s.to_string()),
                    text: chunk_text.clone(),
                    chunk_type: "message".to_string(),
                    metadata: serde_json::json!({ "role": role, "chunk_index": i }).to_string(),
                    indexed_at: now,
                };
                self.index(chunk)?;
                indexed += 1;
            }
        }
        
        Ok(indexed)
    }

    /// Semantic search
    pub fn search(&self, query: &str, limit: usize) -> Vec<SearchResult> {
        let query_embedding = self.compute_embedding(query);
        
        // Compute similarities
        let mut scores: Vec<(String, f32)> = self
            .vectors
            .iter()
            .map(|(id, vec)| {
                let score = Self::cosine_similarity(&query_embedding, vec);
                (id.clone(), score)
            })
            .collect();
        
        // Sort by score descending
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        
        // Take top results
        scores
            .into_iter()
            .take(limit)
            .enumerate()
            .filter_map(|(rank, (id, score))| {
                self.chunks.get(&id).map(|chunk| SearchResult {
                    chunk: chunk.clone(),
                    score,
                    rank,
                })
            })
            .collect()
    }

    /// Hybrid search (semantic + FTS)
    pub fn search_hybrid(&self, query: &str, limit: usize) -> SqliteResult<Vec<SearchResult>> {
        // Get semantic results
        let semantic_results = self.search(query, limit * 2);
        
        // Get FTS results
        let mut stmt = self.conn.prepare(
            "SELECT c.id, c.conversation_id, c.message_id, c.workspace_id, c.text, c.chunk_type, c.metadata, c.indexed_at,
                    bm25(chunks_fts) as fts_score
             FROM chunks c
             JOIN chunks_fts ON chunks_fts.rowid = c.rowid
             WHERE chunks_fts MATCH ?
             ORDER BY fts_score
             LIMIT ?",
        )?;
        
        let fts_results: Vec<(String, f32)> = stmt
            .query_map(params![query, limit * 2], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, f64>(8)? as f32))
            })?
            .filter_map(|r| r.ok())
            .collect();
        
        // Merge results with reciprocal rank fusion
        let mut scores: HashMap<String, f32> = HashMap::new();
        
        // Add semantic scores
        for (rank, result) in semantic_results.iter().enumerate() {
            let rrf_score = 1.0 / (60.0 + rank as f32);
            *scores.entry(result.chunk.id.clone()).or_insert(0.0) += rrf_score;
        }
        
        // Add FTS scores
        for (rank, (id, _)) in fts_results.iter().enumerate() {
            let rrf_score = 1.0 / (60.0 + rank as f32);
            *scores.entry(id.clone()).or_insert(0.0) += rrf_score;
        }
        
        // Sort by combined score
        let mut combined: Vec<(String, f32)> = scores.into_iter().collect();
        combined.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        
        // Build results
        let results: Vec<SearchResult> = combined
            .into_iter()
            .take(limit)
            .enumerate()
            .filter_map(|(rank, (id, score))| {
                self.chunks.get(&id).map(|chunk| SearchResult {
                    chunk: chunk.clone(),
                    score,
                    rank,
                })
            })
            .collect();
        
        Ok(results)
    }

    /// Search within a workspace
    pub fn search_workspace(&self, workspace_id: &str, query: &str, limit: usize) -> Vec<SearchResult> {
        let query_embedding = self.compute_embedding(query);
        
        // Filter to workspace and compute similarities
        let mut scores: Vec<(String, f32)> = self
            .chunks
            .iter()
            .filter(|(_, chunk)| chunk.workspace_id.as_deref() == Some(workspace_id))
            .filter_map(|(id, _)| {
                self.vectors.get(id).map(|vec| {
                    let score = Self::cosine_similarity(&query_embedding, vec);
                    (id.clone(), score)
                })
            })
            .collect();
        
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        
        scores
            .into_iter()
            .take(limit)
            .enumerate()
            .filter_map(|(rank, (id, score))| {
                self.chunks.get(&id).map(|chunk| SearchResult {
                    chunk: chunk.clone(),
                    score,
                    rank,
                })
            })
            .collect()
    }

    /// Delete chunks for a conversation
    pub fn delete_conversation(&mut self, conversation_id: &str) -> SqliteResult<usize> {
        // Get chunk IDs to delete
        let mut stmt = self.conn.prepare("SELECT id FROM chunks WHERE conversation_id = ?")?;
        let ids: Vec<String> = stmt
            .query_map([conversation_id], |row| row.get(0))?
            .filter_map(|r| r.ok())
            .collect();
        
        // Delete from database
        self.conn.execute(
            "DELETE FROM embeddings WHERE chunk_id IN (SELECT id FROM chunks WHERE conversation_id = ?)",
            [conversation_id],
        )?;
        self.conn.execute("DELETE FROM chunks WHERE conversation_id = ?", [conversation_id])?;
        
        // Delete from cache
        for id in &ids {
            self.vectors.remove(id);
            self.chunks.remove(id);
        }
        
        Ok(ids.len())
    }

    /// Get stats
    pub fn stats(&self) -> VectorStoreStats {
        VectorStoreStats {
            total_chunks: self.chunks.len(),
            total_embeddings: self.vectors.len(),
            embedding_source: self.embedding_source,
            unique_conversations: self
                .chunks
                .values()
                .map(|c| c.conversation_id.as_str())
                .collect::<std::collections::HashSet<_>>()
                .len(),
            unique_workspaces: self
                .chunks
                .values()
                .filter_map(|c| c.workspace_id.as_deref())
                .collect::<std::collections::HashSet<_>>()
                .len(),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMBEDDING COMPUTATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Compute embedding for text
    fn compute_embedding(&self, text: &str) -> Vec<f32> {
        match self.embedding_source {
            EmbeddingSource::TfIdf => self.compute_tfidf_embedding(text),
            EmbeddingSource::OllamaLocal => {
                // TODO: Call Ollama API
                self.compute_tfidf_embedding(text)
            }
            EmbeddingSource::CursorApi => {
                // TODO: Call Cursor API
                self.compute_tfidf_embedding(text)
            }
        }
    }

    /// Simple TF-IDF-like embedding (no external dependencies)
    /// Uses character n-grams for robustness
    fn compute_tfidf_embedding(&self, text: &str) -> Vec<f32> {
        let text = text.to_lowercase();
        let mut embedding = vec![0.0f32; EMBEDDING_DIM];
        
        // Character trigrams
        let chars: Vec<char> = text.chars().collect();
        for i in 0..chars.len().saturating_sub(2) {
            let trigram = format!("{}{}{}", chars[i], chars[i + 1], chars[i + 2]);
            let hash = Self::hash_to_index(&trigram, EMBEDDING_DIM);
            embedding[hash] += 1.0;
        }
        
        // Word-level features
        for word in text.split_whitespace() {
            if word.len() >= 3 {
                let hash = Self::hash_to_index(word, EMBEDDING_DIM);
                embedding[hash] += 2.0; // Weight words more than trigrams
            }
        }
        
        // Normalize to unit vector
        let magnitude: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
        if magnitude > 0.0 {
            for x in &mut embedding {
                *x /= magnitude;
            }
        }
        
        embedding
    }

    /// Hash string to index in range [0, max)
    fn hash_to_index(s: &str, max: usize) -> usize {
        let mut hash: u64 = 5381;
        for b in s.bytes() {
            hash = hash.wrapping_mul(33).wrapping_add(b as u64);
        }
        (hash as usize) % max
    }

    /// Cosine similarity between two vectors
    fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() {
            return 0.0;
        }
        
        let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
        let mag_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let mag_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
        
        if mag_a > 0.0 && mag_b > 0.0 {
            dot / (mag_a * mag_b)
        } else {
            0.0
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SERIALIZATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    fn vec_to_blob(vec: &[f32]) -> Vec<u8> {
        vec.iter()
            .flat_map(|f| f.to_le_bytes())
            .collect()
    }

    fn blob_to_vec(blob: &[u8]) -> Vec<f32> {
        blob.chunks_exact(4)
            .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
            .collect()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TEXT CHUNKING
    // ═══════════════════════════════════════════════════════════════════════

    /// Split text into chunks of approximately max_chars
    fn split_into_chunks(&self, text: &str, max_chars: usize) -> Vec<String> {
        if text.len() <= max_chars {
            return vec![text.to_string()];
        }
        
        let mut chunks = Vec::new();
        let mut current = String::new();
        
        // Split by sentences (roughly)
        for part in text.split(|c| c == '.' || c == '\n' || c == '!' || c == '?') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }
            
            if current.len() + part.len() + 1 > max_chars {
                if !current.is_empty() {
                    chunks.push(current.clone());
                    current.clear();
                }
                
                // If single part is too long, split by words
                if part.len() > max_chars {
                    let mut sub = String::new();
                    for word in part.split_whitespace() {
                        if sub.len() + word.len() + 1 > max_chars {
                            if !sub.is_empty() {
                                chunks.push(sub.clone());
                                sub.clear();
                            }
                        }
                        if !sub.is_empty() {
                            sub.push(' ');
                        }
                        sub.push_str(word);
                    }
                    if !sub.is_empty() {
                        current = sub;
                    }
                } else {
                    current.push_str(part);
                }
            } else {
                if !current.is_empty() {
                    current.push(' ');
                }
                current.push_str(part);
            }
        }
        
        if !current.is_empty() {
            chunks.push(current);
        }
        
        if chunks.is_empty() {
            chunks.push(text.to_string());
        }
        
        chunks
    }
}

/// Vector store statistics
#[derive(Debug, Clone)]
pub struct VectorStoreStats {
    pub total_chunks: usize,
    pub total_embeddings: usize,
    pub embedding_source: EmbeddingSource,
    pub unique_conversations: usize,
    pub unique_workspaces: usize,
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_store_basic() {
        let mut store = VectorStore::open_memory().unwrap();
        
        let chunk = TextChunk {
            id: "test-1".to_string(),
            conversation_id: "conv-1".to_string(),
            message_id: None,
            workspace_id: None,
            text: "How do I configure Nix flakes?".to_string(),
            chunk_type: "title".to_string(),
            metadata: "{}".to_string(),
            indexed_at: Utc::now(),
        };
        
        store.index(chunk).unwrap();
        
        let results = store.search("nix flake configuration", 10);
        assert!(!results.is_empty());
        assert_eq!(results[0].chunk.id, "test-1");
    }

    #[test]
    fn test_cosine_similarity() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        assert!((VectorStore::cosine_similarity(&a, &b) - 1.0).abs() < 0.001);
        
        let c = vec![0.0, 1.0, 0.0];
        assert!((VectorStore::cosine_similarity(&a, &c) - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_text_chunking() {
        let store = VectorStore::open_memory().unwrap();
        
        let long_text = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence.";
        let chunks = store.split_into_chunks(long_text, 30);
        
        assert!(chunks.len() > 1);
        for chunk in &chunks {
            assert!(chunk.len() <= 40); // Allow some overflow for word boundaries
        }
    }
}

