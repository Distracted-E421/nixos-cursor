defmodule CursorDocs.Storage.SQLite do
  @moduledoc """
  SQLite storage backend for CursorDocs.

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
  Search chunks using FTS5.
  """
  @spec search_chunks(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search_chunks(query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_chunks, query, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, default_db_path())

    # Ensure directory exists
    db_path |> Path.dirname() |> File.mkdir_p!()

    Logger.info("Opening SQLite database at #{db_path}")

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        # Enable WAL mode for better concurrency
        Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
        Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous=NORMAL")

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
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
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

    case Exqlite.Sqlite3.execute(state.conn, sql, params) do
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
      sql = "UPDATE doc_sources SET #{sets} WHERE id = ?#{length(params) + 1}"
      params = params ++ [id]

      case Exqlite.Sqlite3.execute(state.conn, sql, params) do
        :ok -> {:reply, {:ok, %{id: id}}, state}
        error -> {:reply, error, state}
      end
    else
      {:reply, {:ok, %{id: id}}, state}
    end
  end

  @impl true
  def handle_call({:get_source, id}, _from, state) do
    sql = "SELECT id, url, name, status, pages_count, chunks_count, config, created_at, last_indexed FROM doc_sources WHERE id = ?1"

    case Exqlite.Sqlite3.execute(state.conn, sql, [id]) do
      {:ok, [[id, url, name, status, pages, chunks, config, created, indexed]]} ->
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

      {:ok, []} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_sources, _from, state) do
    sql = "SELECT id, url, name, status, pages_count, chunks_count, created_at, last_indexed FROM doc_sources ORDER BY created_at DESC"

    case Exqlite.Sqlite3.execute(state.conn, sql) do
      {:ok, rows} ->
        sources = Enum.map(rows, fn [id, url, name, status, pages, chunks, created, indexed] ->
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
    # Delete chunks first (FTS)
    Exqlite.Sqlite3.execute(state.conn, "DELETE FROM doc_chunks_fts WHERE source_id = ?1", [id])
    Exqlite.Sqlite3.execute(state.conn, "DELETE FROM doc_chunks WHERE source_id = ?1", [id])
    Exqlite.Sqlite3.execute(state.conn, "DELETE FROM scrape_jobs WHERE source_id = ?1", [id])
    Exqlite.Sqlite3.execute(state.conn, "DELETE FROM doc_sources WHERE id = ?1", [id])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:store_chunk, attrs}, _from, state) do
    id = generate_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    sql = """
    INSERT INTO doc_chunks (id, source_id, url, title, content, position, created_at)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    """

    params = [id, attrs[:source_id], attrs[:url], attrs[:title], attrs[:content], attrs[:position], now]

    case Exqlite.Sqlite3.execute(state.conn, sql, params) do
      :ok ->
        # Insert into FTS index
        fts_sql = "INSERT INTO doc_chunks_fts (rowid, source_id, title, content) VALUES (last_insert_rowid(), ?1, ?2, ?3)"
        Exqlite.Sqlite3.execute(state.conn, fts_sql, [attrs[:source_id], attrs[:title], attrs[:content]])

        {:reply, {:ok, %{id: id}}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_chunks, chunks}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Exqlite.Sqlite3.execute(state.conn, "BEGIN TRANSACTION")

    count =
      Enum.reduce(chunks, 0, fn chunk, acc ->
        id = generate_id()

        sql = """
        INSERT INTO doc_chunks (id, source_id, url, title, content, position, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        """

        params = [id, chunk[:source_id], chunk[:url], chunk[:title], chunk[:content], chunk[:position], now]

        case Exqlite.Sqlite3.execute(state.conn, sql, params) do
          :ok ->
            # FTS index
            fts_sql = "INSERT INTO doc_chunks_fts (source_id, title, content) VALUES (?1, ?2, ?3)"
            Exqlite.Sqlite3.execute(state.conn, fts_sql, [chunk[:source_id], chunk[:title], chunk[:content]])
            acc + 1

          _ ->
            acc
        end
      end)

    Exqlite.Sqlite3.execute(state.conn, "COMMIT")

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call({:search_chunks, query, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 5)
    sources = Keyword.get(opts, :sources, [])

    # FTS5 search
    {sql, params} =
      if sources == [] do
        {"""
        SELECT c.id, c.source_id, c.url, c.title, c.content, c.position,
               bm25(doc_chunks_fts) as score
        FROM doc_chunks_fts fts
        JOIN doc_chunks c ON c.id = fts.rowid
        WHERE doc_chunks_fts MATCH ?1
        ORDER BY score
        LIMIT ?2
        """, [query, limit]}
      else
        placeholders = sources |> Enum.with_index(3) |> Enum.map(fn {_, i} -> "?#{i}" end) |> Enum.join(", ")
        {"""
        SELECT c.id, c.source_id, c.url, c.title, c.content, c.position,
               bm25(doc_chunks_fts) as score
        FROM doc_chunks_fts fts
        JOIN doc_chunks c ON c.id = fts.rowid
        WHERE doc_chunks_fts MATCH ?1 AND c.source_id IN (#{placeholders})
        ORDER BY score
        LIMIT ?2
        """, [query, limit] ++ sources}
      end

    case Exqlite.Sqlite3.execute(state.conn, sql, params) do
      {:ok, rows} ->
        chunks = Enum.map(rows, fn [id, source_id, url, title, content, position, score] ->
          %{
            id: id,
            source_id: source_id,
            url: url,
            title: title,
            content: content,
            position: position,
            score: score
          }
        end)
        {:reply, {:ok, chunks}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state[:conn] do
      Exqlite.Sqlite3.close(state.conn)
    end
  end

  # Private Functions

  defp setup_schema(conn) do
    schema = """
    -- Documentation sources
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
    );

    CREATE INDEX IF NOT EXISTS idx_sources_status ON doc_sources(status);

    -- Content chunks
    CREATE TABLE IF NOT EXISTS doc_chunks (
      id TEXT PRIMARY KEY,
      source_id TEXT NOT NULL,
      url TEXT NOT NULL,
      title TEXT,
      content TEXT NOT NULL,
      position INTEGER DEFAULT 0,
      created_at TEXT,
      FOREIGN KEY (source_id) REFERENCES doc_sources(id)
    );

    CREATE INDEX IF NOT EXISTS idx_chunks_source ON doc_chunks(source_id);

    -- FTS5 virtual table for full-text search
    CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunks_fts USING fts5(
      source_id,
      title,
      content,
      content=doc_chunks,
      content_rowid=rowid
    );

    -- Scrape jobs
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
    );

    CREATE INDEX IF NOT EXISTS idx_jobs_source_status ON scrape_jobs(source_id, status);
    """

    # Execute each statement separately
    schema
    |> String.split(";")
    |> Enum.each(fn stmt ->
      stmt = String.trim(stmt)
      if stmt != "" do
        Exqlite.Sqlite3.execute(conn, stmt)
      end
    end)

    Logger.info("Database schema setup complete")
    :ok
  end

  defp build_update_params(attrs) do
    allowed = [:status, :pages_count, :chunks_count, :last_indexed, :name]

    {sets, params, _idx} =
      Enum.reduce(allowed, {[], [], 1}, fn key, {sets, params, idx} ->
        case Map.get(attrs, key) do
          nil ->
            {sets, params, idx}

          {:increment, val} ->
            col = Atom.to_string(key)
            {["#{col} = #{col} + ?#{idx}" | sets], [val | params], idx + 1}

          val ->
            col = Atom.to_string(key)
            {["#{col} = ?#{idx}" | sets], [val | params], idx + 1}
        end
      end)

    {sets |> Enum.reverse() |> Enum.join(", "), Enum.reverse(params)}
  end

  defp default_db_path do
    Path.expand("~/.local/share/cursor-docs/#{@db_name}")
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end

