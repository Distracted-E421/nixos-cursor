# lib/cursor_docs/ai/lnn/model.ex
defmodule CursorDocs.AI.LNN.Model do
  @moduledoc """
  Elixir port of IBM's Logical Neural Networks (LNN).

  LNNs are a neuro-symbolic framework that provides:
  - Interpretable disentangled representations (every neuron = formula)
  - Omnidirectional inference (not just forward pass)
  - End-to-end differentiable learning
  - Open-world assumption with belief bounds

  ## Example

      alias CursorDocs.AI.LNN.{Model, Predicate, And, Implies, Fact}

      # Define predicates
      smokes = Predicate.new("Smokes", 1)
      cough = Predicate.new("Cough", 1)

      # Define formula: Smokes(x) -> Cough(x)
      rule = Implies.new(smokes, cough)

      # Create model
      {:ok, model} = Model.new("SmokersCough")
      {:ok, model} = Model.add_knowledge(model, rule)

      # Add data
      {:ok, model} = Model.add_data(model, smokes, %{
        "Alice" => Fact.true(),
        "Bob" => Fact.unknown()
      })

      # Reason
      {:ok, model, inferred} = Model.infer(model)

  ## References

  - Paper: "Logical Neural Networks" (Riegel et al., 2020)
  - GitHub: https://github.com/IBM/LNN
  """

  use GenServer
  require Logger

  alias CursorDocs.AI.LNN.{Formula, Graph}

  @type t :: %__MODULE__{
          name: String.t(),
          graph: Graph.t(),
          nodes: %{non_neg_integer() => Formula.t()},
          node_names: %{String.t() => [Formula.t()]},
          num_formulae: non_neg_integer(),
          query: Formula.t() | nil
        }

  defstruct [
    :name,
    :graph,
    :nodes,
    :node_names,
    :num_formulae,
    :query
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Create a new LNN model.
  """
  @spec new(String.t()) :: {:ok, t()}
  def new(name \\ "Model") do
    model = %__MODULE__{
      name: name,
      graph: Graph.new(),
      nodes: %{},
      node_names: %{},
      num_formulae: 0,
      query: nil
    }

    Logger.info("LNN Model '#{name}' created")
    {:ok, model}
  end

  @doc """
  Start model as a GenServer for stateful reasoning sessions.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, "Model")
    GenServer.start_link(__MODULE__, %{name: name}, name: via_tuple(name))
  end

  defp via_tuple(name) do
    {:via, Registry, {CursorDocs.AI.LNN.Registry, name}}
  end

  @doc """
  Add knowledge (formulae) to the model.

  Formulae are added as root nodes. All subformulae are automatically
  included in the model's scope.
  """
  @spec add_knowledge(t(), Formula.t() | [Formula.t()]) :: {:ok, t()}
  def add_knowledge(model, formulae) when is_list(formulae) do
    Enum.reduce(formulae, {:ok, model}, fn formula, {:ok, m} ->
      add_knowledge(m, formula)
    end)
  end

  def add_knowledge(model, formula) do
    # Assign ID if not set
    formula = if formula.id, do: formula, else: %{formula | id: model.num_formulae}

    # Get all formulae (this formula + subformulae)
    all_formulae = collect_formulae(formula, model.num_formulae)

    # Add all to graph and nodes
    {graph, nodes, node_names, num} = Enum.reduce(all_formulae, {model.graph, model.nodes, model.node_names, model.num_formulae}, fn f, {g, n, nn, next_id} ->
      f_with_id = if f.id, do: f, else: %{f | id: next_id}

      g2 = %{g | nodes: MapSet.put(g.nodes, f_with_id.id)}
      n2 = Map.put(n, f_with_id.id, f_with_id)
      nn2 = Map.update(nn, f_with_id.name, [f_with_id], &[f_with_id | &1])

      {g2, n2, nn2, next_id + 1}
    end)

    # Add edges for dependencies
    graph = add_edges_for_formula(graph, formula, nodes)

    updated = %{model |
      graph: graph,
      nodes: nodes,
      node_names: node_names,
      num_formulae: num
    }

    Logger.debug("Added formula '#{formula.name}' to model '#{model.name}'")
    {:ok, updated}
  end

  # Collect formula and all subformulae recursively
  defp collect_formulae(formula, start_id) do
    operands = get_operands(formula)

    sub = operands
    |> Enum.with_index(start_id + 1)
    |> Enum.flat_map(fn {op, idx} ->
      collect_formulae(%{op | id: idx}, idx)
    end)

    [formula | sub]
  end

  defp get_operands(formula) do
    cond do
      Map.has_key?(formula, :operands) -> formula.operands
      Map.has_key?(formula, :operand) -> [formula.operand]
      Map.has_key?(formula, :antecedent) -> [formula.antecedent, formula.consequent]
      Map.has_key?(formula, :left) -> [formula.left, formula.right]
      true -> []
    end
  end

  defp add_edges_for_formula(graph, formula, nodes) do
    operands = get_operands(formula)

    Enum.reduce(operands, graph, fn op, g ->
      # Find the op in nodes (it might have a different id)
      op_node = Enum.find(Map.values(nodes), fn n -> n.name == op.name end)
      if op_node do
        Graph.add_edge(g, formula.id, op_node.id)
      else
        g
      end
    end)
  end

  @doc """
  Add data (facts) to predicates in the model.

  ## Data formats

  For propositional formulae:
      Model.add_data(model, prop, Fact.true())

  For first-order predicates:
      Model.add_data(model, predicate, %{
        "entity1" => Fact.true(),
        "entity2" => {0.3, 0.7}  # belief bounds
      })
  """
  @spec add_data(t(), Formula.t(), map() | Fact.t()) :: {:ok, t()}
  def add_data(model, formula, data) do
    case Map.get(model.nodes, formula.id) do
      nil ->
        {:error, :formula_not_in_model}

      node ->
        updated_node = Formula.add_data(node, data)
        nodes = Map.put(model.nodes, formula.id, updated_node)
        {:ok, %{model | nodes: nodes}}
    end
  end

  @doc """
  Set a query formula for theorem proving / QA.
  """
  @spec set_query(t(), Formula.t()) :: {:ok, t()}
  def set_query(model, formula) do
    {:ok, model} = add_knowledge(model, formula)
    {:ok, %{model | query: formula}}
  end

  @doc """
  Perform inference over the model.

  ## Options

  - `:direction` - `:upward`, `:downward`, or `:both` (default)
  - `:source` - Starting node for inference
  - `:max_steps` - Maximum reasoning steps
  """
  @spec infer(t(), keyword()) :: {:ok, t(), map()}
  def infer(model, opts \\ []) do
    direction = Keyword.get(opts, :direction, :both)
    max_steps = Keyword.get(opts, :max_steps, 100)

    {model, stats} = do_inference(model, direction, max_steps, 0, %{
      steps: 0,
      bounds_updated: 0
    })

    Logger.info("Inference converged in #{stats.steps} steps, #{stats.bounds_updated} bounds updated")
    {:ok, model, stats}
  end

  @doc """
  Perform upward inference (leaf to root).
  """
  @spec upward(t()) :: {:ok, t(), map()}
  def upward(model), do: infer(model, direction: :upward)

  @doc """
  Perform downward inference (root to leaf).
  """
  @spec downward(t()) :: {:ok, t(), map()}
  def downward(model), do: infer(model, direction: :downward)

  @doc """
  Print model state for debugging.
  """
  @spec print(t()) :: :ok
  def print(model) do
    IO.puts("\n" <> String.duplicate("*", 50))
    IO.puts("LNN Model: #{model.name}")
    IO.puts("Formulae: #{model.num_formulae}")
    IO.puts(String.duplicate("-", 50))

    Enum.each(model.nodes, fn {id, node} ->
      IO.puts("  [#{id}] #{Formula.to_string(node)} = #{inspect(node.bounds)}")
    end)

    IO.puts(String.duplicate("*", 50))
    :ok
  end

  # ============================================================================
  # Inference Implementation
  # ============================================================================

  defp do_inference(model, _direction, max_steps, step, stats) when step >= max_steps do
    {model, stats}
  end

  defp do_inference(model, direction, max_steps, step, stats) do
    Logger.debug("Reasoning step #{step}")

    # Get traversal order based on direction
    order = case direction do
      :upward -> Graph.postorder(model.graph)
      :downward -> Graph.reverse_postorder(model.graph)
      :both -> Graph.postorder(model.graph) ++ Graph.reverse_postorder(model.graph)
    end

    # Execute inference at each node
    {updated_model, updates} = Enum.reduce(order, {model, 0}, fn node_id, {m, upd} ->
      case Map.get(m.nodes, node_id) do
        nil -> {m, upd}
        node ->
          {new_node, changed} = Formula.infer(node, m, direction)
          new_nodes = Map.put(m.nodes, node_id, new_node)
          {%{m | nodes: new_nodes}, upd + if(changed, do: 1, else: 0)}
      end
    end)

    # Apply modus ponens for implications (downward inference)
    updated_model = if direction in [:downward, :both] do
      apply_modus_ponens(updated_model)
    else
      updated_model
    end

    new_stats = %{stats |
      steps: step + 1,
      bounds_updated: stats.bounds_updated + updates
    }

    # Check convergence
    if updates == 0 do
      {updated_model, new_stats}
    else
      do_inference(updated_model, direction, max_steps, step + 1, new_stats)
    end
  end

  # Apply modus ponens to all implications in the model
  defp apply_modus_ponens(model) do
    alias CursorDocs.AI.LNN.Connectives.Implies

    Enum.reduce(model.nodes, model, fn {_id, node}, m ->
      case node do
        %Implies{} = impl ->
          case Implies.modus_ponens(impl, m) do
            {:ok, new_bounds, consequent} ->
              # Update the consequent with tightened bounds
              updated_cons = %{consequent | bounds: Formula.meet_bounds(consequent.bounds, new_bounds)}
              new_nodes = Map.put(m.nodes, consequent.id, updated_cons)
              Logger.debug("Modus ponens: #{consequent.name} -> #{inspect(new_bounds)}")
              %{m | nodes: new_nodes}

            :no_inference ->
              m
          end

        _ ->
          m
      end
    end)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(%{name: name}) do
    {:ok, model} = new(name)
    {:ok, model}
  end

  @impl true
  def handle_call({:add_knowledge, formula}, _from, model) do
    case add_knowledge(model, formula) do
      {:ok, new_model} -> {:reply, :ok, new_model}
      error -> {:reply, error, model}
    end
  end

  @impl true
  def handle_call({:add_data, formula, data}, _from, model) do
    case add_data(model, formula, data) do
      {:ok, new_model} -> {:reply, :ok, new_model}
      error -> {:reply, error, model}
    end
  end

  @impl true
  def handle_call(:infer, _from, model) do
    case infer(model) do
      {:ok, new_model, stats} -> {:reply, {:ok, stats}, new_model}
      error -> {:reply, error, model}
    end
  end

  @impl true
  def handle_call(:get_state, _from, model) do
    {:reply, model, model}
  end
end

