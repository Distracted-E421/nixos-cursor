defmodule CursorDocs.Storage do
  @moduledoc """
  Unified storage interface for CursorDocs.

  ## Backend Selection

  Automatically selects the best available backend:
  1. **SurrealDB** (preferred) - Vector embeddings, graph queries, cross-domain
  2. **SQLite** (fallback) - Reliable local storage, Cursor DB compatibility

  ## Features by Backend

  | Feature              | SurrealDB | SQLite |
  |---------------------|-----------|--------|
  | Full-text search    | ✅        | ✅ FTS5 |
  | Vector embeddings   | ✅        | ❌      |
  | Semantic search     | ✅        | ❌      |
  | Graph relationships | ✅        | ❌      |
  | Cross-domain links  | ✅        | ❌      |
  | Cursor DB reading   | ❌        | ✅      |

  ## Usage

      # Automatically uses best backend
      {:ok, source} = Storage.create_source(%{url: "https://docs.example.com"})

      # Semantic search (SurrealDB only)
      {:ok, results} = Storage.search_semantic(query_embedding, limit: 5)

      # Text search (both backends)
      {:ok, results} = Storage.search(query, limit: 5)

  """

  require Logger

  alias CursorDocs.Storage.{SQLite, SurrealDB}
  alias CursorDocs.Embeddings

  # ============================================================================
  # Backend Selection
  # ============================================================================

  @doc """
  Get the current active backend.
  """
  def active_backend do
    cond do
      surrealdb_available?() -> :surrealdb
      sqlite_available?() -> :sqlite
      true -> :none
    end
  end

  @doc """
  Check if SurrealDB backend is available.
  """
  def surrealdb_available? do
    try do
      SurrealDB.available?()
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Check if SQLite backend is available.
  """
  def sqlite_available? do
    try do
      GenServer.call(SQLite, {:get_source, "__test__"})
      true
    catch
      :exit, _ -> false
    end
  end

  # ============================================================================
  # Source Management
  # ============================================================================

  @doc """
  Create a documentation source.
  """
  def create_source(attrs) do
    case active_backend() do
      :surrealdb -> SurrealDB.create_source(attrs)
      :sqlite -> SQLite.create_source(attrs)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Update a documentation source.
  """
  def update_source(id, attrs) do
    case active_backend() do
      :surrealdb -> SurrealDB.update_source(id, attrs)
      :sqlite -> SQLite.update_source(id, attrs)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Get a source by ID.
  """
  def get_source(id) do
    case active_backend() do
      :surrealdb -> SurrealDB.get_source(id)
      :sqlite -> SQLite.get_source(id)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Get source by URL.
  """
  def get_source_by_url(url) do
    case active_backend() do
      :surrealdb -> SurrealDB.get_source_by_url(url)
      :sqlite -> SQLite.get_source_by_url(url)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Check if a URL exists as a source.
  """
  def source_exists?(url) do
    case get_source_by_url(url) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  List all documentation sources.
  """
  def list_sources do
    case active_backend() do
      :surrealdb -> SurrealDB.list_sources()
      :sqlite -> SQLite.list_sources()
      :none -> {:ok, []}
    end
  end

  @doc """
  Remove a source and all its data.
  """
  def remove_source(id) do
    case active_backend() do
      :surrealdb -> SurrealDB.remove_source(id)
      :sqlite -> SQLite.remove_source(id)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Clear chunks for a source (before re-indexing).
  """
  def clear_chunks(source_id) do
    case active_backend() do
      :surrealdb -> SurrealDB.clear_chunks(source_id)
      :sqlite -> SQLite.clear_chunks(source_id)
      :none -> {:error, :no_backend}
    end
  end

  # ============================================================================
  # Chunk Storage
  # ============================================================================

  @doc """
  Store a content chunk.
  Automatically generates embeddings if SurrealDB is active and Ollama is available.
  """
  def store_chunk(attrs, opts \\ []) do
    generate_embeddings? = Keyword.get(opts, :embeddings, true)

    attrs = if generate_embeddings? and active_backend() == :surrealdb and not Map.has_key?(attrs, :embedding) do
      case Embeddings.embed_document(attrs[:content]) do
        {:ok, embedding} -> Map.put(attrs, :embedding, embedding)
        _ -> attrs
      end
    else
      attrs
    end

    case active_backend() do
      :surrealdb -> SurrealDB.store_chunk(attrs)
      :sqlite -> SQLite.store_chunk(attrs)
      :none -> {:error, :no_backend}
    end
  end

  @doc """
  Store multiple chunks.
  Automatically generates embeddings in batch if SurrealDB is active.
  """
  def store_chunks(chunks, opts \\ []) do
    generate_embeddings? = Keyword.get(opts, :embeddings, true)

    chunks = if generate_embeddings? and active_backend() == :surrealdb do
      case Embeddings.embed_chunks(chunks) do
        {:ok, embedded} -> embedded
        _ -> chunks
      end
    else
      chunks
    end

    case active_backend() do
      :surrealdb -> SurrealDB.store_chunks(chunks)
      :sqlite -> SQLite.store_chunks(chunks)
      :none -> {:error, :no_backend}
    end
  end

  # ============================================================================
  # Search
  # ============================================================================

  @doc """
  Smart search - uses semantic search if available, falls back to text search.
  """
  def search(query, opts \\ []) do
    case active_backend() do
      :surrealdb ->
        # Try semantic search first
        case Embeddings.embed_query(query) do
          {:ok, query_embedding} ->
            SurrealDB.search_semantic(query_embedding, opts)

          {:error, _} ->
            # Fallback to text search
            SurrealDB.search_text(query, opts)
        end

      :sqlite ->
        SQLite.search_chunks(query, opts)

      :none ->
        {:ok, []}
    end
  end

  @doc """
  Text-only search (no embeddings).
  """
  def search_text(query, opts \\ []) do
    case active_backend() do
      :surrealdb -> SurrealDB.search_text(query, opts)
      :sqlite -> SQLite.search_chunks(query, opts)
      :none -> {:ok, []}
    end
  end

  @doc """
  Semantic search using vector embeddings.
  Only works with SurrealDB backend.
  """
  def search_semantic(query, opts \\ []) do
    if active_backend() == :surrealdb do
      case Embeddings.embed_query(query) do
        {:ok, embedding} -> SurrealDB.search_semantic(embedding, opts)
        error -> error
      end
    else
      {:error, :semantic_search_unavailable}
    end
  end

  # ============================================================================
  # Status & Diagnostics
  # ============================================================================

  @doc """
  Get storage status including backend info.
  """
  def status do
    backend = active_backend()
    embeddings = Embeddings.available?()

    %{
      backend: backend,
      surrealdb_available: surrealdb_available?(),
      sqlite_available: sqlite_available?(),
      embeddings_available: embeddings,
      features: %{
        semantic_search: backend == :surrealdb and embeddings,
        vector_embeddings: backend == :surrealdb,
        graph_queries: backend == :surrealdb,
        cursor_db_reading: sqlite_available?()
      }
    }
  end

  @doc """
  Setup storage backends.
  """
  def setup do
    # Setup SQLite (always available)
    SQLite.setup()

    # Setup SurrealDB if available
    if surrealdb_available?() do
      SurrealDB.setup()
    end

    :ok
  end
end
