defmodule CursorDocs.Storage.Vector do
  @moduledoc """
  Behaviour for vector storage backends.

  ## Tiered Architecture

  cursor-docs supports multiple vector storage tiers to accommodate
  different user needs:

  ### Tier 1: Disabled (Default - Zero Setup)

  No vector storage. Falls back to FTS5 keyword search.
  For users who just want Cursor to work, no modifications.

  ### Tier 2: sqlite-vss (Recommended - No Daemon)

  Embedded vector search via sqlite-vss extension.
  - Single file, portable
  - No background processes
  - ~50k vectors efficiently
  - For normal users who want semantic search without overhead

  ### Tier 3: SurrealDB (Power Users - Full Features)

  Multi-model database with vectors, graphs, and more.
  - Starts gracefully (low priority, doesn't block boot)
  - Cross-domain queries
  - Relationship tracking between docs
  - For power users building full data pipelines

  ## Usage

      # Auto-detect best available backend
      {:ok, backend} = Vector.detect()

      # Store embedding
      :ok = Vector.store(backend, chunk_id, embedding, metadata)

      # Search similar
      {:ok, results} = Vector.search(backend, query_embedding, limit: 10)

  ## Custom Backends

  Implement the behaviour:

      defmodule MyVectorStore do
        @behaviour CursorDocs.Storage.Vector

        @impl true
        def name, do: "my-store"

        @impl true
        def available?, do: check_my_backend()

        @impl true
        def store(id, embedding, metadata), do: ...

        @impl true
        def search(embedding, opts), do: ...
      end

  """

  @type embedding :: list(float())
  @type chunk_id :: String.t()
  @type metadata :: map()
  @type search_result :: %{
    chunk_id: chunk_id(),
    score: float(),
    metadata: metadata()
  }

  @doc "Human-readable backend name"
  @callback name() :: String.t()

  @doc "Check if this backend is available"
  @callback available?() :: boolean()

  @doc "Get backend tier (:disabled | :embedded | :server)"
  @callback tier() :: :disabled | :embedded | :server

  @doc "Start the backend (returns a child spec or :ignore)"
  @callback start(opts :: keyword()) :: {:ok, pid()} | {:error, term()} | :ignore

  @doc "Store an embedding with metadata"
  @callback store(chunk_id(), embedding(), metadata()) :: :ok | {:error, term()}

  @doc "Store multiple embeddings in batch"
  @callback store_batch(list({chunk_id(), embedding(), metadata()})) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "Search for similar embeddings"
  @callback search(embedding(), opts :: keyword()) :: {:ok, list(search_result())} | {:error, term()}

  @doc "Delete embeddings for a source"
  @callback delete_for_source(source_id :: String.t()) :: :ok | {:error, term()}

  @doc "Get storage statistics"
  @callback stats() :: %{
    total_vectors: non_neg_integer(),
    dimensions: non_neg_integer() | nil,
    storage_bytes: non_neg_integer()
  }

  @doc "Check backend health"
  @callback healthy?() :: boolean()

  @optional_callbacks [store_batch: 1]

  # ============================================================================
  # Backend Detection & Management
  # ============================================================================

  @doc """
  Detect the best available vector storage backend.

  Priority order:
  1. User-configured backend (if set and available)
  2. SurrealDB (if running and healthy)
  3. sqlite-vss (if extension available)
  4. Disabled (always available)
  """
  def detect do
    backends = configured_backends()

    case Enum.find(backends, & &1.available?()) do
      nil ->
        {:ok, CursorDocs.Storage.Vector.Disabled}

      backend ->
        {:ok, backend}
    end
  end

  @doc """
  Get all configured backends.
  """
  def configured_backends do
    Application.get_env(:cursor_docs, :vector_backends, default_backends())
  end

  @doc """
  Default backend priority list.
  """
  def default_backends do
    [
      CursorDocs.Storage.Vector.SurrealDB,
      CursorDocs.Storage.Vector.SQLiteVss,
      CursorDocs.Storage.Vector.Disabled
    ]
  end

  @doc """
  Get detailed status of all backends.
  """
  def status do
    backends = configured_backends()

    Enum.map(backends, fn backend ->
      %{
        name: backend.name(),
        tier: backend.tier(),
        available: backend.available?(),
        healthy: if(backend.available?(), do: backend.healthy?(), else: false)
      }
    end)
  end

  @doc """
  Get the currently active backend.
  """
  def current do
    case :persistent_term.get({__MODULE__, :current}, nil) do
      nil ->
        {:ok, backend} = detect()
        :persistent_term.put({__MODULE__, :current}, backend)
        backend

      backend ->
        backend
    end
  end

  @doc """
  Set the active backend explicitly.
  """
  def set_backend(backend) do
    if backend.available?() do
      :persistent_term.put({__MODULE__, :current}, backend)
      :ok
    else
      {:error, :backend_not_available}
    end
  end

  # ============================================================================
  # Convenience Functions (use current backend)
  # ============================================================================

  @doc """
  Store an embedding using the current backend.
  """
  def store(chunk_id, embedding, metadata \\ %{}) do
    current().store(chunk_id, embedding, metadata)
  end

  @doc """
  Search for similar embeddings using the current backend.
  """
  def search(embedding, opts \\ []) do
    current().search(embedding, opts)
  end

  @doc """
  Delete embeddings for a source using the current backend.
  """
  def delete_for_source(source_id) do
    current().delete_for_source(source_id)
  end

  @doc """
  Get stats from the current backend.
  """
  def stats do
    current().stats()
  end
end
