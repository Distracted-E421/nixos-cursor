## 2025-12-16 21:30:00 - [GUI]

**Description**: Major Index panel improvements for cursor-studio-egui

**Files**:
- cursor-studio-egui/src/docs/ui.rs (complete rewrite)
- cursor-studio-egui/src/docs/mod.rs
- cursor-studio-egui/src/main.rs
- cursor-studio-egui/src/docs/client.rs

**Changes**:

1. **UI Alignment Fixes**:
   - Grid-based layouts for consistent component alignment
   - Fixed-width stat cards for uniform sizing
   - Consistent spacing with standard margins (4.0, 8.0, 12.0)
   - Better visual hierarchy

2. **Functional URL Adding**:
   - Added actual subprocess call to `mix cursor_docs.add`
   - Background thread for async indexing
   - Default 1000 page limit (was 100)
   - Progress channel for live updates

3. **Tab Integration**:
   - New Tab::IndexedDoc variant for opening sources
   - Added DocsPanelEvent system for panel->main communication
   - View button opens source in editor area
   - Tab displays source chunks with content preview

4. **Live Indexing Progress**:
   - Added IndexingJob tracking
   - Progress bar showing page/max_pages
   - Fast refresh (2s) during indexing, slow (30s) otherwise
   - Status messages for started/complete/error states

5. **Source Details View**:
   - Click source to select, click View to open tab
   - Tab shows source metadata (URL, status, chunks count)
   - First 100 chunks displayed with content preview
   - Refresh and Delete action buttons

**Notes**: Requires cursor-docs service at ~/nixos-cursor/services/cursor-docs for URL adding

---

## 2025-12-16 20:50:00 - [FIX]

**Description**: Fixed vector storage modules and tested cursor-docs integration

**Files**:
- services/cursor-docs/lib/cursor_docs/storage/vector/surrealdb.ex
- services/cursor-docs/lib/cursor_docs/storage/vector/sqlite_vss.ex
- services/cursor-docs/lib/cursor_docs/storage/vector/disabled.ex
- cursor-studio-egui/src/docs/client.rs

**Changes**:

1. **Vector Storage Fixes**:
   - Added missing `start_link/1` and `child_spec/1` to all vector storage modules
   - Fixed GenServer supervision compatibility
   - SurrealDB, sqlite-vss, and Disabled backends now start correctly

2. **Rust Client Path Detection**:
   - Updated `default_db_path()` to try multiple locations:
     - cursor-docs-dev (development)
     - cursor-docs (production)
   - Auto-detects existing database

3. **Testing Results**:
   - cursor-docs application starts successfully
   - Search functionality working (FTS5)
   - Security quarantine pipeline flagging hidden content
   - 3 indexed sources: Phoenix Router, Phoenix Overview, Nushell Dataframes

**Commits**: dab29f9

---

## 2025-12-16 14:00:00 - [FEATURE]

**Description**: Comprehensive cursor-studio-egui update - naming, export, and polish

**Files**:
- cursor-studio-egui/src/main.rs (major updates)

**Changes**:

1. **Sub-App Naming Refactor**:
   - ChatLibrary → Archive 📚
   - Security → Sentinel 🛡️
   - Sync → Bridge 🔗
   - Index 📖 (unchanged)
   - Updated icons, labels, and hover text

2. **Export Dialog** (Archive panel):
   - Format dropdown with 6 options:
     - Markdown, Markdown (Obsidian)
     - JSON, JSON Lines
     - OpenAI JSONL, Alpaca JSON (training data)
   - Output directory input
   - Shows CLI command for batch exports

3. **ExportFormat Enum**:
   - New enum with label() and file_extension() methods
   - Supports both documentation and training data formats

**Commits**:
- f853f1e: refactor(cursor-studio): Rename sub-apps
- ac21d6f: feat(cursor-studio): Add export dialog

---

## 2025-12-16 12:30:00 - [FEATURE]

**Description**: Integrated Index (Documentation) panel into cursor-studio-egui + established Cursor Studio vision

**Files**: 
- cursor-studio-egui/src/docs/ (new - Index module)
  - mod.rs, client.rs, models.rs, ui.rs
- cursor-studio-egui/src/main.rs (Index panel integration)
- docs/CURSOR_STUDIO_ARCHITECTURE.md (new - project vision + sub-app naming)
- .cursor/rules/languages/nickel-config.mdc (new - Nickel config standards)

**Notes**: 

**Vision Statement:**
Cursor Studio is the "escape pod" from VS Code/Electron - a native, GPU-accelerated IDE that:
- Uses Cursor's AI as temporary brain while building independence
- Native egui UI, no Electron bloat
- Local compute first (Ollama, ONNX)
- Declarative config via Nickel
- Profile system (vim/emacs/vscode keybindings)
- NixOS-native

**Sub-App Naming:**
| Module | Name | Description |
|--------|------|-------------|
| Chat | Archive 📚 | Chat history export/import |
| Docs | Index 🗂️ | Web doc scraping/search |
| Security | Sentinel 🛡️ | Security alerts/quarantine |
| Sync | Bridge 🔗 | Cursor @docs sync |
| Transform | Forge 🔥 | Training data prep |

**New Language:** Nickel added to preferred config languages (typed, declarative, better than YAML)

---

## 2025-12-16 06:00:00 - [CONFIG]

**Description**: Created Nix flake for cursor-docs v0.3.0-pre with dev shells, NixOS module, and Home Manager module

**Files**: 
- services/cursor-docs/flake.nix (new - dev shells + modules)
- services/cursor-docs/flake.lock (new - generated)
- services/cursor-docs/docs/INSTALLATION.md (new - installation guide)
- services/cursor-docs/mix.exs (version 0.3.0-pre)
- services/cursor-docs/CHANGELOG.md (consolidated to 0.3.0-pre)

**Notes**: 

**Flake Features:**
- `nix develop` - Development shell with Elixir, SQLite, optional backends
- `nix develop .#full` - Full shell with all tools including ChromeDriver
- NixOS module: `services.cursor-docs.enable`, `services.cursor-docs.surrealdb.enable`
- Home Manager module: `programs.cursor-docs.enable`

**Pre-release Branch:**
To publish: `git checkout -b cursor-docs-0.3.0-pre && git push origin cursor-docs-0.3.0-pre`

**Usage from other flakes:**
```nix
cursor-docs = {
  url = "github:Distracted-E421/nixos-cursor?dir=services/cursor-docs&ref=cursor-docs-0.3.0-pre";
};
```

---

## 2025-12-16 05:30:00 - [SCRIPT]

**Description**: Full implementation of tiered vector storage architecture for cursor-docs v0.3.0-pre - sqlite-vss, SurrealDB, embedding generator, and hybrid search

**Files**: 
- services/cursor-docs/lib/cursor_docs/storage/vector.ex (new - vector storage behaviour)
- services/cursor-docs/lib/cursor_docs/storage/vector/disabled.ex (new - FTS5-only fallback)
- services/cursor-docs/lib/cursor_docs/storage/vector/sqlite_vss.ex (new - embedded vectors)
- services/cursor-docs/lib/cursor_docs/storage/vector/surrealdb.ex (new - server vectors)
- services/cursor-docs/lib/cursor_docs/embeddings/generator.ex (new - AI embedding orchestration)
- services/cursor-docs/lib/cursor_docs/search.ex (new - unified search interface)
- services/cursor-docs/lib/cursor_docs/storage/sqlite.ex (added get_chunks_for_source, get_chunk)
- services/cursor-docs/lib/cursor_docs/application.ex (updated - optional AI/vector services)
- services/cursor-docs/docs/NIXOS_SERVICE_CONFIGURATION.md (new - NixOS setup guide)
- services/cursor-docs/CHANGELOG.md (updated - v0.4.0)
- services/cursor-docs/mix.exs (version 0.4.0)

**Notes**: 

**Tiered Architecture:**
| Tier | Backend | Features | Use Case |
|------|---------|----------|----------|
| 1 | Disabled | FTS5 only | Zero setup, just works |
| 2 | sqlite-vss | Embedded vectors | Semantic search, no daemon |
| 3 | SurrealDB | Vectors + graphs | Power users, full pipeline |

**Key Features:**
- Graceful SurrealDB startup (Nice=19, IOSchedulingClass=idle, lazy connect)
- Auto-detection of best available backend
- Hybrid search combining semantic + keyword results
- Hardware-aware batch sizing
- NixOS systemd configuration examples

This captures users from zero-setup to power users building full data pipelines.

---

## 2025-12-16 04:30:00 - [SCRIPT]

**Description**: Designed and implemented pluggable AI provider architecture for cursor-docs v0.3.0 - hardware detection, model registry, and provider abstraction

**Files**: 
- services/cursor-docs/lib/cursor_docs/ai/provider.ex (new - provider behaviour)
- services/cursor-docs/lib/cursor_docs/ai/hardware.ex (new - hardware detection)
- services/cursor-docs/lib/cursor_docs/ai/model_registry.ex (new - verified models)
- services/cursor-docs/lib/cursor_docs/ai/ollama.ex (new - Ollama provider)
- services/cursor-docs/lib/cursor_docs/ai/local.ex (new - ONNX provider)
- services/cursor-docs/lib/cursor_docs/ai/disabled.ex (new - FTS5 fallback)
- services/cursor-docs/docs/AI_PROVIDER_ARCHITECTURE.md (new - design docs)
- services/cursor-docs/CHANGELOG.md (new - version history)
- services/cursor-docs/README.md (updated - AI provider section)
- services/cursor-docs/mix.exs (version 0.3.0)

**Notes**: Designed to be "useful without being a problem app" - no forced daemons, hardware-aware model selection, graceful FTS5 fallback. Hardware detection correctly identifies Obsidian's dual GPUs (RTX 2080 + Arc A770). Provider priority: Ollama → Local ONNX → Disabled. Model registry includes quality/speed benchmarks. Also addressed database architecture question - recommending sqlite-vss as default (embedded) with SurrealDB optional for power users.

---

## 2025-12-06 19:00:00 - [SCRIPT]

**Description**: Created Elixir sync daemon with OTP supervision, named pipes IPC, and full database integration

**Files**: 
- sync-daemon-elixir/ (new directory - complete Elixir project)
  - mix.exs - Project definition with deps
  - config/*.exs - Environment configs
  - lib/cursor_sync/application.ex - OTP supervisor
  - lib/cursor_sync/pipe_server.ex - Named pipe IPC
  - lib/cursor_sync/watcher.ex - File system watcher
  - lib/cursor_sync/sync_engine.ex - Core sync logic
  - lib/cursor_sync/database/cursor_reader.ex - Cursor DB reading
  - lib/cursor_sync/database/external_writer.ex - External DB writing
  - lib/cursor_sync/telemetry.ex - Metrics and monitoring
  - README.md - Full documentation

**Notes**: User decided on Elixir over Rust for daemon due to: multi-machine sync needs, hot code reloading desire, and fault tolerance requirements. Named pipes chosen for IPC (simpler than gRPC/sockets). Project includes full OTP supervision tree, telemetry integration, and JSON-based IPC protocol. Ready for `mix deps.get && iex -S mix` testing.

---

## 2025-12-06 18:00:00 - [SCRIPT]

**Description**: Added Rust sync daemon scaffold and comprehensive Rust vs Elixir language comparison research

**Files**: 
- docs/research/SYNC_DAEMON_LANGUAGE_COMPARISON.md (new - comprehensive comparison)
- cursor-studio-egui/src/sync/mod.rs (new - module structure)
- cursor-studio-egui/src/sync/config.rs (new - TOML config)
- cursor-studio-egui/src/sync/models.rs (new - data types)
- cursor-studio-egui/src/sync/daemon.rs (new - main daemon)
- cursor-studio-egui/src/sync/watcher.rs (new - file watcher stub)
- cursor-studio-egui/src/sync/cursor_db.rs (new - database reader stub)
- cursor-studio-egui/src/sync/external_db.rs (new - database writer stub)
- cursor-studio-egui/Cargo.toml (deps: parking_lot, toml)
- cursor-studio-egui/src/lib.rs (added sync module)

**Notes**: Research concluded Rust 6 vs Elixir 5 on key metrics. Rust chosen for v1.0 due to: direct cursor-studio integration (no IPC), rusqlite maturity, single binary deployment, existing Rust knowledge. Elixir wins on hot reloading and fault tolerance - consider for v2.0 if distributed sync needed. Sync daemon implements event-based architecture, config-driven behavior, and modular design that could be extracted to Elixir later if needed.

---

## 2025-12-06 16:30:00 - [SCRIPT]

**Description**: Implemented native D2 diagram viewer for cursor-studio egui with interactive rendering, VS Code theme integration, and pan/zoom support

**Files**: 
- cursor-studio-egui/src/diagram/mod.rs
- cursor-studio-egui/src/diagram/graph.rs
- cursor-studio-egui/src/diagram/parser.rs
- cursor-studio-egui/src/diagram/renderer.rs
- cursor-studio-egui/src/diagram/theme_mapper.rs
- cursor-studio-egui/examples/d2_viewer_demo.rs
- docs/diagrams/cursor-studio-demo.d2
- cursor-studio-egui/CHANGELOG.md
- cursor-studio-egui/src/lib.rs

**Notes**: Part of Data Pipeline Control objectives. D2 viewer renders diagrams natively in egui without requiring external D2 CLI for viewing. Supports all major D2 shapes (rectangle, cylinder, hexagon, diamond, etc.), edge arrows/labels, inline styles, and VS Code theme color mapping. Interactive features include pan (right-click drag), zoom (scroll wheel), node selection (click), and node dragging. Includes minimap and toolbar. Parser handles direction, title, containers, and style properties.

---

