//! Context management for cursor-agent-tui

use crate::error::{AgentError, Result};
use std::path::{Path, PathBuf};
use tracing::debug;

/// File in context
#[derive(Debug, Clone)]
pub struct FileInContext {
    pub path: String,
    pub content: String,
    pub language: Option<String>,
}

/// Built context for a request
#[derive(Debug, Clone, Default)]
pub struct Context {
    pub files: Vec<FileInContext>,
    pub cwd: Option<String>,
    pub git_branch: Option<String>,
}

/// Context manager
pub struct ContextManager {
    /// Working directory
    cwd: PathBuf,
    /// Files currently in context
    files: Vec<FileInContext>,
    /// Maximum file size to load
    max_file_size: usize,
}

impl ContextManager {
    /// Create a new context manager
    pub fn new(cwd: PathBuf) -> Self {
        Self {
            cwd,
            files: Vec::new(),
            max_file_size: 10 * 1024 * 1024, // 10MB default
        }
    }

    /// Set maximum file size
    pub fn with_max_file_size(mut self, size: usize) -> Self {
        self.max_file_size = size;
        self
    }

    /// Add a file to context
    pub fn add_file(&mut self, path: &Path) -> Result<()> {
        let full_path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.cwd.join(path)
        };

        if !full_path.exists() {
            return Err(AgentError::Context(format!(
                "File not found: {}",
                full_path.display()
            )));
        }

        let metadata = std::fs::metadata(&full_path)?;
        if metadata.len() as usize > self.max_file_size {
            return Err(AgentError::Context(format!(
                "File too large: {} ({} bytes, max {})",
                full_path.display(),
                metadata.len(),
                self.max_file_size
            )));
        }

        let content = std::fs::read_to_string(&full_path)?;
        let language = Self::detect_language(&full_path);
        let relative_path = full_path
            .strip_prefix(&self.cwd)
            .unwrap_or(&full_path)
            .to_string_lossy()
            .to_string();

        // Remove if already exists
        self.files.retain(|f| f.path != relative_path);

        self.files.push(FileInContext {
            path: relative_path,
            content,
            language,
        });

        debug!("Added file to context: {}", full_path.display());
        Ok(())
    }

    /// Remove a file from context
    pub fn remove_file(&mut self, path: &Path) {
        let path_str = path.to_string_lossy();
        self.files.retain(|f| f.path != path_str.as_ref());
    }

    /// Clear all files from context
    pub fn clear(&mut self) {
        self.files.clear();
    }

    /// Get list of files in context
    pub fn list_files(&self) -> Vec<&str> {
        self.files.iter().map(|f| f.path.as_str()).collect()
    }

    /// Build context for a request
    pub fn build_context(&self, _query: &str) -> Context {
        // In the future, this could do smart file selection based on the query
        Context {
            files: self.files.clone(),
            cwd: Some(self.cwd.to_string_lossy().to_string()),
            git_branch: Self::get_git_branch(&self.cwd),
        }
    }

    /// Get current working directory
    pub fn cwd(&self) -> &Path {
        &self.cwd
    }

    /// Set current working directory
    pub fn set_cwd(&mut self, cwd: PathBuf) {
        self.cwd = cwd;
    }

    /// Detect programming language from file extension
    fn detect_language(path: &Path) -> Option<String> {
        let ext = path.extension()?.to_str()?;
        let lang = match ext.to_lowercase().as_str() {
            "rs" => "rust",
            "py" => "python",
            "js" => "javascript",
            "ts" => "typescript",
            "jsx" => "javascriptreact",
            "tsx" => "typescriptreact",
            "go" => "go",
            "java" => "java",
            "c" => "c",
            "cpp" | "cc" | "cxx" => "cpp",
            "h" | "hpp" => "cpp",
            "rb" => "ruby",
            "php" => "php",
            "swift" => "swift",
            "kt" | "kts" => "kotlin",
            "scala" => "scala",
            "sh" | "bash" => "shellscript",
            "zsh" => "shellscript",
            "fish" => "fish",
            "nu" => "nushell",
            "nix" => "nix",
            "json" => "json",
            "yaml" | "yml" => "yaml",
            "toml" => "toml",
            "xml" => "xml",
            "html" | "htm" => "html",
            "css" => "css",
            "scss" | "sass" => "scss",
            "less" => "less",
            "md" | "markdown" => "markdown",
            "sql" => "sql",
            "ex" | "exs" => "elixir",
            "erl" | "hrl" => "erlang",
            "zig" => "zig",
            "v" => "v",
            "nim" => "nim",
            "d" => "d",
            "lua" => "lua",
            "r" | "R" => "r",
            "jl" => "julia",
            "pl" | "pm" => "perl",
            "hs" => "haskell",
            "ml" | "mli" => "ocaml",
            "fs" | "fsi" | "fsx" => "fsharp",
            "clj" | "cljs" | "cljc" => "clojure",
            "lisp" | "lsp" => "lisp",
            "el" => "elisp",
            "vim" => "viml",
            "dockerfile" => "dockerfile",
            "tf" | "tfvars" => "terraform",
            "proto" => "protobuf",
            "graphql" | "gql" => "graphql",
            _ => return None,
        };
        Some(lang.to_string())
    }

    /// Get current git branch
    fn get_git_branch(cwd: &Path) -> Option<String> {
        let output = std::process::Command::new("git")
            .args(["rev-parse", "--abbrev-ref", "HEAD"])
            .current_dir(cwd)
            .output()
            .ok()?;

        if output.status.success() {
            Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
        } else {
            None
        }
    }
}

