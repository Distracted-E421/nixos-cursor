//! Multi-step task planning with checkpoints

use serde::{Deserialize, Serialize};

/// Status of a plan step
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Pending,
    InProgress,
    Complete,
    Blocked,
    Skipped,
}

/// A single step in a task plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub description: String,
    pub status: StepStatus,
    pub notes: String,
    pub checkpoint: Option<String>,  // Git commit SHA
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

impl PlanStep {
    pub fn new(description: &str) -> Self {
        Self {
            description: description.to_string(),
            status: StepStatus::Pending,
            notes: String::new(),
            checkpoint: None,
            started_at: None,
            completed_at: None,
        }
    }
    
    pub fn start(&mut self) {
        self.status = StepStatus::InProgress;
        self.started_at = Some(chrono::Utc::now().to_rfc3339());
    }
    
    pub fn complete(&mut self, notes: &str) {
        self.status = StepStatus::Complete;
        self.notes = notes.to_string();
        self.completed_at = Some(chrono::Utc::now().to_rfc3339());
    }
    
    pub fn block(&mut self, reason: &str) {
        self.status = StepStatus::Blocked;
        self.notes = reason.to_string();
    }
    
    pub fn skip(&mut self, reason: &str) {
        self.status = StepStatus::Skipped;
        self.notes = reason.to_string();
    }
}

/// A multi-step task plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskPlan {
    pub id: String,
    pub description: String,
    pub steps: Vec<PlanStep>,
    pub current_step: usize,
    pub branch: Option<String>,
    pub created: String,
    pub updated: String,
    pub status: PlanStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlanStatus {
    Active,
    Complete,
    Abandoned,
    Paused,
}

impl TaskPlan {
    pub fn new(description: &str, steps: Vec<String>) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: uuid::Uuid::new_v4().to_string()[..8].to_string(),
            description: description.to_string(),
            steps: steps.into_iter().map(|s| PlanStep::new(&s)).collect(),
            current_step: 0,
            branch: None,
            created: now.clone(),
            updated: now,
            status: PlanStatus::Active,
        }
    }
    
    /// Start working on the plan
    pub fn start(&mut self) {
        if !self.steps.is_empty() {
            self.steps[0].start();
            self.touch();
        }
    }
    
    /// Advance to next step
    pub fn advance(&mut self, notes: &str) {
        if self.current_step < self.steps.len() {
            self.steps[self.current_step].complete(notes);
            self.current_step += 1;
            
            if self.current_step < self.steps.len() {
                self.steps[self.current_step].start();
            } else {
                self.status = PlanStatus::Complete;
            }
            
            self.touch();
        }
    }
    
    /// Block current step
    pub fn block(&mut self, reason: &str) {
        if self.current_step < self.steps.len() {
            self.steps[self.current_step].block(reason);
            self.touch();
        }
    }
    
    /// Skip current step
    pub fn skip(&mut self, reason: &str) {
        if self.current_step < self.steps.len() {
            self.steps[self.current_step].skip(reason);
            self.current_step += 1;
            
            if self.current_step < self.steps.len() {
                self.steps[self.current_step].start();
            }
            
            self.touch();
        }
    }
    
    /// Set checkpoint for current step
    pub fn checkpoint(&mut self, commit_sha: &str) {
        if self.current_step < self.steps.len() {
            self.steps[self.current_step].checkpoint = Some(commit_sha.to_string());
            self.touch();
        }
    }
    
    /// Get progress as fraction
    pub fn progress(&self) -> f32 {
        if self.steps.is_empty() {
            return 1.0;
        }
        
        let completed = self.steps.iter()
            .filter(|s| matches!(s.status, StepStatus::Complete | StepStatus::Skipped))
            .count();
        
        completed as f32 / self.steps.len() as f32
    }
    
    /// Get current step description
    pub fn current(&self) -> Option<&PlanStep> {
        self.steps.get(self.current_step)
    }
    
    /// Pause the plan
    pub fn pause(&mut self) {
        self.status = PlanStatus::Paused;
        self.touch();
    }
    
    /// Resume the plan
    pub fn resume(&mut self) {
        self.status = PlanStatus::Active;
        if let Some(step) = self.steps.get_mut(self.current_step) {
            if step.status == StepStatus::Pending {
                step.start();
            }
        }
        self.touch();
    }
    
    /// Abandon the plan
    pub fn abandon(&mut self, reason: &str) {
        self.status = PlanStatus::Abandoned;
        if let Some(step) = self.steps.get_mut(self.current_step) {
            step.notes = format!("Abandoned: {}", reason);
        }
        self.touch();
    }
    
    /// Get summary for display
    pub fn summary(&self) -> String {
        let progress_pct = (self.progress() * 100.0) as u8;
        let current = self.current()
            .map(|s| s.description.as_str())
            .unwrap_or("Complete");
        
        format!(
            "[{}%] {} - Current: {}",
            progress_pct,
            self.description,
            current
        )
    }
    
    fn touch(&mut self) {
        self.updated = chrono::Utc::now().to_rfc3339();
    }
}

/// Render plan as markdown
pub fn plan_to_markdown(plan: &TaskPlan) -> String {
    let mut md = format!(
        "# Plan: {}\n\n*ID: {} | Progress: {:.0}% | Status: {:?}*\n\n",
        plan.description,
        plan.id,
        plan.progress() * 100.0,
        plan.status
    );
    
    md.push_str("## Steps\n\n");
    
    for (i, step) in plan.steps.iter().enumerate() {
        let marker = match step.status {
            StepStatus::Complete => "✅",
            StepStatus::InProgress => "🔄",
            StepStatus::Blocked => "🚫",
            StepStatus::Skipped => "⏭️",
            StepStatus::Pending => "⬜",
        };
        
        let current = if i == plan.current_step && plan.status == PlanStatus::Active {
            " ← **Current**"
        } else {
            ""
        };
        
        md.push_str(&format!(
            "{}. {} {}{}\n",
            i + 1,
            marker,
            step.description,
            current
        ));
        
        if !step.notes.is_empty() {
            md.push_str(&format!("   *Notes: {}*\n", step.notes));
        }
        
        if let Some(ref checkpoint) = step.checkpoint {
            md.push_str(&format!("   *Checkpoint: {}*\n", checkpoint));
        }
    }
    
    md
}

