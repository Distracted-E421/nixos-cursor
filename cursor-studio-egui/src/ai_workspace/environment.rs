//! Environment awareness for multi-machine, multi-context development

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

/// Current environment state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentState {
    pub hostname: String,
    pub os: OsInfo,
    pub user: String,
    pub shell: String,
    pub cwd: PathBuf,
    pub git_state: Option<GitState>,
    pub in_nix_shell: bool,
    pub detected_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OsInfo {
    pub name: String,
    pub version: String,
    pub kernel: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitState {
    pub branch: String,
    pub uncommitted: usize,
    pub untracked: usize,
    pub ahead: usize,
    pub behind: usize,
    pub repo_root: PathBuf,
}

impl EnvironmentState {
    /// Detect current environment
    pub fn detect() -> Self {
        Self {
            hostname: detect_hostname(),
            os: detect_os(),
            user: std::env::var("USER").unwrap_or_else(|_| "unknown".into()),
            shell: detect_shell(),
            cwd: std::env::current_dir().unwrap_or_default(),
            git_state: detect_git_state(),
            in_nix_shell: std::env::var("IN_NIX_SHELL").is_ok(),
            detected_at: chrono::Utc::now().to_rfc3339(),
        }
    }
    
    /// Check if environment differs significantly from another
    pub fn differs_from(&self, other: &EnvironmentState) -> bool {
        self.hostname != other.hostname ||
        self.cwd != other.cwd ||
        self.in_nix_shell != other.in_nix_shell ||
        self.git_branch() != other.git_branch()
    }
    
    /// Get git branch if in repo
    pub fn git_branch(&self) -> Option<&str> {
        self.git_state.as_ref().map(|g| g.branch.as_str())
    }
    
    /// Generate compact delta description
    pub fn delta_description(&self, previous: &EnvironmentState) -> String {
        let mut changes = Vec::new();
        
        if self.hostname != previous.hostname {
            changes.push(format!("🖥️ Machine: {} → {}", previous.hostname, self.hostname));
        }
        if self.cwd != previous.cwd {
            changes.push(format!("📁 CWD: {}", self.cwd.display()));
        }
        if self.git_branch() != previous.git_branch() {
            changes.push(format!("🌿 Branch: {:?} → {:?}", previous.git_branch(), self.git_branch()));
        }
        if self.in_nix_shell != previous.in_nix_shell {
            let status = if self.in_nix_shell { "entered" } else { "exited" };
            changes.push(format!("❄️ Nix shell: {}", status));
        }
        
        if changes.is_empty() {
            "No significant changes".into()
        } else {
            changes.join("\n")
        }
    }
    
    /// Generate minimal context injection (~50-100 tokens)
    pub fn to_injection(&self) -> String {
        let mut parts = Vec::new();
        
        parts.push(format!("Host: {}", self.hostname));
        parts.push(format!("OS: {} {}", self.os.name, self.os.version));
        parts.push(format!("CWD: {}", self.cwd.display()));
        
        if let Some(ref git) = self.git_state {
            parts.push(format!("Git: {} (+{}/-{})", git.branch, git.uncommitted, git.untracked));
        }
        
        if self.in_nix_shell {
            parts.push("In Nix shell".into());
        }
        
        format!("[Environment: {}]", parts.join(" | "))
    }
}

fn detect_hostname() -> String {
    // Try hostname command
    Command::new("hostname")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| {
            // Fallback to /etc/hostname
            std::fs::read_to_string("/etc/hostname")
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|_| "unknown".into())
        })
}

fn detect_os() -> OsInfo {
    // Try /etc/os-release for NixOS and other Linux
    if let Ok(content) = std::fs::read_to_string("/etc/os-release") {
        let mut name = "Linux".to_string();
        let mut version = "unknown".to_string();
        
        for line in content.lines() {
            if line.starts_with("NAME=") {
                name = line[5..].trim_matches('"').to_string();
            }
            if line.starts_with("VERSION=") || line.starts_with("VERSION_ID=") {
                version = line.split('=').nth(1)
                    .map(|s| s.trim_matches('"').to_string())
                    .unwrap_or_default();
            }
        }
        
        let kernel = Command::new("uname")
            .arg("-r")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".into());
        
        OsInfo { name, version, kernel }
    } else {
        OsInfo {
            name: std::env::consts::OS.to_string(),
            version: "unknown".into(),
            kernel: "unknown".into(),
        }
    }
}

fn detect_shell() -> String {
    std::env::var("SHELL")
        .map(|s| PathBuf::from(s)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string())
        .unwrap_or_else(|_| "unknown".into())
}

fn detect_git_state() -> Option<GitState> {
    // Check if in git repo
    let output = Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .output()
        .ok()?;
    
    if !output.status.success() {
        return None;
    }
    
    // Get branch
    let branch = Command::new("git")
        .args(["branch", "--show-current"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "HEAD".into());
    
    // Get status counts
    let status = Command::new("git")
        .args(["status", "--porcelain"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();
    
    let uncommitted = status.lines().filter(|l| !l.starts_with("??")).count();
    let untracked = status.lines().filter(|l| l.starts_with("??")).count();
    
    // Get ahead/behind (if tracking branch)
    let (ahead, behind) = Command::new("git")
        .args(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| {
            let parts: Vec<&str> = s.trim().split('\t').collect();
            if parts.len() == 2 {
                Some((
                    parts[0].parse().unwrap_or(0),
                    parts[1].parse().unwrap_or(0),
                ))
            } else {
                None
            }
        })
        .unwrap_or((0, 0));
    
    // Get repo root
    let repo_root = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| PathBuf::from(s.trim()))
        .unwrap_or_default();
    
    Some(GitState {
        branch,
        uncommitted,
        untracked,
        ahead,
        behind,
        repo_root,
    })
}

/// Machine alias registry
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AliasRegistry {
    pub machines: HashMap<String, MachineAliases>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MachineAliases {
    pub hostname: String,
    pub os: String,
    pub ssh: Option<String>,  // SSH command to reach this machine
    pub aliases: HashMap<String, String>,
    pub notes: Vec<String>,
}

impl AliasRegistry {
    /// Load from file
    pub fn load(path: &PathBuf) -> Self {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }
    
    /// Save to file
    pub fn save(&self, path: &PathBuf) -> std::io::Result<()> {
        let json = serde_json::to_string_pretty(self)?;
        std::fs::write(path, json)
    }
    
    /// Get aliases for a specific machine
    pub fn for_machine(&self, hostname: &str) -> Option<&MachineAliases> {
        self.machines.get(hostname)
    }
    
    /// Get relevant aliases as injection text
    pub fn to_injection(&self, hostname: &str) -> String {
        if let Some(machine) = self.machines.get(hostname) {
            let aliases: Vec<String> = machine.aliases.iter()
                .map(|(name, cmd)| format!("  {}: {}", name, cmd))
                .collect();
            
            if aliases.is_empty() {
                format!("[Machine: {} - No custom aliases]", hostname)
            } else {
                format!("[Machine: {} - Aliases:\n{}]", hostname, aliases.join("\n"))
            }
        } else {
            format!("[Machine: {} - Not in registry]", hostname)
        }
    }
}

/// Create default alias registry for known machines
pub fn create_default_registry() -> AliasRegistry {
    let mut registry = AliasRegistry::default();
    
    // Obsidian
    let mut obsidian = MachineAliases {
        hostname: "Obsidian".into(),
        os: "NixOS 25.11".into(),
        ssh: None,
        aliases: HashMap::new(),
        notes: vec![
            "Primary development machine".into(),
            "Dual GPU: Arc A770 + RTX 2080".into(),
            "Main git operations happen here".into(),
        ],
    };
    obsidian.aliases.insert("cursor-studio-dev".into(), 
        "LD_LIBRARY_PATH=... ~/nixos-cursor/cursor-studio-egui/target/release/cursor-studio".into());
    obsidian.aliases.insert("build-cursor-studio".into(),
        "cd ~/nixos-cursor/cursor-studio-egui && cargo build --release".into());
    obsidian.aliases.insert("rebuild-cursor-dev".into(),
        "cd ~/homelab/nixos && sudo nixos-rebuild switch --impure --flake .#Obsidian --override-input nixos-cursor path:/home/e421/nixos-cursor 2>&1 | nom".into());
    registry.machines.insert("Obsidian".into(), obsidian);
    
    // neon-laptop
    let mut neon = MachineAliases {
        hostname: "neon-laptop".into(),
        os: "NixOS 24.05".into(),
        ssh: Some("ssh e421@neon-laptop".into()),
        aliases: HashMap::new(),
        notes: vec![
            "ThinkPad T14 - Mobile development".into(),
            "Streaming machine".into(),
        ],
    };
    neon.aliases.insert("streaming-mode".into(), "~/scripts/streaming-mode.nu".into());
    neon.aliases.insert("rebuild".into(), "sudo nixos-rebuild switch --flake ~/homelab/nixos#neon-laptop".into());
    registry.machines.insert("neon-laptop".into(), neon);
    
    // framework
    let mut framework = MachineAliases {
        hostname: "framework".into(),
        os: "NixOS 24.05".into(),
        ssh: Some("ssh e421@framework".into()),
        aliases: HashMap::new(),
        notes: vec![
            "Framework Laptop 13".into(),
            "Often offline".into(),
        ],
    };
    registry.machines.insert("framework".into(), framework);
    
    // pi-server
    let mut pi = MachineAliases {
        hostname: "pi-server".into(),
        os: "NixOS".into(),
        ssh: Some("ssh e421@pi-server".into()),
        aliases: HashMap::new(),
        notes: vec![
            "Always-on services".into(),
            "ARM64 infrastructure".into(),
        ],
    };
    registry.machines.insert("pi-server".into(), pi);
    
    // Evie-Desktop (note: different user!)
    let mut evie = MachineAliases {
        hostname: "Evie-Desktop".into(),
        os: "Windows/WSL".into(),
        ssh: Some("ssh evie@Evie-Desktop".into()),  // Different user!
        aliases: HashMap::new(),
        notes: vec![
            "⚠️ USER IS 'evie' NOT 'e421'".into(),
            "Windows with WSL".into(),
        ],
    };
    registry.machines.insert("Evie-Desktop".into(), evie);
    
    registry
}

/// Environment watcher for detecting changes
pub struct EnvironmentWatcher {
    last_state: EnvironmentState,
    registry: AliasRegistry,
}

impl EnvironmentWatcher {
    pub fn new(registry: AliasRegistry) -> Self {
        Self {
            last_state: EnvironmentState::detect(),
            registry,
        }
    }
    
    /// Check for environment changes
    pub fn check(&mut self) -> Option<EnvironmentDelta> {
        let current = EnvironmentState::detect();
        
        if current.differs_from(&self.last_state) {
            let delta = EnvironmentDelta {
                previous: self.last_state.clone(),
                current: current.clone(),
                description: current.delta_description(&self.last_state),
                aliases: self.registry.for_machine(&current.hostname).cloned(),
            };
            self.last_state = current;
            Some(delta)
        } else {
            None
        }
    }
    
    /// Get current state
    pub fn current(&self) -> &EnvironmentState {
        &self.last_state
    }
    
    /// Force refresh
    pub fn refresh(&mut self) {
        self.last_state = EnvironmentState::detect();
    }
}

/// Delta between two environment states
#[derive(Debug, Clone)]
pub struct EnvironmentDelta {
    pub previous: EnvironmentState,
    pub current: EnvironmentState,
    pub description: String,
    pub aliases: Option<MachineAliases>,
}

impl EnvironmentDelta {
    /// Generate injection text for AI context
    pub fn to_injection(&self) -> String {
        let mut parts = vec![
            "---".into(),
            "⚡ Environment Changed:".into(),
            self.description.clone(),
            self.current.to_injection(),
        ];
        
        if let Some(ref aliases) = self.aliases {
            if !aliases.notes.is_empty() {
                parts.push(format!("Notes: {}", aliases.notes.join("; ")));
            }
        }
        
        parts.push("---".into());
        parts.join("\n")
    }
}

