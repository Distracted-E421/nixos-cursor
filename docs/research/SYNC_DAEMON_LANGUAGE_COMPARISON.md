# Sync Daemon Language Comparison: Rust vs Elixir

**Date:** December 6, 2025  
**Purpose:** Determine optimal language for Cursor data sync daemon  
**Status:** ✅ DECIDED - Elixir with Named Pipes IPC

> **Decision:** Elixir chosen for multi-machine sync, hot reloading, and fault tolerance.  
> **IPC Method:** Named pipes (simpler than gRPC, lighter than sockets)  
> **Future:** Hybrid approach with Rust NIFs if performance requires

---

## 🎯 Use Case Requirements

The sync daemon needs to:
1. **Watch SQLite files** for changes (Cursor's `state.vscdb`)
2. **Sync conversations** to external database
3. **Handle concurrent operations** (multiple workspaces)
4. **Support hot reloading** for development iteration
5. **Integrate with cursor-studio** (egui Rust app)
6. **Run as background service** (long-running)
7. **Be fault-tolerant** (recover from errors gracefully)

---

## 📊 Head-to-Head Comparison

| Aspect | Rust | Elixir | Winner |
|--------|------|--------|--------|
| **Hot Reloading** | Limited (dylib) | Native OTP | **Elixir** ✅ |
| **cursor-studio Integration** | Native | IPC required | **Rust** ✅ |
| **SQLite Support** | rusqlite (excellent) | Ecto.SQLite3 (good) | **Rust** ✅ |
| **File Watching** | notify crate | FileSystem lib | Tie |
| **Concurrency** | Tokio async | BEAM processes | **Elixir** ✅ |
| **Fault Tolerance** | Manual impl | Built-in supervisors | **Elixir** ✅ |
| **Memory Usage** | Minimal | VM overhead | **Rust** ✅ |
| **Development Speed** | Slower | Faster | **Elixir** ✅ |
| **Performance** | Near-native | Good for I/O | **Rust** ✅ |
| **Single Binary** | Yes | Requires runtime | **Rust** ✅ |
| **Learning Curve** | You know it | New paradigm | **Rust** ✅ |

**Score: Rust 6 - Elixir 5**

---

## 🔥 Hot Reloading Deep Dive

### Elixir Hot Reloading

Elixir/OTP provides **true hot code swapping** at runtime:

```elixir
# In development - automatic reloading on file save
# In production - can upgrade modules without restart

defmodule SyncDaemon do
  use GenServer
  
  # State persists across code reloads!
  def handle_cast({:sync, workspace}, state) do
    # Logic changes reload without losing state
    {:noreply, %{state | last_sync: DateTime.utc_now()}}
  end
end
```

**Features:**
- ✅ Code changes reload automatically in dev (IEx)
- ✅ State persists across reloads
- ✅ Can upgrade running production systems
- ✅ Phoenix LiveReload built on this

**Limitations:**
- ❌ Requires OTP release for production hot upgrades
- ❌ Complex state migrations need careful handling

### Rust Hot Reloading

Rust hot reloading is **limited but possible**:

```rust
// Using hot-lib-reloader crate
#[hot_lib_reloader::hot_module(dylib = "sync_logic")]
mod sync_logic {
    #[hot_function]
    pub fn process_changes(changes: Vec<Change>) -> Result<()>;
}

// Main daemon stays running, dylib reloads
fn main() {
    loop {
        hot_lib_reloader::update_libs(); // Check for updates
        sync_logic::process_changes(changes)?;
    }
}
```

**Features:**
- ✅ Can reload logic in dynamic libraries
- ✅ Main process stays running
- ✅ Works in development

**Limitations:**
- ❌ Requires splitting code into dylibs
- ❌ Not all code can be hot-reloaded
- ❌ State management across reloads is manual
- ❌ Not commonly used in production
- ❌ Complexity overhead

---

## 🔗 Integration Analysis

### Rust Integration with cursor-studio

```rust
// Direct in-process communication - ZERO overhead
pub struct CursorStudio {
    sync_daemon: SyncDaemon,
    // ... 
}

impl CursorStudio {
    fn start_sync(&mut self) {
        self.sync_daemon.watch_databases();
        // Direct function calls, shared memory
    }
}
```

**Advantages:**
- Same process = no IPC overhead
- Shared data structures
- Single deployment artifact
- Type-safe API

### Elixir Integration with cursor-studio

```elixir
# Option 1: TCP/Unix socket IPC
{:ok, socket} = :gen_tcp.connect('localhost', 9999, [:binary])
:gen_tcp.send(socket, Jason.encode!(%{cmd: :sync, workspace: path}))

# Option 2: Named pipes
File.write!("/tmp/cursor-studio.pipe", Jason.encode!(message))

# Option 3: gRPC/Protocol Buffers
defmodule SyncService do
  use GRPC.Server, service: CursorStudio.Sync.Service
end
```

**Challenges:**
- IPC overhead and complexity
- Two processes to manage
- Serialization/deserialization
- Two deployment artifacts

---

## 🏗️ Architecture Options

### Option A: Pure Rust (Recommended for v1)

```
┌─────────────────────────────────────────────┐
│              cursor-studio                   │
│  ┌─────────────────────────────────────┐    │
│  │           SyncDaemon                 │    │
│  │  ┌──────────┐  ┌──────────────────┐ │    │
│  │  │ Watcher  │  │   Sync Engine    │ │    │
│  │  │ (notify) │─▶│   (rusqlite)     │ │    │
│  │  └──────────┘  └──────────────────┘ │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │         egui UI Components          │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

**Pros:**
- Single binary deployment
- Direct integration
- No IPC complexity
- You already know Rust

**Cons:**
- Limited hot reloading
- Manual fault tolerance

### Option B: Pure Elixir (Better DX)

```
┌───────────────────┐      IPC       ┌───────────────────┐
│   cursor-studio   │◀──────────────▶│   sync_daemon     │
│   (Rust/egui)     │                │   (Elixir/OTP)    │
│                   │                │                   │
│  • UI rendering   │                │  • File watching  │
│  • Settings       │                │  • DB sync        │
│  • D2 viewer      │                │  • Hot reload!    │
└───────────────────┘                └───────────────────┘
```

**Pros:**
- True hot reloading
- Built-in fault tolerance
- Fast development iteration
- Scales to distributed sync

**Cons:**
- Two processes to manage
- IPC complexity
- Two languages to maintain
- Elixir runtime dependency

### Option C: Hybrid (Elixir + Rust NIF)

```
┌───────────────────────────────────────────────────┐
│                  sync_daemon (Elixir)              │
│  ┌─────────────────────────────────────────────┐  │
│  │               GenServer                      │  │
│  │  ┌──────────────┐  ┌────────────────────┐   │  │
│  │  │ File Watcher │  │  Rust NIF (perf)   │   │  │
│  │  │  (Elixir)    │─▶│  - SQLite parsing  │   │  │
│  │  └──────────────┘  │  - Binary diffs    │   │  │
│  │                    └────────────────────┘   │  │
│  └─────────────────────────────────────────────┘  │
│                         │                          │
│                    IPC (socket)                    │
│                         │                          │
│  ┌─────────────────────▼───────────────────────┐  │
│  │            cursor-studio (Rust)              │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

**Used by:** Discord, WhatsApp, Bleacher Report

**Pros:**
- Best of both worlds
- Hot reload Elixir logic
- Performance-critical parts in Rust
- Proven at scale

**Cons:**
- Most complex setup
- Two build systems
- Learning curve for NIFs

---

## 🔬 Detailed Feature Analysis

### 1. File Watching

**Rust (notify crate):**
```rust
use notify::{Watcher, RecursiveMode, watcher};

let (tx, rx) = channel();
let mut watcher = watcher(tx, Duration::from_millis(100))?;
watcher.watch(cursor_db_path, RecursiveMode::NonRecursive)?;

for event in rx {
    match event {
        DebouncedEvent::Write(path) => sync_database(&path),
        _ => {}
    }
}
```

**Elixir (FileSystem):**
```elixir
defmodule Watcher do
  use GenServer
  
  def init(paths) do
    {:ok, pid} = FileSystem.start_link(dirs: paths)
    FileSystem.subscribe(pid)
    {:ok, %{watcher: pid}}
  end
  
  def handle_info({:file_event, _pid, {path, events}}, state) do
    if :modified in events, do: sync_database(path)
    {:noreply, state}
  end
end
```

**Verdict:** Both work well. Rust is slightly more mature.

### 2. SQLite Integration

**Rust (rusqlite):**
```rust
let conn = Connection::open(db_path)?;
let mut stmt = conn.prepare("SELECT value FROM cursorDiskKV WHERE key LIKE ?")?;
let messages: Vec<Message> = stmt
    .query_map(["%bubbleId:%"], |row| {
        let json: String = row.get(0)?;
        Ok(serde_json::from_str(&json)?)
    })?
    .collect()?;
```

**Elixir (Ecto.SQLite3):**
```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.SQLite3
end

# Query
from(k in "cursorDiskKV", 
  where: like(k.key, ^"%bubbleId:%"),
  select: k.value)
|> Repo.all()
```

**Verdict:** rusqlite is more mature and performant for direct SQLite access.

### 3. Fault Tolerance

**Rust (manual):**
```rust
loop {
    match sync_workspace(&workspace) {
        Ok(_) => {}
        Err(e) => {
            error!("Sync failed: {}", e);
            // Manual retry logic
            sleep(Duration::from_secs(5));
            continue;
        }
    }
}
```

**Elixir (built-in):**
```elixir
defmodule SyncSupervisor do
  use Supervisor
  
  def init(_) do
    children = [
      {WorkspaceWatcher, restart: :permanent},
      {SyncEngine, restart: :permanent},
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

**Verdict:** Elixir wins significantly here. OTP supervisors handle restarts automatically.

### 4. Concurrency

**Rust (Tokio):**
```rust
let handles: Vec<_> = workspaces
    .iter()
    .map(|ws| tokio::spawn(sync_workspace(ws.clone())))
    .collect();

join_all(handles).await;
```

**Elixir (Processes):**
```elixir
workspaces
|> Task.async_stream(&sync_workspace/1, max_concurrency: 10)
|> Stream.run()
```

**Verdict:** Both excellent. Elixir's model is more natural for this use case.

---

## 💡 Recommendation

### For v1.0: **Rust** (Pragmatic Choice)

Given that:
1. cursor-studio is already Rust
2. You know Rust well
3. Direct integration avoids IPC complexity
4. rusqlite is excellent
5. notify crate handles file watching well
6. Single binary deployment is simpler

**Implement the sync daemon in Rust first**, with a modular design that could be extracted later.

### For v2.0+: **Consider Elixir** If:
- You need truly distributed sync (multiple machines)
- Hot reloading becomes a major pain point
- Fault tolerance requirements increase
- You want to learn Elixir anyway

### Hybrid Approach Worth Considering If:
- Performance profiling shows bottlenecks
- You want the best of both worlds
- You're willing to invest in two ecosystems

---

## 🛠️ Rust Implementation Plan

If going with Rust, here's the structure:

```
cursor-studio-egui/src/sync/
├── mod.rs              # Module exports
├── daemon.rs           # Main sync daemon
├── watcher.rs          # File system watcher (notify)
├── cursor_db.rs        # Cursor database reader
├── external_db.rs      # External database writer
├── models.rs           # Data structures
└── config.rs           # Configuration
```

**Key crates:**
- `notify` - File watching
- `rusqlite` - SQLite access
- `tokio` - Async runtime
- `serde` - Serialization
- `tracing` - Logging/debugging

**Hot reload workaround:**
```rust
// Use cargo-watch for development
// $ cargo watch -x 'run --example sync_daemon'

// For true hot reload, structure as:
// 1. Static main loop (doesn't change often)
// 2. Config-driven behavior (reload config without restart)
// 3. Plugin system for sync strategies (optional)
```

---

## 📚 References

- [Discord: Using Rust to Scale Elixir](https://discord.com/blog/using-rust-to-scale-elixir-for-11-million-concurrent-users)
- [Rustler: Safe Rust NIFs for Elixir](https://github.com/rusterlium/rustler)
- [notify crate](https://docs.rs/notify)
- [hot-lib-reloader](https://github.com/rksm/hot-lib-reloader-rs)
- [Elixir OTP Guide](https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html)

---

## ✅ Decision Made: Elixir

**Rationale:**
- Multi-machine sync is a priority → BEAM distributed nodes
- Hot reloading is important for development iteration
- Fault tolerance via OTP supervisors
- Named pipes for IPC (simpler than alternatives)

**Implementation:** See `sync-daemon-elixir/` directory

**Future Hybrid Path:** If performance profiling shows bottlenecks, add Rust NIFs via Rustler.
