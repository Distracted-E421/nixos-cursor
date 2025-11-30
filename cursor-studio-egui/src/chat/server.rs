//! Chat Sync Server - REST API for multi-device synchronization.
//!
//! Provides endpoints for:
//! - Device registration and authentication
//! - Conversation sync (push/pull)
//! - Delta sync for efficient updates
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin sync-server -- --port 8080
//! ```

use std::sync::Arc;
use tokio::sync::RwLock;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use super::crdt::{DeviceId, VectorClock};
use super::models::Conversation;
use super::surreal::{SurrealStore, SyncedConversation};

/// Server configuration
#[derive(Debug, Clone)]
pub struct ServerConfig {
    /// Port to listen on
    pub port: u16,
    /// Host to bind to
    pub host: String,
    /// Whether to enable CORS for web clients
    pub enable_cors: bool,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            port: 8420,
            host: "0.0.0.0".to_string(),
            enable_cors: true,
        }
    }
}

/// Shared server state
pub struct ServerState {
    /// The SurrealDB store
    pub store: SurrealStore,
    /// Server's device ID
    pub device_id: DeviceId,
    /// Connected devices (for tracking)
    pub connected_devices: RwLock<Vec<ConnectedDevice>>,
}

/// Information about a connected device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectedDevice {
    pub device_id: String,
    pub last_seen: chrono::DateTime<chrono::Utc>,
    pub sync_count: u64,
}

/// API response wrapper
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
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

/// Health check response
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub device_id: String,
    pub conversations: usize,
    pub uptime_seconds: u64,
}

/// Sync request from a client
#[derive(Debug, Deserialize)]
pub struct SyncRequest {
    /// Client's device ID
    pub device_id: String,
    /// Client's vector clock (for delta sync)
    pub vector_clock: Option<VectorClock>,
    /// Conversations to push (optional)
    pub conversations: Option<Vec<SyncedConversation>>,
}

/// Sync response to a client
#[derive(Debug, Serialize)]
pub struct SyncResponse {
    /// Server's device ID
    pub server_device_id: String,
    /// Conversations updated on server
    pub updated: usize,
    /// Conversations to send to client (delta)
    pub conversations: Vec<SyncedConversation>,
    /// Server's current vector clock
    pub server_clock: VectorClock,
}

/// Query parameters for listing conversations
#[derive(Debug, Deserialize)]
pub struct ListQuery {
    pub limit: Option<usize>,
    pub offset: Option<usize>,
}

/// Query parameters for search
#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub limit: Option<usize>,
}

/// Stats response
#[derive(Debug, Serialize)]
pub struct StatsResponse {
    pub total_conversations: usize,
    pub total_messages: usize,
    pub total_tokens: u64,
    pub connected_devices: usize,
    pub models_used: std::collections::HashMap<String, usize>,
}

/// Create the API router
pub fn create_router(state: Arc<ServerState>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        // Health & Info
        .route("/", get(root_handler))
        .route("/health", get(health_handler))
        .route("/stats", get(stats_handler))
        // Conversations
        .route("/conversations", get(list_conversations_handler))
        .route("/conversations/:id", get(get_conversation_handler))
        .route("/conversations/search", get(search_handler))
        // Sync
        .route("/sync", post(sync_handler))
        .route("/sync/push", post(push_handler))
        .route("/sync/pull", get(pull_handler))
        // Middleware
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state)
}

/// Root endpoint - API info
async fn root_handler() -> impl IntoResponse {
    Json(serde_json::json!({
        "name": "Cursor Chat Sync Server",
        "version": env!("CARGO_PKG_VERSION"),
        "endpoints": {
            "health": "GET /health",
            "stats": "GET /stats",
            "conversations": "GET /conversations",
            "conversation": "GET /conversations/:id",
            "search": "GET /conversations/search?q=<query>",
            "sync": "POST /sync",
            "push": "POST /sync/push",
            "pull": "GET /sync/pull"
        }
    }))
}

/// Health check endpoint
async fn health_handler(State(state): State<Arc<ServerState>>) -> impl IntoResponse {
    let count = state.store.count().await.unwrap_or(0);
    
    Json(ApiResponse::ok(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        device_id: state.device_id.0.clone(),
        conversations: count,
        uptime_seconds: 0, // TODO: track uptime
    }))
}

/// Get server statistics
async fn stats_handler(State(state): State<Arc<ServerState>>) -> impl IntoResponse {
    let conversations = match state.store.list_conversations(10000).await {
        Ok(c) => c,
        Err(e) => return Json(ApiResponse::<StatsResponse>::err(e.to_string())),
    };

    let total_conversations = conversations.len();
    let total_messages: usize = conversations.iter().map(|c| c.message_count).sum();
    let total_tokens: u64 = conversations.iter()
        .map(|c| c.total_input_tokens + c.total_output_tokens)
        .sum();

    let mut models_used: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for conv in &conversations {
        for model in &conv.models_used {
            *models_used.entry(model.clone()).or_insert(0) += 1;
        }
    }

    let connected_devices = state.connected_devices.read().await.len();

    Json(ApiResponse::ok(StatsResponse {
        total_conversations,
        total_messages,
        total_tokens,
        connected_devices,
        models_used,
    }))
}

/// List all conversations
async fn list_conversations_handler(
    State(state): State<Arc<ServerState>>,
    Query(query): Query<ListQuery>,
) -> impl IntoResponse {
    let limit = query.limit.unwrap_or(50);
    
    match state.store.list_conversations(limit).await {
        Ok(conversations) => Json(ApiResponse::ok(conversations)),
        Err(e) => Json(ApiResponse::<Vec<Conversation>>::err(e.to_string())),
    }
}

/// Get a specific conversation
async fn get_conversation_handler(
    State(state): State<Arc<ServerState>>,
    Path(id): Path<String>,
) -> impl IntoResponse {
    match state.store.get_conversation(&id).await {
        Ok(Some(conv)) => (StatusCode::OK, Json(ApiResponse::ok(conv))),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<Conversation>::err("Conversation not found")),
        ),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<Conversation>::err(e.to_string())),
        ),
    }
}

/// Search conversations
async fn search_handler(
    State(state): State<Arc<ServerState>>,
    Query(query): Query<SearchQuery>,
) -> impl IntoResponse {
    let limit = query.limit.unwrap_or(20);
    
    match state.store.search(&query.q, limit).await {
        Ok(results) => Json(ApiResponse::ok(results)),
        Err(e) => Json(ApiResponse::<Vec<Conversation>>::err(e.to_string())),
    }
}

/// Full sync endpoint - bidirectional sync
async fn sync_handler(
    State(state): State<Arc<ServerState>>,
    Json(request): Json<SyncRequest>,
) -> impl IntoResponse {
    // Track this device
    {
        let mut devices = state.connected_devices.write().await;
        let now = chrono::Utc::now();
        
        if let Some(device) = devices.iter_mut().find(|d| d.device_id == request.device_id) {
            device.last_seen = now;
            device.sync_count += 1;
        } else {
            devices.push(ConnectedDevice {
                device_id: request.device_id.clone(),
                last_seen: now,
                sync_count: 1,
            });
        }
    }

    // Process incoming conversations
    let mut updated = 0;
    if let Some(conversations) = request.conversations {
        for conv in conversations {
            match state.store.merge_conversation(&conv).await {
                Ok(_) => updated += 1,
                Err(e) => {
                    log::warn!("Failed to merge conversation: {}", e);
                }
            }
        }
    }

    // Get conversations to send back (delta sync)
    let since = request.vector_clock
        .as_ref()
        .map(|_| chrono::Utc::now() - chrono::Duration::days(30)) // Fallback: last 30 days
        .unwrap_or_else(|| chrono::Utc::now() - chrono::Duration::days(365));
    
    let conversations = state.store.get_modified_since(since).await.unwrap_or_default();

    // Create server clock
    let mut server_clock = VectorClock::new();
    server_clock.increment(&state.device_id);

    Json(ApiResponse::ok(SyncResponse {
        server_device_id: state.device_id.0.clone(),
        updated,
        conversations,
        server_clock,
    }))
}

/// Push conversations to server
async fn push_handler(
    State(state): State<Arc<ServerState>>,
    Json(conversations): Json<Vec<SyncedConversation>>,
) -> impl IntoResponse {
    let mut imported = 0;
    let mut errors = Vec::new();

    for conv in conversations {
        match state.store.merge_conversation(&conv).await {
            Ok(_) => imported += 1,
            Err(e) => errors.push(format!("{}: {}", conv.conversation.id, e)),
        }
    }

    Json(ApiResponse::ok(serde_json::json!({
        "imported": imported,
        "errors": errors
    })))
}

/// Pull conversations from server (delta)
async fn pull_handler(
    State(state): State<Arc<ServerState>>,
    Query(query): Query<ListQuery>,
) -> impl IntoResponse {
    let limit = query.limit.unwrap_or(100);
    
    // For now, just return recent conversations
    // TODO: Implement proper delta sync with vector clocks
    let since = chrono::Utc::now() - chrono::Duration::days(30);
    
    match state.store.get_modified_since(since).await {
        Ok(mut conversations) => {
            conversations.truncate(limit);
            Json(ApiResponse::ok(conversations))
        }
        Err(e) => Json(ApiResponse::<Vec<SyncedConversation>>::err(e.to_string())),
    }
}

/// Start the sync server
pub async fn start_server(config: ServerConfig, store: SurrealStore, device_id: DeviceId) -> anyhow::Result<()> {
    let state = Arc::new(ServerState {
        store,
        device_id: device_id.clone(),
        connected_devices: RwLock::new(Vec::new()),
    });

    let app = create_router(state);
    let addr = format!("{}:{}", config.host, config.port);
    
    log::info!("🚀 Starting Cursor Chat Sync Server");
    log::info!("   Device ID: {}", device_id);
    log::info!("   Listening on: http://{}", addr);
    log::info!("   CORS: {}", if config.enable_cors { "enabled" } else { "disabled" });

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    
    // Handle graceful shutdown
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    log::info!("Server stopped");
    Ok(())
}

/// Wait for shutdown signal
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            log::info!("Received Ctrl+C, shutting down...");
        },
        _ = terminate => {
            log::info!("Received terminate signal, shutting down...");
        },
    }
}
