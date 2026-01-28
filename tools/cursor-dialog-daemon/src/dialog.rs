//! Dialog Types and Management
//!
//! Defines the core dialog structures and handles rendering via egui.

use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};
use tokio::sync::oneshot;

use crate::dbus_interface::{ChoiceOption, FileFilter, FilePickerMode};

/// Content format for dialog prompts
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ContentFormat {
    /// Plain text (default, backward compatible)
    #[default]
    Plain,
    /// CommonMark markdown
    Markdown,
    /// Markdown with embedded image (base64 or file path)
    MarkdownWithImage {
        /// Image data as base64 or file path
        image: String,
        /// Whether image is base64 encoded
        is_base64: bool,
    },
}

/// A dialog request from the D-Bus interface
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DialogRequest {
    /// Unique dialog ID
    pub id: String,
    /// Window title
    pub title: String,
    /// Main prompt/question
    pub prompt: String,
    /// Content format (plain, markdown, etc.)
    #[serde(default)]
    pub content_format: ContentFormat,
    /// Type-specific dialog configuration
    pub dialog_type: DialogType,
    /// Optional timeout in milliseconds
    pub timeout_ms: Option<u32>,
}

/// Dialog type with type-specific configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum DialogType {
    /// Multiple choice selection
    Choice {
        options: Vec<ChoiceOption>,
        default: Option<String>,
        allow_multiple: bool,
    },
    /// Text input (single or multiline)
    TextInput {
        placeholder: String,
        default: Option<String>,
        multiline: bool,
        validation: Option<String>,
    },
    /// Yes/No confirmation
    Confirmation {
        yes_label: String,
        no_label: String,
        default_yes: bool,
    },
    /// Numeric slider
    Slider {
        min: f64,
        max: f64,
        step: f64,
        default: f64,
        unit: Option<String>,
    },
    /// Progress indicator (non-blocking)
    Progress {
        progress: Option<f64>, // None = indeterminate
    },
    /// File/folder picker
    FilePicker {
        mode: FilePickerMode,
        filters: Vec<FileFilter>,
        default_path: Option<String>,
    },
    /// Toast notification (non-blocking, auto-dismiss)
    Toast {
        message: String,
        level: ToastLevel,
        duration_ms: u32, // How long to show (0 = until dismissed)
    },
}

/// Toast notification severity levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ToastLevel {
    #[default]
    Info,
    Success,
    Warning,
    Error,
}

/// Response from a dialog
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DialogResponse {
    /// Dialog ID (matches request)
    pub id: String,
    /// Selected value (type depends on dialog type)
    pub selection: serde_json::Value,
    /// Whether the dialog was cancelled
    pub cancelled: bool,
    /// Error message if any
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// Optional user comment/context for their choice
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    /// Unix timestamp of response
    pub timestamp: u64,
}

impl DialogResponse {
    pub fn cancelled(id: String) -> Self {
        Self {
            id,
            selection: serde_json::Value::Null,
            cancelled: true,
            error: None,
            comment: None,
            timestamp: chrono::Utc::now().timestamp() as u64,
        }
    }

    pub fn success(id: String, selection: serde_json::Value) -> Self {
        Self {
            id,
            selection,
            cancelled: false,
            error: None,
            comment: None,
            timestamp: chrono::Utc::now().timestamp() as u64,
        }
    }

    pub fn with_comment(mut self, comment: Option<String>) -> Self {
        // Only set if non-empty
        self.comment = comment.filter(|c| !c.trim().is_empty());
        self
    }
}

/// Active dialog being rendered
pub struct ActiveDialog {
    pub request: DialogRequest,
    pub response_tx: oneshot::Sender<DialogResponse>,
    pub started_at: Instant,
    /// Current state for interactive dialogs
    pub state: DialogState,
}

/// Mutable state for dialogs
pub struct DialogState {
    /// Type-specific state
    pub variant: DialogStateVariant,
    /// User comment (available on all dialogs)
    pub comment: String,
    /// Whether timer is paused
    pub timer_paused: bool,
    /// Total paused time (to adjust timeout)
    pub paused_duration: std::time::Duration,
    /// When pause started (if paused)
    pub pause_start: Option<std::time::Instant>,
    /// Whether comment section is expanded
    pub comment_expanded: bool,
}

/// Type-specific state variants
pub enum DialogStateVariant {
    Choice {
        selected: Vec<String>,
    },
    TextInput {
        text: String,
        valid: bool,
    },
    Confirmation {
        selected: Option<bool>,
    },
    Slider {
        value: f64,
    },
    Progress,
    FilePicker,
    Toast,
}

impl ActiveDialog {
    pub fn new(request: DialogRequest, response_tx: oneshot::Sender<DialogResponse>) -> Self {
        let variant = match &request.dialog_type {
            DialogType::Choice { default, .. } => {
                DialogStateVariant::Choice {
                    selected: default.clone().map(|d| vec![d]).unwrap_or_default(),
                }
            }
            DialogType::TextInput { default, .. } => {
                DialogStateVariant::TextInput {
                    text: default.clone().unwrap_or_default(),
                    valid: true,
                }
            }
            DialogType::Confirmation { default_yes, .. } => {
                DialogStateVariant::Confirmation {
                    selected: Some(*default_yes),
                }
            }
            DialogType::Slider { default, .. } => {
                DialogStateVariant::Slider { value: *default }
            }
            DialogType::Progress { .. } => DialogStateVariant::Progress,
            DialogType::FilePicker { .. } => DialogStateVariant::FilePicker,
            DialogType::Toast { .. } => DialogStateVariant::Toast,
        };

        let state = DialogState {
            variant,
            comment: String::new(),
            timer_paused: false,
            paused_duration: std::time::Duration::ZERO,
            pause_start: None,
            comment_expanded: false,
        };

        Self {
            request,
            response_tx,
            started_at: Instant::now(),
            state,
        }
    }

    /// Toggle timer pause state
    pub fn toggle_pause(&mut self) {
        if self.state.timer_paused {
            // Resume - add elapsed pause time to total
            if let Some(start) = self.state.pause_start.take() {
                self.state.paused_duration += start.elapsed();
            }
            self.state.timer_paused = false;
        } else {
            // Pause
            self.state.pause_start = Some(Instant::now());
            self.state.timer_paused = true;
        }
    }

    /// Get effective elapsed time (accounting for pauses)
    fn effective_elapsed(&self) -> Duration {
        let raw_elapsed = self.started_at.elapsed();
        let total_paused = self.state.paused_duration + 
            self.state.pause_start.map(|s| s.elapsed()).unwrap_or(Duration::ZERO);
        raw_elapsed.saturating_sub(total_paused)
    }

    /// Check if dialog has timed out
    pub fn is_timed_out(&self) -> bool {
        // Never timeout while paused
        if self.state.timer_paused {
            return false;
        }
        if let Some(timeout_ms) = self.request.timeout_ms {
            self.effective_elapsed() > Duration::from_millis(timeout_ms as u64)
        } else {
            false
        }
    }

    /// Get remaining time as a ratio (1.0 = full time, 0.0 = expired)
    pub fn time_remaining_ratio(&self) -> Option<f32> {
        self.request.timeout_ms.map(|timeout_ms| {
            if self.state.timer_paused {
                // Show frozen ratio when paused
                let elapsed_before_pause = self.state.paused_duration.as_millis() as f32;
                let total = timeout_ms as f32;
                (1.0 - (elapsed_before_pause / total)).max(0.0)
            } else {
                let elapsed = self.effective_elapsed().as_millis() as f32;
                let total = timeout_ms as f32;
                (1.0 - (elapsed / total)).max(0.0)
            }
        })
    }

    /// Complete the dialog with a response
    pub fn complete(self, selection: serde_json::Value) {
        let comment = if self.state.comment.trim().is_empty() {
            None
        } else {
            Some(self.state.comment)
        };
        let response = DialogResponse::success(self.request.id, selection).with_comment(comment);
        let _ = self.response_tx.send(response);
    }

    /// Cancel the dialog
    pub fn cancel(self) {
        let response = DialogResponse::cancelled(self.request.id);
        let _ = self.response_tx.send(response);
    }

    /// Get comment text
    pub fn comment(&self) -> &str {
        &self.state.comment
    }

    /// Get mutable comment text
    pub fn comment_mut(&mut self) -> &mut String {
        &mut self.state.comment
    }

    /// Check if timer is paused
    pub fn is_paused(&self) -> bool {
        self.state.timer_paused
    }
}

/// An active toast notification
#[derive(Debug)]
pub struct ActiveToast {
    pub id: String,
    pub message: String,
    pub level: ToastLevel,
    pub started_at: Instant,
    pub duration: Duration,
    /// Response channel (optional - toasts don't require response)
    pub response_tx: Option<oneshot::Sender<DialogResponse>>,
}

impl ActiveToast {
    pub fn new(id: String, message: String, level: ToastLevel, duration_ms: u32, response_tx: Option<oneshot::Sender<DialogResponse>>) -> Self {
        Self {
            id,
            message,
            level,
            started_at: Instant::now(),
            duration: Duration::from_millis(duration_ms as u64),
            response_tx,
        }
    }

    /// Check if toast should be dismissed
    pub fn is_expired(&self) -> bool {
        if self.duration.is_zero() {
            return false; // Never expires (manual dismiss only)
        }
        self.started_at.elapsed() >= self.duration
    }

    /// Get remaining time ratio (1.0 = full, 0.0 = expired)
    pub fn time_remaining_ratio(&self) -> f32 {
        if self.duration.is_zero() {
            return 1.0; // Never expires
        }
        let elapsed = self.started_at.elapsed().as_secs_f32();
        let total = self.duration.as_secs_f32();
        (1.0 - elapsed / total).max(0.0)
    }

    /// Dismiss and send response
    pub fn dismiss(self) {
        if let Some(tx) = self.response_tx {
            let response = DialogResponse::success(self.id, serde_json::json!("dismissed"));
            let _ = tx.send(response);
        }
    }
}

/// Toast history entry for sidebar
#[derive(Debug, Clone)]
pub struct ToastHistoryEntry {
    pub id: String,
    pub message: String,
    pub level: ToastLevel,
    pub timestamp: Instant,
    pub read: bool,
}

/// Global settings for the dialog system
#[derive(Debug, Clone)]
pub struct DialogSettings {
    /// When true, ALL dialogs ignore timeouts until user responds
    pub hold_mode: bool,
    /// Base font scale (1.0 = default, 1.5 = 150%, etc.)
    pub font_scale: f32,
    /// Whether to play notification sounds
    pub sounds_enabled: bool,
    /// Whether to request window focus on new dialogs
    pub focus_on_dialog: bool,
}

impl Default for DialogSettings {
    fn default() -> Self {
        Self {
            hold_mode: false,
            font_scale: 1.0,
            sounds_enabled: true,
            focus_on_dialog: true,
        }
    }
}

/// Manages dialog queue and rendering
pub struct DialogManager {
    /// Currently active dialog (only one at a time)
    pub active: Option<ActiveDialog>,
    /// Pending dialogs
    pub queue: Vec<(DialogRequest, oneshot::Sender<DialogResponse>)>,
    /// Active toasts (can have multiple, non-blocking)
    pub toasts: Vec<ActiveToast>,
    /// Maximum concurrent toasts
    pub max_toasts: usize,
    /// Whether to remember comment field state
    pub remember_comment_expanded: bool,
    /// Last comment expanded state
    pub last_comment_expanded: bool,
    /// Toast history for sidebar
    pub toast_history: Vec<ToastHistoryEntry>,
    /// Maximum history entries
    pub max_history: usize,
    /// Global settings
    pub settings: DialogSettings,
}

impl Default for DialogManager {
    fn default() -> Self {
        Self::new()
    }
}

impl DialogManager {
    pub fn new() -> Self {
        Self {
            active: None,
            queue: Vec::new(),
            toasts: Vec::new(),
            max_toasts: 5,
            remember_comment_expanded: true,
            last_comment_expanded: false,
            toast_history: Vec::new(),
            max_history: 50,
            settings: DialogSettings::default(),
        }
    }

    /// Toggle global hold mode (no timeouts)
    pub fn toggle_hold_mode(&mut self) {
        self.settings.hold_mode = !self.settings.hold_mode;
    }

    /// Check if hold mode is active
    pub fn is_hold_mode(&self) -> bool {
        self.settings.hold_mode
    }

    /// Add a new dialog request
    pub fn enqueue(&mut self, request: DialogRequest, response_tx: oneshot::Sender<DialogResponse>) {
        // Check if it's a toast - handle separately
        if let DialogType::Toast { message, level, duration_ms } = &request.dialog_type {
            self.add_toast(
                request.id,
                message.clone(),
                level.clone(),
                *duration_ms,
                Some(response_tx),
            );
            return;
        }

        if self.active.is_none() {
            let mut dialog = ActiveDialog::new(request, response_tx);
            // Restore comment state if enabled
            if self.remember_comment_expanded {
                dialog.state.comment_expanded = self.last_comment_expanded;
            }
            self.active = Some(dialog);
        } else {
            self.queue.push((request, response_tx));
        }
    }

    /// Add a toast notification
    pub fn add_toast(&mut self, id: String, message: String, level: ToastLevel, duration_ms: u32, response_tx: Option<oneshot::Sender<DialogResponse>>) {
        // Add to history first
        while self.toast_history.len() >= self.max_history {
            self.toast_history.pop();
        }
        self.toast_history.insert(0, ToastHistoryEntry {
            id: id.clone(),
            message: message.clone(),
            level,
            timestamp: Instant::now(),
            read: false,
        });

        // Remove oldest active toast if at max
        while self.toasts.len() >= self.max_toasts {
            if let Some(toast) = self.toasts.pop() {
                toast.dismiss();
            }
        }
        
        // Add new toast at the front (newest first)
        self.toasts.insert(0, ActiveToast::new(id, message, level, duration_ms, response_tx));
    }

    /// Count unread notifications in history
    pub fn unread_count(&self) -> usize {
        self.toast_history.iter().filter(|t| !t.read).count()
    }

    /// Mark all notifications as read
    pub fn mark_all_read(&mut self) {
        for entry in &mut self.toast_history {
            entry.read = true;
        }
    }

    /// Clear notification history
    pub fn clear_history(&mut self) {
        self.toast_history.clear();
    }

    /// Remove a specific history entry
    pub fn remove_history_entry(&mut self, id: &str) {
        self.toast_history.retain(|e| e.id != id);
    }

    /// Move to next dialog in queue
    pub fn next(&mut self) {
        // Save comment state from current dialog
        if let Some(ref active) = self.active {
            if self.remember_comment_expanded {
                self.last_comment_expanded = active.state.comment_expanded;
            }
        }

        self.active = self.queue.pop().map(|(req, tx)| {
            let mut dialog = ActiveDialog::new(req, tx);
            if self.remember_comment_expanded {
                dialog.state.comment_expanded = self.last_comment_expanded;
            }
            dialog
        });
    }

    /// Switch to a specific queued dialog by index, moving current to back of queue
    /// Returns true if switch was successful
    pub fn switch_to_queued(&mut self, queue_index: usize) -> bool {
        if queue_index >= self.queue.len() {
            return false;
        }

        // Remove the target from queue
        let (target_req, target_tx) = self.queue.remove(queue_index);

        // If there's an active dialog, put it at the back of the queue
        if let Some(active) = self.active.take() {
            // Save comment state
            if self.remember_comment_expanded {
                self.last_comment_expanded = active.state.comment_expanded;
            }
            
            // Move current dialog back to queue, preserving its response channel
            // We need to decompose the ActiveDialog to get the request and response_tx back
            self.queue.push((active.request, active.response_tx));
        }

        // Make the target dialog active
        let mut dialog = ActiveDialog::new(target_req, target_tx);
        if self.remember_comment_expanded {
            dialog.state.comment_expanded = self.last_comment_expanded;
        }
        self.active = Some(dialog);

        true
    }

    /// Get number of dialogs in queue
    pub fn queue_len(&self) -> usize {
        self.queue.len()
    }

    /// Get queue item info for display
    pub fn queue_display_info(&self) -> Vec<(String, String, String)> {
        self.queue.iter().enumerate().map(|(idx, (req, _))| {
            let type_label = match &req.dialog_type {
                DialogType::Choice { .. } => "Choice",
                DialogType::TextInput { .. } => "Text",
                DialogType::Confirmation { .. } => "Confirm",
                DialogType::Slider { .. } => "Slider",
                DialogType::Progress { .. } => "Progress",
                DialogType::FilePicker { .. } => "File",
                DialogType::Toast { .. } => "Toast",
            };
            (req.id.clone(), req.title.clone(), type_label.to_string())
        }).collect()
    }

    /// Check and handle timeouts (dialogs and toasts)
    pub fn check_timeouts(&mut self) {
        // Check dialog timeout (skip if global hold mode is active)
        if !self.settings.hold_mode {
            if let Some(active) = self.active.take() {
                if active.is_timed_out() {
                    active.cancel();
                    self.next();
                } else {
                    self.active = Some(active);
                }
            }
        }

        // Check toast timeouts - remove expired ones (toasts still timeout in hold mode)
        let expired = self.toasts.drain_filter_compat();
        for toast in expired {
            toast.dismiss();
        }
    }

    /// Dismiss a specific toast by ID
    pub fn dismiss_toast(&mut self, id: &str) {
        if let Some(pos) = self.toasts.iter().position(|t| t.id == id) {
            let toast = self.toasts.remove(pos);
            toast.dismiss();
        }
    }
}

/// Helper trait for drain_filter (not stable yet)
trait DrainFilterCompat {
    fn drain_filter_compat(&mut self) -> Vec<ActiveToast>;
}

impl DrainFilterCompat for Vec<ActiveToast> {
    fn drain_filter_compat(&mut self) -> Vec<ActiveToast> {
        let mut removed = Vec::new();
        let mut i = 0;
        while i < self.len() {
            if self[i].is_expired() {
                removed.push(self.remove(i));
            } else {
                i += 1;
            }
        }
        removed
    }
}

