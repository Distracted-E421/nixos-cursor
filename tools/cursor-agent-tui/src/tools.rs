//! Tool execution for cursor-agent-tui

use crate::config::Config;
use crate::error::{AgentError, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tracing::{debug, info, warn};

/// Tool runner
pub struct ToolRunner {
    /// Working directory
    cwd: PathBuf,
    /// Allowed paths
    allowed_paths: Vec<PathBuf>,
    /// Maximum file size
    max_file_size: usize,
    /// Command policy
    command_enabled: bool,
    command_confirmation: bool,
    blocked_patterns: Vec<String>,
}

impl ToolRunner {
    /// Create a new tool runner
    pub fn new(config: &Config) -> Result<Self> {
        let cwd = std::env::current_dir()?;
        
        let mut allowed_paths = config.tools.allowed_paths.clone();
        if allowed_paths.is_empty() {
            allowed_paths.push(cwd.clone());
        }

        Ok(Self {
            cwd,
            allowed_paths,
            max_file_size: config.tools.max_file_size,
            command_enabled: config.tools.command_policy.enabled,
            command_confirmation: config.tools.command_policy.require_confirmation,
            blocked_patterns: config.tools.command_policy.blocked_patterns.clone(),
        })
    }

    /// Execute a tool call
    pub async fn execute(&self, name: &str, args: &serde_json::Value) -> Result<String> {
        debug!("Executing tool: {} with args: {:?}", name, args);

        match name {
            "read_file" => self.read_file(args),
            "edit_file" | "write_file" => self.write_file(args),
            "run_command" | "terminal" => self.run_command(args).await,
            "search" | "grep" => self.search(args),
            "list_directory" | "list_dir" | "ls" => self.list_directory(args),
            _ => Err(AgentError::Tool(format!("Unknown tool: {}", name))),
        }
    }

    /// Check if a path is allowed
    fn is_path_allowed(&self, path: &Path) -> bool {
        let full_path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.cwd.join(path)
        };

        let canonical = match full_path.canonicalize() {
            Ok(p) => p,
            Err(_) => return false,
        };

        for allowed in &self.allowed_paths {
            if let Ok(allowed_canonical) = allowed.canonicalize() {
                if canonical.starts_with(&allowed_canonical) {
                    return true;
                }
            }
        }

        false
    }

    /// Read a file
    fn read_file(&self, args: &serde_json::Value) -> Result<String> {
        #[derive(Deserialize)]
        struct Args {
            path: String,
        }

        let args: Args = serde_json::from_value(args.clone())?;
        let path = Path::new(&args.path);

        if !self.is_path_allowed(path) {
            return Err(AgentError::Tool(format!(
                "Path not allowed: {}",
                args.path
            )));
        }

        let full_path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.cwd.join(path)
        };

        if !full_path.exists() {
            return Err(AgentError::Tool(format!(
                "File not found: {}",
                full_path.display()
            )));
        }

        let metadata = std::fs::metadata(&full_path)?;
        if metadata.len() as usize > self.max_file_size {
            return Err(AgentError::Tool(format!(
                "File too large: {} bytes (max: {})",
                metadata.len(),
                self.max_file_size
            )));
        }

        let content = std::fs::read_to_string(&full_path)?;
        info!("Read file: {} ({} bytes)", args.path, content.len());
        Ok(content)
    }

    /// Write/edit a file
    fn write_file(&self, args: &serde_json::Value) -> Result<String> {
        #[derive(Deserialize)]
        struct Args {
            path: String,
            content: String,
        }

        let args: Args = serde_json::from_value(args.clone())?;
        let path = Path::new(&args.path);

        if !self.is_path_allowed(path) {
            return Err(AgentError::Tool(format!(
                "Path not allowed: {}",
                args.path
            )));
        }

        let full_path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.cwd.join(path)
        };

        // Create parent directories if needed
        if let Some(parent) = full_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        std::fs::write(&full_path, &args.content)?;
        info!("Wrote file: {} ({} bytes)", args.path, args.content.len());
        Ok(format!("Successfully wrote {} bytes to {}", args.content.len(), args.path))
    }

    /// Run a command
    async fn run_command(&self, args: &serde_json::Value) -> Result<String> {
        #[derive(Deserialize)]
        struct Args {
            command: String,
            #[serde(default)]
            cwd: Option<String>,
        }

        if !self.command_enabled {
            return Err(AgentError::Tool("Command execution is disabled".to_string()));
        }

        let args: Args = serde_json::from_value(args.clone())?;

        // Check for blocked patterns
        for pattern in &self.blocked_patterns {
            if args.command.contains(pattern) {
                return Err(AgentError::Tool(format!(
                    "Command blocked by policy: contains '{}'",
                    pattern
                )));
            }
        }

        let cwd = if let Some(ref dir) = args.cwd {
            let path = Path::new(dir);
            if !self.is_path_allowed(path) {
                return Err(AgentError::Tool(format!(
                    "Working directory not allowed: {}",
                    dir
                )));
            }
            self.cwd.join(path)
        } else {
            self.cwd.clone()
        };

        info!("Running command: {} in {}", args.command, cwd.display());

        let output = tokio::process::Command::new("sh")
            .arg("-c")
            .arg(&args.command)
            .current_dir(&cwd)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);

        let result = if output.status.success() {
            if stderr.is_empty() {
                stdout.to_string()
            } else {
                format!("{}\n[stderr]\n{}", stdout, stderr)
            }
        } else {
            format!(
                "[exit code: {}]\n{}\n[stderr]\n{}",
                output.status.code().unwrap_or(-1),
                stdout,
                stderr
            )
        };

        // Truncate if too long
        if result.len() > 100_000 {
            Ok(format!(
                "{}...\n[truncated, {} bytes total]",
                &result[..100_000],
                result.len()
            ))
        } else {
            Ok(result)
        }
    }

    /// Search for files/content
    fn search(&self, args: &serde_json::Value) -> Result<String> {
        #[derive(Deserialize)]
        struct Args {
            pattern: String,
            #[serde(default)]
            path: Option<String>,
            #[serde(default)]
            file_pattern: Option<String>,
        }

        let args: Args = serde_json::from_value(args.clone())?;

        let search_path = if let Some(ref p) = args.path {
            let path = Path::new(p);
            if !self.is_path_allowed(path) {
                return Err(AgentError::Tool(format!(
                    "Path not allowed: {}",
                    p
                )));
            }
            self.cwd.join(path)
        } else {
            self.cwd.clone()
        };

        info!("Searching for '{}' in {}", args.pattern, search_path.display());

        // Use ripgrep if available, otherwise fall back to grep
        let mut command = if which::which("rg").is_ok() {
            let mut cmd = std::process::Command::new("rg");
            cmd.args(["--line-number", "--no-heading", "--color=never"]);
            if let Some(ref file_pattern) = args.file_pattern {
                cmd.args(["--glob", file_pattern]);
            }
            cmd.arg(&args.pattern);
            cmd.arg(&search_path);
            cmd
        } else {
            let mut cmd = std::process::Command::new("grep");
            cmd.args(["-rn", "--color=never"]);
            if let Some(ref file_pattern) = args.file_pattern {
                cmd.args(["--include", file_pattern]);
            }
            cmd.arg(&args.pattern);
            cmd.arg(&search_path);
            cmd
        };

        let output = command
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()?;

        let result = String::from_utf8_lossy(&output.stdout);
        
        // Limit results
        let lines: Vec<&str> = result.lines().take(100).collect();
        let total_matches = result.lines().count();
        
        if total_matches > 100 {
            Ok(format!(
                "{}\n\n[showing 100 of {} matches]",
                lines.join("\n"),
                total_matches
            ))
        } else {
            Ok(lines.join("\n"))
        }
    }

    /// List directory contents
    fn list_directory(&self, args: &serde_json::Value) -> Result<String> {
        #[derive(Deserialize)]
        struct Args {
            #[serde(default)]
            path: Option<String>,
            #[serde(default)]
            recursive: Option<bool>,
        }

        let args: Args = serde_json::from_value(args.clone())?;

        let dir_path = if let Some(ref p) = args.path {
            let path = Path::new(p);
            if !self.is_path_allowed(path) {
                return Err(AgentError::Tool(format!(
                    "Path not allowed: {}",
                    p
                )));
            }
            self.cwd.join(path)
        } else {
            self.cwd.clone()
        };

        if !dir_path.is_dir() {
            return Err(AgentError::Tool(format!(
                "Not a directory: {}",
                dir_path.display()
            )));
        }

        let recursive = args.recursive.unwrap_or(false);
        let mut entries = Vec::new();

        if recursive {
            // Use walkdir for recursive listing
            for entry in walkdir::WalkDir::new(&dir_path)
                .max_depth(3) // Limit depth
                .into_iter()
                .filter_map(|e| e.ok())
                .take(500) // Limit entries
            {
                let relative = entry.path()
                    .strip_prefix(&dir_path)
                    .unwrap_or(entry.path());
                
                let prefix = if entry.file_type().is_dir() { "📁 " } else { "📄 " };
                entries.push(format!("{}{}", prefix, relative.display()));
            }
        } else {
            for entry in std::fs::read_dir(&dir_path)? {
                let entry = entry?;
                let file_type = entry.file_type()?;
                let prefix = if file_type.is_dir() { "📁 " } else { "📄 " };
                entries.push(format!("{}{}", prefix, entry.file_name().to_string_lossy()));
            }
            entries.sort();
        }

        Ok(entries.join("\n"))
    }

    /// Get current working directory
    pub fn cwd(&self) -> &Path {
        &self.cwd
    }

    /// Set current working directory
    pub fn set_cwd(&mut self, cwd: PathBuf) {
        self.cwd = cwd;
    }
}

