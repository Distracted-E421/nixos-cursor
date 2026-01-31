# MIGRATED - cursor-studio-egui

**Status**: MIGRATED to continuum-studio
**Date**: January 31, 2026

## Migration Details

The cursor-studio-egui application has been split and migrated:

### Migrated to continuum-studio/ui/
- `diagram/` → `diagram_d2/` (Full D2 parser/renderer)
- `theme.rs`, `theme_loader.rs` → `theme/vscodetheme.rs`, `theme/loader.rs`

### Archived for Reference (not transferred)
See `/home/e421/continuum-studio/docs/CURSOR_STUDIO_EGUI_REFERENCE.md` for:
- `chat/` - CRDT sync, P2P (rebuild target)
- `sync/` - Database watcher (rebuild target)
- `ai_workspace/` - Replaced by Synapsix NeSy
- `versions/` - Already in synapsix/tools/cursor-versions

### New Home
- Desktop UI: `continuum-studio/ui/`
- Core services: `synapsix/`
- Version management: `synapsix/tools/cursor-versions/`

## DO NOT USE THIS DIRECTORY

This code is preserved for reference only. Use the migrated versions in:
- `/home/e421/continuum-studio/`
- `/home/e421/synapsix/`
