defmodule CursorDocs.Storage.Vector.SQLiteVss do
  @moduledoc """
  sqlite-vss vector storage backend.

  Embedded vector search using the sqlite-vss extension.
  No daemon required - vectors stored in the same SQLite file.

  ## Features

  - **Embedded**: Single file, no server process
  - **Portable**: Copy the DB file anywhere
  - **Efficient**: ~50k vectors with good performance
  - **ANN Search**: Approximate nearest neighbor via IVF

  ## Requirements

  The sqlite-vss extension must be available:
  - NixOS: `pkgs.sqlite-vss` or build from source
  - macOS: `brew install sqlite-vss`
  - Linux: Build from https://github.com/asg017/sqlite-vss

  ## Schema

      -- Vector index using IVF (Inverted File Index)
      CREATE VIRTUAL TABLE IF NOT EXISTS vss_chunks USING vss0(
        embedding(768)  -- Adjust dimensions per model
      );

      -- Metadata table linking vectors to chunks
      CREATE TABLE IF NOT EXISTS vss_metadata (
        rowid INTEGER PRIMARY KEY,
        chunk_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(chunk_id)
      );

  ## Configuration

      config :cursor_docs, CursorDocs.Storage.Vector.SQLiteVss,
        db_path: "~/.local/share/cursor-docs/vectors.db",
        dimensions: 768,  # Must match embedding model
        ef_construction: 200,  # Index quality (higher = better, slower)
        ef_search: 100  # Search quality (higher = better, slower)

  """

  @behaviour CursorDocs.Storage.Vector

  use GenServer
  require Logger

  @default_dimensions 768
  @default_db_path "~/.local/share/cursor-docs/vectors.db"

  # ============================================================================
  # Behaviour Implementation
  # ============================================================================

  @impl true
  def name, do: "sqlite-vss (Embedded)"

  @impl true
  def available? do
    # Check if sqlite-vss extension is loadable
    case check_vss_extension() do
      :ok -> true
      {:error, _} -> false
    end
  end

  @impl true
  def tier, do: :embedded

  @impl true
  def start(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def store(chunk_id, embedding, metadata) do
    GenServer.call(__MODULE__, {:store, chunk_id, embedding, metadata})
  end

  @impl true
  def store_batch(items) do
    GenServer.call(__MODULE__, {:store_batch, items}, 60_000)
  end

  @impl true
  def search(embedding, opts) do
    GenServer.call(__MODULE__, {:search, embedding, opts})
  end

  @impl true
  def delete_for_source(source_id) do
    GenServer.call(__MODULE__, {:delete_for_source, source_id})
  end

  @impl true
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def healthy? do
    case GenServer.call(__MODULE__, :health_check) do
      :ok -> true
      _ -> false
    end
  catch
    :exit, _ -> false
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl GenServer
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, config(:db_path, @default_db_path))
    |> Path.expand()

    dimensions = Keyword.get(opts, :dimensions, config(:dimensions, @default_dimensions))

    # Ensure directory exists
    db_path |> Path.dirname() |> File.mkdir_p!()

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        case setup_schema(conn, dimensions) do
          :ok ->
            Logger.info("sqlite-vss initialized at #{db_path} (#{dimensions} dimensions)")
            {:ok, %{conn: conn, db_path: db_path, dimensions: dimensions}}

          {:error, reason} ->
            Logger.error("Failed to setup sqlite-vss schema: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to open sqlite-vss database: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:store, chunk_id, embedding, metadata}, _from, state) do
    result = do_store(state.conn, chunk_id, embedding, metadata, state.dimensions)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:store_batch, items}, _from, state) do
    result = do_store_batch(state.conn, items, state.dimensions)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:search, embedding, opts}, _from, state) do
    result = do_search(state.conn, embedding, opts, state.dimensions)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete_for_source, source_id}, _from, state) do
    result = do_delete_for_source(state.conn, source_id)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    result = do_stats(state.conn, state.dimensions)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    result = case Exqlite.Sqlite3.execute(state.conn, "SELECT 1") do
      :ok -> :ok
      {:error, _} = err -> err
    end
    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp check_vss_extension do
    # Try to load the extension in a temporary database
    db_path = Path.join(System.tmp_dir!(), "vss_check_#{:rand.uniform(100000)}.db")

    try do
      case Exqlite.Sqlite3.open(db_path) do
        {:ok, conn} ->
          # Try to create a vss table
          result = Exqlite.Sqlite3.execute(conn, """
            CREATE VIRTUAL TABLE IF NOT EXISTS vss_test USING vss0(test_vec(4))
          """)

          Exqlite.Sqlite3.close(conn)
          File.rm(db_path)

          case result do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp setup_schema(conn, dimensions) do
    # Create the VSS virtual table
    vss_sql = """
    CREATE VIRTUAL TABLE IF NOT EXISTS vss_chunks USING vss0(
      embedding(#{dimensions})
    )
    """

    # Create metadata table
    metadata_sql = """
    CREATE TABLE IF NOT EXISTS vss_metadata (
      rowid INTEGER PRIMARY KEY,
      chunk_id TEXT NOT NULL UNIQUE,
      source_id TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    """

    # Create index on source_id for efficient deletion
    index_sql = """
    CREATE INDEX IF NOT EXISTS idx_vss_metadata_source
    ON vss_metadata(source_id)
    """

    with :ok <- Exqlite.Sqlite3.execute(conn, vss_sql),
         :ok <- Exqlite.Sqlite3.execute(conn, metadata_sql),
         :ok <- Exqlite.Sqlite3.execute(conn, index_sql) do
      :ok
    end
  end

  defp do_store(conn, chunk_id, embedding, metadata, expected_dims) do
    if length(embedding) != expected_dims do
      {:error, {:dimension_mismatch, length(embedding), expected_dims}}
    else
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      source_id = metadata[:source_id] || "unknown"

      # Start transaction
      :ok = Exqlite.Sqlite3.execute(conn, "BEGIN TRANSACTION")

      try do
        # Insert into VSS table
        embedding_json = Jason.encode!(embedding)
        vss_sql = "INSERT INTO vss_chunks(embedding) VALUES (?)"

        {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, vss_sql)
        :ok = Exqlite.Sqlite3.bind(stmt, [embedding_json])
        :done = Exqlite.Sqlite3.step(conn, stmt)
        :ok = Exqlite.Sqlite3.release(conn, stmt)

        # Get the rowid
        {:ok, rowid_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT last_insert_rowid()")
        {:row, [rowid]} = Exqlite.Sqlite3.step(conn, rowid_stmt)
        :ok = Exqlite.Sqlite3.release(conn, rowid_stmt)

        # Insert metadata
        meta_sql = """
        INSERT OR REPLACE INTO vss_metadata (rowid, chunk_id, source_id, created_at)
        VALUES (?, ?, ?, ?)
        """

        {:ok, meta_stmt} = Exqlite.Sqlite3.prepare(conn, meta_sql)
        :ok = Exqlite.Sqlite3.bind(meta_stmt, [rowid, chunk_id, source_id, now])
        :done = Exqlite.Sqlite3.step(conn, meta_stmt)
        :ok = Exqlite.Sqlite3.release(conn, meta_stmt)

        :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")
        :ok
      rescue
        e ->
          Exqlite.Sqlite3.execute(conn, "ROLLBACK")
          {:error, Exception.message(e)}
      end
    end
  end

  defp do_store_batch(conn, items, expected_dims) do
    :ok = Exqlite.Sqlite3.execute(conn, "BEGIN TRANSACTION")

    try do
      count = Enum.reduce(items, 0, fn {chunk_id, embedding, metadata}, acc ->
        case do_store_single(conn, chunk_id, embedding, metadata, expected_dims) do
          :ok -> acc + 1
          {:error, _} -> acc
        end
      end)

      :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")
      {:ok, count}
    rescue
      e ->
        Exqlite.Sqlite3.execute(conn, "ROLLBACK")
        {:error, Exception.message(e)}
    end
  end

  defp do_store_single(conn, chunk_id, embedding, metadata, expected_dims) do
    if length(embedding) != expected_dims do
      {:error, {:dimension_mismatch, length(embedding), expected_dims}}
    else
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      source_id = metadata[:source_id] || "unknown"

      embedding_json = Jason.encode!(embedding)
      vss_sql = "INSERT INTO vss_chunks(embedding) VALUES (?)"

      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, vss_sql)
      :ok = Exqlite.Sqlite3.bind(stmt, [embedding_json])
      :done = Exqlite.Sqlite3.step(conn, stmt)
      :ok = Exqlite.Sqlite3.release(conn, stmt)

      # Get the rowid
      {:ok, rowid_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT last_insert_rowid()")
      {:row, [rowid]} = Exqlite.Sqlite3.step(conn, rowid_stmt)
      :ok = Exqlite.Sqlite3.release(conn, rowid_stmt)

      # Insert metadata
      meta_sql = """
      INSERT OR REPLACE INTO vss_metadata (rowid, chunk_id, source_id, created_at)
      VALUES (?, ?, ?, ?)
      """

      {:ok, meta_stmt} = Exqlite.Sqlite3.prepare(conn, meta_sql)
      :ok = Exqlite.Sqlite3.bind(meta_stmt, [rowid, chunk_id, source_id, now])
      :done = Exqlite.Sqlite3.step(conn, meta_stmt)
      :ok = Exqlite.Sqlite3.release(conn, meta_stmt)

      :ok
    end
  end

  defp do_search(conn, embedding, opts, expected_dims) do
    if length(embedding) != expected_dims do
      {:error, {:dimension_mismatch, length(embedding), expected_dims}}
    else
      limit = Keyword.get(opts, :limit, 10)
      embedding_json = Jason.encode!(embedding)

      # VSS search query
      sql = """
      SELECT
        m.chunk_id,
        m.source_id,
        vss_distance_l2(v.embedding, ?) as distance
      FROM vss_chunks v
      JOIN vss_metadata m ON v.rowid = m.rowid
      ORDER BY distance ASC
      LIMIT ?
      """

      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)
      :ok = Exqlite.Sqlite3.bind(stmt, [embedding_json, limit])

      results = collect_rows(conn, stmt, [])
      :ok = Exqlite.Sqlite3.release(conn, stmt)

      formatted = Enum.map(results, fn [chunk_id, source_id, distance] ->
        # Convert L2 distance to similarity score (0-1)
        score = 1.0 / (1.0 + distance)

        %{
          chunk_id: chunk_id,
          score: score,
          metadata: %{source_id: source_id, distance: distance}
        }
      end)

      {:ok, formatted}
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
    end
  end

  defp do_delete_for_source(conn, source_id) do
    :ok = Exqlite.Sqlite3.execute(conn, "BEGIN TRANSACTION")

    try do
      # Get rowids to delete
      select_sql = "SELECT rowid FROM vss_metadata WHERE source_id = ?"
      {:ok, select_stmt} = Exqlite.Sqlite3.prepare(conn, select_sql)
      :ok = Exqlite.Sqlite3.bind(select_stmt, [source_id])

      rowids = collect_rows(conn, select_stmt, []) |> Enum.map(fn [id] -> id end)
      :ok = Exqlite.Sqlite3.release(conn, select_stmt)

      # Delete from VSS table
      Enum.each(rowids, fn rowid ->
        delete_vss = "DELETE FROM vss_chunks WHERE rowid = ?"
        {:ok, del_stmt} = Exqlite.Sqlite3.prepare(conn, delete_vss)
        :ok = Exqlite.Sqlite3.bind(del_stmt, [rowid])
        :done = Exqlite.Sqlite3.step(conn, del_stmt)
        :ok = Exqlite.Sqlite3.release(conn, del_stmt)
      end)

      # Delete from metadata table
      delete_meta = "DELETE FROM vss_metadata WHERE source_id = ?"
      {:ok, meta_stmt} = Exqlite.Sqlite3.prepare(conn, delete_meta)
      :ok = Exqlite.Sqlite3.bind(meta_stmt, [source_id])
      :done = Exqlite.Sqlite3.step(conn, meta_stmt)
      :ok = Exqlite.Sqlite3.release(conn, meta_stmt)

      :ok = Exqlite.Sqlite3.execute(conn, "COMMIT")
      :ok
    rescue
      e ->
        Exqlite.Sqlite3.execute(conn, "ROLLBACK")
        {:error, Exception.message(e)}
    end
  end

  defp do_stats(conn, dimensions) do
    # Count vectors
    {:ok, count_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM vss_metadata")
    {:row, [count]} = Exqlite.Sqlite3.step(conn, count_stmt)
    :ok = Exqlite.Sqlite3.release(conn, count_stmt)

    # Estimate storage (rough: dimensions * 4 bytes per float * count)
    storage_bytes = count * dimensions * 4

    %{
      total_vectors: count,
      dimensions: dimensions,
      storage_bytes: storage_bytes
    }
  end

  defp config(key, default) do
    Application.get_env(:cursor_docs, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
