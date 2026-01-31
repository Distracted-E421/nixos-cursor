//! egui dashboard widget for cursor-proxy
//!
//! Provides an embeddable widget for displaying proxy status in egui applications.

use crate::dashboard::{ActivityRecord, DashboardState, ServiceState};

#[cfg(feature = "egui")]
use egui::{Color32, RichText, Ui, Vec2};

/// Proxy dashboard widget for egui integration
#[cfg(feature = "egui")]
pub struct ProxyDashboardWidget {
    show_activity_log: bool,
    show_agent_state: bool,
}

#[cfg(feature = "egui")]
impl ProxyDashboardWidget {
    /// Create a new dashboard widget
    pub fn new() -> Self {
        Self {
            show_activity_log: true,
            show_agent_state: true,
        }
    }

    /// Show the dashboard
    pub fn show(&mut self, ui: &mut Ui, state: &DashboardState) {
        // Header
        ui.heading("Cursor Proxy Dashboard");
        ui.separator();

        // Status row
        ui.horizontal(|ui| {
            self.status_led(ui, "CONN", state.active_connections > 0, Color32::GREEN);
            self.status_led(ui, "UP", state.pool_connections > 0, Color32::BLUE);
            ui.label(format!("Uptime: {}s", state.uptime_secs));
        });

        ui.add_space(8.0);

        // Metrics grid
        egui::Grid::new("proxy_metrics").show(ui, |ui| {
            ui.label("Active:");
            ui.label(RichText::new(state.active_connections.to_string()).strong());
            ui.label("Requests:");
            ui.label(RichText::new(state.total_requests.to_string()).strong());
            ui.end_row();

            ui.label("Errors:");
            ui.label(RichText::new(state.error_count.to_string()).color(Color32::RED));
            ui.label("Streaming:");
            ui.label(RichText::new(state.streaming_count.to_string()).color(Color32::LIGHT_BLUE));
            ui.end_row();
        });

        ui.add_space(8.0);

        // Latency stats
        ui.collapsing("Latency", |ui| {
            egui::Grid::new("latency_grid").show(ui, |ui| {
                ui.label("p50:");
                ui.label(format!("{}ms", state.latency_p50.unwrap_or(0)));
                ui.label("p99:");
                ui.label(format!("{}ms", state.latency_p99.unwrap_or(0)));
                ui.end_row();
            });
        });

        // Traffic stats
        ui.collapsing("Traffic", |ui| {
            ui.horizontal(|ui| {
                ui.label("↓");
                ui.label(format_bytes(state.bytes_in));
                ui.label("↑");
                ui.label(format_bytes(state.bytes_out));
            });
        });

        // Agent state
        if self.show_agent_state && (state.agent_is_thinking || state.agent_current_tool.is_some()) {
            ui.separator();
            ui.horizontal(|ui| {
                if state.agent_is_thinking {
                    ui.label(RichText::new("◉ Thinking").color(Color32::LIGHT_BLUE));
                    if let Some(secs) = state.agent_thinking_secs {
                        ui.label(format!("{}s", secs));
                    }
                }
                if let Some(tool) = &state.agent_current_tool {
                    ui.label(RichText::new(format!("⚙ {}", tool)).color(Color32::YELLOW));
                }
            });
        }

        // Activity log
        if self.show_activity_log {
            ui.separator();
            ui.collapsing("Recent Activity", |ui| {
                for record in &state.recent_activity {
                    self.activity_row(ui, record);
                }
            });
        }
    }

    fn status_led(&self, ui: &mut Ui, label: &str, active: bool, color: Color32) {
        let led_color = if active { color } else { Color32::DARK_GRAY };
        ui.colored_label(led_color, "●");
        ui.label(label);
    }

    fn activity_row(&self, ui: &mut Ui, record: &ActivityRecord) {
        ui.horizontal(|ui| {
            let status_color = match record.status {
                Some(s) if s < 300 => Color32::GREEN,
                Some(s) if s < 400 => Color32::YELLOW,
                Some(_) => Color32::RED,
                None => Color32::GRAY,
            };

            ui.colored_label(status_color, if record.status.map_or(false, |s| s < 300) { "✓" } else { "✗" });
            ui.label(&record.category);
            ui.label(&record.endpoint);
            if let Some(duration) = record.duration_ms {
                ui.label(format!("{}ms", duration));
            }
            if record.is_streaming {
                ui.label(RichText::new("⚡").color(Color32::LIGHT_BLUE));
            }
        });
    }
}

#[cfg(feature = "egui")]
impl Default for ProxyDashboardWidget {
    fn default() -> Self {
        Self::new()
    }
}

/// Format bytes for display
fn format_bytes(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{}B", bytes)
    } else if bytes < 1024 * 1024 {
        format!("{:.1}KB", bytes as f64 / 1024.0)
    } else if bytes < 1024 * 1024 * 1024 {
        format!("{:.1}MB", bytes as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.2}GB", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}

// Non-egui stubs for when feature is disabled
#[cfg(not(feature = "egui"))]
pub struct ProxyDashboardWidget;

#[cfg(not(feature = "egui"))]
impl ProxyDashboardWidget {
    pub fn new() -> Self {
        Self
    }
}
