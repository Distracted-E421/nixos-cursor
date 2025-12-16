defmodule CursorDocs.AI.Provider do
  @moduledoc """
  Behaviour for AI embedding providers.

  ## Philosophy

  cursor-docs should be useful without being a problem:
  - **No forced dependencies** - Works with SQLite alone
  - **No background daemons** - Unless user explicitly wants them
  - **Hardware-aware** - Detects and uses what's available
  - **Pluggable** - Use Ollama, local models, or cloud APIs

  ## Providers

  Built-in providers:
  - `CursorDocs.AI.Ollama` - Uses existing Ollama installation
  - `CursorDocs.AI.Local` - Direct llama.cpp/ONNX (no daemon)
  - `CursorDocs.AI.OpenAI` - API fallback (requires key)
  - `CursorDocs.AI.Disabled` - No embeddings, FTS5 only

  ## Usage

      # Auto-detect best provider
      {:ok, provider} = Provider.detect()

      # Generate embedding
      {:ok, embedding} = Provider.embed(provider, "some text")

      # Batch embed
      {:ok, embeddings} = Provider.embed_batch(provider, texts)

  ## Custom Providers

  Implement the behaviour:

      defmodule MyProvider do
        @behaviour CursorDocs.AI.Provider

        @impl true
        def name, do: "my-provider"

        @impl true
        def available?, do: check_my_backend()

        @impl true
        def embed(text, opts), do: call_my_backend(text, opts)

        # ... etc
      end

  Then register it:

      config :cursor_docs, :ai_providers, [MyProvider | default_providers()]

  """

  @type embedding :: list(float())
  @type model_info :: %{
    name: String.t(),
    dimensions: pos_integer(),
    context_length: pos_integer(),
    description: String.t()
  }

  @doc "Human-readable provider name"
  @callback name() :: String.t()

  @doc "Check if this provider is available on the system"
  @callback available?() :: boolean()

  @doc "Get hardware requirements/capabilities"
  @callback capabilities() :: %{
    optional(:gpu_required) => boolean(),
    optional(:min_ram_gb) => number(),
    optional(:supports_batch) => boolean(),
    optional(:max_batch_size) => pos_integer()
  }

  @doc "List available models"
  @callback list_models() :: {:ok, list(model_info())} | {:error, term()}

  @doc "Get the default/recommended model"
  @callback default_model() :: String.t()

  @doc "Generate embedding for text"
  @callback embed(text :: String.t(), opts :: keyword()) :: {:ok, embedding()} | {:error, term()}

  @doc "Generate embeddings for multiple texts"
  @callback embed_batch(texts :: list(String.t()), opts :: keyword()) :: {:ok, list(embedding())} | {:error, term()}

  @doc "Warm up the model (optional, for providers that benefit from pre-loading)"
  @callback warmup(opts :: keyword()) :: :ok | {:error, term()}

  @doc "Get estimated resource usage for a batch size"
  @callback estimate_resources(batch_size :: pos_integer(), model :: String.t()) :: %{
    ram_mb: number(),
    vram_mb: number(),
    time_estimate_ms: number()
  }

  @optional_callbacks [warmup: 1, estimate_resources: 2]

  # ============================================================================
  # Provider Detection & Management
  # ============================================================================

  @doc """
  Detect the best available provider based on hardware and installed software.

  Priority order:
  1. User-configured provider (if set and available)
  2. Ollama (if running)
  3. Local ONNX/llama.cpp (if models present)
  4. Disabled (FTS5 only)
  """
  def detect do
    providers = configured_providers()

    case Enum.find(providers, & &1.available?()) do
      nil ->
        {:ok, CursorDocs.AI.Disabled}

      provider ->
        {:ok, provider}
    end
  end

  @doc """
  Get all configured providers.
  """
  def configured_providers do
    Application.get_env(:cursor_docs, :ai_providers, default_providers())
  end

  @doc """
  Default provider priority list.
  """
  def default_providers do
    [
      CursorDocs.AI.Ollama,
      CursorDocs.AI.Local,
      CursorDocs.AI.Disabled
    ]
  end

  @doc """
  Get detailed status of all providers.
  """
  def status do
    providers = configured_providers()

    Enum.map(providers, fn provider ->
      %{
        name: provider.name(),
        available: provider.available?(),
        capabilities: provider.capabilities()
      }
    end)
  end

  @doc """
  Embed text using the best available provider.
  """
  def embed(text, opts \\ []) do
    with {:ok, provider} <- detect() do
      provider.embed(text, opts)
    end
  end

  @doc """
  Batch embed using the best available provider.
  """
  def embed_batch(texts, opts \\ []) do
    with {:ok, provider} <- detect() do
      provider.embed_batch(texts, opts)
    end
  end
end
