defmodule CursorDocs.Storage.SQLite do
  @moduledoc """
  SQLite storage backend for CursorDocs using exqlite.

  Uses the same database format as Cursor where possible, making it easier
  to potentially share data or sync state.

  ## Schema

  ### doc_sources
  Documentation source metadata.

  ### doc_chunks
  Content chunks with FTS5 full-text search.

  ### scrape_jobs
  Scraping job queue with status tracking.
  """

  use GenServer

  require Logger

  alias Exqlite.Sqlite3

  @db_name "cursor_docs.db"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Setup the database schema.
  """
  def setup do
    GenServer.call(__MODULE__, :setup, 30_000)
  end

  @doc """
  Create a new documentation source.
  """
  @spec create_source(map()) :: {:ok, map()} | {:error, term()}
  def create_source(attrs) do
    GenServer.call(__MODULE__, {:create_source, attrs})
  end

  @doc """
  Update a documentation source.
  """
  @spec update_source(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_source(id, attrs) do
    GenServer.call(__MODULE__, {:update_source, id, attrs})
  end

  @doc """
  Get a source by ID.
  """
  @spec get_source(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_source(id) do
    GenServer.call(__MODULE__, {:get_source, id})
  end

  @doc """
  List all sources.
  """
  @spec list_sources() :: {:ok, list(map())}
  def list_sources do
    GenServer.call(__MODULE__, :list_sources)
  end

  @doc """
  Remove a source and its chunks.
  """
  @spec remove_source(String.t()) :: :ok | {:error, term()}
  def remove_source(id) do
    GenServer.call(__MODULE__, {:remove_source, id})
  end

  @doc """
  Clear all chunks for a source (before re-indexing).
  """
  @spec clear_chunks(String.t()) :: :ok | {:error, term()}
  def clear_chunks(source_id) do
    GenServer.call(__MODULE__, {:clear_chunks, source_id})
  end

  @doc """
  Store a content chunk.
  """
  @spec store_chunk(map()) :: {:ok, map()} | {:error, term()}
  def store_chunk(attrs) do
    GenServer.call(__MODULE__, {:store_chunk, attrs})
  end

  @doc """
  Store multiple chunks in a batch.
  """
  @spec store_chunks(list(map())) :: {:ok, integer()} | {:error, term()}
  def store_chunks(chunks) do
    GenServer.call(__MODULE__, {:store_chunks, chunks}, 60_000)
  end

  @doc """
  Check if a URL already exists as a source.
  """
  @spec source_exists?(String.t()) :: boolean()
  def source_exists?(url) do
    GenServer.call(__MODULE__, {:source_exists, url})
  end

  @doc """
  Get source by URL.
  """
  @spec get_source_by_url(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_source_by_url(url) do
    GenServer.call(__MODULE__, {:get_source_by_url, url})
  end

  @doc """
  Search chunks using FTS5.
  """
  @spec search_chunks(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search_chunks(query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_chunks, query, opts})
  end

  @doc """
  Get all chunks for a source (for embedding generation).
  """
  @spec get_chunks_for_source(String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_chunks_for_source(source_id) do
    GenServer.call(__MODULE__, {:get_chunks_for_source, source_id})
  end

  @doc """
  Get a single chunk by ID.
  """
  @spec get_chunk(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_chunk(chunk_id) do
    GenServer.call(__MODULE__, {:get_chunk, chunk_id})
  end

  # ============================================================================
  # Security Alert API
  # ============================================================================

  @doc """
  Store a security alert.
  """
  @spec store_alert(map()) :: {:ok, map()} | {:error, term()}
  def store_alert(attrs) do
    GenServer.call(__MODULE__, {:store_alert, attrs})
  end

  @doc """
  Get alerts for a source.
  """
  @spec get_alerts_for_source(String.t()) :: {:ok, list(map())}
  def get_alerts_for_source(source_id) do
    GenServer.call(__MODULE__, {:get_alerts_for_source, source_id})
  end

  @doc """
  List all unresolved alerts.
  """
  @spec list_unresolved_alerts(keyword()) :: {:ok, list(map())}
  def list_unresolved_alerts(opts \\ []) do
    GenServer.call(__MODULE__, {:list_unresolved_alerts, opts})
  end

  @doc """
  Mark alert as resolved.
  """
  @spec resolve_alert(String.t(), String.t()) :: :ok | {:error, term()}
  def resolve_alert(alert_id, resolution_note) do
    GenServer.call(__MODULE__, {:resolve_alert, alert_id, resolution_note})
  end

  @doc """
  Get alert statistics.
  """
  @spec alert_stats() :: {:ok, map()}
  def alert_stats do
    GenServer.call(__MODULE__, :alert_stats)
  end

  # ============================================================================
  # Quarantine API
  # ============================================================================

  @doc """
  Store a quarantine item.
  """
  @spec store_quarantine_item(map()) :: {:ok, map()} | {:error, term()}
  def store_quarantine_item(attrs) do
    GenServer.call(__MODULE__, {:store_quarantine_item, attrs})
  end

  @doc """
  Get pending review items.
  """
  @spec pending_quarantine_items() :: {:ok, list(map())}
  def pending_quarantine_items do
    GenServer.call(__MODULE__, :pending_quarantine_items)
  end

  @doc """
  Mark quarantine item as reviewed.
  """
  @spec review_quarantine_item(String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def review_quarantine_item(item_id, reviewer, action) do
    GenServer.call(__MODULE__, {:review_quarantine_item, item_id, reviewer, action})
  end

  @doc """
  Get quarantine item by ID.
  """
  @spec get_quarantine_item(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_quarantine_item(item_id) do
    GenServer.call(__MODULE__, {:get_quarantine_item, item_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, default_db_path())

    # Ensure directory exists
    db_path |> Path.dirname() |> File.mkdir_p!()

    Logger.info("Opening SQLite database at #{db_path}")

    case Sqlite3.open(db_path) do
      {:ok, conn} ->
        # Enable WAL mode for better concurrency
        Sqlite3.execute(conn, "PRAGMA journal_mode=WAL;")
        Sqlite3.execute(conn, "PRAGMA synchronous=NORMAL;")

        # Auto-setup schema on fresh database
        setup_schema(conn)

        {:ok, %{conn: conn, path: db_path}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:setup, _from, state) do
    result = setup_schema(state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_source, attrs}, _from, state) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = """
    INSERT INTO doc_sources (id, url, name, status, pages_count, chunks_count, config, created_at, last_indexed)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    params = [
      id,
      attrs[:url],
      attrs[:name],
      "pending",
      0,
      0,
      Jason.encode!(attrs[:config] || %{}),
      now,
      nil
    ]

    case execute_with_params(state.conn, sql, params) do
      :ok ->
        source = Map.merge(attrs, %{id: id, status: "pending", created_at: now})
        {:reply, {:ok, source}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_source, id, attrs}, _from, state) do
    # Build dynamic UPDATE
    {sets, params} = build_update_params(attrs)

    if sets != "" do
      sql = "UPDATE doc_sources SET #{sets} WHERE id = ?"
      params = params ++ [id]

      case execute_with_params(state.conn, sql, params) do
        :ok -> {:reply, {:ok, %{id: id}}, state}
        error -> {:reply, error, state}
      end
    else
      {:reply, {:ok, %{id: id}}, state}
    end
  end

  @impl true
  def handle_call({:get_source, id}, _from, state) do
    sql =
      "SELECT id, url, name, status, pages_count, chunks_count, config, created_at, last_indexed FROM doc_sources WHERE id = ?"

    case fetch_one(state.conn, sql, [id]) do
      {:ok, [id, url, name, status, pages, chunks, config, created, indexed]} ->
        source = %{
          id: id,
          url: url,
          name: name,
          status: status,
          pages_count: pages,
          chunks_count: chunks,
          config: Jason.decode!(config || "{}"),
          created_at: created,
          last_indexed: indexed
        }

        {:reply, {:ok, source}, state}

      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_sources, _from, state) do
    sql =
      "SELECT id, url, name, status, pages_count, chunks_count, created_at, last_indexed FROM doc_sources ORDER BY created_at DESC"

    case fetch_all(state.conn, sql, []) do
      {:ok, rows} ->
        sources =
          Enum.map(rows, fn [id, url, name, status, pages, chunks, created, indexed] ->
            %{
              id: id,
              url: url,
              name: name,
              status: status,
              pages_count: pages,
              chunks_count: chunks,
              created_at: created,
              last_indexed: indexed
            }
          end)

        {:reply, {:ok, sources}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:remove_source, id}, _from, state) do
    # Delete in order (also clear FTS)
    execute_with_params(state.conn, "DELETE FROM doc_chunks_fts WHERE source_id = ?", [id])
    execute_with_params(state.conn, "DELETE FROM doc_chunks WHERE source_id = ?", [id])
    execute_with_params(state.conn, "DELETE FROM scrape_jobs WHERE source_id = ?", [id])
    execute_with_params(state.conn, "DELETE FROM doc_sources WHERE id = ?", [id])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:clear_chunks, source_id}, _from, state) do
    # Clear both regular table and FTS table
    execute_with_params(state.conn, "DELETE FROM doc_chunks_fts WHERE source_id = ?", [source_id])
    execute_with_params(state.conn, "DELETE FROM doc_chunks WHERE source_id = ?", [source_id])
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:source_exists, url}, _from, state) do
    case fetch_one(state.conn, "SELECT COUNT(*) FROM doc_sources WHERE url = ?", [url]) do
      {:ok, [count]} when count > 0 -> {:reply, true, state}
      _ -> {:reply, false, state}
    end
  end

  @impl true
  def handle_call({:get_source_by_url, url}, _from, state) do
    sql =
      "SELECT id, url, name, status, pages_count, chunks_count, config, created_at, last_indexed FROM doc_sources WHERE url = ?"

    case fetch_one(state.conn, sql, [url]) do
      {:ok, [id, url, name, status, pages, chunks, config, created, indexed]} ->
        source = %{
          id: id,
          url: url,
          name: name,
          status: status,
          pages_count: pages,
          chunks_count: chunks,
          config: Jason.decode!(config || "{}"),
          created_at: created,
          last_indexed: indexed
        }

        {:reply, {:ok, source}, state}

      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_chunk, attrs}, _from, state) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = """
    INSERT INTO doc_chunks (id, source_id, url, title, content, position, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    params = [
      id,
      attrs[:source_id],
      attrs[:url],
      attrs[:title],
      attrs[:content],
      attrs[:position] || 0,
      now
    ]

    case execute_with_params(state.conn, sql, params) do
      :ok ->
        # Insert into FTS index
        fts_sql = "INSERT INTO doc_chunks_fts (source_id, title, content) VALUES (?, ?, ?)"

        execute_with_params(state.conn, fts_sql, [
          attrs[:source_id],
          attrs[:title],
          attrs[:content]
        ])

        {:reply, {:ok, %{id: id}}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_chunks, chunks}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Sqlite3.execute(state.conn, "BEGIN TRANSACTION;")

    count =
      Enum.reduce(chunks, 0, fn chunk, acc ->
        id = generate_id()

        sql = """
        INSERT INTO doc_chunks (id, source_id, url, title, content, position, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        params = [
          id,
          chunk[:source_id],
          chunk[:url],
          chunk[:title],
          chunk[:content],
          chunk[:position] || 0,
          now
        ]

        case execute_with_params(state.conn, sql, params) do
          :ok ->
            # FTS index
            fts_sql = "INSERT INTO doc_chunks_fts (source_id, title, content) VALUES (?, ?, ?)"

            execute_with_params(state.conn, fts_sql, [
              chunk[:source_id],
              chunk[:title],
              chunk[:content]
            ])

            acc + 1

          _ ->
            acc
        end
      end)

    Sqlite3.execute(state.conn, "COMMIT;")

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call({:search_chunks, query, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 5)
    sources = Keyword.get(opts, :sources, [])

    # Escape the query for FTS5
    escaped_query = escape_fts_query(query)

    # Query FTS5 directly - it contains all the content we need
    {sql, params} =
      if sources == [] do
        {"""
         SELECT rowid, source_id, title, content, bm25(doc_chunks_fts) as score
         FROM doc_chunks_fts
         WHERE doc_chunks_fts MATCH ?
         ORDER BY score
         LIMIT ?
         """, [escaped_query, limit]}
      else
        placeholders = sources |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")

        {"""
         SELECT rowid, source_id, title, content, bm25(doc_chunks_fts) as score
         FROM doc_chunks_fts
         WHERE doc_chunks_fts MATCH ? AND source_id IN (#{placeholders})
         ORDER BY score
         LIMIT ?
         """, [escaped_query] ++ sources ++ [limit]}
      end

    case fetch_all(state.conn, sql, params) do
      {:ok, rows} ->
        # Get the URL from doc_sources for each result
        chunks =
          Enum.map(rows, fn [rowid, source_id, title, content, score] ->
            # Look up the source URL
            url = get_source_url(state.conn, source_id)

            %{
              id: "fts_#{rowid}",
              source_id: source_id,
              url: url,
              title: title,
              content: content,
              position: 0,
              score: score
            }
          end)

        {:reply, {:ok, chunks}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_chunks_for_source, source_id}, _from, state) do
    sql = """
    SELECT id, source_id, url, title, content, position, created_at
    FROM doc_chunks
    WHERE source_id = ?
    ORDER BY position ASC
    """

    case fetch_all(state.conn, sql, [source_id]) do
      {:ok, rows} ->
        chunks =
          Enum.map(rows, fn [id, src_id, url, title, content, position, created_at] ->
            %{
              id: id,
              source_id: src_id,
              url: url,
              title: title,
              content: content,
              position: position,
              created_at: created_at
            }
          end)

        {:reply, {:ok, chunks}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_chunk, chunk_id}, _from, state) do
    sql = """
    SELECT id, source_id, url, title, content, position, created_at
    FROM doc_chunks
    WHERE id = ?
    LIMIT 1
    """

    case fetch_all(state.conn, sql, [chunk_id]) do
      {:ok, [[id, src_id, url, title, content, position, created_at]]} ->
        chunk = %{
          id: id,
          source_id: src_id,
          url: url,
          title: title,
          content: content,
          position: position,
          created_at: created_at
        }

        {:reply, {:ok, chunk}, state}

      {:ok, []} ->
        {:reply, {:error, :not_found}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Security Alert Handlers
  # ============================================================================

  @impl true
  def handle_call({:store_alert, attrs}, _from, state) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = """
    INSERT INTO security_alerts 
    (id, source_id, source_url, alert_type, severity, description, pattern_matched, detected_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    params = [
      id,
      attrs[:source_id],
      attrs[:source_url],
      to_string(attrs[:type]),
      to_string(attrs[:severity]),
      attrs[:description],
      attrs[:pattern_matched],
      now
    ]

    case execute_with_params(state.conn, sql, params) do
      :ok ->
        alert = Map.merge(attrs, %{id: id, detected_at: now})
        {:reply, {:ok, alert}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_alerts_for_source, source_id}, _from, state) do
    sql = """
    SELECT id, source_id, source_url, alert_type, severity, description, 
           pattern_matched, detected_at, resolved_at, resolution_note
    FROM security_alerts 
    WHERE source_id = ?
    ORDER BY detected_at DESC
    """

    case fetch_all(state.conn, sql, [source_id]) do
      {:ok, rows} ->
        alerts = Enum.map(rows, &row_to_alert/1)
        {:reply, {:ok, alerts}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:list_unresolved_alerts, opts}, _from, state) do
    _min_severity = Keyword.get(opts, :min_severity, "low")
    limit = Keyword.get(opts, :limit, 100)

    sql = """
    SELECT id, source_id, source_url, alert_type, severity, description,
           pattern_matched, detected_at, resolved_at, resolution_note
    FROM security_alerts
    WHERE resolved_at IS NULL
    ORDER BY 
      CASE severity 
        WHEN 'critical' THEN 1 
        WHEN 'high' THEN 2 
        WHEN 'medium' THEN 3 
        ELSE 4 
      END,
      detected_at DESC
    LIMIT ?
    """

    case fetch_all(state.conn, sql, [limit]) do
      {:ok, rows} ->
        alerts = Enum.map(rows, &row_to_alert/1)
        {:reply, {:ok, alerts}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:resolve_alert, alert_id, resolution_note}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = "UPDATE security_alerts SET resolved_at = ?, resolution_note = ? WHERE id = ?"

    case execute_with_params(state.conn, sql, [now, resolution_note, alert_id]) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:alert_stats, _from, state) do
    stats_sql = """
    SELECT 
      COUNT(*) as total,
      SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END) as unresolved,
      SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) as critical,
      SUM(CASE WHEN severity = 'high' THEN 1 ELSE 0 END) as high,
      SUM(CASE WHEN severity = 'medium' THEN 1 ELSE 0 END) as medium,
      SUM(CASE WHEN severity = 'low' THEN 1 ELSE 0 END) as low,
      COUNT(DISTINCT source_id) as sources_affected
    FROM security_alerts
    """

    case fetch_one(state.conn, stats_sql, []) do
      {:ok, [total, unresolved, critical, high, medium, low, sources]} ->
        stats = %{
          total: total || 0,
          unresolved: unresolved || 0,
          by_severity: %{
            critical: critical || 0,
            high: high || 0,
            medium: medium || 0,
            low: low || 0
          },
          sources_affected: sources || 0
        }

        {:reply, {:ok, stats}, state}

      error ->
        {:reply, error, state}
    end
  end

  # ============================================================================
  # Quarantine Handlers
  # ============================================================================

  @impl true
  def handle_call({:store_quarantine_item, attrs}, _from, state) do
    id = attrs[:id] || generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = """
    INSERT OR REPLACE INTO quarantine_items 
    (id, source_id, source_url, source_name, tier, raw_hash, snapshot_preview, snapshot_stats, validated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    params = [
      id,
      attrs[:source_id],
      attrs[:source_url],
      attrs[:source_name],
      to_string(attrs[:tier]),
      attrs[:raw_hash],
      attrs[:snapshot_preview],
      Jason.encode!(attrs[:snapshot_stats] || %{}),
      now
    ]

    case execute_with_params(state.conn, sql, params) do
      :ok ->
        item = Map.merge(attrs, %{id: id, validated_at: now})
        {:reply, {:ok, item}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:pending_quarantine_items, _from, state) do
    sql = """
    SELECT id, source_id, source_url, source_name, tier, raw_hash, 
           snapshot_preview, snapshot_stats, validated_at, reviewed_by, reviewed_at, review_action
    FROM quarantine_items
    WHERE reviewed_at IS NULL AND tier IN ('flagged', 'quarantined')
    ORDER BY validated_at DESC
    """

    case fetch_all(state.conn, sql, []) do
      {:ok, rows} ->
        items = Enum.map(rows, &row_to_quarantine_item/1)
        {:reply, {:ok, items}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:review_quarantine_item, item_id, reviewer, action}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Determine new tier based on action
    new_tier =
      case action do
        :approve -> "clean"
        :reject -> "blocked"
        :keep_flagged -> "flagged"
        _ -> "quarantined"
      end

    sql = """
    UPDATE quarantine_items 
    SET reviewed_by = ?, reviewed_at = ?, review_action = ?, tier = ?
    WHERE id = ?
    """

    case execute_with_params(state.conn, sql, [reviewer, now, to_string(action), new_tier, item_id]) do
      :ok ->
        case handle_call({:get_quarantine_item, item_id}, nil, state) do
          {:reply, {:ok, item}, _} -> {:reply, {:ok, item}, state}
          _ -> {:reply, {:ok, %{id: item_id, tier: new_tier}}, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_quarantine_item, item_id}, _from, state) do
    sql = """
    SELECT id, source_id, source_url, source_name, tier, raw_hash,
           snapshot_preview, snapshot_stats, validated_at, reviewed_by, reviewed_at, review_action
    FROM quarantine_items
    WHERE id = ?
    """

    case fetch_one(state.conn, sql, [item_id]) do
      {:ok, row} when is_list(row) ->
        item = row_to_quarantine_item(row)
        {:reply, {:ok, item}, state}

      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state[:conn] do
      Sqlite3.close(state.conn)
    end
  end

  # Private Functions

  # Helper to get source URL for search results
  defp get_source_url(conn, source_id) do
    case fetch_one(conn, "SELECT url FROM doc_sources WHERE id = ?", [source_id]) do
      {:ok, [url]} -> url
      _ -> nil
    end
  end

  defp execute_with_params(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        Sqlite3.bind(stmt, params)
        result = step_until_done(conn, stmt)
        Sqlite3.release(conn, stmt)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_one(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        Sqlite3.bind(stmt, params)

        result =
          case Sqlite3.step(conn, stmt) do
            {:row, row} -> {:ok, row}
            :done -> {:ok, nil}
            {:error, reason} -> {:error, reason}
          end

        Sqlite3.release(conn, stmt)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        Sqlite3.bind(stmt, params)
        rows = collect_rows(conn, stmt, [])
        Sqlite3.release(conn, stmt)
        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
      {:error, _reason} -> Enum.reverse(acc)
    end
  end

  defp step_until_done(conn, stmt) do
    case Sqlite3.step(conn, stmt) do
      {:row, _row} -> step_until_done(conn, stmt)
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp setup_schema(conn) do
    statements = [
      # Documentation sources
      """
      CREATE TABLE IF NOT EXISTS doc_sources (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL UNIQUE,
        name TEXT,
        status TEXT DEFAULT 'pending',
        pages_count INTEGER DEFAULT 0,
        chunks_count INTEGER DEFAULT 0,
        config TEXT,
        created_at TEXT,
        last_indexed TEXT
      )
      """,
      "CREATE INDEX IF NOT EXISTS idx_sources_status ON doc_sources(status)",

      # Content chunks
      """
      CREATE TABLE IF NOT EXISTS doc_chunks (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        position INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (source_id) REFERENCES doc_sources(id)
      )
      """,
      "CREATE INDEX IF NOT EXISTS idx_chunks_source ON doc_chunks(source_id)",

      # FTS5 virtual table for full-text search
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunks_fts USING fts5(
        source_id,
        title,
        content
      )
      """,

      # Scrape jobs
      """
      CREATE TABLE IF NOT EXISTS scrape_jobs (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        url TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        attempts INTEGER DEFAULT 0,
        error TEXT,
        created_at TEXT,
        started_at TEXT,
        completed_at TEXT,
        FOREIGN KEY (source_id) REFERENCES doc_sources(id)
      )
      """,
      "CREATE INDEX IF NOT EXISTS idx_jobs_source_status ON scrape_jobs(source_id, status)",

      # Security alerts - persistent storage (was ETS)
      """
      CREATE TABLE IF NOT EXISTS security_alerts (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_url TEXT NOT NULL,
        alert_type TEXT NOT NULL,
        severity TEXT NOT NULL,
        description TEXT,
        pattern_matched TEXT,
        detected_at TEXT NOT NULL,
        resolved_at TEXT,
        resolution_note TEXT,
        FOREIGN KEY (source_id) REFERENCES doc_sources(id)
      )
      """,
      "CREATE INDEX IF NOT EXISTS idx_alerts_source ON security_alerts(source_id)",
      "CREATE INDEX IF NOT EXISTS idx_alerts_severity ON security_alerts(severity)",
      "CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON security_alerts(resolved_at)",

      # Quarantine items - content pending review
      """
      CREATE TABLE IF NOT EXISTS quarantine_items (
        id TEXT PRIMARY KEY,
        source_id TEXT,
        source_url TEXT NOT NULL,
        source_name TEXT,
        tier TEXT NOT NULL,
        raw_hash TEXT NOT NULL,
        snapshot_preview TEXT,
        snapshot_stats TEXT,
        validated_at TEXT NOT NULL,
        reviewed_by TEXT,
        reviewed_at TEXT,
        review_action TEXT
      )
      """,
      "CREATE INDEX IF NOT EXISTS idx_quarantine_tier ON quarantine_items(tier)",
      "CREATE INDEX IF NOT EXISTS idx_quarantine_reviewed ON quarantine_items(reviewed_at)"
    ]

    Enum.each(statements, fn sql ->
      case Sqlite3.execute(conn, sql) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Schema statement failed: #{inspect(reason)}")
      end
    end)

    Logger.info("Database schema setup complete")
    :ok
  end

  defp build_update_params(attrs) do
    allowed = [:status, :pages_count, :chunks_count, :last_indexed, :name]

    {sets, params} =
      Enum.reduce(allowed, {[], []}, fn key, {sets, params} ->
        case Map.get(attrs, key) do
          nil ->
            {sets, params}

          {:increment, val} ->
            col = Atom.to_string(key)
            {["#{col} = #{col} + ?" | sets], [val | params]}

          val ->
            col = Atom.to_string(key)
            {["#{col} = ?" | sets], [val | params]}
        end
      end)

    {sets |> Enum.reverse() |> Enum.join(", "), Enum.reverse(params)}
  end

  defp escape_fts_query(query) do
    # FTS5 query - join terms with OR for broader matching
    query
    |> String.trim()
    # Remove special chars
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" OR ")
  end

  defp default_db_path do
    Path.expand("~/.local/share/cursor-docs/#{@db_name}")
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp row_to_alert([id, source_id, source_url, alert_type, severity, description,
                     pattern_matched, detected_at, resolved_at, resolution_note]) do
    %{
      id: id,
      source_id: source_id,
      source_url: source_url,
      type: String.to_atom(alert_type),
      severity: String.to_atom(severity),
      description: description,
      pattern_matched: pattern_matched,
      detected_at: detected_at,
      resolved_at: resolved_at,
      resolution_note: resolution_note
    }
  end

  defp row_to_quarantine_item([id, source_id, source_url, source_name, tier, raw_hash,
                               snapshot_preview, snapshot_stats, validated_at,
                               reviewed_by, reviewed_at, review_action]) do
    %{
      id: id,
      source_id: source_id,
      source_url: source_url,
      source_name: source_name,
      tier: String.to_atom(tier),
      raw_hash: raw_hash,
      snapshot: %{
        preview: snapshot_preview,
        stats: Jason.decode!(snapshot_stats || "{}")
      },
      validated_at: validated_at,
      reviewed_by: reviewed_by,
      reviewed_at: reviewed_at,
      review_action: if(review_action, do: String.to_atom(review_action), else: nil)
    }
  end
end
