# lib/cursor_docs/ai/lnn/formula.ex
defmodule CursorDocs.AI.LNN.Formula do
  @moduledoc """
  Base module for LNN formulae (propositions, predicates, connectives).

  Every formula in an LNN has:
  - Truth bounds [L, U] where 0 <= L <= U <= 1
  - Parameters (weights, biases) for learning
  - Inference rules for upward/downward propagation
  """

  @type bounds :: {float(), float()}
  @type fact :: :true | :false | :unknown | bounds()

  @type t :: %{
          __struct__: atom(),
          id: non_neg_integer() | nil,
          name: String.t(),
          bounds: bounds(),
          world: :open | :closed,
          propositional: boolean(),
          groundings: map()
        }

  @callback infer(t(), map(), :upward | :downward) :: {t(), boolean()}
  @callback add_data(t(), map() | fact()) :: t()
  @callback to_string(t()) :: String.t()

  @doc """
  Classical facts as belief bounds.
  """
  defmodule Fact do
    @moduledoc "Classical truth values for LNN"

    def true_val, do: {1.0, 1.0}
    def false_val, do: {0.0, 0.0}
    def unknown, do: {0.0, 1.0}

    def from_bool(true), do: true_val()
    def from_bool(false), do: false_val()

    def to_bool({l, u}) when l >= 0.5 and u >= 0.5, do: true
    def to_bool({l, u}) when l < 0.5 and u < 0.5, do: false
    def to_bool(_), do: :unknown

    @doc "Check if bounds represent classical TRUE"
    def is_true?({l, _u}), do: l >= 0.5

    @doc "Check if bounds represent classical FALSE"
    def is_false?({_l, u}), do: u < 0.5

    @doc "Check if bounds are in contradiction (L > U)"
    def contradiction?({l, u}), do: l > u
  end

  @doc """
  Combine bounds (meet operation).
  """
  def meet_bounds({l1, u1}, {l2, u2}) do
    {max(l1, l2), min(u1, u2)}
  end

  @doc """
  Join bounds (union operation).
  """
  def join_bounds({l1, u1}, {l2, u2}) do
    {min(l1, l2), max(u1, u2)}
  end

  @doc """
  Negate bounds.
  """
  def negate_bounds({l, u}) do
    {1.0 - u, 1.0 - l}
  end

  @doc """
  And bounds (Lukasiewicz t-norm).
  """
  def and_bounds(bounds_list) do
    Enum.reduce(bounds_list, {1.0, 1.0}, fn {l, u}, {acc_l, acc_u} ->
      # Lukasiewicz: max(0, L1 + L2 - 1), min(U1, U2)
      {max(0.0, acc_l + l - 1.0), min(acc_u, u)}
    end)
  end

  @doc """
  Or bounds (Lukasiewicz t-conorm).
  """
  def or_bounds(bounds_list) do
    Enum.reduce(bounds_list, {0.0, 0.0}, fn {l, u}, {acc_l, acc_u} ->
      # Lukasiewicz: min(1, L1 + L2), max(U1, U2)
      {min(1.0, acc_l + l), max(acc_u, u)}
    end)
  end

  @doc """
  Implication bounds (A -> B = ~A | B).
  """
  def implies_bounds({l_a, u_a}, {l_b, u_b}) do
    # ~A | B
    {neg_l, neg_u} = negate_bounds({l_a, u_a})
    or_bounds([{neg_l, neg_u}, {l_b, u_b}])
  end

  @doc """
  Generic formula to string.
  """
  def to_string(formula) do
    formula.name
  end

  @doc """
  Add data to a formula. Dispatches to specific implementation.
  """
  def add_data(formula, data) do
    module = formula.__struct__
    if function_exported?(module, :add_data, 2) do
      module.add_data(formula, data)
    else
      formula
    end
  end

  @doc """
  Infer bounds for a formula. Dispatches to specific implementation.
  """
  def infer(formula, model, direction) do
    module = formula.__struct__
    if function_exported?(module, :infer, 3) do
      module.infer(formula, model, direction)
    else
      {formula, false}
    end
  end
end

