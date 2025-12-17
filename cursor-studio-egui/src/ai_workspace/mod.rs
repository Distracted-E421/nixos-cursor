//! AI Workspace Management
//! 
//! Provides persistent workspace for AI assistant:
//! - Environment awareness (machine, OS, git state)
//! - Scratchpad for drafting ideas
//! - Context detection and tracking
//! - Multi-step plan management
//! - Git experiment branch tracking
//! - Contextual hint generation

mod context;
mod environment;
mod hints;
mod memory;
mod scratchpad;
mod plans;

pub use context::{TaskContext, ContextAnalyzer, ContextState};
pub use environment::{
    EnvironmentState, EnvironmentWatcher, EnvironmentDelta,
    AliasRegistry, MachineAliases, GitState, OsInfo,
    create_default_registry,
};
pub use hints::{HintInjector, Hint};
pub use memory::{LocalMemory, MemoryEntry, MemoryType};
pub use scratchpad::Scratchpad;
pub use plans::{TaskPlan, PlanStep, StepStatus};

use std::path::PathBuf;
use std::sync::Arc;
use parking_lot::RwLock;

/// Main AI workspace manager
pub struct AiWorkspace {
    root: PathBuf,
    pub context: Arc<RwLock<ContextState>>,
    pub memory: Arc<RwLock<LocalMemory>>,
    pub scratchpad: Scratchpad,
    pub hints: HintInjector,
    pub plans: Arc<RwLock<Vec<TaskPlan>>>,
}

impl AiWorkspace {
    pub fn new(workspace_root: PathBuf) -> Self {
        let ai_workspace = workspace_root.join(".ai-workspace");
        
        // Ensure directories exist
        std::fs::create_dir_all(ai_workspace.join("scratchpad")).ok();
        std::fs::create_dir_all(ai_workspace.join("plans")).ok();
        std::fs::create_dir_all(ai_workspace.join("experiments")).ok();
        std::fs::create_dir_all(ai_workspace.join("context")).ok();
        
        Self {
            root: ai_workspace.clone(),
            context: Arc::new(RwLock::new(ContextState::default())),
            memory: Arc::new(RwLock::new(LocalMemory::new(ai_workspace.join("memory.db")))),
            scratchpad: Scratchpad::new(ai_workspace.join("scratchpad")),
            hints: HintInjector::new(),
            plans: Arc::new(RwLock::new(Vec::new())),
        }
    }
    
    /// Update context based on recent activity
    pub fn update_context(&self, files_touched: &[String], operations: &[String]) {
        let mut context = self.context.write();
        context.update(files_touched, operations);
        
        // Write to file for external tools
        if let Ok(json) = serde_json::to_string_pretty(&*context) {
            std::fs::write(self.root.join("context/current.json"), json).ok();
        }
    }
    
    /// Generate contextual hints
    pub fn generate_hints(&self) -> String {
        let context = self.context.read();
        let hints = self.hints.generate(&context);
        
        // Write to file
        let hints_md = hints.iter()
            .map(|h| format!("💡 {}", h.message))
            .collect::<Vec<_>>()
            .join("\n");
        
        std::fs::write(self.root.join("hints.md"), &hints_md).ok();
        
        hints_md
    }
    
    /// Get relevant tools for current context
    pub fn relevant_tools(&self) -> Vec<RelevantTool> {
        let context = self.context.read();
        context.relevant_tools()
    }
    
    /// Create a draft in scratchpad
    pub fn draft(&self, name: &str, content: &str) -> std::io::Result<PathBuf> {
        self.scratchpad.create(name, content)
    }
    
    /// Create a new task plan
    pub fn create_plan(&self, description: &str, steps: Vec<String>) -> String {
        let plan = TaskPlan::new(description, steps);
        let id = plan.id.clone();
        
        self.plans.write().push(plan);
        self.save_plans();
        
        id
    }
    
    /// Advance plan to next step
    pub fn advance_plan(&self, plan_id: &str, notes: &str) -> bool {
        let mut plans = self.plans.write();
        if let Some(plan) = plans.iter_mut().find(|p| p.id == plan_id) {
            plan.advance(notes);
            drop(plans);
            self.save_plans();
            return true;
        }
        false
    }
    
    fn save_plans(&self) {
        let plans = self.plans.read();
        for plan in plans.iter() {
            let path = self.root.join(format!("plans/{}.json", plan.id));
            if let Ok(json) = serde_json::to_string_pretty(plan) {
                std::fs::write(path, json).ok();
            }
        }
    }
}

/// A tool relevant to current context
#[derive(Debug, Clone)]
pub struct RelevantTool {
    pub name: String,
    pub relevance: f32,
    pub hint: Option<String>,
}

