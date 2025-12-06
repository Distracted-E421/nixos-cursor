//! Real-Time Data Flow Visualization
//!
//! Provides animated visualization of data flowing through diagrams:
//! - Animated particles along edges
//! - Pulsing nodes when active
//! - Color gradients showing load/latency
//! - Status indicators

use eframe::egui::{Color32, Pos2, Vec2};
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Data flow visualization state
#[derive(Debug, Clone)]
pub struct DataFlowState {
    /// Active flows on edges (edge_key -> flow info)
    pub edge_flows: HashMap<String, EdgeFlow>,
    
    /// Active node states
    pub node_states: HashMap<String, NodeActivity>,
    
    /// Global animation time
    pub time: f32,
    
    /// Start time for animation
    start_time: Instant,
    
    /// Whether animation is enabled
    pub enabled: bool,
    
    /// Animation speed multiplier
    pub speed: f32,
}

/// Flow state for a single edge
#[derive(Debug, Clone)]
pub struct EdgeFlow {
    /// Number of active particles
    pub particle_count: usize,
    
    /// Particle positions (0.0 - 1.0 along edge)
    pub particles: Vec<f32>,
    
    /// Flow color (can vary based on data type)
    pub color: Color32,
    
    /// Flow intensity (affects brightness/size)
    pub intensity: f32,
    
    /// Messages per second
    pub throughput: f32,
    
    /// Last update time
    pub last_update: Instant,
}

/// Activity state for a node
#[derive(Debug, Clone)]
pub struct NodeActivity {
    /// Current status
    pub status: NodeStatus,
    
    /// Pulse animation phase (0.0 - 1.0)
    pub pulse_phase: f32,
    
    /// Load percentage (0.0 - 1.0)
    pub load: f32,
    
    /// Latency in milliseconds
    pub latency_ms: f32,
    
    /// Messages processed
    pub message_count: u64,
    
    /// Error count
    pub error_count: u64,
    
    /// Last activity time
    pub last_activity: Instant,
}

/// Node status types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NodeStatus {
    /// Node is idle
    #[default]
    Idle,
    /// Node is actively processing
    Active,
    /// Node is receiving data
    Receiving,
    /// Node is sending data
    Sending,
    /// Node has a warning condition
    Warning,
    /// Node has an error condition
    Error,
    /// Node is disconnected/unavailable
    Disconnected,
}

impl NodeStatus {
    /// Get color for this status
    pub fn color(&self) -> Color32 {
        match self {
            NodeStatus::Idle => Color32::from_rgb(128, 128, 128),
            NodeStatus::Active => Color32::from_rgb(0, 200, 100),
            NodeStatus::Receiving => Color32::from_rgb(100, 150, 255),
            NodeStatus::Sending => Color32::from_rgb(255, 180, 100),
            NodeStatus::Warning => Color32::from_rgb(255, 200, 0),
            NodeStatus::Error => Color32::from_rgb(255, 80, 80),
            NodeStatus::Disconnected => Color32::from_rgb(100, 100, 100),
        }
    }
    
    /// Should this status pulse?
    pub fn should_pulse(&self) -> bool {
        matches!(self, NodeStatus::Active | NodeStatus::Receiving | NodeStatus::Sending)
    }
}

impl Default for DataFlowState {
    fn default() -> Self {
        Self::new()
    }
}

impl DataFlowState {
    /// Create new data flow state
    pub fn new() -> Self {
        Self {
            edge_flows: HashMap::new(),
            node_states: HashMap::new(),
            time: 0.0,
            start_time: Instant::now(),
            enabled: true,
            speed: 1.0,
        }
    }
    
    /// Update animation time
    pub fn update(&mut self) {
        if self.enabled {
            self.time = self.start_time.elapsed().as_secs_f32() * self.speed;
            
            // Update particle positions
            for flow in self.edge_flows.values_mut() {
                for particle in &mut flow.particles {
                    *particle = (*particle + 0.01 * flow.intensity) % 1.0;
                }
            }
            
            // Update pulse phases
            for node in self.node_states.values_mut() {
                if node.status.should_pulse() {
                    node.pulse_phase = (node.pulse_phase + 0.05) % 1.0;
                } else {
                    node.pulse_phase = 0.0;
                }
            }
        }
    }
    
    /// Start a flow on an edge
    pub fn start_flow(&mut self, from: &str, to: &str) {
        let key = Self::edge_key(from, to);
        let flow = self.edge_flows.entry(key).or_insert_with(|| EdgeFlow {
            particle_count: 3,
            particles: vec![0.0, 0.33, 0.66],
            color: Color32::from_rgb(100, 255, 150),
            intensity: 1.0,
            throughput: 0.0,
            last_update: Instant::now(),
        });
        flow.last_update = Instant::now();
    }
    
    /// Stop a flow on an edge
    pub fn stop_flow(&mut self, from: &str, to: &str) {
        let key = Self::edge_key(from, to);
        self.edge_flows.remove(&key);
    }
    
    /// Update edge throughput
    pub fn update_throughput(&mut self, from: &str, to: &str, messages_per_sec: f32) {
        let key = Self::edge_key(from, to);
        if let Some(flow) = self.edge_flows.get_mut(&key) {
            flow.throughput = messages_per_sec;
            flow.intensity = (messages_per_sec / 10.0).clamp(0.5, 3.0);
            
            // Adjust particle count based on throughput
            let new_count = (messages_per_sec / 5.0).ceil() as usize;
            let new_count = new_count.clamp(1, 10);
            
            if new_count != flow.particle_count {
                flow.particle_count = new_count;
                flow.particles = (0..new_count)
                    .map(|i| i as f32 / new_count as f32)
                    .collect();
            }
        }
    }
    
    /// Set node status
    pub fn set_node_status(&mut self, node_id: &str, status: NodeStatus) {
        let activity = self.node_states.entry(node_id.to_string()).or_default();
        activity.status = status;
        activity.last_activity = Instant::now();
    }
    
    /// Update node load
    pub fn update_node_load(&mut self, node_id: &str, load: f32) {
        let activity = self.node_states.entry(node_id.to_string()).or_default();
        activity.load = load.clamp(0.0, 1.0);
        activity.last_activity = Instant::now();
    }
    
    /// Update node latency
    pub fn update_node_latency(&mut self, node_id: &str, latency_ms: f32) {
        let activity = self.node_states.entry(node_id.to_string()).or_default();
        activity.latency_ms = latency_ms;
        activity.last_activity = Instant::now();
    }
    
    /// Increment node message count
    pub fn increment_messages(&mut self, node_id: &str) {
        let activity = self.node_states.entry(node_id.to_string()).or_default();
        activity.message_count += 1;
        activity.last_activity = Instant::now();
    }
    
    /// Increment node error count
    pub fn increment_errors(&mut self, node_id: &str) {
        let activity = self.node_states.entry(node_id.to_string()).or_default();
        activity.error_count += 1;
        activity.status = NodeStatus::Error;
        activity.last_activity = Instant::now();
    }
    
    /// Get edge flow state
    pub fn get_flow(&self, from: &str, to: &str) -> Option<&EdgeFlow> {
        let key = Self::edge_key(from, to);
        self.edge_flows.get(&key)
    }
    
    /// Get node activity state
    pub fn get_node_activity(&self, node_id: &str) -> Option<&NodeActivity> {
        self.node_states.get(node_id)
    }
    
    /// Check if a flow is active
    pub fn is_flow_active(&self, from: &str, to: &str) -> bool {
        let key = Self::edge_key(from, to);
        self.edge_flows.contains_key(&key)
    }
    
    /// Get particle positions for an edge
    pub fn get_particles(&self, from: &str, to: &str) -> Vec<f32> {
        let key = Self::edge_key(from, to);
        self.edge_flows.get(&key)
            .map(|f| f.particles.clone())
            .unwrap_or_default()
    }
    
    /// Get pulse intensity for a node (0.0 - 1.0)
    pub fn get_pulse(&self, node_id: &str) -> f32 {
        self.node_states.get(node_id)
            .map(|n| {
                if n.status.should_pulse() {
                    // Smooth pulse wave
                    (n.pulse_phase * std::f32::consts::PI * 2.0).sin() * 0.5 + 0.5
                } else {
                    0.0
                }
            })
            .unwrap_or(0.0)
    }
    
    /// Get load color for a node
    pub fn get_load_color(&self, node_id: &str) -> Color32 {
        self.node_states.get(node_id)
            .map(|n| load_to_color(n.load))
            .unwrap_or(Color32::GRAY)
    }
    
    /// Get latency color for a node
    pub fn get_latency_color(&self, node_id: &str) -> Color32 {
        self.node_states.get(node_id)
            .map(|n| latency_to_color(n.latency_ms))
            .unwrap_or(Color32::GRAY)
    }
    
    /// Clear all states
    pub fn clear(&mut self) {
        self.edge_flows.clear();
        self.node_states.clear();
    }
    
    /// Generate edge key
    fn edge_key(from: &str, to: &str) -> String {
        format!("{}->{}",from, to)
    }
}

impl Default for NodeActivity {
    fn default() -> Self {
        Self {
            status: NodeStatus::Idle,
            pulse_phase: 0.0,
            load: 0.0,
            latency_ms: 0.0,
            message_count: 0,
            error_count: 0,
            last_activity: Instant::now(),
        }
    }
}

/// Convert load (0.0-1.0) to color (green -> yellow -> red)
fn load_to_color(load: f32) -> Color32 {
    let load = load.clamp(0.0, 1.0);
    
    if load < 0.5 {
        // Green to yellow
        let t = load * 2.0;
        Color32::from_rgb(
            (255.0 * t) as u8,
            200,
            (100.0 * (1.0 - t)) as u8,
        )
    } else {
        // Yellow to red
        let t = (load - 0.5) * 2.0;
        Color32::from_rgb(
            255,
            (200.0 * (1.0 - t)) as u8,
            0,
        )
    }
}

/// Convert latency (ms) to color
fn latency_to_color(latency_ms: f32) -> Color32 {
    if latency_ms < 50.0 {
        Color32::from_rgb(100, 255, 100) // Green - fast
    } else if latency_ms < 200.0 {
        Color32::from_rgb(255, 255, 100) // Yellow - acceptable
    } else if latency_ms < 500.0 {
        Color32::from_rgb(255, 180, 80) // Orange - slow
    } else {
        Color32::from_rgb(255, 80, 80) // Red - very slow
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_data_flow_state() {
        let mut state = DataFlowState::new();
        
        // Start a flow
        state.start_flow("a", "b");
        assert!(state.is_flow_active("a", "b"));
        
        // Set node status
        state.set_node_status("a", NodeStatus::Active);
        assert_eq!(state.get_node_activity("a").unwrap().status, NodeStatus::Active);
        
        // Update load
        state.update_node_load("a", 0.75);
        let color = state.get_load_color("a");
        assert!(color.r() > 200); // Should be orange/red range
    }
    
    #[test]
    fn test_load_colors() {
        let green = load_to_color(0.0);
        let red = load_to_color(1.0);
        
        assert!(green.g() > green.r()); // More green
        assert!(red.r() > red.g()); // More red
    }
}
