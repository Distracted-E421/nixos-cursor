# Cursor Studio Enhancement Roadmap

## ✅ Completed (v0.3.2)

### 1. CLI Workspace Support
- [x] `cursor-studio-cli launch` now supports `--folder/-f` and `--new-window/-n`
- [x] `cursor-versions run` bash script supports folder argument

### 2. Workspace Tracking System
- [x] SQLite-backed workspace registry (`workspace.rs`)
- [x] Track workspace paths, names, open counts
- [x] Track which Cursor versions opened each workspace
- [x] Git statistics integration (branch, uncommitted changes, etc.)
- [x] Pin/tag/color support

### 3. GUI Workspace Panel
- [x] New "Workspaces" tab in left sidebar (📂 icon)
- [x] Native folder picker dialog (`rfd` crate integration)
- [x] Recent workspaces list with stats
- [x] Double-click to launch
- [x] Version selector dropdown
- [x] Pin/unpin workspaces
- [x] Delete workspace from list
- [x] Filter/search workspaces
- [x] Drag & drop folder support

### 4. Vector Search Infrastructure
- [x] TF-IDF + FTS5 hybrid search (`vector.rs`)
- [x] Conversation indexing during import
- [x] Character n-gram + word-level embeddings
- [x] Cosine similarity search
- [x] Workspace-scoped search support

---

## 🔄 v0.4.0 - Cursor CLI Integration

### Goals
Leverage Cursor's new powerful CLI/TUI for deeper integration.

### Tasks

#### 1. CLI Detection & Status
- [ ] Detect `agent` binary on system
- [ ] Show CLI availability in settings panel
- [ ] Display version info

#### 2. Headless Agent Commands
- [ ] "Run Agent" button in workspace panel
- [ ] Choose mode: Normal / Ask / Plan
- [ ] Prompt input dialog
- [ ] Output viewer panel

#### 3. Quick Actions
- [ ] "Explain Codebase" - `agent -p "What does this codebase do?"`
- [ ] "Review Changes" - `agent -p "Review recent changes"`
- [ ] "Update Docs" - `agent -p --force "Update README"`
- [ ] "Security Audit" - `agent -p "Check for security issues"`

#### 4. MCP Integration
- [ ] Show available MCP servers from `/mcp list`
- [ ] Enable/disable MCPs from Studio
- [ ] MCP configuration editor

### Implementation Plan

```rust
// New panel: AgentPanel
struct AgentPanel {
    cli: CursorCli,
    current_prompt: String,
    mode: AgentMode, // Normal, Ask, Plan
    output_history: Vec<AgentOutput>,
    running: Option<std::process::Child>,
}

impl AgentPanel {
    fn run_headless(&mut self, workspace: &Path, force: bool) {
        let output = self.cli.run_headless(
            workspace,
            &self.current_prompt,
            force,
            "json"
        );
        // Parse and display output
    }
}
```

---

## 🔮 v0.5.0 - Enhanced Search & Context

### Goals
Make vector search actually useful for context retrieval.

### Tasks

#### 1. Ollama Integration
- [ ] Auto-detect local Ollama instance
- [ ] Settings to configure embedding model
- [ ] Background re-indexing with real embeddings
- [ ] Fallback to TF-IDF when Ollama unavailable

```rust
// Ollama embedding endpoint
async fn get_ollama_embedding(text: &str, model: &str) -> Result<Vec<f32>> {
    let response = reqwest::Client::new()
        .post("http://localhost:11434/api/embeddings")
        .json(&json!({
            "model": model, // "nomic-embed-text" or "all-minilm"
            "prompt": text
        }))
        .send().await?;
    
    let data: EmbeddingResponse = response.json().await?;
    Ok(data.embedding)
}
```

#### 2. Semantic Search UI
- [ ] Dedicated search panel with semantic mode toggle
- [ ] "Find similar conversations" feature
- [ ] Search within workspace scope
- [ ] Search results with relevance scores
- [ ] Jump-to-message from results

#### 3. Context Window Builder
- [ ] Select multiple conversations/messages
- [ ] Build custom context payload
- [ ] Export as JSON/markdown
- [ ] Token count estimation

#### 4. instant-distance HNSW (Optional)
If TF-IDF proves insufficient:
- [ ] Add `instant-distance` crate
- [ ] Build HNSW index for fast ANN search
- [ ] Benchmark vs brute-force cosine

---

## 🚀 v0.6.0 - Automation & Workflows

### Goals
Enable automated workflows using Cursor CLI.

### Tasks

#### 1. Workflow Templates
- [ ] Pre-defined automation templates
- [ ] Custom workflow editor
- [ ] Schedule workflows (cron-like)

Example templates:
```yaml
name: "Daily Code Review"
schedule: "0 9 * * *"  # 9 AM daily
steps:
  - action: git_diff
    range: "HEAD~5..HEAD"
  - action: agent
    prompt: "Review these changes for issues"
    mode: ask
    output: review.md
  - action: notify
    method: toast
```

#### 2. Cloud Agent Integration
- [ ] Handoff conversations to Cursor Cloud
- [ ] Track cloud agent status
- [ ] Pull results back when complete

#### 3. GitHub Integration
- [ ] Create PR from agent output
- [ ] Auto-generate commit messages
- [ ] Link conversations to PRs

---

## 📊 v1.0.0 - Analytics & Intelligence

### Goals
Understand and optimize AI usage patterns.

### Tasks

#### 1. Usage Analytics
- [ ] Token usage tracking per workspace
- [ ] Cost estimation (based on model)
- [ ] Usage trends over time
- [ ] Most active workspaces/topics

#### 2. Smart Suggestions
- [ ] "You asked about X before" - link to past conversation
- [ ] "Similar issue in project Y" - cross-workspace search
- [ ] Context recommendation engine

#### 3. Export & Backup
- [ ] Full workspace export (conversations + metadata)
- [ ] Scheduled backups
- [ ] Import from backup
- [ ] Sync across machines (P2P or server)

---

## Technical Debt & Improvements

### Build Performance
- [ ] Investigate feature flags to reduce build time
- [ ] Pre-built binaries for common platforms
- [ ] Incremental compilation optimization

### Code Quality
- [ ] Add integration tests for workspace tracking
- [ ] Add benchmarks for vector search
- [ ] Document public API
- [ ] Reduce warnings (currently ~255)

### UX Polish
- [ ] Loading states for async operations
- [ ] Error recovery UI
- [ ] Keyboard shortcuts
- [ ] Accessibility improvements

---

## Database Migration Path

### Current: SQLite + TF-IDF (v0.3.x)
- ✅ Fast builds (~10 sec)
- ✅ Zero external dependencies
- ✅ Good enough for most searches
- ⚠️ Semantic search quality limited

### Future: SQLite + Ollama Embeddings (v0.5.0+)
- ✅ Much better semantic search
- ✅ Still fast builds
- ⚠️ Requires local Ollama
- ✅ Graceful fallback to TF-IDF

### Optional: instant-distance HNSW
- ✅ ~50KB compiled size
- ✅ Sub-millisecond search
- ✅ Memory-efficient
- Consider if dataset > 100K documents

---

## Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Ollama embeddings | High | Medium | P1 |
| Semantic search UI | High | Medium | P1 |
| Agent quick actions | High | Low | P1 |
| MCP integration | Medium | Medium | P2 |
| Workflow templates | Medium | High | P2 |
| Usage analytics | Medium | Medium | P2 |
| Cloud handoff | Low | High | P3 |
| GitHub integration | Medium | High | P3 |

---

## Dependencies to Add

### v0.4.0
```toml
# None needed - use existing workspace.rs CursorCli
```

### v0.5.0
```toml
# For Ollama API calls (already have reqwest)
# May want: serde_json improvements

# Optional: If HNSW needed
instant-distance = "0.6"
```

### v0.6.0
```toml
# For scheduling
cron = "0.12"

# For GitHub API
octocrab = "0.32"
```

---

## Next Immediate Steps

1. **Test the workspace panel** - Run cursor-studio and verify:
   - Folder picker works
   - Workspaces are persisted
   - Launch with workspace works
   - Version selector works

2. **Test conversation indexing** - Import some conversations and verify:
   - Index count is displayed
   - Vector store contains chunks
   - Basic search works

3. **Document new features** - Update README and user guide

4. **Plan v0.4.0 sprint** - Focus on Cursor CLI integration

