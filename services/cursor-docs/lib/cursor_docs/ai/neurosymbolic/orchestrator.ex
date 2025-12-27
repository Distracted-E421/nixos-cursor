defmodule CursorDocs.AI.Neurosymbolic.Orchestrator do
  @moduledoc """
  Co-routine orchestrator for neuro-symbolic reasoning.

  This module implements a state machine that manages multi-step reasoning
  workflows. Each reasoning session can be suspended (yielded) at any point
  and resumed later with new input.

  ## Architecture

  ```
  Query → [Parse] → [Ground] → [Reason] → [Explain] → Response
              ↑          ↑          ↑           ↑
              └──────────┴──────────┴───────────┘
                    YIELD / RESUME points
  ```

  ## States

  - `:idle` - No active reasoning
  - `:parsing` - Converting NL to structured form
  - `:grounding` - Mapping to symbols/entities
  - `:reasoning` - Logical inference
  - `:explaining` - Generating explanation
  - `:complete` - Finished with result
  - `:failed` - Error occurred

  ## Usage

      # Start a reasoning chain
      {:ok, session_id} = Orchestrator.begin_reasoning("Is this code safe?")

      # Check status
      {:ok, %{state: :parsing, data: ...}} = Orchestrator.status(session_id)

      # Resume if yielded (e.g., waiting for clarification)
      {:ok, result} = Orchestrator.resume(session_id, %{clarification: "..."})

  """

  use GenServer
  require Logger

  alias CursorDocs.AI.Neurosymbolic.{Parser, Grounder, Reasoner, Explainer}

  # Session state structure
  defstruct [
    :id,
    :query,
    :state,
    :parsed,
    :grounded,
    :inference,
    :explanation,
    :error,
    :started_at,
    :updated_at,
    :history
  ]

  @type state :: :idle | :parsing | :grounding | :reasoning | :explaining | :complete | :failed

  @type session :: %__MODULE__{
    id: String.t(),
    query: String.t(),
    state: state(),
    parsed: map() | nil,
    grounded: map() | nil,
    inference: map() | nil,
    explanation: String.t() | nil,
    error: term() | nil,
    started_at: DateTime.t(),
    updated_at: DateTime.t(),
    history: list()
  }

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Begin a new reasoning session for a query.

  Returns `{:ok, session_id}` or `{:error, reason}`.
  """
  @spec begin_reasoning(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def begin_reasoning(query, opts \\ []) do
    GenServer.call(__MODULE__, {:begin, query, opts})
  end

  @doc """
  Get the status of a reasoning session.
  """
  @spec status(String.t()) :: {:ok, session()} | {:error, :not_found}
  def status(session_id) do
    GenServer.call(__MODULE__, {:status, session_id})
  end

  @doc """
  Resume a yielded session with new input.

  This is used when a reasoning step needs external input (e.g., clarification
  from user, tool results, etc.)
  """
  @spec resume(String.t(), map()) :: {:ok, session()} | {:error, term()}
  def resume(session_id, input) do
    GenServer.call(__MODULE__, {:resume, session_id, input})
  end

  @doc """
  Cancel an in-progress reasoning session.
  """
  @spec cancel(String.t()) :: :ok | {:error, :not_found}
  def cancel(session_id) do
    GenServer.call(__MODULE__, {:cancel, session_id})
  end

  @doc """
  List all active sessions.
  """
  @spec list_sessions() :: list(session())
  def list_sessions do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Run a complete reasoning chain synchronously.

  This is a convenience wrapper that runs the full pipeline without
  intermediate yields. Use for simple queries that don't need
  human-in-the-loop.
  """
  @spec reason_sync(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reason_sync(query, opts \\ []) do
    with {:ok, session_id} <- begin_reasoning(query, opts),
         {:ok, result} <- await_completion(session_id, opts) do
      {:ok, result}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:begin, query, opts}, _from, state) do
    session_id = generate_session_id()

    session = %__MODULE__{
      id: session_id,
      query: query,
      state: :idle,
      started_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      history: []
    }

    new_state = put_in(state, [:sessions, session_id], session)

    # Start the reasoning pipeline asynchronously
    Task.start(fn -> run_pipeline(session_id, query, opts) end)

    {:reply, {:ok, session_id}, new_state}
  end

  @impl true
  def handle_call({:status, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:resume, session_id, input}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        # Resume based on current state
        Task.start(fn -> resume_pipeline(session, input) end)
        {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:cancel, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _session ->
        new_state = update_in(state, [:sessions], &Map.delete(&1, session_id))
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.sessions), state}
  end

  @impl true
  def handle_cast({:update_session, session_id, updates}, state) do
    new_state = update_in(state, [:sessions, session_id], fn session ->
      if session do
        session
        |> Map.merge(updates)
        |> Map.put(:updated_at, DateTime.utc_now())
        |> Map.update!(:history, &[updates | &1])
      else
        session
      end
    end)

    {:noreply, new_state}
  end

  # ============================================================================
  # Pipeline Execution
  # ============================================================================

  defp run_pipeline(session_id, query, opts) do
    Logger.info("[Neurosymbolic] Starting reasoning for session #{session_id}")

    # Phase 1: Parse
    update_state(session_id, %{state: :parsing})

    case Parser.parse(query, opts) do
      {:ok, parsed} ->
        update_state(session_id, %{state: :grounding, parsed: parsed})
        run_grounding(session_id, parsed, opts)

      {:error, reason} ->
        update_state(session_id, %{state: :failed, error: {:parsing_failed, reason}})
    end
  end

  defp run_grounding(session_id, parsed, opts) do
    case Grounder.ground(parsed, opts) do
      {:ok, grounded} ->
        update_state(session_id, %{state: :reasoning, grounded: grounded})
        run_reasoning(session_id, parsed, grounded, opts)

      {:yield, :need_clarification, context} ->
        # Suspend here - need user input
        update_state(session_id, %{state: :grounding, grounded: {:pending, context}})

      {:error, reason} ->
        update_state(session_id, %{state: :failed, error: {:grounding_failed, reason}})
    end
  end

  defp run_reasoning(session_id, parsed, grounded, opts) do
    case Reasoner.infer(parsed, grounded, opts) do
      {:ok, inference} ->
        update_state(session_id, %{state: :explaining, inference: inference})
        run_explaining(session_id, parsed, grounded, inference, opts)

      {:yield, :need_facts, context} ->
        # Suspend here - need additional facts
        update_state(session_id, %{state: :reasoning, inference: {:pending, context}})

      {:error, reason} ->
        update_state(session_id, %{state: :failed, error: {:reasoning_failed, reason}})
    end
  end

  defp run_explaining(session_id, parsed, grounded, inference, opts) do
    case Explainer.explain(parsed, grounded, inference, opts) do
      {:ok, explanation} ->
        update_state(session_id, %{
          state: :complete,
          explanation: explanation
        })

        Logger.info("[Neurosymbolic] Completed reasoning for session #{session_id}")

      {:error, reason} ->
        update_state(session_id, %{state: :failed, error: {:explanation_failed, reason}})
    end
  end

  defp resume_pipeline(session, input) do
    case session.state do
      :grounding when is_tuple(session.grounded) and elem(session.grounded, 0) == :pending ->
        # Resume grounding with user clarification
        Logger.info("[Neurosymbolic] Resuming grounding with clarification")
        # ... implementation

      :reasoning when is_tuple(session.inference) and elem(session.inference, 0) == :pending ->
        # Resume reasoning with additional facts
        Logger.info("[Neurosymbolic] Resuming reasoning with additional facts")
        # ... implementation

      other ->
        Logger.warning("[Neurosymbolic] Cannot resume session in state: #{inspect(other)}")
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp update_state(session_id, updates) do
    GenServer.cast(__MODULE__, {:update_session, session_id, updates})
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp await_completion(session_id, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    deadline = System.monotonic_time(:millisecond) + timeout

    await_loop(session_id, deadline)
  end

  defp await_loop(session_id, deadline) do
    case status(session_id) do
      {:ok, %{state: :complete} = session} ->
        {:ok, %{
          query: session.query,
          parsed: session.parsed,
          grounded: session.grounded,
          inference: session.inference,
          explanation: session.explanation
        }}

      {:ok, %{state: :failed, error: error}} ->
        {:error, error}

      {:ok, _session} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(100)
          await_loop(session_id, deadline)
        else
          {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
