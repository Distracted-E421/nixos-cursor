defmodule CursorDocs.Embeddings.Generator do
  @moduledoc """
  Embedding generation service.

  Orchestrates AI providers and vector storage to generate
  and store embeddings for documentation chunks.

  ## Architecture

      Chunks → AI Provider → Embeddings → Vector Storage
                   ↓
              Hardware-aware
              batch sizing

  ## Usage

      # Generate embeddings for a source
      {:ok, count} = Generator.process_source(source_id)

      # Generate embedding for search query
      {:ok, embedding} = Generator.embed_query("authentication")

      # Process all pending chunks
      {:ok, stats} = Generator.process_all()

  ## Configuration

      config :cursor_docs, CursorDocs.Embeddings.Generator,
        batch_size: :auto,  # Or explicit number
        parallel: true,      # Use Task.async_stream
        skip_if_exists: true # Don't re-embed existing chunks

  """

  use GenServer
  require Logger

  alias CursorDocs.AI.{Provider, Hardware}
  alias CursorDocs.Storage.{SQLite, Vector}

  @default_batch_size 8

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate embedding for a search query.
  """
  def embed_query(text) do
    case Provider.embed(text) do
      {:ok, embedding} -> {:ok, embedding}
      {:error, :embeddings_disabled} -> {:error, :embeddings_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Process all chunks for a source, generating and storing embeddings.
  """
  def process_source(source_id) do
    GenServer.call(__MODULE__, {:process_source, source_id}, 300_000)
  end

  @doc """
  Process all sources that need embeddings.
  """
  def process_all do
    GenServer.call(__MODULE__, :process_all, 600_000)
  end

  @doc """
  Get embedding generation status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Check if embedding generation is available.
  """
  def available? do
    case Provider.detect() do
      {:ok, CursorDocs.AI.Disabled} -> false
      {:ok, _} ->
        case Vector.detect() do
          {:ok, CursorDocs.Storage.Vector.Disabled} -> false
          {:ok, _} -> true
        end
    end
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  defmodule State do
    @moduledoc false
    defstruct [
      :ai_provider,
      :vector_backend,
      :batch_size,
      processed: 0,
      failed: 0,
      last_run: nil
    ]
  end

  @impl GenServer
  def init(_opts) do
    # Detect available providers
    {:ok, ai_provider} = Provider.detect()
    {:ok, vector_backend} = Vector.detect()

    # Determine batch size based on hardware
    batch_size = determine_batch_size()

    state = %State{
      ai_provider: ai_provider,
      vector_backend: vector_backend,
      batch_size: batch_size
    }

    Logger.info("Embedding generator initialized: AI=#{ai_provider.name()}, Vector=#{vector_backend.name()}, Batch=#{batch_size}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:process_source, source_id}, _from, state) do
    result = do_process_source(source_id, state)
    {:reply, result, update_stats(state, result)}
  end

  @impl GenServer
  def handle_call(:process_all, _from, state) do
    result = do_process_all(state)
    {:reply, result, %{state | last_run: DateTime.utc_now()}}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status = %{
      ai_provider: state.ai_provider.name(),
      vector_backend: state.vector_backend.name(),
      batch_size: state.batch_size,
      available: available?(),
      processed: state.processed,
      failed: state.failed,
      last_run: state.last_run
    }
    {:reply, status, state}
  end

  # ============================================================================
  # Processing Logic
  # ============================================================================

  defp do_process_source(source_id, state) do
    if not available?() do
      {:error, :embeddings_not_available}
    else
      # Get chunks for source
      case SQLite.get_chunks_for_source(source_id) do
        {:ok, chunks} ->
          Logger.info("Processing #{length(chunks)} chunks for source #{source_id}")
          process_chunks(chunks, state)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_process_all(state) do
    if not available?() do
      {:error, :embeddings_not_available}
    else
      # Get all sources
      case SQLite.list_sources() do
        {:ok, sources} ->
          results = Enum.map(sources, fn source ->
            case do_process_source(source.id, state) do
              {:ok, count} -> {:ok, source.id, count}
              {:error, reason} -> {:error, source.id, reason}
            end
          end)

          successful = Enum.count(results, &match?({:ok, _, _}, &1))
          total_chunks = results
          |> Enum.filter(&match?({:ok, _, _}, &1))
          |> Enum.map(fn {:ok, _, count} -> count end)
          |> Enum.sum()

          {:ok, %{sources_processed: successful, chunks_embedded: total_chunks}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp process_chunks(chunks, state) do
    # Filter chunks that already have embeddings (if skip_if_exists)
    chunks_to_process = if config(:skip_if_exists, true) do
      filter_unembedded(chunks, state)
    else
      chunks
    end

    if length(chunks_to_process) == 0 do
      {:ok, 0}
    else
      # Process in batches
      chunks_to_process
      |> Enum.chunk_every(state.batch_size)
      |> Enum.reduce({:ok, 0}, fn batch, {:ok, acc} ->
        case process_batch(batch, state) do
          {:ok, count} -> {:ok, acc + count}
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  defp process_batch(chunks, state) do
    # Extract text content
    texts = Enum.map(chunks, fn chunk ->
      "#{chunk.title}\n\n#{chunk.content}"
    end)

    # Generate embeddings
    case state.ai_provider.embed_batch(texts) do
      {:ok, embeddings} ->
        # Store in vector backend
        items = Enum.zip(chunks, embeddings)
        |> Enum.map(fn {chunk, embedding} ->
          {chunk.id, embedding, %{source_id: chunk.source_id}}
        end)

        case store_embeddings(items, state) do
          {:ok, count} ->
            Logger.debug("Stored #{count} embeddings")
            {:ok, count}

          {:error, reason} ->
            Logger.error("Failed to store embeddings: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :embeddings_disabled} ->
        {:error, :embeddings_disabled}

      {:error, reason} ->
        Logger.error("Failed to generate embeddings: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_embeddings(items, state) do
    # Check if backend supports batch
    if function_exported?(state.vector_backend, :store_batch, 1) do
      state.vector_backend.store_batch(items)
    else
      # Fall back to individual stores
      count = Enum.reduce(items, 0, fn {chunk_id, embedding, metadata}, acc ->
        case state.vector_backend.store(chunk_id, embedding, metadata) do
          :ok -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp filter_unembedded(chunks, _state) do
    # TODO: Check vector storage for existing embeddings
    # For now, return all chunks
    chunks
  end

  defp determine_batch_size do
    case config(:batch_size, :auto) do
      :auto -> Hardware.recommended_batch_size()
      n when is_integer(n) -> n
      _ -> @default_batch_size
    end
  end

  defp update_stats(state, {:ok, count}) do
    %{state | processed: state.processed + count}
  end

  defp update_stats(state, {:error, _}) do
    %{state | failed: state.failed + 1}
  end

  defp config(key, default) do
    Application.get_env(:cursor_docs, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
