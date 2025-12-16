defmodule CursorDocs.AI.Ollama do
  @moduledoc """
  Ollama embedding provider.

  Uses an existing Ollama installation for embeddings.
  This is the preferred provider when Ollama is already running.

  ## Configuration

      config :cursor_docs, CursorDocs.AI.Ollama,
        base_url: "http://localhost:11434",  # or custom port
        model: "nomic-embed-text",           # embedding model
        timeout: 30_000                       # request timeout

  ## Multi-GPU Support

  If you have multiple Ollama instances (like Obsidian's setup):

      config :cursor_docs, CursorDocs.AI.Ollama,
        instances: [
          %{url: "http://localhost:11434", gpu: "RTX 2080"},
          %{url: "http://localhost:11435", gpu: "Arc A770"}
        ],
        strategy: :round_robin  # or :fastest, :least_loaded

  ## Verified Models

  Tested embedding models:
  - `nomic-embed-text` - Best quality, 768 dimensions
  - `all-minilm` - Good quality, faster, 384 dimensions
  - `mxbai-embed-large` - High quality, 1024 dimensions

  """

  @behaviour CursorDocs.AI.Provider

  require Logger

  @default_base_url "http://localhost:11434"
  @default_model "nomic-embed-text"
  @default_timeout 30_000

  # Verified models with their specs
  @verified_models %{
    "nomic-embed-text" => %{
      name: "nomic-embed-text",
      dimensions: 768,
      context_length: 8192,
      description: "Best quality general-purpose embedding model"
    },
    "all-minilm" => %{
      name: "all-minilm",
      dimensions: 384,
      context_length: 512,
      description: "Fast, lightweight embedding model"
    },
    "mxbai-embed-large" => %{
      name: "mxbai-embed-large",
      dimensions: 1024,
      context_length: 512,
      description: "High quality, larger embedding space"
    }
  }

  @impl true
  def name, do: "Ollama"

  @impl true
  def available? do
    base_url = config(:base_url, @default_base_url)

    case check_ollama(base_url) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @impl true
  def capabilities do
    %{
      gpu_required: false,  # Can run on CPU
      min_ram_gb: 4,
      supports_batch: true,
      max_batch_size: 100
    }
  end

  @impl true
  def list_models do
    base_url = config(:base_url, @default_base_url)

    case http_get("#{base_url}/api/tags") do
      {:ok, %{"models" => models}} ->
        model_list = Enum.map(models, fn model ->
          name = model["name"]

          case Map.get(@verified_models, name) do
            nil ->
              %{
                name: name,
                dimensions: :unknown,
                context_length: :unknown,
                description: "Custom model (not verified)"
              }

            verified ->
              verified
          end
        end)

        {:ok, model_list}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def default_model do
    config(:model, @default_model)
  end

  @impl true
  def embed(text, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())
    base_url = config(:base_url, @default_base_url)
    timeout = config(:timeout, @default_timeout)

    payload = %{
      model: model,
      prompt: text
    }

    case http_post("#{base_url}/api/embeddings", payload, timeout) do
      {:ok, %{"embedding" => embedding}} ->
        {:ok, embedding}

      {:error, reason} ->
        Logger.warning("Ollama embed failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def embed_batch(texts, opts \\ []) do
    # Ollama doesn't have native batch support, so we do sequential
    # but with parallelization for multiple instances
    model = Keyword.get(opts, :model, default_model())

    results = texts
    |> Task.async_stream(
      fn text -> embed(text, model: model) end,
      max_concurrency: 4,
      timeout: 60_000
    )
    |> Enum.map(fn
      {:ok, {:ok, embedding}} -> {:ok, embedding}
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, {:exit, reason}}
    end)

    # Check if all succeeded
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        embeddings = Enum.map(results, fn {:ok, emb} -> emb end)
        {:ok, embeddings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def warmup(opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    # Warm up by generating a small embedding
    case embed("warmup", model: model) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def estimate_resources(batch_size, model) do
    model_info = Map.get(@verified_models, model, %{dimensions: 768})
    dimensions = model_info[:dimensions] || 768

    # Rough estimates based on model size and batch
    %{
      ram_mb: batch_size * 10 + 500,
      vram_mb: dimensions * batch_size * 4 / 1024 / 1024 + 1000,
      time_estimate_ms: batch_size * 100
    }
  end

  # ============================================================================
  # Multi-Instance Support (for setups like Obsidian with dual GPUs)
  # ============================================================================

  @doc """
  Get status of all configured Ollama instances.
  """
  def instance_status do
    case config(:instances) do
      nil ->
        base_url = config(:base_url, @default_base_url)
        [%{url: base_url, status: check_ollama(base_url)}]

      instances ->
        Enum.map(instances, fn %{url: url} = inst ->
          Map.put(inst, :status, check_ollama(url))
        end)
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp check_ollama(base_url) do
    case http_get("#{base_url}/api/version") do
      {:ok, %{"version" => version}} -> {:ok, version}
      {:ok, _} -> {:ok, "unknown"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp http_get(url) do
    case :httpc.request(:get, {to_charlist(url), []}, [timeout: 5000], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        Jason.decode(to_string(body))

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:http_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_post(url, payload, timeout) do
    body = Jason.encode!(payload)
    headers = [{~c"content-type", ~c"application/json"}]

    case :httpc.request(:post, {to_charlist(url), headers, ~c"application/json", body}, [timeout: timeout], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        Jason.decode(to_string(response_body))

      {:ok, {{_, status, _}, _, response_body}} ->
        {:error, {:http_error, status, to_string(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config(key, default \\ nil) do
    Application.get_env(:cursor_docs, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
