# CursorTracker

Git-based tracking for Cursor user data with diff, blame, and rollback capabilities.

## Features

- 📸 **Snapshots** - Git-based versioning of Cursor configuration
- 🔍 **Diff** - Compare configurations between snapshots
- ⏪ **Rollback** - Restore previous configurations
- 👀 **Watch Mode** - Automatic snapshots on file changes
- 📊 **Compare** - Compare configurations between Cursor instances

## Architecture

```
CursorTracker.Application
└── CursorTracker.Supervisor
    ├── CursorTracker.Config      (configuration management)
    ├── CursorTracker.GitBackend  (git operations)
    └── CursorTracker.DataWatcher (file system monitoring)
```

## Installation

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Build release
MIX_ENV=prod mix release
```

## Usage

### CLI

```bash
# Initialize tracking
./cursor_tracker init

# Take a snapshot
./cursor_tracker snapshot "Before upgrading to 2.1.34"

# Show status
./cursor_tracker status

# Show diff from last commit
./cursor_tracker diff HEAD~1

# Show history
./cursor_tracker history -n 10

# Rollback to a previous snapshot
./cursor_tracker rollback HEAD~3

# List tracked instances
./cursor_tracker list

# Watch for changes (auto-snapshot)
./cursor_tracker watch --interval 5
```

### IEx (Interactive)

```elixir
# Start application
iex -S mix

# Initialize tracking
CursorTracker.init()

# Take a snapshot
CursorTracker.snapshot("Testing new settings")

# Show status
CursorTracker.status()

# Show diff
CursorTracker.diff("HEAD~1")

# Show history
CursorTracker.history(limit: 10)

# Rollback
CursorTracker.rollback("abc1234")

# Start watching
CursorTracker.watch()

# Stop watching
CursorTracker.unwatch()

# Compare instances
CursorTracker.compare("2.0.77", "2.1.34")
```

## What Gets Tracked

### From `~/.config/Cursor/`

- `User/settings.json` - Editor settings
- `User/keybindings.json` - Custom keybindings
- `User/snippets/` - Code snippets

### From `~/.cursor/`

- `mcp.json` - MCP server configuration
- `argv.json` - Startup arguments
- `agents/` - Custom agent definitions
- `rules/` - Cursor rules

## What Gets Excluded

- `*.vscdb` - SQLite databases (too large, binary)
- `Cache/`, `CachedData/` - Temporary cache
- `workspaceStorage/` - Workspace-specific data
- `logs/` - Log files

## Why Elixir?

| Requirement | Why Elixir Fits |
|-------------|-----------------|
| Long-running daemon | OTP supervision trees |
| File watching | Built-in file_system support |
| Fault tolerance | "Let it crash" philosophy |
| Hot reloading | Update without restart |
| Concurrent operations | Lightweight processes |

## Development

```bash
# Run tests
mix test

# Run linter
mix credo

# Generate docs
mix docs

# Start in development
iex -S mix
```

## Integration with Cursor Manager

This service is designed to integrate with the Cursor Manager GUI:

```elixir
# API for GUI integration
CursorTracker.list_instances()  # Get all tracked instances
CursorTracker.history()         # Get snapshot history for timeline
CursorTracker.diff("HEAD~1")    # Get diff for visual display
CursorTracker.rollback(ref)     # Rollback from GUI
```

## License

MIT
