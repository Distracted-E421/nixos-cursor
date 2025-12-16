defmodule CursorDocs.Storage.Vector.SurrealDB do
  @moduledoc """
  SurrealDB vector storage backend for power users.

  Full-featured multi-model database with vectors, graphs, and more.
  Designed for users building complete data pipelines.

  ## Features

  - **Vector Search**: Native HNSW index for fast ANN
  - **Graph Relationships**: Link docs, chunks, sources
  - **Cross-Domain Queries**: Single query language (SurrealQL)
  - **Real-time Subscriptions**: Live updates for UIs
  - **Multi-Tenant**: Namespace isolation

  ## Graceful Startup

  SurrealDB is designed to start gracefully:
  - Lazy connection (only connects when needed)
  - Health checks before operations
  - Automatic fallback to sqlite-vss if unavailable
  - Low CPU/IO priority on systemd

  ## NixOS Service Configuration

      # In your NixOS config
      systemd.services.surrealdb = {
        description = "SurrealDB for cursor-docs";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        # Low priority - don't slow down boot
        serviceConfig = {
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUWeight = 10;
          MemoryMax = "2G";

          ExecStart = "${pkgs.surrealdb}/bin/surreal start --user root --pass root file:/var/lib/cursor-docs/surreal.db";
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };

  ## Configuration

      config :cursor_docs, CursorDocs.Storage.Vector.SurrealDB,
        endpoint: "http://localhost:8000",
        namespace: "cursor",
        database: "docs",
        username: "root",
        password: "root",
        dimensions: 768,
        connect_timeout: 5_000,
        lazy_connect: true  # Don't connect until first operation

  """

  @behaviour CursorDocs.Storage.Vector

  use GenServer
  require Logger

  @default_endpoint "http://localhost:8000"
  @default_namespace "cursor"
  @default_database "docs"
  @default_dimensions 768
  @connect_timeout 5_000
  @health_check_interval 30_000

  # ============================================================================
  # Behaviour Implementation
  # ============================================================================

  @impl true
  def name, do: "SurrealDB (Full Features)"

  @impl true
  def available? do
    case quick_health_check() do
      :ok -> true
      _ -> false
    end
  end

  @impl true
  def tier, do: :server

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

  defmodule State do
    @moduledoc false
    defstruct [
      :endpoint,
      :namespace,
      :database,
      :username,
      :password,
      :dimensions,
      :token,
      connected: false,
      last_health_check: nil
    ]
  end

  @impl GenServer
  def init(opts) do
    state = %State{
      endpoint: Keyword.get(opts, :endpoint, config(:endpoint, @default_endpoint)),
      namespace: Keyword.get(opts, :namespace, config(:namespace, @default_namespace)),
      database: Keyword.get(opts, :database, config(:database, @default_database)),
      username: Keyword.get(opts, :username, config(:username, "root")),
      password: Keyword.get(opts, :password, config(:password, "root")),
      dimensions: Keyword.get(opts, :dimensions, config(:dimensions, @default_dimensions))
    }

    # Lazy connect - don't block startup
    if config(:lazy_connect, true) do
      Logger.info("SurrealDB backend initialized (lazy connect)")
      {:ok, state}
    else
      case connect(state) do
        {:ok, new_state} ->
          schedule_health_check()
          {:ok, new_state}

        {:error, reason} ->
          Logger.warning("SurrealDB not available: #{inspect(reason)}")
          {:ok, state}
      end
    end
  end

  @impl GenServer
  def handle_call({:store, chunk_id, embedding, metadata}, _from, state) do
    with {:ok, state} <- ensure_connected(state) do
      result = do_store(state, chunk_id, embedding, metadata)
      {:reply, result, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:store_batch, items}, _from, state) do
    with {:ok, state} <- ensure_connected(state) do
      result = do_store_batch(state, items)
      {:reply, result, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:search, embedding, opts}, _from, state) do
    with {:ok, state} <- ensure_connected(state) do
      result = do_search(state, embedding, opts)
      {:reply, result, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete_for_source, source_id}, _from, state) do
    with {:ok, state} <- ensure_connected(state) do
      result = do_delete_for_source(state, source_id)
      {:reply, result, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    with {:ok, state} <- ensure_connected(state) do
      result = do_stats(state)
      {:reply, result, state}
    else
      {:error, _} ->
        {:reply, %{total_vectors: 0, dimensions: nil, storage_bytes: 0}, state}
    end
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    case do_health_check(state) do
      :ok ->
        {:reply, :ok, %{state | last_health_check: DateTime.utc_now()}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | connected: false}}
    end
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    case do_health_check(state) do
      :ok ->
        schedule_health_check()
        {:noreply, %{state | last_health_check: DateTime.utc_now()}}

      {:error, _} ->
        schedule_health_check()
        {:noreply, %{state | connected: false}}
    end
  end

  # ============================================================================
  # Connection Management
  # ============================================================================

  defp ensure_connected(%{connected: true} = state), do: {:ok, state}

  defp ensure_connected(state) do
    connect(state)
  end

  defp connect(state) do
    Logger.debug("Connecting to SurrealDB at #{state.endpoint}")

    # Sign in and get token
    signin_url = "#{state.endpoint}/signin"

    body = Jason.encode!(%{
      ns: state.namespace,
      db: state.database,
      user: state.username,
      pass: state.password
    })

    case http_post(signin_url, body, [{"content-type", "application/json"}]) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"token" => token}} ->
            new_state = %{state | token: token, connected: true}

            # Setup schema
            case setup_schema(new_state) do
              :ok ->
                Logger.info("Connected to SurrealDB")
                schedule_health_check()
                {:ok, new_state}

              {:error, reason} ->
                {:error, {:schema_setup_failed, reason}}
            end

          {:ok, _} ->
            {:error, :invalid_response}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp setup_schema(state) do
    # Create vector chunk table with embedding field
    schema_query = """
    DEFINE TABLE IF NOT EXISTS vector_chunk SCHEMAFULL;
    DEFINE FIELD IF NOT EXISTS chunk_id ON vector_chunk TYPE string;
    DEFINE FIELD IF NOT EXISTS source_id ON vector_chunk TYPE string;
    DEFINE FIELD IF NOT EXISTS embedding ON vector_chunk TYPE array<float>;
    DEFINE FIELD IF NOT EXISTS created_at ON vector_chunk TYPE datetime DEFAULT time::now();
    DEFINE INDEX IF NOT EXISTS idx_chunk_id ON vector_chunk FIELDS chunk_id UNIQUE;
    DEFINE INDEX IF NOT EXISTS idx_source_id ON vector_chunk FIELDS source_id;
    """

    case execute_query(state, schema_query) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  # ============================================================================
  # Operations
  # ============================================================================

  defp do_store(state, chunk_id, embedding, metadata) do
    source_id = metadata[:source_id] || "unknown"

    query = """
    CREATE vector_chunk SET
      chunk_id = $chunk_id,
      source_id = $source_id,
      embedding = $embedding
    ON DUPLICATE KEY UPDATE
      embedding = $embedding
    """

    params = %{
      chunk_id: chunk_id,
      source_id: source_id,
      embedding: embedding
    }

    case execute_query(state, query, params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_store_batch(state, items) do
    # Build batch insert query
    queries = Enum.map(items, fn {chunk_id, embedding, metadata} ->
      source_id = metadata[:source_id] || "unknown"

      """
      CREATE vector_chunk SET
        chunk_id = '#{escape_string(chunk_id)}',
        source_id = '#{escape_string(source_id)}',
        embedding = #{Jason.encode!(embedding)}
      ON DUPLICATE KEY UPDATE
        embedding = #{Jason.encode!(embedding)};
      """
    end)

    query = Enum.join(queries, "\n")

    case execute_query(state, query) do
      {:ok, _} -> {:ok, length(items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_search(state, embedding, opts) do
    limit = Keyword.get(opts, :limit, 10)

    # SurrealDB vector search using cosine similarity
    # Note: SurrealDB 2.0+ has native vector search, for older versions we compute manually
    query = """
    SELECT
      chunk_id,
      source_id,
      vector::similarity::cosine(embedding, $query_embedding) as score
    FROM vector_chunk
    ORDER BY score DESC
    LIMIT $limit
    """

    params = %{
      query_embedding: embedding,
      limit: limit
    }

    case execute_query(state, query, params) do
      {:ok, results} ->
        formatted = Enum.map(results, fn result ->
          %{
            chunk_id: result["chunk_id"],
            score: result["score"] || 0.0,
            metadata: %{source_id: result["source_id"]}
          }
        end)

        {:ok, formatted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_delete_for_source(state, source_id) do
    query = "DELETE vector_chunk WHERE source_id = $source_id"
    params = %{source_id: source_id}

    case execute_query(state, query, params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_stats(state) do
    query = """
    SELECT count() as total FROM vector_chunk GROUP ALL;
    """

    case execute_query(state, query) do
      {:ok, [%{"total" => total}]} ->
        %{
          total_vectors: total,
          dimensions: state.dimensions,
          storage_bytes: total * state.dimensions * 4
        }

      {:ok, []} ->
        %{
          total_vectors: 0,
          dimensions: state.dimensions,
          storage_bytes: 0
        }

      {:error, _} ->
        %{
          total_vectors: 0,
          dimensions: nil,
          storage_bytes: 0
        }
    end
  end

  defp do_health_check(state) do
    case execute_query(state, "INFO FOR DB") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # HTTP Helpers
  # ============================================================================

  defp execute_query(state, query, params \\ %{}) do
    url = "#{state.endpoint}/sql"

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"ns", state.namespace},
      {"db", state.database}
    ]

    headers = if state.token do
      [{"authorization", "Bearer #{state.token}"} | headers]
    else
      headers
    end

    body = if map_size(params) > 0 do
      Jason.encode!(%{query: query, vars: params})
    else
      query
    end

    case http_post(url, body, headers) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, [%{"result" => result}]} -> {:ok, result}
          {:ok, results} when is_list(results) -> {:ok, results}
          {:ok, other} -> {:ok, other}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_post(url, body, headers) do
    # Convert headers to charlist format for :httpc
    headers_charlist = Enum.map(headers, fn {k, v} ->
      {to_charlist(k), to_charlist(v)}
    end)

    content_type = headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == "content-type" end)
    |> case do
      {_, v} -> to_charlist(v)
      nil -> ~c"application/json"
    end

    request = {to_charlist(url), headers_charlist, content_type, body}

    case :httpc.request(:post, request, [timeout: @connect_timeout], []) do
      {:ok, {{_, status, _}, _resp_headers, resp_body}} ->
        {:ok, %{status: status, body: to_string(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp quick_health_check do
    endpoint = config(:endpoint, @default_endpoint)
    url = "#{endpoint}/health"

    case :httpc.request(:get, {to_charlist(url), []}, [timeout: 2_000], []) do
      {:ok, {{_, 200, _}, _, _}} -> :ok
      _ -> {:error, :not_available}
    end
  rescue
    _ -> {:error, :not_available}
  end

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp config(key, default) do
    Application.get_env(:cursor_docs, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
