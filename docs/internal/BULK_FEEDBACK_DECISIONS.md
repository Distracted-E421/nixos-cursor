# Bulk Feedback Decisions Record

**Date:** December 6, 2025  
**Context:** Comprehensive feedback on Data Pipeline Control objectives and D2 Viewer implementation

---

## 📋 Previous Session Questions (Data Pipeline Control)

### Q1: Conversation Browser UI Location
**Decision:** Keep as its own tab for now with left side icon
**Notes:** Eventually will flesh out more specific UI things within the editor

### Q2: Embedding Support  
**Decision:** Support BOTH options + roadmap API integration
**Notes:** API integration for users with wallets without limits

### Q3: Sync Daemon (Rust vs Elixir)
**Decision:** Research both to determine which performs best
**Key Factor:** Hot reloading capability for better DB experience
**Status:** Research needed

### Q4: Context Injection Data Format
**Decision:** Prototype MULTIPLE options, build a better system
**Concerns about MCP:**
- Excessive token usage per prompt
- Requires everything loaded before the prompt
**Concerns about JSON/SQL:**
- Not ideal for data expression
- "JSON works but is not an end game data language"
**Status:** Open to experimentation

### Q5: Workspace Snapshots
**Decision:** ALL of the above
**Goal:** Snapshots should endeavor to get as much as possible down to the byte
**Rationale:** Atomic/reproducible workspace rebuilds

### Q6: @docs System Research
**Decision:** Focus on reverse engineering Cursor SERVER-SIDE API
**NOT:** MCP approach (due to inherent issues with MCP)
**Status:** RE research needed

### Q7: Network Traffic Monitoring
**Decision:** MUST HAVE for the reverse engineering process
**Status:** Priority for @docs RE

### Q8: Export Features
**Decision:** Build export feature with multiple methods:
- Whole DB file export
- HTML file export  
- MD file with properly formatted context
- Bulk export capability
- Sort/organize exported content
**Default ordering:** Date last modified/chatted

### Q9: Cursor Sync POC Location
**Decision:** Move to cursor-studio-egui and rewrite in Rust
**Status:** Migration planned

---

## 🎨 D2 Viewer Questions (New Session)

### Q10: Layout Engines
**Decision:** ALL OF THE ABOVE with selector
- Grid layout ✅ Implemented
- Dagre (hierarchical) ✅ Implemented
- Force-directed (spring physics) ✅ Implemented
- Manual positioning ✅ Implemented

### Q11: Real-time Data Flow Visualization
**Decision:** ALL OF THE ABOVE
- Animated dots flowing along edges ✅ Implemented
- Pulsing nodes when active ✅ Implemented
- Color gradients showing load/latency ✅ Implemented
- Status indicators ✅ Implemented

### Q12: Theme Picker
**Decision:** Enhance current implementation with:
- Live preview feature
- Option to sync between Cursor and cursor-studio
- Option to keep themes separate
- Theme persistence (not reset on relaunch)
- Home Manager options for theme settings
**Status:** Partially implemented, needs live preview & persistence

### Q13: D2 Editor Integration
**Decision:** ALL OF THE ABOVE and more
- Side-by-side editor ✅ Implemented
- Syntax highlighting ✅ Implemented
- Live error highlighting - TODO
- Auto-complete for shapes/styles ✅ Implemented
**Status:** Core features done, error highlighting pending

### Q14: Containers/Nesting
**Decision:** PRIORITY - ALL OF THE ABOVE
- Draw container borders with labels - TODO
- Collapsible containers - TODO
- Child layout within containers ✅ Basic implementation
**Status:** Basic child layout done, needs border rendering and collapse

---

## 🚀 Implementation Status

### ✅ Completed Today
1. **D2 Parser** - Full D2 syntax support
2. **Interactive Renderer** - Pan, zoom, select, drag
3. **Shape Rendering** - 20+ D2 shapes
4. **Theme Mapper** - VS Code theme to diagram colors
5. **Layout Engines** - Grid, Dagre, Force, Manual
6. **Data Flow Viz** - Particles, pulsing, gradients
7. **Syntax Highlighter** - Keywords, properties, shapes
8. **Auto-complete** - Context-aware completions

### 🔄 In Progress
1. Theme persistence (Home Manager integration)
2. Container border rendering
3. Collapsible containers
4. Live error highlighting

### 📋 Next Steps (Priority Order)
1. Theme persistence & Home Manager options
2. Container border/label rendering
3. Collapsible container UI
4. Live error highlighting in editor
5. Network traffic monitoring for @docs RE
6. Research Rust vs Elixir sync daemon

---

## 📝 Additional Notes

### MCP Concerns Raised
The user explicitly mentioned that MCP has inherent issues:
1. **Token usage** - Everything must be loaded before the prompt
2. **Not suitable for context injection** - Looking for better alternatives

This informs future architecture decisions - avoid heavy MCP reliance for data-intensive operations.

### Data Format Philosophy
- JSON: Works but "not an end game data language"
- SQL/SQLite: Functional but limited expression
- Goal: Find/build better data representation for context injection

### Snapshot Philosophy
- Down to the byte reproducibility
- Atomic rebuilds
- Complete workspace state capture

---

**Last Updated:** 2025-12-06T16:45:00Z
