# cursor-docs - Local Documentation Indexing for Cursor

A reliable, local alternative to Cursor's flaky `@docs` feature with **semantic search** and **security validation**. **Zero workflow change** - it reads the same URLs you've already added in Cursor Settings.

## 🎯 The Problem

Cursor's built-in `@docs` indexing has a **widespread server-side bug** affecting versions 0.43.x through 2.0.77+ that causes:

- "Indexing failed" errors with no details
- Silent failures (shows "indexed" but 0 pages)
- No JavaScript rendering (fails on SPAs)
- No way to debug or retry
- **Vulnerable to prompt injection** in indexed content

**This is NOT a NixOS or OS issue** - it affects all platforms.

## ✨ The Solution

**cursor-docs** v0.2.0 scrapes the same documentation URLs locally with:

- ✅ **Semantic search** via vector embeddings (SurrealDB + Ollama)
- ✅ **Security quarantine** - prompt injection & hidden text detection
- ✅ **Quality validation** - filters error pages, login walls, junk
- ✅ FTS5 full-text search (SQLite fallback)
- ✅ Transparent error reporting
- ✅ Automatic retry with exponential backoff
- ✅ MCP integration with Cursor

## 📊 Storage Backends

| Feature              | SurrealDB | SQLite |
|---------------------|-----------|--------|
| Full-text search    | ✅        | ✅ FTS5 |
| Vector embeddings   | ✅        | ❌      |
| Semantic search     | ✅        | ❌      |
| Graph relationships | ✅        | ❌      |
| Cross-domain links  | ✅        | ❌      |
| Cursor DB reading   | ❌        | ✅      |

cursor-docs automatically uses SurrealDB when available, falling back to SQLite.

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
mix cursor_docs.add https://hexdocs.pm/phoenix/Phoenix.Router.html

# Search (uses semantic if available)
mix cursor_docs.search "authentication"

# List indexed docs
mix cursor_docs.list

# Check storage status
mix cursor_docs.status
```

## 🔄 Key Feature: Cursor Sync

The killer feature is **zero workflow change**:

1. You add docs in Cursor Settings → Indexing & Docs (as normal)
2. cursor-docs reads those same URLs from Cursor's SQLite database
3. Runs them through **security quarantine**
4. Indexes them locally with proper content extraction
5. Generates **vector embeddings** for semantic search (if Ollama available)
6. Makes them available via MCP

```elixir
# Sync all docs from Cursor's settings
CursorDocs.sync_from_cursor()

# See what Cursor has configured
CursorDocs.list_cursor_docs()

# Check storage status
CursorDocs.storage_status()
```

## 🔒 Security Pipeline

**All external data is treated as radioactive** until validated:

```
URL → Fetch → [QUARANTINE ZONE] → Validate → Store

            Hidden Content Detection
                    ↓
            Prompt Injection Scan
                    ↓
            Quality Validation
                    ↓
            Security Tier: clean/flagged/quarantined/blocked
```

### Security Features

- **Hidden text detection**: CSS hiding, white-on-white text, zero-dimension elements
- **Prompt injection detection**: "ignore previous instructions", role manipulation, delimiter attacks
- **Quality validation**: Filters error pages, login walls, low-quality content
- **Safe snapshots**: Never expose raw potentially-malicious content to users

### Security Commands

```bash
# View security alerts
mix cursor_docs.alerts

# View quarantined content (pending review)
mix cursor_docs.quarantine

# Review and approve/reject quarantined items
mix cursor_docs.quarantine --review ITEM_ID --action approve

# Export alerts for cursor-studio
mix cursor_docs.alerts --export
```

## 🧠 AI Provider Architecture

cursor-docs is designed to be **useful without being a problem app**:

- **No forced dependencies** - Works with SQLite + FTS5 alone
- **No background daemons** - Unless you explicitly want them
- **Hardware-aware** - Detects and uses what's available efficiently
- **Pluggable** - Use Ollama, local models, or cloud APIs
- **Graceful degradation** - Falls back to FTS5 if AI unavailable

### Hardware Detection

cursor-docs automatically detects your hardware:

```bash
mix run -e "IO.puts(CursorDocs.AI.Hardware.summary())"

# Example output on Obsidian:
# Hardware Profile:
#   CPU: Intel(R) Core(TM) i9-9900K CPU @ 3.60GHz (16 threads)
#   RAM: 31GB
#   GPU: NVIDIA GeForce RTX 2080 (8GB), Intel Arc A770 (16GB)
#   Backend: cuda
#   Batch Size: 32
#   Model: nomic-embed-text
#   Background OK: true
```

### Provider Priority

1. **Ollama** (if running) - Uses existing Ollama installation
2. **Local ONNX** (if models downloaded) - No daemon required
3. **Disabled** - Graceful fallback to FTS5 keyword search

### Quick Setup

```bash
# Option 1: Use existing Ollama
ollama pull nomic-embed-text  # Best quality, 768 dimensions
# or
ollama pull all-minilm        # Faster, 384 dimensions

# Option 2: Local ONNX (no daemon)
mix cursor_docs.model download all-minilm

# Option 3: FTS5 only (no AI)
# Just works out of the box!
```

### Model Registry

| Model | Provider | Dims | Quality | Speed | Size |
|-------|----------|------|---------|-------|------|
| nomic-embed-text | ollama | 768 | 92% | 75% | 274MB |
| all-minilm | ollama | 384 | 82% | 95% | 45MB |
| mxbai-embed-large | ollama | 1024 | 94% | 60% | 670MB |

See [AI_PROVIDER_ARCHITECTURE.md](docs/AI_PROVIDER_ARCHITECTURE.md) for full documentation.

## 📊 Optional: SurrealDB for Vector Storage

For advanced semantic search with vector embeddings:

```bash
# Start SurrealDB (if not already running)
surreal start --user root --pass root file:~/.local/share/cursor-docs/surreal.db
```

With both SurrealDB and Ollama running, cursor-docs automatically:
- Generates embeddings for all indexed chunks
- Uses cosine similarity for semantic search
- Falls back to FTS5 if unavailable

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
│  │  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐  │ │
│  │  │Cursor        │→ │ Security      │→ │ Storage         │  │ │
│  │  │Integration   │  │ Quarantine    │  │ (Surreal/SQLite)│  │ │
│  │  └──────────────┘  └───────────────┘  └─────────────────┘  │ │
│  │         │                                      ↑            │ │
│  │         ↓                                      │            │ │
│  │  ┌──────────────┐  ┌───────────────┐  ┌───────┴─────────┐  │ │
│  │  │ Rate Limiter │→ │ Scraper       │→ │ Embeddings      │  │ │
│  │  │              │  │ + Extractor   │  │ (Ollama)        │  │ │
│  │  └──────────────┘  └───────────────┘  └─────────────────┘  │ │
│  │                                                             │ │
│  │                    ┌─────────────────┐                     │ │
│  │                    │   MCP Server    │◄── Cursor queries   │ │
│  │                    └─────────────────┘                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 Dependencies

```elixir
# Storage
{:exqlite, "~> 0.23"},      # SQLite with FTS5

# HTTP & Parsing
{:req, "~> 0.5"},           # HTTP client
{:floki, "~> 0.36"},        # HTML parsing

# JSON
{:jason, "~> 1.4"},

# Telemetry
{:telemetry, "~> 1.2"},
{:telemetry_metrics, "~> 1.0"},

# File watching
{:file_system, "~> 1.0"},   # Watch Cursor DB changes
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
| cursor-docs SQLite | `~/.local/share/cursor-docs/cursor_docs.db` |
| cursor-docs SurrealDB | `~/.local/share/cursor-docs/surreal.db` |
| Security alerts export | `/tmp/cursor-docs-alerts.json` |
| Cursor global DB | `~/.config/Cursor/User/globalStorage/state.vscdb` |
| Cursor workspace DBs | `~/.config/Cursor/User/workspaceStorage/*/state.vscdb` |

## 🔍 CLI Commands

```bash
# Sync from Cursor
mix cursor_docs.sync

# Add manually
mix cursor_docs.add URL [--name NAME] [--max-pages N] [--force]

# Search (semantic if SurrealDB+Ollama, FTS5 otherwise)
mix cursor_docs.search QUERY [--limit N]

# List sources
mix cursor_docs.list

# Check status (including backend info)
mix cursor_docs.status

# Security alerts
mix cursor_docs.alerts [--severity high] [--export]

# Quarantine management
mix cursor_docs.quarantine [--review ID --action approve|reject|keep_flagged]

# Show Cursor's configured docs
mix cursor_docs.cursor

# Import from Cursor (with limits)
mix cursor_docs.import [--limit N] [--dry-run]

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

## 🛠️ Configuration

Environment-specific config in `config/`:

```elixir
# config/config.exs
config :cursor_docs,
  db_path: "~/.local/share/cursor-docs",
  rate_limit: [requests_per_second: 2, burst: 5]

# SurrealDB (optional, enables semantic search)
config :cursor_docs, :surrealdb,
  endpoint: "http://localhost:8000",
  namespace: "cursor",
  database: "docs",
  username: "root",
  password: "root"
```

## 📝 See Also

- [DOCS_INDEXING_ISSUE.md](../../docs/troubleshooting/DOCS_INDEXING_ISSUE.md) - Full details on Cursor's @docs bug
- [Cursor Forum threads](https://forum.cursor.com/search?q=%40docs%20indexing) - Community reports

## 📄 License

MIT
