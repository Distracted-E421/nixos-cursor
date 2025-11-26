# Cursor Data Tracking Scripts

Git-based version control for Cursor user data.

## Scripts

### `cursor-data-tracker.sh`

Main tracking tool with git-like commands:

```bash
# Initialize tracking
./cursor-data-tracker.sh init                # Default Cursor
./cursor-data-tracker.sh init -v 2.0.77      # Isolated version

# Take snapshots
./cursor-data-tracker.sh snapshot -m "Before upgrade"

# View changes
./cursor-data-tracker.sh status              # Uncommitted changes
./cursor-data-tracker.sh diff HEAD~1         # Changes since last snapshot
./cursor-data-tracker.sh history             # All snapshots

# Investigate
./cursor-data-tracker.sh blame mcp.json      # File history

# Rollback
./cursor-data-tracker.sh rollback HEAD~1     # Restore previous state

# Compare instances
./cursor-data-tracker.sh compare 2.0.77 2.1.34
./cursor-data-tracker.sh list                # Show all tracked instances
```

## What Gets Tracked

- `settings.json` - Editor settings
- `keybindings.json` - Keyboard shortcuts
- `mcp.json` - MCP server configuration
- `agents/` - Custom agent rules
- `rules/` - Custom rules
- `snippets/` - Code snippets

## What's Excluded

- `state.vscdb` - SQLite database (100s of MB)
- Cache directories
- Binary blob storage
- Workspace-specific data

## Use Cases

1. **Before upgrading**: Snapshot → Upgrade → Rollback if needed
2. **Debugging**: Find when a setting changed with `blame`
3. **Multi-version**: Compare configs between versions
4. **Backup**: Regular snapshots for safety

## Documentation

See [docs/DATA_TRACKING.md](../../docs/DATA_TRACKING.md) for full documentation.
