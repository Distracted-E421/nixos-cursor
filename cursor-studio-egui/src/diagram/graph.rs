//! D2 Graph Data Structures
//!
//! Core data structures for representing D2 diagrams in memory.

use eframe::egui::{Pos2, Rect, Vec2};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A D2 diagram graph
#[derive(Debug, Clone)]
pub struct D2Graph {
    /// All nodes in the graph
    pub nodes: HashMap<String, D2Node>,
    
    /// All edges in the graph
    pub edges: Vec<D2Edge>,
    
    /// Graph-level direction (right, down, left, up)
    pub direction: Direction,
    
    /// Graph title
    pub title: Option<String>,
    
    /// Computed layout positions (filled after layout)
    pub layout_computed: bool,
    
    /// Bounding box of the entire graph
    pub bounds: Rect,
}

/// A node in the D2 graph
#[derive(Debug, Clone)]
pub struct D2Node {
    /// Unique identifier (e.g., "cursor.agent")
    pub id: String,
    
    /// Display label
    pub label: String,
    
    /// Shape type
    pub shape: D2Shape,
    
    /// Style properties
    pub style: D2Style,
    
    /// Position (filled after layout)
    pub position: Pos2,
    
    /// Size (filled after layout)
    pub size: Vec2,
    
    /// Child nodes (for containers)
    pub children: Vec<String>,
    
    /// Parent node ID (if nested)
    pub parent: Option<String>,
    
    /// Whether this node is selected
    pub selected: bool,
    
    /// Whether this node is hovered
    pub hovered: bool,
    
    /// Custom data for real-time updates
    pub data: Option<NodeData>,
}

/// An edge connecting two nodes
#[derive(Debug, Clone)]
pub struct D2Edge {
    /// Source node ID
    pub from: String,
    
    /// Target node ID
    pub to: String,
    
    /// Edge label
    pub label: Option<String>,
    
    /// Style properties
    pub style: D2Style,
    
    /// Waypoints for curved edges
    pub waypoints: Vec<Pos2>,
    
    /// Arrow type at source
    pub source_arrow: ArrowType,
    
    /// Arrow type at target
    pub target_arrow: ArrowType,
    
    /// Whether this edge is selected
    pub selected: bool,
    
    /// Whether this edge is highlighted (for data flow)
    pub highlighted: bool,
    
    /// Animation progress (0.0 - 1.0) for data flow visualization
    pub flow_progress: f32,
}

/// Node shapes supported by D2
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum D2Shape {
    #[default]
    Rectangle,
    Square,
    Page,
    Parallelogram,
    Document,
    Cylinder,
    Queue,
    Package,
    Step,
    Callout,
    StoredData,
    Person,
    Diamond,
    Oval,
    Circle,
    Hexagon,
    Cloud,
    Text,
    Code,
    Class,
    SqlTable,
    Image,
    Sequence,
}

impl D2Shape {
    /// Parse from D2 shape string
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "rectangle" | "rect" => D2Shape::Rectangle,
            "square" => D2Shape::Square,
            "page" => D2Shape::Page,
            "parallelogram" => D2Shape::Parallelogram,
            "document" => D2Shape::Document,
            "cylinder" => D2Shape::Cylinder,
            "queue" => D2Shape::Queue,
            "package" => D2Shape::Package,
            "step" => D2Shape::Step,
            "callout" => D2Shape::Callout,
            "stored_data" => D2Shape::StoredData,
            "person" => D2Shape::Person,
            "diamond" => D2Shape::Diamond,
            "oval" => D2Shape::Oval,
            "circle" => D2Shape::Circle,
            "hexagon" => D2Shape::Hexagon,
            "cloud" => D2Shape::Cloud,
            "text" => D2Shape::Text,
            "code" => D2Shape::Code,
            "class" => D2Shape::Class,
            "sql_table" => D2Shape::SqlTable,
            "image" => D2Shape::Image,
            "sequence_diagram" => D2Shape::Sequence,
            _ => D2Shape::Rectangle,
        }
    }
}

/// Style properties for nodes and edges
#[derive(Debug, Clone, Default)]
pub struct D2Style {
    /// Fill color (hex string like "#1a1a2e")
    pub fill: Option<String>,
    
    /// Stroke color
    pub stroke: Option<String>,
    
    /// Stroke width
    pub stroke_width: Option<f32>,
    
    /// Stroke dash pattern (for dashed lines)
    pub stroke_dash: Option<f32>,
    
    /// Font color
    pub font_color: Option<String>,
    
    /// Font size
    pub font_size: Option<f32>,
    
    /// Bold text
    pub bold: bool,
    
    /// Italic text
    pub italic: bool,
    
    /// Opacity (0.0 - 1.0)
    pub opacity: f32,
    
    /// Shadow
    pub shadow: bool,
    
    /// 3D effect
    pub three_d: bool,
    
    /// Multiple border effect
    pub multiple: bool,
    
    /// Border radius
    pub border_radius: Option<f32>,
}

impl D2Style {
    pub fn new() -> Self {
        Self {
            opacity: 1.0,
            ..Default::default()
        }
    }
}

/// Arrow types for edge endpoints
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ArrowType {
    #[default]
    Arrow,
    Triangle,
    Diamond,
    Circle,
    None,
}

/// Graph direction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Direction {
    #[default]
    Right,
    Down,
    Left,
    Up,
}

impl Direction {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "right" => Direction::Right,
            "down" => Direction::Down,
            "left" => Direction::Left,
            "up" => Direction::Up,
            _ => Direction::Right,
        }
    }
}

/// Custom data attached to nodes for real-time monitoring
#[derive(Debug, Clone, Default)]
pub struct NodeData {
    /// Current status (e.g., "active", "idle", "error")
    pub status: Option<String>,
    
    /// Metrics (e.g., message count, latency)
    pub metrics: HashMap<String, f64>,
    
    /// Last updated timestamp
    pub last_updated: Option<i64>,
    
    /// Custom tooltip content
    pub tooltip: Option<String>,
}

impl D2Node {
    /// Create a new node with default values
    pub fn new(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            shape: D2Shape::Rectangle,
            style: D2Style::new(),
            position: Pos2::ZERO,
            size: Vec2::new(120.0, 60.0),
            children: Vec::new(),
            parent: None,
            selected: false,
            hovered: false,
            data: None,
        }
    }
    
    /// Check if a point is inside this node
    pub fn contains(&self, point: Pos2) -> bool {
        let rect = Rect::from_min_size(self.position, self.size);
        rect.contains(point)
    }
    
    /// Get the center position of this node
    pub fn center(&self) -> Pos2 {
        self.position + self.size / 2.0
    }
    
    /// Get the bounding rectangle
    pub fn rect(&self) -> Rect {
        Rect::from_min_size(self.position, self.size)
    }
}

impl D2Edge {
    /// Create a new edge
    pub fn new(from: impl Into<String>, to: impl Into<String>) -> Self {
        Self {
            from: from.into(),
            to: to.into(),
            label: None,
            style: D2Style::new(),
            waypoints: Vec::new(),
            source_arrow: ArrowType::None,
            target_arrow: ArrowType::Arrow,
            selected: false,
            highlighted: false,
            flow_progress: 0.0,
        }
    }
}

impl Default for D2Graph {
    fn default() -> Self {
        Self::new()
    }
}

impl D2Graph {
    /// Create an empty graph
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            edges: Vec::new(),
            direction: Direction::Right,
            title: None,
            layout_computed: false,
            bounds: Rect::from_min_max(Pos2::ZERO, Pos2::ZERO),
        }
    }
    
    /// Add a node to the graph
    pub fn add_node(&mut self, node: D2Node) {
        self.nodes.insert(node.id.clone(), node);
        self.layout_computed = false;
    }
    
    /// Add an edge to the graph
    pub fn add_edge(&mut self, edge: D2Edge) {
        self.edges.push(edge);
        self.layout_computed = false;
    }
    
    /// Get a node by ID
    pub fn get_node(&self, id: &str) -> Option<&D2Node> {
        self.nodes.get(id)
    }
    
    /// Get a mutable node by ID
    pub fn get_node_mut(&mut self, id: &str) -> Option<&mut D2Node> {
        self.nodes.get_mut(id)
    }
    
    /// Find node at position
    pub fn node_at(&self, pos: Pos2) -> Option<&D2Node> {
        self.nodes.values().find(|n| n.contains(pos))
    }
    
    /// Compute a simple automatic layout
    pub fn compute_layout(&mut self) {
        let padding = 20.0;
        let node_width = 150.0;
        let node_height = 70.0;
        let h_spacing = 50.0;
        let v_spacing = 40.0;
        
        // Group nodes by parent - collect IDs first to avoid borrow issues
        let mut root_node_ids: Vec<String> = self.nodes.iter()
            .filter(|(_, n)| n.parent.is_none())
            .map(|(id, _)| id.clone())
            .collect();
        root_node_ids.sort();
        
        // Simple grid layout for root nodes
        let cols = (root_node_ids.len() as f32).sqrt().ceil() as usize;
        let cols = if cols == 0 { 1 } else { cols };
        
        for (i, id) in root_node_ids.iter().enumerate() {
            if let Some(node) = self.nodes.get_mut(id) {
                let col = i % cols;
                let row = i / cols;
                
                node.position = Pos2::new(
                    padding + col as f32 * (node_width + h_spacing),
                    padding + row as f32 * (node_height + v_spacing),
                );
                node.size = Vec2::new(node_width, node_height);
            }
        }
        
        // Update bounds
        self.compute_bounds();
        self.layout_computed = true;
    }
    
    /// Compute the bounding box of all nodes
    fn compute_bounds(&mut self) {
        let mut min = Pos2::new(f32::MAX, f32::MAX);
        let mut max = Pos2::new(f32::MIN, f32::MIN);
        
        for node in self.nodes.values() {
            min.x = min.x.min(node.position.x);
            min.y = min.y.min(node.position.y);
            max.x = max.x.max(node.position.x + node.size.x);
            max.y = max.y.max(node.position.y + node.size.y);
        }
        
        if min.x <= max.x && min.y <= max.y {
            self.bounds = Rect::from_min_max(min, max);
        } else {
            self.bounds = Rect::from_min_size(Pos2::ZERO, Vec2::new(400.0, 300.0));
        }
    }
    
    /// Update real-time data for a node
    pub fn update_node_data(&mut self, node_id: &str, data: NodeData) {
        if let Some(node) = self.nodes.get_mut(node_id) {
            node.data = Some(data);
        }
    }
    
    /// Clear all selections
    pub fn clear_selection(&mut self) {
        for node in self.nodes.values_mut() {
            node.selected = false;
        }
        for edge in &mut self.edges {
            edge.selected = false;
        }
    }
    
    /// Get all selected nodes
    pub fn selected_nodes(&self) -> Vec<&D2Node> {
        self.nodes.values().filter(|n| n.selected).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_node_contains() {
        let mut node = D2Node::new("test", "Test Node");
        node.position = Pos2::new(100.0, 100.0);
        node.size = Vec2::new(100.0, 50.0);
        
        assert!(node.contains(Pos2::new(150.0, 125.0)));
        assert!(!node.contains(Pos2::new(50.0, 50.0)));
    }
    
    #[test]
    fn test_shape_parsing() {
        assert_eq!(D2Shape::from_str("cylinder"), D2Shape::Cylinder);
        assert_eq!(D2Shape::from_str("hexagon"), D2Shape::Hexagon);
        assert_eq!(D2Shape::from_str("unknown"), D2Shape::Rectangle);
    }
}
