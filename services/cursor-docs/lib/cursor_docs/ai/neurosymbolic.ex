defmodule CursorDocs.AI.Neurosymbolic do
  @moduledoc """
  Neuro-Symbolic AI Framework for cursor-docs.

  This module provides a hybrid reasoning system that combines:
  - **Neural Networks** (LLMs via Ollama) for natural language understanding
  - **Symbolic Reasoning** for logical inference and explainability
  - **Co-Routines** for stateful, interruptible reasoning workflows

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────────┐
  │                    NEURO-SYMBOLIC PIPELINE                       │
  ├─────────────────────────────────────────────────────────────────┤
  │                                                                  │
  │   Query ──► Parser ──► Grounder ──► Reasoner ──► Explainer      │
  │             (LLM)       (LLM+KG)     (Rules+LLM)   (LLM)         │
  │                                                                  │
  │   Each stage can YIELD (suspend) and RESUME with new input      │
  │                                                                  │
  └─────────────────────────────────────────────────────────────────┘
  ```

  ## Quick Start

      # Simple synchronous reasoning
      {:ok, result} = CursorDocs.AI.Neurosymbolic.reason("Is this function safe?")

      # Async reasoning with status polling
      {:ok, session_id} = CursorDocs.AI.Neurosymbolic.reason_async("Complex query...")
      {:ok, status} = CursorDocs.AI.Neurosymbolic.status(session_id)

      # Resume if yielded (needs user input)
      {:ok, result} = CursorDocs.AI.Neurosymbolic.resume(session_id, %{clarification: "..."})

  ## Components

  - `Parser` - Converts NL to structured intents
  - `Grounder` - Maps entities to knowledge graph symbols
  - `Reasoner` - Performs logical inference
  - `Explainer` - Generates human-readable explanations
  - `Orchestrator` - Manages the co-routine workflow

  ## Models Used

  | Component | Model | GPU | Purpose |
  |-----------|-------|-----|---------|
  | Parser | qwen2.5-coder:7b | RTX 2080 | Parse queries, detect code |
  | Grounder | qwen2.5:7b | RTX 2080 | Entity resolution |
  | Reasoner | qwen2.5:7b | RTX 2080 | Logical inference |
  | Explainer | qwen2.5:7b | RTX 2080 | Generate explanations |
  | Embeddings | nomic-embed-text | Arc A770 | Similarity search |

  ## Research References

  - IBM Logical Neural Networks (LNN)
  - Stanford DSPy framework
  - Symbol Grounding Problem
  - Co-routine patterns for AI
  """

  alias CursorDocs.AI.Neurosymbolic.{Orchestrator, Parser, Grounder, Reasoner, Explainer}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Start the neuro-symbolic reasoning system.

  This starts the Orchestrator GenServer that manages reasoning sessions.
  """
  def start_link(opts \\ []) do
    Orchestrator.start_link(opts)
  end

  @doc """
  Perform synchronous reasoning on a query.

  This is the simplest way to use the system - it runs the full pipeline
  and blocks until complete.

  ## Options

    * `:timeout` - Maximum time to wait (default: 30_000ms)
    * `:level` - Explanation detail level: `:brief`, `:standard`, `:detailed`

  ## Examples

      iex> reason("Is this code safe to use?")
      {:ok, %{
        summary: "Based on analysis, the code appears safe...",
        reasoning: "...",
        confidence: 0.85
      }}

  """
  @spec reason(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reason(query, opts \\ []) do
    Orchestrator.reason_sync(query, opts)
  end

  @doc """
  Start asynchronous reasoning.

  Returns a session ID that can be used to poll status or resume.

  ## Examples

      iex> {:ok, session_id} = reason_async("Complex reasoning query...")
      iex> status(session_id)
      {:ok, %{state: :reasoning, ...}}

  """
  @spec reason_async(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def reason_async(query, opts \\ []) do
    Orchestrator.begin_reasoning(query, opts)
  end

  @doc """
  Get the status of a reasoning session.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(session_id) do
    Orchestrator.status(session_id)
  end

  @doc """
  Resume a yielded reasoning session with new input.

  Some reasoning steps may yield when they need additional input
  (e.g., clarification from user, results from external tools).

  ## Examples

      iex> resume(session_id, %{clarification: "I meant the validate function"})
      {:ok, %{state: :reasoning, ...}}

  """
  @spec resume(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def resume(session_id, input) do
    Orchestrator.resume(session_id, input)
  end

  @doc """
  Cancel an in-progress reasoning session.
  """
  @spec cancel(String.t()) :: :ok | {:error, :not_found}
  def cancel(session_id) do
    Orchestrator.cancel(session_id)
  end

  @doc """
  List all active reasoning sessions.
  """
  @spec list_sessions() :: list(map())
  def list_sessions do
    Orchestrator.list_sessions()
  end

  # ============================================================================
  # Direct Component Access
  # ============================================================================

  @doc """
  Parse a query without running the full pipeline.

  Useful for debugging or when you want to process components separately.
  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(query, opts \\ []) do
    Parser.parse(query, opts)
  end

  @doc """
  Ground parsed entities without reasoning.
  """
  @spec ground(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def ground(parsed, opts \\ []) do
    Grounder.ground(parsed, opts)
  end

  @doc """
  Run inference on grounded symbols.
  """
  @spec infer(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def infer(parsed, grounded, opts \\ []) do
    Reasoner.infer(parsed, grounded, opts)
  end

  @doc """
  Generate explanation from inference results.
  """
  @spec explain(map(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def explain(parsed, grounded, inference, opts \\ []) do
    Explainer.explain(parsed, grounded, inference, opts)
  end

  # ============================================================================
  # Fast Mode (No LLM)
  # ============================================================================

  @doc """
  Run the pipeline in fast mode (no LLM calls).

  Uses heuristic parsing, rule-based reasoning, and template-based explanation.
  Much faster but less accurate.
  """
  @spec reason_fast(String.t()) :: {:ok, map()}
  def reason_fast(query) do
    with {:ok, parsed} <- Parser.parse_fast(query),
         {:ok, grounded} <- Grounder.ground_fast(parsed),
         {:ok, inference} <- Reasoner.infer_fast(parsed, grounded),
         {:ok, explanation} <- Explainer.explain_fast(parsed, grounded, inference) do
      {:ok, %{
        query: query,
        parsed: parsed,
        grounded: grounded,
        inference: inference,
        explanation: explanation
      }}
    end
  end

  # ============================================================================
  # System Status
  # ============================================================================

  @doc """
  Get the status of the neuro-symbolic system.
  """
  @spec system_status() :: map()
  def system_status do
    ollama_status = check_ollama()
    models = list_available_models()

    %{
      orchestrator: Process.whereis(Orchestrator) != nil,
      ollama: ollama_status,
      models: models,
      sessions: length(list_sessions()),
      capabilities: %{
        parsing: "qwen2.5-coder:7b" in models or "qwen2.5:7b" in models,
        grounding: "qwen2.5:7b" in models,
        reasoning: true,  # Rule-based always available
        explaining: "qwen2.5:7b" in models,
        embeddings: CursorDocs.Embeddings.available?()
      }
    }
  end

  defp check_ollama do
    case Req.get("http://localhost:11434/api/version", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"version" => version}}} -> {:ok, version}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp list_available_models do
    case Req.get("http://localhost:11434/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        Enum.map(models, & &1["name"])

      _ ->
        []
    end
  rescue
    _ -> []
  end
end
