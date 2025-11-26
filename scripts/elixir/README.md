# Elixir Projects

Long-running services and fault-tolerant daemons built with Elixir/OTP.

## Why Elixir?

| Requirement | Why Elixir Fits |
|-------------|-----------------|
| Long-running daemon | OTP supervision trees |
| File watching | Built-in file_system support |
| Fault tolerance | "Let it crash" philosophy |
| Hot reloading | Update without restart |
| Concurrent operations | Lightweight processes |

## Projects

### `cursor_tracker/`

Git-based tracking for Cursor user data with diff, blame, and rollback.

```bash
cd cursor_tracker

# Install dependencies
mix deps.get

# Run in development
iex -S mix

# Build release
MIX_ENV=prod mix release

# Run release
./_build/prod/rel/cursor_tracker/bin/cursor_tracker start
```

**Features:**
- 📸 Automatic snapshots on file changes
- 🔍 Git diff/blame for configuration tracking
- ⏪ Rollback to previous configurations
- 📊 Compare between Cursor instances

## Development Environment

Enter the development shell with Elixir:

```bash
nix develop .#full  # Includes Elixir tooling
```

Or use a specific Elixir shell:

```bash
nix-shell -p elixir
```

## Elixir Standards

See [elixir-scripting.mdc](../../.cursor/rules/languages/elixir-scripting.mdc) for coding standards.

Key principles:
- Use OTP supervision trees for fault tolerance
- Prefer GenServers for stateful services
- Use `with` for error handling chains
- Write comprehensive @moduledoc and @doc
