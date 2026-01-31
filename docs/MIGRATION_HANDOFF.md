# nixos-cursor Migration Handoff Document

**Created**: January 31, 2026  
**Purpose**: Detailed instructions for agent to complete Continuum Studio migration  
**Priority**: High - Complete before starting new nixos-cursor features

## Executive Summary

This document provides step-by-step instructions for migrating code from `nixos-cursor` to the Continuum Studio ecosystem (`synapsix` + `continuum-studio`). The goal is to:

1. Preserve all valuable functionality
2. Consolidate code into appropriate repositories
3. Clean up nixos-cursor to be NixOS packaging only
4. Avoid losing any important features or history

## Migration Categories

### Category A: Direct Move (No Modifications Needed)

These can be moved with minimal changes (rename modules only):

| Component | Source | Destination | Rename |
|-----------|--------|-------------|--------|
| Security blocklists | `security/blocklists/` | `synapsix/priv/security/` | Keep names |
| Security tests | `security/tests/` | `synapsix/test/security/` | Keep names |
| D2 diagrams | `docs/diagrams/` | `continuum-studio/docs/diagrams/` | Keep names |

### Category B: Refactor Required

These need module renaming and import updates:

#### B1: cursor-docs → synapsix/lib/synapsix/docs/

**Source**: `services/cursor-docs/lib/cursor_docs/`

**Key modules to transfer**:
```
cursor_docs/
├── scraper/           → synapsix/lib/synapsix/docs/scraper/
│   ├── background.ex      - Background job processing
│   ├── crawler_strategy.ex - Strategy pattern for crawling
│   ├── extractor.ex       - HTML content extraction
│   ├── job_queue.ex       - Job queue management
│   ├── rate_limiter.ex    - Rate limiting
│   └── strategies/        - Crawling strategy implementations
├── storage/           → synapsix/lib/synapsix/docs/storage/
│   ├── sqlite.ex          - SQLite storage backend
│   ├── search.ex          - FTS5 full-text search
│   └── vector.ex          - Vector embeddings (optional)
├── security/          → synapsix/lib/synapsix/docs/security/
│   ├── alerts.ex          - Security alert system
│   └── quarantine.ex      - Quarantine management
├── search.ex          → synapsix/lib/synapsix/docs/search.ex
└── cli.ex             → synapsix/lib/mix/tasks/docs/
```

**Do NOT transfer** (deprecated or replaced):
- `ai/lnn/` - Experimental LNN, superseded by NeSy
- `storage/surrealdb.ex` - Replaced by SQLite
- `mcp/server.ex` - Placeholder, not implemented

**Rename pattern**:
```elixir
# Old
defmodule CursorDocs.Scraper.Background do
# New
defmodule Synapsix.Docs.Scraper.Background do
```

**Import updates needed**:
- Change all `alias CursorDocs.*` to `alias Synapsix.Docs.*`
- Update supervisor children in application.ex
- Update CLI task module names

#### B2: cursor-studio-egui → continuum-studio/ui/

**Source**: `cursor-studio-egui/src/`

**Full transfer** (~15,000 lines):
```
src/
├── main.rs            → Keep as main entry point
├── lib.rs             → Keep
├── diagram/           → Complete D2 renderer (7 files)
├── chat/              → Conversation browser (9 files)
├── docs/              → Docs panel UI (4 files)
├── modes/             → Custom modes (4 files)
├── sync/              → DB sync (9 files)
├── ai_workspace/      → Context/hints (6 files)
├── security.rs        → NPM scanner
└── theme*.rs          → Theming
```

**Cargo.toml changes**:
```toml
# Old
[package]
name = "cursor-studio"

# New
[package]
name = "continuum-studio-ui"
```

**Integration updates**:
- Update API endpoints to point to Synapsix
- Update WebSocket URLs
- Update any hardcoded paths

#### B3: cursor-proxy → synapsix/tools/proxy/

**Source**: `tools/cursor-proxy/`

**Transfer entire directory** with updates:
- Rename crate in Cargo.toml
- Update any cross-references to other nixos-cursor paths

### Category C: Archive (Historical Value)

Create `archive/` directory in nixos-cursor and move:

| Item | Reason | Archive Location |
|------|--------|------------------|
| `scripts/python/` | Superseded by Elixir/Nushell | `archive/scripts-python/` |
| `scripts/rust/` | Superseded by proper tools | `archive/scripts-rust/` |
| `tools/cursor-tui/` | Superseded by egui app | `archive/cursor-tui/` |
| `tools/cursor-agent-tui/` | Superseded by Synapsix harness | `archive/cursor-agent-tui/` |
| `tools/cursor-isolation/` | Never completed | `archive/cursor-isolation/` |
| `tools/desktop-automation/` | Experimental | `archive/desktop-automation/` |
| `sync-daemon-elixir/` | Reference for Synapsix sync | `archive/sync-daemon-elixir/` |

### Category D: Delete (No Value)

These can be deleted without archiving:

| Item | Reason |
|------|--------|
| `target/` directories | Build artifacts |
| `_build/` directories | Elixir build artifacts |
| `.elixir_ls/` | IDE cache |
| `deps/` | Dependencies (recreatable) |
| `node_modules/` | NPM deps (if any) |
| Temporary test files | `*.tmp`, `*.test.*` |

## Detailed Migration Steps

### Step 1: Create Archive Structure

```bash
cd /home/e421/nixos-cursor
mkdir -p archive/{scripts-python,scripts-rust,cursor-tui,cursor-agent-tui,cursor-isolation,desktop-automation,sync-daemon-elixir}
```

### Step 2: Archive Legacy Code

```bash
# Archive scripts
git mv scripts/python/ archive/scripts-python/
git mv scripts/rust/ archive/scripts-rust/

# Archive superseded tools
git mv tools/cursor-tui/ archive/cursor-tui/
git mv tools/cursor-agent-tui/ archive/cursor-agent-tui/
git mv tools/cursor-isolation/ archive/cursor-isolation/
git mv tools/desktop-automation/ archive/desktop-automation/

# Archive sync daemon (reference)
git mv sync-daemon-elixir/ archive/sync-daemon-elixir/

# Commit archive
git commit -m "archive: Move legacy code to archive/ for reference"
```

### Step 3: Transfer cursor-docs to Synapsix

```bash
# Create directory structure
cd /home/e421/synapsix
mkdir -p lib/synapsix/docs/{scraper/strategies,storage,security}
mkdir -p lib/mix/tasks/docs
mkdir -p priv/docs

# Copy source files (then rename modules)
cp -r /home/e421/nixos-cursor/services/cursor-docs/lib/cursor_docs/scraper/* lib/synapsix/docs/scraper/
cp -r /home/e421/nixos-cursor/services/cursor-docs/lib/cursor_docs/storage/sqlite.ex lib/synapsix/docs/storage/
cp -r /home/e421/nixos-cursor/services/cursor-docs/lib/cursor_docs/storage/search.ex lib/synapsix/docs/storage/
cp -r /home/e421/nixos-cursor/services/cursor-docs/lib/cursor_docs/security/* lib/synapsix/docs/security/
cp /home/e421/nixos-cursor/services/cursor-docs/lib/cursor_docs/search.ex lib/synapsix/docs/

# Update module names in all files
# Use sed or manual editing to change CursorDocs -> Synapsix.Docs
```

### Step 4: Transfer cursor-studio-egui to Continuum Studio

```bash
# Create directory structure
cd /home/e421/continuum-studio
mkdir -p ui/src

# Copy source
cp -r /home/e421/nixos-cursor/cursor-studio-egui/src/* ui/src/
cp /home/e421/nixos-cursor/cursor-studio-egui/Cargo.toml ui/

# Update Cargo.toml
# Change name = "cursor-studio" to name = "continuum-studio-ui"
```

### Step 5: Transfer cursor-proxy to Synapsix

```bash
cd /home/e421/synapsix
mkdir -p tools/proxy

# Copy proxy source
cp -r /home/e421/nixos-cursor/tools/cursor-proxy/* tools/proxy/

# Update Cargo.toml if needed
```

### Step 6: Transfer Security Assets

```bash
cd /home/e421/synapsix

# Copy blocklists
cp -r /home/e421/nixos-cursor/security/blocklists priv/security/

# Copy tests
cp -r /home/e421/nixos-cursor/security/tests test/security/
```

### Step 7: Clean Up nixos-cursor

After transfers are verified working:

```bash
cd /home/e421/nixos-cursor

# Remove transferred code
rm -rf services/cursor-docs/
rm -rf cursor-studio-egui/
rm -rf tools/cursor-proxy/
rm -rf security/blocklists/
rm -rf security/tests/

# Remove empty directories
rm -rf services/
rm -rf tools/cursor-dialog-daemon/  # Already in Synapsix
rm -rf scripts/elixir/  # Integrated into Synapsix
rm -rf scripts/nu/      # Integrated or archived

# Update flake.nix to remove non-packaging outputs
```

### Step 8: Update Documentation

In each repository:

1. **nixos-cursor**: Update README to focus on NixOS packaging only
2. **synapsix**: Add docs for new modules (docs/, proxy/)
3. **continuum-studio**: Add docs for UI components

### Step 9: Update Cross-References

Search and replace in all repos:
- `nixos-cursor/cursor-studio-egui` → `continuum-studio/ui`
- `nixos-cursor/services/cursor-docs` → `synapsix docs module`
- `nixos-cursor/tools/cursor-proxy` → `synapsix tools/proxy`

## Testing Checklist

After migration, verify:

- [ ] `synapsix/docs/` module compiles
- [ ] Documentation search works
- [ ] Scraper can fetch and index pages
- [ ] Security alerts still trigger
- [ ] `continuum-studio/ui/` builds with `cargo build`
- [ ] All UI panels render correctly
- [ ] D2 diagrams display
- [ ] Chat browser works
- [ ] `synapsix/tools/proxy/` builds
- [ ] Proxy can intercept traffic
- [ ] `nixos-cursor` still packages Cursor correctly
- [ ] Home-manager module works
- [ ] Flake builds all outputs

## Risk Mitigation

1. **Backup before migration**: `git stash` or branch all repos
2. **Incremental testing**: Test each step before proceeding
3. **Keep nixos-cursor functional**: Don't break packaging during migration
4. **Document any issues**: Add to this file if problems encountered

## Files to Reference

If you need to understand functionality before migrating:

| File | Purpose |
|------|---------|
| `services/cursor-docs/README.md` | cursor-docs usage |
| `cursor-studio-egui/ROADMAP.md` | Feature status |
| `tools/cursor-proxy/src/lib.rs` | Proxy architecture |
| `docs/CURSOR_STUDIO_ARCHITECTURE.md` | Overall design |

## Completion Criteria

Migration is complete when:

1. ✅ All Category A items moved
2. ✅ All Category B items refactored and working
3. ✅ All Category C items archived
4. ✅ All Category D items deleted
5. ✅ nixos-cursor only contains NixOS packaging
6. ✅ All tests pass in all repos
7. ✅ Documentation updated

## Post-Migration Tasks

After main migration:

1. Update GitHub workflows in all repos
2. Update Nix flakes to reference new locations
3. Update any external documentation
4. Notify any users of path changes
5. Consider deprecation notices in old locations

## Launching Cursor Through Continuum Studio

Once migration is complete, Cursor should be launched through Continuum Studio to get:

1. **NeSy Orchestrator integration** - Formal verification of all agent actions
2. **Synapsix harnesses** - Proper integration with other apps (Godot, Android Studio)
3. **Metrics dashboard** - Real-time observability of agent actions
4. **Security constraints** - SMT-verified action verification

### Launch Steps

1. **Start Synapsix services**:
   ```bash
   # Start the NeSy orchestrator (if not auto-started)
   cd ~/synapsix && iex -S mix
   
   # Or via systemd (if configured)
   systemctl --user start synapsix-nesy
   ```

2. **Start Continuum Studio UI**:
   ```bash
   cd ~/continuum-studio/ui && cargo run --release
   ```

3. **Register Cursor harness**:
   The harness will auto-register when Cursor connects via the dialog daemon.

4. **Start Cursor through harness**:
   ```bash
   # Via Continuum Studio UI - click "Launch Cursor"
   # Or via command:
   synapsix-harness launch cursor
   ```

### What This Enables

When Cursor is launched through Continuum Studio:

- **All LLM agent actions** are verified by NeSy before execution
- **Priority hierarchy** ensures NeSy can override LLM decisions
- **Security constraints** block dangerous operations (forbidden paths, commands)
- **Telemetry events** stream to the metrics dashboard
- **Audit logging** captures all actions for compliance

### Configuration

The harness uses configuration from:
- `~/.config/synapsix/harnesses/cursor.toml` - Cursor-specific settings
- `~/.config/synapsix/security.toml` - Security constraints
- `~/.config/synapsix/orchestrator.toml` - NeSy orchestrator settings

## Current Session Progress (Jan 31, 2026)

### Completed This Session

1. ✅ **OxiZ SMT Solver** - Pure Rust SMT solver integrated via Rustler NIF
2. ✅ **rustler_precompiled setup** - Cross-platform binary distribution
3. ✅ **Telemetry infrastructure** - Event emission, logging, metrics
4. ✅ **WebSocket streaming** - Real-time metrics to dashboard
5. ✅ **Native metrics UI skeleton** - egui-based dashboard structure
6. ✅ **NeSy Orchestrator** - GenServer for agent security management
7. ✅ **D2 workflow diagrams** - 12 diagrams (8 detailed + 4 simple)
8. ✅ **Archive setup** - 7 legacy components archived

### Remaining Migration Work

- [ ] Transfer cursor-docs to synapsix/lib/synapsix/docs/
- [ ] Transfer cursor-studio-egui to continuum-studio/ui/
- [ ] Transfer cursor-proxy to synapsix/tools/proxy/
- [ ] Transfer security assets to synapsix/priv/security/
- [ ] Clean up nixos-cursor (remove transferred code)
- [ ] Update cross-references between repos
- [ ] Update all documentation

### Agent Instructions

When resuming this migration:

1. Follow the steps in this document sequentially
2. Test each transfer before proceeding
3. Keep nixos-cursor packaging functional throughout
4. Update this document with any issues encountered
5. Mark checkboxes as completed
