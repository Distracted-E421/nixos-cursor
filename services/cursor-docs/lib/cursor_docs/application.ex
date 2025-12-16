defmodule CursorDocs.Application do
  @moduledoc """
  OTP Application supervisor for CursorDocs.

  Starts and supervises:

  - `CursorDocs.Storage.SQLite` - SQLite database connection
  - `CursorDocs.CursorIntegration` - Cursor @docs sync and monitoring
  - `CursorDocs.Scraper.Pool` - Browser pool for web scraping
  - `CursorDocs.Scraper.JobQueue` - Scraping job queue
  - `CursorDocs.Scraper.RateLimiter` - Rate limiting
  - `CursorDocs.Telemetry` - Metrics and logging

  ## Architecture

  ```
  CursorDocs.Supervisor
  ├── CursorDocs.Telemetry
  ├── CursorDocs.Storage.SQLite
  ├── CursorDocs.Security.Quarantine  <-- Data plane isolation
  ├── CursorDocs.CursorIntegration    <-- Syncs from Cursor's @docs
  ├── CursorDocs.Scraper.RateLimiter
  ├── CursorDocs.Scraper.JobQueue
  └── CursorDocs.Scraper.Pool
  ```

  The CursorIntegration module automatically:
  1. Reads URLs from Cursor's @docs settings on startup
  2. Watches for new docs being added in Cursor
  3. Queues them for reliable local scraping
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CursorDocs application...")

    children = [
      # Telemetry first (captures startup metrics)
      CursorDocs.Telemetry,

      # Database connection
      {CursorDocs.Storage.SQLite, storage_config()},

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
    # Ensure database schema exists
    spawn(fn ->
      Process.sleep(500)  # Wait for GenServers to initialize
      CursorDocs.Storage.SQLite.setup()
    end)
  end

  defp storage_config do
    [
      db_path: Application.get_env(:cursor_docs, :db_path, "~/.local/share/cursor-docs")
               |> Path.expand()
               |> Path.join("cursor_docs.db")
    ]
  end

  defp rate_limit_config do
    Application.get_env(:cursor_docs, :rate_limit, [
      requests_per_second: 2,
      burst: 5
    ])
  end
end
