defmodule CursorDocs.Embeddings do
  @moduledoc """
  Embedding generation using Ollama.

  ## Architecture

  Uses Ollama running on Obsidian's dual GPU setup:
  - Arc A770 (port 11435) - Primary for large models
  - RTX 2080 (port 11434) - Secondary / fallback

  ## Embedding Models

  Recommended models for documentation embedding:
  - `nomic-embed-text` (768 dim) - Best quality, larger
  - `all-minilm` (384 dim) - Fast, good quality
  - `mxbai-embed-large` (1024 dim) - Highest quality

  ## Usage

      # Generate single embedding
      {:ok, embedding} = Embeddings.generate("Phoenix is a web framework")

      # Batch embed chunks
      {:ok, chunks_with_embeddings} = Embeddings.embed_chunks(chunks)

      # Embed a query for search
      {:ok, query_embedding} = Embeddings.embed_query("how to use router")

  """

  require Logger

  @default_model "nomic-embed-text"
  @default_endpoint "http://localhost:11435"  # Arc A770 Ollama
  @fallback_endpoint "http://localhost:11434"  # RTX 2080 Ollama
  @batch_size 10
  @timeout 60_000

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Generate embedding for a single text.
  """
  @spec generate(String.t(), keyword()) :: {:ok, list(float())} | {:error, term()}
  def generate(text, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    endpoint = Keyword.get(opts, :endpoint, @default_endpoint)

    case call_ollama_embedding(endpoint, model, text) do
      {:ok, embedding} ->
        {:ok, embedding}

      {:error, _reason} ->
        # Try fallback endpoint
        Logger.debug("Trying fallback Ollama endpoint")
        call_ollama_embedding(@fallback_endpoint, model, text)
    end
  end

  @doc """
  Generate embedding optimized for search queries.
  Adds instruction prefix for retrieval-optimized models.
  """
  @spec embed_query(String.t(), keyword()) :: {:ok, list(float())} | {:error, term()}
  def embed_query(query, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    # Some models benefit from query prefixes
    prefixed_query = case model do
      "nomic-embed-text" -> "search_query: #{query}"
      "mxbai-embed-large" -> "Represent this sentence for searching relevant passages: #{query}"
      _ -> query
    end

    generate(prefixed_query, opts)
  end

  @doc """
  Generate embedding for a document chunk.
  """
  @spec embed_document(String.t(), keyword()) :: {:ok, list(float())} | {:error, term()}
  def embed_document(text, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    # Some models benefit from document prefixes
    prefixed_text = case model do
      "nomic-embed-text" -> "search_document: #{text}"
      _ -> text
    end

    generate(prefixed_text, opts)
  end

  @doc """
  Embed multiple chunks in batch.
  Returns chunks with :embedding field added.
  """
  @spec embed_chunks(list(map()), keyword()) :: {:ok, list(map())} | {:error, term()}
  def embed_chunks(chunks, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)

    results =
      chunks
      |> Enum.chunk_every(batch_size)
      |> Enum.with_index()
      |> Enum.flat_map(fn {batch, batch_idx} ->
        Logger.debug("Embedding batch #{batch_idx + 1} (#{length(batch)} chunks)")

        Enum.map(batch, fn chunk ->
          case embed_document(chunk[:content] || chunk.content, opts) do
            {:ok, embedding} ->
              Map.put(chunk, :embedding, embedding)

            {:error, reason} ->
              Logger.warning("Failed to embed chunk: #{inspect(reason)}")
              chunk
          end
        end)
      end)

    embedded_count = Enum.count(results, &Map.has_key?(&1, :embedding))
    Logger.info("Embedded #{embedded_count}/#{length(chunks)} chunks")

    {:ok, results}
  end

  @doc """
  Check if Ollama embedding endpoint is available.
  """
  @spec available?() :: boolean()
  def available? do
    check_endpoint(@default_endpoint) or check_endpoint(@fallback_endpoint)
  end

  @doc """
  Get information about available embedding models.
  """
  @spec list_models(keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_models(opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, @default_endpoint)

    case Req.get("#{endpoint}/api/tags", receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        embedding_models = Enum.filter(models, fn model ->
          name = model["name"] || ""
          String.contains?(name, "embed") or
          String.contains?(name, "minilm") or
          String.contains?(name, "nomic") or
          String.contains?(name, "bge")
        end)
        {:ok, embedding_models}

      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_response}
    end
  end

  @doc """
  Pull an embedding model if not already available.
  """
  @spec ensure_model(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_model(model \\ @default_model, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, @default_endpoint)

    Logger.info("Ensuring embedding model #{model} is available...")

    case Req.post(
      "#{endpoint}/api/pull",
      json: %{name: model},
      receive_timeout: 600_000  # 10 minutes for large models
    ) do
      {:ok, %{status: 200}} ->
        Logger.info("Model #{model} is ready")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp call_ollama_embedding(endpoint, model, text) do
    # Truncate very long texts (embedding models have limits)
    text = String.slice(text, 0, 8000)

    request_body = %{
      model: model,
      prompt: text
    }

    case Req.post(
      "#{endpoint}/api/embeddings",
      json: request_body,
      receive_timeout: @timeout
    ) do
      {:ok, %{status: 200, body: %{"embedding" => embedding}}} when is_list(embedding) ->
        {:ok, embedding}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("Unexpected Ollama response: #{inspect(body)}")
        {:error, :invalid_response}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama error (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, %{reason: :econnrefused}} ->
        {:error, :ollama_unavailable}

      {:error, reason} ->
        Logger.error("Ollama request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_endpoint(endpoint) do
    case Req.get("#{endpoint}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
