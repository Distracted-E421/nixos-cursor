# Context-Aware Tool Injection System

## The Problem

### Current MCP Architecture

```
Every AI Message:
┌─────────────────────────────────────────────────────────┐
│ System Prompt (~500 tokens)                             │
├─────────────────────────────────────────────────────────┤
│ Tool Definitions (~2000-4000 tokens)                    │  ← REPEATED EVERY MESSAGE
│   - filesystem (25 tools × 80 tokens each)              │
│   - github (30 tools × 80 tokens each)                  │
│   - memory (10 tools × 60 tokens each)                  │
│   - playwright (20 tools × 70 tokens each)              │
│   - nixos (15 tools × 70 tokens each)                   │
├─────────────────────────────────────────────────────────┤
│ Conversation History                                    │
├─────────────────────────────────────────────────────────┤
│ User Message                                            │
└─────────────────────────────────────────────────────────┘

Result: 2000-4000 tokens of tool schemas EVERY turn
        → Faster context collapse
        → AI "forgets" less-used tools
        → Homogenized tool usage (only common paths used)
```

### Why This Causes Problems

1. **Cognitive Load**: AI sees 100+ tool options, gravitates to familiar ones
2. **Training Bias**: AI trained on devs who also underuse git/memory features
3. **No Context**: Tools presented statically, not based on current task
4. **Noise**: Irrelevant tools (browser testing during file editing) waste attention
5. **No AI Workspace**: AI has no persistent scratch space for its own ideas

## The Solution: Context-Aware Tool Injection

### Core Concept

Instead of:
```
[All 100 tools] → AI → [uses 5 common ones]
```

Do this:
```
[Context Analyzer] → [Relevant 5-10 tools] → AI → [uses them effectively]
                  ↓
           [Subtle hints about underused capabilities]
```

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Context-Aware Middleware                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │   Context   │    │    Tool     │    │   Hint      │          │
│  │  Analyzer   │───▶│  Selector   │───▶│  Injector   │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│         │                  │                  │                   │
│         ▼                  ▼                  ▼                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │ Task Type   │    │  Relevant   │    │  Contextual │          │
│  │ Detection   │    │   Tools     │    │   Reminders │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│                                                                   │
├──────────────────────────────────────────────────────────────────┤
│                    AI Workspace Manager                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │   Idea      │    │   Branch    │    │  Progress   │          │
│  │  Scratchpad │    │   Manager   │    │   Tracker   │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│                                                                   │
│  AI can:                                                          │
│  - Draft ideas in scratchpad before committing                   │
│  - Create experiment branches automatically                       │
│  - Track multi-step plans with checkpoints                       │
│  - Rollback to previous approach if stuck                        │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Context Analyzer

Detects what the AI is currently doing:

```rust
pub enum TaskContext {
    // File operations
    FileExploration,      // Reading, understanding code
    FileModification,     // Writing, editing files
    
    // Development
    Debugging,            // Finding/fixing bugs
    Refactoring,          // Restructuring code
    NewFeature,           // Adding functionality
    
    // Version control
    PreCommit,            // About to commit changes
    BranchManagement,     // Working with branches
    
    // Documentation
    Writing,              // Creating docs, comments
    Research,             // Looking up information
    
    // System operations
    Configuration,        // Editing configs, Nix
    ServiceManagement,    // Starting/stopping services
    
    // Planning
    Brainstorming,        // Exploring ideas
    ArchitectureDesign,   // System design
}

impl TaskContext {
    pub fn detect(conversation: &[Message]) -> Vec<TaskContext> {
        // Analyze recent messages to determine context
        // Can have multiple contexts active
    }
}
```

### 2. Tool Selector

Maps contexts to relevant tools:

```rust
pub struct ToolRelevance {
    tool_name: String,
    relevance: f32,     // 0.0 to 1.0
    hint: Option<String>, // Contextual suggestion
}

impl ToolSelector {
    pub fn select(&self, contexts: &[TaskContext]) -> Vec<ToolRelevance> {
        let mut tools = Vec::new();
        
        for context in contexts {
            match context {
                TaskContext::FileModification => {
                    tools.push(ToolRelevance {
                        tool_name: "write".into(),
                        relevance: 1.0,
                        hint: None,
                    });
                    tools.push(ToolRelevance {
                        tool_name: "search_replace".into(),
                        relevance: 0.9,
                        hint: None,
                    });
                    // Subtle hint about version control
                    tools.push(ToolRelevance {
                        tool_name: "git_stash".into(),
                        relevance: 0.6,
                        hint: Some("Consider stashing current changes before major edits".into()),
                    });
                }
                
                TaskContext::Brainstorming => {
                    tools.push(ToolRelevance {
                        tool_name: "ai_scratchpad".into(),
                        relevance: 1.0,
                        hint: Some("Use scratchpad to draft ideas before implementing".into()),
                    });
                    tools.push(ToolRelevance {
                        tool_name: "git_branch_create".into(),
                        relevance: 0.8,
                        hint: Some("Create an experiment branch for this exploration".into()),
                    });
                    tools.push(ToolRelevance {
                        tool_name: "memory_store".into(),
                        relevance: 0.9,
                        hint: Some("Remember key decisions for future reference".into()),
                    });
                }
                
                TaskContext::PreCommit => {
                    tools.push(ToolRelevance {
                        tool_name: "git_diff".into(),
                        relevance: 1.0,
                        hint: Some("Review changes before committing".into()),
                    });
                    tools.push(ToolRelevance {
                        tool_name: "git_add_interactive".into(),
                        relevance: 0.7,
                        hint: Some("Consider staging changes selectively".into()),
                    });
                    tools.push(ToolRelevance {
                        tool_name: "memory_store".into(),
                        relevance: 0.8,
                        hint: Some("Document the 'why' behind this change".into()),
                    });
                }
                
                // ... more contexts
            }
        }
        
        // Deduplicate and sort by relevance
        tools.sort_by(|a, b| b.relevance.partial_cmp(&a.relevance).unwrap());
        tools.dedup_by(|a, b| a.tool_name == b.tool_name);
        tools
    }
}
```

### 3. Hint Injector

Adds minimal, contextual hints without full tool schemas:

```rust
pub struct HintInjector {
    // Track what hints have been shown recently
    shown_hints: HashMap<String, Instant>,
    hint_cooldown: Duration,
}

impl HintInjector {
    pub fn generate_hints(&mut self, tools: &[ToolRelevance]) -> String {
        let mut hints = Vec::new();
        
        for tool in tools {
            if let Some(hint) = &tool.hint {
                // Only show hint if not shown recently
                if !self.recently_shown(&tool.tool_name) {
                    hints.push(format!("💡 {}", hint));
                    self.mark_shown(&tool.tool_name);
                }
            }
        }
        
        if hints.is_empty() {
            return String::new();
        }
        
        // Compact format - not a full tool definition, just reminders
        format!("\n---\n{}\n---", hints.join("\n"))
    }
}
```

### 4. AI Workspace Manager

Gives AI persistent workspace for its own thinking:

```rust
pub struct AiWorkspace {
    // Scratchpad for ideas that aren't ready for main code
    scratchpad: PathBuf,  // .ai-workspace/scratchpad/
    
    // Branch manager for AI experiments
    experiment_branches: Vec<String>,
    
    // Progress tracker for multi-step tasks
    active_plans: HashMap<String, TaskPlan>,
}

pub struct TaskPlan {
    id: String,
    description: String,
    steps: Vec<PlanStep>,
    current_step: usize,
    branch: Option<String>,
    created: Instant,
}

pub struct PlanStep {
    description: String,
    status: StepStatus,
    notes: String,
    checkpoint: Option<String>,  // Git commit SHA
}

impl AiWorkspace {
    /// AI can draft ideas here before touching real code
    pub fn draft(&mut self, name: &str, content: &str) -> Result<PathBuf> {
        let path = self.scratchpad.join(format!("{}.md", name));
        std::fs::write(&path, content)?;
        Ok(path)
    }
    
    /// Create an experiment branch for risky changes
    pub fn start_experiment(&mut self, name: &str) -> Result<String> {
        let branch_name = format!("ai-experiment/{}", name);
        // git checkout -b branch_name
        self.experiment_branches.push(branch_name.clone());
        Ok(branch_name)
    }
    
    /// Checkpoint current progress
    pub fn checkpoint(&mut self, plan_id: &str, message: &str) -> Result<String> {
        // git add -A && git commit -m "AI checkpoint: {message}"
        // Return commit SHA
    }
    
    /// Rollback to previous checkpoint
    pub fn rollback(&mut self, plan_id: &str, checkpoint: &str) -> Result<()> {
        // git reset --hard {checkpoint}
    }
    
    /// AI can create and track multi-step plans
    pub fn create_plan(&mut self, description: &str, steps: Vec<String>) -> String {
        let id = uuid::Uuid::new_v4().to_string();
        let plan = TaskPlan {
            id: id.clone(),
            description: description.to_string(),
            steps: steps.into_iter().map(|s| PlanStep {
                description: s,
                status: StepStatus::Pending,
                notes: String::new(),
                checkpoint: None,
            }).collect(),
            current_step: 0,
            branch: None,
            created: Instant::now(),
        };
        self.active_plans.insert(id.clone(), plan);
        id
    }
}
```

## Implementation Strategy

### Phase 1: Local Tool Injection File

Create a file that Cursor rules can reference:

```
.ai-workspace/
├── context.json          # Current detected context
├── relevant-tools.md     # Tools relevant to current context
├── hints.md              # Active hints/reminders
├── scratchpad/           # AI draft area
│   └── *.md
├── plans/                # Multi-step task tracking
│   └── *.json
└── experiments/          # References to experiment branches
    └── *.json
```

### Phase 2: Cursor Rule Integration

Create dynamic rules that read from workspace:

```markdown
# .cursor/rules/context-aware-tools.mdc

{{include:.ai-workspace/hints.md}}

## Current Context
{{include:.ai-workspace/context.json}}

## Relevant Tools for This Task
{{include:.ai-workspace/relevant-tools.md}}
```

### Phase 3: Background Service

A lightweight service that:
1. Monitors conversation/activity
2. Updates context detection
3. Refreshes relevant tools
4. Manages AI workspace

```rust
pub struct ContextService {
    workspace: AiWorkspace,
    analyzer: ContextAnalyzer,
    selector: ToolSelector,
    injector: HintInjector,
}

impl ContextService {
    pub async fn run(&mut self) {
        loop {
            // Watch for conversation changes
            let messages = self.read_recent_messages().await;
            
            // Detect context
            let contexts = self.analyzer.detect(&messages);
            
            // Select relevant tools
            let tools = self.selector.select(&contexts);
            
            // Generate hints
            let hints = self.injector.generate_hints(&tools);
            
            // Write to workspace files
            self.write_context(&contexts).await;
            self.write_relevant_tools(&tools).await;
            self.write_hints(&hints).await;
            
            // Short sleep
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    }
}
```

## Memory Redesign

Current memory is a simple key-value store. Better design:

### Structured Memory Graph

```rust
pub struct MemoryGraph {
    db: sled::Db,
    
    // Different memory types
    facts: Tree,        // Stable facts (hardware specs, preferences)
    decisions: Tree,    // Why certain choices were made
    learnings: Tree,    // What worked/didn't work
    context: Tree,      // Current project context
    plans: Tree,        // Active and historical plans
}

pub struct MemoryEntry {
    id: String,
    content: String,
    memory_type: MemoryType,
    confidence: f32,      // How certain is this information
    source: String,       // Where did this come from
    created: DateTime,
    last_accessed: DateTime,
    access_count: u32,
    related: Vec<String>, // Links to related memories
    tags: Vec<String>,
}

impl MemoryGraph {
    /// Store with automatic categorization
    pub fn remember(&mut self, content: &str, context: &str) -> Result<String> {
        // AI or heuristics determine memory type
        let memory_type = self.categorize(content);
        
        // Find related memories
        let related = self.find_related(content);
        
        // Create entry with full metadata
        let entry = MemoryEntry {
            id: uuid::Uuid::new_v4().to_string(),
            content: content.to_string(),
            memory_type,
            confidence: 1.0,
            source: context.to_string(),
            created: Utc::now(),
            last_accessed: Utc::now(),
            access_count: 0,
            related,
            tags: self.extract_tags(content),
        };
        
        self.store(entry)
    }
    
    /// Contextual recall - not just keyword search
    pub fn recall(&self, query: &str, context: &TaskContext) -> Vec<MemoryEntry> {
        // Weight results by:
        // 1. Semantic similarity to query
        // 2. Relevance to current context
        // 3. Recency and access frequency
        // 4. Confidence level
    }
    
    /// Proactive surfacing - suggest relevant memories
    pub fn surface_relevant(&self, context: &TaskContext) -> Vec<MemoryEntry> {
        // Without explicit query, surface memories that might be useful
        // Based on current task context
    }
}
```

### Memory-Aware Hints

```rust
impl HintInjector {
    pub fn memory_hints(&self, context: &TaskContext, memory: &MemoryGraph) -> Vec<String> {
        let mut hints = Vec::new();
        
        // Surface relevant memories
        let relevant = memory.surface_relevant(context);
        for entry in relevant.iter().take(3) {
            hints.push(format!("📝 Remember: {}", entry.content));
        }
        
        // Suggest what to remember
        if context == TaskContext::PreCommit {
            hints.push("💭 Consider documenting why this change was made".into());
        }
        
        hints
    }
}
```

## Git Workflow Enhancement

### AI-Friendly Git Operations

```rust
pub struct AiGitOps {
    repo: git2::Repository,
}

impl AiGitOps {
    /// Create experiment branch with metadata
    pub fn start_experiment(&self, name: &str, hypothesis: &str) -> Result<()> {
        let branch = format!("ai-experiment/{}", name);
        // Create branch
        // Store hypothesis in branch description or .ai-workspace
    }
    
    /// Intelligent staging - group related changes
    pub fn smart_stage(&self) -> Result<Vec<StagingGroup>> {
        // Analyze diff to group related changes
        // Suggest splitting into multiple commits
    }
    
    /// Generate commit message from changes
    pub fn suggest_commit_message(&self) -> Result<String> {
        // Analyze staged changes
        // Generate conventional commit message
    }
    
    /// Create checkpoint without disrupting flow
    pub fn checkpoint(&self, note: &str) -> Result<String> {
        // Lightweight commit: "WIP: {note}"
        // Return SHA for potential rollback
    }
    
    /// Squash checkpoints into clean commit
    pub fn finalize_work(&self, message: &str) -> Result<()> {
        // Interactive rebase to squash WIP commits
        // Create clean final commit
    }
}
```

### Git Context Hints

```markdown
## Git Workflow Reminders

Current branch: `feature/cursor-studio-index`
Uncommitted changes: 5 files modified

💡 **Suggestions:**
- Consider creating a checkpoint before major refactoring
- You have 3 WIP commits - squash them before PR
- This branch is 12 commits ahead of main - consider rebasing
```

## Token Savings Estimate

| Component | Current (tokens/turn) | After (tokens/turn) | Savings |
|-----------|----------------------|---------------------|---------|
| Tool schemas | 2000-4000 | 200-400 (relevant only) | ~90% |
| Memory queries | 300-500 | 50-100 (targeted) | ~80% |
| Git operations | 400-600 | 100-200 (contextual) | ~70% |
| Hints/reminders | 0 | 50-150 (value-add) | N/A |

**Net effect**: More useful information in fewer tokens

## Implementation Priority

1. **AI Workspace** - Give AI a place to think
2. **Context Analyzer** - Know what AI is doing
3. **Hint Injector** - Subtle, useful reminders
4. **Memory Redesign** - Structured, contextual memory
5. **Git Integration** - AI manages its own workflow
6. **Tool Selector** - Dynamic tool presentation

## Next Steps

1. [ ] Create `.ai-workspace/` directory structure
2. [ ] Implement basic context detection
3. [ ] Create Cursor rule that reads from workspace files
4. [ ] Build hint generation based on context
5. [ ] Implement AI scratchpad functionality
6. [ ] Add git checkpoint/experiment support

