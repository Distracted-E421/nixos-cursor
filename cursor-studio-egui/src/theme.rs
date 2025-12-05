//! Theme definitions for egui and VS Code theme parsing

use eframe::egui::Color32;
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

/// VS Code Dark+ inspired theme
#[derive(Clone, Copy)]
pub struct Theme {
    // Computed indicator colors (for selected states)
    // These are derived from the theme to ensure proper contrast
    pub selected_bg: Color32,
    pub selected_fg: Color32,
    pub bg: Color32,
    pub editor_bg: Color32,
    pub sidebar_bg: Color32,
    pub activitybar_bg: Color32,
    pub statusbar_bg: Color32,
    pub tab_bg: Color32,
    pub tab_active_bg: Color32,
    pub tab_hover_bg: Color32,
    pub input_bg: Color32,
    pub code_bg: Color32,

    pub fg: Color32,
    pub fg_dim: Color32,
    pub fg_bright: Color32,

    pub accent: Color32,
    pub accent_hover: Color32,
    pub accent_dim: Color32,

    pub success: Color32,
    pub warning: Color32,
    pub error: Color32,

    pub border: Color32,
    pub selection: Color32,
    pub list_hover: Color32,

    // Syntax highlighting colors
    pub syntax_keyword: Color32,
    pub syntax_string: Color32,
    pub syntax_number: Color32,
    pub syntax_comment: Color32,
    pub syntax_function: Color32,
    pub syntax_variable: Color32,
    pub syntax_type: Color32,
    pub syntax_operator: Color32,
}

impl Theme {
    pub fn dark() -> Self {
        Self {
            // Selected state colors - bright and visible on dark themes
            selected_bg: Color32::from_rgb(0, 120, 212), // Blue accent background
            selected_fg: Color32::from_rgb(255, 255, 255), // White text

            bg: Color32::from_rgb(30, 30, 30),         // #1e1e1e
            editor_bg: Color32::from_rgb(30, 30, 30),  // #1e1e1e
            sidebar_bg: Color32::from_rgb(37, 37, 38), // #252526
            activitybar_bg: Color32::from_rgb(51, 51, 51), // #333333
            statusbar_bg: Color32::from_rgb(0, 122, 204), // #007acc
            tab_bg: Color32::from_rgb(45, 45, 45),     // #2d2d2d
            tab_active_bg: Color32::from_rgb(30, 30, 30), // #1e1e1e
            tab_hover_bg: Color32::from_rgb(55, 55, 55), // #373737
            input_bg: Color32::from_rgb(60, 60, 60),   // #3c3c3c
            code_bg: Color32::from_rgb(26, 26, 26),    // #1a1a1a

            fg: Color32::from_rgb(204, 204, 204),     // #cccccc
            fg_dim: Color32::from_rgb(128, 128, 128), // #808080
            fg_bright: Color32::from_rgb(255, 255, 255), // #ffffff

            accent: Color32::from_rgb(0, 120, 212), // #0078d4
            accent_hover: Color32::from_rgb(26, 140, 255), // #1a8cff
            accent_dim: Color32::from_rgb(38, 79, 120), // #264f78

            success: Color32::from_rgb(63, 185, 80), // #3fb950
            warning: Color32::from_rgb(204, 167, 0), // #cca700
            error: Color32::from_rgb(248, 81, 73),   // #f85149

            border: Color32::from_rgb(60, 60, 60), // #3c3c3c
            selection: Color32::from_rgb(38, 79, 120), // #264f78
            list_hover: Color32::from_rgb(42, 45, 46), // #2a2d2e

            // Syntax highlighting (VS Code Dark+ defaults)
            syntax_keyword: Color32::from_rgb(86, 156, 214), // #569cd6 - blue
            syntax_string: Color32::from_rgb(206, 145, 120), // #ce9178 - orange
            syntax_number: Color32::from_rgb(181, 206, 168), // #b5cea8 - light green
            syntax_comment: Color32::from_rgb(106, 153, 85), // #6a9955 - green
            syntax_function: Color32::from_rgb(220, 220, 170), // #dcdcaa - yellow
            syntax_variable: Color32::from_rgb(156, 220, 254), // #9cdcfe - light blue
            syntax_type: Color32::from_rgb(78, 201, 176),    // #4ec9b0 - teal
            syntax_operator: Color32::from_rgb(212, 212, 212), // #d4d4d4 - light gray
        }
    }

    pub fn light() -> Self {
        Self {
            // Selected state colors - visible on light themes
            selected_bg: Color32::from_rgb(0, 120, 212), // Blue accent background
            selected_fg: Color32::from_rgb(255, 255, 255), // White text

            bg: Color32::from_rgb(255, 255, 255), // #ffffff
            editor_bg: Color32::from_rgb(255, 255, 255), // #ffffff
            sidebar_bg: Color32::from_rgb(243, 243, 243), // #f3f3f3
            activitybar_bg: Color32::from_rgb(51, 51, 51), // #333333
            statusbar_bg: Color32::from_rgb(0, 122, 204), // #007acc
            tab_bg: Color32::from_rgb(236, 236, 236), // #ececec
            tab_active_bg: Color32::from_rgb(255, 255, 255), // #ffffff
            tab_hover_bg: Color32::from_rgb(220, 220, 220), // #dcdcdc
            input_bg: Color32::from_rgb(255, 255, 255), // #ffffff
            code_bg: Color32::from_rgb(248, 248, 248), // #f8f8f8

            fg: Color32::from_rgb(51, 51, 51),        // #333333
            fg_dim: Color32::from_rgb(128, 128, 128), // #808080
            fg_bright: Color32::from_rgb(0, 0, 0),    // #000000

            accent: Color32::from_rgb(0, 120, 212), // #0078d4
            accent_hover: Color32::from_rgb(26, 140, 255), // #1a8cff
            accent_dim: Color32::from_rgb(200, 220, 240), // light blue

            success: Color32::from_rgb(40, 160, 40), // green
            warning: Color32::from_rgb(180, 130, 0), // amber
            error: Color32::from_rgb(200, 50, 50),   // red

            border: Color32::from_rgb(200, 200, 200), // light gray
            selection: Color32::from_rgb(173, 214, 255), // light blue selection
            list_hover: Color32::from_rgb(232, 232, 232), // very light gray

            // Syntax highlighting (VS Code Light+ defaults)
            syntax_keyword: Color32::from_rgb(0, 0, 255), // #0000ff - blue
            syntax_string: Color32::from_rgb(163, 21, 21), // #a31515 - red
            syntax_number: Color32::from_rgb(9, 136, 90), // #09885a - green
            syntax_comment: Color32::from_rgb(0, 128, 0), // #008000 - green
            syntax_function: Color32::from_rgb(121, 94, 38), // #795e26 - brown
            syntax_variable: Color32::from_rgb(0, 16, 128), // #001080 - dark blue
            syntax_type: Color32::from_rgb(38, 127, 153), // #267f99 - teal
            syntax_operator: Color32::from_rgb(0, 0, 0),  // #000000 - black
        }
    }

    /// Load a theme from a VS Code theme JSON file
    pub fn from_vscode_file(path: &Path) -> Option<Self> {
        let content = std::fs::read_to_string(path).ok()?;
        Self::from_vscode_json(&content)
    }

    /// Parse a VS Code theme from JSON content
    pub fn from_vscode_json(json_content: &str) -> Option<Self> {
        // VS Code themes can have comments, so we need to strip them
        let cleaned = strip_json_comments(json_content);

        let theme_json: VSCodeTheme = match serde_json::from_str(&cleaned) {
            Ok(t) => t,
            Err(e) => {
                log::warn!("Failed to parse theme JSON: {}", e);
                return None;
            }
        };

        // Determine if light or dark theme based on type field or name
        let is_light = theme_json.theme_type.as_deref() == Some("light")
            || theme_json.theme_type.as_deref() == Some("hc-light")
            || theme_json
                .name
                .as_ref()
                .map(|n| n.to_lowercase().contains("light"))
                .unwrap_or(false);

        let mut theme = if is_light {
            Self::light()
        } else {
            Self::dark()
        };

        // Track if we loaded any colors
        let mut loaded_colors = false;

        // Parse colors from the theme
        if let Some(colors) = &theme_json.colors {
            loaded_colors = true;
            
            // Editor colors
            if let Some(c) = colors.get("editor.background") {
                if let Some(color) = parse_color(c) {
                    theme.editor_bg = color;
                    theme.bg = color;
                    theme.tab_active_bg = color;
                }
            }

            if let Some(c) = colors.get("editor.foreground") {
                if let Some(color) = parse_color(c) {
                    theme.fg = color;
                }
            }
            
            // Additional fallback: try "foreground" if editor.foreground not found
            if let Some(c) = colors.get("foreground") {
                if let Some(color) = parse_color(c) {
                    theme.fg_bright = color;
                    // Only set fg if not already set
                    if theme.fg == Theme::dark().fg {
                        theme.fg = color;
                    }
                }
            }

            // Sidebar
            if let Some(c) = colors.get("sideBar.background") {
                if let Some(color) = parse_color(c) {
                    theme.sidebar_bg = color;
                }
            }

            // Activity bar
            if let Some(c) = colors.get("activityBar.background") {
                if let Some(color) = parse_color(c) {
                    theme.activitybar_bg = color;
                }
            }

            // Status bar
            if let Some(c) = colors.get("statusBar.background") {
                if let Some(color) = parse_color(c) {
                    theme.statusbar_bg = color;
                }
            }

            // Tabs
            if let Some(c) = colors.get("tab.inactiveBackground") {
                if let Some(color) = parse_color(c) {
                    theme.tab_bg = color;
                }
            }

            if let Some(c) = colors.get("tab.activeBackground") {
                if let Some(color) = parse_color(c) {
                    theme.tab_active_bg = color;
                }
            }

            // Input
            if let Some(c) = colors.get("input.background") {
                if let Some(color) = parse_color(c) {
                    theme.input_bg = color;
                }
            }

            // Selection
            if let Some(c) = colors.get("editor.selectionBackground") {
                if let Some(color) = parse_color(c) {
                    theme.selection = color;
                }
            }

            // Accent / focus - try multiple VS Code properties
            // Priority: button.background > focusBorder > list.activeSelectionBackground
            let accent_sources = [
                "button.background",
                "button.hoverBackground",
                "focusBorder",
                "list.activeSelectionBackground",
                "activityBarBadge.background",
            ];
            for source in accent_sources {
                if let Some(c) = colors.get(source) {
                    if let Some(color) = parse_color(c) {
                        // Only use if reasonably visible (not too dark or transparent)
                        let brightness =
                            (color.r() as u32 + color.g() as u32 + color.b() as u32) / 3;
                        if brightness > 40 && color.a() > 128 {
                            theme.accent = color;
                            break;
                        }
                    }
                }
            }

            // Selected state background - use list selection colors
            let selection_sources = [
                "list.activeSelectionBackground",
                "list.inactiveSelectionBackground",
                "button.background",
                "editor.selectionBackground",
            ];
            for source in selection_sources {
                if let Some(c) = colors.get(source) {
                    if let Some(color) = parse_color(c) {
                        let brightness =
                            (color.r() as u32 + color.g() as u32 + color.b() as u32) / 3;
                        if brightness > 30 && color.a() > 100 {
                            theme.selected_bg = color;
                            break;
                        }
                    }
                }
            }

            // Selected state foreground - use list selection foreground
            let fg_selection_sources = [
                "list.activeSelectionForeground",
                "button.foreground",
                "list.focusForeground",
            ];
            for source in fg_selection_sources {
                if let Some(c) = colors.get(source) {
                    if let Some(color) = parse_color(c) {
                        theme.selected_fg = color;
                        break;
                    }
                }
            }

            // List hover
            if let Some(c) = colors.get("list.hoverBackground") {
                if let Some(color) = parse_color(c) {
                    theme.list_hover = color;
                }
            }

            // Border
            if let Some(c) = colors.get("panel.border") {
                if let Some(color) = parse_color(c) {
                    theme.border = color;
                }
            }

            // Foreground dim - try VS Code's descriptionForeground
            if let Some(c) = colors.get("descriptionForeground") {
                if let Some(color) = parse_color(c) {
                    theme.fg_dim = color;
                }
            }
        }

        // Compute selected state colors based on theme brightness
        theme.compute_selected_colors();

        // Parse token colors for syntax highlighting
        if let Some(token_colors) = &theme_json.token_colors {
            for token in token_colors {
                if let (Some(scope), Some(settings)) = (&token.scope, &token.settings) {
                    if let Some(fg) = settings.get("foreground").and_then(|f| f.as_str()) {
                        if let Some(color) = parse_color(fg) {
                            let scope_str = match scope {
                                VSCodeScope::String(s) => s.as_str(),
                                VSCodeScope::Array(arr) => {
                                    arr.first().map(|s| s.as_str()).unwrap_or("")
                                }
                            };

                            // Map scopes to our syntax colors
                            if scope_str.contains("keyword") {
                                theme.syntax_keyword = color;
                            } else if scope_str.contains("string") {
                                theme.syntax_string = color;
                            } else if scope_str.contains("constant.numeric")
                                || scope_str.contains("number")
                            {
                                theme.syntax_number = color;
                            } else if scope_str.contains("comment") {
                                theme.syntax_comment = color;
                            } else if scope_str.contains("entity.name.function")
                                || scope_str.contains("support.function")
                            {
                                theme.syntax_function = color;
                            } else if scope_str.contains("variable") {
                                theme.syntax_variable = color;
                            } else if scope_str.contains("entity.name.type")
                                || scope_str.contains("support.type")
                            {
                                theme.syntax_type = color;
                            }
                        }
                    }
                }
            }
        }
        
        // Log if no colors were found
        if !loaded_colors {
            log::info!("Theme has no 'colors' section, using defaults with token colors only");
        }

        Some(theme)
    }

    /// Compute selected state colors based on theme brightness
    /// This ensures buttons/icons have proper contrast when selected
    pub fn compute_selected_colors(&mut self) {
        // Calculate background brightness (0-255 scale)
        let bg_brightness = (self.bg.r() as u32 + self.bg.g() as u32 + self.bg.b() as u32) / 3;

        if bg_brightness > 128 {
            // Light theme - use darker selected colors
            self.selected_bg = Color32::from_rgb(0, 100, 180); // Darker blue
            self.selected_fg = Color32::from_rgb(255, 255, 255); // White
        } else {
            // Dark theme - use brighter selected colors
            // If accent is very dark, override with a visible color
            let accent_brightness =
                (self.accent.r() as u32 + self.accent.g() as u32 + self.accent.b() as u32) / 3;
            if accent_brightness < 80 {
                // Accent is too dark, use a default blue
                self.selected_bg = Color32::from_rgb(30, 136, 229); // Bright blue
            } else {
                self.selected_bg = self.accent;
            }
            self.selected_fg = Color32::from_rgb(255, 255, 255); // White
        }
    }

    /// Check if this is a light theme
    pub fn is_light(&self) -> bool {
        let brightness = (self.bg.r() as u32 + self.bg.g() as u32 + self.bg.b() as u32) / 3;
        brightness > 128
    }
}

/// VS Code theme JSON structure
#[derive(Debug, Deserialize)]
struct VSCodeTheme {
    name: Option<String>,
    #[serde(rename = "type")]
    theme_type: Option<String>,
    colors: Option<HashMap<String, String>>,
    #[serde(rename = "tokenColors")]
    token_colors: Option<Vec<TokenColor>>,
}

#[derive(Debug, Deserialize)]
struct TokenColor {
    scope: Option<VSCodeScope>,
    settings: Option<HashMap<String, serde_json::Value>>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum VSCodeScope {
    String(String),
    Array(Vec<String>),
}

/// Parse a hex color string to Color32
fn parse_color(color_str: &str) -> Option<Color32> {
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

/// Strip C-style comments from JSON (VS Code themes often have comments)
fn strip_json_comments(json: &str) -> String {
    let mut result = String::with_capacity(json.len());
    let mut chars = json.chars().peekable();
    let mut in_string = false;

    while let Some(c) = chars.next() {
        if in_string {
            result.push(c);
            if c == '\\' {
                // Skip escaped character
                if let Some(next) = chars.next() {
                    result.push(next);
                }
            } else if c == '"' {
                in_string = false;
            }
        } else if c == '"' {
            in_string = true;
            result.push(c);
        } else if c == '/' {
            if chars.peek() == Some(&'/') {
                // Line comment - skip to end of line
                for nc in chars.by_ref() {
                    if nc == '\n' {
                        result.push('\n');
                        break;
                    }
                }
            } else if chars.peek() == Some(&'*') {
                // Block comment - skip to */
                chars.next(); // consume *
                while let Some(nc) = chars.next() {
                    if nc == '*' && chars.peek() == Some(&'/') {
                        chars.next(); // consume /
                        break;
                    }
                }
            } else {
                result.push(c);
            }
        } else {
            result.push(c);
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_color() {
        assert_eq!(
            parse_color("#ffffff"),
            Some(Color32::from_rgb(255, 255, 255))
        );
        assert_eq!(parse_color("#000000"), Some(Color32::from_rgb(0, 0, 0)));
        assert_eq!(parse_color("#ff0000"), Some(Color32::from_rgb(255, 0, 0)));
        assert_eq!(
            parse_color("#00ff0080"),
            Some(Color32::from_rgba_unmultiplied(0, 255, 0, 128))
        );
    }

    #[test]
    fn test_strip_comments() {
        let with_comments = r#"{
            // This is a comment
            "key": "value", /* inline comment */
            "key2": "value2"
        }"#;

        let stripped = strip_json_comments(with_comments);
        assert!(!stripped.contains("//"));
        assert!(!stripped.contains("/*"));
    }
}
