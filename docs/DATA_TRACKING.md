# Cursor Data Tracking System

Git-based tracking for Cursor user data with diff, blame, and rollback capabilities.

## Overview

When running multiple Cursor versions or frequently changing configurations, it's important to:
- Track changes to settings, MCP configs, and custom rules
- Compare configurations between versions
- Rollback when something breaks
- Understand what changed and when ("git blame" for your config)

This system uses git to version your Cursor user data, giving you full history and diff capabilities.

## Quick Start

```bash
# Initialize tracking for your default Cursor instance
./scripts/data-tracking/cursor-data-tracker.sh init

# Initialize tracking for an isolated version
./scripts/data-tracking/cursor-data-tracker.sh init -v 2.0.77

# Take a snapshot before making changes
./scripts/data-tracking/cursor-data-tracker.sh snapshot -m "Before MCP update"

# See what changed
./scripts/data-tracking/cursor-data-tracker.sh diff

# Rollback if something broke
./scripts/data-tracking/cursor-data-tracker.sh rollback HEAD~1
```

## What Gets Tracked

### Tracked Files

| File/Directory | Description | Location |
|---------------|-------------|----------|
| `settings.json` | Editor settings | `~/.config/Cursor/User/` |
| `keybindings.json` | Keyboard shortcuts | `~/.config/Cursor/User/` |
| `snippets/` | Code snippets | `~/.config/Cursor/User/snippets/` |
| `mcp.json` | MCP server config | `~/.cursor/` |
| `argv.json` | Launch arguments | `~/.cursor/` |
| `agents/` | Custom agent rules | `~/.cursor/agents/` |
| `rules/` | Custom rules | `~/.cursor/rules/` |
| Extensions list | Installed extensions | Generated manifest |

### Excluded (Too Large/Binary)

| Item | Reason |
|------|--------|
| `state.vscdb` | SQLite database (100s of MB) |
| `Cache/`, `CachedData/` | Temporary cache |
| `blob_storage/` | Binary data |
| `workspaceStorage/` | Per-workspace (tracked separately) |
| `globalStorage/*/` | Extension data (varies) |

## Commands

### `init` - Initialize Tracking

```bash
# Track default Cursor instance
cursor-data-tracker.sh init

# Track isolated version
cursor-data-tracker.sh init -v 2.0.77

# Track specific version
cursor-data-tracker.sh init -v 1.7.54
```

### `snapshot` - Save Current State

```bash
# Take a snapshot with auto-generated message
cursor-data-tracker.sh snapshot

# Take a snapshot with custom message
cursor-data-tracker.sh snapshot -m "Before updating MCP servers"

# Snapshot specific version
cursor-data-tracker.sh snapshot -v 2.0.77 -m "Pre-upgrade backup"
```

### `status` - Show Current State

```bash
# Show uncommitted changes
cursor-data-tracker.sh status

# Show status for specific version
cursor-data-tracker.sh status -v 2.0.77
```

### `diff` - Show Changes

```bash
# Diff with previous snapshot
cursor-data-tracker.sh diff

# Diff with specific commit
cursor-data-tracker.sh diff HEAD~3

# Diff with named snapshot
cursor-data-tracker.sh diff abc1234
```

### `history` - Show Snapshot History

```bash
# Show last 20 snapshots
cursor-data-tracker.sh history

# Show more entries
cursor-data-tracker.sh history -n 50

# Show history for specific version
cursor-data-tracker.sh history -v 2.0.77
```

### `blame` - Show File History

```bash
# See who/what changed a file
cursor-data-tracker.sh blame User/settings.json

# Blame MCP config
cursor-data-tracker.sh blame cursor-home/mcp.json
```

### `rollback` - Restore Previous State

```bash
# Rollback to previous snapshot
cursor-data-tracker.sh rollback HEAD~1

# Rollback to specific commit
cursor-data-tracker.sh rollback abc1234

# Rollback for specific version
cursor-data-tracker.sh rollback -v 2.0.77 HEAD~2
```

### `compare` - Compare Two Instances

```bash
# Compare two version instances
cursor-data-tracker.sh compare 2.0.77 2.1.34

# Compare default with isolated version
cursor-data-tracker.sh compare default 2.0.77
```

### `list` - Show Tracked Instances

```bash
cursor-data-tracker.sh list
```

## Workflows

### Before Upgrading Cursor

```bash
# 1. Take a snapshot of current state
cursor-data-tracker.sh snapshot -m "Pre-upgrade to 2.1.34"

# 2. Upgrade and use new version

# 3. If something's wrong, check what changed
cursor-data-tracker.sh diff HEAD~1

# 4. Rollback if needed
cursor-data-tracker.sh rollback HEAD~1
```

### Comparing Versions

```bash
# 1. Initialize tracking for both versions
cursor-data-tracker.sh init -v 2.0.77
cursor-data-tracker.sh init -v 2.1.34

# 2. Compare their configurations
cursor-data-tracker.sh compare 2.0.77 2.1.34
```

### Finding When Something Changed

```bash
# See history of MCP config
cursor-data-tracker.sh blame cursor-home/mcp.json

# Find when a setting was added
cursor-data-tracker.sh history | grep "MCP"
```

### Regular Maintenance

```bash
# Weekly: Take a snapshot
cursor-data-tracker.sh snapshot -m "Weekly backup"

# Before any major change
cursor-data-tracker.sh snapshot -m "Before experimenting with new MCP servers"
```

## Data Locations

### Tracking Directory

All tracking data is stored in `~/.cursor-data-tracking/`:

```
~/.cursor-data-tracking/
├── default/              # Default Cursor instance
│   ├── .git/            # Git repository
│   ├── User/            # Tracked user settings
│   │   ├── settings.json
│   │   ├── keybindings.json
│   │   └── snippets/
│   ├── cursor-home/     # Tracked .cursor files
│   │   ├── mcp.json
│   │   ├── argv.json
│   │   └── agents/
│   ├── manifest.json    # File manifest
│   └── .cursor-tracking.json  # Metadata
└── cursor-2.0.77/       # Isolated version
    └── ...
```

### Cursor Data Locations

| Instance | Location |
|----------|----------|
| Default | `~/.config/Cursor/` |
| Isolated 2.0.77 | `~/.cursor-2.0.77/` |
| Cursor Home | `~/.cursor/` |

## Integration with Cursor Manager

The data tracker can be integrated with the cursor-manager GUI:

```bash
# In cursor-manager, add menu option for:
# - "Take Snapshot" → cursor-data-tracker.sh snapshot
# - "View History" → cursor-data-tracker.sh history
# - "Rollback" → cursor-data-tracker.sh rollback
```

## Automatic Snapshots

Consider setting up automatic snapshots:

```bash
# Add to crontab for daily snapshots
0 2 * * * /path/to/cursor-data-tracker.sh snapshot -m "Daily auto-backup"

# Or via systemd timer (see home-manager-module)
```

## Troubleshooting

### "Tracking not initialized"

Run `init` first:
```bash
cursor-data-tracker.sh init -v <version>
```

### Large diff output

Use `--stat` for summary only, or filter specific files:
```bash
cursor-data-tracker.sh diff HEAD~1 -- User/settings.json
```

### Merge conflicts on rollback

The rollback creates a new commit, not a hard reset, so conflicts are rare. If they occur:
```bash
cd ~/.cursor-data-tracking/default
git status  # See conflicts
git checkout --theirs .  # Accept old version
# or manually resolve
```

## Related Documentation

- [Garbage Collection](./GARBAGE_COLLECTION.md)
- [User Data Persistence](./USER_DATA_PERSISTENCE.md)
- [Multi-Version Guide](../VERSION_MANAGER_GUIDE.md)
