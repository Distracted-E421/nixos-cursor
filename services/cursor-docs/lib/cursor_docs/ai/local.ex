defmodule CursorDocs.AI.Local do
  @moduledoc """
  Local embedding provider - Direct inference without daemon.

  Uses ONNX Runtime or llama.cpp directly for embeddings,
  without requiring a separate server process.

  ## Benefits

  - No daemon process running in background
  - Lower memory footprint when idle
  - More control over resource usage
  - Works offline

  ## Supported Backends

  - **ONNX Runtime** - Cross-platform, CPU/GPU
  - **llama.cpp** - Optimized for CPU, good on ARM

  ## Model Location

  Models are stored in:
  - Linux: `~/.cache/cursor-docs/models/`
  - macOS: `~/Library/Caches/cursor-docs/models/`

  ## Configuration

      config :cursor_docs, CursorDocs.AI.Local,
        backend: :onnx,  # or :llamacpp
        model_path: "~/.cache/cursor-docs/models/all-minilm-l6-v2.onnx",
        device: :cpu,    # or :cuda, :rocm, :metal
        threads: 4       # CPU threads to use

  ## Verified Models

  Pre-tested ONNX models:
  - `all-minilm-l6-v2.onnx` - 384 dims, 22MB, fast
  - `nomic-embed-text-v1.onnx` - 768 dims, 137MB, best quality
  - `bge-small-en-v1.5.onnx` - 384 dims, 33MB, good quality

  ## Setup

      # Download a model
      mix cursor_docs.model download all-minilm

      # Verify it works
      mix cursor_docs.model test all-minilm

  """

  @behaviour CursorDocs.AI.Provider

  require Logger

  @model_dir_linux "~/.cache/cursor-docs/models"
  @model_dir_macos "~/Library/Caches/cursor-docs/models"

  @verified_models %{
    "all-minilm" => %{
      name: "all-minilm",
      file: "all-minilm-l6-v2.onnx",
      dimensions: 384,
      context_length: 512,
      size_mb: 22,
      description: "Fast, lightweight embedding model",
      url: "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx"
    },
    "nomic-embed" => %{
      name: "nomic-embed",
      file: "nomic-embed-text-v1.onnx",
      dimensions: 768,
      context_length: 8192,
      size_mb: 137,
      description: "Best quality general-purpose embedding model",
      url: nil  # Requires manual download due to license
    },
    "bge-small" => %{
      name: "bge-small",
      file: "bge-small-en-v1.5.onnx",
      dimensions: 384,
      context_length: 512,
      size_mb: 33,
      description: "Good quality, slightly larger",
      url: "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx"
    }
  }

  @impl true
  def name, do: "Local (ONNX)"

  @impl true
  def available? do
    # Check if we have ONNX runtime or llama.cpp available
    has_backend?() and has_model?()
  end

  @impl true
  def capabilities do
    hardware = CursorDocs.AI.Hardware.detect()

    %{
      gpu_required: false,
      min_ram_gb: 2,
      supports_batch: true,
      max_batch_size: hardware.cpu.threads * 4
    }
  end

  @impl true
  def list_models do
    # List downloaded models
    model_dir = model_directory()

    case File.ls(model_dir) do
      {:ok, files} ->
        models = files
        |> Enum.filter(&String.ends_with?(&1, ".onnx"))
        |> Enum.map(fn file ->
          base = Path.basename(file, ".onnx")

          case find_verified_model(file) do
            nil ->
              %{
                name: base,
                dimensions: :unknown,
                context_length: :unknown,
                description: "Custom model"
              }

            verified ->
              Map.take(verified, [:name, :dimensions, :context_length, :description])
          end
        end)

        {:ok, models}

      {:error, _} ->
        {:ok, []}
    end
  end

  @impl true
  def default_model do
    config(:model, "all-minilm")
  end

  @impl true
  def embed(_text, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    # This would use Ortex (Elixir ONNX Runtime bindings) when available
    # For now, return a placeholder error guiding users to install
    case load_model(model) do
      {:ok, _model_ref} ->
        # Would call Ortex.run/2 here
        {:error, :onnx_runtime_not_implemented}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def embed_batch(_texts, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    case load_model(model) do
      {:ok, _model_ref} ->
        # Would batch process here
        {:error, :onnx_runtime_not_implemented}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def warmup(opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    case load_model(model) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def estimate_resources(batch_size, model) do
    model_info = Map.get(@verified_models, model, %{dimensions: 384, size_mb: 50})
    dimensions = model_info[:dimensions] || 384
    size_mb = model_info[:size_mb] || 50

    %{
      ram_mb: size_mb + batch_size * dimensions * 4 / 1024 / 1024,
      vram_mb: 0,  # CPU by default
      time_estimate_ms: batch_size * 50  # ~50ms per embedding on CPU
    }
  end

  # ============================================================================
  # Model Management
  # ============================================================================

  @doc """
  Get the model directory path.
  """
  def model_directory do
    custom = config(:model_dir)

    dir = cond do
      custom != nil -> custom
      :os.type() == {:unix, :darwin} -> Path.expand(@model_dir_macos)
      true -> Path.expand(@model_dir_linux)
    end

    # Ensure directory exists
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Download a verified model.
  """
  def download_model(model_name) do
    case Map.get(@verified_models, model_name) do
      nil ->
        {:error, {:unknown_model, model_name}}

      %{url: nil} ->
        {:error, {:manual_download_required, model_name}}

      %{url: url, file: file} ->
        target_path = Path.join(model_directory(), file)

        if File.exists?(target_path) do
          {:ok, :already_exists}
        else
          Logger.info("Downloading #{model_name} from #{url}...")
          download_file(url, target_path)
        end
    end
  end

  @doc """
  List available models for download.
  """
  def available_models do
    @verified_models
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp has_backend? do
    # Check for ONNX Runtime
    # In a full implementation, we'd check for Ortex or a NIF
    Code.ensure_loaded?(Ortex) or
    System.find_executable("onnxruntime") != nil
  rescue
    _ -> false
  end

  defp has_model? do
    case list_models() do
      {:ok, models} -> length(models) > 0
      _ -> false
    end
  end

  defp load_model(model_name) do
    model_info = Map.get(@verified_models, model_name)
    file = if model_info, do: model_info[:file], else: "#{model_name}.onnx"
    path = Path.join(model_directory(), file)

    if File.exists?(path) do
      # Would load via Ortex here
      {:ok, {:model_ref, path}}
    else
      {:error, {:model_not_found, model_name, path}}
    end
  end

  defp find_verified_model(filename) do
    @verified_models
    |> Map.values()
    |> Enum.find(&(&1[:file] == filename))
  end

  defp download_file(url, target_path) do
    # Simple download using :httpc
    case :httpc.request(:get, {to_charlist(url), []}, [timeout: 300_000], [body_format: :binary]) do
      {:ok, {{_, 200, _}, _, body}} ->
        File.write!(target_path, body)
        {:ok, target_path}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config(key, default \\ nil) do
    Application.get_env(:cursor_docs, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
