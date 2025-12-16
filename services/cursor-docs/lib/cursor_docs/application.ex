defmodule CursorDocs.Application do
  @moduledoc """
  OTP Application supervisor for CursorDocs.

  Starts and supervises:

  - `CursorDocs.Storage.SQLite` - SQLite database (always available)
  - `CursorDocs.Storage.SurrealDB` - SurrealDB with vectors (optional)
  - `CursorDocs.Storage.Vector.*` - Vector storage (tiered: disabled/sqlite-vss/surrealdb)
  - `CursorDocs.Embeddings.Generator` - AI embedding generation (optional)
  - `CursorDocs.CursorIntegration` - Cursor @docs sync and monitoring
  - `CursorDocs.Scraper.Pool` - Browser pool for web scraping
  - `CursorDocs.Scraper.JobQueue` - Scraping job queue
  - `CursorDocs.Scraper.RateLimiter` - Rate limiting
  - `CursorDocs.Telemetry` - Metrics and logging

  ## Architecture

  ```
  CursorDocs.Supervisor
  ├── CursorDocs.Telemetry
  ├── CursorDocs.Storage.SQLite           <-- Always available (FTS5)
  ├── CursorDocs.Storage.SurrealDB        <-- Optional, graph/vector (graceful)
  ├── CursorDocs.Storage.Vector.*         <-- Tiered vector storage
  ├── CursorDocs.Embeddings.Generator     <-- AI embeddings (optional)
  ├── CursorDocs.Security.Quarantine      <-- Data plane isolation
  ├── CursorDocs.CursorIntegration        <-- Syncs from Cursor's @docs
  ├── CursorDocs.Scraper.RateLimiter
  ├── CursorDocs.Scraper.JobQueue
  └── CursorDocs.Scraper.Pool
  ```

  ## Storage Tiers

  ### Tier 1: Disabled (Zero Setup)
  - No AI, no vectors
  - FTS5 keyword search only
  - For users who just want Cursor to work

  ### Tier 2: sqlite-vss (Recommended)
  - Embedded vector search
  - No daemon required
  - For users who want semantic search without overhead

  ### Tier 3: SurrealDB (Power Users)
  - Full vector + graph capabilities
  - Graceful startup (low priority, lazy connect)
  - For users building complete data pipelines

  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CursorDocs application...")

    children = [
      # Telemetry first (captures startup metrics)
      CursorDocs.Telemetry,

      # SQLite database (always available, fallback)
      {CursorDocs.Storage.SQLite, sqlite_config()},

      # SurrealDB database (optional, graceful - doesn't block if unavailable)
      {CursorDocs.Storage.SurrealDB, surrealdb_config()},

      # Security quarantine - ALL data passes through here first
      CursorDocs.Security.Quarantine,

      # Rate limiter (before pool so it's available)
      {CursorDocs.Scraper.RateLimiter, rate_limit_config()},

      # Job queue
      CursorDocs.Scraper.JobQueue,

      # Browser pool (optional - only if wallaby available)
      # {CursorDocs.Scraper.Pool, pool_config()},

      # Cursor integration - syncs @docs URLs automatically
      CursorDocs.CursorIntegration
    ]

    # Optionally start vector storage and embedding generator
    children = children ++ optional_ai_children()

    opts = [strategy: :one_for_one, name: CursorDocs.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("CursorDocs started successfully")
        setup_on_start()
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start CursorDocs: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("CursorDocs shutting down...")
    :ok
  end

  # Run setup tasks after startup
  defp setup_on_start do
    # Ensure database schemas exist
    spawn(fn ->
      Process.sleep(500)  # Wait for GenServers to initialize
      CursorDocs.Storage.setup()
      log_storage_status()
    end)
  end

  defp log_storage_status do
    status = CursorDocs.Storage.status()
    Logger.info("Storage backend: #{status.backend}")

    # Log AI provider status
    {:ok, ai_provider} = CursorDocs.AI.Provider.detect()
    Logger.info("AI provider: #{ai_provider.name()}")

    # Log vector storage status
    {:ok, vector_backend} = CursorDocs.Storage.Vector.detect()
    Logger.info("Vector storage: #{vector_backend.name()}")

    # Log search capabilities
    search_modes = CursorDocs.Search.available_modes()
    modes_str = search_modes.modes |> Enum.map(&to_string/1) |> Enum.join(", ")
    Logger.info("Search modes: #{modes_str} (default: #{search_modes.default})")

    if status.features.semantic_search do
      Logger.info("Features: semantic search ✓, vector embeddings ✓")
    else
      Logger.info("Features: full-text search (FTS5)")
    end
  end

  defp optional_ai_children do
    children = []

    # Start vector storage if not disabled
    {:ok, vector_backend} = CursorDocs.Storage.Vector.detect()

    children = case vector_backend do
      CursorDocs.Storage.Vector.Disabled ->
        Logger.info("Vector storage: disabled (FTS5 only)")
        children

      CursorDocs.Storage.Vector.SQLiteVss ->
        Logger.info("Vector storage: sqlite-vss (embedded)")
        [{CursorDocs.Storage.Vector.SQLiteVss, sqlite_vss_config()} | children]

      CursorDocs.Storage.Vector.SurrealDB ->
        Logger.info("Vector storage: SurrealDB (server)")
        [{CursorDocs.Storage.Vector.SurrealDB, surrealdb_vector_config()} | children]

      _ ->
        children
    end

    # Start embedding generator if AI provider available
    {:ok, ai_provider} = CursorDocs.AI.Provider.detect()

    children = case ai_provider do
      CursorDocs.AI.Disabled ->
        Logger.info("Embeddings: disabled")
        children

      _ ->
        Logger.info("Embeddings: #{ai_provider.name()}")
        [CursorDocs.Embeddings.Generator | children]
    end

    children
  end

  defp sqlite_config do
    [
      db_path: Application.get_env(:cursor_docs, :db_path, "~/.local/share/cursor-docs")
               |> Path.expand()
               |> Path.join("cursor_docs.db")
    ]
  end

  defp surrealdb_config do
    Application.get_env(:cursor_docs, :surrealdb, [
      endpoint: "http://localhost:8000",
      namespace: "cursor",
      database: "docs",
      username: "root",
      password: "root"
    ])
  end

  defp rate_limit_config do
    Application.get_env(:cursor_docs, :rate_limit, [
      requests_per_second: 2,
      burst: 5
    ])
  end

  defp sqlite_vss_config do
    db_path = Application.get_env(:cursor_docs, :db_path, "~/.local/share/cursor-docs")
              |> Path.expand()
              |> Path.join("vectors.db")

    Application.get_env(:cursor_docs, CursorDocs.Storage.Vector.SQLiteVss, [
      db_path: db_path,
      dimensions: 768
    ])
  end

  defp surrealdb_vector_config do
    Application.get_env(:cursor_docs, CursorDocs.Storage.Vector.SurrealDB, [
      endpoint: "http://localhost:8000",
      namespace: "cursor",
      database: "docs",
      username: "root",
      password: "root",
      dimensions: 768,
      lazy_connect: true  # Don't block startup
    ])
  end
end
