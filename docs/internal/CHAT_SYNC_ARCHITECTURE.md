# Cursor Chat Sync Architecture

> **Goal**: Sync Cursor IDE chat history across devices with two modes:
>
> 1. **Self-hosted server** - Central hub with native egui/GPUI interface
> 2. **Peer-to-peer** - Direct device sync for serverless setups

**Status**: Phase 1 - Implementation  
**Database**: SurrealDB (multi-model, real-time sync, Rust-native)  
**Languages**: Rust (everything - library, daemon, UI, server)  
**UI Framework**: egui (immediate mode, 60fps, single binary) or GPUI (future)

### Implementation Progress

| Component | Status | Notes |
|-----------|--------|-------|
| SQLite Parser | ✅ Implemented | Parses real databases (55 convs, 21K msgs) |
| Data Models | ✅ Implemented | Conversation, Message, Stats |
| CRDT Module | ✅ Implemented | VectorClock, DeviceId, merge logic |
| SurrealDB Store | ✅ Implemented | In-memory mode, schema, CRUD, merge |
| Sync Service | ✅ Implemented | Orchestrates full import pipeline |
| CLI Tool | ✅ Implemented | Local + server commands |
| Device ID | ✅ Implemented | Persists to ~/.config/cursor-studio/device_id |
| **Server Mode** | ✅ Implemented | REST API with axum (health, stats, conversations, sync) |
| **HTTP Client** | ✅ Implemented | Pull/push/sync from server |
| **P2P Networking** | ✅ Implemented | libp2p with mDNS, Noise encryption, request/response |
| **egui Integration** | ✅ Implemented | Sync panel in right sidebar (server + P2P status) |

### CLI Usage

```bash
# LOCAL OPERATIONS
cargo run --bin sync-cli -- import       # Import from Cursor SQLite
cargo run --bin sync-cli -- stats        # Show statistics
cargo run --bin sync-cli -- list         # List conversations
cargo run --bin sync-cli -- search <q>   # Search by title

# SERVER OPERATIONS
cargo run --bin sync-cli -- server-status [url]  # Check server health
cargo run --bin sync-cli -- server-stats [url]   # Get server statistics
cargo run --bin sync-cli -- pull [url]           # Pull from server
```

### Server Usage

```bash
# Start server with defaults (port 8420)
cargo run --bin sync-server

# Custom port + import local chats
cargo run --bin sync-server -- --import --port 8080

# Server API endpoints:
#   GET  /              - API info
#   GET  /health        - Health check
#   GET  /stats         - Server statistics
#   GET  /conversations - List conversations
#   GET  /conversations/:id - Get specific conversation
#   GET  /conversations/search?q=<query> - Search
#   POST /sync          - Bidirectional sync
#   POST /sync/push     - Push to server
#   GET  /sync/pull     - Pull from server
```

### P2P Usage

```bash
# Start P2P daemon with auto-discovery
cargo run --bin p2p-sync

# Custom port + import local chats
cargo run --bin p2p-sync -- --import --port 4001

# With custom device name
cargo run --bin p2p-sync -- --import --name "my-laptop"

# P2P features:
# - mDNS auto-discovery on local network
# - Noise encryption for secure connections
# - Request/response protocol for syncing
# - Automatic peer connection
```

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

### The Key Insight: One Binary, Three Modes

Instead of separate components, **cursor-studio** is a single Rust binary that operates in three modes:

1. **GUI Mode** (default) - Full egui interface for browsing/searching chats
2. **Daemon Mode** - Headless background sync
3. **Server Mode** - Accept connections from other devices (headless or with GUI)

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
│  │          │ inotify   │  │          │ inotify   │  │         │ FSEvent │  │
│  │          ▼           │  │          ▼           │  │         ▼         │  │
│  │  ┌───────────────┐   │  │  ┌───────────────┐   │  │  ┌─────────────┐  │  │
│  │  │cursor-studio  │   │  │  │cursor-studio  │   │  │  │cursor-studio│  │  │
│  │  │  (Rust+egui)  │   │  │  │  (Rust+egui)  │   │  │  │ (Rust+egui) │  │  │
│  │  │               │   │  │  │               │   │  │  │             │  │  │
│  │  │ ┌───────────┐ │   │  │  │ ┌───────────┐ │   │  │  │┌───────────┐│  │  │
│  │  │ │ SurrealDB │ │   │  │  │ │ SurrealDB │ │   │  │  ││ SurrealDB ││  │  │
│  │  │ │(embedded) │ │   │  │  │ │(embedded) │ │   │  │  ││(embedded) ││  │  │
│  │  │ └───────────┘ │   │  │  │ └───────────┘ │   │  │  │└───────────┘│  │  │
│  │  └───────┬───────┘   │  │  └───────┬───────┘   │  │  └──────┬──────┘  │  │
│  │          │           │  │          │           │  │         │         │  │
│  └──────────┼───────────┘  └──────────┼───────────┘  └─────────┼─────────┘  │
│             │                         │                        │            │
└─────────────┼─────────────────────────┼────────────────────────┼────────────┘
              │                         │                        │
              └─────────────────────────┼────────────────────────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │                                                   │
              ▼                                                   ▼
     ┌────────────────────────────┐              ┌────────────────────────────┐
     │  MODE A: P2P (libp2p)      │              │  MODE B: Central Hub       │
     │  ┌──────────────────────┐  │              │  ┌──────────────────────┐  │
     │  │ mDNS local discovery │  │              │  │  pi-server / VPS     │  │
     │  │ DHT for remote peers │  │              │  │  ┌────────────────┐  │  │
     │  │ NAT hole punching    │  │              │  │  │ cursor-studio  │  │  │
     │  │ QUIC transport       │  │              │  │  │ --server-mode  │  │  │
     │  │                      │  │              │  │  │                │  │  │
     │  │ Direct encrypted     │  │              │  │  │ ┌────────────┐ │  │  │
     │  │ device-to-device     │  │              │  │  │ │ SurrealDB  │ │  │  │
     │  └──────────────────────┘  │              │  │  │ │ (central)  │ │  │  │
     └────────────────────────────┘              │  │  │ └────────────┘ │  │  │
                                                 │  │  │                │  │  │
                                                 │  │  │ REST + gRPC    │  │  │
                                                 │  │  │ API only       │  │  │
                                                 │  │  └────────────────┘  │  │
                                                 │  └──────────────────────┘  │
                                                 │                            │
                                                 │  Optional: Run with GUI    │
                                                 │  for admin dashboard       │
                                                 └────────────────────────────┘
```

### Why Single Binary?

| Approach | Binaries | Dependencies | Complexity |
|----------|----------|--------------|------------|
| **Old (Web)** | Rust daemon + Elixir server + Node.js UI | 3 runtimes | High |
| **New (Native)** | Just `cursor-studio` | 1 binary | Low |

Benefits:

- **One thing to package** - Single Nix derivation
- **One thing to deploy** - Copy binary, done
- **Consistent UX** - Same interface everywhere
- **Offline-capable** - No server dependencies for local use
- **Resource efficient** - No Electron, no BEAM, no V8

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

### 3. `cursor-studio` Binary Modes

**Purpose**: Single binary that does everything

```rust
// CLI interface
#[derive(Parser)]
pub struct Args {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand)]
pub enum Command {
    /// Launch GUI (default if no command)
    Gui,
    
    /// Run as background daemon (no GUI)
    Daemon {
        /// Also accept incoming sync connections
        #[arg(long)]
        server: bool,
        
        /// Port for server mode
        #[arg(long, default_value = "7890")]
        port: u16,
    },
    
    /// Run as dedicated server (for pi-server/VPS)
    Server {
        #[arg(long, default_value = "0.0.0.0:7890")]
        bind: String,
        
        /// Show GUI admin dashboard (optional)
        #[arg(long)]
        gui: bool,
    },
    
    /// CLI operations
    Sync {
        #[command(subcommand)]
        action: SyncAction,
    },
    
    /// Export conversations
    Export {
        #[arg(long)]
        format: ExportFormat,
        
        #[arg(long)]
        output: PathBuf,
    },
}

#[derive(Subcommand)]
pub enum SyncAction {
    /// Sync now (one-shot)
    Now,
    /// Show sync status
    Status,
    /// Add a peer by ID
    AddPeer { peer_id: String },
    /// List known peers
    ListPeers,
}
```

**Usage Examples:**

```bash
# GUI mode (default)
cursor-studio

# Background daemon with P2P
cursor-studio daemon

# Background daemon that also accepts connections
cursor-studio daemon --server --port 7890

# Dedicated server on pi-server
cursor-studio server --bind 0.0.0.0:7890

# Server with admin GUI (for desktop server)
cursor-studio server --gui

# CLI operations
cursor-studio sync now
cursor-studio sync status
cursor-studio sync add-peer QmXyz...
cursor-studio export --format markdown --output ~/chats/
```

**egui Interface Features:**

- 📊 Dashboard (total chats, tokens used, device status)
- 🔍 Full-text search across ALL conversations (instant, local)
- 📁 Browse by workspace/project
- 📱 Device management (see connected peers/server)
- 📤 Export (JSON, Markdown, PDF)
- ⚙️ Settings (sync mode, encryption, appearance)
- 🔐 Optional E2E encryption key management

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

### Mode A: P2P Only (Simplest - No Server Needed)

```nix
# In home.nix or configuration.nix
programs.cursor-studio = {
  enable = true;
  sync = {
    enable = true;
    mode = "p2p";
    deviceName = "obsidian";  # Human-readable
  };
};

# That's it! Devices on same network auto-discover via mDNS
```

```bash
# Or install directly
nix profile install github:Distracted-E421/nixos-cursor#cursor-studio

# Run the GUI
cursor-studio

# Add remote peer (one-time, for non-local devices)
cursor-studio sync add-peer Qm...peerIdFromOtherDevice
```

### Mode B: Self-Hosted Server

```bash
# On pi-server or VPS - single command
cursor-studio server --bind 0.0.0.0:7890

# Or as systemd service (NixOS)
services.cursor-studio-server = {
  enable = true;
  bind = "0.0.0.0:7890";
};
```

```nix
# On each device
programs.cursor-studio = {
  enable = true;
  sync = {
    enable = true;
    mode = "server";
    serverUrl = "http://pi-server:7890";
    # OR with Tailscale:
    serverUrl = "http://pi-server.tailnet-name.ts.net:7890";
  };
};
```

### Mode C: Hybrid (Best of Both)

```nix
programs.cursor-studio = {
  enable = true;
  sync = {
    enable = true;
    mode = "hybrid";
    server = {
      url = "http://pi-server:7890";
      fallbackToP2P = true;  # If server unreachable, use P2P
    };
    p2p = {
      enableMdns = true;     # Auto-discover on local network
      enableDht = false;     # Disable internet-wide (privacy)
    };
  };
};
```

### One-Line Docker Deploy (For Non-NixOS)

```bash
# Pull and run (no Nix required)
docker run -d --name cursor-studio-server \
  -p 7890:7890 \
  -v cursor-data:/data \
  ghcr.io/distracted-e421/cursor-studio:latest \
  server --bind 0.0.0.0:7890
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
cursor-studio-egui/
├── Cargo.toml                 # Workspace root
├── Cargo.lock                 # Locked deps (reproducible)
├── flake.nix                  # Nix packaging
├── home-manager-module.nix    # NixOS integration
│
├── src/
│   ├── main.rs                # Entry point, CLI parsing
│   ├── app.rs                 # egui application state
│   │
│   ├── ui/                    # egui interface
│   │   ├── mod.rs
│   │   ├── dashboard.rs       # Main dashboard view
│   │   ├── conversation.rs    # Conversation browser
│   │   ├── search.rs          # Search interface
│   │   ├── settings.rs        # Configuration UI
│   │   ├── devices.rs         # Peer/server management
│   │   └── theme.rs           # VS Code theme support
│   │
│   ├── chat/                  # Chat data handling
│   │   ├── mod.rs
│   │   ├── models.rs          # Conversation, Message structs
│   │   ├── cursor_parser.rs   # Parse Cursor's SQLite
│   │   ├── surreal.rs         # SurrealDB operations
│   │   └── crdt.rs            # Vector clocks, merge logic
│   │
│   ├── sync/                  # Synchronization
│   │   ├── mod.rs
│   │   ├── watcher.rs         # File system watching (inotify/FSEvents)
│   │   ├── protocol.rs        # Sync protocol (deltas)
│   │   ├── p2p.rs             # libp2p networking
│   │   └── server.rs          # Server mode (accept connections)
│   │
│   ├── export/                # Export functionality
│   │   ├── mod.rs
│   │   ├── markdown.rs
│   │   ├── json.rs
│   │   └── pdf.rs             # Optional, via printpdf
│   │
│   └── security/              # Security features (existing)
│       ├── mod.rs
│       ├── scanner.rs
│       └── blocklist.rs
│
├── assets/                    # Embedded resources
│   ├── icons/
│   └── fonts/
│
└── tests/
    ├── cursor_parser_test.rs
    ├── sync_protocol_test.rs
    └── crdt_test.rs
```

### Key Dependencies (Cargo.toml)

```toml
[package]
name = "cursor-studio"
version = "0.3.0"

[dependencies]
# UI
eframe = "0.29"
egui = "0.29"
egui_extras = { version = "0.29", features = ["image"] }

# Database
surrealdb = { version = "2", features = ["kv-rocksdb"] }  # Embedded mode
rusqlite = "0.32"  # Read Cursor's SQLite

# Async runtime
tokio = { version = "1", features = ["full"] }

# P2P networking
libp2p = { version = "0.54", features = [
    "tokio",
    "dns",
    "mdns",
    "noise",
    "tcp",
    "quic",
    "identify",
    "kad",  # DHT
] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# IDs
ulid = "1"

# File watching
notify = "6"

# CLI
clap = { version = "4", features = ["derive"] }

# Crypto (for E2E encryption)
ed25519-dalek = "2"
x25519-dalek = "2"
chacha20poly1305 = "0.10"

# Logging
tracing = "0.1"
tracing-subscriber = "0.3"

[features]
default = ["gui"]
gui = []           # Build with egui (can disable for server-only)
pdf-export = ["printpdf"]
```

---

## 🗓️ Implementation Roadmap

### Phase 1: Core Library (Week 1-2)

- [ ] Parse Cursor SQLite (`cursor_parser.rs`)
  - [ ] Read `bubbleId:*` entries from cursorDiskKV
  - [ ] Parse Lexical richText JSON
  - [ ] Extract conversations, messages, metadata
- [ ] Define data models (`models.rs`)
- [ ] SurrealDB embedded store (`surreal.rs`)
- [ ] Basic CRDT vector clocks (`crdt.rs`)

### Phase 2: egui Integration (Week 3-4)

- [ ] Conversation browser UI
- [ ] Full-text search with instant results
- [ ] File watching for live updates
- [ ] CLI commands (export, sync status)

### Phase 3: P2P Sync (Week 5-6)

- [ ] libp2p integration (`p2p.rs`)
- [ ] mDNS auto-discovery
- [ ] Sync protocol (delta-based)
- [ ] Peer management UI

### Phase 4: Server Mode (Week 7-8)

- [ ] Server mode (`--server`)
- [ ] Client connection to server
- [ ] Hybrid mode (P2P + server fallback)
- [ ] Device authentication

### Phase 5: Polish (Week 9-10)

- [ ] E2E encryption (optional feature)
- [ ] Export (Markdown, JSON, PDF)
- [ ] Home Manager module refinement
- [ ] systemd service for daemon mode
- [ ] Documentation and examples

---

## 🔗 Related Documents

- [CURSOR_MANAGER_REDESIGN.md](CURSOR_MANAGER_REDESIGN.md) - UI integration
- [cursor-studio-egui README](../../../cursor-studio-egui/README.md) - Current implementation

---

## 🎯 GPUI Future Path

egui is our immediate choice because:

- Already working in cursor-studio-egui
- Good enough performance (60fps)
- Single-file binary possible
- Well-documented

**GPUI consideration for v2.0:**

- Even faster (GPU-accelerated)
- Zed-proven at scale
- Better text rendering
- More complex to set up (pre-1.0)

Decision point: After v1.0 stable, evaluate GPUI migration if performance needs increase.

---

**Status**: 📝 Architecture Refined (All-Rust, Native UI)  
**Next**: Implement Cursor SQLite parser to validate data extraction  
**Milestone**: v0.3.0 with chat sync (P2P + Server)
