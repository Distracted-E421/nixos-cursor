defmodule CursorDocs.Telemetry do
  @moduledoc """
  Telemetry supervisor for CursorDocs metrics and logging.

  Emits telemetry events for:
  - Scrape job starts/completions/failures
  - Search queries and latency
  - Database operations
  - Browser pool utilization

  ## Events

  - `[:cursor_docs, :scrape, :start]` - Scrape job started
  - `[:cursor_docs, :scrape, :complete]` - Scrape job completed
  - `[:cursor_docs, :scrape, :error]` - Scrape job failed
  - `[:cursor_docs, :search, :query]` - Search query executed
  - `[:cursor_docs, :storage, :query]` - Database query executed
  """

  use Supervisor

  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Telemetry poller for periodic metrics
      {:telemetry_poller,
       measurements: periodic_measurements(),
       period: :timer.seconds(30),
       name: :cursor_docs_poller}
    ]

    # Attach handlers for logging
    attach_handlers()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_pool_stats, []}
    ]
  end

  @doc """
  Measure browser pool statistics.
  """
  def measure_pool_stats do
    stats = CursorDocs.Scraper.Pool.stats()

    :telemetry.execute(
      [:cursor_docs, :pool, :stats],
      %{
        available: stats[:available] || 0,
        busy: stats[:busy] || 0,
        total: stats[:total_browsers] || 0
      },
      %{}
    )
  end

  defp attach_handlers do
    :telemetry.attach_many(
      "cursor-docs-logging",
      [
        [:cursor_docs, :scrape, :start],
        [:cursor_docs, :scrape, :complete],
        [:cursor_docs, :scrape, :error],
        [:cursor_docs, :search, :query]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event([:cursor_docs, :scrape, :start], _measurements, metadata, _config) do
    Logger.info("Scrape started: #{metadata[:url]}")
  end

  def handle_event([:cursor_docs, :scrape, :complete], measurements, metadata, _config) do
    Logger.info(
      "Scrape complete: #{metadata[:url]} - #{measurements[:pages]} pages in #{measurements[:duration_ms]}ms"
    )
  end

  def handle_event([:cursor_docs, :scrape, :error], _measurements, metadata, _config) do
    Logger.error("Scrape failed: #{metadata[:url]} - #{inspect(metadata[:error])}")
  end

  def handle_event([:cursor_docs, :search, :query], measurements, metadata, _config) do
    Logger.debug(
      "Search: \"#{metadata[:query]}\" - #{measurements[:results]} results in #{measurements[:duration_ms]}ms"
    )
  end

  @doc """
  Emit a scrape start event.
  """
  def scrape_start(url, source_id) do
    :telemetry.execute(
      [:cursor_docs, :scrape, :start],
      %{},
      %{url: url, source_id: source_id}
    )
  end

  @doc """
  Emit a scrape complete event.
  """
  def scrape_complete(url, source_id, pages, duration_ms) do
    :telemetry.execute(
      [:cursor_docs, :scrape, :complete],
      %{pages: pages, duration_ms: duration_ms},
      %{url: url, source_id: source_id}
    )
  end

  @doc """
  Emit a scrape error event.
  """
  def scrape_error(url, source_id, error) do
    :telemetry.execute(
      [:cursor_docs, :scrape, :error],
      %{},
      %{url: url, source_id: source_id, error: error}
    )
  end

  @doc """
  Emit a search query event.
  """
  def search_query(query, results, duration_ms) do
    :telemetry.execute(
      [:cursor_docs, :search, :query],
      %{results: results, duration_ms: duration_ms},
      %{query: query}
    )
  end
end

