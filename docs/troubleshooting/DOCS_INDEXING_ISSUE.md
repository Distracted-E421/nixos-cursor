# @Docs Indexing Issue - Cursor Server-Side Bug

> **⚠️ This is NOT a nixos-cursor, cursor-studio, or NixOS issue.**
> 
> This is a **well-documented, widespread bug** affecting Cursor's server-side documentation indexing system across **all platforms** (Windows, macOS, Linux) and **all Cursor versions** from approximately 0.43.x through current releases.

## 📋 Summary

When attempting to add new documentation via Cursor's `@docs` feature (Settings → Indexing & Docs → Add Doc), users experience:

- **"Indexing failed"** error with no details
- Progress starts then silently fails
- Some docs show as "indexed" but have **0 pages**
- Docs that previously worked suddenly fail after updates

## 🔍 Root Cause Analysis

### Where the Problem Lives

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Cursor @Docs Architecture                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐                                                    │
│  │  User adds  │                                                    │
│  │  URL to     │───────────────┐                                    │
│  │  @docs      │               │                                    │
│  └─────────────┘               ▼                                    │
│                       ┌─────────────────┐                           │
│                       │  Cursor Servers │  ◄── THE PROBLEM IS HERE  │
│                       │  (Cloud-based)  │                           │
│                       │  - Crawl URL    │                           │
│                       │  - Extract text │                           │
│                       │  - Embed chunks │                           │
│                       └────────┬────────┘                           │
│                                │                                    │
│                                ▼                                    │
│                       ┌─────────────────┐                           │
│                       │  Vector DB      │                           │
│                       │  (embeddings)   │                           │
│                       └────────┬────────┘                           │
│                                │                                    │
│                                ▼                                    │
│  ┌─────────────┐      ┌─────────────────┐                           │
│  │  @docs in   │◄─────│  Retrieve       │                           │
│  │  chat       │      │  relevant       │                           │
│  │             │      │  chunks         │                           │
│  └─────────────┘      └─────────────────┘                           │
│                                                                     │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  LOCAL (Your Machine)           CLOUD (Cursor's Servers)            │
│  ✅ Works fine                  ❌ Crawler fails frequently          │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Cursor's Server-Side Crawler Fails

The Cursor team's crawler has **significant limitations**:

| Failure Mode | Description | Affected Sites |
|--------------|-------------|----------------|
| **JavaScript Rendering** | Crawler doesn't execute JS | SPAs, React docs, Next.js sites |
| **Large Doc Trees** | Times out on big documentation | Rust docs, Microsoft Learn, AWS docs |
| **Bot Protection** | Blocked by Cloudflare, rate limits | Most modern documentation sites |
| **Non-standard HTML** | Fails to parse content correctly | API references, generated docs |
| **Silent Failures** | No error messages returned | All failure modes |

### Proof This is Server-Side

1. **Same URL fails on Windows, macOS, Linux** - Platform independent
2. **Same URL fails across all Cursor versions** - Not version-specific  
3. **No local network issues** - HTTP/2 disable doesn't fix it
4. **Cursor team acknowledges it** - Forum posts from Dean Rie (Cursor staff)

## 📊 Affected Versions Timeline

| Version | Docs Indexing Status |
|---------|---------------------|
| 0.41.x | ✅ Mostly working |
| 0.43.5 | ❌ **Major regression** |
| 0.45.x | ❌ Still broken |
| 2.0.x | ❌ Still broken |
| 2.0.77 | ❌ Still broken |
| 2.1.x | ❌ Still broken |

**Note:** This has been a persistent issue for **6+ months** with no fix from Cursor.

## 🛠️ Workarounds

### 1. Try Using the Docs Anyway

Counterintuitively, sometimes docs that show "Indexing failed" **actually work**:

```
@docs your-doc-name
```

The UI may show failure, but partial embeddings may have been created.

### 2. HTTP/2 Disable (Mixed Results)

In your Cursor settings.json:

```json
{
  "cursor.general.disableHttp2": true
}
```

**Note:** This helps in some cases but doesn't fix the underlying server-side issue.

### 3. Index Specific Pages Instead

Instead of indexing an entire documentation site:

```
❌ https://docs.example.com/
✅ https://docs.example.com/api/specific-page
```

The crawler handles individual pages better than full sites.

### 4. Submit to Cursor's Crawler Repo

Cursor maintains a list of pre-indexed documentation:

**Repository:** https://github.com/getcursor/crawler

Submit a PR to add documentation you need to their pre-indexed list.

### 5. Use Our Alternative: cursor-docs (Recommended)

**nixos-cursor** provides an alternative documentation system that:
- Indexes locally (no server dependency)
- Works reliably with any URL
- Integrates via MCP protocol
- Stores in SurrealDB for reliability

See: [services/cursor-docs/README.md](../../services/cursor-docs/README.md)

## ❌ What Won't Fix It

| "Fix" | Why It Won't Work |
|-------|-------------------|
| Reinstalling Cursor | Problem is server-side |
| Clearing cache | Problem is server-side |
| Changing NixOS config | Problem is server-side |
| Different Cursor version | All versions affected |
| Network diagnostics | Your network is fine |
| Firewall changes | Not a local issue |
| Different browser/proxy | Cursor's servers do the crawling |

## 📚 References

### Forum Threads (50+ reports)

- [Doc Indexing Failed](https://forum.cursor.com/t/doc-indexing-failed/31605) - Dec 2024, 26 replies
- [Document Indexing Fails After 0.43.5](https://forum.cursor.com/t/document-indexing-fails-after-latest-0-43-5-update/32563) - 44 replies
- [Adding Docs, Indexing keeps failing](https://forum.cursor.com/t/adding-docs-indexing-keeping-fails-after-a-bit/40670) - Has official response
- [Documentation indexing problems](https://forum.cursor.com/t/documentation-indexing-problems/20860) - Oct 2024

### Official Response

From **Dean Rie** (Cursor team member):

> "Hey, yes, despite the 'Indexing Failed' message, the documentation **should work**. This is an error we plan to fix. Also, you can submit a PR to us for the documentation you need."
>
> — https://forum.cursor.com/t/adding-docs-indexing-keeping-fails-after-a-bit/40670/4

### Cursor's Crawler Repository

https://github.com/getcursor/crawler

## 🎯 Our Solution: cursor-docs Service

Since Cursor's server-side indexing is unreliable, **nixos-cursor** provides a local alternative:

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                   cursor-docs (Local Alternative)                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐      ┌──────────────────────────────────────────┐  │
│  │  User adds  │      │          Elixir Scraper Service          │  │
│  │  URL via    │─────▶│  - Headless browser (Playwright)         │  │
│  │  MCP/CLI    │      │  - JavaScript rendering ✅               │  │
│  └─────────────┘      │  - Rate limit handling ✅                │  │
│                       │  - Retry with backoff ✅                 │  │
│                       │  - Detailed error reporting ✅           │  │
│                       └──────────────────┬───────────────────────┘  │
│                                          │                          │
│                                          ▼                          │
│                       ┌──────────────────────────────────────────┐  │
│                       │          SurrealDB Storage               │  │
│                       │  - Local, reliable, queryable            │  │
│                       │  - Full-text search                      │  │
│                       │  - P2P sync capable                      │  │
│                       └──────────────────┬───────────────────────┘  │
│                                          │                          │
│                                          ▼                          │
│  ┌─────────────┐      ┌──────────────────────────────────────────┐  │
│  │  @docs in   │◄─────│          MCP Server Interface            │  │
│  │  Cursor     │      │  - search_docs(query)                    │  │
│  │  chat       │      │  - add_docs(url)                         │  │
│  └─────────────┘      │  - list_docs()                           │  │
│                       └──────────────────────────────────────────┘  │
│                                                                     │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  ALL LOCAL - No dependency on Cursor's broken servers               │
└─────────────────────────────────────────────────────────────────────┘
```

### Quality Targets

| Metric | Cursor's System | cursor-docs |
|--------|-----------------|-------------|
| Coverage | ~50% success | **100% target** |
| Quality | Varies widely | **80%+ of Cursor's best** |
| Reliability | Unpredictable | **Guaranteed (local)** |
| Error Info | None | **Detailed logs** |
| JS Rendering | ❌ No | **✅ Yes (Playwright)** |

### Getting Started

```bash
# Start the cursor-docs service
systemctl --user start cursor-docs

# Add documentation
cursor-docs add https://docs.example.com/

# Search
cursor-docs search "authentication"

# Or use via MCP in Cursor chat
@cursor-docs search authentication
```

See full documentation: [services/cursor-docs/README.md](../../services/cursor-docs/README.md)

---

## 📝 TL;DR

1. **The @docs indexing failures are Cursor's problem**, not yours
2. **All platforms and versions are affected** - it's server-side
3. **Try using docs anyway** - they might partially work
4. **Use our cursor-docs alternative** for reliable local indexing
5. **Don't waste time** debugging your local setup - it's fine

---

*Last Updated: December 15, 2025*
*nixos-cursor version: 0.2.1*

