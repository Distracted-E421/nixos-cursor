//! Theme Mapper for D2 Diagrams
//!
//! Maps D2 style colors to VS Code theme-aware colors.

use eframe::egui::Color32;
use crate::theme::Theme;
use super::graph::{D2Style, D2Shape};

/// Diagram-specific theme derived from VS Code theme
#[derive(Clone, Copy)]
pub struct DiagramTheme {
    /// Background color for the canvas
    pub canvas_bg: Color32,
    
    /// Grid line color
    pub grid_color: Color32,
    
    /// Default node fill
    pub node_fill: Color32,
    
    /// Default node stroke
    pub node_stroke: Color32,
    
    /// Node text color
    pub node_text: Color32,
    
    /// Selected node highlight
    pub node_selected: Color32,
    
    /// Hovered node highlight
    pub node_hover: Color32,
    
    /// Container/group fill
    pub container_fill: Color32,
    
    /// Container border
    pub container_stroke: Color32,
    
    /// Edge/connection color
    pub edge_color: Color32,
    
    /// Edge label color
    pub edge_text: Color32,
    
    /// Highlighted edge (data flow)
    pub edge_highlight: Color32,
    
    /// Edge animation color
    pub edge_flow: Color32,
    
    /// Database/cylinder shape color
    pub shape_database: Color32,
    
    /// Document shape color
    pub shape_document: Color32,
    
    /// Hexagon shape color
    pub shape_hexagon: Color32,
    
    /// Error/warning indicator
    pub status_error: Color32,
    pub status_warning: Color32,
    pub status_success: Color32,
    pub status_active: Color32,
}

impl DiagramTheme {
    /// Create diagram theme from VS Code theme
    pub fn from_vscode_theme(theme: &Theme) -> Self {
        let is_dark = !theme.is_light();
        
        Self {
            // Canvas uses slightly different shade than editor
            canvas_bg: if is_dark {
                darken(theme.editor_bg, 0.1)
            } else {
                lighten(theme.editor_bg, 0.02)
            },
            
            // Grid is very subtle
            grid_color: if is_dark {
                Color32::from_rgba_unmultiplied(255, 255, 255, 15)
            } else {
                Color32::from_rgba_unmultiplied(0, 0, 0, 15)
            },
            
            // Nodes use sidebar-like colors
            node_fill: if is_dark {
                lighten(theme.sidebar_bg, 0.1)
            } else {
                theme.sidebar_bg
            },
            node_stroke: theme.accent,
            node_text: theme.fg,
            
            // Selection uses accent colors
            node_selected: theme.selected_bg,
            node_hover: theme.list_hover,
            
            // Containers are more transparent
            container_fill: Color32::from_rgba_unmultiplied(
                theme.sidebar_bg.r(),
                theme.sidebar_bg.g(),
                theme.sidebar_bg.b(),
                180,
            ),
            container_stroke: theme.border,
            
            // Edges use dimmer colors
            edge_color: theme.fg_dim,
            edge_text: theme.fg_dim,
            edge_highlight: theme.accent,
            edge_flow: theme.success,
            
            // Shape-specific colors using syntax highlighting
            shape_database: theme.syntax_type,      // Teal for database
            shape_document: theme.syntax_string,    // Orange for documents
            shape_hexagon: theme.syntax_function,   // Yellow for agents/processes
            
            // Status colors
            status_error: theme.error,
            status_warning: theme.warning,
            status_success: theme.success,
            status_active: theme.accent,
        }
    }
    
    /// Get default dark theme
    pub fn dark() -> Self {
        Self::from_vscode_theme(&Theme::dark())
    }
    
    /// Get default light theme
    pub fn light() -> Self {
        Self::from_vscode_theme(&Theme::light())
    }
    
    /// Get fill color for a shape, considering style overrides
    pub fn fill_for_shape(&self, shape: D2Shape, style: &D2Style) -> Color32 {
        // If style has explicit fill, use it
        if let Some(ref fill) = style.fill {
            if let Some(color) = parse_hex_color(fill) {
                return apply_opacity(color, style.opacity);
            }
        }
        
        // Otherwise use shape-specific defaults
        let base = match shape {
            D2Shape::Cylinder | D2Shape::StoredData => self.shape_database,
            D2Shape::Document | D2Shape::Page => self.shape_document,
            D2Shape::Hexagon => self.shape_hexagon,
            D2Shape::Diamond => self.status_warning,
            D2Shape::Circle | D2Shape::Oval => self.node_stroke,
            _ => self.node_fill,
        };
        
        apply_opacity(base, style.opacity)
    }
    
    /// Get stroke color, considering style overrides
    pub fn stroke_for_style(&self, style: &D2Style) -> Color32 {
        if let Some(ref stroke) = style.stroke {
            if let Some(color) = parse_hex_color(stroke) {
                return color;
            }
        }
        self.node_stroke
    }
    
    /// Get text color for a node
    pub fn text_color(&self, style: &D2Style) -> Color32 {
        if let Some(ref fc) = style.font_color {
            if let Some(color) = parse_hex_color(fc) {
                return color;
            }
        }
        self.node_text
    }
    
    /// Get edge color, considering style and highlight state
    pub fn edge_color_for(&self, style: &D2Style, highlighted: bool) -> Color32 {
        if highlighted {
            return self.edge_highlight;
        }
        
        if let Some(ref stroke) = style.stroke {
            if let Some(color) = parse_hex_color(stroke) {
                return color;
            }
        }
        
        self.edge_color
    }
    
    /// Get status indicator color
    pub fn status_color(&self, status: Option<&str>) -> Option<Color32> {
        status.map(|s| match s.to_lowercase().as_str() {
            "error" | "failed" | "critical" => self.status_error,
            "warning" | "warn" | "degraded" => self.status_warning,
            "success" | "ok" | "healthy" => self.status_success,
            "active" | "running" | "connected" => self.status_active,
            _ => self.node_stroke,
        })
    }
}

/// Parse a hex color string to Color32
fn parse_hex_color(color_str: &str) -> Option<Color32> {
    let hex = color_str.trim_start_matches('#');
    
    if hex.len() == 6 {
        let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
        let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
        let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
        Some(Color32::from_rgb(r, g, b))
    } else if hex.len() == 8 {
        let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
        let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
        let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
        let a = u8::from_str_radix(&hex[6..8], 16).ok()?;
        Some(Color32::from_rgba_unmultiplied(r, g, b, a))
    } else {
        None
    }
}

/// Darken a color by a factor (0.0 - 1.0)
fn darken(color: Color32, factor: f32) -> Color32 {
    let factor = (1.0 - factor).max(0.0);
    Color32::from_rgb(
        (color.r() as f32 * factor) as u8,
        (color.g() as f32 * factor) as u8,
        (color.b() as f32 * factor) as u8,
    )
}

/// Lighten a color by a factor (0.0 - 1.0)
fn lighten(color: Color32, factor: f32) -> Color32 {
    Color32::from_rgb(
        (color.r() as f32 + (255.0 - color.r() as f32) * factor) as u8,
        (color.g() as f32 + (255.0 - color.g() as f32) * factor) as u8,
        (color.b() as f32 + (255.0 - color.b() as f32) * factor) as u8,
    )
}

/// Apply opacity to a color
fn apply_opacity(color: Color32, opacity: f32) -> Color32 {
    Color32::from_rgba_unmultiplied(
        color.r(),
        color.g(),
        color.b(),
        (color.a() as f32 * opacity) as u8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_hex_color_parsing() {
        assert_eq!(
            parse_hex_color("#ff0000"),
            Some(Color32::from_rgb(255, 0, 0))
        );
        assert_eq!(
            parse_hex_color("#00ff0080"),
            Some(Color32::from_rgba_unmultiplied(0, 255, 0, 128))
        );
        assert_eq!(parse_hex_color("invalid"), None);
    }
    
    #[test]
    fn test_darken_lighten() {
        let white = Color32::from_rgb(255, 255, 255);
        let darkened = darken(white, 0.5);
        assert_eq!(darkened.r(), 127);
        
        let black = Color32::from_rgb(0, 0, 0);
        let lightened = lighten(black, 0.5);
        assert_eq!(lightened.r(), 127);
    }
}
