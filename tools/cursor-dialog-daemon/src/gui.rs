//! GUI Rendering using egui/eframe
//!
//! Renders dialogs with a modern, native-ish look.

use eframe::egui::{self, Color32, RichText, Rounding, Stroke, Vec2};
use std::sync::Arc;
use tokio::sync::{oneshot, RwLock};
use tracing::info;

use crate::dialog::{ActiveDialog, ActiveToast, DialogManager, DialogRequest, DialogResponse, DialogStateVariant, DialogType, ToastHistoryEntry, ToastLevel};
use crate::dbus_interface::ChoiceOption;
use std::time::{Duration, Instant};

/// Display-only toast data (for rendering without holding sender)
#[derive(Debug, Clone)]
struct ToastDisplay {
    id: String,
    message: String,
    level: ToastLevel,
    started_at: Instant,
    duration: Duration,
}

impl ToastDisplay {
    fn time_remaining_ratio(&self) -> f32 {
        if self.duration.is_zero() {
            return 1.0;
        }
        let elapsed = self.started_at.elapsed().as_secs_f32();
        let total = self.duration.as_secs_f32();
        (1.0 - elapsed / total).max(0.0)
    }
}

/// GUI Application state
pub struct DialogApp {
    /// Dialog manager (shared with D-Bus interface)
    manager: Arc<RwLock<DialogManager>>,
    /// Channel to receive new dialog requests (sync version for GUI)
    dialog_rx: std::sync::mpsc::Receiver<(DialogRequest, oneshot::Sender<DialogResponse>)>,
    /// Whether we should close after completing current dialog
    close_on_complete: bool,
    /// Theme colors
    theme: Theme,
    /// Whether toast sidebar is expanded
    sidebar_expanded: bool,
}

struct Theme {
    bg_primary: Color32,
    bg_secondary: Color32,
    fg_primary: Color32,
    fg_secondary: Color32,
    accent: Color32,
    accent_hover: Color32,
    danger: Color32,
    success: Color32,
    border: Color32,
}

impl Default for Theme {
    fn default() -> Self {
        // Dark theme inspired by Cursor's aesthetic
        Self {
            bg_primary: Color32::from_rgb(24, 24, 27),      // zinc-900
            bg_secondary: Color32::from_rgb(39, 39, 42),    // zinc-800
            fg_primary: Color32::from_rgb(250, 250, 250),   // zinc-50
            fg_secondary: Color32::from_rgb(161, 161, 170), // zinc-400
            accent: Color32::from_rgb(59, 130, 246),        // blue-500
            accent_hover: Color32::from_rgb(96, 165, 250),  // blue-400
            danger: Color32::from_rgb(239, 68, 68),         // red-500
            success: Color32::from_rgb(34, 197, 94),        // green-500
            border: Color32::from_rgb(63, 63, 70),          // zinc-700
        }
    }
}

impl DialogApp {
    pub fn new(
        _cc: &eframe::CreationContext<'_>,
        manager: Arc<RwLock<DialogManager>>,
        dialog_rx: std::sync::mpsc::Receiver<(DialogRequest, oneshot::Sender<DialogResponse>)>,
    ) -> Self {
        Self {
            manager,
            dialog_rx,
            close_on_complete: false,
            theme: Theme::default(),
            sidebar_expanded: false,
        }
    }

    /// Play a notification sound based on toast level
    fn play_notification_sound(level: ToastLevel) {
        // Try to play system notification sound
        // This runs async to not block the UI
        std::thread::spawn(move || {
            // Different sound based on level
            let sound = match level {
                ToastLevel::Error => "/usr/share/sounds/freedesktop/stereo/dialog-error.oga",
                ToastLevel::Warning => "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
                ToastLevel::Success => "/usr/share/sounds/freedesktop/stereo/complete.oga",
                ToastLevel::Info => "/usr/share/sounds/freedesktop/stereo/message.oga",
            };
            
            // Try paplay (PulseAudio) first
            let _ = std::process::Command::new("paplay")
                .arg(sound)
                .spawn()
                .or_else(|_| {
                    // Fallback: try pw-play (PipeWire)
                    std::process::Command::new("pw-play").arg(sound).spawn()
                })
                .or_else(|_| {
                    // Final fallback: console bell
                    print!("\x07");
                    std::io::Write::flush(&mut std::io::stdout())
                        .map(|_| std::process::Command::new("true").spawn().unwrap())
                });
        });
    }
}

impl eframe::App for DialogApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Check for new dialog requests (using sync channel)
        while let Ok((request, response_tx)) = self.dialog_rx.try_recv() {
            info!("Received dialog request: {}", request.id);
            
            // Request window attention for blocking dialogs (not toasts)
            if !matches!(request.dialog_type, DialogType::Toast { .. }) {
                ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
                ctx.send_viewport_cmd(egui::ViewportCommand::RequestUserAttention(
                    egui::UserAttentionType::Critical
                ));
            }
            
            let mut manager = self.manager.blocking_write();
            manager.enqueue(request, response_tx);
        }

        // Check for timeouts
        {
            let mut manager = self.manager.blocking_write();
            manager.check_timeouts();
        }

        // Set up custom styling
        let mut style = (*ctx.style()).clone();
        style.visuals.dark_mode = true;
        style.visuals.override_text_color = Some(self.theme.fg_primary);
        style.visuals.widgets.noninteractive.bg_fill = self.theme.bg_secondary;
        style.visuals.widgets.inactive.bg_fill = self.theme.bg_secondary;
        style.visuals.widgets.hovered.bg_fill = self.theme.accent;
        style.visuals.widgets.active.bg_fill = self.theme.accent_hover;
        style.visuals.selection.bg_fill = self.theme.accent.linear_multiply(0.5);
        ctx.set_style(style);

        // Render the active dialog
        let mut manager = self.manager.blocking_write();
        
        if manager.active.is_none() {
            // No active dialog - show idle state
            egui::CentralPanel::default()
                .frame(egui::Frame::none().fill(self.theme.bg_primary))
                .show(ctx, |ui| {
                    ui.centered_and_justified(|ui| {
                        ui.label(
                            RichText::new("Waiting for dialog requests...")
                                .color(self.theme.fg_secondary)
                                .size(14.0),
                        );
                    });
                });
            
            // Render toasts even when idle
            // Extract display data to avoid borrow conflict
            let toast_displays: Vec<_> = manager.toasts.iter().map(|t| ToastDisplay {
                id: t.id.clone(),
                message: t.message.clone(),
                level: t.level,
                started_at: t.started_at,
                duration: t.duration,
            }).collect();
            let history = manager.toast_history.clone();
            let unread = manager.unread_count();
            drop(manager);
            
            self.render_toasts_and_sidebar(ctx, &toast_displays, &history, unread);
            ctx.request_repaint();
            return;
        }

        // We have an active dialog - render it
        let should_complete = egui::CentralPanel::default()
            .frame(egui::Frame::none().fill(self.theme.bg_primary).inner_margin(20.0))
            .show(ctx, |ui| {
                let active = manager.active.as_mut().unwrap();
                self.render_dialog(ui, active)
            })
            .inner;

        if let Some(selection) = should_complete {
            if let Some(active) = manager.active.take() {
                active.complete(selection);
                manager.next();
            }
        }

        // Render toasts in top-right corner (overlay)
        // Extract display data to avoid borrow conflict
        let toast_displays: Vec<_> = manager.toasts.iter().map(|t| ToastDisplay {
            id: t.id.clone(),
            message: t.message.clone(),
            level: t.level,
            started_at: t.started_at,
            duration: t.duration,
        }).collect();
        let history = manager.toast_history.clone();
        let unread = manager.unread_count();
        drop(manager);
        
        self.render_toasts_and_sidebar(ctx, &toast_displays, &history, unread);

        // Request repaint for smooth animations
        ctx.request_repaint();
    }
}

impl DialogApp {
    /// Render toast notifications and sidebar (with extracted data to avoid borrow conflicts)
    fn render_toasts_and_sidebar(&mut self, ctx: &egui::Context, toasts: &[ToastDisplay], history: &[ToastHistoryEntry], unread: usize) {
        // Play sounds for new toasts
        for toast in toasts {
            // Check if this is a new toast we haven't played sound for
            // We use a simple heuristic: if toast just started (< 100ms old), play sound
            if toast.started_at.elapsed().as_millis() < 100 {
                Self::play_notification_sound(toast.level);
            }
        }

        // Render sidebar toggle button (only when sidebar is closed)
        if !self.sidebar_expanded {
            let button_text = if unread > 0 {
                format!("🔔 {}", unread)
            } else {
                "📋".to_string()
            };
            
            egui::Area::new(egui::Id::new("sidebar_toggle"))
                .fixed_pos(egui::pos2(ctx.screen_rect().right() - 40.0, 10.0))
                .order(egui::Order::Foreground)
                .show(ctx, |ui| {
                    if ui.add(
                        egui::Button::new(RichText::new(&button_text).size(16.0))
                            .fill(if unread > 0 { self.theme.accent } else { self.theme.bg_secondary })
                            .rounding(Rounding::same(8.0))
                            .min_size(Vec2::new(32.0, 32.0))
                    ).clicked() {
                        self.sidebar_expanded = true;
                        let mut manager = self.manager.blocking_write();
                        manager.mark_all_read();
                    }
                });
        }

        // Render expanded sidebar
        if self.sidebar_expanded {
            self.render_toast_sidebar(ctx, history);
        }

        // Render active toasts (floating)
        if !toasts.is_empty() {
            egui::Area::new(egui::Id::new("toast_area"))
                .fixed_pos(egui::pos2(ctx.screen_rect().right() - 320.0, 50.0))
                .order(egui::Order::Foreground)
                .show(ctx, |ui| {
                    ui.set_width(300.0);
                    
                    let mut to_dismiss: Vec<String> = Vec::new();
                    
                    for toast in toasts {
                        self.render_toast(ui, toast, &mut to_dismiss);
                        ui.add_space(8.0);
                    }
                    
                    // Dismiss clicked toasts
                    if !to_dismiss.is_empty() {
                        let mut manager = self.manager.blocking_write();
                        for id in to_dismiss {
                            manager.dismiss_toast(&id);
                        }
                    }
                });
        }
    }

    /// Render the toast history sidebar
    fn render_toast_sidebar(&mut self, ctx: &egui::Context, history: &[ToastHistoryEntry]) {
        let mut clear_history = false;
        let mut entries_to_remove: Vec<String> = Vec::new();

        egui::SidePanel::right("toast_sidebar")
            .resizable(true)
            .default_width(280.0)
            .min_width(200.0)
            .max_width(400.0)
            .frame(egui::Frame::none()
                .fill(Color32::from_rgba_unmultiplied(24, 24, 27, 240)) // Semi-transparent
                .stroke(Stroke::new(1.0, self.theme.border)))
            .show(ctx, |ui| {
                ui.add_space(8.0);
                
                // Header
                ui.horizontal(|ui| {
                    ui.label(RichText::new("Notifications").size(16.0).strong());
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.add(
                            egui::Button::new(RichText::new("×").size(16.0))
                                .fill(Color32::TRANSPARENT)
                                .frame(false)
                        ).clicked() {
                            self.sidebar_expanded = false;
                        }
                        
                        if !history.is_empty() {
                            if ui.add(
                                egui::Button::new(RichText::new("Clear").size(11.0))
                                    .fill(self.theme.bg_secondary)
                                    .rounding(Rounding::same(4.0))
                            ).clicked() {
                                clear_history = true;
                            }
                        }
                    });
                });
                
                ui.separator();
                ui.add_space(4.0);

                // Scrollable notification list
                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        if history.is_empty() {
                            ui.centered_and_justified(|ui| {
                                ui.label(
                                    RichText::new("No notifications")
                                        .color(self.theme.fg_secondary)
                                        .size(13.0)
                                );
                            });
                        } else {
                            for entry in history {
                                let elapsed = entry.timestamp.elapsed();
                                let time_str = if elapsed.as_secs() < 60 {
                                    format!("{}s ago", elapsed.as_secs())
                                } else if elapsed.as_secs() < 3600 {
                                    format!("{}m ago", elapsed.as_secs() / 60)
                                } else {
                                    format!("{}h ago", elapsed.as_secs() / 3600)
                                };

                                let (icon, color) = match entry.level {
                                    ToastLevel::Success => ("✓", self.theme.success),
                                    ToastLevel::Info => ("ℹ", self.theme.accent),
                                    ToastLevel::Warning => ("⚠", Color32::from_rgb(245, 158, 11)),
                                    ToastLevel::Error => ("✗", self.theme.danger),
                                };

                                egui::Frame::none()
                                    .fill(self.theme.bg_secondary)
                                    .rounding(Rounding::same(6.0))
                                    .inner_margin(8.0)
                                    .show(ui, |ui| {
                                        ui.horizontal(|ui| {
                                            ui.label(RichText::new(icon).color(color).size(14.0));
                                            ui.vertical(|ui| {
                                                ui.set_width(ui.available_width() - 30.0);
                                                ui.label(
                                                    RichText::new(&entry.message)
                                                        .size(12.0)
                                                        .color(self.theme.fg_primary)
                                                );
                                                ui.label(
                                                    RichText::new(&time_str)
                                                        .size(10.0)
                                                        .color(self.theme.fg_secondary)
                                                );
                                            });
                                            if ui.add(
                                                egui::Button::new(RichText::new("×").size(12.0).color(self.theme.fg_secondary))
                                                    .fill(Color32::TRANSPARENT)
                                                    .frame(false)
                                            ).clicked() {
                                                entries_to_remove.push(entry.id.clone());
                                            }
                                        });
                                    });
                                ui.add_space(4.0);
                            }
                        }
                    });
            });

        // Apply changes to manager after UI rendering
        if clear_history || !entries_to_remove.is_empty() {
            let mut manager = self.manager.blocking_write();
            if clear_history {
                manager.clear_history();
            }
            for id in entries_to_remove {
                manager.remove_history_entry(&id);
            }
        }
    }

    /// Render a single toast
    fn render_toast(&self, ui: &mut egui::Ui, toast: &ToastDisplay, to_dismiss: &mut Vec<String>) {
        let (bg_color, icon, border_color) = match toast.level {
            ToastLevel::Info => (
                Color32::from_rgb(30, 41, 59),    // slate-800
                "ℹ️",
                self.theme.accent,
            ),
            ToastLevel::Success => (
                Color32::from_rgb(20, 83, 45),    // green-900
                "✓",
                self.theme.success,
            ),
            ToastLevel::Warning => (
                Color32::from_rgb(120, 53, 15),   // amber-900
                "⚠",
                Color32::from_rgb(245, 158, 11), // amber-500
            ),
            ToastLevel::Error => (
                Color32::from_rgb(127, 29, 29),   // red-900
                "✗",
                self.theme.danger,
            ),
        };

        egui::Frame::none()
            .fill(bg_color)
            .rounding(Rounding::same(8.0))
            .stroke(Stroke::new(1.0, border_color))
            .inner_margin(12.0)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    // Icon
                    ui.label(RichText::new(icon).size(16.0));
                    
                    // Message
                    ui.vertical(|ui| {
                        ui.set_width(220.0);
                        ui.label(
                            RichText::new(&toast.message)
                                .size(13.0)
                                .color(self.theme.fg_primary),
                        );
                    });
                    
                    // Dismiss button
                    if ui.add(
                        egui::Button::new(RichText::new("×").size(14.0).color(self.theme.fg_secondary))
                            .fill(Color32::TRANSPARENT)
                            .frame(false)
                    ).clicked() {
                        to_dismiss.push(toast.id.clone());
                    }
                });

                // Progress bar for auto-dismiss
                if !toast.duration.is_zero() {
                    ui.add_space(6.0);
                    let ratio = toast.time_remaining_ratio();
                    let bar_rect = ui.available_rect_before_wrap();
                    let progress_rect = egui::Rect::from_min_size(
                        bar_rect.min,
                        Vec2::new(bar_rect.width() * ratio, 2.0),
                    );
                    ui.painter().rect_filled(progress_rect, Rounding::same(1.0), border_color.linear_multiply(0.7));
                }
            });
    }

    fn render_dialog(&self, ui: &mut egui::Ui, active: &mut ActiveDialog) -> Option<serde_json::Value> {
        // Title
        ui.add_space(8.0);
        ui.label(
            RichText::new(&active.request.title)
                .size(20.0)
                .color(self.theme.fg_primary)
                .strong(),
        );
        ui.add_space(12.0);

        // Prompt (process escape sequences for multi-line support)
        let prompt_text = process_escape_sequences(&active.request.prompt);
        ui.label(
            RichText::new(&prompt_text)
                .size(14.0)
                .color(self.theme.fg_secondary),
        );
        ui.add_space(16.0);

        // Timeout indicator with pause button
        if let Some(ratio) = active.time_remaining_ratio() {
            ui.horizontal(|ui| {
                // Pause/Resume button
                let pause_text = if active.is_paused() { "▶ Resume" } else { "⏸ Pause" };
                let pause_color = if active.is_paused() { 
                    self.theme.success 
                } else { 
                    self.theme.fg_secondary 
                };
                
                if ui.add(
                    egui::Button::new(RichText::new(pause_text).size(11.0).color(pause_color))
                        .fill(self.theme.bg_secondary)
                        .rounding(Rounding::same(4.0))
                ).clicked() {
                    active.toggle_pause();
                }

                ui.add_space(8.0);

                // Timer bar
                let timeout_color = if active.is_paused() {
                    self.theme.success  // Green when paused
                } else if ratio > 0.3 {
                    self.theme.accent
                } else {
                    self.theme.danger
                };
                
                let remaining_rect = ui.available_rect_before_wrap();
                let bar_height = 6.0;
                let bar_rect = egui::Rect::from_min_size(
                    egui::pos2(remaining_rect.min.x, remaining_rect.min.y + 8.0),
                    Vec2::new(remaining_rect.width() * ratio, bar_height),
                );
                let bg_rect = egui::Rect::from_min_size(
                    egui::pos2(remaining_rect.min.x, remaining_rect.min.y + 8.0),
                    Vec2::new(remaining_rect.width(), bar_height),
                );
                ui.painter().rect_filled(bg_rect, Rounding::same(3.0), self.theme.bg_secondary);
                ui.painter().rect_filled(bar_rect, Rounding::same(3.0), timeout_color);
                
                if active.is_paused() {
                    ui.painter().text(
                        egui::pos2(remaining_rect.center().x, remaining_rect.min.y + 8.0 + bar_height / 2.0),
                        egui::Align2::CENTER_CENTER,
                        "PAUSED",
                        egui::FontId::proportional(9.0),
                        self.theme.fg_primary,
                    );
                }
            });
            ui.add_space(8.0);
        }

        ui.separator();
        ui.add_space(12.0);

        // Clone the dialog type to avoid borrow conflict
        let dialog_type = active.request.dialog_type.clone();
        
        // Dialog-specific content
        let selection = match dialog_type {
            DialogType::Choice { ref options, allow_multiple, .. } => {
                self.render_choice(ui, active, options, allow_multiple)
            }
            DialogType::TextInput { ref placeholder, multiline, ref validation, .. } => {
                self.render_text_input(ui, active, placeholder, multiline, validation.as_deref())
            }
            DialogType::Confirmation { ref yes_label, ref no_label, .. } => {
                self.render_confirmation(ui, active, yes_label, no_label)
            }
            DialogType::Slider { min, max, step, ref unit, .. } => {
                self.render_slider(ui, active, min, max, step, unit.as_deref())
            }
            DialogType::Progress { progress } => {
                self.render_progress(ui, progress);
                None
            }
            DialogType::FilePicker { ref mode, ref filters, ref default_path } => {
                self.render_file_picker(ui, mode, filters, default_path.as_deref())
            }
            DialogType::Toast { .. } => {
                // Toasts are rendered separately, not as blocking dialogs
                // If we get here, just complete immediately
                Some(serde_json::json!("toast_shown"))
            }
        };

        // If selection was made, it will be returned. But first, show comment field
        // (not for progress dialogs and toasts)
        if !matches!(dialog_type, DialogType::Progress { .. } | DialogType::Toast { .. }) && selection.is_none() {
            ui.add_space(12.0);
            self.render_comment_field(ui, active);
        }

        selection
    }

    /// Render the collapsible comment field
    fn render_comment_field(&self, ui: &mut egui::Ui, active: &mut ActiveDialog) {
        let header_text = if active.state.comment_expanded {
            "▼ Add comment (optional)"
        } else {
            "▶ Add comment (optional)"
        };

        // Collapsible header
        if ui.add(
            egui::Button::new(
                RichText::new(header_text)
                    .size(11.0)
                    .color(self.theme.fg_secondary)
            )
            .fill(Color32::TRANSPARENT)
            .frame(false)
        ).clicked() {
            active.state.comment_expanded = !active.state.comment_expanded;
            // Auto-pause timer when expanding comment
            if active.state.comment_expanded && !active.is_paused() {
                active.toggle_pause();
            }
        }

        if active.state.comment_expanded {
            ui.add_space(4.0);
            
            // Comment text area
            let comment = &mut active.state.comment;
            let text_edit = egui::TextEdit::multiline(comment)
                .hint_text("Add context, clarification, or nuance that the options don't capture...")
                .desired_rows(3)
                .desired_width(f32::INFINITY)
                .font(egui::TextStyle::Small);
            
            ui.add(text_edit);

            // Character count
            ui.horizontal(|ui| {
                ui.label(
                    RichText::new(format!("{} chars", comment.len()))
                        .size(10.0)
                        .color(self.theme.fg_secondary)
                );
                
                // Clear button if has content
                if !comment.is_empty() {
                    if ui.add(
                        egui::Button::new(RichText::new("Clear").size(10.0))
                            .fill(Color32::TRANSPARENT)
                    ).clicked() {
                        comment.clear();
                    }
                }
            });
        }
    }

    fn render_choice(
        &self,
        ui: &mut egui::Ui,
        active: &mut ActiveDialog,
        options: &[ChoiceOption],
        allow_multiple: bool,
    ) -> Option<serde_json::Value> {
        let DialogStateVariant::Choice { selected } = &mut active.state.variant else {
            return None;
        };

        for option in options {
            let is_selected = selected.contains(&option.value);
            
            let response = ui.add(
                egui::Button::new(
                    RichText::new(format!(
                        "{} {}",
                        if is_selected { "●" } else { "○" },
                        &option.label
                    ))
                    .size(14.0),
                )
                .fill(if is_selected {
                    self.theme.accent.linear_multiply(0.3)
                } else {
                    self.theme.bg_secondary
                })
                .stroke(Stroke::new(
                    1.0,
                    if is_selected {
                        self.theme.accent
                    } else {
                        self.theme.border
                    },
                ))
                .rounding(Rounding::same(6.0))
                .min_size(Vec2::new(ui.available_width(), 40.0)),
            );

            if let Some(desc) = &option.description {
                ui.indent("desc", |ui| {
                    ui.label(
                        RichText::new(desc)
                            .size(12.0)
                            .color(self.theme.fg_secondary),
                    );
                });
            }

            ui.add_space(4.0);

            if response.clicked() {
                if allow_multiple {
                    if is_selected {
                        selected.retain(|s| s != &option.value);
                    } else {
                        selected.push(option.value.clone());
                    }
                } else {
                    *selected = vec![option.value.clone()];
                }
            }
        }

        ui.add_space(16.0);

        // Confirm button
        ui.horizontal(|ui| {
            if ui
                .add(
                    egui::Button::new(RichText::new("Cancel").size(14.0))
                        .fill(self.theme.bg_secondary)
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
            {
                return Some(serde_json::Value::Null); // Will trigger cancel
            }

            ui.add_space(8.0);

            let can_confirm = !selected.is_empty();
            if ui
                .add_enabled(
                    can_confirm,
                    egui::Button::new(RichText::new("Confirm").size(14.0))
                        .fill(if can_confirm {
                            self.theme.accent
                        } else {
                            self.theme.bg_secondary
                        })
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
            {
                if allow_multiple {
                    return Some(serde_json::json!(selected.clone()));
                } else {
                    return Some(serde_json::json!(selected.first().cloned()));
                }
            }

            None
        })
        .inner
    }

    fn render_text_input(
        &self,
        ui: &mut egui::Ui,
        active: &mut ActiveDialog,
        placeholder: &str,
        multiline: bool,
        validation: Option<&str>,
    ) -> Option<serde_json::Value> {
        let DialogStateVariant::TextInput { text, valid } = &mut active.state.variant else {
            return None;
        };

        let text_edit = if multiline {
            egui::TextEdit::multiline(text)
                .hint_text(placeholder)
                .desired_rows(5)
                .desired_width(f32::INFINITY)
        } else {
            egui::TextEdit::singleline(text)
                .hint_text(placeholder)
                .desired_width(f32::INFINITY)
        };

        let response = ui.add(text_edit);

        // Validate if regex provided
        if let Some(regex_str) = validation {
            if let Ok(re) = regex::Regex::new(regex_str) {
                *valid = re.is_match(text);
                if !*valid && !text.is_empty() {
                    ui.label(
                        RichText::new("Invalid input format")
                            .size(12.0)
                            .color(self.theme.danger),
                    );
                }
            }
        }

        ui.add_space(16.0);

        // Buttons
        ui.horizontal(|ui| {
            if ui
                .add(
                    egui::Button::new("Cancel")
                        .fill(self.theme.bg_secondary)
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
            {
                return Some(serde_json::Value::Null);
            }

            ui.add_space(8.0);

            let can_submit = *valid && !text.is_empty();
            if ui
                .add_enabled(
                    can_submit,
                    egui::Button::new("Submit")
                        .fill(if can_submit {
                            self.theme.accent
                        } else {
                            self.theme.bg_secondary
                        })
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
                || (response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) && !multiline)
            {
                return Some(serde_json::json!(text.clone()));
            }

            None
        })
        .inner
    }

    fn render_confirmation(
        &self,
        ui: &mut egui::Ui,
        active: &mut ActiveDialog,
        yes_label: &str,
        no_label: &str,
    ) -> Option<serde_json::Value> {
        ui.horizontal(|ui| {
            if ui
                .add(
                    egui::Button::new(RichText::new(no_label).size(14.0))
                        .fill(self.theme.bg_secondary)
                        .min_size(Vec2::new(120.0, 44.0)),
                )
                .clicked()
            {
                return Some(serde_json::json!(false));
            }

            ui.add_space(12.0);

            if ui
                .add(
                    egui::Button::new(RichText::new(yes_label).size(14.0))
                        .fill(self.theme.accent)
                        .min_size(Vec2::new(120.0, 44.0)),
                )
                .clicked()
            {
                return Some(serde_json::json!(true));
            }

            None
        })
        .inner
    }

    fn render_slider(
        &self,
        ui: &mut egui::Ui,
        active: &mut ActiveDialog,
        min: f64,
        max: f64,
        step: f64,
        unit: Option<&str>,
    ) -> Option<serde_json::Value> {
        let DialogStateVariant::Slider { value } = &mut active.state.variant else {
            return None;
        };

        // Value display
        ui.horizontal(|ui| {
            ui.label(
                RichText::new(format!("{:.1}{}", value, unit.unwrap_or("")))
                    .size(24.0)
                    .color(self.theme.accent)
                    .strong(),
            );
        });

        ui.add_space(12.0);

        // Slider
        let mut value_f32 = *value as f32;
        let slider = egui::Slider::new(&mut value_f32, (min as f32)..=(max as f32))
            .step_by(step)
            .show_value(false);
        
        if ui.add(slider).changed() {
            *value = value_f32 as f64;
        }

        // Min/Max labels
        ui.horizontal(|ui| {
            ui.label(
                RichText::new(format!("{}{}", min, unit.unwrap_or("")))
                    .size(11.0)
                    .color(self.theme.fg_secondary),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(
                    RichText::new(format!("{}{}", max, unit.unwrap_or("")))
                        .size(11.0)
                        .color(self.theme.fg_secondary),
                );
            });
        });

        ui.add_space(16.0);

        // Buttons
        ui.horizontal(|ui| {
            if ui
                .add(
                    egui::Button::new("Cancel")
                        .fill(self.theme.bg_secondary)
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
            {
                return Some(serde_json::Value::Null);
            }

            ui.add_space(8.0);

            if ui
                .add(
                    egui::Button::new("Confirm")
                        .fill(self.theme.accent)
                        .min_size(Vec2::new(100.0, 36.0)),
                )
                .clicked()
            {
                return Some(serde_json::json!(*value));
            }

            None
        })
        .inner
    }

    fn render_progress(&self, ui: &mut egui::Ui, progress: Option<f64>) {
        if let Some(p) = progress {
            let bar = egui::ProgressBar::new(p as f32)
                .show_percentage()
                .animate(true);
            ui.add(bar);
        } else {
            // Indeterminate spinner
            ui.add(egui::Spinner::new().size(32.0));
        }
    }

    fn render_file_picker(
        &self,
        ui: &mut egui::Ui,
        mode: &crate::dbus_interface::FilePickerMode,
        filters: &[crate::dbus_interface::FileFilter],
        default_path: Option<&str>,
    ) -> Option<serde_json::Value> {
        // Use native file dialog via rfd
        use rfd::FileDialog;

        let mut dialog = FileDialog::new();
        
        if let Some(path) = default_path {
            dialog = dialog.set_directory(path);
        }

        for filter in filters {
            let exts: Vec<&str> = filter.extensions.iter().map(|s| s.as_str()).collect();
            dialog = dialog.add_filter(&filter.name, &exts);
        }

        ui.label("Opening file picker...");

        // This is blocking - in real implementation we'd spawn this
        let result = match mode {
            crate::dbus_interface::FilePickerMode::SingleFile => {
                dialog.pick_file().map(|p| serde_json::json!(p.to_string_lossy()))
            }
            crate::dbus_interface::FilePickerMode::MultipleFiles => {
                dialog.pick_files().map(|paths| {
                    serde_json::json!(paths.iter().map(|p| p.to_string_lossy().to_string()).collect::<Vec<_>>())
                })
            }
            crate::dbus_interface::FilePickerMode::Folder => {
                dialog.pick_folder().map(|p| serde_json::json!(p.to_string_lossy()))
            }
            crate::dbus_interface::FilePickerMode::Save => {
                dialog.save_file().map(|p| serde_json::json!(p.to_string_lossy()))
            }
        };

        result.or(Some(serde_json::Value::Null))
    }
}

/// Process escape sequences in text (e.g., \n -> newline, \t -> tab)
/// This handles the case where shell passes literal "\n" instead of actual newlines
fn process_escape_sequences(input: &str) -> String {
    let mut result = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.peek() {
                Some('n') => {
                    result.push('\n');
                    chars.next();
                }
                Some('t') => {
                    result.push('\t');
                    chars.next();
                }
                Some('r') => {
                    result.push('\r');
                    chars.next();
                }
                Some('\\') => {
                    result.push('\\');
                    chars.next();
                }
                _ => {
                    result.push(c);
                }
            }
        } else {
            result.push(c);
        }
    }
    
    result
}

/// Run the GUI application (synchronous version for main thread)
pub fn run_gui_sync(
    manager: Arc<RwLock<DialogManager>>,
    dialog_rx: std::sync::mpsc::Receiver<(DialogRequest, oneshot::Sender<DialogResponse>)>,
) -> Result<(), eframe::Error> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([420.0, 320.0])
            .with_min_inner_size([320.0, 200.0])
            .with_title("Cursor Dialog")
            .with_decorations(true)
            .with_transparent(false)
            .with_always_on_top(),
        ..Default::default()
    };

    eframe::run_native(
        "Cursor Dialog Daemon",
        options,
        Box::new(move |cc| {
            Ok(Box::new(DialogApp::new(cc, manager, dialog_rx)))
        }),
    )
}

