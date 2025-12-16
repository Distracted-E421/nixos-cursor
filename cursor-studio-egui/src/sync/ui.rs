//! Sync Status UI Panel
//!
//! egui panel showing real-time sync daemon status.

use eframe::egui::{self, Color32, RichText, Ui, Vec2};
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use super::pipe_client::{
    AsyncPipeClient, ClientError, DaemonCommand, DaemonEvent, DaemonResponse, DaemonStatus,
    PipeClient, SyncStats,
};

/// Sync status panel state
pub struct SyncStatusPanel {
    /// Sync client (blocking)
    client: PipeClient,

    /// Async client for background operations
    async_client: Option<AsyncPipeClient>,

    /// Event receiver from async client
    event_rx: Option<Receiver<DaemonEvent>>,

    /// Last fetched status
    status: Option<DaemonStatus>,

    /// Last fetched stats
    stats: Option<SyncStats>,

    /// Last error message
    last_error: Option<String>,

    /// Whether daemon is connected
    daemon_connected: bool,

    /// Last refresh time
    last_refresh: Instant,

    /// Auto-refresh interval
    refresh_interval: Duration,

    /// Whether to auto-refresh
    auto_refresh: bool,

    /// Pending sync request
    sync_pending: bool,
}

impl Default for SyncStatusPanel {
    fn default() -> Self {
        Self::new()
    }
}

impl SyncStatusPanel {
    /// Create a new sync status panel
    pub fn new() -> Self {
        let client = PipeClient::new();
        let daemon_connected = client.is_daemon_running();

        Self {
            client,
            async_client: None,
            event_rx: None,
            status: None,
            stats: None,
            last_error: None,
            daemon_connected,
            last_refresh: Instant::now() - Duration::from_secs(60), // Force immediate refresh
            refresh_interval: Duration::from_secs(5),
            auto_refresh: true,
            sync_pending: false,
        }
    }

    /// Check for daemon and refresh status
    pub fn refresh(&mut self) {
        self.daemon_connected = self.client.is_daemon_running();

        if !self.daemon_connected {
            self.status = None;
            self.stats = None;
            self.last_error = Some("Daemon not running".to_string());
            return;
        }

        // Fetch status
        match self.client.status() {
            Ok(status) => {
                self.status = Some(status);
                self.last_error = None;
            }
            Err(e) => {
                self.last_error = Some(e.to_string());
            }
        }

        // Fetch stats
        match self.client.stats() {
            Ok(stats) => {
                self.stats = Some(stats);
            }
            Err(e) => {
                if self.last_error.is_none() {
                    self.last_error = Some(e.to_string());
                }
            }
        }

        self.last_refresh = Instant::now();
    }

    /// Trigger a sync operation
    pub fn trigger_sync(&mut self) {
        self.sync_pending = true;

        match self.client.sync_all() {
            Ok(response) => {
                if response.ok {
                    self.last_error = None;
                } else {
                    self.last_error = response.error;
                }
                self.sync_pending = false;
                self.refresh(); // Refresh status after sync
            }
            Err(e) => {
                self.last_error = Some(e.to_string());
                self.sync_pending = false;
            }
        }
    }

    /// Render the sync status panel
    pub fn ui(&mut self, ui: &mut Ui) {
        // Auto-refresh if enabled
        if self.auto_refresh && self.last_refresh.elapsed() > self.refresh_interval {
            self.refresh();
        }

        ui.heading("🔄 Sync Daemon");
        ui.separator();

        // Connection status
        ui.horizontal(|ui| {
            let (icon, color, text) = if self.daemon_connected {
                ("●", Color32::from_rgb(100, 200, 100), "Connected")
            } else {
                ("○", Color32::from_rgb(200, 100, 100), "Disconnected")
            };

            ui.label(RichText::new(icon).color(color).size(16.0));
            ui.label(text);

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("⟳ Refresh").clicked() {
                    self.refresh();
                }
            });
        });

        ui.add_space(8.0);

        // Status section
        if let Some(ref status) = self.status {
            ui.group(|ui| {
                ui.label(RichText::new("Status").strong());

                egui::Grid::new("sync_status_grid")
                    .num_columns(2)
                    .spacing([20.0, 4.0])
                    .show(ui, |ui| {
                        ui.label("Syncing:");
                        ui.label(if status.syncing {
                            RichText::new("Yes").color(Color32::YELLOW)
                        } else {
                            RichText::new("No").color(Color32::GRAY)
                        });
                        ui.end_row();

                        ui.label("Total Syncs:");
                        ui.label(format!("{}", status.total_syncs));
                        ui.end_row();

                        ui.label("Workspaces:");
                        ui.label(format!("{}", status.workspaces_synced));
                        ui.end_row();

                        ui.label("Last Sync:");
                        ui.label(
                            status
                                .last_sync
                                .as_deref()
                                .unwrap_or("Never"),
                        );
                        ui.end_row();
                    });
            });
        }

        ui.add_space(8.0);

        // Stats section
        if let Some(ref stats) = self.stats {
            ui.group(|ui| {
                ui.label(RichText::new("Statistics").strong());

                egui::Grid::new("sync_stats_grid")
                    .num_columns(2)
                    .spacing([20.0, 4.0])
                    .show(ui, |ui| {
                        ui.label("Messages Synced:");
                        ui.label(format!("{}", stats.messages_synced));
                        ui.end_row();

                        ui.label("Conversations:");
                        ui.label(format!("{}", stats.conversations_synced));
                        ui.end_row();

                        ui.label("Success Rate:");
                        let rate = if stats.total_syncs > 0 {
                            (stats.successful_syncs as f64 / stats.total_syncs as f64) * 100.0
                        } else {
                            0.0
                        };
                        let rate_color = if rate >= 90.0 {
                            Color32::from_rgb(100, 200, 100)
                        } else if rate >= 70.0 {
                            Color32::YELLOW
                        } else {
                            Color32::from_rgb(200, 100, 100)
                        };
                        ui.label(RichText::new(format!("{:.1}%", rate)).color(rate_color));
                        ui.end_row();

                        ui.label("Avg Duration:");
                        ui.label(format!("{:.0}ms", stats.avg_duration_ms));
                        ui.end_row();
                    });
            });
        }

        ui.add_space(8.0);

        // Actions
        ui.horizontal(|ui| {
            let sync_btn = ui.add_enabled(
                self.daemon_connected && !self.sync_pending,
                egui::Button::new("🔄 Sync Now"),
            );
            if sync_btn.clicked() {
                self.trigger_sync();
            }

            ui.checkbox(&mut self.auto_refresh, "Auto-refresh");
        });

        // Error display
        if let Some(ref error) = self.last_error {
            ui.add_space(8.0);
            ui.group(|ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new("⚠").color(Color32::YELLOW).size(16.0));
                    ui.label(RichText::new(error).color(Color32::from_rgb(255, 200, 100)));
                });
            });
        }

        // Footer
        ui.add_space(8.0);
        ui.separator();
        ui.horizontal(|ui| {
            ui.label(
                RichText::new(format!(
                    "Last updated: {:.1}s ago",
                    self.last_refresh.elapsed().as_secs_f32()
                ))
                .small()
                .color(Color32::GRAY),
            );
        });
    }

    /// Render as a collapsible side panel
    pub fn side_panel(&mut self, ctx: &egui::Context) {
        egui::SidePanel::right("sync_panel")
            .default_width(250.0)
            .show(ctx, |ui| {
                self.ui(ui);
            });
    }

    /// Render as a window
    pub fn window(&mut self, ctx: &egui::Context, open: &mut bool) {
        egui::Window::new("Sync Status")
            .open(open)
            .default_size(Vec2::new(300.0, 400.0))
            .show(ctx, |ui| {
                self.ui(ui);
            });
    }
}

/// Compact sync status indicator for toolbar
pub struct SyncStatusIndicator {
    client: PipeClient,
    connected: bool,
    syncing: bool,
    last_check: Instant,
}

impl Default for SyncStatusIndicator {
    fn default() -> Self {
        Self::new()
    }
}

impl SyncStatusIndicator {
    pub fn new() -> Self {
        Self {
            client: PipeClient::new(),
            connected: false,
            syncing: false,
            last_check: Instant::now() - Duration::from_secs(60),
        }
    }

    /// Quick status check (every 2 seconds)
    pub fn check(&mut self) {
        if self.last_check.elapsed() > Duration::from_secs(2) {
            self.connected = self.client.is_daemon_running();

            if self.connected {
                if let Ok(status) = self.client.status() {
                    self.syncing = status.syncing;
                }
            }

            self.last_check = Instant::now();
        }
    }

    /// Render compact indicator
    pub fn ui(&mut self, ui: &mut Ui) -> egui::Response {
        self.check();

        let (icon, color, tooltip) = if !self.connected {
            ("○", Color32::from_rgb(150, 150, 150), "Sync daemon disconnected")
        } else if self.syncing {
            ("◐", Color32::YELLOW, "Syncing...")
        } else {
            ("●", Color32::from_rgb(100, 200, 100), "Sync daemon connected")
        };

        ui.label(RichText::new(icon).color(color).size(14.0))
            .on_hover_text(tooltip)
    }
}
