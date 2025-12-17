//! Mode injection system - applies modes to Cursor

use super::{CustomMode, ModeRegistry};
use crate::ai_workspace::{EnvironmentState, AliasRegistry};
use std::path::PathBuf;

/// Where to inject mode configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InjectionTarget {
    /// Generate .cursorrules in project root
    CursorRules,
    /// Generate to .cursor/rules/ directory
    CursorRulesDir,
    /// Generate to AI workspace hints
    AiWorkspace,
    /// All targets
    All,
}

/// Handles injecting mode configuration into Cursor
pub struct ModeInjector {
    /// Project root directory
    project_root: PathBuf,
    
    /// AI workspace directory
    ai_workspace: PathBuf,
    
    /// Environment state for context injection
    environment: Option<EnvironmentState>,
    
    /// Alias registry for machine-specific context
    aliases: Option<AliasRegistry>,
}

impl ModeInjector {
    /// Create a new injector for a project
    pub fn new(project_root: PathBuf) -> Self {
        let ai_workspace = project_root.join(".ai-workspace");
        
        Self {
            project_root,
            ai_workspace,
            environment: None,
            aliases: None,
        }
    }
    
    /// Set environment context
    pub fn with_environment(mut self, env: EnvironmentState) -> Self {
        self.environment = Some(env);
        self
    }
    
    /// Set alias registry
    pub fn with_aliases(mut self, aliases: AliasRegistry) -> Self {
        self.aliases = Some(aliases);
        self
    }
    
    /// Inject a mode configuration
    pub fn inject(&self, mode: &CustomMode, target: InjectionTarget) -> std::io::Result<Vec<PathBuf>> {
        let mut generated = Vec::new();
        
        match target {
            InjectionTarget::CursorRules => {
                let path = self.inject_cursorrules(mode)?;
                generated.push(path);
            }
            InjectionTarget::CursorRulesDir => {
                let path = self.inject_cursor_rules_dir(mode)?;
                generated.push(path);
            }
            InjectionTarget::AiWorkspace => {
                let paths = self.inject_ai_workspace(mode)?;
                generated.extend(paths);
            }
            InjectionTarget::All => {
                generated.push(self.inject_cursorrules(mode)?);
                generated.push(self.inject_cursor_rules_dir(mode)?);
                generated.extend(self.inject_ai_workspace(mode)?);
            }
        }
        
        Ok(generated)
    }
    
    /// Generate .cursorrules file
    fn inject_cursorrules(&self, mode: &CustomMode) -> std::io::Result<PathBuf> {
        let path = self.project_root.join(".cursorrules");
        let content = self.generate_full_rules(mode);
        std::fs::write(&path, content)?;
        Ok(path)
    }
    
    /// Generate file in .cursor/rules/ directory
    fn inject_cursor_rules_dir(&self, mode: &CustomMode) -> std::io::Result<PathBuf> {
        let rules_dir = self.project_root.join(".cursor").join("rules");
        std::fs::create_dir_all(&rules_dir)?;
        
        let filename = format!("{}.mdc", mode.name.to_lowercase().replace(' ', "-"));
        let path = rules_dir.join(&filename);
        
        let content = format!(
            "# {}\n\n{}\n\n{}\n",
            mode.name,
            mode.description,
            mode.to_cursorrules()
        );
        
        std::fs::write(&path, content)?;
        Ok(path)
    }
    
    /// Update AI workspace with mode context
    fn inject_ai_workspace(&self, mode: &CustomMode) -> std::io::Result<Vec<PathBuf>> {
        std::fs::create_dir_all(&self.ai_workspace)?;
        let mut generated = Vec::new();
        
        // Update hints.md
        let hints_path = self.ai_workspace.join("hints.md");
        let hints_content = self.generate_hints(mode);
        std::fs::write(&hints_path, hints_content)?;
        generated.push(hints_path);
        
        // Update relevant-tools.md
        let tools_path = self.ai_workspace.join("relevant-tools.md");
        let tools_content = self.generate_relevant_tools(mode);
        std::fs::write(&tools_path, tools_content)?;
        generated.push(tools_path);
        
        // Update context/current.json
        let context_dir = self.ai_workspace.join("context");
        std::fs::create_dir_all(&context_dir)?;
        let context_path = context_dir.join("current.json");
        let context_content = self.generate_context_json(mode);
        std::fs::write(&context_path, context_content)?;
        generated.push(context_path);
        
        Ok(generated)
    }
    
    /// Generate full rules content with environment
    fn generate_full_rules(&self, mode: &CustomMode) -> String {
        let mut sections = Vec::new();
        
        // Mode header
        sections.push(format!("# Active Mode: {}\n", mode.name));
        sections.push(mode.description.clone());
        sections.push(String::new());
        
        // System prompt
        sections.push(mode.system_prompt.clone());
        
        // Environment context (if enabled and available)
        if mode.context.include_environment {
            if let Some(ref env) = self.environment {
                sections.push(String::new());
                sections.push("## Current Environment".to_string());
                sections.push(env.to_injection());
                
                // Add aliases if available
                if let Some(ref aliases) = self.aliases {
                    sections.push(aliases.to_injection(&env.hostname));
                }
            }
        }
        
        // Tool restrictions
        sections.push(self.generate_tool_section(mode));
        
        // Model hint
        sections.push(format!(
            "\n## Model\nThis mode is optimized for: {}\n",
            mode.model.primary
        ));
        
        sections.join("\n")
    }
    
    /// Generate tool restriction section
    fn generate_tool_section(&self, mode: &CustomMode) -> String {
        use super::config::AccessMode;
        
        match mode.tools.mode {
            AccessMode::AllAllowed => {
                String::from("\n## Tools\nAll tools are available.\n")
            }
            AccessMode::Allowlist => {
                let tools: Vec<_> = mode.tools.allowed.iter().collect();
                format!(
                    "\n## Tool Access (ALLOWLIST)\nYou may ONLY use these tools:\n{}\n\nAll other tools are BLOCKED.\n",
                    tools.iter().map(|t| format!("- `{}`", t)).collect::<Vec<_>>().join("\n")
                )
            }
            AccessMode::Blocklist => {
                let tools: Vec<_> = mode.tools.blocked.iter().collect();
                format!(
                    "\n## Tool Restrictions (BLOCKLIST)\nYou may NOT use these tools:\n{}\n\nAll other tools are allowed.\n",
                    tools.iter().map(|t| format!("- `{}`", t)).collect::<Vec<_>>().join("\n")
                )
            }
        }
    }
    
    /// Generate hints for AI workspace
    fn generate_hints(&self, mode: &CustomMode) -> String {
        let mut hints = Vec::new();
        
        hints.push(format!("# Hints for Mode: {}", mode.name));
        hints.push(String::new());
        hints.push(format!("*Generated: {}*", chrono::Utc::now().to_rfc3339()));
        hints.push(String::new());
        
        // Mode-specific hints
        hints.push("## Mode Reminders".to_string());
        hints.push(String::new());
        
        use super::config::AccessMode;
        match mode.tools.mode {
            AccessMode::Blocklist if !mode.tools.blocked.is_empty() => {
                hints.push("⚠️ **Tool Restrictions Active**".to_string());
                hints.push(format!(
                    "Blocked: {}",
                    mode.tools.blocked.iter().cloned().collect::<Vec<_>>().join(", ")
                ));
            }
            AccessMode::Allowlist => {
                hints.push("🔒 **Limited Tool Access**".to_string());
                hints.push(format!(
                    "Only allowed: {}",
                    mode.tools.allowed.iter().cloned().collect::<Vec<_>>().join(", ")
                ));
            }
            _ => {}
        }
        
        // Environment hints
        if let Some(ref env) = self.environment {
            hints.push(String::new());
            hints.push("## Environment".to_string());
            hints.push(format!("- Host: {}", env.hostname));
            hints.push(format!("- OS: {} {}", env.os.name, env.os.version));
            
            if let Some(ref git) = env.git_state {
                hints.push(format!("- Branch: {}", git.branch));
                if git.uncommitted > 0 {
                    hints.push(format!("- ⚠️ {} uncommitted changes", git.uncommitted));
                }
            }
        }
        
        hints.join("\n")
    }
    
    /// Generate relevant tools list
    fn generate_relevant_tools(&self, mode: &CustomMode) -> String {
        let mut content = Vec::new();
        
        content.push(format!("# Relevant Tools for: {}", mode.name));
        content.push(String::new());
        
        use super::config::AccessMode;
        match mode.tools.mode {
            AccessMode::AllAllowed => {
                content.push("All tools available. Focus on task-relevant ones.".to_string());
                content.push(String::new());
                content.push("## Common Tools".to_string());
                content.push("- `read_file` - Read file contents".to_string());
                content.push("- `write` - Write/create files".to_string());
                content.push("- `grep` - Search in files".to_string());
                content.push("- `run_terminal_cmd` - Execute commands".to_string());
            }
            AccessMode::Allowlist => {
                content.push("## Allowed Tools".to_string());
                for tool in &mode.tools.allowed {
                    content.push(format!("- `{}`", tool));
                }
            }
            AccessMode::Blocklist => {
                content.push("## Available Tools (blocklist mode)".to_string());
                content.push("Most tools available except:".to_string());
                for tool in &mode.tools.blocked {
                    content.push(format!("- ~~`{}`~~ (blocked)", tool));
                }
            }
        }
        
        content.join("\n")
    }
    
    /// Generate context JSON
    fn generate_context_json(&self, mode: &CustomMode) -> String {
        let context = serde_json::json!({
            "mode": {
                "name": mode.name,
                "icon": mode.icon,
                "description": mode.description,
            },
            "tools": {
                "mode": format!("{:?}", mode.tools.mode),
                "restrictions_active": mode.tools.mode != super::config::AccessMode::AllAllowed,
            },
            "model": {
                "primary": mode.model.primary,
                "fallback": mode.model.fallback,
            },
            "environment": self.environment.as_ref().map(|e| serde_json::json!({
                "hostname": e.hostname,
                "os": format!("{} {}", e.os.name, e.os.version),
                "user": e.user,
                "git_branch": e.git_state.as_ref().map(|g| &g.branch),
            })),
            "generated_at": chrono::Utc::now().to_rfc3339(),
        });
        
        serde_json::to_string_pretty(&context).unwrap_or_default()
    }
}

/// Quick function to apply a mode to the current project
pub fn apply_mode(
    project_root: PathBuf,
    registry: &ModeRegistry,
    mode_name: &str,
    target: InjectionTarget,
) -> std::io::Result<Vec<PathBuf>> {
    let mode = registry.modes.get(mode_name)
        .ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("Mode '{}' not found", mode_name)
        ))?;
    
    let injector = ModeInjector::new(project_root);
    injector.inject(mode, target)
}

