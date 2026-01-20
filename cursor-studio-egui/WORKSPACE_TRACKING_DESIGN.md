# Workspace Tracking & Vector Search Design Document

## Overview

This document describes the workspace tracking system and vector search capabilities added to Cursor Studio, addressing the following user concerns:

1. **Workspace Management** - Ability to launch Cursor with a specific workspace/folder
2. **Central Chat History** - Pulling conversations from ALL Cursor instances
3. **Vector Search** - Fast, lightweight context retrieval for chat history
4. **Cursor CLI Integration** - Leveraging Cursor's new powerful CLI/TUI features

## Implementation Status

### ✅ Completed

#### 1. CLI Workspace Support (`cursor-studio-cli` and `cursor-versions`)

**Files Modified:**
- `cursor-studio-egui/src/bin/cursor_cli.rs`
- `tools/cursor-isolation/cursor-versions`

**New CLI Arguments:**
```bash
# cursor-studio-cli
cursor-studio-cli launch 2.1.34 --folder ~/myproject
cursor-studio-cli launch current -f /path/to/workspace --new-window

# cursor-versions (bash)
cursor-versions run 2.2.36 ~/myproject
cursor-versions run 2.2.36 -f /path/to/workspace -n
```

#### 2. Workspace Tracking System (`workspace.rs`)

**File:** `cursor-studio-egui/src/workspace.rs`

**Features:**
- SQLite-backed persistence (no external DB required)
- Tracks workspace metadata:
  - Path, name, description
  - Creation and last opened timestamps
  - Open count per workspace
  - Custom tags and colors
  - Pinned status
- Version tracking per workspace:
  - Which Cursor versions have opened the workspace
  - When and how many times
- Conversation linking:
  - Associate conversations with workspaces
  - Confidence scoring for fuzzy matching
- Git statistics:
  - Current branch
  - Uncommitted changes
  - Last commit info
  - Total files count

**Database Schema:**
```sql
workspaces (id, path, name, description, created_at, last_opened_at, ...)
workspace_versions (workspace_id, version, first_opened, last_opened, open_count)
workspace_conversations (workspace_id, conversation_id, source, confidence)
```

#### 3. Vector Search System (`vector.rs`)

**File:** `cursor-studio-egui/src/vector.rs`

**Features:**
- SQLite-backed with FTS5 for hybrid search
- Character n-gram + word-level TF-IDF embeddings (no external dependencies!)
- Cosine similarity for semantic search
- Supports multiple embedding sources:
  - `TfIdf` - Built-in, zero dependencies (default)
  - `OllamaLocal` - For local AI models (future)
  - `CursorApi` - Via Cursor's API (future)

**Why Not SurrealDB?**
- SurrealDB adds ~2-8 minutes to NixOS rebuild time
- sqlite-vec/FTS5 adds <10 seconds
- For our use case (semantic search over conversations), TF-IDF + FTS5 is sufficient

**Performance Characteristics:**
- Index: O(n) where n = text length
- Search: O(m * d) where m = num documents, d = embedding dimension
- For 100K documents at 384 dimensions: ~10-50ms search time

#### 4. Cursor CLI Integration (`workspace.rs::CursorCli`)

**Features:**
- Detect Cursor's `agent` CLI binary
- Launch GUI with workspace
- Launch CLI/TUI modes (normal, ask, plan)
- Headless execution for scripts
- API key support for automation

**Example Usage:**
```rust
let cli = CursorCli::new();

// Launch GUI
cli.launch_gui(workspace_path, Some("2.1.34"), true)?;

// Launch CLI in plan mode
cli.launch_cli(workspace_path, "plan", None)?;

// Headless execution
let output = cli.run_headless(workspace_path, "analyze this code", true, "json")?;
```

### 🔄 In Progress / Next Steps

#### 1. GUI Workspace Picker

**Current State:** Infrastructure added to `main.rs` but UI not fully wired up

**TODO:**
- [ ] Add "Workspaces" panel to left sidebar
- [ ] Recent workspaces list with launch buttons
- [ ] Folder picker dialog integration
- [ ] Workspace detail view (versions, conversations, git stats)
- [ ] Pin/tag/color workspace management

**Proposed UI Flow:**
```
┌─────────────────────────────────────────────┐
│ WORKSPACES                                  │
├─────────────────────────────────────────────┤
│ 📌 nixos-cursor         v2.1.34  2h ago    │
│    └ 12 convos | main | 3 uncommitted      │
│                                             │
│ 📁 homelab              v2.2.36  1d ago    │
│    └ 45 convos | feat/ai | clean           │
│                                             │
│ [+ Add Workspace...]                        │
├─────────────────────────────────────────────┤
│ [▶ Launch]  [📂 Browse]  [🔧 Settings]     │
└─────────────────────────────────────────────┘
```

#### 2. Conversation-Workspace Linking

**TODO:**
- [ ] Parse workspace paths from Cursor's `state.vscdb`
- [ ] Auto-detect workspace from conversation metadata
- [ ] Manual workspace assignment UI
- [ ] Bulk re-association tool

**Detection Strategies:**
1. `workspaceStorage` path contains workspace hash
2. File paths mentioned in messages
3. `.cursor` folder references
4. User manual assignment

#### 3. Vector Index Population

**TODO:**
- [ ] Index conversations during import
- [ ] Incremental indexing for new conversations
- [ ] Background re-indexing job
- [ ] Index quality monitoring

**Chunking Strategy:**
- Conversation titles → 1 chunk
- Messages → Split at ~500 chars (sentence boundaries)
- Code blocks → Separate chunks with metadata
- Tool calls → Index tool name and summary

#### 4. Advanced Search UI

**TODO:**
- [ ] Semantic search input in sidebar
- [ ] Filter by workspace, date, role
- [ ] Search result preview cards
- [ ] Jump-to-conversation from results
- [ ] Similar conversation suggestions

### 🎯 Future Enhancements (v0.4.0+)

#### 1. Ollama Integration for Better Embeddings

```rust
// Future: Use Ollama's embedding endpoint
pub async fn compute_ollama_embedding(&self, text: &str) -> Result<Vec<f32>> {
    let response = self.client
        .post("http://localhost:11434/api/embeddings")
        .json(&json!({
            "model": "nomic-embed-text",
            "prompt": text
        }))
        .send().await?;
    // Parse and return embedding vector
}
```

**Recommended Models:**
- `nomic-embed-text` - 768 dims, good quality
- `all-minilm` - 384 dims, faster
- `mxbai-embed-large` - 1024 dims, highest quality

#### 2. Cursor CLI Deep Integration

**Cursor CLI Features to Leverage:**
- `/plan` mode for architectural analysis
- `/ask` mode for codebase Q&A
- `/model` switching for cost optimization
- `/mcp` for tool access
- Cloud handoff with `&` prefix

**Potential Automations:**
```bash
# Auto-generate summaries
agent -p --output-format json "Summarize the last 5 commits"

# Security review
agent -p "Review for security issues" > review.md

# Documentation updates
agent -p --force "Update README with new features"
```

#### 3. Workspace Templates

Pre-configured workspace settings for common project types:
- NixOS configurations
- Rust projects
- Python ML projects
- Web applications

#### 4. Conversation Analytics

- Message count trends per workspace
- Token usage estimates
- Most active topics
- Context window usage patterns

## Database Comparison

| Feature | SurrealDB | SQLite + FTS5 + TF-IDF |
|---------|-----------|------------------------|
| NixOS Build Time | 2-8 min | <10 sec |
| Vector Search | Native | Custom TF-IDF |
| Full-text Search | Built-in | FTS5 extension |
| Dependencies | Heavy | Zero external |
| Sync Capabilities | Native | Manual |
| Query Language | SurrealQL | SQL |
| ACID Compliance | Yes | Yes |

**Recommendation:** Use SQLite + TF-IDF for v0.3.x, consider adding `instant-distance` crate for HNSW in v0.4.0 if semantic search quality needs improvement.

## File Structure

```
cursor-studio-egui/src/
├── workspace.rs       # Workspace tracking system
├── vector.rs          # Vector search and embeddings
├── main.rs            # GUI integration (partial)
├── lib.rs             # Public API exports
└── ...
```

## Testing

```bash
# Unit tests
cargo test --lib workspace
cargo test --lib vector

# Integration test with real data
cargo run --bin cursor-studio
```

## Configuration

Workspace data stored in:
- `~/.local/share/cursor-studio/workspaces.db` (workspace tracking)
- `~/.local/share/cursor-studio/vectors.db` (vector search index)

## References

- [Cursor CLI Documentation](https://cursor.com/docs/cli/overview)
- [Cursor Headless Mode](https://cursor.com/docs/cli/headless)
- [sqlite-vec](https://github.com/asg017/sqlite-vec) - If we want to upgrade
- [instant-distance](https://docs.rs/instant-distance) - Fast HNSW in Rust

