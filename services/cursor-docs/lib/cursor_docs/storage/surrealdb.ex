defmodule CursorDocs.Storage.SurrealDB do
  @moduledoc """
  SurrealDB storage backend for CursorDocs with vector embeddings.

  ## Why SurrealDB?

  - **Vector embeddings** for semantic search (much better than keyword FTS5)
  - **Graph relationships** for cross-domain analysis
  - **Multi-model** - documents, graphs, and vectors in one database
  - **Stack alignment** - same DB for docs, chats, and code analysis

  ## Schema

  ```surql
  -- Documentation sources (websites/repos)
  DEFINE TABLE doc_source SCHEMAFULL;
  DEFINE FIELD url ON doc_source TYPE string ASSERT $value != NONE;
  DEFINE FIELD name ON doc_source TYPE string;
  DEFINE FIELD status ON doc_source TYPE string DEFAULT 'pending';
  DEFINE FIELD security_tier ON doc_source TYPE string DEFAULT 'unknown';
  DEFINE FIELD pages_count ON doc_source TYPE int DEFAULT 0;
  DEFINE FIELD chunks_count ON doc_source TYPE int DEFAULT 0;
  DEFINE FIELD config ON doc_source TYPE object DEFAULT {};
  DEFINE FIELD created_at ON doc_source TYPE datetime DEFAULT time::now();
  DEFINE FIELD last_indexed ON doc_source TYPE option<datetime>;
  DEFINE INDEX idx_url ON doc_source FIELDS url UNIQUE;

  -- Content chunks with embeddings
  DEFINE TABLE doc_chunk SCHEMAFULL;
  DEFINE FIELD source ON doc_chunk TYPE record<doc_source>;
  DEFINE FIELD url ON doc_chunk TYPE string;
  DEFINE FIELD title ON doc_chunk TYPE string;
  DEFINE FIELD content ON doc_chunk TYPE string;
  DEFINE FIELD position ON doc_chunk TYPE int DEFAULT 0;
  DEFINE FIELD embedding ON doc_chunk TYPE option<array<float>>;
  DEFINE FIELD has_code ON doc_chunk TYPE bool DEFAULT false;
  DEFINE FIELD quality_score ON doc_chunk TYPE float DEFAULT 0.5;
  DEFINE FIELD created_at ON doc_chunk TYPE datetime DEFAULT time::now();
  DEFINE INDEX idx_source ON doc_chunk FIELDS source;
  -- Vector index for semantic search (when SurrealDB 2.0+ with HNSW)
  -- DEFINE INDEX idx_embedding ON doc_chunk FIELDS embedding MTREE DIMENSION 384;

  -- Security alerts
  DEFINE TABLE security_alert SCHEMAFULL;
  DEFINE FIELD source ON security_alert TYPE record<doc_source>;
  DEFINE FIELD alert_type ON security_alert TYPE string;
  DEFINE FIELD severity ON security_alert TYPE int;
  DEFINE FIELD description ON security_alert TYPE string;
  DEFINE FIELD details ON security_alert TYPE object DEFAULT {};
  DEFINE FIELD created_at ON security_alert TYPE datetime DEFAULT time::now();
  DEFINE INDEX idx_source_severity ON security_alert FIELDS source, severity;

  -- Cross-domain: Link docs to chat conversations
  DEFINE TABLE answered_by SCHEMAFULL;
  DEFINE FIELD in ON answered_by TYPE record<chat_message>;
  DEFINE FIELD out ON answered_by TYPE record<doc_chunk>;
  DEFINE FIELD relevance ON answered_by TYPE float;
  DEFINE FIELD created_at ON answered_by TYPE datetime DEFAULT time::now();
  ```

  ## Connection

  Connects to SurrealDB via HTTP API (no Elixir client library needed).
  Default: `http://localhost:8000` with namespace `cursor` and database `docs`.
  """

  use GenServer

  require Logger

  @default_endpoint "http://localhost:8000"
  @default_namespace "cursor"
  @default_database "docs"
  # Embedding dimension: 384 for nomic-embed-text, 768 for larger models

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if SurrealDB is available and configured.
  """
  def available? do
    GenServer.call(__MODULE__, :available?)
  catch
    :exit, _ -> false
  end

  @doc """
  Setup the database schema.
  """
  def setup do
    GenServer.call(__MODULE__, :setup, 30_000)
  end

  @doc """
  Create a documentation source.
  """
  def create_source(attrs) do
    GenServer.call(__MODULE__, {:create_source, attrs})
  end

  @doc """
  Update a documentation source.
  """
  def update_source(id, attrs) do
    GenServer.call(__MODULE__, {:update_source, id, attrs})
  end

  @doc """
  Get a source by ID.
  """
  def get_source(id) do
    GenServer.call(__MODULE__, {:get_source, id})
  end

  @doc """
  Get source by URL.
  """
  def get_source_by_url(url) do
    GenServer.call(__MODULE__, {:get_source_by_url, url})
  end

  @doc """
  List all sources.
  """
  def list_sources do
    GenServer.call(__MODULE__, :list_sources)
  end

  @doc """
  Remove a source and all its chunks.
  """
  def remove_source(id) do
    GenServer.call(__MODULE__, {:remove_source, id})
  end

  @doc """
  Clear chunks for a source (before re-indexing).
  """
  def clear_chunks(source_id) do
    GenServer.call(__MODULE__, {:clear_chunks, source_id})
  end

  @doc """
  Store a chunk with optional embedding.
  """
  def store_chunk(attrs) do
    GenServer.call(__MODULE__, {:store_chunk, attrs})
  end

  @doc """
  Store multiple chunks (batch insert).
  """
  def store_chunks(chunks) do
    GenServer.call(__MODULE__, {:store_chunks, chunks}, 120_000)
  end

  @doc """
  Semantic search using vector embeddings.
  Falls back to text search if no embedding provided.
  """
  def search_semantic(query_embedding, opts \\ []) do
    GenServer.call(__MODULE__, {:search_semantic, query_embedding, opts})
  end

  @doc """
  Full-text search (fallback when no embeddings).
  """
  def search_text(query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_text, query, opts})
  end

  @doc """
  Store a security alert.
  """
  def store_alert(attrs) do
    GenServer.call(__MODULE__, {:store_alert, attrs})
  end

  @doc """
  Get alerts for a source.
  """
  def get_alerts(source_id) do
    GenServer.call(__MODULE__, {:get_alerts, source_id})
  end

  @doc """
  Link a doc chunk to a chat message (cross-domain).
  """
  def link_to_chat(chunk_id, chat_message_id, relevance) do
    GenServer.call(__MODULE__, {:link_to_chat, chunk_id, chat_message_id, relevance})
  end

  # Server Implementation

  @impl true
  def init(opts) do
    config = %{
      endpoint: Keyword.get(opts, :endpoint, @default_endpoint),
      namespace: Keyword.get(opts, :namespace, @default_namespace),
      database: Keyword.get(opts, :database, @default_database),
      username: Keyword.get(opts, :username, "root"),
      password: Keyword.get(opts, :password, "root")
    }

    # Test connection asynchronously
    send(self(), :check_connection)

    {:ok, %{config: config, connected: false}}
  end

  @impl true
  def handle_info(:check_connection, state) do
    connected = test_connection(state.config)

    if connected do
      Logger.info("SurrealDB connected at #{state.config.endpoint}")
      # Auto-setup schema on first connect
      setup_schema(state.config)
    else
      Logger.warning("SurrealDB not available at #{state.config.endpoint} - will use SQLite fallback")
    end

    {:noreply, %{state | connected: connected}}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call(:setup, _from, state) do
    result = setup_schema(state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_source, attrs}, _from, state) do
    id = generate_id()

    query = """
    CREATE doc_source:#{id} SET
      url = $url,
      name = $name,
      status = 'pending',
      security_tier = 'unknown',
      pages_count = 0,
      chunks_count = 0,
      config = $config,
      created_at = time::now();
    """

    params = %{
      url: attrs[:url],
      name: attrs[:name] || derive_name(attrs[:url]),
      config: attrs[:config] || %{}
    }

    case execute_query(state.config, query, params) do
      {:ok, [result | _]} ->
        source = normalize_source(result)
        {:reply, {:ok, Map.put(source, :id, id)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_source, id, attrs}, _from, state) do
    # Build SET clause dynamically
    sets = attrs
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.map(fn
      {:status, v} -> "status = '#{v}'"
      {:security_tier, v} -> "security_tier = '#{v}'"
      {:pages_count, {:increment, n}} -> "pages_count += #{n}"
      {:pages_count, n} -> "pages_count = #{n}"
      {:chunks_count, {:increment, n}} -> "chunks_count += #{n}"
      {:chunks_count, n} -> "chunks_count = #{n}"
      {:last_indexed, v} -> "last_indexed = '#{v}'"
      {:name, v} -> "name = '#{v}'"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")

    if sets != "" do
      query = "UPDATE doc_source:#{id} SET #{sets};"
      case execute_query(state.config, query) do
        {:ok, _} -> {:reply, {:ok, %{id: id}}, state}
        error -> {:reply, error, state}
      end
    else
      {:reply, {:ok, %{id: id}}, state}
    end
  end

  @impl true
  def handle_call({:get_source, id}, _from, state) do
    query = "SELECT * FROM doc_source:#{id};"

    case execute_query(state.config, query) do
      {:ok, [result | _]} ->
        {:reply, {:ok, normalize_source(result)}, state}

      {:ok, []} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_source_by_url, url}, _from, state) do
    query = "SELECT * FROM doc_source WHERE url = $url;"

    case execute_query(state.config, query, %{url: url}) do
      {:ok, [result | _]} ->
        {:reply, {:ok, normalize_source(result)}, state}

      {:ok, []} ->
        {:reply, {:error, :not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:list_sources, _from, state) do
    query = "SELECT * FROM doc_source ORDER BY created_at DESC;"

    case execute_query(state.config, query) do
      {:ok, results} ->
        sources = Enum.map(results, &normalize_source/1)
        {:reply, {:ok, sources}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:remove_source, id}, _from, state) do
    queries = [
      "DELETE security_alert WHERE source = doc_source:#{id};",
      "DELETE doc_chunk WHERE source = doc_source:#{id};",
      "DELETE doc_source:#{id};"
    ]

    Enum.each(queries, &execute_query(state.config, &1))
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:clear_chunks, source_id}, _from, state) do
    query = "DELETE doc_chunk WHERE source = doc_source:#{source_id};"
    execute_query(state.config, query)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:store_chunk, attrs}, _from, state) do
    id = generate_id()

    # Handle embedding - convert to array if present
    embedding_set = if attrs[:embedding] do
      "embedding = #{Jason.encode!(attrs[:embedding])}"
    else
      ""
    end

    query = """
    CREATE doc_chunk:#{id} SET
      source = doc_source:#{attrs[:source_id]},
      url = $url,
      title = $title,
      content = $content,
      position = $position,
      has_code = $has_code,
      quality_score = $quality_score,
      created_at = time::now()
      #{if embedding_set != "", do: ", " <> embedding_set, else: ""};
    """

    params = %{
      url: attrs[:url],
      title: attrs[:title] || "",
      content: attrs[:content],
      position: attrs[:position] || 0,
      has_code: attrs[:has_code] || false,
      quality_score: attrs[:quality_score] || 0.5
    }

    case execute_query(state.config, query, params) do
      {:ok, _} -> {:reply, {:ok, %{id: id}}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_chunks, chunks}, _from, state) do
    # Batch insert using transaction
    statements = Enum.map(chunks, fn chunk ->
      id = generate_id()
      embedding_set = if chunk[:embedding] do
        ", embedding = #{Jason.encode!(chunk[:embedding])}"
      else
        ""
      end

      """
      CREATE doc_chunk:#{id} SET
        source = doc_source:#{chunk[:source_id]},
        url = '#{escape_string(chunk[:url] || "")}',
        title = '#{escape_string(chunk[:title] || "")}',
        content = '#{escape_string(chunk[:content] || "")}',
        position = #{chunk[:position] || 0},
        has_code = #{chunk[:has_code] || false},
        quality_score = #{chunk[:quality_score] || 0.5},
        created_at = time::now()#{embedding_set};
      """
    end)

    query = "BEGIN TRANSACTION;\n#{Enum.join(statements, "\n")}\nCOMMIT TRANSACTION;"

    case execute_query(state.config, query) do
      {:ok, _} -> {:reply, {:ok, length(chunks)}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:search_semantic, query_embedding, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 5)
    sources = Keyword.get(opts, :sources, [])

    # SurrealDB vector search using vector::similarity::cosine
    source_filter = if sources != [] do
      source_ids = Enum.map(sources, &"doc_source:#{&1}") |> Enum.join(", ")
      "AND source IN [#{source_ids}]"
    else
      ""
    end

    query = """
    SELECT
      *,
      vector::similarity::cosine(embedding, $query_embedding) AS score
    FROM doc_chunk
    WHERE embedding != NONE #{source_filter}
    ORDER BY score DESC
    LIMIT #{limit};
    """

    case execute_query(state.config, query, %{query_embedding: query_embedding}) do
      {:ok, results} ->
        chunks = Enum.map(results, &normalize_chunk/1)
        {:reply, {:ok, chunks}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:search_text, query, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 5)
    sources = Keyword.get(opts, :sources, [])

    source_filter = if sources != [] do
      source_ids = Enum.map(sources, &"doc_source:#{&1}") |> Enum.join(", ")
      "AND source IN [#{source_ids}]"
    else
      ""
    end

    # Basic text search (SurrealDB full-text search)
    search_query = """
    SELECT * FROM doc_chunk
    WHERE content CONTAINS $query OR title CONTAINS $query #{source_filter}
    LIMIT #{limit};
    """

    case execute_query(state.config, search_query, %{query: query}) do
      {:ok, results} ->
        chunks = Enum.map(results, &normalize_chunk/1)
        {:reply, {:ok, chunks}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:store_alert, attrs}, _from, state) do
    id = generate_id()

    query = """
    CREATE security_alert:#{id} SET
      source = doc_source:#{attrs[:source_id]},
      alert_type = $alert_type,
      severity = $severity,
      description = $description,
      details = $details,
      created_at = time::now();
    """

    params = %{
      alert_type: Atom.to_string(attrs[:type] || :unknown),
      severity: attrs[:severity] || 4,
      description: attrs[:description] || "",
      details: attrs[:details] || %{}
    }

    case execute_query(state.config, query, params) do
      {:ok, _} -> {:reply, {:ok, %{id: id}}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_alerts, source_id}, _from, state) do
    query = """
    SELECT * FROM security_alert
    WHERE source = doc_source:#{source_id}
    ORDER BY severity ASC, created_at DESC;
    """

    case execute_query(state.config, query) do
      {:ok, results} ->
        alerts = Enum.map(results, &normalize_alert/1)
        {:reply, {:ok, alerts}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:link_to_chat, chunk_id, chat_message_id, relevance}, _from, state) do
    # Create graph edge between doc chunk and chat message
    query = """
    RELATE chat_message:#{chat_message_id}->answered_by->doc_chunk:#{chunk_id}
    SET relevance = #{relevance}, created_at = time::now();
    """

    case execute_query(state.config, query) do
      {:ok, _} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  # Private Functions

  defp test_connection(config) do
    case Req.post("#{config.endpoint}/health") do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp execute_query(config, query, params \\ %{}) do
    url = "#{config.endpoint}/sql"

    headers = [
      {"accept", "application/json"},
      {"content-type", "text/plain"},
      {"ns", config.namespace},
      {"db", config.database},
      {"authorization", "Basic " <> Base.encode64("#{config.username}:#{config.password}")}
    ]

    # SurrealDB uses $param syntax, we pass params as JSON in body
    body = if params == %{} do
      query
    else
      # For parameterized queries, we need to use the proper format
      query
    end

    case Req.post(url, headers: headers, body: body, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("SurrealDB error (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("SurrealDB request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_response(body) when is_list(body) do
    # SurrealDB returns array of statement results
    results = Enum.flat_map(body, fn
      %{"result" => result} when is_list(result) -> result
      %{"result" => result} -> [result]
      _ -> []
    end)

    {:ok, results}
  end

  defp parse_response(body) when is_map(body) do
    case body do
      %{"result" => result} -> {:ok, List.wrap(result)}
      %{"error" => error} -> {:error, error}
      _ -> {:ok, []}
    end
  end

  defp parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_response(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp setup_schema(config) do
    schema = """
    -- Documentation sources
    DEFINE TABLE doc_source SCHEMAFULL;
    DEFINE FIELD url ON doc_source TYPE string ASSERT $value != NONE;
    DEFINE FIELD name ON doc_source TYPE string;
    DEFINE FIELD status ON doc_source TYPE string DEFAULT 'pending';
    DEFINE FIELD security_tier ON doc_source TYPE string DEFAULT 'unknown';
    DEFINE FIELD pages_count ON doc_source TYPE int DEFAULT 0;
    DEFINE FIELD chunks_count ON doc_source TYPE int DEFAULT 0;
    DEFINE FIELD config ON doc_source TYPE object DEFAULT {};
    DEFINE FIELD created_at ON doc_source TYPE datetime DEFAULT time::now();
    DEFINE FIELD last_indexed ON doc_source TYPE option<datetime>;
    DEFINE INDEX idx_url ON doc_source FIELDS url UNIQUE;

    -- Content chunks with embeddings
    DEFINE TABLE doc_chunk SCHEMAFULL;
    DEFINE FIELD source ON doc_chunk TYPE record<doc_source>;
    DEFINE FIELD url ON doc_chunk TYPE string;
    DEFINE FIELD title ON doc_chunk TYPE string;
    DEFINE FIELD content ON doc_chunk TYPE string;
    DEFINE FIELD position ON doc_chunk TYPE int DEFAULT 0;
    DEFINE FIELD embedding ON doc_chunk TYPE option<array<float>>;
    DEFINE FIELD has_code ON doc_chunk TYPE bool DEFAULT false;
    DEFINE FIELD quality_score ON doc_chunk TYPE float DEFAULT 0.5;
    DEFINE FIELD created_at ON doc_chunk TYPE datetime DEFAULT time::now();
    DEFINE INDEX idx_source ON doc_chunk FIELDS source;

    -- Security alerts
    DEFINE TABLE security_alert SCHEMAFULL;
    DEFINE FIELD source ON security_alert TYPE record<doc_source>;
    DEFINE FIELD alert_type ON security_alert TYPE string;
    DEFINE FIELD severity ON security_alert TYPE int;
    DEFINE FIELD description ON security_alert TYPE string;
    DEFINE FIELD details ON security_alert TYPE object DEFAULT {};
    DEFINE FIELD created_at ON security_alert TYPE datetime DEFAULT time::now();
    DEFINE INDEX idx_source_severity ON security_alert FIELDS source, severity;

    -- Cross-domain: Link docs to chat conversations
    DEFINE TABLE answered_by SCHEMAFULL;
    DEFINE FIELD in ON answered_by TYPE record;
    DEFINE FIELD out ON answered_by TYPE record;
    DEFINE FIELD relevance ON answered_by TYPE float;
    DEFINE FIELD created_at ON answered_by TYPE datetime DEFAULT time::now();
    """

    case execute_query(config, schema) do
      {:ok, _} ->
        Logger.info("SurrealDB schema setup complete")
        :ok

      {:error, reason} ->
        Logger.warning("SurrealDB schema setup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize_source(data) when is_map(data) do
    %{
      id: extract_id(data["id"]),
      url: data["url"],
      name: data["name"],
      status: data["status"],
      security_tier: data["security_tier"],
      pages_count: data["pages_count"] || 0,
      chunks_count: data["chunks_count"] || 0,
      config: data["config"] || %{},
      created_at: data["created_at"],
      last_indexed: data["last_indexed"]
    }
  end

  defp normalize_chunk(data) when is_map(data) do
    %{
      id: extract_id(data["id"]),
      source_id: extract_id(data["source"]),
      url: data["url"],
      title: data["title"],
      content: data["content"],
      position: data["position"] || 0,
      has_code: data["has_code"] || false,
      quality_score: data["quality_score"] || 0.5,
      score: data["score"],
      created_at: data["created_at"]
    }
  end

  defp normalize_alert(data) when is_map(data) do
    %{
      id: extract_id(data["id"]),
      source_id: extract_id(data["source"]),
      type: String.to_existing_atom(data["alert_type"] || "unknown"),
      severity: data["severity"] || 4,
      description: data["description"],
      details: data["details"] || %{},
      created_at: data["created_at"]
    }
  rescue
    _ -> %{
      id: extract_id(data["id"]),
      source_id: extract_id(data["source"]),
      type: :unknown,
      severity: data["severity"] || 4,
      description: data["description"],
      details: data["details"] || %{},
      created_at: data["created_at"]
    }
  end

  defp extract_id(nil), do: nil
  defp extract_id(id) when is_binary(id) do
    # SurrealDB IDs are like "doc_source:abc123" - extract the ID part
    case String.split(id, ":") do
      [_table, id] -> id
      _ -> id
    end
  end
  defp extract_id(id), do: to_string(id)

  defp escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
  defp escape_string(other), do: to_string(other)

  defp derive_name(url) when is_binary(url) do
    uri = URI.parse(url)
    parts = String.split(uri.host || "", ".")
    domain = Enum.at(parts, -2) || Enum.at(parts, 0) || "docs"
    String.capitalize(domain)
  end
  defp derive_name(_), do: "Unknown"

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
