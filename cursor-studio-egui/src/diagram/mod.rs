//! D2 Diagram Rendering Module
//!
//! Native D2 diagram rendering for cursor-studio with:
//! - Interactive pan/zoom
//! - Theme-aware colors from VS Code themes
//! - Click-to-select nodes
//! - Real-time data flow visualization (planned)
//!
//! Part of the Data Pipeline Control objectives for v0.3.0.

pub mod parser;
pub mod renderer;
pub mod graph;
pub mod theme_mapper;

pub use graph::{D2Graph, D2Node, D2Edge, D2Shape};
pub use renderer::D2Viewer;
pub use theme_mapper::DiagramTheme;
