# MIGRATED - cursor-dialog-daemon

**Status**: MIGRATED to synapsix
**Date**: January 31, 2026

## Migration Details

cursor-dialog-daemon has been migrated to:
- **New location**: `/home/e421/synapsix/dialog/`
- **New binary names**: 
  - `synapsix-dialog-daemon`
  - `synapsix-dialog-cli`
- **Version**: 0.6.0
- **D-Bus service**: `sh.synapsix.Dialog`

### New Features (in synapsix version)
- Phase 1: Port & Rename ✓
- Phase 2: Queue System ✓
- Phase 3: Multi-Device Sync ✓
- Phase 4: Rich Context Display ✓
- Phase 5: Decision Memory ✓
- Phase 6: Approval Workflows ✓
- Phase 7: Rules Engine ✓
- Phase 8: AFK Busy Work ✓

### Integration
- Elixir client: `Synapsix.Dialog`
- NixOS service: `homelab.synapsix.enable = true`

## DO NOT USE THIS DIRECTORY

Use: `/home/e421/synapsix/dialog/`
