# nixos-cursor → Continuum Studio Migration Plan

**Created**: January 31, 2026  
**Status**: Planning  
**Goal**: Consolidate cursor tooling into Continuum Studio ecosystem

## Overview

This document outlines the migration strategy for moving relevant components from the `nixos-cursor` repository to the Continuum Studio ecosystem (Synapsix + Continuum Studio proper).

## Repository Roles After Migration

| Repository | Role |
|------------|------|
| **synapsix** | Backend services (Elixir), NIFs, harness orchestration |
| **continuum-studio** | Frontend/UI (native egui + mobile), diagram rendering |
| **nixos-cursor** | NixOS packaging ONLY (cursor module, home-manager) |

## Migration Assessment

### 🟢 Transfer to Synapsix (Elixir Backend)

| Component | Location | Destination | Notes |
|-----------|----------|-------------|-------|
| **cursor-docs** | `services/cursor-docs/` | `synapsix/lib/synapsix/docs/` | Documentation indexer, scraper, FTS |
| **version-registry** | `services/version-registry/` | `synapsix/lib/synapsix/versions/` | Cursor version tracking |
| **sync-daemon-elixir** | `sync-daemon-elixir/` | `synapsix/lib/synapsix/sync/` | Database sync service |
| **Elixir scripts** | `scripts/elixir/` | Integrate into Synapsix mix tasks | CLI tools |

**Rationale**: These are all Elixir services that belong in the Synapsix umbrella.

### 🟢 Transfer to Continuum Studio (Native UI)

| Component | Location | Destination | Notes |
|-----------|----------|-------------|-------|
| **cursor-studio-egui** | `cursor-studio-egui/` | `continuum-studio/ui/` | Already ~15k lines Rust egui |
| **D2 diagram renderer** | `cursor-studio-egui/src/diagram/` | `continuum-studio/ui/diagram/` | Interactive diagrams |
| **conversation browser** | `cursor-studio-egui/src/chat/` | `continuum-studio/ui/chat/` | Chat history UI |
| **security scanner** | `cursor-studio-egui/src/security.rs` | `continuum-studio/ui/security/` | NPM blocklist UI |
| **modes UI** | `cursor-studio-egui/src/modes/` | `continuum-studio/ui/modes/` | Custom mode editor |

**Rationale**: These form the native desktop UI for the Continuum Studio experience.

### 🟡 Transfer to Synapsix Tools (Rust CLI/Utils)

| Component | Location | Destination | Notes |
|-----------|----------|-------------|-------|
| **cursor-proxy** | `tools/cursor-proxy/` | `synapsix/tools/proxy/` | Traffic inspection |
| **cursor-agent-tui** | `tools/cursor-agent-tui/` | Archive or delete | Superseded by Synapsix harness |
| **cursor-tui** | `tools/cursor-tui/` | Archive or delete | Superseded by egui app |
| **cursor-dialog-daemon** | `tools/cursor-dialog-daemon/` | Already in synapsix | Keep as reference only |

### 🟡 Keep in nixos-cursor (NixOS Packaging)

| Component | Location | Keep? | Notes |
|-----------|----------|-------|-------|
| **cursor/ module** | `cursor/` | ✅ Yes | Core AppImage packaging |
| **home-manager-module/** | `home-manager-module/` | ✅ Yes | HM integration |
| **modules/** | `modules/` | ✅ Yes | NixOS modules |
| **flake.nix** | `flake.nix` | ✅ Yes | Main flake |
| **examples/** | `examples/` | ✅ Yes | Usage examples |
| **cursor-versions.nix** | root | ✅ Yes | Version pinning |

**Rationale**: nixos-cursor should remain as the canonical NixOS packaging for Cursor IDE.

### 🔴 Delete or Archive

| Component | Location | Action | Rationale |
|-----------|----------|--------|-----------|
| **Python scripts** | `scripts/python/` | Archive | Superseded by Elixir/Nushell |
| **Rust scripts** | `scripts/rust/` | Archive | Superseded by proper tools |
| **cursor-isolation** | `tools/cursor-isolation/` | Delete | Never completed |
| **desktop-automation** | `tools/desktop-automation/` | Archive | Experimental |
| **android-companion** | `tools/android-companion/` | Move to continuum | Mobile companion |
| **Most docs/** | `docs/` | Archive | Historical, move relevant to new repos |

## Migration Steps

### Phase 1: Prepare Synapsix (1-2 days)

1. [ ] Create `synapsix/lib/synapsix/docs/` module structure
2. [ ] Create `synapsix/lib/synapsix/versions/` module structure
3. [ ] Create `synapsix/lib/synapsix/sync/` module structure
4. [ ] Add necessary deps (SQLite, HTTP client, etc.)

### Phase 2: Migrate Elixir Services (2-3 days)

1. [ ] Copy cursor-docs source to Synapsix
   - Rename modules: `CursorDocs.*` → `Synapsix.Docs.*`
   - Update imports and references
   - Run tests
2. [ ] Copy version-registry to Synapsix
3. [ ] Copy sync-daemon code to Synapsix
4. [ ] Update mix.exs with new modules
5. [ ] Create unified CLI tasks

### Phase 3: Migrate Native UI (2-3 days)

1. [ ] Create continuum-studio/ui/ structure
2. [ ] Copy cursor-studio-egui source
   - Rename crate: `cursor-studio` → `continuum-studio-ui`
   - Update Cargo.toml
   - Update module paths
3. [ ] Integrate with Synapsix backend
   - Update API endpoints
   - WebSocket connections
4. [ ] Build and test

### Phase 4: Transfer Rust Tools (1 day)

1. [ ] Move cursor-proxy to synapsix/tools/
2. [ ] Archive cursor-agent-tui and cursor-tui
3. [ ] Update build scripts

### Phase 5: Clean nixos-cursor (1 day)

1. [ ] Remove migrated directories
2. [ ] Update flake.nix (remove non-packaging outputs)
3. [ ] Update README.md (focus on NixOS packaging)
4. [ ] Archive old documentation
5. [ ] Create MIGRATION_COMPLETE.md summary

### Phase 6: Update Cross-References

1. [ ] Update all internal links in documentation
2. [ ] Update GitHub workflows
3. [ ] Update any CI/CD references
4. [ ] Update homelab configurations

## File Structure After Migration

### nixos-cursor (simplified)

```
nixos-cursor/
├── cursor/                 # Cursor packaging
│   ├── default.nix
│   └── unwrapped.nix
├── cursor-versions.nix     # Version pinning
├── cursor-versions-darwin.nix
├── modules/                # NixOS modules
│   ├── cursor.nix
│   └── service.nix
├── home-manager-module/    # HM integration
│   ├── default.nix
│   └── gc.nix
├── examples/               # Usage examples
├── flake.nix
├── flake.lock
└── README.md
```

### synapsix (expanded)

```
synapsix/
├── lib/
│   ├── synapsix/
│   │   ├── docs/           # From cursor-docs
│   │   │   ├── scraper/
│   │   │   ├── storage/
│   │   │   └── security/
│   │   ├── versions/       # From version-registry
│   │   ├── sync/           # From sync-daemon
│   │   ├── nesy/           # Existing NeSy stack
│   │   └── ...
├── native/
│   ├── synapsix_oxiz/      # Existing
│   ├── synapsix_carcara/   # Existing
│   └── synapsix_metrics_ui/ # Existing
├── tools/
│   └── proxy/              # From cursor-proxy
└── docs/
```

### continuum-studio (expanded)

```
continuum-studio/
├── core/                   # Elixir core (existing)
├── ui/                     # From cursor-studio-egui
│   ├── src/
│   │   ├── chat/           # Conversation browser
│   │   ├── diagram/        # D2 renderer
│   │   ├── docs/           # Docs panel
│   │   ├── modes/          # Mode editor
│   │   ├── security/       # Scanner UI
│   │   └── main.rs
│   ├── Cargo.toml
│   └── README.md
├── android/                # Mobile (existing)
└── docs/
```

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing users | High | Keep nixos-cursor packaging stable, only move services |
| Loss of git history | Medium | Use `git filter-repo` to preserve history during move |
| Breaking integrations | Medium | Update all references before deleting old paths |
| Missing functionality | Low | Comprehensive testing before cleanup |

## Success Criteria

- [ ] All Elixir services running in Synapsix
- [ ] Native UI compiles and runs from continuum-studio
- [ ] nixos-cursor still packages Cursor correctly
- [ ] All tests passing
- [ ] No broken imports or references
- [ ] Documentation updated

## Timeline Estimate

| Phase | Duration | Dependency |
|-------|----------|------------|
| Phase 1: Prepare | 1-2 days | None |
| Phase 2: Elixir Migration | 2-3 days | Phase 1 |
| Phase 3: UI Migration | 2-3 days | Phase 1 |
| Phase 4: Tools | 1 day | Phase 2 |
| Phase 5: Cleanup | 1 day | All previous |
| Phase 6: Cross-refs | 0.5 day | Phase 5 |

**Total: ~8-11 days** (can be parallelized)

## Open Questions

1. **Version registry**: Keep as separate service or integrate into Synapsix core?
2. **cursor-proxy**: Still needed if using NeSy verification instead?
3. **P2P sync**: Keep chat sync or simplify to single-node?
4. **Mobile companion**: Priority for Android app?

## References

- [PROJECT_INVENTORY.md](PROJECT_INVENTORY.md) - Current state inventory
- [CURSOR_STUDIO_ARCHITECTURE.md](CURSOR_STUDIO_ARCHITECTURE.md) - Architecture docs
- [Synapsix docs](../../synapsix/docs/) - Synapsix documentation
