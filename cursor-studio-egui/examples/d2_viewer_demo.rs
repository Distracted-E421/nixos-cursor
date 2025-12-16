//! D2 Viewer Demo
//!
//! Run with: cargo run --example d2_viewer_demo
//!
//! This demonstrates the native D2 diagram rendering with:
//! - Interactive pan/zoom
//! - Theme-aware colors
//! - Shape rendering
//! - Real-time data flow (planned)

use eframe::egui;
use cursor_studio::diagram::D2Viewer;
use cursor_studio::theme::Theme;

fn main() -> eframe::Result<()> {
    env_logger::init();
    
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1200.0, 800.0])
            .with_title("D2 Viewer Demo - cursor-studio"),
        ..Default::default()
    };
    
    eframe::run_native(
        "D2 Viewer Demo",
        options,
        Box::new(|cc| Ok(Box::new(D2ViewerApp::new(cc)))),
    )
}

struct D2ViewerApp {
    viewer: D2Viewer,
    theme: Theme,
    d2_source: String,
    show_source: bool,
}

impl D2ViewerApp {
    fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        let mut viewer = D2Viewer::new();
        
        // Load demo D2 content - use double # for raw string to allow # in content
        let demo_d2 = r##"
direction: right
title: "Data Pipeline Demo"

source: "Data Sources"
source.api: "REST API" { shape: hexagon }
source.db: "Database" { shape: cylinder }
source.stream: "Event Stream" { shape: queue }

process: "Processing"
process.transform: "Transform" { shape: diamond }
process.validate: "Validate" { shape: hexagon }

output: "Output"
output.storage: "Data Lake" { shape: cylinder }
output.dashboard: "Dashboard"

source.api -> process.transform: "JSON"
source.db -> process.transform: "SQL"
source.stream -> process.validate: "Events"

process.transform -> process.validate
process.validate -> output.storage: "Cleaned Data"
process.validate -> output.dashboard: "Real-time"
        "##;
        
        let _ = viewer.load_string(demo_d2);
        
        Self {
            viewer,
            theme: Theme::dark(),
            d2_source: demo_d2.to_string(),
            show_source: false,
        }
    }
}

impl eframe::App for D2ViewerApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Top menu bar
        egui::TopBottomPanel::top("menu_bar").show(ctx, |ui| {
            egui::menu::bar(ui, |ui| {
                ui.menu_button("View", |ui| {
                    if ui.checkbox(&mut self.viewer.show_grid, "Show Grid (G)").clicked() {
                        ui.close_menu();
                    }
                    if ui.checkbox(&mut self.viewer.show_minimap, "Show Minimap").clicked() {
                        ui.close_menu();
                    }
                    if ui.checkbox(&mut self.viewer.show_toolbar, "Show Toolbar").clicked() {
                        ui.close_menu();
                    }
                    if ui.checkbox(&mut self.viewer.animate, "Animations").clicked() {
                        ui.close_menu();
                    }
                    if ui.checkbox(&mut self.show_source, "Show Source").clicked() {
                        ui.close_menu();
                    }
                    
                    ui.separator();
                    
                    if ui.button("Fit to View (F)").clicked() {
                        self.viewer.fit_to_view();
                        ui.close_menu();
                    }
                    
                    if ui.button("Reset Zoom").clicked() {
                        self.viewer.zoom = 1.0;
                        ui.close_menu();
                    }
                });
                
                ui.menu_button("Theme", |ui| {
                    if ui.button("Dark (Default)").clicked() {
                        self.theme = Theme::dark();
                        self.viewer.set_theme(&self.theme);
                        ui.close_menu();
                    }
                    if ui.button("Light").clicked() {
                        self.theme = Theme::light();
                        self.viewer.set_theme(&self.theme);
                        ui.close_menu();
                    }
                });
                
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(format!("Zoom: {:.0}%", self.viewer.zoom * 100.0));
                    ui.separator();
                    ui.label(format!(
                        "Nodes: {} | Edges: {}",
                        self.viewer.graph.nodes.len(),
                        self.viewer.graph.edges.len()
                    ));
                    if let Some(ref selected) = self.viewer.selected_node {
                        ui.separator();
                        ui.label(format!("Selected: {}", selected));
                    }
                });
            });
        });
        
        // Optional source panel
        if self.show_source {
            egui::SidePanel::right("source_panel")
                .default_width(300.0)
                .show(ctx, |ui| {
                    ui.heading("D2 Source");
                    ui.separator();
                    
                    egui::ScrollArea::vertical().show(ui, |ui| {
                        let response = ui.add(
                            egui::TextEdit::multiline(&mut self.d2_source)
                                .font(egui::TextStyle::Monospace)
                                .desired_width(f32::INFINITY)
                        );
                        
                        if response.changed() {
                            let _ = self.viewer.load_string(&self.d2_source);
                        }
                    });
                });
        }
        
        // Main diagram viewer
        egui::CentralPanel::default().show(ctx, |ui| {
            self.viewer.ui(ui);
        });
        
        // Status bar
        egui::TopBottomPanel::bottom("status_bar").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label("D2 Viewer Demo");
                ui.separator();
                ui.label("Pan: Right-click drag | Zoom: Scroll | Select: Left-click | Drag: Left-click on node");
            });
        });
    }
}
