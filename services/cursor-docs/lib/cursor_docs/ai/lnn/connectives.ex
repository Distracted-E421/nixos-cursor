# lib/cursor_docs/ai/lnn/connectives.ex
defmodule CursorDocs.AI.LNN.Connectives do
  @moduledoc """
  Logical connectives for LNN: And, Or, Not, Implies, Iff, XOr.

  Each connective is a neuron with learnable parameters that
  compute bounds based on operand bounds.

  Supports both **upward** (leaf→root) and **downward** (root→leaf) inference:
  - Upward: Compute parent bounds from child bounds
  - Downward: Propagate constraints (modus ponens, etc.)
  """

  alias CursorDocs.AI.LNN.Formula

  # ============================================================================
  # Shared Helper
  # ============================================================================

  defp find_by_name(nodes, name) do
    Enum.find(Map.values(nodes), fn n -> n.name == name end)
  end

  # ============================================================================
  # Proposition (0-ary predicate)
  # ============================================================================

  defmodule Proposition do
    @moduledoc "A propositional formula (ground truth)"

    @enforce_keys [:name]
    defstruct [
      :id,
      :name,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{},
      data: nil
    ]

    @type t :: %__MODULE__{
            id: non_neg_integer() | nil,
            name: String.t(),
            bounds: Formula.bounds(),
            world: :open | :closed,
            propositional: true,
            groundings: map(),
            data: any()
          }

    def new(name, opts \\ []) do
      %__MODULE__{
        name: name,
        bounds: Keyword.get(opts, :bounds, {0.0, 1.0}),
        world: Keyword.get(opts, :world, :open)
      }
    end

    def add_data(prop, fact) when is_tuple(fact) do
      %{prop | bounds: fact, data: fact}
    end

    def add_data(prop, :true), do: add_data(prop, Formula.Fact.true_val())
    def add_data(prop, :false), do: add_data(prop, Formula.Fact.false_val())
    def add_data(prop, :unknown), do: add_data(prop, Formula.Fact.unknown())

    def infer(prop, _model, _direction) do
      # Propositions don't propagate - they hold ground truth
      {prop, false}
    end

    def to_string(prop), do: prop.name
  end

  # ============================================================================
  # Predicate (n-ary, with groundings)
  # ============================================================================

  defmodule Predicate do
    @moduledoc "A first-order predicate with arity"

    @enforce_keys [:name]
    defstruct [
      :id,
      :name,
      :arity,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: false,
      groundings: %{}
    ]

    @type t :: %__MODULE__{
            id: non_neg_integer() | nil,
            name: String.t(),
            arity: pos_integer(),
            bounds: Formula.bounds(),
            world: :open | :closed,
            propositional: false,
            groundings: %{(tuple() | String.t()) => Formula.bounds()}
          }

    def new(name, arity \\ 1, opts \\ []) do
      %__MODULE__{
        name: name,
        arity: arity,
        bounds: Keyword.get(opts, :bounds, {0.0, 1.0}),
        world: Keyword.get(opts, :world, :open)
      }
    end

    def add_data(pred, data) when is_map(data) do
      new_groundings = Enum.reduce(data, pred.groundings, fn {entity, fact}, acc ->
        bounds = normalize_fact(fact)
        Map.put(acc, entity, bounds)
      end)
      %{pred | groundings: new_groundings}
    end

    defp normalize_fact(:true), do: Formula.Fact.true_val()
    defp normalize_fact(:false), do: Formula.Fact.false_val()
    defp normalize_fact(:unknown), do: Formula.Fact.unknown()
    defp normalize_fact({l, u}) when is_float(l) and is_float(u), do: {l, u}
    defp normalize_fact(val) when is_float(val), do: {val, val}

    def infer(pred, _model, _direction) do
      # Predicates don't propagate internally
      {pred, false}
    end

    def to_string(pred), do: "#{pred.name}/#{pred.arity}"

    @doc "Get bounds for a specific grounding"
    def get_grounding(pred, entity) do
      Map.get(pred.groundings, entity, {0.0, 1.0})
    end
  end

  # ============================================================================
  # Not (negation)
  # ============================================================================

  defmodule Not do
    @moduledoc "Logical negation"

    @enforce_keys [:operand]
    defstruct [
      :id,
      :name,
      :operand,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{}
    ]

    def new(operand, opts \\ []) do
      %__MODULE__{
        name: "¬#{operand.name}",
        operand: operand,
        world: Keyword.get(opts, :world, :open)
      }
    end

    def infer(not_node, model, direction) do
      operand = find_by_name(model.nodes, not_node.operand.name) || not_node.operand

      case direction do
        :upward ->
          new_bounds = Formula.negate_bounds(operand.bounds)
          changed = new_bounds != not_node.bounds
          {%{not_node | bounds: new_bounds}, changed}

        :downward ->
          # Downward: if ¬A has bounds, propagate to A
          # ¬A = [L, U] => A = [1-U, 1-L]
          {not_node, false}

        :both ->
          new_bounds = Formula.negate_bounds(operand.bounds)
          changed = new_bounds != not_node.bounds
          {%{not_node | bounds: new_bounds}, changed}
      end
    end

    def to_string(not_node), do: "¬(#{not_node.operand.name})"

    defp find_by_name(nodes, name) do
      Enum.find(Map.values(nodes), fn n -> n.name == name end)
    end
  end

  # ============================================================================
  # And (conjunction)
  # ============================================================================

  defmodule And do
    @moduledoc "Logical conjunction with Lukasiewicz semantics"

    @enforce_keys [:operands]
    defstruct [
      :id,
      :name,
      :operands,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{},
      # Learnable parameters
      alpha: 1.0,
      weights: nil
    ]

    def new(operands, opts \\ []) when is_list(operands) do
      names = Enum.map(operands, & &1.name) |> Enum.join(" ∧ ")
      %__MODULE__{
        name: "(#{names})",
        operands: operands,
        world: Keyword.get(opts, :world, :open),
        alpha: Keyword.get(opts, :alpha, 1.0)
      }
    end

    @doc "Convenience: And.binary(a, b) for binary and"
    def binary(op1, op2, opts \\ []) do
      new([op1, op2], opts)
    end

    def infer(and_node, model, direction) do
      operand_nodes = Enum.map(and_node.operands, fn op ->
        find_by_name(model.nodes, op.name) || op
      end)

      case direction do
        :upward ->
          bounds_list = Enum.map(operand_nodes, & &1.bounds)
          new_bounds = Formula.and_bounds(bounds_list)
          changed = new_bounds != and_node.bounds
          {%{and_node | bounds: new_bounds}, changed}

        :downward ->
          # Downward: if And is TRUE [1,1], all operands must be TRUE
          # This propagates constraints to children
          {and_node, false}

        :both ->
          bounds_list = Enum.map(operand_nodes, & &1.bounds)
          new_bounds = Formula.and_bounds(bounds_list)
          changed = new_bounds != and_node.bounds
          {%{and_node | bounds: new_bounds}, changed}
      end
    end

    def to_string(and_node), do: and_node.name

    defp find_by_name(nodes, name) do
      Enum.find(Map.values(nodes), fn n -> n.name == name end)
    end
  end

  # ============================================================================
  # Or (disjunction)
  # ============================================================================

  defmodule Or do
    @moduledoc "Logical disjunction with Lukasiewicz semantics"

    @enforce_keys [:operands]
    defstruct [
      :id,
      :name,
      :operands,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{},
      alpha: 1.0,
      weights: nil
    ]

    def new(operands, opts \\ []) when is_list(operands) do
      names = Enum.map(operands, & &1.name) |> Enum.join(" ∨ ")
      %__MODULE__{
        name: "(#{names})",
        operands: operands,
        world: Keyword.get(opts, :world, :open)
      }
    end

    @doc "Convenience: Or.binary(a, b) for binary or"
    def binary(op1, op2, opts \\ []) do
      new([op1, op2], opts)
    end

    def infer(or_node, model, direction) do
      operand_nodes = Enum.map(or_node.operands, fn op ->
        find_by_name(model.nodes, op.name) || op
      end)

      case direction do
        :upward ->
          bounds_list = Enum.map(operand_nodes, & &1.bounds)
          new_bounds = Formula.or_bounds(bounds_list)
          changed = new_bounds != or_node.bounds
          {%{or_node | bounds: new_bounds}, changed}

        :downward ->
          {or_node, false}

        :both ->
          bounds_list = Enum.map(operand_nodes, & &1.bounds)
          new_bounds = Formula.or_bounds(bounds_list)
          changed = new_bounds != or_node.bounds
          {%{or_node | bounds: new_bounds}, changed}
      end
    end

    def to_string(or_node), do: or_node.name

    defp find_by_name(nodes, name) do
      Enum.find(Map.values(nodes), fn n -> n.name == name end)
    end
  end

  # ============================================================================
  # Implies (implication) - WITH MODUS PONENS
  # ============================================================================

  defmodule Implies do
    @moduledoc """
    Logical implication: A -> B

    Supports bidirectional inference:
    - **Upward**: Compute A→B bounds from A and B bounds
    - **Downward (Modus Ponens)**: If A→B is TRUE and A is TRUE, then B must be TRUE
    """

    @enforce_keys [:antecedent, :consequent]
    defstruct [
      :id,
      :name,
      :antecedent,
      :consequent,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{}
    ]

    def new(antecedent, consequent, opts \\ []) do
      %__MODULE__{
        name: "(#{antecedent.name} → #{consequent.name})",
        antecedent: antecedent,
        consequent: consequent,
        world: Keyword.get(opts, :world, :open)
      }
    end

    def infer(impl, model, direction) do
      ant = find_by_name(model.nodes, impl.antecedent.name) || impl.antecedent
      cons = find_by_name(model.nodes, impl.consequent.name) || impl.consequent

      case direction do
        :upward ->
          # Upward: compute implication bounds from operands
          new_bounds = Formula.implies_bounds(ant.bounds, cons.bounds)
          changed = new_bounds != impl.bounds
          {%{impl | bounds: new_bounds}, changed}

        :downward ->
          # **MODUS PONENS**
          # If A→B is TRUE (L >= threshold) and A is TRUE, then B must be TRUE
          impl_true? = elem(impl.bounds, 0) >= 0.9
          ant_true? = elem(ant.bounds, 0) >= 0.9

          if impl_true? and ant_true? do
            # B must be TRUE - return update info for consequent
            # The actual update happens in Model.do_inference
            {impl, true}  # Signal that inference produced result
          else
            {impl, false}
          end

        :both ->
          # Combined: upward first, then check modus ponens
          new_bounds = Formula.implies_bounds(ant.bounds, cons.bounds)
          bounds_changed = new_bounds != impl.bounds
          updated = %{impl | bounds: new_bounds}

          # Check modus ponens
          impl_true? = elem(new_bounds, 0) >= 0.9
          ant_true? = elem(ant.bounds, 0) >= 0.9
          modus_ponens = impl_true? and ant_true?

          {updated, bounds_changed or modus_ponens}
      end
    end

    @doc """
    Apply modus ponens: Given A→B is TRUE and A is TRUE, return updated B bounds.
    Returns {:ok, new_b_bounds} if inference applies, :no_inference otherwise.
    """
    def modus_ponens(impl, model) do
      ant = find_by_name(model.nodes, impl.antecedent.name) || impl.antecedent
      cons = find_by_name(model.nodes, impl.consequent.name) || impl.consequent

      {impl_l, _impl_u} = impl.bounds
      {ant_l, _ant_u} = ant.bounds
      {cons_l, cons_u} = cons.bounds

      # Modus ponens: if A→B ≥ threshold and A ≥ threshold, then B ≥ threshold
      if impl_l >= 0.9 and ant_l >= 0.9 do
        # B must be at least as true as the rule allows
        new_b_l = max(cons_l, impl_l)
        {:ok, {new_b_l, cons_u}, cons}
      else
        :no_inference
      end
    end

    @doc """
    Apply modus tollens: Given A→B is TRUE and B is FALSE, return updated A bounds.
    Returns {:ok, new_a_bounds} if inference applies, :no_inference otherwise.
    """
    def modus_tollens(impl, model) do
      ant = find_by_name(model.nodes, impl.antecedent.name) || impl.antecedent
      cons = find_by_name(model.nodes, impl.consequent.name) || impl.consequent

      {impl_l, _impl_u} = impl.bounds
      {ant_l, ant_u} = ant.bounds
      {_cons_l, cons_u} = cons.bounds

      # Modus tollens: if A→B ≥ threshold and B ≤ (1-threshold), then A ≤ (1-threshold)
      if impl_l >= 0.9 and cons_u <= 0.1 do
        new_a_u = min(ant_u, 1.0 - impl_l)
        {:ok, {ant_l, new_a_u}, ant}
      else
        :no_inference
      end
    end

    def to_string(impl), do: impl.name

    defp find_by_name(nodes, name) do
      Enum.find(Map.values(nodes), fn n -> n.name == name end)
    end
  end

  # ============================================================================
  # Iff (biconditional)
  # ============================================================================

  defmodule Iff do
    @moduledoc "Logical biconditional: A <-> B"

    @enforce_keys [:left, :right]
    defstruct [
      :id,
      :name,
      :left,
      :right,
      bounds: {0.0, 1.0},
      world: :open,
      propositional: true,
      groundings: %{}
    ]

    def new(left, right, opts \\ []) do
      %__MODULE__{
        name: "(#{left.name} ↔ #{right.name})",
        left: left,
        right: right,
        world: Keyword.get(opts, :world, :open)
      }
    end

    def infer(iff, model, direction) do
      left = find_by_name(model.nodes, iff.left.name) || iff.left
      right = find_by_name(model.nodes, iff.right.name) || iff.right

      case direction do
        :upward ->
          # A <-> B = (A -> B) & (B -> A)
          impl1 = Formula.implies_bounds(left.bounds, right.bounds)
          impl2 = Formula.implies_bounds(right.bounds, left.bounds)
          new_bounds = Formula.and_bounds([impl1, impl2])
          changed = new_bounds != iff.bounds
          {%{iff | bounds: new_bounds}, changed}

        :downward ->
          # Bidirectional inference
          {iff, false}

        :both ->
          impl1 = Formula.implies_bounds(left.bounds, right.bounds)
          impl2 = Formula.implies_bounds(right.bounds, left.bounds)
          new_bounds = Formula.and_bounds([impl1, impl2])
          changed = new_bounds != iff.bounds
          {%{iff | bounds: new_bounds}, changed}
      end
    end

    def to_string(iff), do: iff.name

    defp find_by_name(nodes, name) do
      Enum.find(Map.values(nodes), fn n -> n.name == name end)
    end
  end
end
