//! D2 Syntax Highlighting
//!
//! Provides syntax highlighting for D2 source code in the editor.

use eframe::egui::Color32;
use std::ops::Range;

/// A syntax highlight span
#[derive(Debug, Clone)]
pub struct HighlightSpan {
    /// Range of characters in the source
    pub range: Range<usize>,
    /// Highlight type
    pub kind: HighlightKind,
}

/// Types of syntax elements
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HighlightKind {
    /// Comments: # ...
    Comment,
    /// String literals: "..."
    String,
    /// Keywords: direction, title, shape, style, etc.
    Keyword,
    /// Node identifiers
    Identifier,
    /// Property names: fill, stroke, etc.
    Property,
    /// Operators: ->, <-, --, :
    Operator,
    /// Numbers
    Number,
    /// Colors: #ff0000
    Color,
    /// Shape names: rectangle, cylinder, etc.
    Shape,
    /// Braces: { }
    Brace,
    /// Punctuation: . ; ,
    Punctuation,
    /// Error/invalid syntax
    Error,
}

impl HighlightKind {
    /// Get color for this highlight kind (Dark+ theme)
    pub fn color_dark(&self) -> Color32 {
        match self {
            HighlightKind::Comment => Color32::from_rgb(106, 153, 85),     // Green
            HighlightKind::String => Color32::from_rgb(206, 145, 120),     // Orange
            HighlightKind::Keyword => Color32::from_rgb(86, 156, 214),     // Blue
            HighlightKind::Identifier => Color32::from_rgb(156, 220, 254), // Light blue
            HighlightKind::Property => Color32::from_rgb(156, 220, 254),   // Light blue
            HighlightKind::Operator => Color32::from_rgb(212, 212, 212),   // Light gray
            HighlightKind::Number => Color32::from_rgb(181, 206, 168),     // Light green
            HighlightKind::Color => Color32::from_rgb(206, 145, 120),      // Orange
            HighlightKind::Shape => Color32::from_rgb(78, 201, 176),       // Teal
            HighlightKind::Brace => Color32::from_rgb(220, 220, 170),      // Yellow
            HighlightKind::Punctuation => Color32::from_rgb(212, 212, 212), // Light gray
            HighlightKind::Error => Color32::from_rgb(244, 71, 71),        // Red
        }
    }
    
    /// Get color for this highlight kind (Light theme)
    pub fn color_light(&self) -> Color32 {
        match self {
            HighlightKind::Comment => Color32::from_rgb(0, 128, 0),        // Green
            HighlightKind::String => Color32::from_rgb(163, 21, 21),       // Red
            HighlightKind::Keyword => Color32::from_rgb(0, 0, 255),        // Blue
            HighlightKind::Identifier => Color32::from_rgb(0, 16, 128),    // Dark blue
            HighlightKind::Property => Color32::from_rgb(0, 16, 128),      // Dark blue
            HighlightKind::Operator => Color32::from_rgb(0, 0, 0),         // Black
            HighlightKind::Number => Color32::from_rgb(9, 136, 90),        // Green
            HighlightKind::Color => Color32::from_rgb(163, 21, 21),        // Red
            HighlightKind::Shape => Color32::from_rgb(38, 127, 153),       // Teal
            HighlightKind::Brace => Color32::from_rgb(121, 94, 38),        // Brown
            HighlightKind::Punctuation => Color32::from_rgb(0, 0, 0),      // Black
            HighlightKind::Error => Color32::from_rgb(200, 0, 0),          // Red
        }
    }
}

/// D2 syntax highlighter
pub struct D2Highlighter {
    /// Known keywords
    keywords: Vec<&'static str>,
    /// Known properties
    properties: Vec<&'static str>,
    /// Known shapes
    shapes: Vec<&'static str>,
}

impl Default for D2Highlighter {
    fn default() -> Self {
        Self::new()
    }
}

impl D2Highlighter {
    pub fn new() -> Self {
        Self {
            keywords: vec![
                "direction", "title", "label", "icon", "tooltip", "link",
                "near", "width", "height", "top", "left", "grid-rows", "grid-columns",
                "horizontal-gap", "vertical-gap", "class", "classes", "vars",
            ],
            properties: vec![
                "shape", "fill", "stroke", "stroke-width", "stroke-dash", "font-color",
                "font-size", "bold", "italic", "underline", "opacity", "shadow", "3d",
                "multiple", "double-border", "border-radius", "animated", "filled",
                "source-arrowhead", "target-arrowhead", "constraint",
            ],
            shapes: vec![
                "rectangle", "square", "page", "parallelogram", "document", "cylinder",
                "queue", "package", "step", "callout", "stored_data", "person", "diamond",
                "oval", "circle", "hexagon", "cloud", "text", "code", "class", "sql_table",
                "image", "sequence_diagram",
            ],
        }
    }
    
    /// Highlight D2 source code
    pub fn highlight(&self, source: &str) -> Vec<HighlightSpan> {
        let mut spans = Vec::new();
        let mut pos = 0;
        let chars: Vec<char> = source.chars().collect();
        let len = chars.len();
        
        while pos < len {
            let ch = chars[pos];
            
            // Skip whitespace
            if ch.is_whitespace() {
                pos += 1;
                continue;
            }
            
            // Comment: # to end of line
            if ch == '#' {
                let start = pos;
                while pos < len && chars[pos] != '\n' {
                    pos += 1;
                }
                spans.push(HighlightSpan {
                    range: start..pos,
                    kind: HighlightKind::Comment,
                });
                continue;
            }
            
            // String: "..." or '...'
            if ch == '"' || ch == '\'' {
                let quote = ch;
                let start = pos;
                pos += 1;
                while pos < len && chars[pos] != quote {
                    if chars[pos] == '\\' && pos + 1 < len {
                        pos += 2;
                    } else {
                        pos += 1;
                    }
                }
                if pos < len {
                    pos += 1; // Include closing quote
                }
                spans.push(HighlightSpan {
                    range: start..pos,
                    kind: HighlightKind::String,
                });
                continue;
            }
            
            // Color: #xxxxxx
            if ch == '#' || (pos > 0 && chars[pos-1] == ':' && ch.is_ascii_hexdigit()) {
                // This would conflict with comments, but comments are already handled above
                // Colors appear after : like "fill: #ff0000"
            }
            
            // Operators: ->, <-, <->, --, :
            if ch == '-' && pos + 1 < len {
                let start = pos;
                if chars[pos + 1] == '>' {
                    pos += 2;
                    spans.push(HighlightSpan {
                        range: start..pos,
                        kind: HighlightKind::Operator,
                    });
                    continue;
                } else if chars[pos + 1] == '-' {
                    pos += 2;
                    spans.push(HighlightSpan {
                        range: start..pos,
                        kind: HighlightKind::Operator,
                    });
                    continue;
                }
            }
            
            if ch == '<' && pos + 1 < len && chars[pos + 1] == '-' {
                let start = pos;
                pos += 2;
                if pos < len && chars[pos] == '>' {
                    pos += 1;
                }
                spans.push(HighlightSpan {
                    range: start..pos,
                    kind: HighlightKind::Operator,
                });
                continue;
            }
            
            if ch == ':' {
                spans.push(HighlightSpan {
                    range: pos..pos + 1,
                    kind: HighlightKind::Operator,
                });
                pos += 1;
                continue;
            }
            
            // Braces: { }
            if ch == '{' || ch == '}' {
                spans.push(HighlightSpan {
                    range: pos..pos + 1,
                    kind: HighlightKind::Brace,
                });
                pos += 1;
                continue;
            }
            
            // Punctuation: . ; ,
            if ch == '.' || ch == ';' || ch == ',' {
                spans.push(HighlightSpan {
                    range: pos..pos + 1,
                    kind: HighlightKind::Punctuation,
                });
                pos += 1;
                continue;
            }
            
            // Number
            if ch.is_ascii_digit() || (ch == '-' && pos + 1 < len && chars[pos + 1].is_ascii_digit()) {
                let start = pos;
                if ch == '-' {
                    pos += 1;
                }
                while pos < len && (chars[pos].is_ascii_digit() || chars[pos] == '.') {
                    pos += 1;
                }
                spans.push(HighlightSpan {
                    range: start..pos,
                    kind: HighlightKind::Number,
                });
                continue;
            }
            
            // Identifier/Keyword
            if ch.is_alphabetic() || ch == '_' {
                let start = pos;
                while pos < len && (chars[pos].is_alphanumeric() || chars[pos] == '_' || chars[pos] == '-') {
                    pos += 1;
                }
                
                let word: String = chars[start..pos].iter().collect();
                let word_lower = word.to_lowercase();
                
                let kind = if self.keywords.contains(&word_lower.as_str()) {
                    HighlightKind::Keyword
                } else if self.properties.contains(&word_lower.as_str()) {
                    HighlightKind::Property
                } else if self.shapes.contains(&word_lower.as_str()) {
                    HighlightKind::Shape
                } else {
                    HighlightKind::Identifier
                };
                
                spans.push(HighlightSpan {
                    range: start..pos,
                    kind,
                });
                continue;
            }
            
            // Unknown character - mark as punctuation
            spans.push(HighlightSpan {
                range: pos..pos + 1,
                kind: HighlightKind::Punctuation,
            });
            pos += 1;
        }
        
        spans
    }
    
    /// Get completions for a given context
    pub fn completions(&self, prefix: &str, context: CompletionContext) -> Vec<Completion> {
        let prefix_lower = prefix.to_lowercase();
        let mut completions = Vec::new();
        
        match context {
            CompletionContext::Property => {
                for &prop in &self.properties {
                    if prop.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: prop.to_string(),
                            kind: CompletionKind::Property,
                            detail: Some(format!("D2 style property")),
                        });
                    }
                }
            }
            CompletionContext::Shape => {
                for &shape in &self.shapes {
                    if shape.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: shape.to_string(),
                            kind: CompletionKind::Shape,
                            detail: Some(format!("D2 shape")),
                        });
                    }
                }
            }
            CompletionContext::Keyword => {
                for &kw in &self.keywords {
                    if kw.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: kw.to_string(),
                            kind: CompletionKind::Keyword,
                            detail: Some(format!("D2 keyword")),
                        });
                    }
                }
            }
            CompletionContext::Any => {
                // Return all matching
                for &kw in &self.keywords {
                    if kw.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: kw.to_string(),
                            kind: CompletionKind::Keyword,
                            detail: None,
                        });
                    }
                }
                for &prop in &self.properties {
                    if prop.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: prop.to_string(),
                            kind: CompletionKind::Property,
                            detail: None,
                        });
                    }
                }
                for &shape in &self.shapes {
                    if shape.starts_with(&prefix_lower) {
                        completions.push(Completion {
                            text: shape.to_string(),
                            kind: CompletionKind::Shape,
                            detail: None,
                        });
                    }
                }
            }
        }
        
        completions.sort_by(|a, b| a.text.cmp(&b.text));
        completions
    }
}

/// Completion context
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompletionContext {
    /// After "shape:" - expecting a shape name
    Shape,
    /// After "." or inside style block - expecting a property
    Property,
    /// At start of line - expecting a keyword
    Keyword,
    /// Unknown context - return all
    Any,
}

/// A completion suggestion
#[derive(Debug, Clone)]
pub struct Completion {
    /// Text to insert
    pub text: String,
    /// Kind of completion
    pub kind: CompletionKind,
    /// Additional detail
    pub detail: Option<String>,
}

/// Completion kinds
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompletionKind {
    Keyword,
    Property,
    Shape,
    Identifier,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_highlight_comment() {
        let hl = D2Highlighter::new();
        let spans = hl.highlight("# This is a comment\nnode: Label");
        
        assert!(spans.iter().any(|s| s.kind == HighlightKind::Comment));
        assert!(spans.iter().any(|s| s.kind == HighlightKind::Identifier));
    }
    
    #[test]
    fn test_highlight_string() {
        let hl = D2Highlighter::new();
        let spans = hl.highlight(r#"node: "Hello World""#);
        
        assert!(spans.iter().any(|s| s.kind == HighlightKind::String));
    }
    
    #[test]
    fn test_highlight_shape() {
        let hl = D2Highlighter::new();
        let spans = hl.highlight("shape: cylinder");
        
        assert!(spans.iter().any(|s| s.kind == HighlightKind::Shape));
    }
    
    #[test]
    fn test_completions() {
        let hl = D2Highlighter::new();
        let completions = hl.completions("cyl", CompletionContext::Shape);
        
        assert!(!completions.is_empty());
        assert!(completions.iter().any(|c| c.text == "cylinder"));
    }
}
