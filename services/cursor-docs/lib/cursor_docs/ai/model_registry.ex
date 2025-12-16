defmodule CursorDocs.AI.ModelRegistry do
  @moduledoc """
  Registry of tested and verified embedding models.

  ## Philosophy

  cursor-docs ships with a curated list of models that have been:
  - Tested for quality on documentation search
  - Benchmarked for performance
  - Verified to work with supported backends

  Users can still use custom models, but verified models
  provide a "works out of the box" experience.

  ## Quality Tiers

  - **Recommended**: Best quality/performance balance
  - **Fast**: Prioritizes speed over quality
  - **Quality**: Prioritizes quality over speed
  - **Experimental**: New models being evaluated

  ## Usage

      # Get recommended model for hardware
      model = ModelRegistry.recommended()

      # Get model info
      info = ModelRegistry.info("nomic-embed-text")

      # List all verified models
      models = ModelRegistry.list()

  """

  @type model_spec :: %{
    name: String.t(),
    provider: :ollama | :local | :openai,
    dimensions: pos_integer(),
    context_length: pos_integer(),
    quality_score: float(),
    speed_score: float(),
    size_mb: pos_integer(),
    description: String.t(),
    tier: :recommended | :fast | :quality | :experimental,
    hardware_requirements: %{
      min_ram_gb: number(),
      min_vram_gb: number() | nil,
      supports_cpu: boolean()
    }
  }

  @verified_models %{
    # ============================================
    # Ollama Models
    # ============================================
    "nomic-embed-text" => %{
      name: "nomic-embed-text",
      provider: :ollama,
      dimensions: 768,
      context_length: 8192,
      quality_score: 0.92,
      speed_score: 0.75,
      size_mb: 274,
      description: "Best overall embedding model. Long context support.",
      tier: :recommended,
      hardware_requirements: %{
        min_ram_gb: 4,
        min_vram_gb: 2,
        supports_cpu: true
      }
    },

    "all-minilm" => %{
      name: "all-minilm",
      provider: :ollama,
      dimensions: 384,
      context_length: 512,
      quality_score: 0.82,
      speed_score: 0.95,
      size_mb: 45,
      description: "Fast, lightweight. Good for limited hardware.",
      tier: :fast,
      hardware_requirements: %{
        min_ram_gb: 2,
        min_vram_gb: nil,
        supports_cpu: true
      }
    },

    "mxbai-embed-large" => %{
      name: "mxbai-embed-large",
      provider: :ollama,
      dimensions: 1024,
      context_length: 512,
      quality_score: 0.94,
      speed_score: 0.60,
      size_mb: 670,
      description: "Highest quality. Best for semantic search.",
      tier: :quality,
      hardware_requirements: %{
        min_ram_gb: 8,
        min_vram_gb: 4,
        supports_cpu: true
      }
    },

    "snowflake-arctic-embed" => %{
      name: "snowflake-arctic-embed",
      provider: :ollama,
      dimensions: 1024,
      context_length: 512,
      quality_score: 0.93,
      speed_score: 0.65,
      size_mb: 568,
      description: "Excellent for code and technical docs.",
      tier: :quality,
      hardware_requirements: %{
        min_ram_gb: 6,
        min_vram_gb: 3,
        supports_cpu: true
      }
    },

    # ============================================
    # Local ONNX Models
    # ============================================
    "all-minilm-l6-v2" => %{
      name: "all-minilm-l6-v2",
      provider: :local,
      dimensions: 384,
      context_length: 512,
      quality_score: 0.82,
      speed_score: 0.95,
      size_mb: 22,
      description: "Tiny ONNX model. Runs anywhere.",
      tier: :fast,
      hardware_requirements: %{
        min_ram_gb: 1,
        min_vram_gb: nil,
        supports_cpu: true
      }
    },

    "bge-small-en-v1.5" => %{
      name: "bge-small-en-v1.5",
      provider: :local,
      dimensions: 384,
      context_length: 512,
      quality_score: 0.86,
      speed_score: 0.90,
      size_mb: 33,
      description: "Good balance for local inference.",
      tier: :recommended,
      hardware_requirements: %{
        min_ram_gb: 2,
        min_vram_gb: nil,
        supports_cpu: true
      }
    },

    # ============================================
    # OpenAI Models (for reference/fallback)
    # ============================================
    "text-embedding-3-small" => %{
      name: "text-embedding-3-small",
      provider: :openai,
      dimensions: 1536,
      context_length: 8191,
      quality_score: 0.91,
      speed_score: 0.85,
      size_mb: 0,  # Cloud
      description: "OpenAI's small embedding model. Requires API key.",
      tier: :quality,
      hardware_requirements: %{
        min_ram_gb: 0,
        min_vram_gb: nil,
        supports_cpu: true
      }
    },

    "text-embedding-3-large" => %{
      name: "text-embedding-3-large",
      provider: :openai,
      dimensions: 3072,
      context_length: 8191,
      quality_score: 0.96,
      speed_score: 0.75,
      size_mb: 0,  # Cloud
      description: "OpenAI's best embedding model. Requires API key.",
      tier: :quality,
      hardware_requirements: %{
        min_ram_gb: 0,
        min_vram_gb: nil,
        supports_cpu: true
      }
    }
  }

  @doc """
  Get the recommended model for current hardware.
  """
  @spec recommended() :: String.t()
  def recommended do
    hardware = CursorDocs.AI.Hardware.detect()
    vram = CursorDocs.AI.Hardware.total_vram_mb()
    ram = hardware.ram_mb

    cond do
      vram > 4000 -> "nomic-embed-text"
      vram > 2000 -> "all-minilm"
      ram > 8000 -> "bge-small-en-v1.5"
      true -> "all-minilm-l6-v2"
    end
  end

  @doc """
  Get the recommended model for a specific tier.
  """
  @spec recommended_for_tier(:fast | :recommended | :quality) :: String.t()
  def recommended_for_tier(:fast), do: "all-minilm"
  def recommended_for_tier(:recommended), do: "nomic-embed-text"
  def recommended_for_tier(:quality), do: "mxbai-embed-large"

  @doc """
  Get information about a specific model.
  """
  @spec info(String.t()) :: model_spec() | nil
  def info(model_name) do
    Map.get(@verified_models, model_name)
  end

  @doc """
  List all verified models.
  """
  @spec list() :: list(model_spec())
  def list do
    Map.values(@verified_models)
  end

  @doc """
  List models for a specific provider.
  """
  @spec list_for_provider(:ollama | :local | :openai) :: list(model_spec())
  def list_for_provider(provider) do
    @verified_models
    |> Map.values()
    |> Enum.filter(&(&1.provider == provider))
  end

  @doc """
  List models for a specific tier.
  """
  @spec list_for_tier(:fast | :recommended | :quality | :experimental) :: list(model_spec())
  def list_for_tier(tier) do
    @verified_models
    |> Map.values()
    |> Enum.filter(&(&1.tier == tier))
  end

  @doc """
  Check if a model is verified.
  """
  @spec verified?(String.t()) :: boolean()
  def verified?(model_name) do
    Map.has_key?(@verified_models, model_name)
  end

  @doc """
  Get models compatible with current hardware.
  """
  @spec compatible() :: list(model_spec())
  def compatible do
    hardware = CursorDocs.AI.Hardware.detect()
    vram = CursorDocs.AI.Hardware.total_vram_mb()
    ram = hardware.ram_mb

    @verified_models
    |> Map.values()
    |> Enum.filter(fn model ->
      reqs = model.hardware_requirements
      ram_ok = ram >= reqs.min_ram_gb * 1024
      vram_ok = reqs.min_vram_gb == nil or vram >= reqs.min_vram_gb * 1024
      cpu_ok = reqs.supports_cpu or CursorDocs.AI.Hardware.has_gpu?()

      ram_ok and vram_ok and cpu_ok
    end)
    |> Enum.sort_by(& &1.quality_score, :desc)
  end

  @doc """
  Format models as a comparison table.
  """
  @spec format_comparison() :: String.t()
  def format_comparison do
    header = """
    | Model | Provider | Dims | Quality | Speed | Size | Tier |
    |-------|----------|------|---------|-------|------|------|
    """

    rows = @verified_models
    |> Map.values()
    |> Enum.sort_by(&{&1.tier, -&1.quality_score})
    |> Enum.map(fn m ->
      "| #{m.name} | #{m.provider} | #{m.dimensions} | #{Float.round(m.quality_score * 100, 0)}% | #{Float.round(m.speed_score * 100, 0)}% | #{m.size_mb}MB | #{m.tier} |"
    end)
    |> Enum.join("\n")

    header <> rows
  end
end
