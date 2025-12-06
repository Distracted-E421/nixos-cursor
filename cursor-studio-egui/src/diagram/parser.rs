//! D2 File Parser
//!
//! Parses D2 diagram source files into our graph structures.
//! This is a simplified parser that handles the most common D2 patterns.

use super::graph::{D2Graph, D2Node, D2Edge, D2Shape, D2Style, Direction, ArrowType};
use std::collections::HashMap;
use std::path::Path;

/// Parse a D2 file into a graph
pub fn parse_file(path: &Path) -> Result<D2Graph, ParseError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| ParseError::IoError(e.to_string()))?;
    parse_string(&content)
}

/// Parse D2 source code into a graph
pub fn parse_string(source: &str) -> Result<D2Graph, ParseError> {
    let mut parser = D2Parser::new(source);
    parser.parse()
}

/// Parser error types
#[derive(Debug, Clone)]
pub enum ParseError {
    IoError(String),
    SyntaxError { line: usize, message: String },
    InvalidShape(String),
    UnexpectedToken { line: usize, expected: String, found: String },
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::IoError(e) => write!(f, "IO error: {}", e),
            ParseError::SyntaxError { line, message } => {
                write!(f, "Syntax error on line {}: {}", line, message)
            }
            ParseError::InvalidShape(s) => write!(f, "Invalid shape: {}", s),
            ParseError::UnexpectedToken { line, expected, found } => {
                write!(f, "Line {}: expected {}, found {}", line, expected, found)
            }
        }
    }
}

impl std::error::Error for ParseError {}

/// D2 Parser state
struct D2Parser<'a> {
    source: &'a str,
    lines: Vec<&'a str>,
    current_line: usize,
    graph: D2Graph,
    // Track container hierarchy
    container_stack: Vec<String>,
    // Track style classes
    style_classes: HashMap<String, D2Style>,
}

impl<'a> D2Parser<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            source,
            lines: source.lines().collect(),
            current_line: 0,
            graph: D2Graph::new(),
            container_stack: Vec::new(),
            style_classes: HashMap::new(),
        }
    }
    
    fn parse(&mut self) -> Result<D2Graph, ParseError> {
        while self.current_line < self.lines.len() {
            let line = self.lines[self.current_line].trim();
            self.current_line += 1;
            
            // Skip empty lines and comments
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            
            // Parse the line
            self.parse_line(line)?;
        }
        
        // Compute layout if not already done
        if !self.graph.layout_computed {
            self.graph.compute_layout();
        }
        
        Ok(self.graph.clone())
    }
    
    fn parse_line(&mut self, line: &str) -> Result<(), ParseError> {
        let trimmed = line.trim();
        
        // Handle closing brace
        if trimmed == "}" {
            self.container_stack.pop();
            return Ok(());
        }
        
        // Handle direction declaration
        if trimmed.starts_with("direction:") {
            let dir = trimmed.trim_start_matches("direction:").trim();
            self.graph.direction = Direction::from_str(dir);
            return Ok(());
        }
        
        // Handle title
        if trimmed.starts_with("title:") {
            let title = trimmed.trim_start_matches("title:").trim();
            self.graph.title = Some(unquote(title));
            return Ok(());
        }
        
        // Handle vars/style classes (simplified)
        if trimmed.starts_with("vars:") || trimmed.starts_with("classes:") {
            // Skip for now, we handle styles inline
            return Ok(());
        }
        
        // Parse connection or node definition
        self.parse_element(trimmed)
    }
    
    fn parse_element(&mut self, line: &str) -> Result<(), ParseError> {
        // Check for edge syntax: A -> B, A -- B, A <- B
        if let Some(edge) = self.try_parse_edge(line) {
            self.graph.add_edge(edge);
            return Ok(());
        }
        
        // Check for node definition: name: label { ... } or name.property: value
        if let Some(node) = self.try_parse_node(line)? {
            // If this is a container (has opening brace), push to stack
            if line.contains('{') && !line.contains('}') {
                self.container_stack.push(node.id.clone());
            }
            
            self.graph.add_node(node);
        }
        
        Ok(())
    }
    
    fn try_parse_edge(&mut self, line: &str) -> Option<D2Edge> {
        // Find edge operator
        let (from_str, to_str, source_arrow, target_arrow) = 
            if let Some(pos) = line.find(" -> ") {
                let (f, t) = line.split_at(pos);
                (f.trim(), t[4..].trim(), ArrowType::None, ArrowType::Arrow)
            } else if let Some(pos) = line.find(" <- ") {
                let (f, t) = line.split_at(pos);
                (f.trim(), t[4..].trim(), ArrowType::Arrow, ArrowType::None)
            } else if let Some(pos) = line.find(" <-> ") {
                let (f, t) = line.split_at(pos);
                (f.trim(), t[5..].trim(), ArrowType::Arrow, ArrowType::Arrow)
            } else if let Some(pos) = line.find(" -- ") {
                let (f, t) = line.split_at(pos);
                (f.trim(), t[4..].trim(), ArrowType::None, ArrowType::None)
            } else {
                return None;
            };
        
        // Extract node IDs and optional label
        let from_id = extract_id(from_str);
        
        // Handle edge label: A -> B: "label"
        let (to_part, label) = if let Some(colon_pos) = to_str.find(':') {
            let (t, l) = to_str.split_at(colon_pos);
            (t.trim(), Some(unquote(l[1..].trim())))
        } else {
            // Handle inline style block
            let to_part = to_str.split('{').next().unwrap_or(to_str).trim();
            (to_part, None)
        };
        
        let to_id = extract_id(to_part);
        
        // Ensure both nodes exist
        if !self.graph.nodes.contains_key(&from_id) {
            let node = D2Node::new(&from_id, &from_id);
            self.graph.add_node(node);
        }
        if !self.graph.nodes.contains_key(&to_id) {
            let node = D2Node::new(&to_id, &to_id);
            self.graph.add_node(node);
        }
        
        let mut edge = D2Edge::new(from_id, to_id);
        edge.label = label;
        edge.source_arrow = source_arrow;
        edge.target_arrow = target_arrow;
        
        // Parse inline style if present
        if let Some(style_start) = to_str.find('{') {
            if let Some(style_end) = to_str.find('}') {
                let style_str = &to_str[style_start + 1..style_end];
                edge.style = parse_inline_style(style_str);
            }
        }
        
        Some(edge)
    }
    
    fn try_parse_node(&mut self, line: &str) -> Result<Option<D2Node>, ParseError> {
        // Skip if it's just a closing brace or edge
        if line == "}" || line.contains(" -> ") || line.contains(" <- ") 
            || line.contains(" -- ") || line.contains(" <-> ") {
            return Ok(None);
        }
        
        // Extract ID (everything before : or { or .)
        let id_end = line.find(':')
            .or_else(|| line.find('{'))
            .or_else(|| line.find('.'))
            .unwrap_or(line.len());
        
        let raw_id = line[..id_end].trim();
        let id = if raw_id.is_empty() {
            return Ok(None);
        } else {
            // Prepend container path if in a container
            if let Some(parent) = self.container_stack.last() {
                format!("{}.{}", parent, raw_id)
            } else {
                raw_id.to_string()
            }
        };
        
        // Check if node already exists (for property updates)
        let mut node = self.graph.nodes.get(&id).cloned()
            .unwrap_or_else(|| {
                let mut n = D2Node::new(&id, raw_id);
                if let Some(parent) = self.container_stack.last() {
                    n.parent = Some(parent.clone());
                }
                n
            });
        
        // Parse label: id: "Label Text"
        if let Some(colon_pos) = line.find(':') {
            let after_colon = line[colon_pos + 1..].trim();
            
            // Check for property assignment: node.shape: circle
            if raw_id.contains('.') {
                let parts: Vec<&str> = raw_id.splitn(2, '.').collect();
                if parts.len() == 2 {
                    let base_id = if let Some(parent) = self.container_stack.last() {
                        format!("{}.{}", parent, parts[0])
                    } else {
                        parts[0].to_string()
                    };
                    
                    // Update existing node property
                    if let Some(existing) = self.graph.nodes.get_mut(&base_id) {
                        let prop = parts[1].to_string();
                        let val = after_colon.to_string();
                        Self::update_node_property_static(existing, &prop, &val);
                        return Ok(None);
                    }
                }
            }
            
            // Regular label assignment
            let label = if after_colon.starts_with('"') || after_colon.starts_with('\'') {
                unquote(after_colon.split('{').next().unwrap_or(after_colon).trim())
            } else if after_colon.starts_with('|') {
                // Markdown/code block
                unquote(after_colon.trim_matches('|').trim())
            } else {
                after_colon.split('{').next().unwrap_or(after_colon).trim().to_string()
            };
            
            if !label.is_empty() && !label.starts_with('{') {
                node.label = label;
            }
        }
        
        // Parse inline style block
        if let Some(style_start) = line.find('{') {
            if let Some(style_end) = line.rfind('}') {
                let style_str = &line[style_start + 1..style_end];
                node.style = parse_inline_style(style_str);
            }
        }
        
        Ok(Some(node))
    }
    
    fn update_node_property_static(node: &mut D2Node, property: &str, value: &str) {
        let clean_value = unquote(value.trim());
        
        match property.to_lowercase().as_str() {
            "shape" => node.shape = D2Shape::from_str(&clean_value),
            "label" => node.label = clean_value,
            "fill" | "style.fill" => node.style.fill = Some(clean_value),
            "stroke" | "style.stroke" => node.style.stroke = Some(clean_value),
            "stroke-width" | "style.stroke-width" => {
                node.style.stroke_width = clean_value.parse().ok();
            }
            "stroke-dash" | "style.stroke-dash" => {
                node.style.stroke_dash = clean_value.parse().ok();
            }
            "font-color" | "style.font-color" => node.style.font_color = Some(clean_value),
            "font-size" | "style.font-size" => {
                node.style.font_size = clean_value.parse().ok();
            }
            "bold" | "style.bold" => node.style.bold = clean_value == "true",
            "italic" | "style.italic" => node.style.italic = clean_value == "true",
            "opacity" | "style.opacity" => {
                node.style.opacity = clean_value.parse().unwrap_or(1.0);
            }
            "shadow" | "style.shadow" => node.style.shadow = clean_value == "true",
            "3d" | "style.3d" => node.style.three_d = clean_value == "true",
            "multiple" | "style.multiple" => node.style.multiple = clean_value == "true",
            "border-radius" | "style.border-radius" => {
                node.style.border_radius = clean_value.parse().ok();
            }
            _ => {} // Ignore unknown properties
        }
    }
}

/// Parse inline style block: { fill: #1a1a2e; stroke: #4cc9f0 }
fn parse_inline_style(style_str: &str) -> D2Style {
    let mut style = D2Style::new();
    
    for part in style_str.split(';') {
        let part = part.trim();
        if let Some(colon_pos) = part.find(':') {
            let key = part[..colon_pos].trim().to_lowercase();
            let value = unquote(part[colon_pos + 1..].trim());
            
            match key.as_str() {
                "fill" => style.fill = Some(value),
                "stroke" => style.stroke = Some(value),
                "stroke-width" => style.stroke_width = value.parse().ok(),
                "stroke-dash" => style.stroke_dash = value.parse().ok(),
                "font-color" => style.font_color = Some(value),
                "font-size" => style.font_size = value.parse().ok(),
                "bold" => style.bold = value == "true",
                "italic" => style.italic = value == "true",
                "opacity" => style.opacity = value.parse().unwrap_or(1.0),
                "shadow" => style.shadow = value == "true",
                "3d" => style.three_d = value == "true",
                "multiple" => style.multiple = value == "true",
                "border-radius" => style.border_radius = value.parse().ok(),
                _ => {}
            }
        }
    }
    
    style
}

/// Extract a node ID from a string, handling quoted labels
fn extract_id(s: &str) -> String {
    let s = s.trim();
    // If quoted, use as-is but remove quotes
    if s.starts_with('"') || s.starts_with('\'') {
        return unquote(s);
    }
    // Otherwise use the identifier
    s.split_whitespace().next().unwrap_or(s).to_string()
}

/// Remove quotes from a string
fn unquote(s: &str) -> String {
    let s = s.trim();
    if (s.starts_with('"') && s.ends_with('"')) 
        || (s.starts_with('\'') && s.ends_with('\'')) {
        s[1..s.len()-1].to_string()
    } else {
        s.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_simple_parse() {
        let source = r#"
            direction: right
            
            A: "Node A"
            B: "Node B"
            A -> B: "connection"
        "#;
        
        let graph = parse_string(source).unwrap();
        assert_eq!(graph.nodes.len(), 2);
        assert_eq!(graph.edges.len(), 1);
        assert!(graph.nodes.contains_key("A"));
        assert!(graph.nodes.contains_key("B"));
    }
    
    #[test]
    fn test_shape_parsing() {
        let source = r#"
            db: Database {
                shape: cylinder
            }
        "#;
        
        let graph = parse_string(source).unwrap();
        let node = graph.nodes.get("db").unwrap();
        assert_eq!(node.shape, D2Shape::Cylinder);
    }
    
    #[test]
    fn test_inline_style() {
        let source = r#"
            node: "Styled" { fill: #ff0000; stroke: #00ff00 }
        "#;
        
        let graph = parse_string(source).unwrap();
        let node = graph.nodes.get("node").unwrap();
        assert_eq!(node.style.fill, Some("#ff0000".to_string()));
        assert_eq!(node.style.stroke, Some("#00ff00".to_string()));
    }
    
    #[test]
    fn test_edge_labels() {
        let source = r#"
            A -> B: "labeled edge"
        "#;
        
        let graph = parse_string(source).unwrap();
        assert_eq!(graph.edges[0].label, Some("labeled edge".to_string()));
    }
}
