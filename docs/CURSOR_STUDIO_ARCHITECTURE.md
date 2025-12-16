# Cursor Studio Architecture

## Vision

**Cursor Studio** is the escape pod from VS Code/Electron bloat - a native, GPU-accelerated IDE built for the future of AI-assisted development.

### The Problem

1. **VS Code is a clusterfuck** when pushed hard - slow, buggy, Electron overhead
2. **Cursor is losing the plot** - buggy releases, cut features (custom modes), broken docs
3. **TypeScript backend** - not performant, not NixOS-friendly
4. **Subscription lock-in** - can't use local compute effectively
5. **Electron** - just bad for native desktop apps

### The Solution

Build a bridge that:
- **Uses Cursor's AI as a temporary brain** (your $40/mo gets 1000 fast + unlimited slow)
- **Native GPU-accelerated UI** using egui (Rust) - no Electron
- **Local compute first** - your GPUs, your models, your data
- **Declarative configuration** via Nickel - not JSON/YAML mess
- **Profile system** - vi, vim, emacs, neovim, vscode, jetbrains keybindings
- **NixOS-native** - reproducible, declarative, just works

### Language Stack

| Layer | Language | Why |
|-------|----------|-----|
| GUI | **Rust + egui** | Native, GPU-accelerated, fast |
| TUI | **Rust + ratatui** | Same codebase, terminal power users |
| Services | **Elixir** | Fault-tolerant, hot-reload, distributed |
| Config | **Nickel** | Typed, declarative, better than YAML/JSON |
| Scripts | **Nushell** | Structured data, replaces bash |
| AI/ML | **Python (uv)** | Ecosystem, but managed properly |
| System | **Nix** | Reproducible builds, NixOS integration |

### End Goal

A fully independent, local-first IDE that:
- Runs AI inference on your hardware (Ollama, ONNX, custom models)
- Syncs across devices via your infrastructure
- Configures declaratively via Nickel
- Provides hardcore dev experience (vi-mode, TUI, fast)
- Remains usable for beginners (GUI, presets, defaults)

## Sub-Application Naming

### Proposed Names (Theme: Clear, Action-Oriented)

| Module | Name | Icon | Description |
|--------|------|------|-------------|
| Chat Export | **Archive** | 📚 | Chat history export, import, browsing, search |
| Documentation | **Index** | 🗂️ | Web documentation scraping, indexing, search |
| Security | **Sentinel** | 🛡️ | Security alerts, quarantine, content validation |
| Sync | **Bridge** | 🔗 | Cursor @docs sync, file watchers, integration |
| Data Transform | **Forge** | 🔥 | Data manipulation, training data prep, exports |

### Alternative Naming Schemes

**Option A: Lab Theme** (experimental feel)
- Chat Lab, Docs Lab, Security Lab, Sync Lab, Data Lab

**Option B: Single Word**
- Library, Index, Shield, Sync, Transform

**Option C: Cursor Prefix**
- Cursor Archive, Cursor Index, Cursor Sentinel, Cursor Bridge, Cursor Forge

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CURSOR STUDIO (egui)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌─────────┐          │
│  │ Archive │  │  Index  │  │ Sentinel │  │ Bridge  │  │  Forge  │  [tabs]  │
│  │   📚    │  │   🗂️   │  │    🛡️   │  │   🔗    │  │   🔥    │          │
│  └─────────┘  └─────────┘  └──────────┘  └─────────┘  └─────────┘          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐    ┌─────────────────────────────────────────────┐ │
│  │    SIDEBAR          │    │                 MAIN PANEL                  │ │
│  │                     │    │                                             │ │
│  │  [Dashboard]        │    │  Content varies by module:                  │ │
│  │  ─────────────      │    │                                             │ │
│  │  📊 Quick Stats     │    │  Archive: Chat list, preview, export        │ │
│  │  🔔 Alerts (3)      │    │  Index:   Doc sources, add/manage, search   │ │
│  │  ⚡ Actions         │    │  Sentinel: Alert feed, quarantine review    │ │
│  │                     │    │  Bridge:  Sync status, watched paths        │ │
│  │  [Items]            │    │  Forge:   Data pipelines, transforms        │ │
│  │  ─────────────      │    │                                             │ │
│  │  ▸ Item 1 (expand)  │    │                                             │ │
│  │    └─ details       │    │                                             │ │
│  │  ▸ Item 2           │    │                                             │ │
│  │  ▸ Item 3           │    │                                             │ │
│  │                     │    │                                             │ │
│  └─────────────────────┘    └─────────────────────────────────────────────┘ │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Status Bar]  Connected: cursor-docs | CPU: 2% | RAM: 45MB | v0.3.0-pre   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Module Details

### 1. Archive (Chat Export) 📚

**Purpose**: Browse, search, and export Cursor chat history

**Sidebar**:
- Dashboard with chat statistics
- Filter by source/workspace
- Search box
- List of conversations (expandable)

**Main Panel**:
- Chat viewer (markdown rendered)
- Export options panel
- Batch operations

**Features**:
- List all chats from all Cursor installations
- Search by content
- Export to: Markdown, JSON, JSONL, HTML, TXT
- Markdown presets: Obsidian, GitHub, Notion, Docusaurus
- Training data formats: OpenAI, Alpaca, ShareGPT
- Batch export with customization

### 2. Index (Documentation) 🗂️

**Purpose**: Add, manage, and search indexed documentation

**Sidebar**:
- Dashboard with indexing stats
- Quick actions (Add URL, Refresh All)
- List of doc sources (expandable with details)
  - Status indicator (✅ indexed, ⏳ indexing, ❌ failed)
  - Chunk count
  - Last indexed time

**Main Panel**:
- Add new documentation form
  - URL input
  - Name/alias
  - Options (max pages, follow links, force re-index)
- Source details view
  - URL, name, status
  - Chunk browser
  - Re-index button
  - Delete button
- Search interface
  - Query input
  - Results with snippets
  - Jump to source

**Features**:
- Add documentation by URL
- Monitor indexing progress
- Browse indexed content
- Search across all sources
- Manage sources (refresh, delete)
- View security status per source

### 3. Sentinel (Security) 🛡️

**Purpose**: Monitor security alerts and manage quarantine

**Sidebar**:
- Dashboard with alert summary
  - 🚨 Critical: N
  - ⚠️ High: N
  - ⚡ Medium: N
  - ℹ️ Low: N
- Filter by severity/type
- Quarantine queue (N pending)

**Main Panel**:
- Alert feed (real-time updates)
- Alert detail view
  - Source, type, severity
  - Description
  - Affected content preview (safe)
  - Actions: dismiss, investigate
- Quarantine review
  - Item preview
  - Alerts list
  - Actions: approve, reject, flag

**Features**:
- Real-time security alerts
- Quarantine review workflow
- Content validation details
- Export alerts for analysis
- Alert history and trends

### 4. Bridge (Sync) 🔗

**Purpose**: Sync with Cursor and manage integrations

**Sidebar**:
- Dashboard with sync status
- Connection status indicators
- Watched paths list

**Main Panel**:
- Cursor @docs sync status
- Manual sync triggers
- Watched path configuration
- Integration settings
  - Cursor installation paths
  - Auto-sync options
  - Notification preferences

**Features**:
- Sync from Cursor's @docs
- Monitor Cursor database changes
- Multi-installation support
- Auto-sync on change
- Sync history log

### 5. Forge (Data Transform) 🔥

**Purpose**: Transform and prepare data for AI training

**Sidebar**:
- Dashboard with data stats
- Pipeline templates
- Recent exports

**Main Panel**:
- Data source selection
  - Chats
  - Indexed docs
  - Custom files
- Transform pipeline builder
  - Filter by criteria
  - Format selection
  - Output options
- Export configuration
  - Training format (OpenAI, Alpaca, etc.)
  - Split ratios (train/val/test)
  - Deduplication
  - Quality filters

**Features**:
- Combine multiple data sources
- Transform to training formats
- Quality filtering
- Deduplication
- Train/val/test splits
- Export to local or cloud

## Shared Components

### Status Bar
- Backend connection status
- Resource usage (CPU, RAM)
- Version info
- Notifications

### Settings Panel (gear icon)
- Theme (light/dark)
- Backend configuration
- Export defaults
- Keyboard shortcuts
- Data directory paths

### Command Palette (Ctrl+K)
- Quick access to any action
- Fuzzy search
- Recent commands

## Technical Implementation

### Rust/egui Structure

```
cursor-studio-egui/
├── src/
│   ├── main.rs
│   ├── app.rs                 # Main app state
│   ├── theme.rs               # Shared theming
│   ├── widgets/               # Reusable widgets
│   │   ├── sidebar.rs
│   │   ├── status_bar.rs
│   │   ├── expandable_list.rs
│   │   └── dashboard_card.rs
│   ├── modules/
│   │   ├── mod.rs
│   │   ├── archive/           # Chat export
│   │   │   ├── mod.rs
│   │   │   ├── sidebar.rs
│   │   │   ├── chat_list.rs
│   │   │   ├── chat_viewer.rs
│   │   │   └── export_panel.rs
│   │   ├── index/             # Documentation
│   │   │   ├── mod.rs
│   │   │   ├── sidebar.rs
│   │   │   ├── add_form.rs
│   │   │   ├── source_list.rs
│   │   │   └── search_panel.rs
│   │   ├── sentinel/          # Security
│   │   │   ├── mod.rs
│   │   │   ├── sidebar.rs
│   │   │   ├── alert_feed.rs
│   │   │   └── quarantine.rs
│   │   ├── bridge/            # Sync
│   │   │   ├── mod.rs
│   │   │   ├── sidebar.rs
│   │   │   └── sync_panel.rs
│   │   └── forge/             # Data transform
│   │       ├── mod.rs
│   │       ├── sidebar.rs
│   │       ├── pipeline.rs
│   │       └── export.rs
│   └── backend/
│       ├── mod.rs
│       ├── client.rs          # HTTP client to cursor-docs
│       └── types.rs           # Shared types
```

### Backend Communication

cursor-studio communicates with cursor-docs via:

1. **HTTP API** - cursor-docs runs a local HTTP server
2. **SQLite Direct** - Read-only access to cursor-docs databases
3. **File Watching** - Monitor export directories

```rust
// Example backend client
pub struct CursorDocsClient {
    base_url: String,
    client: reqwest::Client,
}

impl CursorDocsClient {
    pub async fn list_sources(&self) -> Result<Vec<DocSource>> { ... }
    pub async fn add_source(&self, url: &str, opts: AddOpts) -> Result<DocSource> { ... }
    pub async fn search(&self, query: &str) -> Result<Vec<SearchResult>> { ... }
    pub async fn list_chats(&self) -> Result<Vec<Conversation>> { ... }
    pub async fn export_chat(&self, id: &str, format: ExportFormat) -> Result<String> { ... }
    pub async fn get_alerts(&self) -> Result<Vec<Alert>> { ... }
}
```

## Migration Path

### Phase 1: Index Module (Current Focus)
1. Create Index module in cursor-studio-egui
2. Add sidebar with doc source list
3. Add main panel with add form and search
4. Connect to cursor-docs HTTP API

### Phase 2: Archive Module
1. Port existing chat library to new structure
2. Add export options panel
3. Integrate markdown presets

### Phase 3: Sentinel Module
1. Add security dashboard
2. Alert feed with real-time updates
3. Quarantine review workflow

### Phase 4: Bridge Module
1. Sync status display
2. Manual sync triggers
3. Auto-sync configuration

### Phase 5: Forge Module
1. Pipeline builder UI
2. Transform configuration
3. Export to training formats

## Future: TUI Version

Once the egui version is stable, create a TUI version using:
- **ratatui** for terminal UI
- Same backend (cursor-docs)
- Keyboard-driven navigation
- Reduced feature set (power user focused)

```
┌─ Cursor Studio TUI ──────────────────────────────────────────┐
│ [1]Archive [2]Index [3]Sentinel [4]Bridge [5]Forge  [?]Help  │
├──────────────────────────────────────────────────────────────┤
│ ┌─ Sources ─────────────┐ ┌─ Details ──────────────────────┐ │
│ │ ✅ Elixir Docs    42  │ │ Name: Elixir Docs              │ │
│ │ ✅ NixOS Manual  156  │ │ URL: hexdocs.pm/elixir         │ │
│ │ ⏳ Rust Book      --  │ │ Status: indexed                │ │
│ │ ❌ Phoenix Guide  !!  │ │ Chunks: 42                     │ │
│ │                       │ │ Last indexed: 2h ago           │ │
│ │                       │ │                                │ │
│ │                       │ │ [r] Refresh  [d] Delete        │ │
│ └───────────────────────┘ └────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────┤
│ [a] Add URL  [s] Search  [q] Quit           CPU:2% RAM:45MB │
└──────────────────────────────────────────────────────────────┘
```

## Color Scheme

### Module Colors (for tabs/accents)
- Archive: Amber (#F59E0B)
- Index: Blue (#3B82F6)
- Sentinel: Red (#EF4444)
- Bridge: Purple (#8B5CF6)
- Forge: Orange (#F97316)

### Status Colors
- Success/Indexed: Green (#22C55E)
- Warning/Pending: Yellow (#EAB308)
- Error/Failed: Red (#EF4444)
- Info: Blue (#3B82F6)

## File Organization Summary

```
nixos-cursor/
├── cursor-studio-egui/         # GUI application
│   ├── src/modules/
│   │   ├── archive/            # 📚 Chat export
│   │   ├── index/              # 🗂️ Documentation
│   │   ├── sentinel/           # 🛡️ Security
│   │   ├── bridge/             # 🔗 Sync
│   │   └── forge/              # 🔥 Transform
│   └── ...
│
├── services/cursor-docs/       # Backend (Elixir)
│   ├── lib/cursor_docs/
│   │   ├── chat/               # Chat reading/export
│   │   ├── scraper/            # Web scraping
│   │   ├── storage/            # SQLite, vectors
│   │   ├── security/           # Quarantine, alerts
│   │   ├── cursor_integration/ # Cursor sync
│   │   └── embeddings/         # AI embeddings
│   └── ...
│
└── cursor-studio-tui/          # Future TUI version
    └── ...
```

