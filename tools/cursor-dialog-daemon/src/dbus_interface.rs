//! D-Bus Interface Definition for Cursor Dialog Daemon
//!
//! Service: sh.cursor.studio.Dialog
//! Object Path: /sh/cursor/studio/Dialog
//!
//! This provides structured IPC for AI agents to request user input
//! without burning API requests.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, RwLock};
use tracing::{debug, info, warn};
use uuid::Uuid;
use zbus::{interface, Connection, Result as ZbusResult};

use crate::dialog::{DialogManager, DialogRequest, DialogResponse, DialogType};

/// D-Bus interface for the dialog service
pub struct DialogInterface {
    /// Channel to send dialog requests to the GUI
    dialog_tx: mpsc::Sender<(DialogRequest, oneshot::Sender<DialogResponse>)>,
    /// Active dialogs waiting for responses
    pending: Arc<RwLock<HashMap<String, oneshot::Sender<DialogResponse>>>>,
}

impl DialogInterface {
    pub fn new(dialog_tx: mpsc::Sender<(DialogRequest, oneshot::Sender<DialogResponse>)>) -> Self {
        Self {
            dialog_tx,
            pending: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

#[interface(name = "sh.cursor.studio.Dialog1")]
impl DialogInterface {
    /// Show a multiple choice dialog
    ///
    /// # Arguments
    /// * `title` - Dialog window title
    /// * `prompt` - Question/prompt to display
    /// * `options` - JSON array of options: [{"value": "x", "label": "X", "description": "..."}]
    /// * `default_value` - Default selected value (empty for none)
    /// * `allow_multiple` - Allow selecting multiple options
    /// * `timeout_ms` - Timeout in milliseconds (0 for no timeout)
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "selection": "value" or ["v1","v2"], "cancelled": false}
    async fn show_choice(
        &self,
        title: String,
        prompt: String,
        options: String, // JSON array
        default_value: String,
        allow_multiple: bool,
        timeout_ms: u32,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowChoice request id={}", id);

        let options: Vec<ChoiceOption> = match serde_json::from_str(&options) {
            Ok(opts) => opts,
            Err(e) => {
                return serde_json::to_string(&DialogResponse {
                    id: id.clone(),
                    selection: serde_json::Value::Null,
                    cancelled: true,
                    error: Some(format!("Invalid options JSON: {}", e)),
                    comment: None,
                    timestamp: chrono::Utc::now().timestamp() as u64,
                })
                .unwrap_or_default();
            }
        };

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt,
            dialog_type: DialogType::Choice {
                options,
                default: if default_value.is_empty() {
                    None
                } else {
                    Some(default_value)
                },
                allow_multiple,
            },
            timeout_ms: if timeout_ms == 0 {
                None
            } else {
                Some(timeout_ms)
            },
        };

        self.execute_dialog(request).await
    }

    /// Show a text input dialog
    ///
    /// # Arguments
    /// * `title` - Dialog window title
    /// * `prompt` - Question/prompt to display
    /// * `placeholder` - Placeholder text for input
    /// * `default_value` - Pre-filled value
    /// * `multiline` - Allow multiline input
    /// * `validation_regex` - Optional regex for validation (empty to skip)
    /// * `timeout_ms` - Timeout in milliseconds (0 for no timeout)
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "selection": "user input", "cancelled": false}
    async fn show_text_input(
        &self,
        title: String,
        prompt: String,
        placeholder: String,
        default_value: String,
        multiline: bool,
        validation_regex: String,
        timeout_ms: u32,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowTextInput request id={}", id);

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt,
            dialog_type: DialogType::TextInput {
                placeholder,
                default: if default_value.is_empty() {
                    None
                } else {
                    Some(default_value)
                },
                multiline,
                validation: if validation_regex.is_empty() {
                    None
                } else {
                    Some(validation_regex)
                },
            },
            timeout_ms: if timeout_ms == 0 {
                None
            } else {
                Some(timeout_ms)
            },
        };

        self.execute_dialog(request).await
    }

    /// Show a confirmation dialog (Yes/No)
    ///
    /// # Arguments
    /// * `title` - Dialog window title
    /// * `prompt` - Question to confirm
    /// * `yes_label` - Label for yes button (default: "Yes")
    /// * `no_label` - Label for no button (default: "No")
    /// * `default_yes` - Whether Yes is the default selection
    /// * `timeout_ms` - Timeout in milliseconds (0 for no timeout)
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "selection": true/false, "cancelled": false}
    async fn show_confirmation(
        &self,
        title: String,
        prompt: String,
        yes_label: String,
        no_label: String,
        default_yes: bool,
        timeout_ms: u32,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowConfirmation request id={}", id);

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt,
            dialog_type: DialogType::Confirmation {
                yes_label: if yes_label.is_empty() {
                    "Yes".to_string()
                } else {
                    yes_label
                },
                no_label: if no_label.is_empty() {
                    "No".to_string()
                } else {
                    no_label
                },
                default_yes,
            },
            timeout_ms: if timeout_ms == 0 {
                None
            } else {
                Some(timeout_ms)
            },
        };

        self.execute_dialog(request).await
    }

    /// Show a slider/range input dialog
    ///
    /// # Arguments
    /// * `title` - Dialog window title
    /// * `prompt` - Description of what the value represents
    /// * `min` - Minimum value
    /// * `max` - Maximum value
    /// * `step` - Step increment
    /// * `default_value` - Initial value
    /// * `unit` - Unit label (e.g., "tokens", "%", "ms")
    /// * `timeout_ms` - Timeout in milliseconds (0 for no timeout)
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "selection": 42.5, "cancelled": false}
    async fn show_slider(
        &self,
        title: String,
        prompt: String,
        min: f64,
        max: f64,
        step: f64,
        default_value: f64,
        unit: String,
        timeout_ms: u32,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowSlider request id={}", id);

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt,
            dialog_type: DialogType::Slider {
                min,
                max,
                step,
                default: default_value,
                unit: if unit.is_empty() { None } else { Some(unit) },
            },
            timeout_ms: if timeout_ms == 0 {
                None
            } else {
                Some(timeout_ms)
            },
        };

        self.execute_dialog(request).await
    }

    /// Show a progress notification (non-blocking)
    ///
    /// # Arguments
    /// * `title` - Notification title
    /// * `message` - Progress message
    /// * `progress` - Progress value 0.0-1.0 (negative for indeterminate)
    ///
    /// # Returns
    /// Notification ID for updates
    async fn show_progress(&self, title: String, message: String, progress: f64) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowProgress request id={}", id);

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt: message,
            dialog_type: DialogType::Progress {
                progress: if progress < 0.0 { None } else { Some(progress) },
            },
            timeout_ms: None,
        };

        // Progress is non-blocking, fire and forget
        let (tx, _rx) = oneshot::channel();
        let _ = self.dialog_tx.send((request, tx)).await;

        serde_json::to_string(&serde_json::json!({
            "id": id,
            "status": "shown"
        }))
        .unwrap_or_default()
    }

    /// Update a progress notification
    async fn update_progress(&self, id: String, message: String, progress: f64) -> bool {
        // TODO: Implement progress updates via notification ID
        debug!("D-Bus: UpdateProgress id={} progress={}", id, progress);
        true
    }

    /// Dismiss a progress notification
    async fn dismiss_progress(&self, id: String) -> bool {
        debug!("D-Bus: DismissProgress id={}", id);
        true
    }

    /// Show a file/folder selection dialog
    ///
    /// # Arguments
    /// * `title` - Dialog title
    /// * `prompt` - Description
    /// * `mode` - "file", "files", "folder", or "save"
    /// * `filters` - JSON array of filters: [{"name": "Nix files", "extensions": ["nix"]}]
    /// * `default_path` - Starting directory
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "selection": "/path/to/file" or [paths], "cancelled": false}
    async fn show_file_picker(
        &self,
        title: String,
        prompt: String,
        mode: String,
        filters: String,
        default_path: String,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowFilePicker request id={} mode={}", id, mode);

        let filters: Vec<FileFilter> = serde_json::from_str(&filters).unwrap_or_default();

        let request = DialogRequest {
            id: id.clone(),
            title,
            prompt,
            dialog_type: DialogType::FilePicker {
                mode: match mode.as_str() {
                    "files" => FilePickerMode::MultipleFiles,
                    "folder" => FilePickerMode::Folder,
                    "save" => FilePickerMode::Save,
                    _ => FilePickerMode::SingleFile,
                },
                filters,
                default_path: if default_path.is_empty() {
                    None
                } else {
                    Some(default_path)
                },
            },
            timeout_ms: None,
        };

        self.execute_dialog(request).await
    }

    /// Show a toast notification (non-blocking, auto-dismiss)
    ///
    /// # Arguments
    /// * `message` - Toast message to display
    /// * `level` - Severity: "info", "success", "warning", "error"
    /// * `duration_ms` - Duration to show (0 = until manually dismissed)
    ///
    /// # Returns
    /// JSON response: {"id": "uuid", "status": "shown"}
    async fn show_toast(
        &self,
        message: String,
        level: String,
        duration_ms: u32,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        info!("D-Bus: ShowToast request id={} level={}", id, level);

        let toast_level = match level.to_lowercase().as_str() {
            "success" => crate::dialog::ToastLevel::Success,
            "warning" | "warn" => crate::dialog::ToastLevel::Warning,
            "error" | "err" => crate::dialog::ToastLevel::Error,
            _ => crate::dialog::ToastLevel::Info,
        };

        let request = DialogRequest {
            id: id.clone(),
            title: String::new(), // Toasts don't have titles
            prompt: String::new(), // Message is in the type
            dialog_type: DialogType::Toast {
                message,
                level: toast_level,
                duration_ms,
            },
            timeout_ms: None, // Toasts manage their own duration
        };

        // Toasts are fire-and-forget (non-blocking)
        let (tx, _rx) = oneshot::channel();
        let _ = self.dialog_tx.send((request, tx)).await;

        serde_json::to_string(&serde_json::json!({
            "id": id,
            "status": "shown"
        }))
        .unwrap_or_default()
    }

    /// Dismiss a specific toast by ID
    async fn dismiss_toast(&self, id: String) -> bool {
        // TODO: Implement toast dismissal via manager
        debug!("D-Bus: DismissToast id={}", id);
        true
    }

    /// Get daemon version and capabilities
    async fn get_info(&self) -> String {
        serde_json::to_string(&serde_json::json!({
            "version": env!("CARGO_PKG_VERSION"),
            "capabilities": [
                "choice",
                "text_input",
                "confirmation",
                "slider",
                "progress",
                "file_picker",
                "toast"
            ],
            "platform": std::env::consts::OS,
        }))
        .unwrap_or_default()
    }

    /// Ping to check if daemon is alive
    async fn ping(&self) -> String {
        "pong".to_string()
    }
}

impl DialogInterface {
    async fn execute_dialog(&self, request: DialogRequest) -> String {
        let (response_tx, response_rx) = oneshot::channel();

        if let Err(e) = self.dialog_tx.send((request.clone(), response_tx)).await {
            warn!("Failed to send dialog request: {}", e);
            return serde_json::to_string(&DialogResponse {
                id: request.id,
                selection: serde_json::Value::Null,
                cancelled: true,
                error: Some(format!("Internal error: {}", e)),
                comment: None,
                timestamp: chrono::Utc::now().timestamp() as u64,
            })
            .unwrap_or_default();
        }

        match response_rx.await {
            Ok(response) => serde_json::to_string(&response).unwrap_or_default(),
            Err(e) => {
                warn!("Dialog response channel closed: {}", e);
                serde_json::to_string(&DialogResponse {
                    id: request.id,
                    selection: serde_json::Value::Null,
                    cancelled: true,
                    error: Some("Dialog was closed unexpectedly".to_string()),
                    comment: None,
                    timestamp: chrono::Utc::now().timestamp() as u64,
                })
                .unwrap_or_default()
            }
        }
    }
}

/// Choice option for multiple choice dialogs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChoiceOption {
    /// Internal value (returned in response)
    pub value: String,
    /// Display label
    pub label: String,
    /// Optional description/hint
    #[serde(default)]
    pub description: Option<String>,
    /// Optional icon name or emoji
    #[serde(default)]
    pub icon: Option<String>,
}

/// File filter for file picker dialogs
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FileFilter {
    /// Filter name (e.g., "Nix files")
    pub name: String,
    /// Extensions without dots (e.g., ["nix", "nixos"])
    pub extensions: Vec<String>,
}

/// File picker mode
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FilePickerMode {
    SingleFile,
    MultipleFiles,
    Folder,
    Save,
}

/// Start the D-Bus service
pub async fn start_dbus_service(
    dialog_tx: mpsc::Sender<(DialogRequest, oneshot::Sender<DialogResponse>)>,
) -> ZbusResult<Connection> {
    let interface = DialogInterface::new(dialog_tx);

    let connection = Connection::session().await?;

    // Request the well-known name
    connection
        .request_name("sh.cursor.studio.Dialog")
        .await?;

    connection
        .object_server()
        .at("/sh/cursor/studio/Dialog", interface)
        .await?;

    info!("D-Bus service registered: sh.cursor.studio.Dialog");
    info!("Object path: /sh/cursor/studio/Dialog");
    info!("Interface: sh.cursor.studio.Dialog1");

    Ok(connection)
}

