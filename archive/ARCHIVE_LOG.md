# Archive Log

**Archived**: January 31, 2026  
**Purpose**: Preserve legacy code for reference during Continuum Studio migration

## Archived Components

### scripts-python/

**Original location**: `scripts/python/`  
**Reason**: Superseded by Elixir and Nushell equivalents in Synapsix  
**Contents**:
- cursor-version-manager.py - Version management scripts
- data-analysis scripts
- Utility scripts for Cursor data

**Reference value**: Low - functionality moved to Elixir services

### scripts-rust/

**Original location**: `scripts/rust/`  
**Reason**: Superseded by proper Rust tools in tools/  
**Contents**:
- Early experimental Rust scripts
- CLI prototypes

**Reference value**: Low - functionality in cursor-studio-egui

### cursor-tui/

**Original location**: `tools/cursor-tui/`  
**Reason**: Superseded by cursor-studio-egui (full GUI)  
**Contents**:
- Terminal UI for Cursor management
- ~1,500 lines Rust
- Ratatui-based TUI

**Reference value**: Medium - TUI concepts could be useful

### cursor-agent-tui/

**Original location**: `tools/cursor-agent-tui/`  
**Reason**: Superseded by Synapsix harness orchestrator  
**Contents**:
- Agent control TUI
- Protobuf definitions
- Capture scripts

**Reference value**: Medium - Protobuf definitions might be useful

### cursor-isolation/

**Original location**: `tools/cursor-isolation/`  
**Reason**: Never completed  
**Contents**:
- Network isolation experiments
- Namespace scripts
- Firewall rules

**Reference value**: Low - concepts moved to proxy approach

### desktop-automation/

**Original location**: `tools/desktop-automation/`  
**Reason**: Experimental, not integrated  
**Contents**:
- Screenshot automation
- Desktop interaction scripts

**Reference value**: Low - KDE automation in homelab rules

### sync-daemon-elixir/

**Original location**: `sync-daemon-elixir/`  
**Reason**: Reference for Synapsix sync module  
**Contents**:
- Elixir sync daemon
- Database sync logic
- GenServer implementations

**Reference value**: High - Architecture reference for Synapsix

## Retrieval

To restore any archived code:

```bash
# Check what's available
ls archive/

# Copy to new location
cp -r archive/component-name /destination/path/

# Or restore to original location
git mv archive/component-name original/path/
```

## Related Documents

- [CONTINUUM_STUDIO_MIGRATION.md](../docs/CONTINUUM_STUDIO_MIGRATION.md) - Full migration plan
- [MIGRATION_HANDOFF.md](../docs/MIGRATION_HANDOFF.md) - Agent handoff instructions
- [PROJECT_INVENTORY.md](../PROJECT_INVENTORY.md) - Component inventory
