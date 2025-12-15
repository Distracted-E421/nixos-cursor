# cursor-docs - Local Documentation Indexing for Cursor

A reliable, local alternative to Cursor's flaky `@docs` feature. **Zero workflow change** - it reads the same URLs you've already added in Cursor Settings.

## 🎯 The Problem

Cursor's built-in `@docs` indexing has a **widespread server-side bug** affecting versions 0.43.x through 2.0.77+ that causes:

- "Indexing failed" errors with no details
- Silent failures (shows "indexed" but 0 pages)
- No JavaScript rendering (fails on SPAs)
- No way to debug or retry

**This is NOT a NixOS or OS issue** - it affects all platforms.

## ✨ The Solution

**cursor-docs** scrapes the same documentation URLs locally with:

- ✅ Full JavaScript rendering
- ✅ FTS5 full-text search
- ✅ Transparent error reporting
- ✅ Automatic retry
- ✅ MCP integration with Cursor

## 🚀 Quick Start

```bash
cd services/cursor-docs

# Install dependencies
mix deps.get

# Setup database
mix cursor_docs.setup

# Sync from Cursor's existing @docs (main workflow!)
mix cursor_docs.sync

# Or add docs manually
mix cursor_docs.add https://hexdocs.pm/phoenix/

# Search
mix cursor_docs.search "authentication"

# List indexed docs
mix cursor_docs.list
```

## 🔄 Key Feature: Cursor Sync

The killer feature is **zero workflow change**:

1. You add docs in Cursor Settings → Indexing & Docs (as normal)
2. cursor-docs reads those same URLs from Cursor's SQLite database
3. Indexes them locally with proper JS rendering
4. Makes them available via MCP

```elixir
# Sync all docs from Cursor's settings
CursorDocs.sync_from_cursor()

# See what Cursor has configured
CursorDocs.list_cursor_docs()
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Cursor IDE                               │
│                                                                  │
│  Settings → Indexing & Docs                                      │
│  ┌────────────────────────────┐                                  │
│  │ @docs URLs:                │                                  │
│  │ • hexdocs.pm/phoenix       │                                  │
│  │ • docs.pola.rs             │                                  │
│  │ • (stored in SQLite)       │                                  │
│  └────────────────────────────┘                                  │
│              │                                                   │
│              │ cursor-docs reads                                 │
│              ▼                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │               cursor-docs (Elixir/OTP)                      │ │
│  │                                                             │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │ │
│  │  │CursorIntegration│→ │ Scraper Pool    │→ │ SQLite+FTS5 │ │ │
│  │  │ (reads Cursor)  │  │ (JS rendering)  │  │ (storage)   │ │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────┘ │ │
│  │                                                             │ │
│  │                    ┌─────────────────┐                     │ │
│  │                    │   MCP Server    │◄── Cursor queries   │ │
│  │                    └─────────────────┘                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 Dependencies

Real Hex packages that exist:

```elixir
{:exqlite, "~> 0.23"},     # SQLite with FTS5
{:req, "~> 0.5"},          # HTTP client
{:floki, "~> 0.36"},       # HTML parsing
{:wallaby, "~> 0.30"},     # Browser automation (optional)
{:jason, "~> 1.4"},        # JSON
{:file_system, "~> 1.0"},  # Watch Cursor DB changes
```

## 🔧 MCP Integration

Add to your `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "cursor-docs": {
      "command": "mix",
      "args": ["cursor_docs.mcp"],
      "cwd": "/path/to/nixos-cursor/services/cursor-docs"
    }
  }
}
```

Then use in Cursor chat:

```
@cursor-docs search "authentication with Guardian"
@cursor-docs list
@cursor-docs sync
```

## 📁 Data Locations

| What | Where |
|------|-------|
| cursor-docs DB | `~/.local/share/cursor-docs/cursor_docs.db` |
| Cursor global DB | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Cursor workspace DBs | `~/.config/Cursor/User/workspaceStorage/*/state.vscdb` |

## 🔍 CLI Commands

```bash
# Sync from Cursor
mix cursor_docs.sync

# Add manually
mix cursor_docs.add URL [--name NAME] [--max-pages N]

# Search
mix cursor_docs.search QUERY [--limit N]

# List sources
mix cursor_docs.list

# Check status
mix cursor_docs.status

# Start MCP server (for Cursor)
mix cursor_docs.mcp

# Start as daemon
mix cursor_docs.server
```

## 🧪 Development

```bash
# Run tests
mix test

# Type checking
mix dialyzer

# Linting
mix credo

# Generate docs
mix docs
```

## 📝 See Also

- [DOCS_INDEXING_ISSUE.md](../../docs/troubleshooting/DOCS_INDEXING_ISSUE.md) - Full details on Cursor's @docs bug
- [Cursor Forum threads](https://forum.cursor.com/search?q=%40docs%20indexing) - Community reports

## 📄 License

MIT
