//! Layout Engines for D2 Diagrams
//!
//! Multiple layout algorithms:
//! - Grid: Simple row/column layout
//! - Dagre: Hierarchical layout (like D2 uses)
//! - Force: Force-directed spring physics layout
//! - Manual: User-positioned nodes only

use super::graph::{D2Graph, D2Node, D2Edge, Direction};
use eframe::egui::{Pos2, Vec2};
use std::collections::{HashMap, HashSet, VecDeque};

/// Available layout algorithms
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LayoutEngine {
    /// Simple grid layout
    #[default]
    Grid,
    /// Hierarchical layout (Sugiyama-style, like dagre)
    Dagre,
    /// Force-directed layout (spring physics)
    Force,
    /// No automatic layout - manual positioning only
    Manual,
}

impl LayoutEngine {
    pub fn name(&self) -> &'static str {
        match self {
            LayoutEngine::Grid => "Grid",
            LayoutEngine::Dagre => "Hierarchical",
            LayoutEngine::Force => "Force-Directed",
            LayoutEngine::Manual => "Manual",
        }
    }
    
    pub fn all() -> &'static [LayoutEngine] {
        &[LayoutEngine::Grid, LayoutEngine::Dagre, LayoutEngine::Force, LayoutEngine::Manual]
    }
}

/// Layout configuration
#[derive(Debug, Clone)]
pub struct LayoutConfig {
    /// Minimum node width
    pub node_width: f32,
    /// Minimum node height
    pub node_height: f32,
    /// Horizontal spacing between nodes
    pub h_spacing: f32,
    /// Vertical spacing between nodes
    pub v_spacing: f32,
    /// Padding around the graph
    pub padding: f32,
    /// Rank separation for dagre (vertical distance between layers)
    pub rank_sep: f32,
    /// Node separation within a rank
    pub node_sep: f32,
    /// Force layout: repulsion strength
    pub repulsion: f32,
    /// Force layout: attraction strength (for edges)
    pub attraction: f32,
    /// Force layout: damping factor
    pub damping: f32,
    /// Force layout: iteration count
    pub iterations: usize,
}

impl Default for LayoutConfig {
    fn default() -> Self {
        Self {
            node_width: 150.0,
            node_height: 70.0,
            h_spacing: 60.0,
            v_spacing: 50.0,
            padding: 40.0,
            rank_sep: 100.0,
            node_sep: 50.0,
            repulsion: 8000.0,
            attraction: 0.1,
            damping: 0.85,
            iterations: 100,
        }
    }
}

/// Compute layout for a graph
pub fn compute_layout(graph: &mut D2Graph, engine: LayoutEngine, config: &LayoutConfig) {
    match engine {
        LayoutEngine::Grid => grid_layout(graph, config),
        LayoutEngine::Dagre => dagre_layout(graph, config),
        LayoutEngine::Force => force_layout(graph, config),
        LayoutEngine::Manual => {} // No-op
    }
    
    graph.layout_computed = true;
    compute_bounds(graph);
}

/// Simple grid layout
fn grid_layout(graph: &mut D2Graph, config: &LayoutConfig) {
    // Get root nodes (no parent)
    let mut root_ids: Vec<String> = graph.nodes.iter()
        .filter(|(_, n)| n.parent.is_none())
        .map(|(id, _)| id.clone())
        .collect();
    root_ids.sort();
    
    if root_ids.is_empty() {
        return;
    }
    
    let cols = (root_ids.len() as f32).sqrt().ceil() as usize;
    let cols = cols.max(1);
    
    for (i, id) in root_ids.iter().enumerate() {
        if let Some(node) = graph.nodes.get_mut(id) {
            let col = i % cols;
            let row = i / cols;
            
            node.position = Pos2::new(
                config.padding + col as f32 * (config.node_width + config.h_spacing),
                config.padding + row as f32 * (config.node_height + config.v_spacing),
            );
            node.size = Vec2::new(config.node_width, config.node_height);
        }
    }
    
    // Layout children within containers
    layout_children(graph, config);
}

/// Hierarchical layout (Sugiyama-style, simplified dagre)
fn dagre_layout(graph: &mut D2Graph, config: &LayoutConfig) {
    // Build adjacency list
    let mut adj: HashMap<String, Vec<String>> = HashMap::new();
    let mut in_degree: HashMap<String, usize> = HashMap::new();
    
    for (id, _) in &graph.nodes {
        adj.entry(id.clone()).or_default();
        in_degree.entry(id.clone()).or_insert(0);
    }
    
    for edge in &graph.edges {
        adj.entry(edge.from.clone()).or_default().push(edge.to.clone());
        *in_degree.entry(edge.to.clone()).or_insert(0) += 1;
    }
    
    // Assign ranks using topological sort (Kahn's algorithm)
    let mut ranks: HashMap<String, usize> = HashMap::new();
    let mut queue: VecDeque<String> = VecDeque::new();
    
    // Find nodes with no incoming edges
    for (id, &degree) in &in_degree {
        if degree == 0 {
            queue.push_back(id.clone());
            ranks.insert(id.clone(), 0);
        }
    }
    
    // Process in topological order
    while let Some(node_id) = queue.pop_front() {
        let current_rank = *ranks.get(&node_id).unwrap_or(&0);
        
        if let Some(neighbors) = adj.get(&node_id) {
            for neighbor in neighbors {
                let new_rank = current_rank + 1;
                let existing_rank = ranks.entry(neighbor.clone()).or_insert(0);
                *existing_rank = (*existing_rank).max(new_rank);
                
                // Decrease in-degree
                if let Some(deg) = in_degree.get_mut(neighbor) {
                    *deg = deg.saturating_sub(1);
                    if *deg == 0 {
                        queue.push_back(neighbor.clone());
                    }
                }
            }
        }
    }
    
    // Handle cycles - assign remaining nodes to last rank
    let max_rank = ranks.values().copied().max().unwrap_or(0);
    for (id, _) in &graph.nodes {
        ranks.entry(id.clone()).or_insert(max_rank + 1);
    }
    
    // Group nodes by rank
    let mut rank_nodes: HashMap<usize, Vec<String>> = HashMap::new();
    for (id, &rank) in &ranks {
        rank_nodes.entry(rank).or_default().push(id.clone());
    }
    
    // Sort nodes within each rank for consistent ordering
    for nodes in rank_nodes.values_mut() {
        nodes.sort();
    }
    
    // Position nodes based on direction
    let direction = graph.direction;
    let num_ranks = rank_nodes.len();
    
    for (rank, node_ids) in &rank_nodes {
        let num_nodes = node_ids.len();
        
        for (i, id) in node_ids.iter().enumerate() {
            if let Some(node) = graph.nodes.get_mut(id) {
                let (x, y) = match direction {
                    Direction::Right => {
                        let x = config.padding + *rank as f32 * (config.node_width + config.rank_sep);
                        let y = config.padding + i as f32 * (config.node_height + config.node_sep);
                        (x, y)
                    }
                    Direction::Down => {
                        let x = config.padding + i as f32 * (config.node_width + config.node_sep);
                        let y = config.padding + *rank as f32 * (config.node_height + config.rank_sep);
                        (x, y)
                    }
                    Direction::Left => {
                        let x = config.padding + (num_ranks - 1 - *rank) as f32 * (config.node_width + config.rank_sep);
                        let y = config.padding + i as f32 * (config.node_height + config.node_sep);
                        (x, y)
                    }
                    Direction::Up => {
                        let x = config.padding + i as f32 * (config.node_width + config.node_sep);
                        let y = config.padding + (num_ranks - 1 - *rank) as f32 * (config.node_height + config.rank_sep);
                        (x, y)
                    }
                };
                
                node.position = Pos2::new(x, y);
                node.size = Vec2::new(config.node_width, config.node_height);
            }
        }
    }
    
    layout_children(graph, config);
}

/// Force-directed layout using spring physics
fn force_layout(graph: &mut D2Graph, config: &LayoutConfig) {
    // Initialize positions randomly if not set
    let node_ids: Vec<String> = graph.nodes.keys().cloned().collect();
    let n = node_ids.len();
    
    if n == 0 {
        return;
    }
    
    // Initialize positions in a circle
    for (i, id) in node_ids.iter().enumerate() {
        if let Some(node) = graph.nodes.get_mut(id) {
            let angle = 2.0 * std::f32::consts::PI * i as f32 / n as f32;
            let radius = (n as f32).sqrt() * 100.0;
            node.position = Pos2::new(
                config.padding + radius + angle.cos() * radius,
                config.padding + radius + angle.sin() * radius,
            );
            node.size = Vec2::new(config.node_width, config.node_height);
        }
    }
    
    // Build edge set for quick lookup
    let edge_set: HashSet<(String, String)> = graph.edges.iter()
        .map(|e| (e.from.clone(), e.to.clone()))
        .collect();
    
    // Iterate force simulation
    let mut velocities: HashMap<String, Vec2> = node_ids.iter()
        .map(|id| (id.clone(), Vec2::ZERO))
        .collect();
    
    for _ in 0..config.iterations {
        let mut forces: HashMap<String, Vec2> = node_ids.iter()
            .map(|id| (id.clone(), Vec2::ZERO))
            .collect();
        
        // Repulsion between all pairs
        for i in 0..n {
            for j in (i + 1)..n {
                let id_i = &node_ids[i];
                let id_j = &node_ids[j];
                
                let pos_i = graph.nodes.get(id_i).map(|n| n.center()).unwrap_or(Pos2::ZERO);
                let pos_j = graph.nodes.get(id_j).map(|n| n.center()).unwrap_or(Pos2::ZERO);
                
                let delta = pos_j - pos_i;
                let dist = delta.length().max(1.0);
                let force_mag = config.repulsion / (dist * dist);
                let force = delta.normalized() * force_mag;
                
                *forces.get_mut(id_i).unwrap() -= force;
                *forces.get_mut(id_j).unwrap() += force;
            }
        }
        
        // Attraction along edges
        for edge in &graph.edges {
            let pos_from = graph.nodes.get(&edge.from).map(|n| n.center()).unwrap_or(Pos2::ZERO);
            let pos_to = graph.nodes.get(&edge.to).map(|n| n.center()).unwrap_or(Pos2::ZERO);
            
            let delta = pos_to - pos_from;
            let dist = delta.length();
            let force = delta * config.attraction * dist;
            
            if let Some(f) = forces.get_mut(&edge.from) {
                *f += force;
            }
            if let Some(f) = forces.get_mut(&edge.to) {
                *f -= force;
            }
        }
        
        // Apply forces with damping
        for id in &node_ids {
            if let (Some(node), Some(vel), Some(force)) = (
                graph.nodes.get_mut(id),
                velocities.get_mut(id),
                forces.get(id),
            ) {
                *vel = (*vel + *force) * config.damping;
                node.position += *vel * 0.1;
            }
        }
    }
    
    // Center the graph
    center_graph(graph, config);
    layout_children(graph, config);
}

/// Layout children within container nodes
fn layout_children(graph: &mut D2Graph, config: &LayoutConfig) {
    // Find container nodes
    let container_ids: Vec<String> = graph.nodes.iter()
        .filter(|(_, n)| !n.children.is_empty())
        .map(|(id, _)| id.clone())
        .collect();
    
    for container_id in container_ids {
        let children: Vec<String> = graph.nodes.get(&container_id)
            .map(|n| n.children.clone())
            .unwrap_or_default();
        
        if children.is_empty() {
            continue;
        }
        
        let container_pos = graph.nodes.get(&container_id)
            .map(|n| n.position)
            .unwrap_or(Pos2::ZERO);
        
        // Layout children in a mini-grid within the container
        let cols = (children.len() as f32).sqrt().ceil() as usize;
        let cols = cols.max(1);
        let child_width = config.node_width * 0.8;
        let child_height = config.node_height * 0.8;
        let child_spacing = 10.0;
        
        let mut max_x = 0.0f32;
        let mut max_y = 0.0f32;
        
        for (i, child_id) in children.iter().enumerate() {
            if let Some(child) = graph.nodes.get_mut(child_id) {
                let col = i % cols;
                let row = i / cols;
                
                child.position = Pos2::new(
                    container_pos.x + 20.0 + col as f32 * (child_width + child_spacing),
                    container_pos.y + 40.0 + row as f32 * (child_height + child_spacing), // Extra space for container label
                );
                child.size = Vec2::new(child_width, child_height);
                
                max_x = max_x.max(child.position.x + child.size.x);
                max_y = max_y.max(child.position.y + child.size.y);
            }
        }
        
        // Resize container to fit children
        if let Some(container) = graph.nodes.get_mut(&container_id) {
            container.size = Vec2::new(
                (max_x - container_pos.x + 20.0).max(config.node_width),
                (max_y - container_pos.y + 20.0).max(config.node_height),
            );
        }
    }
}

/// Center the graph around origin
fn center_graph(graph: &mut D2Graph, config: &LayoutConfig) {
    let mut min = Pos2::new(f32::MAX, f32::MAX);
    let mut max = Pos2::new(f32::MIN, f32::MIN);
    
    for node in graph.nodes.values() {
        min.x = min.x.min(node.position.x);
        min.y = min.y.min(node.position.y);
        max.x = max.x.max(node.position.x + node.size.x);
        max.y = max.y.max(node.position.y + node.size.y);
    }
    
    if min.x > max.x || min.y > max.y {
        return;
    }
    
    // Shift to positive coordinates with padding
    let offset = Vec2::new(config.padding - min.x, config.padding - min.y);
    
    for node in graph.nodes.values_mut() {
        node.position += offset;
    }
}

/// Compute graph bounding box
fn compute_bounds(graph: &mut D2Graph) {
    let mut min = Pos2::new(f32::MAX, f32::MAX);
    let mut max = Pos2::new(f32::MIN, f32::MIN);
    
    for node in graph.nodes.values() {
        min.x = min.x.min(node.position.x);
        min.y = min.y.min(node.position.y);
        max.x = max.x.max(node.position.x + node.size.x);
        max.y = max.y.max(node.position.y + node.size.y);
    }
    
    if min.x <= max.x && min.y <= max.y {
        graph.bounds = eframe::egui::Rect::from_min_max(min, max);
    }
}

/// Incrementally update force layout (for interactive use)
pub fn force_layout_step(graph: &mut D2Graph, config: &LayoutConfig) -> bool {
    let node_ids: Vec<String> = graph.nodes.keys().cloned().collect();
    let n = node_ids.len();
    
    if n == 0 {
        return true;
    }
    
    let mut forces: HashMap<String, Vec2> = node_ids.iter()
        .map(|id| (id.clone(), Vec2::ZERO))
        .collect();
    
    let mut max_force = 0.0f32;
    
    // Repulsion
    for i in 0..n {
        for j in (i + 1)..n {
            let id_i = &node_ids[i];
            let id_j = &node_ids[j];
            
            let pos_i = graph.nodes.get(id_i).map(|n| n.center()).unwrap_or(Pos2::ZERO);
            let pos_j = graph.nodes.get(id_j).map(|n| n.center()).unwrap_or(Pos2::ZERO);
            
            let delta = pos_j - pos_i;
            let dist = delta.length().max(1.0);
            let force_mag = config.repulsion / (dist * dist);
            let force = delta.normalized() * force_mag;
            
            *forces.get_mut(id_i).unwrap() -= force;
            *forces.get_mut(id_j).unwrap() += force;
        }
    }
    
    // Attraction
    for edge in &graph.edges {
        let pos_from = graph.nodes.get(&edge.from).map(|n| n.center()).unwrap_or(Pos2::ZERO);
        let pos_to = graph.nodes.get(&edge.to).map(|n| n.center()).unwrap_or(Pos2::ZERO);
        
        let delta = pos_to - pos_from;
        let dist = delta.length();
        let force = delta * config.attraction * dist;
        
        if let Some(f) = forces.get_mut(&edge.from) {
            *f += force;
        }
        if let Some(f) = forces.get_mut(&edge.to) {
            *f -= force;
        }
    }
    
    // Apply forces
    for id in &node_ids {
        if let (Some(node), Some(force)) = (graph.nodes.get_mut(id), forces.get(id)) {
            let clamped_force = Vec2::new(
                force.x.clamp(-50.0, 50.0),
                force.y.clamp(-50.0, 50.0),
            );
            node.position += clamped_force * 0.05;
            max_force = max_force.max(force.length());
        }
    }
    
    compute_bounds(graph);
    
    // Return true if converged (forces are small)
    max_force < 1.0
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_grid_layout() {
        let mut graph = D2Graph::new();
        graph.add_node(D2Node::new("a", "A"));
        graph.add_node(D2Node::new("b", "B"));
        graph.add_node(D2Node::new("c", "C"));
        graph.add_node(D2Node::new("d", "D"));
        
        compute_layout(&mut graph, LayoutEngine::Grid, &LayoutConfig::default());
        
        assert!(graph.layout_computed);
        assert!(graph.bounds.width() > 0.0);
    }
    
    #[test]
    fn test_dagre_layout() {
        let mut graph = D2Graph::new();
        graph.add_node(D2Node::new("a", "A"));
        graph.add_node(D2Node::new("b", "B"));
        graph.add_node(D2Node::new("c", "C"));
        graph.add_edge(D2Edge::new("a", "b"));
        graph.add_edge(D2Edge::new("b", "c"));
        
        compute_layout(&mut graph, LayoutEngine::Dagre, &LayoutConfig::default());
        
        assert!(graph.layout_computed);
        
        // In dagre, nodes should be in different ranks
        let pos_a = graph.nodes.get("a").unwrap().position;
        let pos_b = graph.nodes.get("b").unwrap().position;
        let pos_c = graph.nodes.get("c").unwrap().position;
        
        // With Direction::Right, x should increase
        assert!(pos_a.x < pos_b.x);
        assert!(pos_b.x < pos_c.x);
    }
}
