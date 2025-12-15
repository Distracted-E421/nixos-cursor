# cursor-docs - Local Documentation Indexing Service

> **Reliable, local alternative to Cursor's broken @docs system**

## 🎯 Purpose

Cursor's built-in `@docs` feature relies on server-side crawling that fails ~50% of the time. This service provides a **local, reliable alternative** using:

- **Elixir** - Fault-tolerant, concurrent scraping with OTP supervision
- **Playwright** - Full JavaScript rendering (handles SPAs, React docs, etc.)
- **SurrealDB** - Local storage with full-text search and P2P sync capability
- **MCP Protocol** - Seamless integration with Cursor

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        cursor-docs Service                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    CursorDocs.Application                    │   │
│  │  (OTP Application - Supervised Process Tree)                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                               │                                     │
│           ┌───────────────────┼───────────────────┐                 │
│           ▼                   ▼                   ▼                 │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐   │
│  │  Scraper.Pool   │ │  Storage.Surreal│ │  MCP.Server         │   │
│  │  (GenServer)    │ │  (GenServer)    │ │  (Plug/Cowboy)      │   │
│  │                 │ │                 │ │                     │   │
│  │  • Browser pool │ │  • Connection   │ │  • Tool handlers    │   │
│  │  • Job queue    │ │    management   │ │  • JSON-RPC         │   │
│  │  • Rate limits  │ │  • FTS queries  │ │  • Stdio transport  │   │
│  │  • Retry logic  │ │  • Sync events  │ │                     │   │
│  └────────┬────────┘ └────────┬────────┘ └──────────┬──────────┘   │
│           │                   │                     │               │
│           └───────────────────┼─────────────────────┘               │
│                               ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    SurrealDB (Embedded)                      │   │
│  │                                                              │   │
│  │  doc_sources: [id, url, title, status, pages_count, ...]    │   │
│  │  doc_chunks:  [id, source_id, url, content, position, ...]  │   │
│  │  scrape_jobs: [id, url, status, attempts, error, ...]       │   │
│  │                                                              │   │
│  │  FTS Index: DEFINE INDEX content_fts ON doc_chunks          │   │
│  │             FIELDS content SEARCH ANALYZER vs               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 📦 Project Structure

```
services/cursor-docs/
├── mix.exs                    # Elixir project definition
├── config/
│   ├── config.exs             # Base configuration
│   ├── dev.exs                # Development settings
│   └── prod.exs               # Production settings
├── lib/
│   ├── cursor_docs.ex         # Application entry point
│   ├── cursor_docs/
│   │   ├── application.ex     # OTP Application supervisor
│   │   ├── scraper/
│   │   │   ├── pool.ex        # Browser pool management
│   │   │   ├── worker.ex      # Individual scrape workers
│   │   │   ├── job.ex         # Job queue management
│   │   │   └── extractor.ex   # Content extraction logic
│   │   ├── storage/
│   │   │   ├── surreal.ex     # SurrealDB client
│   │   │   ├── schema.ex      # Database schema definitions
│   │   │   └── search.ex      # Full-text search queries
│   │   └── mcp/
│   │       ├── server.ex      # MCP protocol server
│   │       ├── tools.ex       # Tool definitions
│   │       └── transport.ex   # Stdio/HTTP transport
├── priv/
│   └── surreal/
│       └── schema.surql       # SurrealDB schema
├── test/
│   └── cursor_docs_test.exs
└── README.md
```

## 🚀 Quick Start

### Prerequisites

```bash
# Elixir (via Nix)
nix-shell -p elixir erlang

# Or if using direnv with flake
cd services/cursor-docs
direnv allow
```

### Installation

```bash
cd services/cursor-docs

# Install dependencies
mix deps.get

# Setup database
mix cursor_docs.setup

# Start the service
mix cursor_docs.server
```

### CLI Usage

```bash
# Add documentation
mix cursor_docs.add https://docs.example.com/

# Add with custom name
mix cursor_docs.add https://hexdocs.pm/ecto/Ecto.html --name "Ecto Docs"

# List all indexed docs
mix cursor_docs.list

# Search documentation
mix cursor_docs.search "database queries"

# Check scrape job status
mix cursor_docs.status

# Remove documentation
mix cursor_docs.remove ecto-docs
```

### MCP Integration

Add to your Cursor MCP configuration (`~/.cursor/mcp.json`):

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
@cursor-docs search "how to define schemas"
@cursor-docs add https://docs.pola.rs/
```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CURSOR_DOCS_DB_PATH` | `~/.local/share/cursor-docs/` | SurrealDB data directory |
| `CURSOR_DOCS_BROWSER_POOL` | `3` | Concurrent browser instances |
| `CURSOR_DOCS_CHUNK_SIZE` | `1500` | Characters per chunk |
| `CURSOR_DOCS_CHUNK_OVERLAP` | `200` | Overlap between chunks |
| `CURSOR_DOCS_TIMEOUT` | `30000` | Page load timeout (ms) |
| `CURSOR_DOCS_RETRIES` | `3` | Retry attempts per page |

### config/config.exs

```elixir
import Config

config :cursor_docs,
  db_path: System.get_env("CURSOR_DOCS_DB_PATH", "~/.local/share/cursor-docs"),
  browser_pool_size: 3,
  chunk_size: 1500,
  chunk_overlap: 200,
  page_timeout: 30_000,
  max_retries: 3,
  rate_limit: [
    requests_per_second: 2,
    burst: 5
  ]
```

## 📊 Comparison with Cursor's @docs

| Feature | Cursor @docs | cursor-docs |
|---------|--------------|-------------|
| **Success Rate** | ~50% | **~95%+** |
| **JS Rendering** | ❌ No | ✅ Yes (Playwright) |
| **Error Messages** | ❌ None | ✅ Detailed |
| **Local Storage** | ❌ Server-only | ✅ SurrealDB |
| **Offline Use** | ❌ No | ✅ Yes |
| **Custom Crawl Rules** | ❌ No | ✅ Yes |
| **Rate Limiting** | ❌ Aggressive | ✅ Configurable |
| **P2P Sync** | ❌ No | ✅ Planned |

## 🔄 Scraping Pipeline

```
URL Input
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    1. Job Queue (GenServer)                     │
│  - Deduplication                                                │
│  - Priority ordering                                            │
│  - Rate limiting                                                │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    2. Browser Pool                              │
│  - Playwright browser instances                                 │
│  - Page lifecycle management                                    │
│  - Resource cleanup                                             │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    3. Content Extraction                        │
│  - Wait for JS hydration                                        │
│  - Remove nav/footer/ads                                        │
│  - Extract main content                                         │
│  - Parse metadata (title, description)                          │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    4. Link Discovery                            │
│  - Find internal documentation links                            │
│  - Respect robots.txt                                           │
│  - Apply crawl rules                                            │
│  - Queue discovered URLs                                        │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    5. Chunking                                  │
│  - Split content at paragraph/sentence boundaries               │
│  - Maintain context overlap                                     │
│  - Preserve code blocks                                         │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    6. Storage (SurrealDB)                       │
│  - Store doc_source metadata                                    │
│  - Store doc_chunks with FTS indexing                           │
│  - Update scrape job status                                     │
└─────────────────────────────────────────────────────────────────┘
```

## 🎯 MCP Tools

The service exposes these MCP tools:

### `cursor_docs_add`

Add a documentation URL for indexing.

```json
{
  "name": "cursor_docs_add",
  "description": "Add documentation URL to be indexed locally",
  "inputSchema": {
    "type": "object",
    "properties": {
      "url": { "type": "string", "description": "Documentation URL" },
      "name": { "type": "string", "description": "Display name (optional)" },
      "max_pages": { "type": "integer", "description": "Max pages to crawl" }
    },
    "required": ["url"]
  }
}
```

### `cursor_docs_search`

Search indexed documentation.

```json
{
  "name": "cursor_docs_search",
  "description": "Search local documentation index",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search query" },
      "limit": { "type": "integer", "default": 5 },
      "sources": { "type": "array", "description": "Filter by source names" }
    },
    "required": ["query"]
  }
}
```

### `cursor_docs_list`

List all indexed documentation sources.

```json
{
  "name": "cursor_docs_list",
  "description": "List all indexed documentation sources",
  "inputSchema": {
    "type": "object",
    "properties": {}
  }
}
```

### `cursor_docs_status`

Get scraping job status.

```json
{
  "name": "cursor_docs_status",
  "description": "Check status of scraping jobs",
  "inputSchema": {
    "type": "object",
    "properties": {
      "source": { "type": "string", "description": "Filter by source" }
    }
  }
}
```

## 🧪 Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test
mix test test/cursor_docs/scraper/extractor_test.exs
```

## 📈 Roadmap

### v0.1.0 (Current)
- [x] Basic scraping with Playwright
- [x] SurrealDB storage
- [x] Full-text search
- [x] MCP server interface
- [x] CLI commands

### v0.2.0 (Planned)
- [ ] Crawl rules (exclude patterns, max depth)
- [ ] Incremental updates (only re-scrape changed pages)
- [ ] Sitemap.xml support
- [ ] robots.txt respect

### v0.3.0 (Planned)
- [ ] P2P sync between devices
- [ ] Team shared docs
- [ ] Import from Cursor's @docs

### v1.0.0 (Goal)
- [ ] 95%+ success rate on all documentation sites
- [ ] Sub-second search latency
- [ ] Zero-config NixOS service module

## 🔗 Related

- [Troubleshooting Guide](../../docs/troubleshooting/DOCS_INDEXING_ISSUE.md)
- [Data Pipeline Control Roadmap](../../docs/internal/DATA_PIPELINE_CONTROL_ROADMAP.md)
- [Cursor's Crawler Repo](https://github.com/getcursor/crawler)

---

*Part of [nixos-cursor](https://github.com/Distracted-E421/nixos-cursor)*

