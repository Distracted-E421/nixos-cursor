//! Web server for remote dialog access (PWA)
//!
//! Provides HTTP and WebSocket endpoints for mobile/remote access to the dialog system.

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    http::StatusCode,
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::{broadcast, oneshot, RwLock};
use tower_http::cors::{Any, CorsLayer};
use tracing::{error, info};

use crate::dialog::{DialogManager, DialogRequest, DialogResponse, DialogType};

/// Web server state shared across handlers
#[derive(Clone)]
pub struct WebState {
    /// Dialog manager (shared with GUI and D-Bus)
    pub manager: Arc<RwLock<DialogManager>>,
    /// Broadcast channel for dialog updates (WebSocket subscribers)
    pub updates_tx: broadcast::Sender<DialogUpdate>,
}

/// Update message sent to WebSocket clients
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
pub enum DialogUpdate {
    /// New dialog arrived
    NewDialog {
        id: String,
        title: String,
        prompt: String,
        dialog_type: String,
        timeout_ms: Option<u32>,
    },
    /// Dialog completed (answered or cancelled)
    DialogCompleted {
        id: String,
        selection: serde_json::Value,
        cancelled: bool,
    },
    /// Queue changed
    QueueUpdate {
        active_id: Option<String>,
        queue_count: usize,
    },
    /// Hold mode toggled
    HoldModeChanged {
        enabled: bool,
    },
}

/// Request to respond to a dialog
#[derive(Debug, Deserialize)]
pub struct DialogAnswerRequest {
    pub id: String,
    pub selection: serde_json::Value,
    pub comment: Option<String>,
}

/// API response wrapper
#[derive(Debug, Serialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }
    
    pub fn err(message: impl Into<String>) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(message.into()),
        }
    }
}

/// Create the web server router
pub fn create_router(state: WebState) -> Router {
    Router::new()
        // API endpoints
        .route("/api/status", get(get_status))
        .route("/api/current", get(get_current_dialog))
        .route("/api/queue", get(get_queue))
        .route("/api/answer", post(answer_dialog))
        .route("/api/skip", post(skip_to_next))
        .route("/api/hold", post(toggle_hold_mode))
        // WebSocket for real-time updates
        .route("/ws", get(ws_handler))
        // PWA assets
        .route("/", get(serve_index))
        .route("/manifest.json", get(serve_manifest))
        .route("/sw.js", get(serve_service_worker))
        // CORS for local development
        .layer(CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any))
        .with_state(state)
}

/// Get current system status
async fn get_status(State(state): State<WebState>) -> Json<ApiResponse<serde_json::Value>> {
    let manager = state.manager.read().await;
    let status = serde_json::json!({
        "has_active": manager.active.is_some(),
        "queue_length": manager.queue_len(),
        "hold_mode": manager.settings.hold_mode,
        "toast_count": manager.toasts.len(),
    });
    Json(ApiResponse::ok(status))
}

/// Get current active dialog details
async fn get_current_dialog(State(state): State<WebState>) -> Json<ApiResponse<serde_json::Value>> {
    let manager = state.manager.read().await;
    
    if let Some(ref active) = manager.active {
        let dialog_type_str = match &active.request.dialog_type {
            DialogType::Choice { options, allow_multiple, .. } => {
                serde_json::json!({
                    "type": "choice",
                    "options": options,
                    "allow_multiple": allow_multiple,
                })
            }
            DialogType::TextInput { placeholder, multiline, .. } => {
                serde_json::json!({
                    "type": "text",
                    "placeholder": placeholder,
                    "multiline": multiline,
                })
            }
            DialogType::Confirmation { yes_label, no_label, .. } => {
                serde_json::json!({
                    "type": "confirm",
                    "yes_label": yes_label,
                    "no_label": no_label,
                })
            }
            DialogType::Slider { min, max, step, unit, .. } => {
                serde_json::json!({
                    "type": "slider",
                    "min": min,
                    "max": max,
                    "step": step,
                    "unit": unit,
                })
            }
            _ => serde_json::json!({ "type": "unknown" }),
        };
        
        let dialog = serde_json::json!({
            "id": active.request.id,
            "title": active.request.title,
            "prompt": active.request.prompt,
            "dialog_type": dialog_type_str,
            "timeout_ms": active.request.timeout_ms,
            "time_remaining_ratio": active.time_remaining_ratio(),
            "is_paused": active.is_paused(),
        });
        Json(ApiResponse::ok(dialog))
    } else {
        Json(ApiResponse::err("No active dialog"))
    }
}

/// Get queue information
async fn get_queue(State(state): State<WebState>) -> Json<ApiResponse<Vec<serde_json::Value>>> {
    let manager = state.manager.read().await;
    let queue_info: Vec<_> = manager.queue_display_info()
        .into_iter()
        .enumerate()
        .map(|(idx, (id, title, type_label))| {
            serde_json::json!({
                "index": idx,
                "id": id,
                "title": title,
                "type": type_label,
            })
        })
        .collect();
    Json(ApiResponse::ok(queue_info))
}

/// Answer a dialog
async fn answer_dialog(
    State(state): State<WebState>,
    Json(request): Json<DialogAnswerRequest>,
) -> Json<ApiResponse<String>> {
    let mut manager = state.manager.write().await;
    
    // Check if the requested dialog is the active one
    if let Some(ref active) = manager.active {
        if active.request.id == request.id {
            // Set comment on active dialog before completing
            if let Some(ref mut active) = manager.active {
                if let Some(comment) = &request.comment {
                    active.state.comment = comment.clone();
                }
            }
            
            // Take the active dialog and complete it
            if let Some(active) = manager.active.take() {
                active.complete(request.selection);
                manager.next();
                
                // Broadcast update
                let _ = state.updates_tx.send(DialogUpdate::DialogCompleted {
                    id: request.id.clone(),
                    selection: serde_json::Value::Null,  // Don't echo selection
                    cancelled: false,
                });
                let _ = state.updates_tx.send(DialogUpdate::QueueUpdate {
                    active_id: manager.active.as_ref().map(|a| a.request.id.clone()),
                    queue_count: manager.queue_len(),
                });
                
                return Json(ApiResponse::ok("Dialog answered".to_string()));
            }
        }
    }
    
    Json(ApiResponse::err("Dialog not found or not active"))
}

/// Skip to next dialog in queue
async fn skip_to_next(State(state): State<WebState>) -> Json<ApiResponse<String>> {
    let mut manager = state.manager.write().await;
    
    if manager.queue_len() > 0 {
        if manager.switch_to_queued(0) {
            let _ = state.updates_tx.send(DialogUpdate::QueueUpdate {
                active_id: manager.active.as_ref().map(|a| a.request.id.clone()),
                queue_count: manager.queue_len(),
            });
            return Json(ApiResponse::ok("Switched to next dialog".to_string()));
        }
    }
    
    Json(ApiResponse::err("No dialogs in queue"))
}

/// Toggle hold mode
async fn toggle_hold_mode(State(state): State<WebState>) -> Json<ApiResponse<bool>> {
    let mut manager = state.manager.write().await;
    manager.toggle_hold_mode();
    let new_state = manager.settings.hold_mode;
    
    let _ = state.updates_tx.send(DialogUpdate::HoldModeChanged { enabled: new_state });
    
    Json(ApiResponse::ok(new_state))
}

/// WebSocket handler for real-time updates
async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<WebState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_websocket(socket, state))
}

/// Handle WebSocket connection
async fn handle_websocket(socket: WebSocket, state: WebState) {
    let (mut sender, mut receiver) = socket.split();
    
    // Subscribe to updates
    let mut updates_rx = state.updates_tx.subscribe();
    
    // Send initial state
    {
        let manager = state.manager.read().await;
        let initial = serde_json::json!({
            "type": "initial",
            "has_active": manager.active.is_some(),
            "active_id": manager.active.as_ref().map(|a| &a.request.id),
            "queue_count": manager.queue_len(),
            "hold_mode": manager.settings.hold_mode,
        });
        let _ = sender.send(Message::Text(initial.to_string().into())).await;
    }
    
    // Handle both incoming messages and outgoing updates
    loop {
        tokio::select! {
            // Forward updates to client
            Ok(update) = updates_rx.recv() => {
                let json = serde_json::to_string(&update).unwrap_or_default();
                if sender.send(Message::Text(json.into())).await.is_err() {
                    break;
                }
            }
            // Handle client messages (pings, etc.)
            Some(msg) = receiver.next() => {
                match msg {
                    Ok(Message::Close(_)) => break,
                    Ok(Message::Ping(data)) => {
                        let _ = sender.send(Message::Pong(data)).await;
                    }
                    Err(_) => break,
                    _ => {}
                }
            }
            else => break,
        }
    }
}

/// Serve the PWA index page
async fn serve_index() -> Html<&'static str> {
    Html(include_str!("../static/index.html"))
}

/// Serve the PWA manifest
async fn serve_manifest() -> impl IntoResponse {
    (
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        include_str!("../static/manifest.json"),
    )
}

/// Serve the service worker
async fn serve_service_worker() -> impl IntoResponse {
    (
        [(axum::http::header::CONTENT_TYPE, "application/javascript")],
        include_str!("../static/sw.js"),
    )
}

/// Start the web server
pub async fn start_web_server(
    manager: Arc<RwLock<DialogManager>>,
    port: u16,
) -> Result<broadcast::Sender<DialogUpdate>, std::io::Error> {
    let (updates_tx, _) = broadcast::channel(100);
    let updates_tx_clone = updates_tx.clone();
    
    let state = WebState {
        manager,
        updates_tx,
    };
    
    let app = create_router(state);
    
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    info!("Web server started on http://0.0.0.0:{}", port);
    info!("Access via Tailscale: http://obsidian:{}", port);
    
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    
    Ok(updates_tx_clone)
}

