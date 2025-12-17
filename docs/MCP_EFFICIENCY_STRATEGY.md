# MCP Efficiency Strategy

## The Problem

Model Context Protocol (MCP) servers are valuable but **token-inefficient**:

| Issue | Impact |
|-------|--------|
| JSON verbosity | Every tool call/response adds ~200-500 tokens overhead |
| Schema duplication | Tool definitions repeated in every context |
| Response bloat | Structured data often 3-5x larger than needed |
| Context collapse | Token waste → faster context window exhaustion |
| No streaming | Full responses required even for progress |

### Example: Simple File Read

**MCP Way** (~400 tokens total):
```json
// Tool call
{"name": "mcp_filesystem_read_file", "parameters": {"path": "/home/e421/file.txt"}}
// Response wrapper + content
{"content": [{"type": "text", "text": "file contents..."}]}
```

**Direct Way** (~50 tokens):
```
cat /home/e421/file.txt
→ file contents...
```

## Strategy: Built-in Efficient Alternatives

Rather than removing MCP servers, we build **efficient alternatives** for common operations that live inside Cursor Studio itself.

### Phase 1: High-Impact Replacements

#### 1. **Memory** → Local Knowledge Graph

Replace MCP memory server with embedded graph database:

```rust
// cursor-studio-egui/src/memory/mod.rs
pub struct LocalMemory {
    db: sled::Db,  // Fast embedded key-value store
    graph: petgraph::Graph<Entity, Relation>,
}

impl LocalMemory {
    pub fn remember(&mut self, key: &str, value: &str, context: &str) -> Result<()>;
    pub fn recall(&self, query: &str) -> Vec<MemoryEntry>;
    pub fn forget(&mut self, key: &str) -> Result<()>;
}
```

**Benefits:**
- Zero network/IPC overhead
- Instant access
- No JSON serialization
- AI can access via simple function calls
- Persistent across sessions

#### 2. **Filesystem** → Direct File Operations

For operations within workspace, use direct Rust:

```rust
// cursor-studio-egui/src/files/mod.rs
pub struct WorkspaceFiles {
    root: PathBuf,
    cache: DashMap<PathBuf, FileCache>,
}

impl WorkspaceFiles {
    pub fn read(&self, path: &Path) -> Result<String>;
    pub fn write(&self, path: &Path, content: &str) -> Result<()>;
    pub fn search(&self, pattern: &str) -> Vec<SearchResult>;
    pub fn tree(&self, depth: usize) -> DirectoryTree;
}
```

**Benefits:**
- Cached reads (no repeated I/O)
- Streaming for large files
- Native gitignore support
- Efficient glob matching

#### 3. **GitHub** → Git Operations Module

```rust
// cursor-studio-egui/src/git/mod.rs
pub struct GitOps {
    repo: git2::Repository,
    gh_token: Option<String>,
}

impl GitOps {
    // Local operations (instant, no API)
    pub fn status(&self) -> GitStatus;
    pub fn diff(&self, staged: bool) -> String;
    pub fn log(&self, limit: usize) -> Vec<Commit>;
    pub fn branches(&self) -> Vec<Branch>;
    
    // Remote operations (batched, cached)
    pub fn push(&self, remote: &str, branch: &str) -> Result<()>;
    pub fn create_pr(&self, title: &str, body: &str) -> Result<PullRequest>;
}
```

**Benefits:**
- Local ops don't need network
- Batch multiple operations
- Cache remote responses
- Incremental updates

#### 4. **Screenshots** → Built-in Capture

```rust
// cursor-studio-egui/src/feedback/mod.rs
pub struct VisualFeedback {
    screenshot_dir: PathBuf,
}

impl VisualFeedback {
    pub fn capture_window(&self, title: &str) -> Result<PathBuf>;
    pub fn capture_region(&self, rect: Rect) -> Result<PathBuf>;
    pub fn diff_images(&self, a: &Path, b: &Path) -> ImageDiff;
    pub fn annotate(&self, image: &Path, annotations: &[Annotation]) -> Result<PathBuf>;
}
```

### Phase 2: Domain-Specific Intelligence

#### 5. **NixOS** → Embedded Knowledge

Instead of querying external MCP for Nix info:

```rust
// cursor-studio-egui/src/nix/mod.rs
pub struct NixKnowledge {
    packages: FuzzyIndex<PackageInfo>,  // Loaded from dump
    options: FuzzyIndex<NixOption>,     // Loaded from dump
    flakes: HashMap<String, FlakeInfo>, // User's flakes
}

impl NixKnowledge {
    pub fn search_packages(&self, query: &str) -> Vec<PackageInfo>;
    pub fn option_docs(&self, option: &str) -> Option<NixOption>;
    pub fn flake_outputs(&self, flake: &str) -> Result<Vec<FlakeOutput>>;
}
```

**Data source:** Pre-generated JSON dumps from `nix search --json`, `nixos-option --json`, etc.

#### 6. **Playwright** → Lightweight Browser Control

For service verification, use minimal browser automation:

```rust
// cursor-studio-egui/src/browser/mod.rs
pub struct BrowserControl {
    // Use headless chromium or webkit
}

impl BrowserControl {
    pub fn screenshot_url(&self, url: &str) -> Result<PathBuf>;
    pub fn check_health(&self, url: &str) -> HealthStatus;
    pub fn extract_text(&self, url: &str, selector: &str) -> Result<String>;
}
```

### Phase 3: AI Integration Layer

#### Token-Efficient AI Interface

```rust
// cursor-studio-egui/src/ai/mod.rs
pub struct AiInterface {
    memory: LocalMemory,
    files: WorkspaceFiles,
    git: GitOps,
    nix: NixKnowledge,
}

impl AiInterface {
    /// Single entry point for AI - minimal JSON, maximum context
    pub fn query(&self, request: AiRequest) -> AiResponse {
        // Parse intent
        // Execute locally where possible
        // Only call external services when necessary
        // Return concise, structured response
    }
}

pub enum AiRequest {
    Remember { key: String, value: String },
    Recall { query: String },
    ReadFile { path: PathBuf },
    WriteFile { path: PathBuf, content: String },
    GitStatus,
    GitCommit { message: String, files: Vec<PathBuf> },
    SearchNixPackages { query: String },
    Screenshot { target: String },
    // ... more operations
}

pub enum AiResponse {
    Success { data: serde_json::Value },
    Error { message: String },
    NeedsConfirmation { action: String },
}
```

## Implementation Priority

| Feature | Tokens Saved | Complexity | Priority |
|---------|--------------|------------|----------|
| Local Memory | ~300/op | Medium | 🔥 High |
| Direct File Ops | ~250/op | Low | 🔥 High |
| Git Local Ops | ~400/op | Medium | High |
| Screenshot | ~200/op | Low | Medium |
| NixOS Knowledge | ~500/op | High | Medium |
| Browser Control | ~300/op | High | Low |

## Migration Path

1. **Keep MCPs active** - Fallback for edge cases
2. **Build local alternatives** - One at a time
3. **Prefer local in code** - AI learns to use efficient path
4. **Measure token savings** - Track before/after
5. **Deprecate MCPs gradually** - As confidence builds

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Cursor Studio                        │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │   Memory    │ │   Files     │ │    Git      │       │
│  │  (sled)     │ │  (direct)   │ │  (git2)     │       │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘       │
│         │               │               │               │
│         └───────────────┼───────────────┘               │
│                         ▼                               │
│               ┌─────────────────┐                       │
│               │  AI Interface   │ ◄── Minimal JSON      │
│               │  (unified API)  │                       │
│               └────────┬────────┘                       │
│                        │                                │
├────────────────────────┼────────────────────────────────┤
│                        ▼                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │            MCP Fallback Layer                     │  │
│  │  (Only used when local alternative unavailable)  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Metrics to Track

1. **Tokens per operation** - Before/after comparison
2. **Latency** - Response time improvement
3. **Context window usage** - Longer conversations
4. **Fallback rate** - How often MCP still needed
5. **Error rate** - Reliability of local alternatives

## Future: Local Agent Foundation

This efficient layer becomes the foundation for local agents:

```rust
pub struct LocalAgent {
    interface: AiInterface,
    model: LocalLLM,  // llama.cpp, ollama, etc.
    planner: TaskPlanner,
}

impl LocalAgent {
    pub async fn execute(&mut self, task: &str) -> Result<TaskResult> {
        let plan = self.planner.plan(task)?;
        for step in plan {
            let result = self.interface.query(step)?;
            self.planner.update(result)?;
        }
        Ok(self.planner.finalize()?)
    }
}
```

This enables:
- **Fully offline operation** - No external services needed
- **Privacy** - All data stays local
- **Speed** - No network latency
- **Cost** - No API charges
- **Customization** - Domain-specific tuning

## Next Steps

1. [ ] Create `cursor-studio-egui/src/memory/` module
2. [ ] Create `cursor-studio-egui/src/files/` module
3. [ ] Create `cursor-studio-egui/src/git/` module
4. [ ] Design unified `AiInterface`
5. [ ] Add metrics/logging
6. [ ] Create `.cursor/rules/efficient-operations.mdc`

