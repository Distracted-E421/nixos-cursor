# cursor-docs Daemon Architecture

> **Goal**: Run cursor-docs as a long-running service with client/server sync, enabling distributed indexing across your homelab.

## Architecture Overview

```
                                    ┌─────────────────────────────────────┐
                                    │         SERVER INSTANCE             │
                                    │       (pi-server / Obsidian)        │
                                    │                                     │
                                    │  ┌─────────────────────────────┐   │
                                    │  │     cursor-docs daemon      │   │
                                    │  │                             │   │
                                    │  │  - Full SQLite index        │   │
                                    │  │  - Background crawler       │   │
                                    │  │  - Embeddings (if GPU)      │   │
                                    │  │  - HTTP API (:4000)         │   │
                                    │  │  - WebSocket sync (:4001)   │   │
                                    │  └─────────────────────────────┘   │
                                    │                │                   │
                                    └────────────────┼───────────────────┘
                                                     │
                           ┌─────────────────────────┼─────────────────────────┐
                           │                         │                         │
                           ▼                         ▼                         ▼
              ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
              │   CLIENT INSTANCE   │   │   CLIENT INSTANCE   │   │   CLIENT INSTANCE   │
              │   (neon-laptop)     │   │    (framework)      │   │    (Obsidian)       │
              │                     │   │                     │   │                     │
              │ - Local SQLite      │   │ - Local SQLite      │   │ - Local SQLite      │
              │ - Sync agent        │   │ - Sync agent        │   │ - Can also be server│
              │ - CLI/MCP access    │   │ - CLI/MCP access    │   │ - Full capabilities │
              └─────────────────────┘   └─────────────────────┘   └─────────────────────┘
```

## Deployment Modes

### Mode 1: Standalone (Current)
- Single machine, ephemeral
- CLI commands start/stop app
- No persistence of background jobs

### Mode 2: Daemon (Local)
- Single machine, persistent
- Systemd user service
- Background jobs survive restarts
- HTTP API for local integrations

### Mode 3: Server (Network)
- Hosts the canonical index
- Accepts connections from clients
- Handles crawling requests
- Distributes to clients

### Mode 4: Client (Network)
- Syncs from server
- Local cache for offline use
- Can submit URLs for server to crawl
- Optional: local crawling too

## HTTP API Design

```elixir
# services/cursor-docs/lib/cursor_docs/api/router.ex

defmodule CursorDocs.API.Router do
  use Plug.Router
  
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch
  
  # ==========================================================================
  # Sources Management
  # ==========================================================================
  
  # List all sources with optional filtering
  get "/api/sources" do
    # Query params: ?status=indexed&limit=50&offset=0
    sources = Storage.list_sources(conn.query_params)
    json(conn, 200, %{sources: sources, total: length(sources)})
  end
  
  # Add new source (triggers crawl)
  post "/api/sources" do
    %{"url" => url} = conn.body_params
    opts = [
      name: conn.body_params["name"],
      max_pages: conn.body_params["max_pages"] || 100,
      strategy: conn.body_params["strategy"] || :auto,
      priority: conn.body_params["priority"] || :normal
    ]
    
    case Background.start_crawl(url, opts) do
      {:ok, job_id} ->
        json(conn, 202, %{job_id: job_id, status: "queued"})
      {:error, reason} ->
        json(conn, 400, %{error: reason})
    end
  end
  
  # Get source details
  get "/api/sources/:id" do
    case Storage.get_source(id) do
      {:ok, source} -> json(conn, 200, source)
      {:error, :not_found} -> json(conn, 404, %{error: "not found"})
    end
  end
  
  # Delete source
  delete "/api/sources/:id" do
    case Storage.delete_source(id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> json(conn, 400, %{error: reason})
    end
  end
  
  # Refresh source (re-crawl)
  post "/api/sources/:id/refresh" do
    case Scraper.refresh(id) do
      {:ok, _} -> json(conn, 202, %{status: "refreshing"})
      {:error, reason} -> json(conn, 400, %{error: reason})
    end
  end
  
  # ==========================================================================
  # Search
  # ==========================================================================
  
  # Full-text search
  get "/api/search" do
    query = conn.query_params["q"] || ""
    limit = String.to_integer(conn.query_params["limit"] || "10")
    
    results = Storage.search_chunks(query, limit)
    json(conn, 200, %{query: query, results: results, count: length(results)})
  end
  
  # POST search with filters
  post "/api/search" do
    %{"query" => query} = conn.body_params
    opts = [
      limit: conn.body_params["limit"] || 10,
      sources: conn.body_params["sources"],
      min_score: conn.body_params["min_score"]
    ]
    
    results = Storage.search_chunks(query, opts)
    json(conn, 200, %{query: query, results: results, count: length(results)})
  end
  
  # ==========================================================================
  # Sync (Client/Server)
  # ==========================================================================
  
  # Get changes since timestamp (for clients to pull)
  get "/api/sync/changes" do
    since = conn.query_params["since"] # ISO8601 timestamp
    
    changes = Sync.get_changes_since(since)
    json(conn, 200, %{
      changes: changes,
      count: length(changes),
      server_time: DateTime.utc_now()
    })
  end
  
  # Push changes from client
  post "/api/sync/push" do
    %{"changes" => changes, "client_id" => client_id} = conn.body_params
    
    case Sync.apply_changes(changes, client_id) do
      {:ok, applied} ->
        json(conn, 200, %{applied: applied, conflicts: []})
      {:conflict, conflicts} ->
        json(conn, 409, %{conflicts: conflicts})
    end
  end
  
  # Register as client
  post "/api/sync/register" do
    %{"client_id" => client_id, "hostname" => hostname} = conn.body_params
    
    case Sync.register_client(client_id, hostname) do
      {:ok, _} -> json(conn, 200, %{status: "registered"})
      {:error, reason} -> json(conn, 400, %{error: reason})
    end
  end
  
  # ==========================================================================
  # Jobs Management
  # ==========================================================================
  
  get "/api/jobs" do
    jobs = Background.list_jobs()
    json(conn, 200, %{jobs: jobs})
  end
  
  get "/api/jobs/:id" do
    case Background.status(id) do
      {:ok, job} -> json(conn, 200, job)
      {:error, :not_found} -> json(conn, 404, %{error: "not found"})
    end
  end
  
  delete "/api/jobs/:id" do
    case Background.cancel(id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> json(conn, 400, %{error: reason})
    end
  end
  
  # ==========================================================================
  # Security
  # ==========================================================================
  
  get "/api/alerts" do
    alerts = Security.Alerts.list_alerts()
    json(conn, 200, %{alerts: alerts})
  end
  
  get "/api/quarantine" do
    items = Security.Quarantine.list_items()
    json(conn, 200, %{items: items})
  end
  
  post "/api/quarantine/:id/review" do
    %{"action" => action} = conn.body_params # approve, reject, keep_flagged
    
    case Security.Quarantine.review(id, action) do
      {:ok, _} -> json(conn, 200, %{status: "reviewed"})
      {:error, reason} -> json(conn, 400, %{error: reason})
    end
  end
  
  # ==========================================================================
  # Status
  # ==========================================================================
  
  get "/api/status" do
    json(conn, 200, %{
      status: "healthy",
      version: Application.spec(:cursor_docs, :vsn),
      mode: Application.get_env(:cursor_docs, :mode, :standalone),
      uptime: System.monotonic_time(:second),
      stats: Storage.stats()
    })
  end
  
  # Catch-all
  match _ do
    send_resp(conn, 404, "Not found")
  end
  
  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## WebSocket Sync Protocol

```elixir
# services/cursor-docs/lib/cursor_docs/sync/websocket.ex

defmodule CursorDocs.Sync.WebSocket do
  @behaviour :cowboy_websocket
  
  # Message types
  @type_subscribe "subscribe"
  @type_unsubscribe "unsubscribe"
  @type_change "change"
  @type_request_sync "request_sync"
  @type_sync_complete "sync_complete"
  @type_heartbeat "heartbeat"
  
  def init(req, state) do
    {:cowboy_websocket, req, state}
  end
  
  def websocket_init(state) do
    # Register this connection
    client_id = state[:client_id] || generate_client_id()
    Sync.Registry.register(client_id, self())
    
    {:ok, Map.put(state, :client_id, client_id)}
  end
  
  def websocket_handle({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => @type_subscribe, "sources" => sources}} ->
        # Subscribe to changes for specific sources
        Enum.each(sources, &Sync.subscribe(state.client_id, &1))
        {:ok, state}
      
      {:ok, %{"type" => @type_request_sync, "since" => since}} ->
        # Client wants full sync since timestamp
        spawn_link(fn -> send_full_sync(state.client_id, since) end)
        {:ok, state}
      
      {:ok, %{"type" => @type_change, "changes" => changes}} ->
        # Client pushing changes
        Sync.apply_changes(changes, state.client_id)
        {:ok, state}
      
      {:ok, %{"type" => @type_heartbeat}} ->
        reply = Jason.encode!(%{type: "heartbeat_ack", time: DateTime.utc_now()})
        {:reply, {:text, reply}, state}
      
      _ ->
        {:ok, state}
    end
  end
  
  def websocket_info({:change, change}, state) do
    # Broadcast change to this client
    msg = Jason.encode!(%{type: @type_change, change: change})
    {:reply, {:text, msg}, state}
  end
  
  def websocket_info({:sync_batch, batch}, state) do
    msg = Jason.encode!(%{type: "sync_batch", changes: batch})
    {:reply, {:text, msg}, state}
  end
  
  def terminate(_reason, _req, state) do
    Sync.Registry.unregister(state.client_id)
    :ok
  end
  
  defp send_full_sync(client_id, since) do
    changes = Sync.get_changes_since(since)
    
    # Send in batches of 100
    changes
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      send(self(), {:sync_batch, batch})
      Process.sleep(50)  # Rate limit
    end)
    
    send(self(), {:sync_complete})
  end
end
```

## Sync Data Model

```elixir
# services/cursor-docs/lib/cursor_docs/sync/models.ex

defmodule CursorDocs.Sync.Models do
  @moduledoc """
  CRDT-based sync models for conflict-free replication.
  """
  
  # Change record for sync
  defmodule Change do
    defstruct [
      :id,           # UUID
      :type,         # :source_added, :source_deleted, :chunk_added, etc.
      :entity_type,  # :source, :chunk, :alert
      :entity_id,    # ID of affected entity
      :data,         # The actual change data
      :timestamp,    # Hybrid logical clock
      :origin,       # client_id that made change
      :vector_clock  # For conflict detection
    ]
  end
  
  # Sync state for a client
  defmodule ClientState do
    defstruct [
      :client_id,
      :hostname,
      :last_seen,
      :last_sync,
      :subscriptions,  # List of source IDs to sync
      :vector_clock
    ]
  end
  
  # Server sync metadata
  defmodule SyncMeta do
    defstruct [
      :server_id,
      :clients,        # Map of client_id -> ClientState
      :change_log,     # Recent changes for replay
      :log_retention   # How long to keep changes
    ]
  end
end
```

## Systemd Service

```nix
# NixOS module for cursor-docs daemon
# nixos/modules/cursor-docs.nix

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cursor-docs;
in {
  options.services.cursor-docs = {
    enable = mkEnableOption "cursor-docs documentation indexer";
    
    mode = mkOption {
      type = types.enum [ "standalone" "daemon" "server" "client" ];
      default = "daemon";
      description = "Operating mode";
    };
    
    port = mkOption {
      type = types.port;
      default = 4000;
      description = "HTTP API port";
    };
    
    wsPort = mkOption {
      type = types.port;
      default = 4001;
      description = "WebSocket sync port";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/cursor-docs";
      description = "Data directory for index";
    };
    
    server = {
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Server URL (for client mode)";
      };
      
      clientId = mkOption {
        type = types.str;
        default = config.networking.hostName;
        description = "Client identifier for sync";
      };
    };
    
    crawling = {
      maxConcurrent = mkOption {
        type = types.int;
        default = 3;
        description = "Max concurrent crawl jobs";
      };
      
      rateLimit = mkOption {
        type = types.int;
        default = 2;
        description = "Requests per second limit";
      };
    };
    
    embeddings = {
      enable = mkEnableOption "AI embeddings generation";
      
      provider = mkOption {
        type = types.enum [ "ollama" "openai" "local" ];
        default = "ollama";
      };
      
      ollamaUrl = mkOption {
        type = types.str;
        default = "http://localhost:11434";
      };
    };
  };
  
  config = mkIf cfg.enable {
    systemd.services.cursor-docs = {
      description = "cursor-docs Documentation Indexer";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        MIX_ENV = "prod";
        CURSOR_DOCS_MODE = cfg.mode;
        CURSOR_DOCS_PORT = toString cfg.port;
        CURSOR_DOCS_WS_PORT = toString cfg.wsPort;
        CURSOR_DOCS_DATA_DIR = cfg.dataDir;
        CURSOR_DOCS_MAX_CONCURRENT = toString cfg.crawling.maxConcurrent;
        CURSOR_DOCS_RATE_LIMIT = toString cfg.crawling.rateLimit;
      } // optionalAttrs (cfg.server.url != null) {
        CURSOR_DOCS_SERVER_URL = cfg.server.url;
        CURSOR_DOCS_CLIENT_ID = cfg.server.clientId;
      } // optionalAttrs cfg.embeddings.enable {
        CURSOR_DOCS_EMBEDDINGS_PROVIDER = cfg.embeddings.provider;
        CURSOR_DOCS_OLLAMA_URL = cfg.embeddings.ollamaUrl;
      };
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.cursor-docs}/bin/cursor-docs daemon";
        Restart = "always";
        RestartSec = 5;
        
        # Security hardening
        DynamicUser = true;
        StateDirectory = "cursor-docs";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
    
    # Firewall rules for server mode
    networking.firewall = mkIf (cfg.mode == "server") {
      allowedTCPPorts = [ cfg.port cfg.wsPort ];
    };
  };
}
```

## User Service (Home Manager)

```nix
# For user-level daemon (e.g., on laptops)
# nixos/users/e421/cursor-docs.nix

{ config, lib, pkgs, ... }:

{
  systemd.user.services.cursor-docs = {
    Unit = {
      Description = "cursor-docs Documentation Indexer";
      After = [ "network.target" ];
    };
    
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.cursor-docs}/bin/cursor-docs daemon";
      Restart = "always";
      Environment = [
        "CURSOR_DOCS_MODE=client"
        "CURSOR_DOCS_PORT=4000"
        "CURSOR_DOCS_SERVER_URL=http://obsidian:4000"
        "CURSOR_DOCS_CLIENT_ID=${config.networking.hostName}"
        "CURSOR_DOCS_DATA_DIR=%h/.local/share/cursor-docs"
      ];
    };
    
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
  
  # Also enable socket activation for on-demand startup
  systemd.user.sockets.cursor-docs = {
    Unit = {
      Description = "cursor-docs Socket";
    };
    
    Socket = {
      ListenStream = "4000";
    };
    
    Install = {
      WantedBy = [ "sockets.target" ];
    };
  };
}
```

## Sync Flow

### Initial Sync (Client → Server)

```
Client                                 Server
  │                                      │
  │  POST /api/sync/register             │
  │  {client_id, hostname}               │
  │ ────────────────────────────────────►│
  │                                      │
  │  200 OK {registered}                 │
  │ ◄────────────────────────────────────│
  │                                      │
  │  WS connect                          │
  │ ────────────────────────────────────►│
  │                                      │
  │  {"type":"request_sync","since":0}   │
  │ ────────────────────────────────────►│
  │                                      │
  │  {"type":"sync_batch",changes:[...]} │
  │ ◄────────────────────────────────────│
  │  (repeat for all batches)            │
  │                                      │
  │  {"type":"sync_complete"}            │
  │ ◄────────────────────────────────────│
```

### URL Added on Client

```
Client                                 Server
  │                                      │
  │  User: mix cursor_docs.add URL       │
  │                                      │
  │  POST /api/sources                   │
  │  {url, name, client_origin: true}    │
  │ ────────────────────────────────────►│
  │                                      │
  │  202 Accepted {job_id}               │
  │ ◄────────────────────────────────────│
  │                                      │
  │  (Server crawls with its resources)  │
  │                                      │
  │  WS: {"type":"change",               │
  │       change:{source_indexed}}       │
  │ ◄────────────────────────────────────│
  │                                      │
  │  (Client updates local index)        │
```

### Real-time Sync

```
                    Server
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
   Client A       Client B       Client C
       
When Client A adds a URL:
1. A sends to Server
2. Server crawls
3. Server broadcasts change to B and C via WebSocket
4. All clients have consistent index
```

## CLI Updates for Daemon Mode

```bash
# Start daemon
mix cursor_docs.daemon start

# Stop daemon
mix cursor_docs.daemon stop

# Status
mix cursor_docs.daemon status

# Sync commands (client mode)
mix cursor_docs.sync status          # Show sync state
mix cursor_docs.sync pull            # Pull changes from server
mix cursor_docs.sync push            # Push local changes
mix cursor_docs.sync register        # Register with server

# Server commands (server mode)
mix cursor_docs.server clients       # List connected clients
mix cursor_docs.server broadcast     # Broadcast message
```

## Implementation Phases

### Phase 1: Local Daemon (Week 1)
- [ ] HTTP API implementation (Plug router)
- [ ] Background process persistence (GenServer state recovery)
- [ ] Systemd service file
- [ ] Basic health endpoints

### Phase 2: Sync Protocol (Week 2)
- [ ] WebSocket server (cowboy)
- [ ] Change tracking in SQLite
- [ ] Client registration
- [ ] Delta sync implementation

### Phase 3: Client Mode (Week 3)
- [ ] Server discovery (mDNS or config)
- [ ] Sync agent service
- [ ] Conflict resolution (CRDT)
- [ ] Offline queue

### Phase 4: Integration (Week 4)
- [ ] cursor-studio-egui integration
- [ ] MCP server for Cursor
- [ ] NixOS module
- [ ] Documentation

## Configuration

```elixir
# config/runtime.exs

import Config

config :cursor_docs,
  mode: System.get_env("CURSOR_DOCS_MODE", "standalone") |> String.to_atom(),
  port: System.get_env("CURSOR_DOCS_PORT", "4000") |> String.to_integer(),
  ws_port: System.get_env("CURSOR_DOCS_WS_PORT", "4001") |> String.to_integer(),
  data_dir: System.get_env("CURSOR_DOCS_DATA_DIR", "~/.local/share/cursor-docs") |> Path.expand()

# Server connection (for client mode)
if config[:mode] == :client do
  config :cursor_docs, :server,
    url: System.get_env("CURSOR_DOCS_SERVER_URL") || raise("Server URL required"),
    client_id: System.get_env("CURSOR_DOCS_CLIENT_ID", node() |> to_string())
end

# Crawling limits
config :cursor_docs, :crawling,
  max_concurrent: System.get_env("CURSOR_DOCS_MAX_CONCURRENT", "3") |> String.to_integer(),
  rate_limit: System.get_env("CURSOR_DOCS_RATE_LIMIT", "2") |> String.to_integer()
```

## Next Steps

1. [ ] Implement HTTP API router
2. [ ] Add Plug to dependencies
3. [ ] Create daemon entry point
4. [ ] Test with curl/httpie
5. [ ] Add WebSocket support
6. [ ] Build sync protocol
7. [ ] Create NixOS module
8. [ ] Test multi-device sync

