## 2025-12-27 18:00:00 - [AI] Phase 3: Elixir LNN Port & Arc A770 Issues

**Description**: Implemented IBM LNN Elixir port for cursor-docs, discovered critical Arc A770 Vulkan issues

**Files Created**:

- `services/cursor-docs/lib/cursor_docs/ai/lnn.ex` - Main LNN module
- `services/cursor-docs/lib/cursor_docs/ai/lnn/model.ex` - LNN model container (GenServer)
- `services/cursor-docs/lib/cursor_docs/ai/lnn/formula.ex` - Base formula + Lukasiewicz bounds
- `services/cursor-docs/lib/cursor_docs/ai/lnn/connectives.ex` - And, Or, Not, Implies, Iff, Predicate, Proposition
- `services/cursor-docs/lib/cursor_docs/ai/lnn/graph.ex` - DAG for formula dependencies
- `services/cursor-docs/lib/cursor_docs/ai/lnn/python.ex` - Optional Python interop for training

**LNN Elixir Port Features**:

- ✅ Propositional logic (And, Or, Not, Implies, Iff)
- ✅ First-order predicates with groundings
- ✅ Upward inference (leaf to root)
- ✅ Belief bounds [L, U] ∈ [0,1]²
- ✅ Lukasiewicz semantics (differentiable t-norms)
- 🔄 Downward inference (modus ponens) - partial
- 🔄 Training via Python interop - scaffolded

**⚠️ Arc A770 Vulkan Critical Issue Discovered**:

- Models download and load successfully on Arc A770 (port 11435)
- Inference produces **gibberish output** (repetitive nonsense)
- Tested: qwen2.5:7b and qwen2.5:14b both fail
- Root cause: Vulkan compute shader compatibility with Intel Arc
- **Workaround**: Use RTX 2080 (port 11434) until fixed

**Recommended Solutions for Arc A770**:

1. llama.cpp with SYCL/Level Zero (better Intel support)
2. IPEX-LLM (Intel's optimized runtime)
3. CPU offload mode (`OLLAMA_NUM_GPU=0`)
4. Wait for Ollama Vulkan fixes

**Research Document Updated**:

- Added Section 6.5: Elixir LNN Port details
- Updated Section 6: Hardware with Arc A770 Vulkan issues
- Added llama.cpp distributed inference architecture
- Marked IBM LNN as selected solution

**Verified Working**:

- LNN formula calculations (implies, and, or, not bounds)
- Model knowledge base construction
- Graph traversal for inference
- Upward belief propagation

**Next Steps**:

- Implement full downward inference (modus ponens)
- Test llama.cpp with SYCL on Framework laptop
- Integrate LNN with neuro-symbolic pipeline
- Create cursor-docs documentation KB

---

## 2025-12-27 16:00:00 - [AI] Phase 2: Models & Distributed Architecture

**Description**: Expanded AI model inventory, documented distributed inference, added IBM LNN deep dive

**Models Added**:

- `qwen2.5:14b` (9.0GB) - Large reasoning model for Arc A770
- `nomic-embed-text` (274MB) - Embedding model for semantic search

**Research Added**:

- IBM LNN architecture deep dive (Section 9)
- llama.cpp RPC distributed inference (Section 10)
- Elixir co-routine implementation patterns (Section 11)
- Model inventory and GPU allocation strategy (Section 12)

**Application Changes**:

- Registered `CursorDocs.AI.Neurosymbolic.Orchestrator` in application supervisor
- Added `ModelSelector` module for task-based model selection

**Infrastructure Notes**:

- RTX 2080: qwen2.5:3b, qwen2.5:7b, qwen2.5-coder:7b, nomic-embed-text
- Arc A770: qwen2.5:14b (ready for large reasoning tasks)
- Network cap: 1Gbps (suitable for batch processing, not real-time distributed)

**Next Steps**:

- Configure Arc A770 Ollama with ONEAPI optimizations
- Test llama.cpp RPC across homelab machines
- Evaluate IBM LNN Python integration in Elixir via ports

---

## 2025-12-27 15:30:00 - [AI]

**Description**: Neuro-Symbolic AI Framework - Initial Implementation

**Files**:

- docs/research/NEUROSYMBOLIC_AI_FRAMEWORK.md (comprehensive research document)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic.ex (main module)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic/orchestrator.ex (co-routine orchestrator)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic/parser.ex (NL parser)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic/grounder.ex (symbol grounder)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic/reasoner.ex (logical reasoner)
- services/cursor-docs/lib/cursor_docs/ai/neurosymbolic/explainer.ex (explanation generator)

**New Capabilities**:

- Co-routine-based reasoning pipeline with YIELD/RESUME semantics
- LLM-powered natural language parsing (qwen2.5-coder:7b for code queries)
- Symbol grounding connecting NL to knowledge graph entities
- Hybrid reasoning (rule-based + LLM-guided inference)
- Multi-level explanation generation (brief/standard/detailed)
- Fast mode without LLM for quick heuristic reasoning

**Models Upgraded**:

- Downloaded qwen2.5-coder:7b (4.7GB) for code-focused parsing
- Existing: qwen2.5:7b, qwen2.5:3b for general reasoning

**Research Topics Documented**:

- Symbol Grounding Problem and LLM solutions
- IBM Logical Neural Networks (LNN)
- Stanford DSPy framework for programming LLMs
- Co-routine patterns for interruptible AI workflows
- Local training strategies for custom SLMs

**Hardware Utilization**:

- RTX 2080 (8GB): qwen2.5:7b, qwen2.5-coder:7b (NL interface, reasoning)
- Arc A770 (16GB): Available for larger models, embeddings

**Next Steps**:

- Test full pipeline with documentation queries
- Integrate with cursor-docs search
- Evaluate IBM LNN vs Clingo ASP for formal reasoning
- Create training data for custom grounding model

---

## 2025-12-19 11:45:00 - [SCRIPT]

**Description**: Cursor Isolation & Recovery Tools created after experimental work broke main Cursor

**Files**:

- tools/cursor-isolation/cursor-test (run Cursor with isolated user data)
- tools/cursor-isolation/cursor-backup (backup/restore Cursor config)
- tools/cursor-isolation/cursor-versions (manage multiple AppImage versions)
- tools/cursor-isolation/cursor-sandbox (full environment isolation)
- tools/cursor-isolation/sync-versions (sync from oslook/cursor-ai-downloads)
- tools/cursor-isolation/README.md (documentation)

**New Capabilities**:

- `cursor-test --env <name>` - Run isolated Cursor instances for safe testing
- `cursor-backup save/restore` - Snapshot and restore configuration
- `cursor-versions download/run <ver>` - Multiple version management
- Downloaded Cursor 2.2.36 with verified hash

**Verified Hashes**:

- Cursor-2.2.36-x86_64.AppImage: `b7a3c925c4e52d53dddcc7c911d31fb1bc1431e0c139f006662400ac6ac7ccba`

**Incident Triage**:
After proxy injection work broke the main Cursor (crashes, charging for no-output requests),
these tools ensure we can safely test experimental features without affecting production.

**Usage**:

```bash
# Safe testing workflow
cursor-backup quick              # Backup before experiment
cursor-test --env proxy-dev      # Test in isolation
cursor-test --reset              # Reset if broken
cursor-backup restore <name>     # Restore if needed
```

---

## 2025-12-19 07:30:00 - [UPDATE]

**Description**: Comprehensive cursor-proxy injection system and API analysis

**Files**:

- tools/cursor-proxy/src/injection.rs (new - request/response injection engine)
- tools/cursor-proxy/src/config.rs (added InjectionConfig)
- tools/cursor-proxy/src/main.rs (added inject CLI commands)
- tools/cursor-proxy/src/proxy.rs (integrated injection manager)
- tools/cursor-proxy/injection-rules.toml.example (new - example config)
- tools/cursor-agent-tui/test_endpoints.py (new - Python endpoint testing)
- tools/cursor-agent-tui/capture/quick-capture.sh (new - traffic capture)

**Injection System Features**:

- System prompt injection via protobuf modification
- X-Cursor-Client-Version header spoofing
- Context file injection
- Custom header injection
- CLI management: `cursor-proxy inject <enable|disable|status|prompt|version>`

**API Analysis Results**:

| Endpoint | Status | Notes |
|----------|--------|-------|
| WarmStreamUnifiedChatWithTools | ✅ 200 | Cache operation |
| AvailableModels | ✅ 200 | Returns 58 models |
| StreamUnifiedChat | ⚠️ DEPRECATED | Returns "outdated" message |
| StreamUnifiedChatWithTools | ❌ 464 | OUTDATED_CLIENT |
| StreamUnifiedChatWithToolsSSE | ❌ HANG | Connection timeout |

**Key Discovery**:
Cursor sends additional headers we weren't using:

- `x-cursor-checksum` - Likely integrity/version validation hash
- `x-cursor-config-version` - Feature flag configuration
- `x-cursor-timezone` - Timezone info

**Root Cause**:
Version validation is more than just the header - likely includes checksum
that incorporates client version + request body + installation ID.

**Next Steps**:

1. Update Cursor version via nixpkgs
2. Capture real traffic with SSLKEYLOGFILE
3. Reverse engineer checksum algorithm

---

## 2025-12-19 04:35:00 - [UPDATE]

**Description**: Enhanced cursor-agent-tui with protobuf support and comprehensive documentation

**Files**:

- tools/cursor-agent-tui/src/proto.rs (new - Protobuf message definitions)
- tools/cursor-agent-tui/src/api.rs (enhanced - Connect Protocol, better errors)
- tools/cursor-agent-tui/src/error.rs (added - ProtobufSchemaUnknown error)
- tools/cursor-agent-tui/README.md (new - comprehensive documentation)
- Cargo.toml (added prost for protobuf)

**Current Status**:

| Feature | Status |
|---------|--------|
| Auth extraction | ✅ Working |
| Model listing | ✅ Working |
| Agent models filter | ✅ Working |
| Config management | ✅ Working |
| Chat/Query | 🚧 Schema needed |

**Technical Discovery**:

- Cursor API uses Connect Protocol (gRPC-web) with binary protobuf
- `AvailableModels` accepts JSON (works!)
- `StreamUnifiedChatWithTools` requires protobuf (schema unknown)
- mitmproxy can't capture streaming gRPC for reverse engineering

**Next Steps**:

1. Capture protobuf traffic with Wireshark/Charles
2. Decode wire format to reconstruct message structure
3. Update proto.rs with correct schema
4. Enable chat functionality

---

## 2025-12-19 04:28:00 - [UPDATE]

**Description**: Enhanced cursor-agent-tui with working auth extraction, models command, and tests

**Files**:

- tools/cursor-agent-tui/src/auth.rs (fixed - correct SQLite key path)
- tools/cursor-agent-tui/src/api.rs (enhanced - Connect Protocol headers, ModelInfo struct)
- tools/cursor-agent-tui/src/main.rs (added - `models` command)
- tools/cursor-agent-tui/tests/auth_test.rs (new - auth extraction tests)
- tools/cursor-agent-tui/tests/api_test.rs (new - API integration tests)
- scripts/cleanup-cursor-db.sh (fixed - removed bc dependency)

**Fixes**:

1. Auth now correctly reads from `ItemTable` key `cursorAuth/accessToken`
2. Removed `bc` dependency from cleanup script (pure bash arithmetic)
3. Added proper Connect Protocol headers (X-Cursor-*, session IDs)

**New Features**:

1. `cursor-agent models` - List available AI models
2. `cursor-agent models --agent-only` - Show only agent-capable models  
3. Full model details including thinking support, context limits
4. 6 passing tests (3 auth + 3 API)

**DB Cleanup Results**:

- Before: 2.1GB (32833 bubbles, 7251 checkpoints)
- After: 968MB (removed checkpoints, ran VACUUM)
- Saved: ~1.1GB

---

## 2025-12-19 - [FEATURE]

**Description**: Created cursor-agent-tui - A lightweight TUI for Cursor AI without Electron bloat

**Files**:

- tools/cursor-agent-tui/ARCHITECTURE.md (new - comprehensive design document)
- tools/cursor-agent-tui/Cargo.toml (new - Rust dependencies)
- tools/cursor-agent-tui/src/main.rs (new - CLI entry point)
- tools/cursor-agent-tui/src/api.rs (new - Cursor API client)
- tools/cursor-agent-tui/src/auth.rs (new - Token extraction from Cursor)
- tools/cursor-agent-tui/src/config.rs (new - Configuration management)
- tools/cursor-agent-tui/src/context.rs (new - File context management)
- tools/cursor-agent-tui/src/tools.rs (new - Tool execution)
- tools/cursor-agent-tui/src/state.rs (new - Bounded state management)
- tools/cursor-agent-tui/src/app.rs (new - Application state)
- tools/cursor-agent-tui/src/tui.rs (new - Ratatui TUI interface)
- tools/cursor-agent-tui/src/error.rs (new - Error types)
- scripts/cleanup-cursor-db.sh (new - Database cleanup utility)

**Motivation**:

- Cursor's state.vscdb grew to 2.1GB causing severe slowdowns
- Electron/V8 GC pressure makes Cursor sluggish over time
- Need for lightweight, composable AI agent interface

**Features**:

1. **Direct API Access** - HTTPS to api2.cursor.sh without Electron IPC
2. **Token Extraction** - Can extract auth from Cursor's SQLite storage
3. **Bounded State** - Maximum 50MB state file (vs Cursor's 2GB+)
4. **Tool Execution** - Direct file/command operations
5. **TUI Interface** - Ratatui-based with vim-like keybindings
6. **Streaming** - SSE stream parsing for real-time responses

**Performance Targets**:

| Metric | Cursor IDE | cursor-agent-tui |
|--------|-----------|------------------|
| Memory (idle) | 500MB+ | <50MB |
| Memory (active) | 2GB+ | <200MB |
| Startup time | 5-10s | <1s |
| State file | 2GB+ | <50MB (hard limit) |

**Usage**:

```bash
# Start TUI
cursor-agent chat

# Single query (non-interactive)
cursor-agent query "Fix the bug in main.rs" --files main.rs

# Check auth
cursor-agent auth --test
```

**Notes**:

- Phase 1 implementation - core infrastructure working
- API protocol based on proxy captures
- State manager with automatic pruning prevents bloat
- Ready for further development of tool execution

---

## 2025-12-19 - [SCRIPT]

**Description**: Database cleanup script for Cursor's bloated state.vscdb

**Files**:

- scripts/cleanup-cursor-db.sh (new)

**Features**:

- Shows database statistics and table breakdown
- Creates automatic backups before cleanup
- Three cleanup modes:
  - `--safe`: Remove only agent checkpoints (~1GB savings)
  - `--moderate`: Also prune old conversations (keep 500)
  - `--aggressive`: Keep only 100 recent conversations
- Runs VACUUM to reclaim disk space

**Root Cause Found**:

- `cursorDiskKV` table: 2,096 MB
- `bubbleId` entries: 32,769 (788 MB) - conversation messages
- `checkpointId` entries: 7,227 (1,094 MB) - agent rollback state
- Some single bubbles were 118MB each!

**Usage**:

```bash
# Close Cursor first!
./scripts/cleanup-cursor-db.sh stats
./scripts/cleanup-cursor-db.sh clean --safe
```

---

## 2025-12-19 - [FIX]

**Description**: Critical memory leak fixes for cursor-proxy system - addresses RAM accumulation and sluggish behavior

**Files**:

- tools/cursor-proxy/src/pool.rs (memory leak fix - connection pool cleanup)
- tools/cursor-proxy/src/dashboard.rs (memory leak fix - in-flight request cleanup)
- tools/cursor-proxy/src/capture.rs (memory leak fix - bounded concurrent saves)
- tools/cursor-proxy/src/proxy.rs (periodic cleanup task)
- tools/cursor-proxy/src/main.rs (enable/disable commands)
- tools/cursor-studio (enable/disable support)

**Root Causes Fixed**:

1. **Connection Pool Memory Leak** (`pool.rs`):
   - DashMap entries were set to `None` but **never removed** from the map
   - Added periodic cleanup every 50 requests or when pool exceeds 100 entries
   - Added `last_used` tracking for idle connection cleanup
   - Pool now properly removes stale/unhealthy connections

2. **Dashboard State Accumulation** (`dashboard.rs`):
   - `in_flight` HashMap could grow unboundedly if events were missed
   - `Led::activity_count` only incremented, never reset (u32 overflow risk)
   - Added timeout-based cleanup of stale in-flight requests (5 min max)
   - Added MAX_IN_FLIGHT_ENTRIES limit (1000) with force-trim
   - LED activity counts now decay every 5 minutes

3. **Unbounded Capture Spawning** (`capture.rs`):
   - `tokio::spawn` was used without tracking completion
   - If disk I/O was slow, spawned tasks would accumulate in memory
   - Added Semaphore to limit to 10 concurrent save operations
   - Added `pending_saves` counter for monitoring
   - Implemented `cleanup_old_captures()` based on retention policy

4. **Missing Periodic Cleanup** (`proxy.rs`):
   - No background task was running cleanup
   - Added 60-second interval cleanup task that:
     - Cleans connection pool
     - Removes old capture files
   - Pool now cleared on `stop()` to release resources

5. **Proxy Disable Not Working** (`main.rs`):
   - `config.proxy.enabled` flag existed but was never checked
   - Added proper `enable`/`disable` CLI commands
   - Added `--force` flag to override disabled state
   - Disable now stops proxy and updates config

**New Commands**:

- `cursor-proxy enable` - Enable proxy in configuration
- `cursor-proxy disable` - Disable proxy (stops if running)
- `cursor-proxy start --force` - Start even if disabled in config
- `cursor-studio proxy enable` - Same via cursor-studio
- `cursor-studio proxy disable` - Same via cursor-studio

**Notes**:

- The "minimal cursor command" mentioned by user likely bypassed the proxy
- Reverting to generation 151 was necessary because the proxy was consuming RAM
- After these fixes, garbage collection should work properly
- Consider monitoring with `cursor-proxy status` after extended use

---

## 2025-12-18 17:35:00 - [FEATURE]

**Description**: Complete redesign of cursor-proxy v2 with hyper-based HTTP/1.1+HTTP/2 support and cursor-studio CLI integration

**Files**:

- tools/cursor-proxy/ARCHITECTURE.md (new - comprehensive design doc)
- tools/cursor-proxy/Cargo.toml (new - dependencies)
- tools/cursor-proxy/src/main.rs (new - CLI with subcommands)
- tools/cursor-proxy/src/error.rs (new - unified error handling)
- tools/cursor-proxy/src/config.rs (new - TOML configuration)
- tools/cursor-proxy/src/cert.rs (new - CA management)
- tools/cursor-proxy/src/iptables.rs (new - safe iptables management)
- tools/cursor-proxy/src/proxy.rs (new - hyper-based proxy server)
- tools/cursor-studio (new - unified launcher script)
- modules/home-manager/cursor-studio.nix (new - Home Manager module)

**Changes**:

1. **Proxy Core (Rust with hyper)**:
   - HTTP/1.1 + HTTP/2 support via hyper crate
   - ALPN negotiation for protocol detection
   - Dynamic certificate generation with caching
   - Native system CA trust for upstream connections
   - Graceful error handling with recovery suggestions

2. **CLI Interface**:
   - `cursor-proxy init` - Initialize CA and config
   - `cursor-proxy start [--transparent]` - Start proxy
   - `cursor-proxy stop` - Stop proxy
   - `cursor-proxy status` - Show status
   - `cursor-proxy trust-ca` - CA certificate management
   - `cursor-proxy iptables <add|remove|show|flush>` - Rule management
   - `cursor-proxy cleanup [--all]` - Clean up resources

3. **cursor-studio Integration**:
   - `cursor-studio` - Normal Cursor launch
   - `cursor-studio --proxy` - Launch with proxy enabled
   - `cursor-studio proxy <command>` - Proxy management
   - Automatic CA bundle creation
   - Background proxy startup

4. **Home Manager Module**:
   - `programs.cursor-studio.enable` - Install cursor-studio
   - `programs.cursor-studio.proxy.enable` - Enable proxy
   - Configuration options for port, CA, capture, iptables
   - Desktop entries for normal and proxy modes
   - Warning for system-wide CA trust setup

5. **Error Handling**:
   - Categorized errors with codes
   - Recovery suggestions for common issues
   - Graceful degradation (transparent → explicit proxy)

**Key Discovery**: Cursor uses HTTP/1.1 for some requests, not just HTTP/2.
Previous h2-only approach failed with "invalid preface" errors.
Solution: Use hyper which handles both protocols seamlessly.

**Notes**: Run `cursor-studio proxy init` to generate CA, then
`cursor-studio --proxy` to launch with interception enabled.

---

## 2025-12-17 14:25:00 - [TEST]

**Description**: Comprehensive test coverage for cursor-manager and Python MCP servers

**Files**:

- scripts/rust/cursor-manager/src/config.rs (8 tests added)
- scripts/rust/cursor-manager/src/version.rs (20 tests added)
- scripts/rust/cursor-manager/src/instance.rs (9 tests added)
- scripts/rust/cursor-manager/src/download.rs (8 tests added)
- scripts/python/tests/ (new directory)
- scripts/python/tests/conftest.py (shared fixtures)
- scripts/python/tests/test_context_inject.py (~25 tests)
- scripts/python/tests/test_docs_mcp.py (~20 tests)
- scripts/python/tests/test_sync_poc.py (~15 tests)
- scripts/python/pyproject.toml (pytest config)
- tools/proxy-test/tests/ (new directory)
- tools/proxy-test/tests/test_proxy_addon.py (~15 tests)
- tools/proxy-test/pyproject.toml (pytest config)
- tests/run-all-tests.nu (updated for pytest integration)
- docs/TEST_COVERAGE.md (new - comprehensive test docs)

**Changes**:

1. **Rust cursor-manager tests (45 total)**:
   - Config: serialization, get/set, persistence
   - Version: format_size, list/install/uninstall, cleanup
   - Instance: CRUD operations, lifecycle management
   - Download: URL generation, hash verification, cache usage

2. **Python MCP server tests (~60 total)**:
   - ContextStore: CRUD, search, expiration, persistence
   - DocsClient: chunking, FTS search, database ops
   - SyncPOC: database schema, message storage, foreign keys

3. **Proxy addon tests (~15 total)**:
   - Domain matching, SSE parsing, error tracking
   - Certificate pinning detection, streaming detection

4. **Infrastructure updates**:
   - Updated run-all-tests.nu to run cargo test and pytest
   - Created pyproject.toml for pytest configuration
   - Added shared test fixtures in conftest.py

**Notes**: All 45 Rust tests pass. Python tests require pytest installation.
Run: `cargo test -p cursor-manager` or `pytest scripts/python/tests/ -v`

---

## 2025-12-17 11:30:00 - [FEATURE]

**Description**: Background crawler + project inventory for cursor-docs

**Files**:

- services/cursor-docs/lib/cursor_docs/scraper/background.ex (new)
- services/cursor-docs/lib/cursor_docs/cli.ex (bg commands)
- services/cursor-docs/lib/cursor_docs/application.ex
- services/cursor-docs/mix.exs
- PROJECT_INVENTORY.md (new - comprehensive project status)

**Changes**:

1. **Background Crawler**:
   - Non-blocking crawl jobs via `mix cursor_docs.bg URL`
   - Up to 3 concurrent jobs
   - Live progress tracking: `mix cursor_docs.bg watch`
   - Job management: `mix cursor_docs.bg status`, `jobs`, `cancel`
   - Task-based async with proper cleanup

2. **Project Inventory**:
   - Full audit of cursor-studio-egui (Rust) and cursor-docs (Elixir)
   - Identified duplicates: Cursor DB reading (both), SQLite storage (shared), Security (complementary)
   - Integration points documented
   - Future architecture diagram

**Usage**:

```bash
# Start background crawl
mix cursor_docs.bg https://docs.example.com --name "Example"

# Watch progress  
mix cursor_docs.bg watch

# List all jobs
mix cursor_docs.bg jobs
```

**Notes**: Jobs don't persist across `mix` restarts - designed for daemon mode.

---

## 2025-12-17 10:45:00 - [FEATURE]

**Description**: Multi-page crawler strategies + security persistence for cursor-docs

**Files**:

- services/cursor-docs/lib/cursor_docs/scraper/crawler_strategy.ex (new)
- services/cursor-docs/lib/cursor_docs/scraper/strategies/*.ex (new - 4 strategies)
- services/cursor-docs/lib/cursor_docs/storage/sqlite.ex (security tables + APIs)
- services/cursor-docs/lib/cursor_docs/scraper.ex (strategy integration)
- .ai-workspace/plans/cursor-docs-v0.4-roadmap.json (new)

**Changes**:

1. **Multi-Page Crawling Strategies**:
   - `SinglePage` - Default single-page scraping
   - `Frameset` - Javadoc classic (<frameset>) support
   - `Sitemap` - XML sitemap.xml discovery
   - `LinkFollow` - BFS link crawling (depth-limited)
   - Auto-detection based on page content

2. **Security Alert Persistence**:
   - New `security_alerts` SQLite table
   - New `quarantine_items` SQLite table
   - Full CRUD API for alerts (store, resolve, stats)
   - Quarantine review workflow (approve/reject/keep_flagged)

3. **Scraper Updates**:
   - Strategy auto-detection on add/refresh
   - Multi-page batch processing
   - Simplified content page scraping for discovered URLs

**Testing**:

```bash
# Ghidra found 590 initial links (but crawling is slow)
mix cursor_docs.add "https://ghidra.re/ghidra_docs/api/" --name "Ghidra-API" --max-pages 20

# Verify security tables
sqlite3 ~/.local/share/cursor-docs-dev/cursor_docs.db ".tables"
```

**Notes**: Large API docs like Ghidra (590+ pages) need parallelism or async processing.

---

## 2025-12-17 10:20:00 - [FEATURE]

**Description**: Successfully indexed Cursor's failed docs locally via cursor-docs service

**Files**:

- services/cursor-docs/lib/cursor_docs/cli.ex (derive_name_from_url fix)
- services/cursor-docs/lib/cursor_docs/storage/sqlite.ex (handle_call grouping fix)

**Changes**:

1. **Imported Failed Cursor Docs**:
   - ✅ nixidy: 213 chunks (raw.githubusercontent.com)
   - ✅ nixos-cursor: 208 chunks (raw.githubusercontent.com)
   - ✅ Zed-GPUI: 206 chunks (raw.githubusercontent.com)
   - ❌ Ghidra-API: Javadoc frameset (needs multi-page crawler)

2. **CLI Bug Fixes**:
   - Fixed `derive_name_from_url/1` to handle nil hosts from URI.parse
   - Now gracefully extracts name from path when host is nil
   - Correct usage: `mix cursor_docs.add URL --name NAME`

3. **Compiler Warning Fix**:
   - Reorganized handle_call/3 clauses to be grouped together
   - Moved `get_source_url/2` private helper after terminate/2
   - Clean compile with `--warnings-as-errors`

**Total Indexed**: 6 sources, 1336 chunks

**Testing**:

```bash
mix cursor_docs.add "https://raw.githubusercontent.com/.../README.md" --name "project"
mix cursor_docs.search "NixOS cursor module"
mix cursor_docs.status
```

**Notes**: GitHub blob URLs trigger login wall detection. Use raw.githubusercontent.com URLs instead.

---

## 2025-12-16 23:30:00 - [FIX]

**Description**: Fixed cursor-studio-dev alias for Wayland/OpenGL context creation

**Files**:

- nixos/modules/shell/homelab-aliases.nix
- cursor-studio-egui/src/main.rs

**Changes**:

1. **OpenGL/EGL Library Fix**:
   - Added libGL, mesa, egl-wayland to LD_LIBRARY_PATH
   - Fixed `NoGlutinConfigs` error during startup
   - Updated from deprecated `mesa.drivers` to `mesa`

2. **New Aliases**:
   - `cursor-studio-dev` - Full LD_LIBRARY_PATH approach
   - `cursor-studio-wrapped` - Simpler nix-shell wrapper

3. **UI Consistency Applied**:
   - Sentinel panel: reorganized with card_frame helpers
   - Bridge panel: unified spacing constants
   - Forge panel: used warning_card_frame for Coming Soon

**Testing**:

```bash
# After rebuilding NixOS:
cursor-studio-dev  # Now works with full Wayland/GL support
```

---

## 2025-12-16 22:15:00 - [FEATURE]

**Description**: Real-time progress tracking and UI consistency improvements

**Files**:

- services/cursor-docs/lib/cursor_docs/progress.ex (new)
- services/cursor-docs/lib/cursor_docs/cli.ex
- cursor-studio-egui/src/docs/ui.rs
- cursor-studio-egui/src/main.rs

**Changes**:

1. **Structured Progress Output (cursor-docs)**:
   - New `CursorDocs.Progress` module for JSON progress events
   - Format: `PROGRESS:{"type":"...", "data":{...}}`
   - Event types: `started`, `page`, `complete`, `error`, `security`
   - CLI now emits progress during indexing

2. **Real-time Progress Parsing (GUI)**:
   - Switched from `cmd.output()` to `cmd.spawn()` + stdout piping
   - Live parsing of `PROGRESS:` JSON lines via `BufReader`
   - Backward compatible with old "Chunks: N" format

3. **Delete Functionality**:
   - Delete button with confirmation dialog
   - Direct SQL delete fallback via `DocsClient::delete_source()`
   - `pending_delete` state for confirmation workflow

4. **UI Consistency Framework**:
   - Added spacing constants: `PANEL_PADDING`, `SECTION_SPACING`, etc.
   - Panel layout helpers: `panel_header()`, `stat_card()`, `card_frame()`
   - Ready for uniform application across all panels

5. **Alias Fixes (homelab)**:
   - `cursor-studio-dev` now sets LD_LIBRARY_PATH for Wayland
   - `rebuild-cursor-dev` fixed pipe syntax for nom
   - Added `cursor-studio-shell` alias for nix-shell approach

---

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

## 2025-12-17 22:35:00 - [SCRIPT]

**Description**: Built comprehensive Cursor API payload analysis tooling and Rust-based filter

**Files**:

- `tools/proxy-test/payload-filter/` (new Rust crate)
- `tools/proxy-test/analyze_payloads.py`
- `tools/proxy-test/decode_protobuf.py`
- `tools/proxy-test/SCHEMA_RECONSTRUCTION.md`
- `tools/proxy-test/FINDINGS.md`

**Notes**:

- Created Rust payload-filter tool that loads 29,864 payloads in 583ms and analyzes in 22ms
- Discovered only 140 unique payloads out of 29,864 (excellent deduplication)
- Found PotentiallyGenerateMemory endpoint contains 1.7MB full conversation context
- Reconstructed Protobuf schemas for all high-priority endpoints
- 69% of traffic is noise (analytics/telemetry) - can be filtered
- ChatService/StreamUnifiedChatWithTools not captured due to streaming issues

---

## 2025-12-17 23:35:00 - [SCRIPT]

**Description**: Created Rust transparent proxy skeleton and deep analyzed PotentiallyGenerateMemory

**Files**:

- `tools/proxy-test/cursor-proxy/` (new Rust crate)
- `tools/proxy-test/MEMORY_PAYLOAD_SCHEMA.md`
- `tools/proxy-test/decode_memory_payload.py`
- `tools/proxy-test/cp` (symlink to cursor-proxy)

**Notes**:

- Rust proxy starts and accepts connections on port 8443
- CA certificate generation working (~/.cursor-proxy/)
- PotentiallyGenerateMemory contains 1.65MB of full conversation context
- Identified 293 unique strings including full file contents, tool calls, terminal output
- Documented complete message schema with 20+ field types
- Key discovery: context injection can modify field 3 (files) or synthetic turns

---

## 2025-12-17 23:50:00 - [SCRIPT]

**Description**: Built complete HTTP/2 streaming proxy with h2 crate

**Files**:

- `tools/proxy-test/cursor-proxy/src/main.rs` - Full HTTP/2 proxy implementation
- `tools/proxy-test/cursor-with-proxy.sh` - Helper script for proxy + iptables
- `tools/proxy-test/rust-captures/` - Capture output directory

**Notes**:

- Proxy successfully handles HTTP/2 connections via h2 crate
- Dynamic certificate generation working (per-domain certs signed by CA)
- iptables integration for transparent proxying
- Stream capture to disk implemented
- TLS handshakes fail because Cursor doesn't trust our CA (expected)
- Next step: Trust CA via NixOS config or NODE_EXTRA_CA_CERTS

---

## 2025-12-17 21:10:00 - [CONFIG]

**Description**: Enhanced Cursor launcher with combined CA bundle for proxy interception

**Files**:

- `~/.local/bin/cursor-with-ca` - Updated wrapper with combined CA bundle
- `~/.cursor-proxy/combined-ca-bundle.pem` - System CAs + Proxy CA bundle
- `~/.local/share/applications/cursor.desktop` - Desktop entry (already pointed to wrapper)

**Notes**:

- NODE_EXTRA_CA_CERTS now points to combined bundle (system + proxy CAs)
- Bundle auto-regenerates when system CAs or proxy CA change
- Also sets SSL_CERT_FILE and REQUESTS_CA_BUNDLE for other tools
- Desktop entry already configured to use wrapper
- Cursor launched from desktop/menu will automatically trust proxy CA

---

## 2025-12-18 18:20:00 - [SCRIPT]

**Description**: Cursor Proxy v3 - DNS-based interception mode (major redesign)

**Files**:

- `tools/cursor-proxy/` - Core proxy with external DNS resolution
- `tools/cursor-proxy/ARCHITECTURE_V3.md` - New architecture documentation
- `tools/cursor-proxy/src/dns.rs` - External DNS resolver (bypasses /etc/hosts)
- `modules/nixos/cursor-proxy.nix` - NixOS service module
- `tools/cursor-studio` - Updated with --dns-mode support

**Notes**:

- DNS-based mode solves the DNS rotation issue that caused agent hangs
- Uses hickory-resolver to bypass /etc/hosts and resolve real AWS IPs
- Much more reliable than iptables-based approach
- Requires /etc/hosts entry: `127.0.0.1 api2.cursor.sh`
- NixOS module provides declarative service configuration
- CAP_NET_BIND_SERVICE allows port 443 binding without root

---

## 2025-12-18 19:52:00 - [FIX]

**Description**: Fixed Cursor Proxy HTTP/2 upstream connection bug

**Files**:

- `tools/cursor-proxy/src/proxy.rs` - Changed upstream connection from HTTP/1.1 to HTTP/2
- `tools/cursor-proxy/test-dns-mode.sh` - Added comprehensive test script

**Notes**:

- Root cause: Proxy was using `http1::handshake` but Cursor API requires HTTP/2
- Fixed by changing to `http2::handshake` with TokioExecutor
- Also fixed version header from HTTP_11 to HTTP_2
- All curl tests now pass (basic, OPTIONS, POST)
- CA sync between user/root required when running with sudo

---

## 2025-12-18 20:14:00 - [FIX]

**Description**: Fixed streaming response bug - proxy no longer blocks on collect()

**Files**:

- `tools/cursor-proxy/src/proxy.rs` - Changed response handling from `body.collect().await.to_bytes()` to direct stream pass-through

**Notes**:

- Root cause: `collect().await` blocks until entire response body is received
- For streaming AI responses (StreamChat), this would wait forever
- Fix passes the body stream directly through without buffering
- Time to first byte now 0.28s (was: timeout)

---

## 2025-12-18 20:35:00 - [FIX]

**Description**: Added retry logic to reduce 502 Bad Gateway errors

**Files**:

- `tools/cursor-proxy/src/proxy.rs` - Added `try_forward_to_upstream` with retry logic

**Notes**:

- Added 1 retry on connection failure (100ms delay between attempts)
- Added 10-second timeout on TCP connection
- Better error messages for debugging
- Root cause: Creating new connection per request can fail under load
- TODO: Implement proper HTTP/2 connection pooling for long-term fix

---

## 2025-12-18 22:45:00 - [SCRIPT]

**Description**: Added LED-style real-time dashboard for cursor-proxy

**Files**:

- `tools/cursor-proxy/src/events.rs` - Event broadcast system with tokio::broadcast
- `tools/cursor-proxy/src/dashboard.rs` - TUI dashboard with LED indicators
- `tools/cursor-proxy/src/dashboard_egui.rs` - egui widget for cursor-studio integration
- `tools/cursor-proxy/src/ipc.rs` - Unix socket IPC for dashboard connections
- `tools/cursor-proxy/src/lib.rs` - Library exports for cursor-studio
- `tools/cursor-proxy/src/proxy.rs` - Event emission on requests

**Notes**:

- Architecture: tokio::broadcast for zero-copy multi-consumer event distribution
- TUI Features: LED decay animations, service categories, latency percentiles (p50/p99)
- Metrics: Bytes in/out, active streaming count, pool connections
- IPC: Dashboard connects via Unix socket (no performance impact when disconnected)
- egui: Optional feature flag `--features egui` for cursor-studio integration
- Demo mode available when proxy not running

---

## 2025-12-18 23:35:00 - [SCRIPT]

**Description**: Enhanced cursor-proxy dashboard with theme-aware colors and advanced metrics

**Files**:

- `tools/cursor-proxy/src/dashboard.rs` - ANSI 16-color palette for terminal theme compatibility
- `tools/cursor-proxy/src/dashboard_egui.rs` - Light/dark theme toggle
- `tools/cursor-proxy/src/events.rs` - AgentActivity event type for tool call monitoring

**New Features**:

- **Theme-aware colors**: Uses ANSI 16-color palette that respects terminal themes
- **Request queue**: Per-category in-flight request counts with activity bars
- **Error breakdown**: Categorized errors (Timeout, Upstream, TLS, Network, Protocol)
- **Rate tracker**: Live requests/second metric
- **Hang detection**: Warns when requests exceed 5s (yellow) or 30s (red)
- **Agent monitoring**: Thinking state, current tool, total tool calls
- **Latency percentiles**: p50, p99, average with running window
- **Traffic counters**: Bytes in/out with auto-formatting (B/K/M/G)

**Notes**:

- ANSI 16-color ensures colors adapt to user's terminal color scheme
- Agent state shows during streaming to track AI thinking/tool execution
- egui version has matching features with light/dark theme toggle

---

## 2025-12-19 05:03:00 - [SCRIPT]

**Description**: Reverse-engineered Cursor API protobuf schema from bundled JavaScript

**Files**:

- `tools/cursor-agent-tui/proto/aiserver.proto` - Complete protobuf schema (2,129 types)
- `tools/cursor-agent-tui/capture/PROTO_SCHEMA_ANALYSIS.md` - Discovery documentation
- `tools/cursor-agent-tui/capture/proto-types.txt` - All discovered type names
- `tools/cursor-agent-tui/capture/restart-capture.sh` - Traffic capture script (SSL didn't work for API)
- `tools/cursor-agent-tui/README.md` - Updated with schema status

**Discovery Method**:

- Analyzed `cursor-always-local` extension's bundled JS code
- Extracted protobuf-es type definitions using grep/sed
- Found field numbers, types, and nesting structure
- SSL key logging didn't work for api2.cursor.sh (uses separate TLS implementation)

**Key Findings**:

- **2,129 protobuf types** in `aiserver.v1` namespace
- **ChatService** endpoints: `StreamUnifiedChatWithTools`, `StreamUnifiedChatWithToolsSSE`
- **StreamUnifiedChatRequestWithTools** structure:
  - Field 1: `stream_unified_chat_request` (the main request)
  - Field 2: `client_side_tool_v2_result` (tool execution results)
- **StreamUnifiedChatResponseWithTools** structure:
  - Field 1: `client_side_tool_v2_call` (tool calls from server)
  - Field 2: `stream_unified_chat_response` (text response)
  - Fields 3-7: Summary, rules, tracing context, event ID
- **ConversationMessage** has 13+ fields including bubble_id, type enum, code chunks

**Notes**:

- This unblocks the TUI agent chat implementation
- Next step: Generate Rust code with prost-build and implement encoding
- SSL key logging only captured metrics/telemetry traffic, not API calls
- API uses Connect Protocol v1 with binary protobuf, not JSON

---

## 2025-12-19 06:30:00 - [SCRIPT]

**Description**: cursor-agent-tui - significant debugging progress on chat endpoint

**Progress Made**:

- Confirmed protobuf encoding is correct (WarmStreamUnifiedChatWithTools accepts it)
- Identified version issue: Cursor 2.0.77 is too old for StreamUnifiedChatWithTools
- Added proto_test binary for testing encoded requests
- Created STATUS.md documenting current blockers

**Endpoint Status**:

- WarmStreamUnifiedChatWithTools: ✅ Works
- StreamUnifiedChatWithTools: ❌ OUTDATED_CLIENT error
- StreamUnifiedChatWithToolsSSE: ⏳ Hangs (needs investigation)
- AvailableModels: ✅ Works (58 models returned)

**Files**:

- tools/cursor-agent-tui/STATUS.md
- tools/cursor-agent-tui/src/bin/proto_test.rs
- tools/cursor-agent-tui/proto/test_data.json

**Notes**: Next step is either updating Cursor to newer version or finding the correct version header format. The proto schema reverse-engineering is complete - the blocker is purely server-side version validation.

---

## 2025-12-19 07:15:00 - [SCRIPT]

**Description**: cursor-proxy injection system implemented

**Features Added**:

- System prompt injection into chat requests
- Version spoofing via X-Cursor-Client-Version header
- Context file injection support
- Header override capability
- CLI commands: inject enable/disable/status/prompt/version/add-context

**Protobuf Wire Format Support**:

- Manual varint encoding/decoding
- ConversationMessage encoding
- Request body modification for chat endpoints
- Connect protocol framing preserved

**Files**:

- tools/cursor-proxy/src/injection.rs (new)
- tools/cursor-proxy/src/config.rs (updated with InjectionConfigFile)
- tools/cursor-proxy/src/proxy.rs (integrated injection engine)
- tools/cursor-proxy/src/main.rs (CLI commands)
- tools/cursor-proxy/injection-rules.toml.example
- tools/cursor-proxy/test-capture.sh

**Notes**:

- Version spoofing tested but all versions return OUTDATED_CLIENT
- Server appears to check request format, not just headers
- Ready for traffic capture testing to reverse-engineer exact format

---

## 2025-12-27 17:22:00 - [AI]

**Description**: llama.cpp SYCL backend research + Intel GPU module enhancement + Neuro-symbolic documentation update

**Arc A770 SYCL Findings**:

- llama.cpp SYCL backend officially verified for Arc A770 (~55 tokens/s)
- Ollama Vulkan backend produces gibberish (Intel shader compatibility issue)
- Solution: Build llama.cpp with SYCL backend using Intel oneAPI

**NixOS Configuration Updates**:

- Enhanced gpu-intel.nix module with Level-Zero and AdaptiveCpp (SYCL) support
- Added enableSycl option for AI workloads
- Added ACPP_TARGETS environment variable for backend discovery
- Verified dry-build succeeds (11m46s evaluation)

**Research Documentation**:

- Updated NEUROSYMBOLIC_AI_FRAMEWORK.md with llama.cpp SYCL findings
- Documented Arc A770 Vulkan issues and workarounds
- Added build instructions for llama.cpp with SYCL on NixOS
- Added performance comparison table (SYCL vs Vulkan vs OpenCL)
- Created roadmap for immediate, short-term, and medium-term tasks

**Files**:

- /home/e421/homelab/nixos/modules/hardware/gpu-intel.nix (enhanced)
- /home/e421/nixos-cursor/docs/research/NEUROSYMBOLIC_AI_FRAMEWORK.md (updated)
- /home/e421/llama.cpp (cloned for SYCL build)

**Notes**:

- Next steps: Install Intel oneAPI toolkit, build llama.cpp with SYCL
- Consider Docker container approach for cleanest isolation
- RTX 2080 remains reliable for Ollama CUDA inference

---
