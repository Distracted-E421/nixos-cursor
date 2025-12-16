defmodule CursorDocs.Search do
  @moduledoc """
  Unified search interface for cursor-docs.

  Provides intelligent search that automatically selects
  the best available backend:

  1. **Semantic Search** (Vector + FTS5 hybrid)
     - Best results for natural language queries
     - Requires AI provider + vector storage

  2. **Keyword Search** (FTS5 only)
     - Fast, reliable keyword matching
     - Works without any AI

  ## Usage

      # Auto-select best available mode
      {:ok, results} = Search.query("authentication with JWT")

      # Force specific mode
      {:ok, results} = Search.query("auth", mode: :keyword)
      {:ok, results} = Search.query("how do I protect routes", mode: :semantic)

  ## Hybrid Search

  When both modes are available, semantic search uses a hybrid approach:
  1. Generate query embedding
  2. Search vector store for semantically similar chunks
  3. Also search FTS5 for keyword matches
  4. Combine and re-rank results
  5. Return deduplicated, ranked results

  """

  require Logger

  alias CursorDocs.Storage.{SQLite, Vector}
  alias CursorDocs.Embeddings.Generator

  @type search_result :: %{
    id: String.t(),
    source_id: String.t(),
    url: String.t(),
    title: String.t(),
    content: String.t(),
    score: float(),
    match_type: :semantic | :keyword | :hybrid
  }

  @doc """
  Search for documentation chunks.

  ## Options

  - `:mode` - `:auto`, `:semantic`, or `:keyword` (default: `:auto`)
  - `:limit` - Maximum results (default: 10)
  - `:sources` - Filter to specific source IDs
  - `:semantic_weight` - Weight for semantic results in hybrid (default: 0.7)
  - `:keyword_weight` - Weight for keyword results in hybrid (default: 0.3)

  """
  @spec query(String.t(), keyword()) :: {:ok, list(search_result())} | {:error, term()}
  def query(query_text, opts \\ []) do
    mode = Keyword.get(opts, :mode, :auto)
    limit = Keyword.get(opts, :limit, 10)

    resolved_mode = resolve_mode(mode)

    Logger.debug("Search query: #{inspect(query_text)}, mode: #{resolved_mode}")

    case resolved_mode do
      :semantic ->
        semantic_search(query_text, opts)

      :hybrid ->
        hybrid_search(query_text, opts)

      :keyword ->
        keyword_search(query_text, opts)
    end
    |> case do
      {:ok, results} ->
        {:ok, Enum.take(results, limit)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check which search modes are available.
  """
  def available_modes do
    has_embeddings = Generator.available?()
    has_vectors = case Vector.detect() do
      {:ok, CursorDocs.Storage.Vector.Disabled} -> false
      {:ok, _} -> true
    end

    modes = [:keyword]

    modes = if has_embeddings and has_vectors do
      [:semantic, :hybrid | modes]
    else
      modes
    end

    %{
      modes: modes,
      default: if(:semantic in modes, do: :hybrid, else: :keyword),
      has_embeddings: has_embeddings,
      has_vectors: has_vectors
    }
  end

  # ============================================================================
  # Search Implementations
  # ============================================================================

  defp semantic_search(query_text, opts) do
    limit = Keyword.get(opts, :limit, 10) * 2  # Get more, then filter

    with {:ok, embedding} <- Generator.embed_query(query_text),
         {:ok, vector_results} <- Vector.search(embedding, limit: limit) do

      # Enrich with chunk data
      results = enrich_vector_results(vector_results)
      |> Enum.map(&Map.put(&1, :match_type, :semantic))

      {:ok, results}
    else
      {:error, :embeddings_disabled} ->
        Logger.debug("Embeddings disabled, falling back to keyword search")
        keyword_search(query_text, opts)

      {:error, :vector_storage_disabled} ->
        Logger.debug("Vector storage disabled, falling back to keyword search")
        keyword_search(query_text, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp keyword_search(query_text, opts) do
    limit = Keyword.get(opts, :limit, 10)
    sources = Keyword.get(opts, :sources, [])

    case SQLite.search_chunks(query_text, limit: limit, sources: sources) do
      {:ok, results} ->
        formatted = Enum.map(results, fn chunk ->
          %{
            id: chunk.id,
            source_id: chunk.source_id,
            url: chunk.url || "",
            title: chunk.title || "",
            content: chunk.content || "",
            score: abs(chunk.score || 0),  # BM25 returns negative scores
            match_type: :keyword
          }
        end)

        {:ok, formatted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hybrid_search(query_text, opts) do
    limit = Keyword.get(opts, :limit, 10)
    semantic_weight = Keyword.get(opts, :semantic_weight, 0.7)
    keyword_weight = Keyword.get(opts, :keyword_weight, 0.3)

    # Get results from both backends
    semantic_task = Task.async(fn ->
      semantic_search(query_text, Keyword.put(opts, :limit, limit * 2))
    end)

    keyword_task = Task.async(fn ->
      keyword_search(query_text, Keyword.put(opts, :limit, limit * 2))
    end)

    semantic_results = case Task.await(semantic_task, 30_000) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    keyword_results = case Task.await(keyword_task, 30_000) do
      {:ok, results} -> results
      {:error, _} -> []
    end

    # Combine and re-rank
    combined = combine_results(semantic_results, keyword_results, semantic_weight, keyword_weight)
    |> Enum.map(&Map.put(&1, :match_type, :hybrid))

    {:ok, combined}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp resolve_mode(:auto) do
    case available_modes() do
      %{default: mode} -> mode
    end
  end

  defp resolve_mode(:semantic) do
    if Generator.available?() do
      :semantic
    else
      Logger.warning("Semantic search requested but not available, using keyword")
      :keyword
    end
  end

  defp resolve_mode(:hybrid) do
    if Generator.available?() do
      :hybrid
    else
      Logger.warning("Hybrid search requested but embeddings not available, using keyword")
      :keyword
    end
  end

  defp resolve_mode(:keyword), do: :keyword

  defp enrich_vector_results(vector_results) do
    # Get full chunk data for each result
    Enum.map(vector_results, fn %{chunk_id: chunk_id, score: score, metadata: meta} ->
      # TODO: Batch this lookup for efficiency
      case get_chunk_by_id(chunk_id) do
        {:ok, chunk} ->
          %{
            id: chunk_id,
            source_id: meta[:source_id] || chunk.source_id,
            url: chunk.url || "",
            title: chunk.title || "",
            content: chunk.content || "",
            score: score
          }

        {:error, _} ->
          %{
            id: chunk_id,
            source_id: meta[:source_id] || "unknown",
            url: "",
            title: "",
            content: "",
            score: score
          }
      end
    end)
  end

  defp get_chunk_by_id(chunk_id) do
    # Direct SQLite query for chunk
    # This would be better as a batch operation
    case SQLite.get_chunk(chunk_id) do
      {:ok, chunk} -> {:ok, chunk}
      _ -> {:error, :not_found}
    end
  end

  defp combine_results(semantic, keyword, sem_weight, kw_weight) do
    # Normalize scores and combine
    max_sem_score = semantic |> Enum.map(& &1.score) |> Enum.max(fn -> 1 end)
    max_kw_score = keyword |> Enum.map(& &1.score) |> Enum.max(fn -> 1 end)

    # Build a map of chunk_id -> combined score
    score_map = %{}

    # Add semantic scores
    score_map = Enum.reduce(semantic, score_map, fn result, acc ->
      normalized = (result.score / max_sem_score) * sem_weight
      Map.update(acc, result.id, {normalized, result}, fn {existing, _} ->
        {existing + normalized, result}
      end)
    end)

    # Add keyword scores
    score_map = Enum.reduce(keyword, score_map, fn result, acc ->
      normalized = (result.score / max_kw_score) * kw_weight
      Map.update(acc, result.id, {normalized, result}, fn {existing, data} ->
        {existing + normalized, data}
      end)
    end)

    # Sort by combined score and return results
    score_map
    |> Map.values()
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> Enum.map(fn {score, result} ->
      %{result | score: score}
    end)
  end
end
