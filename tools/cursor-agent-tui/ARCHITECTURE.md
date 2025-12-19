# Cursor Agent TUI - Architecture

> A lightweight, Electron-free terminal interface for Cursor AI

## 🎯 Mission

Replace the Electron-based Cursor IDE with a composable TUI that:
- Eliminates memory bloat (no V8, no Chromium)
- Provides direct API access (no IPC overhead)
- Manages its own state efficiently (no 2GB SQLite)
- Runs anywhere (local terminal, SSH, tmux)

## 📐 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        cursor-agent-tui                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│  │   TUI Layer  │  │  Agent Core  │  │  Tool Runner │               │
│  │  (Ratatui)   │  │              │  │              │               │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘               │
│         │                 │                 │                        │
│         └────────────┬────┴────────────────┘                        │
│                      │                                               │
│              ┌───────▼───────┐                                       │
│              │ State Manager │  (bounded, efficient)                │
│              └───────┬───────┘                                       │
│                      │                                               │
│              ┌───────▼───────┐                                       │
│              │  API Client   │  (direct HTTPS to api2.cursor.sh)    │
│              └───────────────┘                                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ api2.cursor.sh  │
                    │   (gRPC-web)    │
                    └─────────────────┘
```

## 🧩 Components

### 1. API Client (`src/api/`)

Direct communication with Cursor's backend, bypassing Electron entirely.

```rust
pub struct CursorApiClient {
    /// HTTP client with connection pooling
    client: reqwest::Client,
    /// Authentication token
    auth: AuthToken,
    /// Base URL (api2.cursor.sh)
    base_url: String,
}

impl CursorApiClient {
    /// Stream a chat completion with tool calls
    pub async fn stream_chat(&self, request: ChatRequest) -> impl Stream<Item = ChatEvent>;
    
    /// Get available models
    pub async fn available_models(&self) -> Vec<Model>;
    
    /// Check queue position
    pub async fn queue_position(&self) -> QueueStatus;
}
```

**Protocol Details** (from proxy captures):
- Endpoint: `POST /aiserver.v1.ChatService/StreamUnifiedChatWithToolsSSE`
- Format: Server-Sent Events (SSE) with JSON payloads
- Auth: Bearer token in header
- Content-Type: `application/grpc-web+proto` (but actually JSON in practice)

### 2. Authentication (`src/auth/`)

Extract and manage Cursor authentication tokens.

```rust
pub struct AuthManager {
    /// Path to Cursor's credential storage
    cursor_storage: PathBuf,
    /// Cached token
    cached_token: Option<AuthToken>,
}

impl AuthManager {
    /// Extract token from Cursor's storage
    pub fn extract_from_cursor() -> Result<AuthToken>;
    
    /// Refresh expired token
    pub async fn refresh(&mut self) -> Result<AuthToken>;
    
    /// Store our own token (independent of Cursor)
    pub fn store_token(&self, token: AuthToken) -> Result<()>;
}
```

**Token Location**: `~/.cursor-server/data/` or `~/.config/Cursor/` depending on version.

### 3. Context Manager (`src/context/`)

Intelligent context building without VSCode's bloat.

```rust
pub struct ContextManager {
    /// Current working directory
    cwd: PathBuf,
    /// Open files in session
    open_files: Vec<FileContext>,
    /// Git repository info
    git: Option<GitContext>,
    /// Project configuration
    project: ProjectConfig,
}

impl ContextManager {
    /// Build context for a chat request
    pub fn build_context(&self, query: &str) -> Context;
    
    /// Add file to context
    pub fn add_file(&mut self, path: &Path) -> Result<()>;
    
    /// Get relevant files based on query
    pub fn relevant_files(&self, query: &str) -> Vec<&FileContext>;
}
```

**Key Difference from Cursor**: We only load files when needed, not maintain a massive index.

### 4. Tool Runner (`src/tools/`)

Execute tool calls directly, no IPC overhead.

```rust
pub enum ToolCall {
    ReadFile { path: PathBuf },
    WriteFile { path: PathBuf, content: String },
    RunCommand { command: String, cwd: Option<PathBuf> },
    Search { pattern: String, path: PathBuf },
    ListDirectory { path: PathBuf },
    // ... more tools
}

pub struct ToolRunner {
    /// Working directory
    cwd: PathBuf,
    /// Allowed paths (security)
    allowed_paths: Vec<PathBuf>,
    /// Command whitelist
    command_policy: CommandPolicy,
}

impl ToolRunner {
    /// Execute a tool call
    pub async fn execute(&self, tool: ToolCall) -> Result<ToolResult>;
    
    /// Check if tool is allowed
    pub fn is_allowed(&self, tool: &ToolCall) -> bool;
}
```

### 5. State Manager (`src/state/`)

Efficient, bounded state management (unlike Cursor's 2GB SQLite).

```rust
pub struct StateManager {
    /// Current conversation (in memory)
    conversation: Conversation,
    /// Conversation history (bounded ring buffer)
    history: RingBuffer<ConversationSummary>,
    /// Persistent storage (optional, much smaller)
    storage: Option<Storage>,
}

impl StateManager {
    /// Maximum conversation history entries
    const MAX_HISTORY: usize = 100;
    
    /// Maximum state file size
    const MAX_STATE_SIZE: usize = 50 * 1024 * 1024; // 50MB max
    
    /// Save conversation to history
    pub fn save_conversation(&mut self);
    
    /// Load conversation from history
    pub fn load_conversation(&mut self, id: &str) -> Result<()>;
    
    /// Prune old entries automatically
    pub fn prune(&mut self);
}
```

### 6. TUI Layer (`src/tui/`)

Terminal interface using Ratatui.

```rust
pub struct App {
    /// Current conversation
    conversation: ConversationView,
    /// File browser panel
    files: FileTreeView,
    /// Command/input area
    input: InputView,
    /// Status bar
    status: StatusBar,
    /// Current mode
    mode: Mode,
}

pub enum Mode {
    Normal,          // Navigate, view
    Insert,          // Typing message
    Command,         // : commands
    FileSelect,      // Selecting files for context
    DiffPreview,     // Viewing proposed changes
}
```

**Layout**:
```
┌──────────────────────────────────────────────────────────────┐
│ [cursor-agent] ~/nixos-cursor                    │ Model: o1 │
├──────────────────────────────────────────────────────────────┤
│ Files          │ Conversation                                │
│ ────────────── │ ──────────────────────────────────────────  │
│ ▼ src/         │ You: Fix the memory leak in pool.rs         │
│   main.rs      │                                              │
│   lib.rs       │ Agent: I'll analyze the connection pool...  │
│ ▼ tools/       │                                              │
│   cursor-proxy │ [Tool: read_file] src/pool.rs               │
│                │ [Tool: edit_file] Added cleanup method       │
│                │                                              │
│                │ ✓ Changes applied to pool.rs                │
├────────────────┴─────────────────────────────────────────────┤
│ > Fix the memory leak in the dashboard too                   │
├──────────────────────────────────────────────────────────────┤
│ [i]nsert [f]iles [d]iff [q]uit  │ Tokens: 15.2k │ Queue: 0  │
└──────────────────────────────────────────────────────────────┘
```

## 🔌 API Protocol Details

Based on proxy captures, the Cursor API uses:

### Chat Request

```json
{
  "conversation": {
    "messages": [
      {
        "role": "user",
        "content": "Fix the memory leak",
        "context": {
          "files": [
            {"path": "src/pool.rs", "content": "...", "language": "rust"}
          ]
        }
      }
    ]
  },
  "model": "claude-3-5-sonnet-20241022",
  "tools": ["read_file", "edit_file", "run_command", "search", "list_dir"],
  "stream": true
}
```

### Chat Response (SSE Stream)

```
event: message
data: {"type": "text", "content": "I'll analyze..."}

event: tool_call
data: {"type": "tool_call", "name": "read_file", "args": {"path": "src/pool.rs"}}

event: tool_result
data: {"type": "tool_result", "name": "read_file", "result": "...file content..."}

event: message
data: {"type": "text", "content": "I found the issue..."}

event: done
data: {"type": "done", "usage": {"prompt_tokens": 5000, "completion_tokens": 1500}}
```

## 🗂️ Project Structure

```
cursor-agent-tui/
├── Cargo.toml
├── src/
│   ├── main.rs           # Entry point
│   ├── app.rs            # Application state
│   ├── api/
│   │   ├── mod.rs
│   │   ├── client.rs     # API client
│   │   ├── types.rs      # Request/response types
│   │   └── stream.rs     # SSE stream handling
│   ├── auth/
│   │   ├── mod.rs
│   │   ├── token.rs      # Token management
│   │   └── extract.rs    # Extract from Cursor
│   ├── context/
│   │   ├── mod.rs
│   │   ├── manager.rs    # Context building
│   │   ├── files.rs      # File context
│   │   └── git.rs        # Git integration
│   ├── tools/
│   │   ├── mod.rs
│   │   ├── runner.rs     # Tool execution
│   │   ├── file_ops.rs   # File read/write
│   │   ├── terminal.rs   # Command execution
│   │   └── search.rs     # Code search
│   ├── state/
│   │   ├── mod.rs
│   │   ├── manager.rs    # State management
│   │   ├── conversation.rs
│   │   └── storage.rs    # Persistence
│   └── tui/
│       ├── mod.rs
│       ├── app.rs        # TUI application
│       ├── views/
│       │   ├── conversation.rs
│       │   ├── files.rs
│       │   ├── input.rs
│       │   └── diff.rs
│       └── widgets/
│           ├── message.rs
│           └── tool_call.rs
├── tests/
│   └── ...
└── README.md
```

## 🛠️ Dependencies

```toml
[dependencies]
# TUI
ratatui = "0.26"
crossterm = "0.27"

# Async runtime
tokio = { version = "1", features = ["full"] }

# HTTP client
reqwest = { version = "0.12", features = ["stream", "json"] }

# SSE parsing
eventsource-stream = "0.2"

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# File operations
walkdir = "2"
ignore = "0.4"  # .gitignore support

# Git integration
git2 = "0.18"

# Syntax highlighting (optional)
syntect = "5"

# Diff display
similar = "2"

# Error handling
thiserror = "1"
anyhow = "1"

# Logging
tracing = "0.1"
tracing-subscriber = "0.3"
```

## 🚀 Development Phases

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] API client with authentication
- [ ] Basic SSE stream handling
- [ ] Token extraction from Cursor
- [ ] Simple request/response cycle

### Phase 2: Tool Execution (Week 2-3)
- [ ] File read/write tools
- [ ] Terminal command execution
- [ ] Search functionality
- [ ] Tool result formatting

### Phase 3: TUI Interface (Week 3-4)
- [ ] Basic Ratatui layout
- [ ] Conversation view
- [ ] Input handling
- [ ] File browser

### Phase 4: Context & State (Week 4-5)
- [ ] Context manager
- [ ] File context building
- [ ] Conversation history
- [ ] Bounded state storage

### Phase 5: Polish & Features (Week 5-6)
- [ ] Diff preview
- [ ] Syntax highlighting
- [ ] Git integration
- [ ] Configuration system

## 🔐 Security Considerations

1. **Token Storage**: Store tokens securely, not in plain text
2. **Path Restrictions**: Only allow operations within project directory
3. **Command Whitelist**: Restrict allowed terminal commands
4. **Network**: HTTPS only, certificate validation

## 📊 Performance Targets

| Metric | Cursor IDE | cursor-agent-tui Target |
|--------|-----------|------------------------|
| Memory (idle) | 500MB+ | <50MB |
| Memory (active) | 2GB+ | <200MB |
| Startup time | 5-10s | <1s |
| State file size | 2GB+ | <50MB (hard limit) |
| File descriptor usage | 1000+ | <100 |

## 🔗 Integration with Existing Tools

- **cursor-proxy**: Can still use for traffic analysis/debugging
- **cursor-studio**: Can launch TUI as alternative mode
- **cursor-studio-egui**: Shares API client code

## 📝 Notes

This architecture prioritizes:
1. **Simplicity** - Do one thing well (AI chat + tools)
2. **Efficiency** - Bounded memory, no bloat
3. **Composability** - Works in any terminal environment
4. **Reliability** - Explicit state management, no surprises

The goal is NOT to replicate all of VSCode/Cursor, but to provide a focused, efficient interface for AI-assisted coding that doesn't consume half your RAM.

