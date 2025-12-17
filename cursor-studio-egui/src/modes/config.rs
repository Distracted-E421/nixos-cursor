//! Custom Mode configuration structures

use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// A custom mode definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomMode {
    /// Mode name (displayed in UI)
    pub name: String,
    
    /// Mode description
    pub description: String,
    
    /// Icon emoji for this mode
    pub icon: String,
    
    /// System prompt to inject
    pub system_prompt: String,
    
    /// Tool access configuration
    pub tools: ToolAccess,
    
    /// Model configuration
    pub model: ModelConfig,
    
    /// Context configuration
    pub context: ContextConfig,
    
    /// Whether this is a built-in mode
    #[serde(default)]
    pub builtin: bool,
    
    /// Created timestamp
    pub created_at: Option<String>,
    
    /// Last modified timestamp
    pub modified_at: Option<String>,
}

/// Tool access control
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolAccess {
    /// Access mode
    pub mode: AccessMode,
    
    /// Explicitly allowed tools (when mode is Allowlist)
    #[serde(default)]
    pub allowed: HashSet<String>,
    
    /// Explicitly blocked tools (when mode is Blocklist)
    #[serde(default)]
    pub blocked: HashSet<String>,
}

/// How to interpret tool lists
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum AccessMode {
    /// All tools allowed
    #[default]
    AllAllowed,
    /// Only listed tools allowed
    Allowlist,
    /// All except listed tools allowed
    Blocklist,
}

/// Model configuration for the mode
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    /// Primary model for this mode
    pub primary: String,
    
    /// Fallback model if primary unavailable
    pub fallback: Option<String>,
    
    /// Temperature override (if any)
    pub temperature: Option<f32>,
    
    /// Max tokens override (if any)
    pub max_tokens: Option<u32>,
}

/// Context configuration for the mode
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextConfig {
    /// Include environment info
    #[serde(default = "default_true")]
    pub include_environment: bool,
    
    /// Include git state
    #[serde(default = "default_true")]
    pub include_git: bool,
    
    /// Include project-specific context
    #[serde(default = "default_true")]
    pub include_project: bool,
    
    /// Additional context files to include
    #[serde(default)]
    pub include_files: Vec<String>,
    
    /// Custom context injection
    #[serde(default)]
    pub custom_injection: String,
}

fn default_true() -> bool { true }

impl Default for ContextConfig {
    fn default() -> Self {
        Self {
            include_environment: true,
            include_git: true,
            include_project: true,
            include_files: Vec::new(),
            custom_injection: String::new(),
        }
    }
}

impl CustomMode {
    /// Create a new custom mode
    pub fn new(name: &str, description: &str) -> Self {
        Self {
            name: name.to_string(),
            description: description.to_string(),
            icon: "🤖".to_string(),
            system_prompt: String::new(),
            tools: ToolAccess::all_allowed(),
            model: ModelConfig::default(),
            context: ContextConfig::default(),
            builtin: false,
            created_at: Some(chrono::Utc::now().to_rfc3339()),
            modified_at: None,
        }
    }
    
    /// Default Agent mode - full access
    pub fn agent_default() -> Self {
        Self {
            name: "Agent".to_string(),
            description: "Full autonomous agent with all tools".to_string(),
            icon: "🤖".to_string(),
            system_prompt: r#"You are an autonomous coding agent. You have full access to read, write, and execute code.

## Operating Principles
1. **Plan before acting** - Think through the task before making changes
2. **Verify after each step** - Confirm changes work as expected
3. **Recover from errors** - If something fails, try alternative approaches
4. **Ask when uncertain** - Request clarification rather than guessing

## Safety Rules
- Never delete files without explicit confirmation
- Create backups before destructive operations
- Test changes before committing"#.to_string(),
            tools: ToolAccess::all_allowed(),
            model: ModelConfig::opus(),
            context: ContextConfig::default(),
            builtin: true,
            created_at: None,
            modified_at: None,
        }
    }
    
    /// Code Review mode - read-only
    pub fn code_review() -> Self {
        Self {
            name: "Code Review".to_string(),
            description: "Review code without modifications".to_string(),
            icon: "🔍".to_string(),
            system_prompt: r#"You are reviewing code for quality, bugs, and improvements.

## Focus Areas
- Correctness and edge cases
- Performance implications
- Security vulnerabilities
- Code clarity and maintainability
- Design patterns and architecture

## Constraints
- You CANNOT modify files
- Provide suggestions as code blocks, not edits
- Explain the reasoning behind each suggestion"#.to_string(),
            tools: ToolAccess::blocklist(&[
                "write",
                "edit_file",
                "delete_file",
                "run_terminal_cmd",
                "create_directory",
            ]),
            model: ModelConfig::sonnet(),
            context: ContextConfig::default(),
            builtin: true,
            created_at: None,
            modified_at: None,
        }
    }
    
    /// Maxim mode - from your Obsidian setup
    pub fn maxim_obsidian() -> Self {
        Self {
            name: "Maxim".to_string(),
            description: "Obsidian Agent - Primary Development Machine".to_string(),
            icon: "🖥️".to_string(),
            system_prompt: r#"You are Maxim, the AI agent for Obsidian (NixOS 25.11 workstation).

## Identity
- Primary development machine agent
- Cost: 2 requests per interaction
- Philosophy: Proactive with strict safety guardrails
- Goal: Maximize token usage per request

## Machine Context
- CPU: Intel i9-9900KS (8C/16T @ 5.0GHz)
- RAM: 32GB DDR4
- GPUs: Intel Arc A770 (16GB) + NVIDIA RTX 2080 (8GB)
- OS: NixOS 25.11 (Xantusia)
- User: e421

## Core Principles
1. Safety First: Never repeat the October 18, 2025 incident
2. Declarative Everything: All changes via NixOS config
3. Git Hub: All repo ops happen on Obsidian
4. Modern Tools: Use nom, nvd, nix-topology
5. Proactive with Guardrails: Act autonomously for safe ops, ask for dangerous ones

## SSH Access (always specify user)
- neon-laptop: ssh e421@neon-laptop
- framework: ssh e421@framework  
- pi-server: ssh e421@pi-server
- Evie-Desktop: ssh evie@Evie-Desktop (⚠️ Different user!)

## Absolute Prohibitions
- Bulk file deletion without explicit confirmation
- SQLite VACUUM on user databases
- Force push to git without explicit user command"#.to_string(),
            tools: ToolAccess::all_allowed(),
            model: ModelConfig::sonnet(),
            context: ContextConfig {
                include_environment: true,
                include_git: true,
                include_project: true,
                include_files: vec![
                    ".ai-workspace/environment.json".to_string(),
                    ".ai-workspace/context/current.json".to_string(),
                ],
                custom_injection: String::new(),
            },
            builtin: true,
            created_at: None,
            modified_at: None,
        }
    }
    
    /// Planning mode - think before acting
    pub fn planning() -> Self {
        Self {
            name: "Planning".to_string(),
            description: "Create detailed plans before execution".to_string(),
            icon: "📋".to_string(),
            system_prompt: r#"You are a planning assistant. Before taking any action, create a detailed plan.

## Planning Format
1. **Goal**: What are we trying to achieve?
2. **Current State**: What exists now?
3. **Steps**: Numbered steps with:
   - What to do
   - What tools needed
   - What could go wrong
   - How to verify success
4. **Risks**: What might fail?
5. **Rollback**: How to undo if needed?

## Rules
- Generate plan first, wait for approval
- Break large tasks into smaller steps
- Identify dependencies between steps
- Consider edge cases and error handling"#.to_string(),
            tools: ToolAccess::blocklist(&[
                "write",
                "edit_file", 
                "delete_file",
                "run_terminal_cmd",
            ]),
            model: ModelConfig::opus(),
            context: ContextConfig::default(),
            builtin: true,
            created_at: None,
            modified_at: None,
        }
    }
    
    /// Generate .cursorrules content from this mode
    pub fn to_cursorrules(&self) -> String {
        let mut sections = Vec::new();
        
        // System prompt
        sections.push(self.system_prompt.clone());
        
        // Tool restrictions
        match self.tools.mode {
            AccessMode::AllAllowed => {
                // No restrictions needed
            }
            AccessMode::Allowlist => {
                sections.push(format!(
                    "\n## Tool Access\nYou may ONLY use these tools:\n{}",
                    self.tools.allowed.iter()
                        .map(|t| format!("- {}", t))
                        .collect::<Vec<_>>()
                        .join("\n")
                ));
            }
            AccessMode::Blocklist => {
                sections.push(format!(
                    "\n## Tool Restrictions\nYou may NOT use these tools:\n{}",
                    self.tools.blocked.iter()
                        .map(|t| format!("- {}", t))
                        .collect::<Vec<_>>()
                        .join("\n")
                ));
            }
        }
        
        // Model preference (as hint)
        sections.push(format!(
            "\n## Model Preference\nPreferred model: {}",
            self.model.primary
        ));
        
        sections.join("\n")
    }
}

impl ToolAccess {
    /// All tools allowed
    pub fn all_allowed() -> Self {
        Self {
            mode: AccessMode::AllAllowed,
            allowed: HashSet::new(),
            blocked: HashSet::new(),
        }
    }
    
    /// Only specified tools allowed
    pub fn allowlist(tools: &[&str]) -> Self {
        Self {
            mode: AccessMode::Allowlist,
            allowed: tools.iter().map(|s| s.to_string()).collect(),
            blocked: HashSet::new(),
        }
    }
    
    /// All except specified tools allowed
    pub fn blocklist(tools: &[&str]) -> Self {
        Self {
            mode: AccessMode::Blocklist,
            allowed: HashSet::new(),
            blocked: tools.iter().map(|s| s.to_string()).collect(),
        }
    }
    
    /// Check if a tool is allowed
    pub fn is_allowed(&self, tool: &str) -> bool {
        match self.mode {
            AccessMode::AllAllowed => true,
            AccessMode::Allowlist => self.allowed.contains(tool),
            AccessMode::Blocklist => !self.blocked.contains(tool),
        }
    }
}

impl Default for ModelConfig {
    fn default() -> Self {
        Self::sonnet()
    }
}

impl ModelConfig {
    /// Claude Sonnet 4.5 (balanced)
    pub fn sonnet() -> Self {
        Self {
            primary: "claude-4.5-sonnet".to_string(),
            fallback: Some("claude-4-sonnet".to_string()),
            temperature: None,
            max_tokens: None,
        }
    }
    
    /// Claude Opus 4 (most capable)
    pub fn opus() -> Self {
        Self {
            primary: "claude-opus-4".to_string(),
            fallback: Some("claude-4.5-sonnet".to_string()),
            temperature: None,
            max_tokens: None,
        }
    }
    
    /// Claude Haiku (fastest)
    pub fn haiku() -> Self {
        Self {
            primary: "claude-3-haiku".to_string(),
            fallback: Some("claude-3.5-haiku".to_string()),
            temperature: None,
            max_tokens: None,
        }
    }
    
    /// GPT-4o
    pub fn gpt4o() -> Self {
        Self {
            primary: "gpt-4o".to_string(),
            fallback: Some("gpt-4-turbo".to_string()),
            temperature: None,
            max_tokens: None,
        }
    }
}

/// Configuration for the entire modes system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModeConfig {
    /// Directory for mode storage
    pub modes_dir: String,
    
    /// Whether to auto-generate .cursorrules
    pub auto_generate_cursorrules: bool,
    
    /// Path to generate .cursorrules to
    pub cursorrules_path: Option<String>,
    
    /// Whether to include environment in generated rules
    pub include_environment_in_rules: bool,
}

impl Default for ModeConfig {
    fn default() -> Self {
        Self {
            modes_dir: "~/.config/cursor-studio/modes".to_string(),
            auto_generate_cursorrules: true,
            cursorrules_path: None,
            include_environment_in_rules: true,
        }
    }
}

