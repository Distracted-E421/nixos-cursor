//! Workspace Tracking System
//!
//! Tracks workspaces across Cursor instances, including:
//! - Which versions have opened each workspace
//! - When workspaces were last accessed
//! - File change statistics (from git if available)
//! - Associated conversation history
//!
//! Storage: Uses SQLite for persistence (no external dependencies)

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Result as SqliteResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use ulid::Ulid;

// ═══════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════

/// A tracked workspace (project folder)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    /// Unique identifier for this workspace
    pub id: String,
    /// Absolute path to the workspace folder
    pub path: PathBuf,
    /// User-friendly name (defaults to folder name)
    pub name: String,
    /// Optional description
    pub description: Option<String>,
    /// When this workspace was first tracked
    pub created_at: DateTime<Utc>,
    /// Last time any Cursor instance opened this workspace
    pub last_opened_at: DateTime<Utc>,
    /// Total number of times this workspace has been opened
    pub open_count: u32,
    /// Associated Cursor versions that have opened this workspace
    pub versions: Vec<WorkspaceVersion>,
    /// Git statistics if available
    pub git_stats: Option<GitStats>,
    /// Pinned to top of list
    pub pinned: bool,
    /// Custom tags for organization
    pub tags: Vec<String>,
    /// Custom color (hex)
    pub color: Option<String>,
}

/// Record of a specific Cursor version opening a workspace
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceVersion {
    /// Cursor version (e.g., "2.1.34")
    pub version: String,
    /// When this version first opened the workspace
    pub first_opened: DateTime<Utc>,
    /// When this version last opened the workspace
    pub last_opened: DateTime<Utc>,
    /// Number of times this version has opened the workspace
    pub open_count: u32,
}

/// Git repository statistics for a workspace
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GitStats {
    /// Current branch
    pub branch: String,
    /// Number of commits in current branch
    pub commit_count: Option<u32>,
    /// Files changed but not committed
    pub uncommitted_changes: u32,
    /// Last commit date
    pub last_commit: Option<DateTime<Utc>>,
    /// Last commit message
    pub last_commit_message: Option<String>,
    /// Total lines of code (from `git ls-files`)
    pub total_files: Option<u32>,
    /// Stats updated at
    pub updated_at: DateTime<Utc>,
}

/// Workspace-Conversation mapping
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceConversation {
    pub workspace_id: String,
    pub conversation_id: String,
    /// Source: "global" or "workspace-<hash>"
    pub source: String,
    /// Cursor version this conversation came from
    pub cursor_version: Option<String>,
    /// Confidence score (0.0 - 1.0) of workspace association
    pub confidence: f32,
    /// When this association was detected
    pub detected_at: DateTime<Utc>,
}

/// Workspace launch request
#[derive(Debug, Clone)]
pub struct LaunchRequest {
    pub workspace_id: String,
    pub version: String,
    pub new_window: bool,
    /// Use Cursor's CLI (agent command) instead of GUI
    pub use_cli: bool,
    /// CLI mode: "normal", "ask", "plan"
    pub cli_mode: String,
}

// ═══════════════════════════════════════════════════════════════════════════
// WORKSPACE TRACKER
// ═══════════════════════════════════════════════════════════════════════════

/// Main workspace tracking system
pub struct WorkspaceTracker {
    /// SQLite connection for persistence
    conn: Connection,
    /// In-memory cache of workspaces
    workspaces: HashMap<String, Workspace>,
    /// Recent workspaces (ordered by last_opened_at)
    recent_ids: Vec<String>,
}

impl WorkspaceTracker {
    /// Initialize workspace tracker with database path
    pub fn new(db_path: impl AsRef<Path>) -> SqliteResult<Self> {
        let conn = Connection::open(db_path)?;
        let mut tracker = Self {
            conn,
            workspaces: HashMap::new(),
            recent_ids: Vec::new(),
        };
        tracker.init_schema()?;
        tracker.load_all()?;
        Ok(tracker)
    }

    /// Initialize in-memory database (for testing)
    pub fn new_memory() -> SqliteResult<Self> {
        let conn = Connection::open_in_memory()?;
        let mut tracker = Self {
            conn,
            workspaces: HashMap::new(),
            recent_ids: Vec::new(),
        };
        tracker.init_schema()?;
        Ok(tracker)
    }

    /// Initialize database schema
    fn init_schema(&self) -> SqliteResult<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL,
                last_opened_at TEXT NOT NULL,
                open_count INTEGER DEFAULT 0,
                pinned INTEGER DEFAULT 0,
                tags TEXT DEFAULT '[]',
                color TEXT,
                git_stats TEXT
            );
            
            CREATE TABLE IF NOT EXISTS workspace_versions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspace_id TEXT NOT NULL,
                version TEXT NOT NULL,
                first_opened TEXT NOT NULL,
                last_opened TEXT NOT NULL,
                open_count INTEGER DEFAULT 0,
                FOREIGN KEY (workspace_id) REFERENCES workspaces(id),
                UNIQUE(workspace_id, version)
            );
            
            CREATE TABLE IF NOT EXISTS workspace_conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspace_id TEXT NOT NULL,
                conversation_id TEXT NOT NULL,
                source TEXT NOT NULL,
                cursor_version TEXT,
                confidence REAL DEFAULT 1.0,
                detected_at TEXT NOT NULL,
                FOREIGN KEY (workspace_id) REFERENCES workspaces(id),
                UNIQUE(workspace_id, conversation_id, source)
            );
            
            CREATE INDEX IF NOT EXISTS idx_workspaces_path ON workspaces(path);
            CREATE INDEX IF NOT EXISTS idx_workspaces_last_opened ON workspaces(last_opened_at);
            CREATE INDEX IF NOT EXISTS idx_workspace_versions_workspace ON workspace_versions(workspace_id);
            CREATE INDEX IF NOT EXISTS idx_workspace_conversations_workspace ON workspace_conversations(workspace_id);
            CREATE INDEX IF NOT EXISTS idx_workspace_conversations_convo ON workspace_conversations(conversation_id);
            "#,
        )?;
        Ok(())
    }

    /// Load all workspaces from database
    fn load_all(&mut self) -> SqliteResult<()> {
        // Load workspaces
        let mut stmt = self.conn.prepare(
            "SELECT id, path, name, description, created_at, last_opened_at, 
                    open_count, pinned, tags, color, git_stats 
             FROM workspaces 
             ORDER BY last_opened_at DESC",
        )?;

        let workspace_iter = stmt.query_map([], |row| {
            let tags_json: String = row.get(8)?;
            let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
            
            let git_stats_json: Option<String> = row.get(10)?;
            let git_stats: Option<GitStats> = git_stats_json
                .and_then(|s| serde_json::from_str(&s).ok());

            Ok(Workspace {
                id: row.get(0)?,
                path: PathBuf::from(row.get::<_, String>(1)?),
                name: row.get(2)?,
                description: row.get(3)?,
                created_at: DateTime::parse_from_rfc3339(&row.get::<_, String>(4)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                last_opened_at: DateTime::parse_from_rfc3339(&row.get::<_, String>(5)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                open_count: row.get(6)?,
                pinned: row.get::<_, i32>(7)? != 0,
                tags,
                color: row.get(9)?,
                git_stats,
                versions: Vec::new(), // Loaded separately
            })
        })?;

        for workspace_result in workspace_iter {
            if let Ok(mut workspace) = workspace_result {
                // Load versions for this workspace
                workspace.versions = self.load_workspace_versions(&workspace.id)?;
                self.recent_ids.push(workspace.id.clone());
                self.workspaces.insert(workspace.id.clone(), workspace);
            }
        }

        Ok(())
    }

    /// Load versions associated with a workspace
    fn load_workspace_versions(&self, workspace_id: &str) -> SqliteResult<Vec<WorkspaceVersion>> {
        let mut stmt = self.conn.prepare(
            "SELECT version, first_opened, last_opened, open_count 
             FROM workspace_versions 
             WHERE workspace_id = ?
             ORDER BY last_opened DESC",
        )?;

        let version_iter = stmt.query_map([workspace_id], |row| {
            Ok(WorkspaceVersion {
                version: row.get(0)?,
                first_opened: DateTime::parse_from_rfc3339(&row.get::<_, String>(1)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                last_opened: DateTime::parse_from_rfc3339(&row.get::<_, String>(2)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
                open_count: row.get(3)?,
            })
        })?;

        version_iter.collect()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═══════════════════════════════════════════════════════════════════════

    /// Register or update a workspace
    pub fn register_workspace(&mut self, path: impl AsRef<Path>) -> SqliteResult<Workspace> {
        let path = path.as_ref().canonicalize().unwrap_or_else(|_| path.as_ref().to_path_buf());
        
        // Check if already registered
        if let Some(id) = self.find_workspace_by_path(&path) {
            // Update existing
            self.update_workspace_opened(&id)?;
            return Ok(self.workspaces.get(&id).cloned().unwrap());
        }

        // Create new workspace
        let id = Ulid::new().to_string();
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "Unknown".to_string());
        let now = Utc::now();

        let workspace = Workspace {
            id: id.clone(),
            path: path.clone(),
            name,
            description: None,
            created_at: now,
            last_opened_at: now,
            open_count: 1,
            versions: Vec::new(),
            git_stats: self.get_git_stats(&path),
            pinned: false,
            tags: Vec::new(),
            color: None,
        };

        // Insert into database
        self.conn.execute(
            "INSERT INTO workspaces (id, path, name, description, created_at, last_opened_at, open_count, pinned, tags, color, git_stats)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                workspace.id,
                workspace.path.to_string_lossy(),
                workspace.name,
                workspace.description,
                workspace.created_at.to_rfc3339(),
                workspace.last_opened_at.to_rfc3339(),
                workspace.open_count,
                workspace.pinned as i32,
                serde_json::to_string(&workspace.tags).unwrap_or_else(|_| "[]".to_string()),
                workspace.color,
                workspace.git_stats.as_ref().and_then(|g| serde_json::to_string(g).ok()),
            ],
        )?;

        // Update cache
        self.workspaces.insert(id.clone(), workspace.clone());
        self.recent_ids.insert(0, id);

        Ok(workspace)
    }

    /// Record that a specific version opened a workspace
    pub fn record_version_open(&mut self, workspace_id: &str, version: &str) -> SqliteResult<()> {
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        // Try to insert or update
        let rows_affected = self.conn.execute(
            "INSERT INTO workspace_versions (workspace_id, version, first_opened, last_opened, open_count)
             VALUES (?, ?, ?, ?, 1)
             ON CONFLICT(workspace_id, version) DO UPDATE SET
                last_opened = excluded.last_opened,
                open_count = open_count + 1",
            params![workspace_id, version, now_str, now_str],
        )?;

        // Update in-memory cache
        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            if let Some(ver) = workspace.versions.iter_mut().find(|v| v.version == version) {
                ver.last_opened = now;
                ver.open_count += 1;
            } else {
                workspace.versions.insert(
                    0,
                    WorkspaceVersion {
                        version: version.to_string(),
                        first_opened: now,
                        last_opened: now,
                        open_count: 1,
                    },
                );
            }
        }

        log::debug!(
            "Recorded version {} open for workspace {}, rows affected: {}",
            version,
            workspace_id,
            rows_affected
        );

        Ok(())
    }

    /// Link a conversation to a workspace
    pub fn link_conversation(
        &mut self,
        workspace_id: &str,
        conversation_id: &str,
        source: &str,
        cursor_version: Option<&str>,
        confidence: f32,
    ) -> SqliteResult<()> {
        let now = Utc::now().to_rfc3339();

        self.conn.execute(
            "INSERT INTO workspace_conversations (workspace_id, conversation_id, source, cursor_version, confidence, detected_at)
             VALUES (?, ?, ?, ?, ?, ?)
             ON CONFLICT(workspace_id, conversation_id, source) DO UPDATE SET
                confidence = MAX(confidence, excluded.confidence),
                detected_at = excluded.detected_at",
            params![workspace_id, conversation_id, source, cursor_version, confidence, now],
        )?;

        Ok(())
    }

    /// Get conversations linked to a workspace
    pub fn get_workspace_conversations(&self, workspace_id: &str) -> SqliteResult<Vec<WorkspaceConversation>> {
        let mut stmt = self.conn.prepare(
            "SELECT workspace_id, conversation_id, source, cursor_version, confidence, detected_at
             FROM workspace_conversations
             WHERE workspace_id = ?
             ORDER BY confidence DESC, detected_at DESC",
        )?;

        let conv_iter = stmt.query_map([workspace_id], |row| {
            Ok(WorkspaceConversation {
                workspace_id: row.get(0)?,
                conversation_id: row.get(1)?,
                source: row.get(2)?,
                cursor_version: row.get(3)?,
                confidence: row.get(4)?,
                detected_at: DateTime::parse_from_rfc3339(&row.get::<_, String>(5)?)
                    .map(|dt| dt.with_timezone(&Utc))
                    .unwrap_or_else(|_| Utc::now()),
            })
        })?;

        conv_iter.collect()
    }

    /// Get all workspaces, optionally filtered
    pub fn get_all(&self) -> Vec<&Workspace> {
        // Return in recent order, with pinned at top
        let mut result: Vec<&Workspace> = self.workspaces.values().collect();
        result.sort_by(|a, b| {
            // Pinned first, then by last_opened
            match (a.pinned, b.pinned) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => b.last_opened_at.cmp(&a.last_opened_at),
            }
        });
        result
    }

    /// Get recent workspaces (limit)
    pub fn get_recent(&self, limit: usize) -> Vec<&Workspace> {
        self.get_all().into_iter().take(limit).collect()
    }

    /// Find workspace by path
    pub fn find_workspace_by_path(&self, path: &Path) -> Option<String> {
        let canonical = path.canonicalize().ok()?;
        self.workspaces
            .values()
            .find(|w| w.path == canonical)
            .map(|w| w.id.clone())
    }

    /// Get workspace by ID
    pub fn get(&self, id: &str) -> Option<&Workspace> {
        self.workspaces.get(id)
    }

    /// Update workspace name
    pub fn set_name(&mut self, workspace_id: &str, name: &str) -> SqliteResult<()> {
        self.conn.execute(
            "UPDATE workspaces SET name = ? WHERE id = ?",
            params![name, workspace_id],
        )?;
        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            workspace.name = name.to_string();
        }
        Ok(())
    }

    /// Toggle pinned status
    pub fn toggle_pinned(&mut self, workspace_id: &str) -> SqliteResult<bool> {
        let new_pinned = if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            workspace.pinned = !workspace.pinned;
            workspace.pinned
        } else {
            return Ok(false);
        };

        self.conn.execute(
            "UPDATE workspaces SET pinned = ? WHERE id = ?",
            params![new_pinned as i32, workspace_id],
        )?;

        Ok(new_pinned)
    }

    /// Set custom color
    pub fn set_color(&mut self, workspace_id: &str, color: Option<&str>) -> SqliteResult<()> {
        self.conn.execute(
            "UPDATE workspaces SET color = ? WHERE id = ?",
            params![color, workspace_id],
        )?;
        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            workspace.color = color.map(|s| s.to_string());
        }
        Ok(())
    }

    /// Add tag to workspace
    pub fn add_tag(&mut self, workspace_id: &str, tag: &str) -> SqliteResult<()> {
        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            if !workspace.tags.contains(&tag.to_string()) {
                workspace.tags.push(tag.to_string());
                let tags_json = serde_json::to_string(&workspace.tags).unwrap_or_else(|_| "[]".to_string());
                self.conn.execute(
                    "UPDATE workspaces SET tags = ? WHERE id = ?",
                    params![tags_json, workspace_id],
                )?;
            }
        }
        Ok(())
    }

    /// Remove tag from workspace
    pub fn remove_tag(&mut self, workspace_id: &str, tag: &str) -> SqliteResult<()> {
        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            workspace.tags.retain(|t| t != tag);
            let tags_json = serde_json::to_string(&workspace.tags).unwrap_or_else(|_| "[]".to_string());
            self.conn.execute(
                "UPDATE workspaces SET tags = ? WHERE id = ?",
                params![tags_json, workspace_id],
            )?;
        }
        Ok(())
    }

    /// Delete a workspace (and its associations)
    pub fn delete(&mut self, workspace_id: &str) -> SqliteResult<()> {
        self.conn.execute(
            "DELETE FROM workspace_conversations WHERE workspace_id = ?",
            [workspace_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspace_versions WHERE workspace_id = ?",
            [workspace_id],
        )?;
        self.conn.execute(
            "DELETE FROM workspaces WHERE id = ?",
            [workspace_id],
        )?;
        
        self.workspaces.remove(workspace_id);
        self.recent_ids.retain(|id| id != workspace_id);
        
        Ok(())
    }

    /// Refresh git stats for a workspace
    pub fn refresh_git_stats(&mut self, workspace_id: &str) -> SqliteResult<()> {
        // Get the path first to avoid borrow conflicts
        let path = self.workspaces.get(workspace_id).map(|w| w.path.clone());
        
        if let Some(path) = path {
            let git_stats = self.get_git_stats(&path);
            let git_stats_json = git_stats.as_ref().and_then(|g| serde_json::to_string(g).ok());
            
            self.conn.execute(
                "UPDATE workspaces SET git_stats = ? WHERE id = ?",
                params![git_stats_json, workspace_id],
            )?;
            
            if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
                workspace.git_stats = git_stats;
            }
        }
        Ok(())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// Update workspace last opened time
    fn update_workspace_opened(&mut self, workspace_id: &str) -> SqliteResult<()> {
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        self.conn.execute(
            "UPDATE workspaces SET last_opened_at = ?, open_count = open_count + 1 WHERE id = ?",
            params![now_str, workspace_id],
        )?;

        if let Some(workspace) = self.workspaces.get_mut(workspace_id) {
            workspace.last_opened_at = now;
            workspace.open_count += 1;
        }

        // Move to front of recent list
        self.recent_ids.retain(|id| id != workspace_id);
        self.recent_ids.insert(0, workspace_id.to_string());

        Ok(())
    }

    /// Get git stats for a path (if it's a git repo)
    fn get_git_stats(&self, path: &Path) -> Option<GitStats> {
        if !path.join(".git").exists() {
            return None;
        }

        let git_dir = path.to_string_lossy();
        
        // Get current branch
        let branch = std::process::Command::new("git")
            .args(["-C", &git_dir, "rev-parse", "--abbrev-ref", "HEAD"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        // Get uncommitted changes count
        let uncommitted = std::process::Command::new("git")
            .args(["-C", &git_dir, "status", "--porcelain"])
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).lines().count() as u32)
            .unwrap_or(0);

        // Get last commit info
        let last_commit_output = std::process::Command::new("git")
            .args(["-C", &git_dir, "log", "-1", "--format=%H|%cI|%s"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok());

        let (last_commit, last_commit_message) = if let Some(output) = last_commit_output {
            let parts: Vec<&str> = output.trim().split('|').collect();
            let commit_date = parts.get(1).and_then(|s| {
                DateTime::parse_from_rfc3339(s)
                    .ok()
                    .map(|dt| dt.with_timezone(&Utc))
            });
            let message = parts.get(2).map(|s| s.to_string());
            (commit_date, message)
        } else {
            (None, None)
        };

        // Get total files count
        let total_files = std::process::Command::new("git")
            .args(["-C", &git_dir, "ls-files"])
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).lines().count() as u32);

        // Get commit count
        let commit_count = std::process::Command::new("git")
            .args(["-C", &git_dir, "rev-list", "--count", "HEAD"])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .and_then(|s| s.trim().parse().ok());

        Some(GitStats {
            branch,
            commit_count,
            uncommitted_changes: uncommitted,
            last_commit,
            last_commit_message,
            total_files,
            updated_at: Utc::now(),
        })
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CURSOR CLI INTEGRATION
// ═══════════════════════════════════════════════════════════════════════════

/// Cursor CLI launcher (uses the new `agent` command)
pub struct CursorCli {
    /// Path to the cursor/agent binary
    pub agent_path: Option<PathBuf>,
    /// API key for headless operations
    pub api_key: Option<String>,
}

impl CursorCli {
    pub fn new() -> Self {
        // Try to find the agent binary
        let agent_path = which::which("agent")
            .or_else(|_| which::which("cursor"))
            .ok();
        
        let api_key = std::env::var("CURSOR_API_KEY").ok();
        
        Self { agent_path, api_key }
    }

    /// Check if CLI is available
    pub fn is_available(&self) -> bool {
        self.agent_path.is_some()
    }

    /// Launch Cursor GUI with a workspace
    pub fn launch_gui(&self, workspace: &Path, version: Option<&str>, new_window: bool) -> Result<(), String> {
        // Try version-specific AppImage first
        if let Some(version) = version {
            if let Some(home) = dirs::home_dir() {
                let appimage_path = home
                    .join(format!(".cursor-studio/versions/cursor-{}", version))
                    .join(format!("Cursor-{}.AppImage", version));
                
                if appimage_path.exists() {
                    let mut cmd = std::process::Command::new(&appimage_path);
                    cmd.arg(workspace);
                    if new_window {
                        cmd.arg("--new-window");
                    }
                    cmd.spawn()
                        .map_err(|e| format!("Failed to launch Cursor {}: {}", version, e))?;
                    return Ok(());
                }
            }
        }

        // Fall back to system cursor
        let cursor_path = if let Some(path) = self.agent_path.as_ref() {
            path.clone()
        } else {
            which::which("cursor")
                .map_err(|_| "Cursor not found in PATH".to_string())?
        };

        let mut cmd = std::process::Command::new(&cursor_path);
        cmd.arg(workspace);
        if new_window {
            cmd.arg("--new-window");
        }
        cmd.spawn()
            .map_err(|e| format!("Failed to launch Cursor: {}", e))?;
        
        Ok(())
    }

    /// Launch Cursor CLI (agent) with a workspace
    pub fn launch_cli(
        &self,
        workspace: &Path,
        mode: &str, // "normal", "ask", "plan"
        prompt: Option<&str>,
    ) -> Result<std::process::Child, String> {
        let agent_path = self.agent_path.as_ref()
            .ok_or_else(|| "Cursor agent CLI not found".to_string())?;

        let mut cmd = std::process::Command::new(agent_path);
        cmd.current_dir(workspace);
        
        // Set mode
        match mode {
            "ask" => { cmd.args(["--mode", "ask"]); }
            "plan" => { cmd.args(["--mode", "plan"]); }
            _ => {} // normal mode is default
        }

        // Add prompt if provided
        if let Some(prompt) = prompt {
            cmd.arg(prompt);
        }

        // Pass API key if available for headless
        if let Some(api_key) = &self.api_key {
            cmd.env("CURSOR_API_KEY", api_key);
        }

        cmd.spawn()
            .map_err(|e| format!("Failed to launch Cursor CLI: {}", e))
    }

    /// Run headless agent command and return output
    pub fn run_headless(
        &self,
        workspace: &Path,
        prompt: &str,
        force: bool,
        output_format: &str, // "text", "json", "stream-json"
    ) -> Result<String, String> {
        let agent_path = self.agent_path.as_ref()
            .ok_or_else(|| "Cursor agent CLI not found".to_string())?;

        let mut cmd = std::process::Command::new(agent_path);
        cmd.current_dir(workspace);
        cmd.arg("-p"); // print mode
        
        if force {
            cmd.arg("--force");
        }
        
        cmd.args(["--output-format", output_format]);
        cmd.arg(prompt);

        // Pass API key
        if let Some(api_key) = &self.api_key {
            cmd.env("CURSOR_API_KEY", api_key);
        }

        let output = cmd.output()
            .map_err(|e| format!("Failed to run headless agent: {}", e))?;

        if output.status.success() {
            String::from_utf8(output.stdout)
                .map_err(|e| format!("Invalid UTF-8 output: {}", e))
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }
}

impl Default for CursorCli {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_workspace_tracker_memory() {
        let mut tracker = WorkspaceTracker::new_memory().unwrap();
        
        // Register a workspace
        let ws = tracker.register_workspace("/tmp/test-workspace").unwrap();
        assert_eq!(ws.name, "test-workspace");
        assert_eq!(ws.open_count, 1);
        
        // Record version open
        tracker.record_version_open(&ws.id, "2.1.34").unwrap();
        let ws = tracker.get(&ws.id).unwrap();
        assert_eq!(ws.versions.len(), 1);
        assert_eq!(ws.versions[0].version, "2.1.34");
        
        // Link conversation
        tracker.link_conversation(&ws.id, "conv-123", "global", Some("2.1.34"), 0.9).unwrap();
        let convs = tracker.get_workspace_conversations(&ws.id).unwrap();
        assert_eq!(convs.len(), 1);
        assert_eq!(convs[0].conversation_id, "conv-123");
    }

    #[test]
    fn test_workspace_pinning() {
        let mut tracker = WorkspaceTracker::new_memory().unwrap();
        let ws = tracker.register_workspace("/tmp/test-ws").unwrap();
        
        assert!(!ws.pinned);
        
        let pinned = tracker.toggle_pinned(&ws.id).unwrap();
        assert!(pinned);
        
        let ws = tracker.get(&ws.id).unwrap();
        assert!(ws.pinned);
    }
}

