# Data Pipeline Control Roadmap

> **⚠️ SPECULATIVE DOCUMENT**
> This document outlines ambitious research goals for v0.3.0 and v0.4.0.
> Feasibility depends on Cursor's undocumented internals and may require experimentation.

## 🎯 Global Objective

**Total control of the data pipeline** - Document, monitor, and manipulate the data flow in Cursor to and from the agent with real-time visibility and reproducible state management.

---

## 📊 Research Findings Summary

### Database Structure (Confirmed)

| Location | Tables | Purpose |
|----------|--------|---------|
| `~/.config/Cursor/User/globalStorage/state.vscdb` | `ItemTable`, `cursorDiskKV` | Global conversations, settings |
| `~/.config/Cursor/User/workspaceStorage/{hash}/state.vscdb` | `ItemTable`, `cursorDiskKV` | Workspace-specific data |

### Key Data Types Discovered

| Key Pattern | Content | Size (this instance) |
|-------------|---------|---------------------|
| `bubbleId:{composer}:{bubble}` | Individual messages (JSON) | **25,105 messages** |
| `checkpointId:{composer}:{id}` | Undo/redo checkpoints | Variable |
| `codeBlockDiff:{composer}:{id}` | Code change diffs | Variable |
| `composerData:{uuid}` (in `composer.composerData`) | Conversation metadata | All conversations |

### Message Structure (Confirmed Fields)

```json
{
  "_v": 3,
  "type": 1,
  "bubbleId": "uuid",
  "isAgentic": true,
  "docsReferences": [],      // <-- @docs citations
  "webReferences": [],       // <-- @web citations  
  "aiWebSearchResults": [],  // <-- AI search results
  "toolResults": [],         // <-- MCP tool outputs
  "allThinkingBlocks": [],   // <-- Claude <thinking> blocks
  "mcpDescriptors": [],      // <-- MCP server metadata
  "supportedTools": [],      // <-- Available tools list
  // ... many more fields
}
```

---

## 🔮 Speculative Objectives

### Phase 1: Conversation Sync & Export (v0.3.0)

#### Objective 1.1: External Database Redundancy

**Goal:** Sync conversations to a separate database for redundancy and portability.

**Approach (SPECULATIVE):**
```
┌─────────────────────┐     ┌──────────────────────┐
│  Cursor state.vscdb │────▶│  cursor-studio sync  │
│  (source of truth)  │     │  service (daemon)    │
└─────────────────────┘     └──────────┬───────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
            ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
            │  SurrealDB    │  │   SQLite      │  │   JSON Files  │
            │  (P2P sync)   │  │   (portable)  │  │   (git-able)  │
            └───────────────┘  └───────────────┘  └───────────────┘
```

**Implementation Strategy:**
1. **File watcher on state.vscdb** - Detect changes in real-time
2. **Incremental sync** - Only sync changed bubbles/composers
3. **Conflict resolution** - Handle multi-device scenarios
4. **Schema normalization** - Transform blob JSON into relational structure

**Technical Challenges:**
- SQLite locking (Cursor may hold locks)
- Change detection (no WAL mode access guaranteed)
- Schema evolution across Cursor versions

**Feasibility: HIGH** - We can read the database, sync is straightforward.

#### Objective 1.2: Conversation Viewer/Browser

**Goal:** View and interact with synced conversations outside Cursor.

**Implementation:**
```rust
// cursor-studio-egui additions
struct ConversationBrowser {
    conversations: Vec<Conversation>,
    selected: Option<usize>,
    search_query: String,
    filter_by_date: Option<DateRange>,
    filter_by_model: Option<String>,
}

impl ConversationBrowser {
    fn load_from_external_db(&mut self, db_path: &Path) -> Result<()> {
        // Load from our synced database, not Cursor's
    }
    
    fn render_conversation(&self, ui: &mut Ui, conv: &Conversation) {
        // Rich rendering with thinking blocks, tool calls, etc.
    }
}
```

**Feasibility: HIGH** - Direct extension of current cursor-studio work.

---

### Phase 2: Docs System Control (v0.3.0 - v0.4.0)

#### Objective 2.1: Discover Docs Storage Location

**Status: PARTIALLY EXPLORED**

**What We Know:**
- `docsReferences` field exists in messages (empty in sampled data)
- `selectedDocs` in context fields
- No local cache of docs content found
- Likely server-side indexed/stored

**Speculation:**
The @docs system probably works like this:
```
┌─────────────────┐     ┌───────────────────┐     ┌─────────────────┐
│  User adds URL  │────▶│  Cursor servers   │────▶│  Indexed docs   │
│  to @docs       │     │  crawl & embed    │     │  (embeddings)   │
└─────────────────┘     └───────────────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌───────────────────┐
                        │  During prompt,   │
                        │  retrieve chunks  │
                        └───────────────────┘
```

**Research Tasks:**
1. [ ] Add @docs to a conversation and examine the `selectedDocs` field
2. [ ] Monitor network traffic during @docs usage
3. [ ] Check if docs are cached in extension storage
4. [ ] Look for Cursor docs API endpoints

**Feasibility: MEDIUM** - Requires more research, may be server-only.

#### Objective 2.2: Bulk Docs Injection

**Goal:** Inject new documentation links in bulk for easier scraping.

**Speculative Approach A: Settings File Manipulation**
```json
// Possibly in ~/.config/Cursor/User/settings.json or globalStorage
{
  "cursor.docs": [
    { "url": "https://docs.example.com/", "name": "Example Docs" },
    { "url": "https://api.another.com/", "name": "Another API" }
  ]
}
```

**Speculative Approach B: API Interception**
```rust
// Create local proxy/MCP server that provides docs
struct DocsInjectionServer {
    docs: Vec<DocSource>,
}

impl DocsInjectionServer {
    fn handle_query(&self, query: &str) -> Vec<DocChunk> {
        // Search local docs, return chunks
    }
}
```

**Speculative Approach C: Extension-based**
```typescript
// VS Code extension that provides @docs-like functionality
vscode.commands.registerCommand('cursorDocs.addBulk', async () => {
    const urls = await readBulkDocsFile();
    for (const url of urls) {
        await cursorDocsApi.add(url);  // Hypothetical API
    }
});
```

**Feasibility: LOW-MEDIUM** - Depends on Cursor's docs API being accessible.

#### Objective 2.3: Separate Docs System

**Goal:** Build independent documentation system if injection fails.

**Architecture (SPECULATIVE):**
```
┌─────────────────────────────────────────────────────────────────┐
│                    cursor-docs-server (MCP)                      │
├──────────────────┬──────────────────┬──────────────────────────┤
│   Web Scraper    │  Local Indexer   │   Embedding Generator    │
│   (jina-reader)  │  (tantivy/meilisearch)  │  (ollama embed)     │
└──────────────────┴──────────────────┴──────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        MCP Tools                                 │
├─────────────────────────────────────────────────────────────────┤
│  search_docs(query) → Relevant chunks with citations            │
│  add_docs(url) → Scrape and index new documentation             │
│  list_docs() → Show indexed documentation sources               │
│  refresh_docs(id) → Re-scrape and update                        │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation:**
1. **Scraping:** Use jina-reader or similar to get clean text
2. **Chunking:** Split into context-appropriate chunks
3. **Embedding:** Use local Ollama for embeddings (Arc A770!)
4. **Storage:** SurrealDB or Meilisearch for vector search
5. **MCP Interface:** Expose as MCP tools for agent use

**Feasibility: HIGH** - Doesn't depend on Cursor internals.

---

### Phase 3: Data Flow Monitoring (v0.3.0)

#### Objective 3.1: Real-time Context Visualization

**Goal:** See exactly what data flows to the agent in real-time.

**Implementation (SPECULATIVE):**
```
┌────────────────────────────────────────────────────────────────┐
│                  cursor-studio-monitor                          │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Rules Loaded │  │ Files Added  │  │ MCP Tools Called     │  │
│  │ ───────────  │  │ ───────────  │  │ ───────────────────  │  │
│  │ • safety.mdc │  │ • main.rs    │  │ • read_file(x3)      │  │
│  │ • git.mdc    │  │ • lib.rs     │  │ • grep(x1)           │  │
│  │ • nix.mdc    │  │ + context    │  │ • memory_store(x2)   │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Token Budget                             │ │
│  │  ████████████████████████░░░░░░░░░░░░  67% (201k/300k)     │ │
│  │                                                             │ │
│  │  Rules: 45k  Files: 120k  History: 36k                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

**Data Sources:**
1. **Watch state.vscdb** for new bubble creation
2. **Parse bubble JSON** for context fields
3. **Track MCP calls** via tool_results
4. **Estimate tokens** from content lengths

**Feasibility: HIGH** - All data is in the database.

#### Objective 3.2: Data Flow Diagram Generation

**Goal:** Auto-generate D2 diagrams showing data flow.

```d2
# Auto-generated from conversation analysis
direction: right

user_input: "User Query" {
  shape: document
}

context: "Context Assembly" {
  rules: ".cursor/rules/*" {
    shape: page
  }
  files: "@-mentioned files" {
    shape: page
  }
  codebase: "Semantic search" {
    shape: cylinder
  }
}

mcp_tools: "MCP Tools" {
  filesystem: "Filesystem"
  memory: "Memory"
  github: "GitHub"
}

agent: "Claude Agent" {
  shape: hexagon
}

user_input -> context -> agent
agent -> mcp_tools
mcp_tools -> agent: "tool results"
```

**Feasibility: HIGH** - Combine existing D2MCP with data parsing.

---

### Phase 4: Reproducible Workspace (v0.4.0)

#### Objective 4.1: Workspace State Snapshot

**Goal:** Capture complete workspace state for instant reproduction.

**Snapshot Contents:**
```yaml
# workspace-snapshot.yaml
version: "1.0"
created: "2025-12-06T12:00:00Z"
workspace: "/home/e421/nixos-cursor"

# Git state
git:
  branch: "main"
  commit: "abc123..."
  dirty_files: []
  
# Cursor rules (content hashes + content)
rules:
  - path: ".cursor/rules/safety.mdc"
    hash: "sha256:..."
    content: |
      # Safety Rules...

# MCP configuration
mcp:
  servers:
    - id: "filesystem"
      enabled: true
      config: {...}

# Extension state
extensions:
  - id: "ms-python.python"
    version: "2025.6.1"
    settings: {...}

# Open conversations (references)
conversations:
  - id: "abc-123"
    name: "Current work"
    synced_to: "external-db"
```

**Restore Process:**
1. Clone git repo to specified commit
2. Apply cursor rules
3. Configure MCP servers
4. Restore extension settings
5. Optionally restore conversation context

**Feasibility: MEDIUM** - Git + rules are easy, extensions/conversations harder.

#### Objective 4.2: Atomic Workspace Rebuild

**Goal:** Rebuild workspace anywhere with Nix-level reproducibility.

**Implementation:**
```nix
# flake.nix addition
{
  outputs = { self, nixpkgs, ... }: {
    # Workspace definition
    workspaces.nixos-cursor = {
      path = ./.; 
      rules = ./.cursor/rules;
      mcp = ./mcp.json;
      snapshot = ./workspace-snapshot.yaml;
    };
    
    # Rebuild command
    apps.rebuild-workspace = {
      type = "app";
      program = "${self.packages.cursor-studio}/bin/cursor-studio-cli";
      args = ["workspace" "restore" "--from" "workspace-snapshot.yaml"];
    };
  };
}
```

**Feasibility: MEDIUM** - Nix handles most, cursor state is the challenge.

---

### Phase 5: Data Injection to Agent (v0.4.0+)

#### Objective 5.1: Context Injection via MCP

**Goal:** Inject arbitrary context to the agent through MCP.

**Implementation:**
```rust
// cursor-context-mcp server
struct ContextInjectionServer {
    context_store: HashMap<String, ContextItem>,
}

#[mcp_tool]
fn inject_context(&self, key: &str, content: &str, priority: Priority) -> Result<()> {
    // Store context item
    self.context_store.insert(key, ContextItem {
        content: content.to_string(),
        priority,
        injected_at: Utc::now(),
    });
    Ok(())
}

#[mcp_tool]  
fn get_injected_context(&self, query: &str) -> Vec<ContextItem> {
    // Return relevant injected context
    self.search_context(query)
}
```

**Agent-side:**
The agent would call `get_injected_context` at the start of relevant conversations, effectively "remembering" injected data.

**Feasibility: HIGH** - This is what MCP is designed for.

#### Objective 5.2: Conversation Continuation

**Goal:** Inject previous conversation context into new sessions.

**Approach:**
```
┌─────────────────────┐     ┌──────────────────────┐
│  Old Conversation   │────▶│  context-summary     │
│  (from external DB) │     │  generator           │
└─────────────────────┘     └──────────┬───────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │  MCP inject_context  │
                            │  tool                │
                            └──────────┬───────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │  New Conversation    │
                            │  (with prior context)│
                            └──────────────────────┘
```

**Feasibility: MEDIUM** - Requires good summarization.

---

## 📈 Implementation Timeline

### v0.3.0 (Target: Q1 2025)

| Feature | Priority | Feasibility | Status |
|---------|----------|-------------|--------|
| Conversation sync to external DB | P0 | HIGH | 🟡 Planned |
| Conversation browser GUI | P0 | HIGH | 🟡 Planned |
| Real-time context monitor | P1 | HIGH | 🟡 Planned |
| MCP-based docs server | P1 | HIGH | 🟡 Planned |
| Data flow diagram gen | P2 | HIGH | 🟡 Planned |

### v0.4.0 (Target: Q2 2025)

| Feature | Priority | Feasibility | Status |
|---------|----------|-------------|--------|
| Workspace snapshots | P0 | MEDIUM | ⚪ Not started |
| Atomic workspace rebuild | P1 | MEDIUM | ⚪ Not started |
| Context injection MCP | P1 | HIGH | ⚪ Not started |
| Docs bulk injection | P2 | LOW-MEDIUM | ⚪ Not started |
| Conversation continuation | P2 | MEDIUM | ⚪ Not started |

---

## 🔬 Research Tasks

### Immediate (Before v0.3.0 Implementation)

1. [ ] **Test @docs integration** - Add docs, examine database changes
2. [ ] **Network traffic analysis** - What APIs does Cursor call for docs?
3. [ ] **SQLite locking behavior** - Can we read while Cursor writes?
4. [ ] **Extension API exploration** - What can VS Code extensions access?

### Ongoing

1. [ ] **Monitor Cursor updates** - Track schema changes
2. [ ] **Community research** - Check if others have documented this
3. [ ] **Performance testing** - Can we sync without impacting Cursor?

---

## 🧪 Proof of Concept Scripts

### POC 1: Sync to External SQLite

```python
#!/usr/bin/env python3
"""Sync Cursor conversations to external SQLite database."""
import sqlite3
import json
from pathlib import Path
from watchfiles import watch

CURSOR_DB = Path.home() / ".config/Cursor/User/globalStorage/state.vscdb"
EXTERNAL_DB = Path.home() / ".local/share/cursor-studio/conversations.db"

def init_external_db():
    conn = sqlite3.connect(EXTERNAL_DB)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            name TEXT,
            created_at INTEGER,
            updated_at INTEGER,
            data JSON
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT,
            type TEXT,
            content JSON,
            created_at INTEGER,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id)
        )
    """)
    return conn

def sync_conversations():
    cursor_conn = sqlite3.connect(f"file:{CURSOR_DB}?mode=ro", uri=True)
    external_conn = init_external_db()
    
    # Get all bubbles
    for row in cursor_conn.execute(
        "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'"
    ):
        key, value = row
        parts = key.split(":")
        conv_id, bubble_id = parts[1], parts[2]
        data = json.loads(value)
        
        external_conn.execute("""
            INSERT OR REPLACE INTO messages (id, conversation_id, type, content, created_at)
            VALUES (?, ?, ?, ?, ?)
        """, (bubble_id, conv_id, data.get("type"), json.dumps(data), data.get("createdAt")))
    
    external_conn.commit()
    print(f"Synced to {EXTERNAL_DB}")

if __name__ == "__main__":
    sync_conversations()
```

### POC 2: Context Monitor

```nu
#!/usr/bin/env nu
# Real-time context monitoring

def watch-cursor-context [] {
    loop {
        let latest = (
            sqlite3 ~/.config/Cursor/User/globalStorage/state.vscdb 
            "SELECT value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%' ORDER BY rowid DESC LIMIT 1"
            | from json
        )
        
        print $"Latest message context:"
        print $"  Files: ($latest.attachedCodeChunks | length)"
        print $"  Rules: ($latest.cursorRules | length)"  
        print $"  Tools: ($latest.toolResults | length)"
        print $"  Docs: ($latest.docsReferences | length)"
        
        sleep 2sec
    }
}
```

---

## 📚 Related Documents

- [CONTEXT_CAPTURE_DESIGN.md](CONTEXT_CAPTURE_DESIGN.md) - Detailed data structure documentation
- [CHAT_SYNC_ARCHITECTURE.md](CHAT_SYNC_ARCHITECTURE.md) - P2P sync architecture
- [../cursor-studio-egui/ROADMAP.md](../../cursor-studio-egui/ROADMAP.md) - cursor-studio roadmap

---

## ⚠️ Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cursor updates break parsing | HIGH | Version detection, graceful degradation |
| SQLite locking prevents reads | MEDIUM | Read-only mode, retry logic, copy-on-read |
| Docs are server-only | MEDIUM | Build independent docs MCP server |
| Performance impact on Cursor | LOW | Throttle sync, background daemon |
| Privacy concerns with export | LOW | Redaction options, encryption |

---

*Last updated: 2025-12-06*
*Status: SPECULATIVE - Research Phase*
