# Cursor Sync Daemon (Elixir)

An Elixir-based sync daemon for Cursor IDE data pipeline control.

## Why Elixir?

- **Hot Code Reloading** - Change sync logic without stopping the daemon
- **Fault Tolerance** - OTP supervisors automatically restart crashed components
- **Multi-Machine Sync** - BEAM's distributed node support for future clustering
- **Named Pipes IPC** - Lightweight communication with cursor-studio (Rust)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   CursorSync.Supervisor                  │
│  ┌──────────────┐  ┌─────────────┐  ┌───────────────┐  │
│  │ PipeServer   │  │  Watcher    │  │  SyncEngine   │  │
│  │ (named pipe) │  │ (inotify)   │  │  (core sync)  │  │
│  └──────────────┘  └─────────────┘  └───────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │                   Telemetry                       │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │                    │                  │
         ▼                    ▼                  ▼
  cursor-studio         Cursor DBs        External DB
    (Rust)           (state.vscdb)    (conversations.db)
```

## Quick Start

```bash
# Install dependencies
mix deps.get

# Start in interactive mode (best for development)
iex -S mix

# Start as daemon
mix run --no-halt

# Build release for production
mix release
```

## IPC Protocol

Communication with cursor-studio via named pipes at:
- Command: `/tmp/cursor-sync-cmd.pipe`
- Response: `/tmp/cursor-sync-resp.pipe`

### Commands

```json
// Sync all databases
{"cmd": "sync"}

// Sync specific workspace
{"cmd": "sync", "workspace": "abc123"}

// Get status
{"cmd": "status"}

// Get statistics
{"cmd": "stats"}

// Graceful shutdown
{"cmd": "stop"}
```

### Responses

```json
// Success
{"ok": true, "data": {...}}

// Error
{"ok": false, "error": "message"}
```

### Example (from shell)

```bash
# Send command
echo '{"cmd": "status"}' > /tmp/cursor-sync-cmd.pipe

# Read response
cat /tmp/cursor-sync-resp.pipe
```

## Hot Reloading

The killer feature! Change code and reload without restart:

```elixir
iex> # Edit lib/cursor_sync/sync_engine.ex
iex> r CursorSync.SyncEngine
{:reloaded, [CursorSync.SyncEngine]}

iex> # State is preserved! New logic active.
iex> CursorSync.SyncEngine.stats()
%{total_syncs: 5, ...}
```

## Configuration

See `config/runtime.exs` for runtime configuration.

Environment variables:
- `HOME` - User home directory
- `XDG_CONFIG_HOME` - Config directory (default: `$HOME/.config`)
- `CURSOR_SYNC_CMD_PIPE` - Command pipe path
- `CURSOR_SYNC_RESP_PIPE` - Response pipe path
- `CURSOR_SYNC_LOG_LEVEL` - Log level (debug, info, warning, error)

## Development

```bash
# Run tests
mix test

# Run with live reload
iex -S mix

# Format code
mix format

# Run linter
mix credo

# Type checking
mix dialyzer
```

## Integration with cursor-studio (Rust)

The Rust side can communicate via named pipes:

```rust
use std::fs::File;
use std::io::{Write, BufReader, BufRead};

// Send command
let mut cmd_pipe = File::create("/tmp/cursor-sync-cmd.pipe")?;
writeln!(cmd_pipe, r#"{{"cmd": "sync"}}"#)?;

// Read response
let resp_pipe = File::open("/tmp/cursor-sync-resp.pipe")?;
let reader = BufReader::new(resp_pipe);
for line in reader.lines() {
    println!("Response: {}", line?);
}
```

## Future: Distributed Sync

Elixir's BEAM makes distributed sync straightforward:

```elixir
# On machine A
Node.start(:"sync@machine-a")
Node.connect(:"sync@machine-b")

# Sync events automatically propagate!
CursorSync.SyncEngine.sync()
```

## License

MIT
