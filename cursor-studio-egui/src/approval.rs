//! Approval system for confirming operations
//!
//! Provides both GUI and terminal-based approval mechanisms for operations
//! like downloads, imports, and other potentially destructive actions.

use std::io::{self, Write};
use std::sync::mpsc;

/// Types of operations that require approval
#[derive(Debug, Clone)]
pub enum ApprovalOperation {
    /// Download a Cursor version
    Download {
        version: String,
        size_estimate: Option<u64>,
    },
    /// Install a version
    Install { version: String, path: String },
    /// Clear and reimport all data
    ClearAndReimport { conversation_count: usize },
    /// Delete a version
    DeleteVersion { version: String },
    /// Export data
    Export { format: String, path: String },
    /// Custom operation
    Custom { title: String, description: String },
}

impl ApprovalOperation {
    /// Get a human-readable title for the operation
    pub fn title(&self) -> String {
        match self {
            ApprovalOperation::Download { version, .. } => {
                format!("Download Cursor v{}", version)
            }
            ApprovalOperation::Install { version, .. } => {
                format!("Install Cursor v{}", version)
            }
            ApprovalOperation::ClearAndReimport { .. } => "Clear and Reimport Data".to_string(),
            ApprovalOperation::DeleteVersion { version } => {
                format!("Delete Cursor v{}", version)
            }
            ApprovalOperation::Export { format, .. } => {
                format!("Export to {}", format)
            }
            ApprovalOperation::Custom { title, .. } => title.clone(),
        }
    }

    /// Get a detailed description of the operation
    pub fn description(&self) -> String {
        match self {
            ApprovalOperation::Download {
                version,
                size_estimate,
            } => {
                let size_str = size_estimate
                    .map(|s| format!(" (~{} MB)", s / 1024 / 1024))
                    .unwrap_or_default();
                format!(
                    "Download Cursor IDE version {}{}.\nThis will be saved to the cache directory.",
                    version, size_str
                )
            }
            ApprovalOperation::Install { version, path } => {
                format!(
                    "Install Cursor IDE version {} from:\n  {}\n\nThe AppImage will be made executable and registered.",
                    version, path
                )
            }
            ApprovalOperation::ClearAndReimport { conversation_count } => {
                format!(
                    "Clear {} conversations from the database and reimport from Cursor.\n\n⚠️ Bookmarks will be preserved but re-matched by sequence number.",
                    conversation_count
                )
            }
            ApprovalOperation::DeleteVersion { version } => {
                format!(
                    "Delete Cursor IDE version {} and all associated data.\n\n⚠️ This cannot be undone!",
                    version
                )
            }
            ApprovalOperation::Export { format, path } => {
                format!("Export data to {} format at:\n  {}", format, path)
            }
            ApprovalOperation::Custom { description, .. } => description.clone(),
        }
    }

    /// Check if this operation is potentially destructive
    pub fn is_destructive(&self) -> bool {
        matches!(
            self,
            ApprovalOperation::ClearAndReimport { .. } | ApprovalOperation::DeleteVersion { .. }
        )
    }
}

/// Result of an approval request
#[derive(Debug, Clone, PartialEq)]
pub enum ApprovalResult {
    Approved,
    Denied,
    Cancelled,
    Timeout,
}

/// Approval mode - how to request user approval
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ApprovalMode {
    /// Always require terminal confirmation (stdin)
    Terminal,
    /// Use GUI dialogs (double-click confirmation)
    Gui,
    /// Use both - GUI with terminal fallback
    #[default]
    Both,
    /// Auto-approve all operations (dangerous!)
    AutoApprove,
}

/// Pending approval state for GUI mode
#[derive(Debug, Clone)]
pub struct PendingApproval {
    pub operation: ApprovalOperation,
    pub first_click_time: std::time::Instant,
    pub needs_confirmation: bool,
}

impl PendingApproval {
    pub fn new(operation: ApprovalOperation) -> Self {
        Self {
            operation,
            first_click_time: std::time::Instant::now(),
            needs_confirmation: true,
        }
    }

    /// Check if the confirmation window has expired (>3 seconds)
    pub fn is_expired(&self) -> bool {
        self.first_click_time.elapsed() > std::time::Duration::from_secs(3)
    }
}

/// Terminal approval handler
pub struct TerminalApproval {
    /// Whether terminal is available
    terminal_available: bool,
}

impl TerminalApproval {
    pub fn new() -> Self {
        // Check if we have a terminal
        let terminal_available = atty::is(atty::Stream::Stdin);
        Self { terminal_available }
    }

    /// Request approval via terminal
    pub fn request(&self, operation: &ApprovalOperation) -> ApprovalResult {
        if !self.terminal_available {
            log::warn!("Terminal not available for approval, returning Denied");
            return ApprovalResult::Denied;
        }

        // Print operation details
        println!();
        println!("╔══════════════════════════════════════════════════════════════╗");
        println!("║  APPROVAL REQUIRED                                           ║");
        println!("╚══════════════════════════════════════════════════════════════╝");
        println!();
        println!("  {}", operation.title());
        println!();
        
        // Print description with indentation
        for line in operation.description().lines() {
            println!("  {}", line);
        }
        println!();

        if operation.is_destructive() {
            println!("  ⚠️  WARNING: This operation is DESTRUCTIVE");
            println!();
        }

        print!("  Do you want to proceed? [y/N]: ");
        io::stdout().flush().expect("Failed to flush stdout");

        let mut input = String::new();
        match io::stdin().read_line(&mut input) {
            Ok(_) => {
                let response = input.trim().to_lowercase();
                if response == "y" || response == "yes" {
                    println!("  ✓ Approved");
                    println!();
                    ApprovalResult::Approved
                } else {
                    println!("  ✗ Denied");
                    println!();
                    ApprovalResult::Denied
                }
            }
            Err(_) => {
                println!("  ✗ Input error - Cancelled");
                println!();
                ApprovalResult::Cancelled
            }
        }
    }

    /// Request approval with timeout
    pub fn request_with_timeout(
        &self,
        operation: &ApprovalOperation,
        timeout_secs: u64,
    ) -> ApprovalResult {
        if !self.terminal_available {
            return ApprovalResult::Denied;
        }

        // Use a channel for timeout
        let (tx, rx) = mpsc::channel();
        let op_clone = operation.clone();

        std::thread::spawn(move || {
            let approval = TerminalApproval::new();
            let result = approval.request(&op_clone);
            let _ = tx.send(result);
        });

        match rx.recv_timeout(std::time::Duration::from_secs(timeout_secs)) {
            Ok(result) => result,
            Err(_) => {
                println!("  ⏰ Timeout - operation cancelled");
                println!();
                ApprovalResult::Timeout
            }
        }
    }

    /// Check if terminal is available
    pub fn is_available(&self) -> bool {
        self.terminal_available
    }
}

impl Default for TerminalApproval {
    fn default() -> Self {
        Self::new()
    }
}

/// Central approval manager
pub struct ApprovalManager {
    mode: ApprovalMode,
    terminal: TerminalApproval,
    /// For GUI mode: pending approvals keyed by operation type
    pending: std::collections::HashMap<String, PendingApproval>,
}

impl ApprovalManager {
    pub fn new(mode: ApprovalMode) -> Self {
        Self {
            mode,
            terminal: TerminalApproval::new(),
            pending: std::collections::HashMap::new(),
        }
    }

    /// Set the approval mode
    pub fn set_mode(&mut self, mode: ApprovalMode) {
        self.mode = mode;
    }

    /// Get current approval mode
    pub fn mode(&self) -> ApprovalMode {
        self.mode
    }

    /// Check if terminal approval is available
    pub fn has_terminal(&self) -> bool {
        self.terminal.is_available()
    }

    /// Request approval for an operation
    /// 
    /// In GUI mode, returns whether this is the first or second click:
    /// - First click: Returns Denied with pending approval registered
    /// - Second click (within timeout): Returns Approved
    /// 
    /// In Terminal mode: Blocks and prompts in terminal
    pub fn request(&mut self, operation: ApprovalOperation) -> ApprovalResult {
        match self.mode {
            ApprovalMode::AutoApprove => ApprovalResult::Approved,
            ApprovalMode::Terminal => self.terminal.request(&operation),
            ApprovalMode::Gui => self.request_gui(operation),
            ApprovalMode::Both => {
                // Try GUI first, fall back to terminal if needed
                let result = self.request_gui(operation.clone());
                if result == ApprovalResult::Denied && self.terminal.is_available() {
                    self.terminal.request(&operation)
                } else {
                    result
                }
            }
        }
    }

    /// GUI-style approval (double-click pattern)
    fn request_gui(&mut self, operation: ApprovalOperation) -> ApprovalResult {
        let key = operation.title();

        // Check if we have a pending approval for this operation
        if let Some(pending) = self.pending.get(&key) {
            if !pending.is_expired() {
                // Second click within timeout - approve!
                self.pending.remove(&key);
                return ApprovalResult::Approved;
            }
            // Expired - remove and start fresh
            self.pending.remove(&key);
        }

        // First click - register as pending
        self.pending.insert(key, PendingApproval::new(operation));
        ApprovalResult::Denied
    }

    /// Get pending approval status for UI display
    pub fn get_pending(&self, operation_title: &str) -> Option<&PendingApproval> {
        self.pending.get(operation_title)
    }

    /// Clear all pending approvals
    pub fn clear_pending(&mut self) {
        self.pending.clear();
    }

    /// Get message to show for pending approval
    pub fn get_pending_message(&self, operation_title: &str) -> Option<String> {
        self.pending.get(operation_title).map(|p| {
            let remaining = 3.0 - p.first_click_time.elapsed().as_secs_f32();
            if remaining > 0.0 {
                format!(
                    "⚠️ Click again within {:.0}s to confirm: {}",
                    remaining,
                    p.operation.title()
                )
            } else {
                "".to_string()
            }
        })
    }

    /// Clean up expired pending approvals
    pub fn cleanup_expired(&mut self) {
        self.pending.retain(|_, v| !v.is_expired());
    }
}

impl Default for ApprovalManager {
    fn default() -> Self {
        Self::new(ApprovalMode::default())
    }
}

/// CLI interface for approval prompts
pub fn prompt_yes_no(message: &str, default: bool) -> bool {
    let default_hint = if default { "[Y/n]" } else { "[y/N]" };
    print!("{} {}: ", message, default_hint);
    io::stdout().flush().expect("Failed to flush stdout");

    let mut input = String::new();
    match io::stdin().read_line(&mut input) {
        Ok(_) => {
            let response = input.trim().to_lowercase();
            if response.is_empty() {
                default
            } else {
                response == "y" || response == "yes"
            }
        }
        Err(_) => default,
    }
}

/// Progress indicator for terminal
pub struct TerminalProgress {
    total: u64,
    current: u64,
    last_printed_percent: u8,
}

impl TerminalProgress {
    pub fn new(total: u64) -> Self {
        Self {
            total,
            current: 0,
            last_printed_percent: 0,
        }
    }

    pub fn update(&mut self, current: u64) {
        self.current = current;
        let percent = if self.total > 0 {
            ((self.current as f64 / self.total as f64) * 100.0) as u8
        } else {
            0
        };

        if percent != self.last_printed_percent {
            self.last_printed_percent = percent;
            
            // Print progress bar
            let filled = (percent as usize) / 2; // 50 chars wide
            let empty = 50 - filled;
            print!(
                "\r  [{}{}] {}%",
                "█".repeat(filled),
                "░".repeat(empty),
                percent
            );
            io::stdout().flush().expect("Failed to flush stdout");
        }
    }

    pub fn finish(&self) {
        println!(" Done!");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_approval_operation_title() {
        let op = ApprovalOperation::Download {
            version: "2.1.34".into(),
            size_estimate: Some(150_000_000),
        };
        assert!(op.title().contains("2.1.34"));
    }

    #[test]
    fn test_destructive_detection() {
        assert!(
            ApprovalOperation::ClearAndReimport {
                conversation_count: 10
            }
            .is_destructive()
        );
        assert!(!ApprovalOperation::Download {
            version: "1.0".into(),
            size_estimate: None
        }
        .is_destructive());
    }

    #[test]
    fn test_pending_expiry() {
        let pending = PendingApproval::new(ApprovalOperation::Download {
            version: "1.0".into(),
            size_estimate: None,
        });
        assert!(!pending.is_expired());
        // Can't easily test expiry without sleeping
    }
}
