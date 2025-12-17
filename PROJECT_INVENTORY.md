# nixos-cursor Project Inventory

> **Generated**: 2025-12-17
> **Purpose**: Centralized inventory of all sub-projects, their status, and integration points

---

## 📦 Sub-Projects Overview

| Project | Language | Status | Purpose |
|---------|----------|--------|---------|
| **cursor-studio-egui** | Rust | ✅ Active | GUI companion app for Cursor |
| **services/cursor-docs** | Elixir | ✅ Active | Local documentation indexer |
| **cursor** | Nix | ✅ Active | Cursor AppImage packaging for NixOS |
| **cursor-studio** (legacy) | Rust | ⚠️ Deprecated | Original GPUI experiment |

---

## 🖥️ cursor-studio-egui (Rust)

**Location**: `cursor-studio-egui/`
**Status**: v0.2.1 - Active Development
**Framework**: egui

### Modules

| Module | Files | Purpose | Status |
|--------|-------|---------|--------|
| **modes/** | config.rs, injection.rs, ui.rs, mod.rs | Custom mode system replacing Cursor's removed feature | ✅ Complete |
| **docs/** | client.rs, models.rs, ui.rs | GUI for cursor-docs service | ✅ Working |
| **chat/** | 9 files | Conversation browser, P2P sync, CRDT | 🚧 Needs testing |
| **diagram/** | 7 files | D2 diagram renderer | ✅ Working |
| **sync/** | 9 files | Cursor DB sync daemon | 🚧 Partial |
| **ai_workspace/** | 6 files | Environment context, hints, plans | ✅ Working |
| **security.rs** | 1 file | NPM/sensitive data scanning | ✅ Working |

### Key Features
- ✅ VS Code-like layout
- ✅ Conversation browser with bookmarks
- ✅ Async imports
- ✅ Custom modes with tool locking
- ✅ Security scanning (NPM blocklist)
- ✅ D2 diagram viewing
- 🚧 P2P sync (code complete, needs testing)
- 🚧 cursor-docs integration (read-only)

### Built-in Modes
1. **Agent** - Full access, autonomous
2. **Code Review** - Read-only, no file writes
3. **Maxim** - Obsidian-specific agent rules
4. **Planning** - Think before acting

---

## 📚 services/cursor-docs (Elixir)

**Location**: `services/cursor-docs/`
**Status**: v0.3.0 - Active Development
**Framework**: Elixir/OTP + SQLite

### Modules

| Module | Files | Purpose | Status |
|--------|-------|---------|--------|
| **scraper/** | 8 files | Multi-page crawler, strategies | ✅ Working |
| **security/** | 2 files | Content validation, quarantine | ✅ Working |
| **storage/** | 4 files | SQLite + FTS5 | ✅ Working |
| **cursor_integration** | 1 file | Read Cursor's @docs config | ✅ Working |
| **ai/** | 6 files | Ollama integration | 🚧 Partial |
| **mcp/** | 1 file | MCP server | ❌ Placeholder |

### Crawling Strategies
1. **SinglePage** - Default single-page docs
2. **Frameset** - Javadoc classic framesets
3. **Sitemap** - XML sitemap discovery
4. **LinkFollow** - BFS link crawling

### CLI Commands
```bash
mix cursor_docs.setup    # Initialize database
mix cursor_docs.add      # Add documentation source
mix cursor_docs.list     # List indexed sources
mix cursor_docs.search   # Search indexed content
mix cursor_docs.sync     # Sync from Cursor's config
mix cursor_docs.import   # Import Cursor's failed docs
mix cursor_docs.alerts   # View security alerts
mix cursor_docs.quarantine # Manage quarantined content
```

---

## 🔄 Identified Duplicates/Overlaps

### 1. Cursor Database Reading

| Implementation | Location | Used For |
|----------------|----------|----------|
| Elixir | `cursor_integration.ex` | Reading @docs URLs |
| Rust | `sync/cursor_db.rs` | Reading conversations |

**Resolution**: Keep both - they read different data. Could share a spec for DB schema.

### 2. SQLite Storage

| Implementation | Location | Schema |
|----------------|----------|--------|
| Elixir | `storage/sqlite.ex` | doc_sources, doc_chunks, security_alerts |
| Rust | `docs/client.rs` | Reads from Elixir's DB |

**Resolution**: ✅ Already integrated - Rust reads from Elixir's DB.

### 3. Security Scanning

| Implementation | Location | Scans For |
|----------------|----------|-----------|
| Rust | `security.rs` | NPM packages, API keys, passwords |
| Elixir | `security/*.ex` | Hidden content, prompt injection |

**Resolution**: Keep both - complementary. Rust scans code, Elixir scans external docs.

---

## 🔗 Integration Points

### Current Integrations

```
┌─────────────────────────┐
│   cursor-studio-egui    │
│         (Rust)          │
│                         │
│ ┌─────────────────────┐ │
│ │   docs/client.rs    │─┼────► reads ────► SQLite DB
│ └─────────────────────┘ │                     │
│                         │                     │
│ ┌─────────────────────┐ │                     │
│ │   modes/injection   │─┼─► .cursorrules     │
│ └─────────────────────┘ │                     │
└─────────────────────────┘                     │
                                                │
┌─────────────────────────┐                     │
│   cursor-docs (Elixir)  │◄──── writes ────────┘
│                         │
│ ┌─────────────────────┐ │
│ │   scraper/          │─┼────► fetches URLs
│ └─────────────────────┘ │
│                         │
│ ┌─────────────────────┐ │
│ │ cursor_integration  │─┼────► reads Cursor's state.vscdb
│ └─────────────────────┘ │
└─────────────────────────┘
```

### Missing Integrations

1. **Cursor Studio → cursor-docs (write)**: GUI can't trigger scraping
2. **Mid-stream injection**: No way to inject context while AI is responding
3. **Background progress**: Crawler blocks CLI, no live updates
4. **Modes → Cursor IDE**: Generated rules not automatically applied

---

## 🎯 Priority Integration Tasks

### P0: Background Crawler with Live Updates

**Problem**: `mix cursor_docs.add` blocks while crawling
**Solution**: 
1. Add async task supervisor in Elixir
2. CLI shows live progress via Phoenix LiveView or simple polling
3. Continue accepting new commands while crawling

```elixir
# Proposed: services/cursor-docs/lib/cursor_docs/scraper/background.ex
defmodule CursorDocs.Scraper.Background do
  use GenServer
  
  def start_crawl(url, opts) do
    GenServer.cast(__MODULE__, {:start_crawl, url, opts})
  end
  
  def status do
    GenServer.call(__MODULE__, :status)
  end
end
```

### P1: Mid-Stream Context Injection

**Problem**: Can't add context while AI is responding
**Solution**: Named pipe or WebSocket between cursor-studio and Cursor

```
User typing in Cursor IDE
         │
         ▼
┌─────────────────────────────┐
│   cursor-studio (watching)  │
│                             │
│  Detects: AI needs docs     │
│                             │
│  Injects via:               │
│  1. Append to file that's   │
│     already @mentioned      │
│  2. Or: Cursor extension    │
│     API (if available)      │
└─────────────────────────────┘
```

**Approach A**: File-based injection (works today)
- cursor-studio writes to `.ai-workspace/injected-context.md`
- User includes `@injected-context.md` in chat
- cursor-studio updates file, AI sees on next read

**Approach B**: Cursor extension (requires investigation)
- Check if Cursor exposes extension API for context injection
- Would allow true mid-stream injection

### P2: Trigger Scraping from GUI

**Problem**: GUI can only read from cursor-docs, not write
**Solution**: Add HTTP API to cursor-docs

```elixir
# Proposed: services/cursor-docs/lib/cursor_docs/api/router.ex
scope "/api" do
  post "/sources", SourceController, :create
  post "/sources/:id/refresh", SourceController, :refresh
  delete "/sources/:id", SourceController, :delete
end
```

---

## 📋 Documentation Status

| Document | Location | Status |
|----------|----------|--------|
| Main README | `README.md` | 🟡 Needs update |
| Cursor Studio Roadmap | `cursor-studio-egui/ROADMAP.md` | ✅ Current |
| cursor-docs Troubleshooting | `docs/troubleshooting/DOCS_INDEXING_ISSUE.md` | ✅ Current |
| Project Inventory | `PROJECT_INVENTORY.md` | ✅ Current |

---

## 🗑️ Candidates for Cleanup

| Path | Reason | Action |
|------|--------|--------|
| `cursor-studio/` (not egui) | Legacy GPUI experiment | Archive or delete |
| `services/cursor-docs/lib/cursor_docs/storage/surrealdb.ex` | Replaced by SQLite | Keep as reference |
| `.ai-workspace/plans/*.json` | Outdated plans | Review and archive |

---

## 📊 Lines of Code

```
cursor-studio-egui/src/    ~15,000 lines Rust
services/cursor-docs/lib/  ~3,500 lines Elixir
cursor/                    ~500 lines Nix
```

---

## 🔮 Future Architecture

```
                    ┌─────────────────────────────────────┐
                    │         cursor-studio-egui          │
                    │              (Rust)                 │
                    │                                     │
                    │  ┌──────────┐  ┌─────────────────┐ │
                    │  │  Modes   │  │  Context Injector│ │
                    │  │  Panel   │  │  (mid-stream)   │ │
                    │  └──────────┘  └─────────────────┘ │
                    │  ┌──────────┐  ┌─────────────────┐ │
                    │  │  Docs    │  │  Security       │ │
                    │  │  Panel   │  │  Scanner        │ │
                    │  └──────────┘  └─────────────────┘ │
                    └───────┬──────────────┬─────────────┘
                            │              │
              HTTP API      │              │  File System
                            ▼              ▼
                    ┌──────────────┐  ┌─────────────────┐
                    │ cursor-docs  │  │  .cursorrules   │
                    │  (Elixir)    │  │  .ai-workspace/ │
                    │              │  │  injected.md    │
                    │  Background  │  └─────────────────┘
                    │  Crawler     │           │
                    └──────────────┘           │
                            │                 │
                            ▼                 ▼
                    ┌─────────────────────────────────────┐
                    │            Cursor IDE               │
                    │                                     │
                    │  Reads: .cursorrules (modes)        │
                    │  Reads: @injected.md (context)      │
                    │  Reads: @docs (from our index)      │
                    └─────────────────────────────────────┘
```

---

## 🚀 Next Steps

1. **Implement background crawler** in cursor-docs with live progress
2. **Add HTTP API** to cursor-docs for GUI integration
3. **Test file-based injection** for mid-stream context
4. **Archive legacy cursor-studio** (non-egui version)
5. **Update main README** with current project structure

