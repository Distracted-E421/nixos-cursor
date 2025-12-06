//! D2 Diagram Rendering Module
//!
//! Native D2 diagram rendering for cursor-studio with:
//! - Interactive pan/zoom
//! - Theme-aware colors from VS Code themes
//! - Click-to-select nodes
//! - Real-time data flow visualization
//! - Multiple layout algorithms (Grid, Dagre, Force-directed)
//! - Syntax highlighting and auto-complete for D2 editor
//!
//! Part of the Data Pipeline Control objectives for v0.3.0.

pub mod parser;
pub mod renderer;
pub mod graph;
pub mod theme_mapper;
pub mod layout;
pub mod dataflow;
pub mod syntax;

pub use graph::{D2Graph, D2Node, D2Edge, D2Shape, D2Style, Direction, ArrowType, NodeData};
pub use renderer::D2Viewer;
pub use theme_mapper::DiagramTheme;
pub use layout::{LayoutEngine, LayoutConfig, compute_layout, force_layout_step};
pub use dataflow::{DataFlowState, EdgeFlow, NodeActivity, NodeStatus};
pub use syntax::{D2Highlighter, HighlightSpan, HighlightKind, Completion, CompletionContext, CompletionKind};
