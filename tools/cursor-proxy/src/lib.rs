//! Cursor Proxy Library
//!
//! Provides components for integrating the proxy dashboard into other applications.
//!
//! # Features
//!
//! - `egui` - Enables egui dashboard widget for GUI integration
//!
//! # Usage
//!
//! ```rust,ignore
//! use cursor_proxy::dashboard::DashboardState;
//! use cursor_proxy::events::{EventBroadcaster, ProxyEvent};
//! use cursor_proxy::ipc::IpcClient;
//!
//! // Connect to running proxy
//! let client = IpcClient::new();
//! let mut stream = client.connect().await?;
//!
//! // Receive events
//! while let Some(event) = stream.next().await {
//!     // Process event...
//! }
//! ```
//!
//! # egui Integration
//!
//! ```rust,ignore
//! use cursor_proxy::dashboard_egui::ProxyDashboardWidget;
//!
//! // In your egui app
//! fn show_dashboard(ui: &mut egui::Ui, state: &DashboardState) {
//!     let widget = ProxyDashboardWidget::new();
//!     widget.show(ui, state);
//! }
//! ```

mod capture;
mod cert;
mod config;
mod dns;
mod error;
mod iptables;
mod pool;
mod proxy;

// Public API
pub mod dashboard;
pub mod dashboard_egui;
pub mod events;
pub mod injection;
pub mod ipc;

// Re-exports for convenience
pub use dashboard::{Dashboard, DashboardState, ActivityRecord, ServiceState};
pub use events::{EventBroadcaster, EventReceiver, ProxyEvent, ServiceCategory};
pub use ipc::{IpcClient, IpcEventStream};

#[cfg(feature = "egui")]
pub use dashboard_egui::ProxyDashboardWidget;

