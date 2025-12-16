//! Interactive D2 Diagram Renderer
//!
//! Native egui rendering of D2 diagrams with:
//! - Pan and zoom (mouse wheel + drag)
//! - Node selection
//! - Edge highlighting
//! - Real-time data flow animation
//! - Theme-aware colors

use eframe::egui::{self, Color32, Painter, Pos2, Rect, Sense, Stroke, Vec2, FontId, Align2};
use super::graph::{D2Graph, D2Node, D2Edge, D2Shape, ArrowType};
use super::theme_mapper::DiagramTheme;
use super::parser::{parse_string, parse_file, ParseError};
use crate::theme::Theme;
use std::path::PathBuf;
use std::time::Instant;

/// Main D2 diagram viewer widget
pub struct D2Viewer {
    /// The graph data
    pub graph: D2Graph,
    
    /// Theme for rendering
    pub theme: DiagramTheme,
    
    /// Current pan offset
    pub pan: Vec2,
    
    /// Current zoom level (1.0 = 100%)
    pub zoom: f32,
    
    /// Minimum zoom level
    pub min_zoom: f32,
    
    /// Maximum zoom level
    pub max_zoom: f32,
    
    /// Whether to show grid
    pub show_grid: bool,
    
    /// Grid size in pixels
    pub grid_size: f32,
    
    /// Currently selected node ID
    pub selected_node: Option<String>,
    
    /// Currently hovered node ID
    pub hovered_node: Option<String>,
    
    /// Whether currently dragging a node
    dragging_node: Option<String>,
    
    /// Whether currently panning
    is_panning: bool,
    
    /// Last mouse position for delta calculation
    last_mouse_pos: Option<Pos2>,
    
    /// Animation time for data flow effects
    animation_time: f32,
    
    /// Start time for animations
    start_time: Instant,
    
    /// Source file path (for reload)
    source_path: Option<PathBuf>,
    
    /// Parse error message
    error: Option<String>,
    
    /// Enable animations
    pub animate: bool,
    
    /// Show minimap
    pub show_minimap: bool,
    
    /// Show toolbar
    pub show_toolbar: bool,
}

impl Default for D2Viewer {
    fn default() -> Self {
        Self::new()
    }
}

impl D2Viewer {
    /// Create a new empty viewer
    pub fn new() -> Self {
        Self {
            graph: D2Graph::new(),
            theme: DiagramTheme::dark(),
            pan: Vec2::ZERO,
            zoom: 1.0,
            min_zoom: 0.1,
            max_zoom: 5.0,
            show_grid: true,
            grid_size: 20.0,
            selected_node: None,
            hovered_node: None,
            dragging_node: None,
            is_panning: false,
            last_mouse_pos: None,
            animation_time: 0.0,
            start_time: Instant::now(),
            source_path: None,
            error: None,
            animate: true,
            show_minimap: true,
            show_toolbar: true,
        }
    }
    
    /// Load a D2 file
    pub fn load_file(&mut self, path: impl Into<PathBuf>) -> Result<(), ParseError> {
        let path = path.into();
        let graph = parse_file(&path)?;
        self.graph = graph;
        self.source_path = Some(path);
        self.error = None;
        self.fit_to_view();
        Ok(())
    }
    
    /// Load D2 from string
    pub fn load_string(&mut self, source: &str) -> Result<(), ParseError> {
        let graph = parse_string(source)?;
        self.graph = graph;
        self.source_path = None;
        self.error = None;
        self.fit_to_view();
        Ok(())
    }
    
    /// Reload from source file
    pub fn reload(&mut self) -> Result<(), ParseError> {
        if let Some(ref path) = self.source_path.clone() {
            self.load_file(path)
        } else {
            Err(ParseError::IoError("No source file loaded".to_string()))
        }
    }
    
    /// Set the color theme
    pub fn set_theme(&mut self, theme: &Theme) {
        self.theme = DiagramTheme::from_vscode_theme(theme);
    }
    
    /// Fit the diagram to the view
    pub fn fit_to_view(&mut self) {
        self.pan = Vec2::ZERO;
        self.zoom = 1.0;
    }
    
    /// Center on a specific node
    pub fn center_on_node(&mut self, node_id: &str) {
        if let Some(node) = self.graph.get_node(node_id) {
            self.pan = -node.center().to_vec2();
        }
    }
    
    /// Main UI function
    pub fn ui(&mut self, ui: &mut egui::Ui) {
        // Update animation time
        if self.animate {
            self.animation_time = self.start_time.elapsed().as_secs_f32();
            ui.ctx().request_repaint();
        }
        
        let available_size = ui.available_size();
        let (response, painter) = ui.allocate_painter(available_size, Sense::click_and_drag());
        let rect = response.rect;
        
        // Fill background
        painter.rect_filled(rect, 0.0, self.theme.canvas_bg);
        
        // Draw grid if enabled
        if self.show_grid {
            self.draw_grid(&painter, rect);
        }
        
        // Handle input
        self.handle_input(ui, &response);
        
        // Transform for pan/zoom
        let transform = self.get_transform(rect);
        
        // Draw edges first (behind nodes)
        for edge in &self.graph.edges {
            self.draw_edge(&painter, edge, &transform);
        }
        
        // Draw nodes
        for node in self.graph.nodes.values() {
            self.draw_node(&painter, node, &transform);
        }
        
        // Draw toolbar if enabled
        if self.show_toolbar {
            self.draw_toolbar(ui, rect);
        }
        
        // Draw minimap if enabled
        if self.show_minimap {
            self.draw_minimap(&painter, rect);
        }
        
        // Draw error if any
        if let Some(ref error) = self.error {
            self.draw_error(&painter, rect, error);
        }
    }
    
    /// Handle user input
    fn handle_input(&mut self, ui: &egui::Ui, response: &egui::Response) {
        let input = ui.input(|i| i.clone());
        
        // Zoom with scroll wheel
        if response.hovered() {
            let scroll_delta = input.smooth_scroll_delta.y;
            if scroll_delta != 0.0 {
                let zoom_delta = 1.0 + scroll_delta * 0.001;
                self.zoom = (self.zoom * zoom_delta).clamp(self.min_zoom, self.max_zoom);
            }
        }
        
        // Pan with middle mouse or right mouse
        if response.dragged_by(egui::PointerButton::Middle) || 
           response.dragged_by(egui::PointerButton::Secondary) {
            self.pan += response.drag_delta();
        }
        
        // Node interaction
        if let Some(pos) = response.interact_pointer_pos() {
            let world_pos = self.screen_to_world(pos, response.rect);
            
            // Update hover state
            self.hovered_node = None;
            for (id, node) in &self.graph.nodes {
                if node.contains(world_pos) {
                    self.hovered_node = Some(id.clone());
                    break;
                }
            }
            
            // Handle click
            if response.clicked() {
                self.graph.clear_selection();
                if let Some(ref hovered) = self.hovered_node {
                    if let Some(node) = self.graph.get_node_mut(hovered) {
                        node.selected = true;
                        self.selected_node = Some(hovered.clone());
                    }
                } else {
                    self.selected_node = None;
                }
            }
            
            // Node dragging with primary mouse
            if response.drag_started_by(egui::PointerButton::Primary) {
                if let Some(ref hovered) = self.hovered_node {
                    self.dragging_node = Some(hovered.clone());
                }
            }
            
            if response.dragged_by(egui::PointerButton::Primary) {
                if let Some(ref dragging) = self.dragging_node.clone() {
                    let delta = response.drag_delta() / self.zoom;
                    if let Some(node) = self.graph.get_node_mut(dragging) {
                        node.position += delta;
                    }
                }
            }
            
            if response.drag_stopped() {
                self.dragging_node = None;
            }
        }
        
        // Keyboard shortcuts
        if response.has_focus() || response.hovered() {
            if input.key_pressed(egui::Key::F) {
                self.fit_to_view();
            }
            if input.key_pressed(egui::Key::G) {
                self.show_grid = !self.show_grid;
            }
            if input.key_pressed(egui::Key::R) && self.source_path.is_some() {
                if let Err(e) = self.reload() {
                    self.error = Some(e.to_string());
                }
            }
        }
    }
    
    /// Get the transformation for world -> screen coordinates
    fn get_transform(&self, rect: Rect) -> Transform {
        Transform {
            offset: rect.center().to_vec2() + self.pan,
            zoom: self.zoom,
        }
    }
    
    /// Convert screen coordinates to world coordinates
    fn screen_to_world(&self, screen_pos: Pos2, rect: Rect) -> Pos2 {
        let transform = self.get_transform(rect);
        transform.to_world(screen_pos)
    }
    
    /// Draw the grid
    fn draw_grid(&self, painter: &Painter, rect: Rect) {
        let grid_size = self.grid_size * self.zoom;
        let offset = Vec2::new(
            self.pan.x.rem_euclid(grid_size),
            self.pan.y.rem_euclid(grid_size),
        );
        
        let start = rect.min + offset;
        
        // Vertical lines
        let mut x = start.x;
        while x < rect.max.x {
            painter.line_segment(
                [Pos2::new(x, rect.min.y), Pos2::new(x, rect.max.y)],
                Stroke::new(1.0, self.theme.grid_color),
            );
            x += grid_size;
        }
        
        // Horizontal lines
        let mut y = start.y;
        while y < rect.max.y {
            painter.line_segment(
                [Pos2::new(rect.min.x, y), Pos2::new(rect.max.x, y)],
                Stroke::new(1.0, self.theme.grid_color),
            );
            y += grid_size;
        }
    }
    
    /// Draw a node
    fn draw_node(&self, painter: &Painter, node: &D2Node, transform: &Transform) {
        let rect = transform.transform_rect(node.rect());
        
        // Get colors from theme
        let fill = self.theme.fill_for_shape(node.shape, &node.style);
        let stroke_color = if node.selected {
            self.theme.node_selected
        } else if node.hovered || self.hovered_node.as_ref() == Some(&node.id) {
            self.theme.node_hover
        } else {
            self.theme.stroke_for_style(&node.style)
        };
        let stroke_width = if node.selected { 3.0 } else { 1.5 };
        let text_color = self.theme.text_color(&node.style);
        
        // Draw shape
        match node.shape {
            D2Shape::Rectangle | D2Shape::Square => {
                let rounding = node.style.border_radius.unwrap_or(4.0) * self.zoom;
                painter.rect(rect, rounding, fill, Stroke::new(stroke_width, stroke_color));
            }
            D2Shape::Circle | D2Shape::Oval => {
                painter.rect(rect, rect.height() / 2.0, fill, Stroke::new(stroke_width, stroke_color));
            }
            D2Shape::Diamond => {
                let center = rect.center();
                let points = vec![
                    Pos2::new(center.x, rect.min.y),
                    Pos2::new(rect.max.x, center.y),
                    Pos2::new(center.x, rect.max.y),
                    Pos2::new(rect.min.x, center.y),
                ];
                painter.add(egui::Shape::convex_polygon(points, fill, Stroke::new(stroke_width, stroke_color)));
            }
            D2Shape::Hexagon => {
                let center = rect.center();
                let w = rect.width() / 2.0;
                let h = rect.height() / 2.0;
                let points = vec![
                    Pos2::new(center.x - w * 0.5, rect.min.y),
                    Pos2::new(center.x + w * 0.5, rect.min.y),
                    Pos2::new(rect.max.x, center.y),
                    Pos2::new(center.x + w * 0.5, rect.max.y),
                    Pos2::new(center.x - w * 0.5, rect.max.y),
                    Pos2::new(rect.min.x, center.y),
                ];
                painter.add(egui::Shape::convex_polygon(points, fill, Stroke::new(stroke_width, stroke_color)));
            }
            D2Shape::Cylinder => {
                // Draw cylinder as rectangle with rounded top/bottom
                let cap_height = rect.height() * 0.15;
                let body_rect = Rect::from_min_max(
                    Pos2::new(rect.min.x, rect.min.y + cap_height * 0.5),
                    Pos2::new(rect.max.x, rect.max.y - cap_height * 0.5),
                );
                painter.rect_filled(body_rect, 0.0, fill);
                
                // Top ellipse
                let top_center = Pos2::new(rect.center().x, rect.min.y + cap_height * 0.5);
                painter.add(egui::Shape::ellipse_filled(top_center, Vec2::new(rect.width() / 2.0, cap_height), fill));
                
                // Bottom ellipse (darker)
                let bottom_center = Pos2::new(rect.center().x, rect.max.y - cap_height * 0.5);
                painter.add(egui::Shape::ellipse_stroke(bottom_center, Vec2::new(rect.width() / 2.0, cap_height), Stroke::new(stroke_width, stroke_color)));
                
                // Outline
                painter.rect_stroke(body_rect, 0.0, Stroke::new(stroke_width, stroke_color));
                painter.add(egui::Shape::ellipse_stroke(top_center, Vec2::new(rect.width() / 2.0, cap_height), Stroke::new(stroke_width, stroke_color)));
            }
            D2Shape::Document | D2Shape::Page => {
                // Document with wavy bottom
                let points = vec![
                    rect.left_top(),
                    rect.right_top(),
                    rect.right_bottom() - Vec2::new(0.0, rect.height() * 0.1),
                    rect.center_bottom(),
                    rect.left_bottom() - Vec2::new(0.0, rect.height() * 0.1),
                ];
                painter.add(egui::Shape::convex_polygon(points, fill, Stroke::new(stroke_width, stroke_color)));
            }
            D2Shape::Cloud => {
                // Simplified cloud as rounded rectangle
                painter.rect(rect, rect.height() * 0.3, fill, Stroke::new(stroke_width, stroke_color));
            }
            D2Shape::Person => {
                // Person icon: head + body
                let head_radius = rect.width().min(rect.height()) * 0.15;
                let head_center = Pos2::new(rect.center().x, rect.min.y + head_radius * 1.5);
                painter.circle(head_center, head_radius, fill, Stroke::new(stroke_width, stroke_color));
                
                // Body (trapezoid)
                let body_top = head_center.y + head_radius + 5.0;
                let body_points = vec![
                    Pos2::new(rect.center().x - head_radius, body_top),
                    Pos2::new(rect.center().x + head_radius, body_top),
                    rect.right_bottom(),
                    rect.left_bottom(),
                ];
                painter.add(egui::Shape::convex_polygon(body_points, fill, Stroke::new(stroke_width, stroke_color)));
            }
            _ => {
                // Default to rectangle
                painter.rect(rect, 4.0 * self.zoom, fill, Stroke::new(stroke_width, stroke_color));
            }
        }
        
        // Draw status indicator if present
        if let Some(ref data) = node.data {
            if let Some(ref status) = data.status {
                if let Some(status_color) = self.theme.status_color(Some(status)) {
                    let indicator_pos = Pos2::new(rect.max.x - 8.0, rect.min.y + 8.0);
                    painter.circle_filled(indicator_pos, 5.0, status_color);
                }
            }
        }
        
        // Draw label
        let font_size = node.style.font_size.unwrap_or(14.0) * self.zoom;
        let font = FontId::proportional(font_size);
        painter.text(
            rect.center(),
            Align2::CENTER_CENTER,
            &node.label,
            font,
            text_color,
        );
    }
    
    /// Draw an edge
    fn draw_edge(&self, painter: &Painter, edge: &D2Edge, transform: &Transform) {
        // Get source and target node positions
        let from_node = match self.graph.get_node(&edge.from) {
            Some(n) => n,
            None => return,
        };
        let to_node = match self.graph.get_node(&edge.to) {
            Some(n) => n,
            None => return,
        };
        
        // Calculate connection points
        let from_rect = transform.transform_rect(from_node.rect());
        let to_rect = transform.transform_rect(to_node.rect());
        
        let (start, end) = self.calculate_edge_points(&from_rect, &to_rect);
        
        // Get edge color
        let color = self.theme.edge_color_for(&edge.style, edge.highlighted);
        let stroke_width = edge.style.stroke_width.unwrap_or(1.5);
        
        // Draw the line
        if let Some(dash) = edge.style.stroke_dash {
            // Dashed line
            self.draw_dashed_line(painter, start, end, stroke_width, color, dash * self.zoom);
        } else {
            painter.line_segment([start, end], Stroke::new(stroke_width, color));
        }
        
        // Draw arrows
        if edge.target_arrow != ArrowType::None {
            self.draw_arrow(painter, start, end, color, stroke_width, edge.target_arrow);
        }
        if edge.source_arrow != ArrowType::None {
            self.draw_arrow(painter, end, start, color, stroke_width, edge.source_arrow);
        }
        
        // Draw label if present
        if let Some(ref label) = edge.label {
            let mid = Pos2::new((start.x + end.x) / 2.0, (start.y + end.y) / 2.0);
            let font = FontId::proportional(12.0 * self.zoom);
            
            // Background for label
            let galley = painter.layout_no_wrap(label.clone(), font.clone(), self.theme.edge_text);
            let label_rect = Rect::from_center_size(mid, galley.size() + Vec2::splat(4.0));
            painter.rect_filled(label_rect, 2.0, self.theme.canvas_bg);
            
            painter.text(mid, Align2::CENTER_CENTER, label, font, self.theme.edge_text);
        }
        
        // Draw flow animation if highlighted
        if edge.highlighted && self.animate {
            self.draw_flow_animation(painter, start, end, edge.flow_progress);
        }
    }
    
    /// Calculate edge connection points between two rectangles
    fn calculate_edge_points(&self, from: &Rect, to: &Rect) -> (Pos2, Pos2) {
        let from_center = from.center();
        let to_center = to.center();
        
        let start = self.rect_intersection(from, from_center, to_center);
        let end = self.rect_intersection(to, to_center, from_center);
        
        (start, end)
    }
    
    /// Find intersection point of a line with a rectangle
    fn rect_intersection(&self, rect: &Rect, inside: Pos2, outside: Pos2) -> Pos2 {
        let dir = outside - inside;
        let mut t = f32::MAX;
        
        // Check each edge
        if dir.x != 0.0 {
            let t_left = (rect.left() - inside.x) / dir.x;
            let t_right = (rect.right() - inside.x) / dir.x;
            if t_left > 0.0 { t = t.min(t_left); }
            if t_right > 0.0 { t = t.min(t_right); }
        }
        if dir.y != 0.0 {
            let t_top = (rect.top() - inside.y) / dir.y;
            let t_bottom = (rect.bottom() - inside.y) / dir.y;
            if t_top > 0.0 { t = t.min(t_top); }
            if t_bottom > 0.0 { t = t.min(t_bottom); }
        }
        
        if t == f32::MAX { inside } else { inside + dir * t }
    }
    
    /// Draw an arrowhead
    fn draw_arrow(&self, painter: &Painter, from: Pos2, to: Pos2, color: Color32, _stroke_width: f32, arrow_type: ArrowType) {
        let dir = (from - to).normalized();
        let size = 10.0 * self.zoom;
        let angle: f32 = 0.4; // ~25 degrees
        
        let left = to + Vec2::new(
            dir.x * angle.cos() - dir.y * angle.sin(),
            dir.x * angle.sin() + dir.y * angle.cos(),
        ) * size;
        
        let right = to + Vec2::new(
            dir.x * angle.cos() + dir.y * angle.sin(),
            -dir.x * angle.sin() + dir.y * angle.cos(),
        ) * size;
        
        match arrow_type {
            ArrowType::Arrow | ArrowType::Triangle => {
                let points = vec![to, left, right];
                painter.add(egui::Shape::convex_polygon(points, color, Stroke::NONE));
            }
            ArrowType::Diamond => {
                let back = to + dir * size;
                let points = vec![to, left, back, right];
                painter.add(egui::Shape::convex_polygon(points, color, Stroke::NONE));
            }
            ArrowType::Circle => {
                painter.circle_filled(to + dir * (size / 2.0), size / 2.0, color);
            }
            ArrowType::None => {}
        }
    }
    
    /// Draw a dashed line
    fn draw_dashed_line(&self, painter: &Painter, start: Pos2, end: Pos2, width: f32, color: Color32, dash_len: f32) {
        let dir = end - start;
        let len = dir.length();
        let dir = dir / len;
        
        let mut pos = 0.0;
        let mut drawing = true;
        
        while pos < len {
            let next = (pos + dash_len).min(len);
            if drawing {
                let p1 = start + dir * pos;
                let p2 = start + dir * next;
                painter.line_segment([p1, p2], Stroke::new(width, color));
            }
            pos = next;
            drawing = !drawing;
        }
    }
    
    /// Draw flow animation on an edge
    fn draw_flow_animation(&self, painter: &Painter, start: Pos2, end: Pos2, progress: f32) {
        let dir = end - start;
        let len = dir.length();
        
        // Animated dot moving along the edge
        let t = (self.animation_time * 0.5 + progress).fract();
        let pos = start + dir * t;
        
        painter.circle_filled(pos, 4.0 * self.zoom, self.theme.edge_flow);
    }
    
    /// Draw toolbar
    fn draw_toolbar(&mut self, ui: &mut egui::Ui, rect: Rect) {
        let toolbar_rect = Rect::from_min_size(
            rect.min + Vec2::new(10.0, 10.0),
            Vec2::new(200.0, 30.0),
        );
        
        ui.allocate_ui_at_rect(toolbar_rect, |ui| {
            ui.horizontal(|ui| {
                if ui.small_button("⟳").on_hover_text("Reload (R)").clicked() {
                    if let Err(e) = self.reload() {
                        self.error = Some(e.to_string());
                    }
                }
                if ui.small_button("⊞").on_hover_text("Fit to view (F)").clicked() {
                    self.fit_to_view();
                }
                if ui.small_button("▦").on_hover_text("Toggle grid (G)").clicked() {
                    self.show_grid = !self.show_grid;
                }
                ui.label(format!("{:.0}%", self.zoom * 100.0));
            });
        });
    }
    
    /// Draw minimap
    fn draw_minimap(&self, painter: &Painter, rect: Rect) {
        let minimap_size = Vec2::new(150.0, 100.0);
        let minimap_rect = Rect::from_min_size(
            Pos2::new(rect.max.x - minimap_size.x - 10.0, rect.max.y - minimap_size.y - 10.0),
            minimap_size,
        );
        
        // Background
        painter.rect_filled(minimap_rect, 4.0, Color32::from_rgba_unmultiplied(0, 0, 0, 150));
        painter.rect_stroke(minimap_rect, 4.0, Stroke::new(1.0, self.theme.node_stroke));
        
        // Scale to fit graph bounds in minimap
        let scale = if self.graph.bounds.width() > 0.0 && self.graph.bounds.height() > 0.0 {
            (minimap_size.x / self.graph.bounds.width())
                .min(minimap_size.y / self.graph.bounds.height())
                * 0.8
        } else {
            1.0
        };
        
        // Draw nodes in minimap
        for node in self.graph.nodes.values() {
            let node_offset = Vec2::new(
                node.position.x - self.graph.bounds.min.x,
                node.position.y - self.graph.bounds.min.y,
            );
            let node_rect = Rect::from_min_size(
                minimap_rect.min + node_offset * scale + Vec2::splat(10.0),
                node.size * scale,
            );
            
            let color = if Some(&node.id) == self.selected_node.as_ref() {
                self.theme.node_selected
            } else {
                self.theme.node_fill
            };
            
            painter.rect_filled(node_rect, 1.0, color);
        }
        
        // Draw viewport indicator
        let viewport_center = Pos2::new(-self.pan.x, -self.pan.y);
        let viewport_in_world = Rect::from_center_size(
            viewport_center,
            rect.size() / self.zoom,
        );
        
        let viewport_offset = Vec2::new(
            viewport_in_world.min.x - self.graph.bounds.min.x,
            viewport_in_world.min.y - self.graph.bounds.min.y,
        );
        let viewport_in_minimap = Rect::from_min_size(
            minimap_rect.min + viewport_offset * scale + Vec2::splat(10.0),
            viewport_in_world.size() * scale,
        );
        
        painter.rect_stroke(viewport_in_minimap, 0.0, Stroke::new(1.0, self.theme.node_stroke));
    }
    
    /// Draw error message
    fn draw_error(&self, painter: &Painter, rect: Rect, error: &str) {
        let error_rect = Rect::from_center_size(rect.center(), Vec2::new(400.0, 60.0));
        painter.rect_filled(error_rect, 8.0, Color32::from_rgb(60, 20, 20));
        painter.rect_stroke(error_rect, 8.0, Stroke::new(2.0, self.theme.status_error));
        
        let font = FontId::proportional(14.0);
        painter.text(
            error_rect.center(),
            Align2::CENTER_CENTER,
            format!("⚠ {}", error),
            font,
            self.theme.status_error,
        );
    }
}

/// Coordinate transformation helper
struct Transform {
    offset: Vec2,
    zoom: f32,
}

impl Transform {
    fn to_screen(&self, world: Pos2) -> Pos2 {
        Pos2::new(
            world.x * self.zoom + self.offset.x,
            world.y * self.zoom + self.offset.y,
        )
    }
    
    fn to_world(&self, screen: Pos2) -> Pos2 {
        Pos2::new(
            (screen.x - self.offset.x) / self.zoom,
            (screen.y - self.offset.y) / self.zoom,
        )
    }
    
    fn transform_rect(&self, rect: Rect) -> Rect {
        Rect::from_min_max(
            self.to_screen(rect.min),
            self.to_screen(rect.max),
        )
    }
}

// Re-export parse functions
pub use super::parser::{parse_file as load_d2_file, parse_string as load_d2_string};
