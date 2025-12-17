//! Contextual hint generation

use std::collections::HashMap;
use std::time::{Duration, Instant};
use super::context::{ContextState, TaskContext};

/// A contextual hint for the AI
#[derive(Debug, Clone)]
pub struct Hint {
    pub message: String,
    pub category: HintCategory,
    pub priority: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HintCategory {
    Memory,
    Git,
    Planning,
    Workflow,
}

/// Generates contextual hints based on task detection
pub struct HintInjector {
    shown_hints: HashMap<String, Instant>,
    cooldown: Duration,
}

impl HintInjector {
    pub fn new() -> Self {
        Self {
            shown_hints: HashMap::new(),
            cooldown: Duration::from_secs(300), // 5 minute cooldown per hint
        }
    }
    
    /// Generate hints based on current context
    pub fn generate(&self, context: &ContextState) -> Vec<Hint> {
        let mut hints = Vec::new();
        
        for task_context in &context.detected_contexts {
            hints.extend(self.hints_for_context(task_context));
        }
        
        // Git state hints
        if context.git_state.uncommitted_changes > 5 {
            hints.push(Hint {
                message: format!(
                    "You have {} uncommitted changes. Consider committing or stashing.",
                    context.git_state.uncommitted_changes
                ),
                category: HintCategory::Git,
                priority: 2,
            });
        }
        
        if context.git_state.ahead_of_main > 10 {
            hints.push(Hint {
                message: format!(
                    "Branch is {} commits ahead of main. Consider rebasing or creating PR.",
                    context.git_state.ahead_of_main
                ),
                category: HintCategory::Git,
                priority: 1,
            });
        }
        
        // Filter out recently shown hints
        hints.retain(|h| !self.recently_shown(&h.message));
        
        // Sort by priority
        hints.sort_by(|a, b| b.priority.cmp(&a.priority));
        
        // Limit to avoid noise
        hints.truncate(5);
        
        hints
    }
    
    fn hints_for_context(&self, context: &TaskContext) -> Vec<Hint> {
        match context {
            TaskContext::Brainstorming => vec![
                Hint {
                    message: "Use scratchpad (.ai-workspace/scratchpad/) to draft ideas before implementing".into(),
                    category: HintCategory::Planning,
                    priority: 3,
                },
                Hint {
                    message: "Remember key decisions in memory for future reference".into(),
                    category: HintCategory::Memory,
                    priority: 2,
                },
            ],
            
            TaskContext::ArchitectureDesign => vec![
                Hint {
                    message: "Create a multi-step plan with checkpoints for complex implementations".into(),
                    category: HintCategory::Planning,
                    priority: 3,
                },
                Hint {
                    message: "Document architectural decisions in memory - record 'why' not just 'what'".into(),
                    category: HintCategory::Memory,
                    priority: 3,
                },
                Hint {
                    message: "Consider creating an experiment branch for major structural changes".into(),
                    category: HintCategory::Git,
                    priority: 2,
                },
            ],
            
            TaskContext::PreCommit => vec![
                Hint {
                    message: "Review diff before committing: git diff --staged".into(),
                    category: HintCategory::Git,
                    priority: 3,
                },
                Hint {
                    message: "Use git add -p for selective staging".into(),
                    category: HintCategory::Git,
                    priority: 2,
                },
                Hint {
                    message: "Document the 'why' behind this change in memory or commit message".into(),
                    category: HintCategory::Memory,
                    priority: 2,
                },
            ],
            
            TaskContext::FileModification => vec![
                Hint {
                    message: "Consider creating a checkpoint before major changes".into(),
                    category: HintCategory::Git,
                    priority: 2,
                },
            ],
            
            TaskContext::Debugging => vec![
                Hint {
                    message: "Document the bug and fix in memory for future reference".into(),
                    category: HintCategory::Memory,
                    priority: 2,
                },
                Hint {
                    message: "Consider git bisect to find when bug was introduced".into(),
                    category: HintCategory::Git,
                    priority: 1,
                },
            ],
            
            TaskContext::Refactoring => vec![
                Hint {
                    message: "Create experiment branch for risky refactoring".into(),
                    category: HintCategory::Git,
                    priority: 3,
                },
                Hint {
                    message: "Break refactoring into smaller, atomic commits".into(),
                    category: HintCategory::Git,
                    priority: 2,
                },
            ],
            
            _ => vec![],
        }
    }
    
    fn recently_shown(&self, message: &str) -> bool {
        if let Some(shown_at) = self.shown_hints.get(message) {
            shown_at.elapsed() < self.cooldown
        } else {
            false
        }
    }
    
    pub fn mark_shown(&mut self, message: &str) {
        self.shown_hints.insert(message.to_string(), Instant::now());
    }
}

impl Default for HintInjector {
    fn default() -> Self {
        Self::new()
    }
}

