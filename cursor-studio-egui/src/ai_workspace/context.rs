//! Task context detection and tracking

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use super::RelevantTool;

/// Types of tasks the AI might be doing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskContext {
    // File operations
    FileExploration,
    FileModification,
    
    // Development
    Debugging,
    Refactoring,
    NewFeature,
    
    // Version control
    PreCommit,
    BranchManagement,
    
    // Documentation
    Writing,
    Research,
    
    // System operations
    Configuration,
    ServiceManagement,
    
    // Planning
    Brainstorming,
    ArchitectureDesign,
    
    // Unknown
    Unknown,
}

impl TaskContext {
    pub fn from_keywords(text: &str) -> Vec<Self> {
        let text_lower = text.to_lowercase();
        let mut contexts = Vec::new();
        
        // Detection heuristics
        if text_lower.contains("bug") || text_lower.contains("fix") || text_lower.contains("error") {
            contexts.push(TaskContext::Debugging);
        }
        if text_lower.contains("refactor") || text_lower.contains("clean up") || text_lower.contains("restructure") {
            contexts.push(TaskContext::Refactoring);
        }
        if text_lower.contains("add") || text_lower.contains("implement") || text_lower.contains("create") || text_lower.contains("new feature") {
            contexts.push(TaskContext::NewFeature);
        }
        if text_lower.contains("commit") || text_lower.contains("push") || text_lower.contains("pr") {
            contexts.push(TaskContext::PreCommit);
        }
        if text_lower.contains("branch") || text_lower.contains("merge") || text_lower.contains("rebase") {
            contexts.push(TaskContext::BranchManagement);
        }
        if text_lower.contains("doc") || text_lower.contains("readme") || text_lower.contains("comment") {
            contexts.push(TaskContext::Writing);
        }
        if text_lower.contains("architecture") || text_lower.contains("design") || text_lower.contains("structure") {
            contexts.push(TaskContext::ArchitectureDesign);
        }
        if text_lower.contains("idea") || text_lower.contains("brainstorm") || text_lower.contains("explore") || text_lower.contains("think") {
            contexts.push(TaskContext::Brainstorming);
        }
        if text_lower.contains("config") || text_lower.contains("nix") || text_lower.contains("setting") {
            contexts.push(TaskContext::Configuration);
        }
        
        if contexts.is_empty() {
            contexts.push(TaskContext::Unknown);
        }
        
        contexts
    }
}

/// Current context state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextState {
    pub detected_contexts: HashSet<TaskContext>,
    pub confidence: f32,
    pub last_updated: String,
    pub active_files: Vec<String>,
    pub recent_operations: Vec<String>,
    pub git_state: GitState,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GitState {
    pub branch: String,
    pub uncommitted_changes: usize,
    pub ahead_of_main: usize,
}

impl Default for ContextState {
    fn default() -> Self {
        Self {
            detected_contexts: HashSet::new(),
            confidence: 0.0,
            last_updated: chrono::Utc::now().to_rfc3339(),
            active_files: Vec::new(),
            recent_operations: Vec::new(),
            git_state: GitState::default(),
        }
    }
}

impl ContextState {
    pub fn update(&mut self, files: &[String], operations: &[String]) {
        self.active_files = files.to_vec();
        self.recent_operations = operations.to_vec();
        self.last_updated = chrono::Utc::now().to_rfc3339();
        
        // Detect contexts from files and operations
        let mut new_contexts = HashSet::new();
        
        for op in operations {
            for ctx in TaskContext::from_keywords(op) {
                new_contexts.insert(ctx);
            }
        }
        
        // File-based detection
        for file in files {
            if file.ends_with(".md") {
                new_contexts.insert(TaskContext::Writing);
            }
            if file.contains("test") {
                new_contexts.insert(TaskContext::Debugging);
            }
            if file.ends_with(".nix") {
                new_contexts.insert(TaskContext::Configuration);
            }
        }
        
        self.detected_contexts = new_contexts;
        self.confidence = if self.detected_contexts.is_empty() { 0.0 } else { 0.8 };
    }
    
    pub fn relevant_tools(&self) -> Vec<RelevantTool> {
        let mut tools = Vec::new();
        
        for context in &self.detected_contexts {
            match context {
                TaskContext::FileModification => {
                    tools.push(RelevantTool {
                        name: "write".into(),
                        relevance: 1.0,
                        hint: None,
                    });
                    tools.push(RelevantTool {
                        name: "search_replace".into(),
                        relevance: 0.9,
                        hint: None,
                    });
                    tools.push(RelevantTool {
                        name: "git_stash".into(),
                        relevance: 0.6,
                        hint: Some("Consider stashing before major edits".into()),
                    });
                }
                
                TaskContext::Brainstorming => {
                    tools.push(RelevantTool {
                        name: "scratchpad".into(),
                        relevance: 1.0,
                        hint: Some("Draft ideas in scratchpad before implementing".into()),
                    });
                    tools.push(RelevantTool {
                        name: "memory".into(),
                        relevance: 0.9,
                        hint: Some("Remember key decisions for future reference".into()),
                    });
                    tools.push(RelevantTool {
                        name: "git_branch".into(),
                        relevance: 0.7,
                        hint: Some("Create experiment branch for risky exploration".into()),
                    });
                }
                
                TaskContext::PreCommit => {
                    tools.push(RelevantTool {
                        name: "git_diff".into(),
                        relevance: 1.0,
                        hint: Some("Review changes before committing".into()),
                    });
                    tools.push(RelevantTool {
                        name: "git_add_p".into(),
                        relevance: 0.7,
                        hint: Some("Stage changes selectively".into()),
                    });
                    tools.push(RelevantTool {
                        name: "memory".into(),
                        relevance: 0.8,
                        hint: Some("Document why this change was made".into()),
                    });
                }
                
                TaskContext::ArchitectureDesign => {
                    tools.push(RelevantTool {
                        name: "scratchpad".into(),
                        relevance: 1.0,
                        hint: Some("Draft architecture before implementing".into()),
                    });
                    tools.push(RelevantTool {
                        name: "memory".into(),
                        relevance: 1.0,
                        hint: Some("Record architectural decisions".into()),
                    });
                    tools.push(RelevantTool {
                        name: "plans".into(),
                        relevance: 0.9,
                        hint: Some("Create multi-step plan with checkpoints".into()),
                    });
                }
                
                TaskContext::Debugging => {
                    tools.push(RelevantTool {
                        name: "grep".into(),
                        relevance: 1.0,
                        hint: None,
                    });
                    tools.push(RelevantTool {
                        name: "git_bisect".into(),
                        relevance: 0.5,
                        hint: Some("Use git bisect to find when bug was introduced".into()),
                    });
                }
                
                _ => {}
            }
        }
        
        // Deduplicate
        tools.sort_by(|a, b| b.relevance.partial_cmp(&a.relevance).unwrap());
        tools.dedup_by(|a, b| a.name == b.name);
        
        tools
    }
}

/// Analyzer for detecting task context
pub struct ContextAnalyzer;

impl ContextAnalyzer {
    pub fn analyze(messages: &[String]) -> Vec<TaskContext> {
        let mut all_contexts = Vec::new();
        
        for message in messages {
            all_contexts.extend(TaskContext::from_keywords(message));
        }
        
        // Deduplicate
        let unique: HashSet<_> = all_contexts.into_iter().collect();
        unique.into_iter().collect()
    }
}

