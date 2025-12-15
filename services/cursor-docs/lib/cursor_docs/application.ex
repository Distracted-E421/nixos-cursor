defmodule CursorDocs.Application do
  @moduledoc """
  OTP Application supervisor for CursorDocs.

  Starts and supervises the following processes:

  - `CursorDocs.Storage.Surreal` - SurrealDB connection pool
  - `CursorDocs.Scraper.Pool` - Playwright browser pool
  - `CursorDocs.Scraper.JobQueue` - Scraping job queue
  - `CursorDocs.Telemetry` - Metrics and logging

  The supervision tree is structured for fault tolerance:
  - Storage failures don't affect ongoing scraping
  - Individual browser crashes are isolated
  - Job queue persists state to database
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CursorDocs application...")

    children = [
      # Telemetry supervisor (first, to capture startup metrics)
      CursorDocs.Telemetry,

      # Database connection
      {CursorDocs.Storage.Surreal, surreal_config()},

      # Browser pool for scraping
      {CursorDocs.Scraper.Pool, pool_config()},

      # Job queue for managing scrape jobs
      CursorDocs.Scraper.JobQueue,

      # Rate limiter
      {CursorDocs.Scraper.RateLimiter, rate_limit_config()}
    ]

    opts = [strategy: :one_for_one, name: CursorDocs.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("CursorDocs started successfully")
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

  defp surreal_config do
    [
      path: db_path(),
      namespace: "cursor_docs",
      database: "main"
    ]
  end

  defp pool_config do
    [
      size: Application.get_env(:cursor_docs, :browser_pool_size, 3),
      max_overflow: 2
    ]
  end

  defp rate_limit_config do
    Application.get_env(:cursor_docs, :rate_limit, [
      requests_per_second: 2,
      burst: 5
    ])
  end

  defp db_path do
    Application.get_env(:cursor_docs, :db_path, "~/.local/share/cursor-docs")
    |> Path.expand()
  end
end
