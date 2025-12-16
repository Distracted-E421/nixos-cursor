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

  # Helper to get source URL for search results
  defp get_source_url(conn, source_id) do
    case fetch_one(conn, "SELECT url FROM doc_sources WHERE id = ?", [source_id]) do
      {:ok, [url]} -> url
      _ -> nil
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state[:conn] do
      Sqlite3.close(state.conn)
    end
  end

  # Private Functions

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
      "CREATE INDEX IF NOT EXISTS idx_jobs_source_status ON scrape_jobs(source_id, status)"
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
        chunks = Enum.map(rows, fn [id, src_id, url, title, content, position, created_at] ->
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
end
