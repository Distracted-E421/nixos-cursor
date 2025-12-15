defmodule CursorDocs.Storage.Surreal do
  @moduledoc """
  SurrealDB client for CursorDocs storage.

  Manages:
  - Database connection and lifecycle
  - Schema setup and migrations
  - CRUD operations for doc sources and chunks
  - Full-text search queries

  ## Schema

  ### doc_sources
  Stores metadata about documentation sources.

      {
        id: "source:abc123",
        url: "https://docs.example.com/",
        name: "Example Docs",
        status: "indexed" | "indexing" | "failed",
        pages_count: 234,
        chunks_count: 1456,
        last_indexed: "2024-01-15T12:00:00Z",
        created_at: "2024-01-10T08:00:00Z",
        config: { max_pages: 100, depth: 3 }
      }

  ### doc_chunks
  Stores content chunks with full-text search index.

      {
        id: "chunk:xyz789",
        source_id: "source:abc123",
        url: "https://docs.example.com/api/auth",
        title: "Authentication",
        content: "To authenticate...",
        position: 0,
        created_at: "2024-01-15T12:00:00Z"
      }

  ### scrape_jobs
  Tracks scraping job status.

      {
        id: "job:def456",
        source_id: "source:abc123",
        url: "https://docs.example.com/api/auth",
        status: "pending" | "processing" | "complete" | "failed",
        attempts: 0,
        error: null,
        created_at: "2024-01-15T12:00:00Z"
      }
  """

  use GenServer

  require Logger

  @default_namespace "cursor_docs"
  @default_database "main"

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Setup database schema.
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
  Get a documentation source by ID.
  """
  @spec get_source(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_source(id) do
    GenServer.call(__MODULE__, {:get_source, id})
  end

  @doc """
  List all documentation sources.
  """
  @spec list_sources() :: {:ok, list(map())}
  def list_sources do
    GenServer.call(__MODULE__, :list_sources)
  end

  @doc """
  Remove a documentation source and all its chunks.
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
  Full-text search for chunks.
  """
  @spec search_chunks(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search_chunks(query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_chunks, query, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, "~/.local/share/cursor-docs") |> Path.expand()
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    database = Keyword.get(opts, :database, @default_database)

    Logger.info("Initializing SurrealDB at #{path}")

    # Ensure directory exists
    File.mkdir_p!(path)

    state = %{
      path: path,
      namespace: namespace,
      database: database,
      conn: nil
    }

    # Connect asynchronously
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect(state) do
      {:ok, conn} ->
        Logger.info("Connected to SurrealDB")
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.error("Failed to connect to SurrealDB: #{inspect(reason)}")
        # Retry in 5 seconds
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:setup, _from, state) do
    result = setup_schema(state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_source, attrs}, _from, state) do
    id = generate_id("source")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    source = Map.merge(attrs, %{
      id: id,
      status: "pending",
      pages_count: 0,
      chunks_count: 0,
      created_at: now
    })

    query = """
    CREATE doc_sources CONTENT $source
    """

    result = execute(state.conn, query, %{source: source})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_source, id, attrs}, _from, state) do
    query = """
    UPDATE doc_sources:$id MERGE $attrs
    """

    result = execute(state.conn, query, %{id: id, attrs: attrs})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_source, id}, _from, state) do
    query = "SELECT * FROM doc_sources:$id"

    case execute(state.conn, query, %{id: id}) do
      {:ok, [source]} -> {:reply, {:ok, source}, state}
      {:ok, []} -> {:reply, {:error, :not_found}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_sources, _from, state) do
    query = "SELECT * FROM doc_sources ORDER BY created_at DESC"
    result = execute(state.conn, query, %{})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_source, id}, _from, state) do
    queries = [
      "DELETE FROM doc_chunks WHERE source_id = $id",
      "DELETE FROM scrape_jobs WHERE source_id = $id",
      "DELETE FROM doc_sources:$id"
    ]

    results = Enum.map(queries, &execute(state.conn, &1, %{id: id}))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:reply, :ok, state}
    else
      {:reply, {:error, :delete_failed}, state}
    end
  end

  @impl true
  def handle_call({:store_chunk, attrs}, _from, state) do
    id = generate_id("chunk")
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    chunk = Map.merge(attrs, %{
      id: id,
      created_at: now
    })

    query = "CREATE doc_chunks CONTENT $chunk"
    result = execute(state.conn, query, %{chunk: chunk})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:store_chunks, chunks}, _from, state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    prepared_chunks =
      Enum.map(chunks, fn chunk ->
        Map.merge(chunk, %{
          id: generate_id("chunk"),
          created_at: now
        })
      end)

    query = """
    FOR $chunk IN $chunks {
      CREATE doc_chunks CONTENT $chunk
    }
    """

    case execute(state.conn, query, %{chunks: prepared_chunks}) do
      {:ok, _} -> {:reply, {:ok, length(prepared_chunks)}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:search_chunks, query, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 5)
    sources = Keyword.get(opts, :sources, [])

    surql =
      if sources == [] do
        """
        SELECT *, search::score(1) AS score
        FROM doc_chunks
        WHERE content @1@ $query
        ORDER BY score DESC
        LIMIT $limit
        """
      else
        """
        SELECT *, search::score(1) AS score
        FROM doc_chunks
        WHERE content @1@ $query AND source_id IN $sources
        ORDER BY score DESC
        LIMIT $limit
        """
      end

    params = %{query: query, limit: limit, sources: sources}
    result = execute(state.conn, surql, params)
    {:reply, result, state}
  end

  # Private Functions

  defp connect(state) do
    # This is a placeholder - actual SurrealDB connection would use their Elixir client
    # For now, we'll simulate with a simple state
    {:ok, %{path: state.path, namespace: state.namespace, database: state.database}}
  end

  defp setup_schema(conn) do
    schema = """
    -- Documentation sources
    DEFINE TABLE doc_sources SCHEMAFULL;
    DEFINE FIELD url ON doc_sources TYPE string;
    DEFINE FIELD name ON doc_sources TYPE string;
    DEFINE FIELD status ON doc_sources TYPE string;
    DEFINE FIELD pages_count ON doc_sources TYPE int DEFAULT 0;
    DEFINE FIELD chunks_count ON doc_sources TYPE int DEFAULT 0;
    DEFINE FIELD last_indexed ON doc_sources TYPE datetime;
    DEFINE FIELD created_at ON doc_sources TYPE datetime;
    DEFINE FIELD config ON doc_sources TYPE object;
    DEFINE INDEX url_idx ON doc_sources FIELDS url UNIQUE;

    -- Content chunks with full-text search
    DEFINE TABLE doc_chunks SCHEMAFULL;
    DEFINE FIELD source_id ON doc_chunks TYPE string;
    DEFINE FIELD url ON doc_chunks TYPE string;
    DEFINE FIELD title ON doc_chunks TYPE string;
    DEFINE FIELD content ON doc_chunks TYPE string;
    DEFINE FIELD position ON doc_chunks TYPE int;
    DEFINE FIELD created_at ON doc_chunks TYPE datetime;
    DEFINE INDEX source_idx ON doc_chunks FIELDS source_id;
    DEFINE ANALYZER vs TOKENIZERS blank,class FILTERS ascii,lowercase,snowball(english);
    DEFINE INDEX content_fts ON doc_chunks FIELDS content SEARCH ANALYZER vs BM25;

    -- Scrape jobs
    DEFINE TABLE scrape_jobs SCHEMAFULL;
    DEFINE FIELD source_id ON scrape_jobs TYPE string;
    DEFINE FIELD url ON scrape_jobs TYPE string;
    DEFINE FIELD status ON scrape_jobs TYPE string DEFAULT 'pending';
    DEFINE FIELD attempts ON scrape_jobs TYPE int DEFAULT 0;
    DEFINE FIELD error ON scrape_jobs TYPE option<string>;
    DEFINE FIELD created_at ON scrape_jobs TYPE datetime;
    DEFINE INDEX source_status_idx ON scrape_jobs FIELDS source_id, status;
    """

    execute(conn, schema, %{})
  end

  defp execute(_conn, _query, _params) do
    # Placeholder for actual SurrealDB query execution
    # In real implementation, this would use the surrealdb Elixir client
    {:ok, []}
  end

  defp generate_id(prefix) do
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{prefix}:#{random}"
  end
end
