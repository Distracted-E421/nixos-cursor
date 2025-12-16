defmodule CursorDocs.AI.Disabled do
  @moduledoc """
  Disabled embedding provider - FTS5 only mode.

  This provider is used when:
  - No AI backend is available
  - User explicitly disables embeddings
  - System resources are too limited

  ## Behavior

  - `available?/0` always returns true (it's the fallback)
  - `embed/2` returns an error indicating embeddings are disabled
  - Search falls back to SQLite FTS5 full-text search

  ## When This is Used

  cursor-docs is designed to be useful even without embeddings.
  FTS5 provides:
  - Full-text search with relevance ranking
  - Phrase matching
  - Boolean operators (AND, OR, NOT)
  - Prefix matching

  Users can still:
  - Add and scrape documentation
  - Search using keywords
  - Export and manage sources

  ## Enabling Embeddings Later

  To enable embeddings later:

      # Install Ollama and pull an embedding model
      ollama pull nomic-embed-text

      # Restart cursor-docs to detect Ollama
      mix cursor_docs.status

  """

  @behaviour CursorDocs.AI.Provider

  @impl true
  def name, do: "Disabled (FTS5 only)"

  @impl true
  def available?, do: true  # Always available as fallback

  @impl true
  def capabilities do
    %{
      gpu_required: false,
      min_ram_gb: 0,
      supports_batch: false,
      max_batch_size: 0
    }
  end

  @impl true
  def list_models do
    {:ok, []}
  end

  @impl true
  def default_model do
    "none"
  end

  @impl true
  def embed(_text, _opts \\ []) do
    {:error, :embeddings_disabled}
  end

  @impl true
  def embed_batch(_texts, _opts \\ []) do
    {:error, :embeddings_disabled}
  end

  @impl true
  def warmup(_opts \\ []) do
    :ok
  end

  @impl true
  def estimate_resources(_batch_size, _model) do
    %{
      ram_mb: 0,
      vram_mb: 0,
      time_estimate_ms: 0
    }
  end
end
