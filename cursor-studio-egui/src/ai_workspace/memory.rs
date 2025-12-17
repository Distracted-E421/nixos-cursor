//! Local memory system - structured, contextual, persistent

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Types of memories
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MemoryType {
    /// Stable facts (hardware, preferences)
    Fact,
    /// Why certain choices were made
    Decision,
    /// What worked or didn't
    Learning,
    /// Current project context
    Context,
    /// Patterns and conventions
    Pattern,
}

/// A memory entry with full metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEntry {
    pub id: String,
    pub content: String,
    pub memory_type: MemoryType,
    pub confidence: f32,
    pub source: String,
    pub created: String,
    pub last_accessed: String,
    pub access_count: u32,
    pub related: Vec<String>,
    pub tags: Vec<String>,
}

impl MemoryEntry {
    pub fn new(content: &str, memory_type: MemoryType, source: &str) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            content: content.to_string(),
            memory_type,
            confidence: 1.0,
            source: source.to_string(),
            created: now.clone(),
            last_accessed: now,
            access_count: 0,
            related: Vec::new(),
            tags: Self::extract_tags(content),
        }
    }
    
    fn extract_tags(content: &str) -> Vec<String> {
        // Simple tag extraction from content
        let mut tags = Vec::new();
        
        // Extract hashtags
        for word in content.split_whitespace() {
            if word.starts_with('#') && word.len() > 1 {
                tags.push(word[1..].to_lowercase());
            }
        }
        
        // Detect common categories
        let lower = content.to_lowercase();
        if lower.contains("architecture") || lower.contains("design") {
            tags.push("architecture".into());
        }
        if lower.contains("decision") || lower.contains("chose") || lower.contains("decided") {
            tags.push("decision".into());
        }
        if lower.contains("bug") || lower.contains("fix") {
            tags.push("bugfix".into());
        }
        if lower.contains("nix") || lower.contains("nixos") {
            tags.push("nix".into());
        }
        if lower.contains("rust") || lower.contains("cargo") {
            tags.push("rust".into());
        }
        if lower.contains("cursor") || lower.contains("studio") {
            tags.push("cursor-studio".into());
        }
        
        tags.sort();
        tags.dedup();
        tags
    }
    
    pub fn mark_accessed(&mut self) {
        self.last_accessed = chrono::Utc::now().to_rfc3339();
        self.access_count += 1;
    }
}

/// Local memory store with graph relationships
pub struct LocalMemory {
    path: PathBuf,
    entries: HashMap<String, MemoryEntry>,
}

impl LocalMemory {
    pub fn new(path: PathBuf) -> Self {
        let mut memory = Self {
            path: path.clone(),
            entries: HashMap::new(),
        };
        memory.load();
        memory
    }
    
    /// Store a new memory
    pub fn remember(&mut self, content: &str, memory_type: MemoryType, source: &str) -> String {
        let entry = MemoryEntry::new(content, memory_type, source);
        let id = entry.id.clone();
        
        // Find related memories
        let related = self.find_related(content);
        let mut entry = entry;
        entry.related = related.iter().map(|e| e.id.clone()).collect();
        
        self.entries.insert(id.clone(), entry);
        self.save();
        
        id
    }
    
    /// Recall memories matching a query
    pub fn recall(&mut self, query: &str) -> Vec<MemoryEntry> {
        let query_lower = query.to_lowercase();
        let query_words: Vec<&str> = query_lower.split_whitespace().collect();
        
        let mut results: Vec<(MemoryEntry, f32)> = self.entries.values()
            .map(|entry| {
                let score = self.score_match(entry, &query_words);
                (entry.clone(), score)
            })
            .filter(|(_, score)| *score > 0.0)
            .collect();
        
        // Sort by score
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        
        // Mark accessed
        for (entry, _) in &results {
            if let Some(e) = self.entries.get_mut(&entry.id) {
                e.mark_accessed();
            }
        }
        
        self.save();
        
        results.into_iter().map(|(e, _)| e).collect()
    }
    
    /// Find memories related to content
    pub fn find_related(&self, content: &str) -> Vec<MemoryEntry> {
        let content_lower = content.to_lowercase();
        let tags = MemoryEntry::extract_tags(content);
        
        self.entries.values()
            .filter(|entry| {
                // Check tag overlap
                entry.tags.iter().any(|t| tags.contains(t)) ||
                // Check content similarity
                entry.content.to_lowercase().split_whitespace()
                    .any(|w| content_lower.contains(w) && w.len() > 3)
            })
            .cloned()
            .collect()
    }
    
    /// Get memories by type
    pub fn by_type(&self, memory_type: MemoryType) -> Vec<&MemoryEntry> {
        self.entries.values()
            .filter(|e| e.memory_type == memory_type)
            .collect()
    }
    
    /// Surface potentially relevant memories (proactive)
    pub fn surface_relevant(&self, tags: &[String]) -> Vec<&MemoryEntry> {
        self.entries.values()
            .filter(|entry| entry.tags.iter().any(|t| tags.contains(t)))
            .collect()
    }
    
    /// Forget a memory
    pub fn forget(&mut self, id: &str) -> bool {
        let result = self.entries.remove(id).is_some();
        if result {
            self.save();
        }
        result
    }
    
    /// Get all memories
    pub fn all(&self) -> Vec<&MemoryEntry> {
        self.entries.values().collect()
    }
    
    fn score_match(&self, entry: &MemoryEntry, query_words: &[&str]) -> f32 {
        let content_lower = entry.content.to_lowercase();
        let mut score = 0.0;
        
        for word in query_words {
            if content_lower.contains(word) {
                score += 1.0;
            }
            if entry.tags.iter().any(|t| t.contains(word)) {
                score += 0.5;
            }
        }
        
        // Boost recent and frequently accessed
        score *= 1.0 + (entry.access_count as f32 * 0.1).min(0.5);
        
        score
    }
    
    fn load(&mut self) {
        if let Ok(content) = std::fs::read_to_string(&self.path) {
            if let Ok(entries) = serde_json::from_str::<HashMap<String, MemoryEntry>>(&content) {
                self.entries = entries;
            }
        }
    }
    
    fn save(&self) {
        if let Ok(json) = serde_json::to_string_pretty(&self.entries) {
            std::fs::write(&self.path, json).ok();
        }
    }
}

