//! UI components for the Index (Docs) module

use super::client::DocsClient;
use super::models::*;
use eframe::egui::{self, Color32, RichText, Rounding, Stroke, Vec2};

/// State for the docs panel
pub struct DocsPanel {
    /// Backend client
    client: DocsClient,
    /// Cached sources
    sources: Vec<DocSource>,
    /// Cached stats
    stats: DocsStats,
    /// Backend connection status
    backend_status: BackendStatus,
    /// Selected source ID
    selected_source: Option<String>,
    /// Expanded source IDs (for sidebar)
    expanded_sources: std::collections::HashSet<String>,
    /// Search query
    search_query: String,
    /// Search results
    search_results: Vec<SearchResult>,
    /// Is searching
    is_searching: bool,
    /// Add URL form state
    add_url_input: String,
    add_name_input: String,
    add_max_pages: usize,
    add_follow_links: bool,
    /// Show add form
    show_add_form: bool,
    /// Error message
    error_message: Option<String>,
    /// Success message
    success_message: Option<String>,
    /// Last refresh time
    last_refresh: std::time::Instant,
}

impl Default for DocsPanel {
    fn default() -> Self {
        Self::new()
    }
}

impl DocsPanel {
    pub fn new() -> Self {
        let db_path = DocsClient::default_db_path();
        let client = DocsClient::new_sqlite(db_path);

        let mut panel = Self {
            client,
            sources: Vec::new(),
            stats: DocsStats::default(),
            backend_status: BackendStatus::Disconnected,
            selected_source: None,
            expanded_sources: std::collections::HashSet::new(),
            search_query: String::new(),
            search_results: Vec::new(),
            is_searching: false,
            add_url_input: String::new(),
            add_name_input: String::new(),
            add_max_pages: 100,
            add_follow_links: false,
            show_add_form: false,
            error_message: None,
            success_message: None,
            last_refresh: std::time::Instant::now(),
        };

        panel.refresh();
        panel
    }

    /// Refresh data from backend
    pub fn refresh(&mut self) {
        self.backend_status = self.client.check_connection();

        if self.backend_status == BackendStatus::Connected {
            if let Ok(sources) = self.client.get_sources() {
                self.sources = sources;
            }
            if let Ok(stats) = self.client.get_stats() {
                self.stats = stats;
            }
        }

        self.last_refresh = std::time::Instant::now();
    }

    /// Perform search
    pub fn search(&mut self) {
        if self.search_query.trim().is_empty() {
            self.search_results.clear();
            self.is_searching = false;
            return;
        }

        self.is_searching = true;
        match self.client.search(&self.search_query, 50) {
            Ok(results) => {
                self.search_results = results;
                self.error_message = None;
            }
            Err(e) => {
                self.error_message = Some(format!("Search failed: {}", e));
                self.search_results.clear();
            }
        }
        self.is_searching = false;
    }

    /// Main UI rendering
    pub fn show(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        // Auto-refresh every 30 seconds
        if self.last_refresh.elapsed().as_secs() > 30 {
            self.refresh();
        }

        ui.vertical(|ui| {
            // Dashboard section
            self.show_dashboard(ui, theme);

            ui.add_space(8.0);
            ui.separator();
            ui.add_space(8.0);

            // Sources list
            self.show_sources_list(ui, theme);
        });
    }

    /// Show dashboard with stats and quick actions
    fn show_dashboard(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        // Header with status
        ui.horizontal(|ui| {
            ui.label(
                RichText::new("📖 Index")
                    .size(14.0)
                    .color(theme.accent())
                    .strong(),
            );

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                // Connection status
                ui.label(
                    RichText::new(format!(
                        "{} {}",
                        self.backend_status.icon(),
                        self.backend_status.label()
                    ))
                    .size(10.0)
                    .color(theme.fg_dim()),
                );
            });
        });

        ui.add_space(8.0);

        // Stats cards
        ui.horizontal(|ui| {
            self.stat_card(ui, theme, "📚", "Sources", self.stats.total_sources);
            ui.add_space(4.0);
            self.stat_card(ui, theme, "📄", "Chunks", self.stats.total_chunks);
            ui.add_space(4.0);
            self.stat_card(ui, theme, "✅", "Indexed", self.stats.indexed_sources);
        });

        ui.add_space(8.0);

        // Quick actions
        ui.horizontal(|ui| {
            if ui
                .add(
                    egui::Button::new(RichText::new("➕ Add URL").size(11.0))
                        .fill(theme.accent())
                        .rounding(Rounding::same(4.0)),
                )
                .clicked()
            {
                self.show_add_form = !self.show_add_form;
            }

            if ui
                .add(
                    egui::Button::new(RichText::new("🔄").size(11.0))
                        .fill(theme.button_bg())
                        .rounding(Rounding::same(4.0)),
                )
                .on_hover_text("Refresh")
                .clicked()
            {
                self.refresh();
            }
        });

        // Add URL form
        if self.show_add_form {
            ui.add_space(8.0);
            self.show_add_form_ui(ui, theme);
        }

        // Search bar
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            ui.label(RichText::new("🔍").size(12.0).color(theme.fg_dim()));
            let response = ui.add(
                egui::TextEdit::singleline(&mut self.search_query)
                    .hint_text("Search indexed docs...")
                    .desired_width(ui.available_width() - 60.0),
            );
            if response.changed() || (response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))) {
                self.search();
            }
            if !self.search_query.is_empty() {
                if ui
                    .add(egui::Button::new("✕").frame(false))
                    .clicked()
                {
                    self.search_query.clear();
                    self.search_results.clear();
                }
            }
        });

        // Search results
        if !self.search_results.is_empty() {
            ui.add_space(4.0);
            self.show_search_results(ui, theme);
        }

        // Messages
        if let Some(ref msg) = self.error_message {
            ui.add_space(4.0);
            ui.label(RichText::new(msg).color(theme.error()).size(10.0));
        }
        if let Some(ref msg) = self.success_message {
            ui.add_space(4.0);
            ui.label(RichText::new(msg).color(theme.success()).size(10.0));
        }
    }

    /// Show add URL form
    fn show_add_form_ui(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        egui::Frame::none()
            .fill(theme.card_bg())
            .rounding(Rounding::same(4.0))
            .inner_margin(8.0)
            .show(ui, |ui| {
                ui.label(RichText::new("Add Documentation").size(11.0).strong());
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label(RichText::new("URL:").size(10.0).color(theme.fg_dim()));
                    ui.add(
                        egui::TextEdit::singleline(&mut self.add_url_input)
                            .hint_text("https://docs.example.com/")
                            .desired_width(200.0),
                    );
                });

                ui.horizontal(|ui| {
                    ui.label(RichText::new("Name:").size(10.0).color(theme.fg_dim()));
                    ui.add(
                        egui::TextEdit::singleline(&mut self.add_name_input)
                            .hint_text("Optional alias")
                            .desired_width(200.0),
                    );
                });

                ui.horizontal(|ui| {
                    ui.label(RichText::new("Max pages:").size(10.0).color(theme.fg_dim()));
                    ui.add(egui::DragValue::new(&mut self.add_max_pages).range(1..=1000));
                    ui.checkbox(&mut self.add_follow_links, "Follow links");
                });

                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    if ui
                        .add(
                            egui::Button::new("Add")
                                .fill(theme.accent())
                                .rounding(Rounding::same(4.0)),
                        )
                        .clicked()
                    {
                        self.add_source();
                    }
                    if ui.button("Cancel").clicked() {
                        self.show_add_form = false;
                        self.add_url_input.clear();
                        self.add_name_input.clear();
                    }
                });
            });
    }

    /// Add a new source (placeholder - needs backend command)
    fn add_source(&mut self) {
        if self.add_url_input.trim().is_empty() {
            self.error_message = Some("URL is required".to_string());
            return;
        }

        // TODO: Actually add the source via cursor-docs CLI or HTTP API
        // For now, show instructions
        self.success_message = Some(format!(
            "Run: mix cursor_docs.add {} --max-pages {}",
            self.add_url_input, self.add_max_pages
        ));

        self.add_url_input.clear();
        self.add_name_input.clear();
        self.show_add_form = false;
    }

    /// Show sources list
    fn show_sources_list(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.label(
            RichText::new("SOURCES")
                .size(10.0)
                .color(theme.fg_dim())
                .strong(),
        );
        ui.add_space(4.0);

        if self.sources.is_empty() {
            ui.label(
                RichText::new("No sources indexed yet.\nAdd a URL to get started.")
                    .size(10.0)
                    .color(theme.fg_dim()),
            );
            return;
        }

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                for source in &self.sources {
                    let is_expanded = self.expanded_sources.contains(&source.id);
                    let is_selected = self.selected_source.as_ref() == Some(&source.id);

                    let bg = if is_selected {
                        theme.selection_bg()
                    } else {
                        theme.card_bg()
                    };

                    egui::Frame::none()
                        .fill(bg)
                        .rounding(Rounding::same(4.0))
                        .inner_margin(6.0)
                        .show(ui, |ui| {
                            // Header row
                            ui.horizontal(|ui| {
                                // Expand arrow
                                let arrow = if is_expanded { "▼" } else { "▸" };
                                if ui
                                    .add(egui::Button::new(arrow).frame(false))
                                    .clicked()
                                {
                                    if is_expanded {
                                        self.expanded_sources.remove(&source.id);
                                    } else {
                                        self.expanded_sources.insert(source.id.clone());
                                    }
                                }

                                // Status icon
                                ui.label(RichText::new(source.status.icon()).size(12.0));

                                // Name
                                let name = source.display_name();
                                let truncated = if name.len() > 25 {
                                    format!("{}...", &name[..22])
                                } else {
                                    name.to_string()
                                };

                                if ui
                                    .add(
                                        egui::Label::new(
                                            RichText::new(&truncated)
                                                .size(11.0)
                                                .color(theme.fg()),
                                        )
                                        .sense(egui::Sense::click()),
                                    )
                                    .clicked()
                                {
                                    self.selected_source = Some(source.id.clone());
                                }

                                // Chunk count
                                ui.with_layout(
                                    egui::Layout::right_to_left(egui::Align::Center),
                                    |ui| {
                                        ui.label(
                                            RichText::new(format!("{}", source.chunks_count))
                                                .size(10.0)
                                                .color(theme.fg_dim()),
                                        );
                                    },
                                );
                            });

                            // Expanded details
                            if is_expanded {
                                ui.add_space(4.0);
                                ui.label(
                                    RichText::new(&source.url)
                                        .size(9.0)
                                        .color(theme.fg_dim()),
                                );

                                if let Some(ref last) = source.last_indexed {
                                    ui.label(
                                        RichText::new(format!("Last indexed: {}", last))
                                            .size(9.0)
                                            .color(theme.fg_dim()),
                                    );
                                }

                                ui.horizontal(|ui| {
                                    ui.label(
                                        RichText::new(format!(
                                            "Status: {}",
                                            source.status.label()
                                        ))
                                        .size(9.0)
                                        .color(theme.fg_dim()),
                                    );
                                });

                                // Actions
                                ui.horizontal(|ui| {
                                    if ui.small_button("🔄 Refresh").clicked() {
                                        // TODO: Refresh this source
                                        self.success_message = Some(format!(
                                            "Run: mix cursor_docs.add {} --force",
                                            source.url
                                        ));
                                    }
                                    if ui.small_button("🗑️ Delete").clicked() {
                                        // TODO: Delete this source
                                        self.error_message =
                                            Some("Delete not yet implemented".to_string());
                                    }
                                });
                            }
                        });

                    ui.add_space(2.0);
                }
            });
    }

    /// Show search results
    fn show_search_results(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.label(
            RichText::new(format!("Results: {}", self.search_results.len()))
                .size(10.0)
                .color(theme.fg_dim()),
        );

        egui::ScrollArea::vertical()
            .max_height(200.0)
            .show(ui, |ui| {
                for result in &self.search_results {
                    egui::Frame::none()
                        .fill(theme.card_bg())
                        .rounding(Rounding::same(4.0))
                        .inner_margin(6.0)
                        .show(ui, |ui| {
                            ui.horizontal(|ui| {
                                ui.label(
                                    RichText::new(&result.chunk.title)
                                        .size(11.0)
                                        .color(theme.fg())
                                        .strong(),
                                );
                            });
                            ui.label(
                                RichText::new(&result.snippet)
                                    .size(10.0)
                                    .color(theme.fg_dim()),
                            );
                            ui.label(
                                RichText::new(&result.source_name)
                                    .size(9.0)
                                    .color(theme.accent()),
                            );
                        });
                    ui.add_space(2.0);
                }
            });
    }

    /// Render a stat card
    fn stat_card(
        &self,
        ui: &mut egui::Ui,
        theme: &dyn DocsTheme,
        icon: &str,
        label: &str,
        value: usize,
    ) {
        egui::Frame::none()
            .fill(theme.card_bg())
            .rounding(Rounding::same(4.0))
            .inner_margin(6.0)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(icon).size(14.0));
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new(format!("{}", value))
                                .size(12.0)
                                .color(theme.fg())
                                .strong(),
                        );
                        ui.label(
                            RichText::new(label)
                                .size(9.0)
                                .color(theme.fg_dim()),
                        );
                    });
                });
            });
    }
}

/// Theme trait for docs panel (to work with main app theme)
pub trait DocsTheme {
    fn bg(&self) -> Color32;
    fn fg(&self) -> Color32;
    fn fg_dim(&self) -> Color32;
    fn accent(&self) -> Color32;
    fn error(&self) -> Color32;
    fn success(&self) -> Color32;
    fn card_bg(&self) -> Color32;
    fn button_bg(&self) -> Color32;
    fn selection_bg(&self) -> Color32;
}

/// Default dark theme implementation
pub struct DarkDocsTheme;

impl DocsTheme for DarkDocsTheme {
    fn bg(&self) -> Color32 {
        Color32::from_rgb(30, 30, 30)
    }
    fn fg(&self) -> Color32 {
        Color32::from_rgb(220, 220, 220)
    }
    fn fg_dim(&self) -> Color32 {
        Color32::from_rgb(140, 140, 140)
    }
    fn accent(&self) -> Color32 {
        Color32::from_rgb(59, 130, 246)
    }
    fn error(&self) -> Color32 {
        Color32::from_rgb(239, 68, 68)
    }
    fn success(&self) -> Color32 {
        Color32::from_rgb(34, 197, 94)
    }
    fn card_bg(&self) -> Color32 {
        Color32::from_rgb(45, 45, 45)
    }
    fn button_bg(&self) -> Color32 {
        Color32::from_rgb(60, 60, 60)
    }
    fn selection_bg(&self) -> Color32 {
        Color32::from_rgb(59, 130, 246).gamma_multiply(0.3)
    }
}

