# Cursor Chat Sync Architecture

> **Goal**: Sync Cursor IDE chat history across devices with two modes:
> 1. **Self-hosted server** - Central hub with Cursor Studio web UI
> 2. **Peer-to-peer** - Direct device sync for serverless setups

**Status**: Design Phase  
**Database**: SurrealDB (multi-model, real-time sync, Rust-native)  
**Languages**: Rust (core library, P2P daemon), Elixir (server), TypeScript (web UI)

---

## 🎯 Design Principles

1. **User-Scalable**: Normal dev can set up in <5 minutes
2. **Zero External Dependencies**: No cloud services, no subscriptions
3. **Offline-First**: Works without network, syncs when available
4. **Conflict-Free**: CRDT-based merge, no manual conflict resolution
5. **Privacy-First**: End-to-end encryption optional, data never leaves your control
6. **Incremental**: Sync deltas, not full dumps

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER'S DEVICES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌───────────────────┐  │
│  │     Obsidian         │  │    neon-laptop       │  │    framework      │  │
│  │  ┌───────────────┐   │  │  ┌───────────────┐   │  │  ┌─────────────┐  │  │
│  │  │  Cursor IDE   │   │  │  │  Cursor IDE   │   │  │  │ Cursor IDE  │  │  │
│  │  │  (SQLite)     │   │  │  │  (SQLite)     │   │  │  │ (SQLite)    │  │  │
│  │  └───────┬───────┘   │  │  └───────┬───────┘   │  │  └──────┬──────┘  │  │
│  │          │           │  │          │           │  │         │         │  │
│  │          ▼           │  │          ▼           │  │         ▼         │  │
│  │  ┌───────────────┐   │  │  ┌───────────────┐   │  │  ┌─────────────┐  │  │
│  │  │ cursor-sync   │   │  │  │ cursor-sync   │   │  │  │cursor-sync  │  │  │
│  │  │   daemon      │   │  │  │   daemon      │   │  │  │  daemon     │  │  │
│  │  │ (Rust+Surreal)│   │  │  │ (Rust+Surreal)│   │  │  │(Rust+Surreal│  │  │
│  │  └───────┬───────┘   │  │  └───────┬───────┘   │  │  └──────┬──────┘  │  │
│  │          │           │  │          │           │  │         │         │  │
│  └──────────┼───────────┘  └──────────┼───────────┘  └─────────┼─────────┘  │
│             │                         │                        │            │
└─────────────┼─────────────────────────┼────────────────────────┼────────────┘
              │                         │                        │
              │         ┌───────────────┴────────────────┐       │
              │         │                                │       │
              ▼         ▼                                ▼       ▼
     ┌────────────────────────────┐              ┌───────────────────────────┐
     │  MODE A: P2P (libp2p)      │              │  MODE B: Self-Hosted Hub  │
     │  ┌──────────────────────┐  │              │  ┌─────────────────────┐  │
     │  │ mDNS local discovery │  │              │  │  pi-server / VPS    │  │
     │  │ DHT for remote peers │  │              │  │  ┌───────────────┐  │  │
     │  │ NAT hole punching    │  │              │  │  │ Cursor Studio │  │  │
     │  │ Direct encrypted     │  │              │  │  │ Server        │  │  │
     │  │ device-to-device     │  │              │  │  │ (Elixir)      │  │  │
     │  └──────────────────────┘  │              │  │  └───────┬───────┘  │  │
     └────────────────────────────┘              │  │          │          │  │
                                                 │  │  ┌───────▼───────┐  │  │
                                                 │  │  │  SurrealDB    │  │  │
                                                 │  │  │  (Central)    │  │  │
                                                 │  │  └───────────────┘  │  │
                                                 │  │          │          │  │
                                                 │  │  ┌───────▼───────┐  │  │
                                                 │  │  │  Web UI       │  │  │
                                                 │  │  │  (Search,     │  │  │
                                                 │  │  │   Browse,     │  │  │
                                                 │  │  │   Export)     │  │  │
                                                 │  │  └───────────────┘  │  │
                                                 │  └─────────────────────┘  │
                                                 └───────────────────────────┘
```

---

## 📦 Component Breakdown

### 1. `cursor-chat-lib` (Rust Crate)

**Purpose**: Extract, transform, and sync chat data from Cursor's SQLite

```rust
// Core data structures
pub struct Conversation {
    pub id: Ulid,                    // Universally unique, sortable
    pub device_id: DeviceId,         // Origin device
    pub workspace: Option<String>,   // Workspace path hash
    pub title: Option<String>,       // Auto-generated or user-set
    pub messages: Vec<Message>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub vector_clock: VectorClock,   // For CRDT merge
}

pub struct Message {
    pub id: Ulid,
    pub role: Role,                  // User, Assistant, System, Tool
    pub content: String,
    pub model: Option<String>,       // claude-3.5-sonnet, gpt-4, etc.
    pub tokens: Option<TokenCount>,
    pub tool_calls: Vec<ToolCall>,
    pub attachments: Vec<Attachment>,
    pub timestamp: DateTime<Utc>,
}

pub struct DeviceId(pub [u8; 16]);   // Random, persisted per device

// Core traits
pub trait ChatStore {
    async fn get_conversation(&self, id: &Ulid) -> Result<Conversation>;
    async fn list_conversations(&self, filter: ConversationFilter) -> Result<Vec<ConversationMeta>>;
    async fn upsert_conversation(&self, conv: &Conversation) -> Result<()>;
    async fn search(&self, query: &str, limit: usize) -> Result<Vec<SearchResult>>;
    async fn merge(&self, remote: &Conversation) -> Result<MergeResult>;
}

// Implementations
pub struct CursorSqliteStore;    // Read from Cursor's state.vscdb
pub struct SurrealStore;         // Our sync-capable store
```

**Key Features:**
- Read-only access to Cursor's SQLite (never corrupt original)
- ULID-based IDs (timestamp + random, sortable)
- Vector clocks for conflict-free merge
- Efficient delta sync (only changed conversations)

### 2. `cursor-sync` (Rust Daemon)

**Purpose**: Background service that syncs local SurrealDB with peers/server

```rust
// Configuration
pub struct SyncConfig {
    pub mode: SyncMode,
    pub device_name: String,
    pub sync_interval: Duration,
    pub cursor_data_paths: Vec<PathBuf>,
}

pub enum SyncMode {
    /// P2P only - discover peers on local network + optionally DHT
    PeerToPeer {
        enable_mdns: bool,          // Local network discovery
        enable_dht: bool,           // Internet-wide via DHT
        bootstrap_peers: Vec<Multiaddr>,
    },
    /// Server mode - connect to central Cursor Studio instance
    Server {
        url: Url,                   // https://cursor.yourdomain.com
        api_key: Option<String>,    // Optional auth
    },
    /// Hybrid - P2P + Server fallback
    Hybrid {
        server: ServerConfig,
        p2p: P2PConfig,
    },
}
```

**Sync Protocol:**
```
1. Watch Cursor SQLite for changes (inotify/FSEvents)
2. Extract new/modified conversations to SurrealDB
3. Calculate delta since last sync
4. Push delta to peers/server
5. Pull remote deltas
6. Merge using CRDT rules
7. Optionally write back to Cursor SQLite (for search in IDE)
```

### 3. `cursor-studio-server` (Elixir/Phoenix)

**Purpose**: Central hub with web UI, API, and aggregated search

```elixir
# Main application supervisor
defmodule CursorStudio.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Web endpoint
      CursorStudioWeb.Endpoint,
      
      # SurrealDB connection pool
      {CursorStudio.Repo, []},
      
      # Device connection manager
      CursorStudio.DeviceManager,
      
      # Real-time sync coordinator
      CursorStudio.SyncCoordinator,
      
      # Search indexer
      CursorStudio.SearchIndexer,
      
      # Background jobs (cleanup, analytics)
      {Oban, Application.fetch_env!(:cursor_studio, Oban)}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**API Endpoints:**
```
POST   /api/v1/sync           # Push conversation deltas
GET    /api/v1/sync           # Pull conversation deltas since timestamp
GET    /api/v1/conversations  # List all conversations (paginated)
GET    /api/v1/search         # Full-text search across all chats
WS     /api/v1/live           # Real-time sync via WebSocket
```

**Web UI Features:**
- 📊 Dashboard (total chats, tokens used, device status)
- 🔍 Full-text search across ALL conversations
- 📁 Browse by workspace/project
- 📱 Device management (see all connected devices)
- 📤 Export (JSON, Markdown, PDF)
- 🔐 Optional E2E encryption management

### 4. P2P Layer (libp2p)

**Purpose**: Direct device-to-device sync without central server

**Discovery Methods:**
1. **mDNS** - Automatic on local network (same WiFi)
2. **DHT** - Find peers across internet via distributed hash table
3. **Manual** - Add peer by ID/address

**Protocol:**
```
/cursor-sync/1.0.0
  - Handshake: Exchange device IDs, vector clocks
  - Delta Request: "Give me changes since vector clock X"
  - Delta Response: Stream of conversation deltas
  - Conflict Resolution: CRDT merge (last-write-wins per message)
```

**NAT Traversal:**
- STUN for symmetric NAT
- Relay nodes (optional, can self-host)
- TCP hole punching

---

## 🗃️ Data Model (SurrealDB)

```sql
-- Device registration
DEFINE TABLE device SCHEMAFULL;
DEFINE FIELD name ON device TYPE string;
DEFINE FIELD public_key ON device TYPE string;  -- For E2E encryption
DEFINE FIELD last_seen ON device TYPE datetime;
DEFINE FIELD sync_cursor ON device TYPE object;  -- Vector clock

-- Conversations
DEFINE TABLE conversation SCHEMAFULL;
DEFINE FIELD device ON conversation TYPE record(device);
DEFINE FIELD workspace ON conversation TYPE option<string>;
DEFINE FIELD title ON conversation TYPE option<string>;
DEFINE FIELD created_at ON conversation TYPE datetime;
DEFINE FIELD updated_at ON conversation TYPE datetime;
DEFINE FIELD vector_clock ON conversation TYPE object;
DEFINE FIELD deleted ON conversation TYPE bool DEFAULT false;

-- Full-text search index
DEFINE ANALYZER conversation_analyzer TOKENIZERS blank,class FILTERS lowercase,snowball(english);
DEFINE INDEX conversation_search ON conversation FIELDS title SEARCH ANALYZER conversation_analyzer;

-- Messages (nested in conversation, but can query separately)
DEFINE TABLE message SCHEMAFULL;
DEFINE FIELD conversation ON message TYPE record(conversation);
DEFINE FIELD role ON message TYPE string ASSERT $value IN ['user', 'assistant', 'system', 'tool'];
DEFINE FIELD content ON message TYPE string;
DEFINE FIELD model ON message TYPE option<string>;
DEFINE FIELD tokens ON message TYPE option<object>;
DEFINE FIELD tool_calls ON message TYPE array;
DEFINE FIELD timestamp ON message TYPE datetime;

-- Full-text search on message content
DEFINE INDEX message_search ON message FIELDS content SEARCH ANALYZER conversation_analyzer;

-- Relationships (graph queries)
DEFINE TABLE references SCHEMAFULL;  -- conversation -> conversation
DEFINE TABLE mentions SCHEMAFULL;    -- message -> file/symbol
```

**Example Queries:**
```sql
-- Search across all conversations
SELECT * FROM conversation 
WHERE title @@ 'nixos cursor' 
OR id IN (SELECT conversation FROM message WHERE content @@ 'nixos cursor')
ORDER BY updated_at DESC
LIMIT 20;

-- Get all conversations from a device
SELECT * FROM conversation WHERE device = device:obsidian;

-- Find conversations about a specific file
SELECT conversation.* FROM mentions 
WHERE file = '/home/e421/nixos-cursor/flake.nix'
FETCH conversation;
```

---

## 🚀 User Setup Experience

### Mode A: P2P Only (Simplest)

```bash
# Install on each device (NixOS)
nix profile install github:Distracted-E421/nixos-cursor#cursor-sync

# Or via Home Manager
programs.cursor-sync = {
  enable = true;
  mode = "p2p";
  deviceName = "obsidian";  # Human-readable
};

# That's it! Devices on same network auto-discover
# For remote sync, exchange peer IDs once:
cursor-sync peer add <peer-id-from-other-device>
```

### Mode B: Self-Hosted Server

```bash
# On pi-server or VPS
docker compose up -d
# OR
nix run github:Distracted-E421/nixos-cursor#cursor-studio-server

# On each device
programs.cursor-sync = {
  enable = true;
  mode = "server";
  serverUrl = "https://cursor.yourdomain.com";
  # OR for local network:
  serverUrl = "http://pi-server:8080";
};
```

### Mode C: Hybrid (Best of Both)

```nix
programs.cursor-sync = {
  enable = true;
  mode = "hybrid";
  server = {
    url = "https://cursor.yourdomain.com";
    fallbackToP2P = true;  # If server unreachable
  };
  p2p = {
    enableMdns = true;     # Local network
    enableDht = false;     # Disable internet-wide (privacy)
  };
};
```

---

## 🔐 Security Model

### Device Authentication
- Each device generates Ed25519 keypair on first run
- Device ID = hash of public key
- Server/peers verify signatures on sync requests

### Optional E2E Encryption
- Conversations encrypted with device key before sync
- Server stores encrypted blobs (can't read content)
- Key exchange via QR code or manual ID exchange
- Supports key rotation

### Access Control (Server Mode)
- API keys for device authentication
- Optional user accounts with OAuth
- Per-workspace access control (future)

---

## 📊 Sync Protocol Details

### Delta Calculation

```rust
pub struct SyncDelta {
    pub from_clock: VectorClock,
    pub to_clock: VectorClock,
    pub conversations: Vec<ConversationDelta>,
}

pub struct ConversationDelta {
    pub id: Ulid,
    pub operation: DeltaOp,
}

pub enum DeltaOp {
    Create(Conversation),
    Update {
        messages_added: Vec<Message>,
        title_changed: Option<String>,
        // ... other fields
    },
    Delete,
}
```

### Conflict Resolution (CRDT)

**Rule: Last-Write-Wins at Message Level**

```rust
fn merge_conversations(local: &Conversation, remote: &Conversation) -> Conversation {
    let mut merged = local.clone();
    
    // Merge messages by ID, keep latest timestamp
    for remote_msg in &remote.messages {
        match merged.messages.iter_mut().find(|m| m.id == remote_msg.id) {
            Some(local_msg) => {
                if remote_msg.timestamp > local_msg.timestamp {
                    *local_msg = remote_msg.clone();
                }
            }
            None => {
                merged.messages.push(remote_msg.clone());
            }
        }
    }
    
    // Sort messages by timestamp
    merged.messages.sort_by_key(|m| m.timestamp);
    
    // Update vector clock
    merged.vector_clock = VectorClock::merge(&local.vector_clock, &remote.vector_clock);
    
    merged
}
```

---

## 📁 Project Structure

```
cursor-studio/
├── crates/
│   ├── cursor-chat-lib/       # Core Rust library
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── models.rs      # Data structures
│   │   │   ├── cursor_store.rs # Read from Cursor SQLite
│   │   │   ├── surreal_store.rs
│   │   │   ├── crdt.rs        # Vector clocks, merge
│   │   │   └── search.rs
│   │   └── Cargo.toml
│   │
│   ├── cursor-sync/           # Daemon
│   │   ├── src/
│   │   │   ├── main.rs
│   │   │   ├── config.rs
│   │   │   ├── watcher.rs     # File system watching
│   │   │   ├── p2p.rs         # libp2p networking
│   │   │   └── server.rs      # Server mode client
│   │   └── Cargo.toml
│   │
│   └── cursor-sync-cli/       # CLI tools
│       └── ...
│
├── server/                    # Elixir server
│   ├── lib/
│   │   ├── cursor_studio/
│   │   │   ├── application.ex
│   │   │   ├── sync_coordinator.ex
│   │   │   └── ...
│   │   └── cursor_studio_web/
│   │       ├── router.ex
│   │       ├── live/          # LiveView UI
│   │       └── ...
│   ├── mix.exs
│   └── ...
│
├── web/                       # Web UI (if separate from Phoenix)
│   └── ...
│
├── nix/
│   ├── cursor-sync.nix        # Daemon package
│   ├── cursor-studio.nix      # Server package
│   └── module.nix             # NixOS/Home Manager module
│
└── docker/
    ├── Dockerfile.server
    └── docker-compose.yml
```

---

## 🗓️ Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] `cursor-chat-lib`: Parse Cursor SQLite
- [ ] `cursor-chat-lib`: SurrealDB store implementation
- [ ] `cursor-chat-lib`: Basic CRDT merge
- [ ] Nix packaging for SurrealDB

### Phase 2: Local Sync (Week 3-4)
- [ ] `cursor-sync` daemon: File watching
- [ ] `cursor-sync` daemon: Local SurrealDB sync
- [ ] CLI for manual sync/export
- [ ] Home Manager module (local mode)

### Phase 3: P2P (Week 5-6)
- [ ] libp2p integration
- [ ] mDNS discovery
- [ ] Basic P2P sync protocol
- [ ] Peer management CLI

### Phase 4: Server (Week 7-8)
- [ ] Elixir Phoenix server scaffold
- [ ] SurrealDB connection
- [ ] Sync API endpoints
- [ ] Basic web UI (list conversations)

### Phase 5: Polish (Week 9-10)
- [ ] Full-text search UI
- [ ] Export functionality
- [ ] E2E encryption (optional)
- [ ] Docker packaging
- [ ] Documentation

---

## 🔗 Related Documents

- [CURSOR_MANAGER_REDESIGN.md](CURSOR_MANAGER_REDESIGN.md) - UI integration plans
- [SCRIPTING_ARCHITECTURE.md](SCRIPTING_ARCHITECTURE.md) - Language choices
- [NPM_SECURITY_ARCHITECTURE.md](NPM_SECURITY_ARCHITECTURE.md) - Security patterns

---

**Status**: 📝 Architecture Design Complete  
**Next**: Implement `cursor-chat-lib` Phase 1  
**Questions**: Should we prototype the SQLite parser first to validate data model?
