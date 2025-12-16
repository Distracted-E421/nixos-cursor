//! UI components for the Index (Docs) module
//! 
//! Clean, grid-aligned interface for cursor-docs integration

use super::client::DocsClient;
use super::models::*;
use eframe::egui::{self, Color32, RichText, Rounding, Vec2};
use std::process::Command;
use std::sync::mpsc;

/// Events that the docs panel can emit to the main app
#[derive(Debug, Clone)]
pub enum DocsPanelEvent {
    /// Open a source in the main editor area
    OpenSource { source_id: String, source_name: String },
    /// Status message to show in main app
    StatusMessage(String),
}

/// Indexing job state
#[derive(Debug, Clone)]
pub struct IndexingJob {
    pub source_id: String,
    pub url: String,
    pub name: String,
    pub max_pages: usize,
    pub current_page: usize,
    pub status: String,
    pub started_at: std::time::Instant,
}

/// State for the docs panel
pub struct DocsPanel {
    /// Backend client (public for tab access)
    pub client: DocsClient,
    /// Cached sources
    sources: Vec<DocSource>,
    /// Cached stats
    stats: DocsStats,
    /// Backend connection status
    backend_status: BackendStatus,
    /// Selected source ID
    selected_source: Option<String>,
    /// Search query
    search_query: String,
    /// Search results
    search_results: Vec<SearchResult>,
    /// Add URL form state
    add_url_input: String,
    add_name_input: String,
    add_max_pages: usize,
    /// Show add form
    show_add_form: bool,
    /// Error message
    error_message: Option<String>,
    /// Success message  
    success_message: Option<String>,
    /// Last refresh time
    last_refresh: std::time::Instant,
    /// Active indexing jobs
    indexing_jobs: Vec<IndexingJob>,
    /// Events to send to main app
    pending_events: Vec<DocsPanelEvent>,
    /// Channel for receiving indexing updates
    indexing_receiver: Option<mpsc::Receiver<IndexingUpdate>>,
}

/// Update from background indexing thread
#[derive(Debug)]
pub enum IndexingUpdate {
    Started { url: String },
    Progress { url: String, page: usize, status: String },
    Complete { url: String, chunks: usize },
    Error { url: String, error: String },
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
            search_query: String::new(),
            search_results: Vec::new(),
            add_url_input: String::new(),
            add_name_input: String::new(),
            add_max_pages: 1000, // Default to 1000
            show_add_form: false,
            error_message: None,
            success_message: None,
            last_refresh: std::time::Instant::now(),
            indexing_jobs: Vec::new(),
            pending_events: Vec::new(),
            indexing_receiver: None,
        };

        panel.refresh();
        panel
    }

    /// Get and clear pending events
    pub fn take_events(&mut self) -> Vec<DocsPanelEvent> {
        std::mem::take(&mut self.pending_events)
    }

    /// Check for indexing updates
    fn poll_indexing(&mut self) {
        // Collect updates first to avoid borrow issues
        let updates: Vec<_> = self.indexing_receiver
            .as_ref()
            .map(|rx| {
                let mut collected = Vec::new();
                while let Ok(update) = rx.try_recv() {
                    collected.push(update);
                }
                collected
            })
            .unwrap_or_default();
        
        let mut needs_refresh = false;
        
        for update in updates {
            match update {
                IndexingUpdate::Started { url } => {
                    self.success_message = Some(format!("Started indexing: {}", url));
                }
                IndexingUpdate::Progress { url, page, status } => {
                    if let Some(job) = self.indexing_jobs.iter_mut().find(|j| j.url == url) {
                        job.current_page = page;
                        job.status = status;
                    }
                }
                IndexingUpdate::Complete { url, chunks } => {
                    self.indexing_jobs.retain(|j| j.url != url);
                    self.success_message = Some(format!("Indexed {} ({} chunks)", url, chunks));
                    needs_refresh = true;
                }
                IndexingUpdate::Error { url, error } => {
                    self.indexing_jobs.retain(|j| j.url != url);
                    self.error_message = Some(format!("Failed to index {}: {}", url, error));
                    needs_refresh = true;
                }
            }
        }
        
        if needs_refresh {
            self.refresh();
        }
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
            return;
        }

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
    }

    /// Add a new source via cursor-docs CLI
    fn add_source(&mut self) {
        let url = self.add_url_input.trim().to_string();
        if url.is_empty() {
            self.error_message = Some("URL is required".to_string());
            return;
        }

        let name = if self.add_name_input.trim().is_empty() {
            None
        } else {
            Some(self.add_name_input.trim().to_string())
        };
        let max_pages = self.add_max_pages;

        // Build command
        let mut cmd = Command::new("mix");
        cmd.arg("cursor_docs.add")
            .arg(&url)
            .arg("--max-pages")
            .arg(max_pages.to_string());

        if let Some(ref n) = name {
            cmd.arg("--name").arg(n);
        }

        // Set working directory to cursor-docs service
        let cursor_docs_path = dirs::home_dir()
            .map(|h| h.join("nixos-cursor/services/cursor-docs"))
            .unwrap_or_default();

        if cursor_docs_path.exists() {
            cmd.current_dir(&cursor_docs_path);
        }

        // Create indexing job
        let job = IndexingJob {
            source_id: String::new(), // Will be assigned by backend
            url: url.clone(),
            name: name.clone().unwrap_or_else(|| url.clone()),
            max_pages,
            current_page: 0,
            status: "Starting...".to_string(),
            started_at: std::time::Instant::now(),
        };
        self.indexing_jobs.push(job);

        // Spawn in background
        let (tx, rx) = mpsc::channel();
        self.indexing_receiver = Some(rx);

        let url_clone = url.clone();
        std::thread::spawn(move || {
            let _ = tx.send(IndexingUpdate::Started { url: url_clone.clone() });

            match cmd.output() {
                Ok(output) => {
                    if output.status.success() {
                        let stdout = String::from_utf8_lossy(&output.stdout);
                        // Parse chunks from output if available
                        let chunks = stdout
                            .lines()
                            .find(|l| l.contains("Chunks:"))
                            .and_then(|l| l.split(':').last())
                            .and_then(|s| s.trim().parse().ok())
                            .unwrap_or(0);

                        let _ = tx.send(IndexingUpdate::Complete {
                            url: url_clone,
                            chunks,
                        });
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr);
                        let _ = tx.send(IndexingUpdate::Error {
                            url: url_clone,
                            error: stderr.to_string(),
                        });
                    }
                }
                Err(e) => {
                    let _ = tx.send(IndexingUpdate::Error {
                        url: url_clone,
                        error: e.to_string(),
                    });
                }
            }
        });

        self.success_message = Some(format!("Adding {} (max {} pages)...", url, max_pages));
        self.add_url_input.clear();
        self.add_name_input.clear();
        self.show_add_form = false;
    }

    /// Main UI rendering
    pub fn show(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        // Poll for indexing updates
        self.poll_indexing();

        // Auto-refresh: fast during indexing, slow otherwise
        let refresh_interval = if self.indexing_jobs.is_empty() { 30 } else { 2 };
        if self.last_refresh.elapsed().as_secs() > refresh_interval {
            self.refresh();
        }

        // Clear old messages after 5 seconds
        if self.success_message.is_some() || self.error_message.is_some() {
            // Messages auto-clear is handled by UI context
        }

        ui.spacing_mut().item_spacing = Vec2::new(8.0, 6.0);

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                self.show_header(ui, theme);
                ui.add_space(12.0);
                
                self.show_stats(ui, theme);
                ui.add_space(12.0);

                self.show_actions(ui, theme);
                
                if self.show_add_form {
                    ui.add_space(8.0);
                    self.show_add_form_ui(ui, theme);
                }

                // Show active indexing jobs
                if !self.indexing_jobs.is_empty() {
                    ui.add_space(12.0);
                    self.show_indexing_progress(ui, theme);
                }

                ui.add_space(12.0);
                self.show_search(ui, theme);

                if !self.search_results.is_empty() {
                    ui.add_space(8.0);
                    self.show_search_results(ui, theme);
                }

                ui.add_space(12.0);
                ui.separator();
                ui.add_space(8.0);

                self.show_sources_list(ui, theme);

                // Messages at bottom
                if let Some(ref msg) = self.error_message {
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        ui.label(RichText::new("⚠️").size(12.0));
                        ui.label(RichText::new(msg).color(theme.error()).size(10.0));
                    });
                }
                if let Some(ref msg) = self.success_message {
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        ui.label(RichText::new("✅").size(12.0));
                        ui.label(RichText::new(msg).color(theme.success()).size(10.0));
                    });
                }
            });
    }

    fn show_header(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            ui.label(
                RichText::new("📖 INDEX")
                    .size(13.0)
                    .color(theme.accent())
                    .strong(),
            );
            
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.add_space(4.0);
                // Connection indicator
                let (icon, color) = match self.backend_status {
                    BackendStatus::Connected => ("●", theme.success()),
                    BackendStatus::Disconnected => ("○", theme.fg_dim()),
                    BackendStatus::Connecting => ("◐", theme.accent()),
                    BackendStatus::Error => ("●", theme.error()),
                };
                ui.label(RichText::new(icon).size(10.0).color(color));
                ui.label(
                    RichText::new(self.backend_status.label())
                        .size(9.0)
                        .color(theme.fg_dim()),
                );
            });
        });
    }

    fn show_stats(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            
            // Use fixed-width stat cards for alignment
            let card_width = (ui.available_width() - 24.0) / 3.0;
            
            self.stat_card_fixed(ui, theme, "📚", "Sources", self.stats.total_sources, card_width);
            self.stat_card_fixed(ui, theme, "📄", "Chunks", self.stats.total_chunks, card_width);
            self.stat_card_fixed(ui, theme, "✅", "Indexed", self.stats.indexed_sources, card_width);
        });
    }

    fn stat_card_fixed(
        &self,
        ui: &mut egui::Ui,
        theme: &dyn DocsTheme,
        icon: &str,
        label: &str,
        value: usize,
        width: f32,
    ) {
        egui::Frame::none()
            .fill(theme.card_bg())
            .rounding(Rounding::same(6.0))
            .inner_margin(egui::Margin::symmetric(8.0, 6.0))
            .show(ui, |ui| {
                ui.set_width(width);
                ui.horizontal(|ui| {
                    ui.label(RichText::new(icon).size(16.0));
                    ui.add_space(4.0);
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new(format!("{}", value))
                                .size(14.0)
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

    fn show_actions(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            
            // Add URL button
            let add_btn = ui.add_sized(
                Vec2::new(100.0, 28.0),
                egui::Button::new(
                    RichText::new("➕ Add URL")
                        .size(11.0)
                        .color(Color32::WHITE),
                )
                .fill(theme.accent())
                .rounding(Rounding::same(4.0)),
            );
            if add_btn.clicked() {
                self.show_add_form = !self.show_add_form;
            }

            // Refresh button
            let refresh_btn = ui.add_sized(
                Vec2::new(32.0, 28.0),
                egui::Button::new(RichText::new("🔄").size(12.0))
                    .fill(theme.button_bg())
                    .rounding(Rounding::same(4.0)),
            );
            if refresh_btn.on_hover_text("Refresh sources").clicked() {
                self.refresh();
            }
        });
    }

    fn show_add_form_ui(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        egui::Frame::none()
            .fill(theme.card_bg())
            .rounding(Rounding::same(6.0))
            .inner_margin(egui::Margin::same(12.0))
            .stroke(egui::Stroke::new(1.0, theme.accent().gamma_multiply(0.3)))
            .show(ui, |ui| {
                ui.label(
                    RichText::new("Add Documentation Source")
                        .size(11.0)
                        .color(theme.fg())
                        .strong(),
                );
                ui.add_space(8.0);

                // Use Grid for clean alignment
                egui::Grid::new("add_form_grid")
                    .num_columns(2)
                    .spacing([8.0, 6.0])
                    .show(ui, |ui| {
                        // URL row
                        ui.label(RichText::new("URL:").size(10.0).color(theme.fg_dim()));
                        ui.add_sized(
                            Vec2::new(ui.available_width() - 8.0, 24.0),
                            egui::TextEdit::singleline(&mut self.add_url_input)
                                .hint_text("https://docs.example.com/"),
                        );
                        ui.end_row();

                        // Name row
                        ui.label(RichText::new("Name:").size(10.0).color(theme.fg_dim()));
                        ui.add_sized(
                            Vec2::new(ui.available_width() - 8.0, 24.0),
                            egui::TextEdit::singleline(&mut self.add_name_input)
                                .hint_text("Optional display name"),
                        );
                        ui.end_row();

                        // Max pages row
                        ui.label(RichText::new("Max pages:").size(10.0).color(theme.fg_dim()));
                        ui.horizontal(|ui| {
                            ui.add(
                                egui::DragValue::new(&mut self.add_max_pages)
                                    .range(1..=10000)
                                    .speed(10),
                            );
                            ui.label(
                                RichText::new("(default: 1000)")
                                    .size(9.0)
                                    .color(theme.fg_dim()),
                            );
                        });
                        ui.end_row();
                    });

                ui.add_space(8.0);

                // Action buttons
                ui.horizontal(|ui| {
                    let add_btn = ui.add_sized(
                        Vec2::new(80.0, 26.0),
                        egui::Button::new(
                            RichText::new("Add")
                                .size(11.0)
                                .color(Color32::WHITE),
                        )
                        .fill(theme.accent())
                        .rounding(Rounding::same(4.0)),
                    );
                    if add_btn.clicked() {
                        self.add_source();
                    }

                    let cancel_btn = ui.add_sized(
                        Vec2::new(80.0, 26.0),
                        egui::Button::new(RichText::new("Cancel").size(11.0))
                            .fill(theme.button_bg())
                            .rounding(Rounding::same(4.0)),
                    );
                    if cancel_btn.clicked() {
                        self.show_add_form = false;
                        self.add_url_input.clear();
                        self.add_name_input.clear();
                    }
                });
            });
    }

    fn show_indexing_progress(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            ui.label(
                RichText::new("INDEXING")
                    .size(10.0)
                    .color(theme.accent())
                    .strong(),
            );
        });
        ui.add_space(4.0);

        for job in &self.indexing_jobs {
            egui::Frame::none()
                .fill(theme.card_bg())
                .rounding(Rounding::same(4.0))
                .inner_margin(egui::Margin::same(8.0))
                .stroke(egui::Stroke::new(1.0, theme.accent().gamma_multiply(0.5)))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.spinner();
                        ui.add_space(8.0);
                        ui.vertical(|ui| {
                            ui.label(
                                RichText::new(&job.name)
                                    .size(11.0)
                                    .color(theme.fg())
                                    .strong(),
                            );
                            ui.label(
                                RichText::new(format!(
                                    "{} • Page {}/{}",
                                    job.status, job.current_page, job.max_pages
                                ))
                                .size(9.0)
                                .color(theme.fg_dim()),
                            );
                            
                            // Progress bar
                            let progress = job.current_page as f32 / job.max_pages as f32;
                            ui.add(
                                egui::ProgressBar::new(progress)
                                    .desired_width(ui.available_width())
                                    .show_percentage(),
                            );
                        });
                    });
                });
            ui.add_space(4.0);
        }
    }

    fn show_search(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            ui.label(RichText::new("🔍").size(12.0).color(theme.fg_dim()));
            
            let response = ui.add_sized(
                Vec2::new(ui.available_width() - 40.0, 24.0),
                egui::TextEdit::singleline(&mut self.search_query)
                    .hint_text("Search indexed documentation..."),
            );
            
            if response.changed() {
                self.search();
            }
            if response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                self.search();
            }
            
            if !self.search_query.is_empty() {
                if ui.add(egui::Button::new("✕").frame(false)).clicked() {
                    self.search_query.clear();
                    self.search_results.clear();
                }
            }
        });
    }

    fn show_search_results(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            ui.label(
                RichText::new(format!("Results: {}", self.search_results.len()))
                    .size(10.0)
                    .color(theme.fg_dim()),
            );
        });

        egui::ScrollArea::vertical()
            .max_height(180.0)
            .show(ui, |ui| {
                for result in &self.search_results {
                    ui.add_space(2.0);
                    egui::Frame::none()
                        .fill(theme.card_bg())
                        .rounding(Rounding::same(4.0))
                        .inner_margin(egui::Margin::same(8.0))
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new(&result.chunk.title)
                                    .size(11.0)
                                    .color(theme.fg())
                                    .strong(),
                            );
                            ui.label(
                                RichText::new(&result.snippet)
                                    .size(10.0)
                                    .color(theme.fg_dim()),
                            );
                            ui.horizontal(|ui| {
                                ui.label(
                                    RichText::new(&result.source_name)
                                        .size(9.0)
                                        .color(theme.accent()),
                                );
                            });
                        });
                }
            });
    }

    fn show_sources_list(&mut self, ui: &mut egui::Ui, theme: &dyn DocsTheme) {
        ui.horizontal(|ui| {
            ui.add_space(4.0);
            ui.label(
                RichText::new("SOURCES")
                    .size(10.0)
                    .color(theme.fg_dim())
                    .strong(),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.add_space(4.0);
                ui.label(
                    RichText::new(format!("{} total", self.sources.len()))
                        .size(9.0)
                        .color(theme.fg_dim()),
                );
            });
        });
        ui.add_space(4.0);

        if self.sources.is_empty() {
            egui::Frame::none()
                .fill(theme.card_bg())
                .rounding(Rounding::same(4.0))
                .inner_margin(egui::Margin::same(16.0))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(
                            RichText::new("No sources indexed yet")
                                .size(11.0)
                                .color(theme.fg_dim()),
                        );
                        ui.add_space(4.0);
                        ui.label(
                            RichText::new("Click \"Add URL\" to index documentation")
                                .size(10.0)
                                .color(theme.fg_dim()),
                        );
                    });
                });
            return;
        }

        // Source list with consistent layout
        for source in self.sources.clone() {
            let is_selected = self.selected_source.as_ref() == Some(&source.id);
            
            let bg = if is_selected {
                theme.selection_bg()
            } else {
                theme.card_bg()
            };

            let response = egui::Frame::none()
                .fill(bg)
                .rounding(Rounding::same(4.0))
                .inner_margin(egui::Margin::same(8.0))
                .show(ui, |ui| {
                    ui.set_width(ui.available_width());
                    
                    // Header row with grid for alignment
                    ui.horizontal(|ui| {
                        // Status icon - fixed width
                        ui.add_sized(
                            Vec2::new(20.0, 20.0),
                            egui::Label::new(RichText::new(source.status.icon()).size(14.0)),
                        );

                        // Name - flexible width
                        let name = source.display_name();
                        let truncated = if name.len() > 30 {
                            format!("{}...", &name[..27])
                        } else {
                            name.to_string()
                        };
                        
                        ui.label(
                            RichText::new(&truncated)
                                .size(11.0)
                                .color(theme.fg())
                                .strong(),
                        );

                        // Right side info
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            // Chunk count badge
                            egui::Frame::none()
                                .fill(theme.button_bg())
                                .rounding(Rounding::same(10.0))
                                .inner_margin(egui::Margin::symmetric(6.0, 2.0))
                                .show(ui, |ui| {
                                    ui.label(
                                        RichText::new(format!("{} chunks", source.chunks_count))
                                            .size(9.0)
                                            .color(theme.fg_dim()),
                                    );
                                });
                        });
                    });

                    // URL on second line
                    ui.label(
                        RichText::new(&source.url)
                            .size(9.0)
                            .color(theme.fg_dim()),
                    );

                    // Action buttons when selected
                    if is_selected {
                        ui.add_space(6.0);
                        ui.horizontal(|ui| {
                            // Open in editor button
                            if ui
                                .add_sized(
                                    Vec2::new(70.0, 22.0),
                                    egui::Button::new(
                                        RichText::new("📖 View")
                                            .size(10.0)
                                            .color(Color32::WHITE),
                                    )
                                    .fill(theme.accent())
                                    .rounding(Rounding::same(3.0)),
                                )
                                .on_hover_text("Open in editor")
                                .clicked()
                            {
                                self.pending_events.push(DocsPanelEvent::OpenSource {
                                    source_id: source.id.clone(),
                                    source_name: source.display_name().to_string(),
                                });
                            }

                            // Refresh button
                            if ui
                                .add_sized(
                                    Vec2::new(70.0, 22.0),
                                    egui::Button::new(RichText::new("🔄 Refresh").size(10.0))
                                        .fill(theme.button_bg())
                                        .rounding(Rounding::same(3.0)),
                                )
                                .on_hover_text("Re-index this source")
                                .clicked()
                            {
                                // Start re-indexing
                                self.add_url_input = source.url.clone();
                                self.add_name_input = source.name.clone();
                                self.add_source();
                            }

                            // Delete button
                            if ui
                                .add_sized(
                                    Vec2::new(70.0, 22.0),
                                    egui::Button::new(
                                        RichText::new("🗑️ Delete")
                                            .size(10.0)
                                            .color(theme.error()),
                                    )
                                    .fill(theme.button_bg())
                                    .rounding(Rounding::same(3.0)),
                                )
                                .on_hover_text("Remove this source")
                                .clicked()
                            {
                                self.error_message = Some("Delete not yet implemented".to_string());
                            }
                        });
                    }
                });

            // Handle click to select
            if response.response.interact(egui::Sense::click()).clicked() {
                if self.selected_source.as_ref() == Some(&source.id) {
                    self.selected_source = None;
                } else {
                    self.selected_source = Some(source.id.clone());
                }
            }

            ui.add_space(4.0);
        }
    }
}

/// Theme trait for docs panel
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

/// Default dark theme
pub struct DarkDocsTheme;

impl DocsTheme for DarkDocsTheme {
    fn bg(&self) -> Color32 { Color32::from_rgb(30, 30, 30) }
    fn fg(&self) -> Color32 { Color32::from_rgb(220, 220, 220) }
    fn fg_dim(&self) -> Color32 { Color32::from_rgb(140, 140, 140) }
    fn accent(&self) -> Color32 { Color32::from_rgb(59, 130, 246) }
    fn error(&self) -> Color32 { Color32::from_rgb(239, 68, 68) }
    fn success(&self) -> Color32 { Color32::from_rgb(34, 197, 94) }
    fn card_bg(&self) -> Color32 { Color32::from_rgb(45, 45, 45) }
    fn button_bg(&self) -> Color32 { Color32::from_rgb(60, 60, 60) }
    fn selection_bg(&self) -> Color32 { Color32::from_rgb(59, 130, 246).gamma_multiply(0.3) }
}
