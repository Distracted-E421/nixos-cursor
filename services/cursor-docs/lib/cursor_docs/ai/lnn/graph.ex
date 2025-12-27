# lib/cursor_docs/ai/lnn/graph.ex
defmodule CursorDocs.AI.LNN.Graph do
  @moduledoc """
  Directed graph for LNN formula dependencies.

  Edges point from operators (parents) to operands (children).
  This enables efficient traversal for upward/downward inference.
  """

  @type t :: %__MODULE__{
          nodes: MapSet.t(non_neg_integer()),
          edges: %{non_neg_integer() => [non_neg_integer()]},
          reverse_edges: %{non_neg_integer() => [non_neg_integer()]}
        }

  defstruct nodes: MapSet.new(),
            edges: %{},
            reverse_edges: %{}

  @doc """
  Create a new empty graph.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Add a formula and all its subformulae to the graph.
  Returns {updated_graph, next_formula_number}.
  """
  @spec add_formula(t(), map(), non_neg_integer()) :: {t(), non_neg_integer()}
  def add_formula(graph, formula, formula_num) do
    # Assign ID if not set
    formula_with_id = if formula.id, do: formula, else: %{formula | id: formula_num}
    new_num = formula_num + 1

    # Add node
    graph = %{graph | nodes: MapSet.put(graph.nodes, formula_with_id.id)}

    # Add edges from formula to operands
    operands = get_operands(formula_with_id)

    {graph, new_num} = Enum.reduce(operands, {graph, new_num}, fn op, {g, n} ->
      # Recursively add operand
      {g2, n2} = add_formula(g, op, n)

      # Add edge from formula to operand
      g3 = add_edge(g2, formula_with_id.id, op.id || n)

      {g3, n2}
    end)

    {graph, new_num}
  end

  @doc """
  Add an edge from parent to child.
  """
  @spec add_edge(t(), non_neg_integer(), non_neg_integer()) :: t()
  def add_edge(graph, from, to) do
    edges = Map.update(graph.edges, from, [to], &[to | &1])
    reverse_edges = Map.update(graph.reverse_edges, to, [from], &[from | &1])

    %{graph |
      edges: edges,
      reverse_edges: reverse_edges
    }
  end

  @doc """
  Get children (operands) of a node.
  """
  @spec children(t(), non_neg_integer()) :: [non_neg_integer()]
  def children(graph, node_id) do
    Map.get(graph.edges, node_id, [])
  end

  @doc """
  Get parents (formulas using this as operand) of a node.
  """
  @spec parents(t(), non_neg_integer()) :: [non_neg_integer()]
  def parents(graph, node_id) do
    Map.get(graph.reverse_edges, node_id, [])
  end

  @doc """
  Get root nodes (nodes with no parents).
  """
  @spec roots(t()) :: [non_neg_integer()]
  def roots(graph) do
    graph.nodes
    |> MapSet.to_list()
    |> Enum.filter(fn id -> parents(graph, id) == [] end)
  end

  @doc """
  Get leaf nodes (nodes with no children).
  """
  @spec leaves(t()) :: [non_neg_integer()]
  def leaves(graph) do
    graph.nodes
    |> MapSet.to_list()
    |> Enum.filter(fn id -> children(graph, id) == [] end)
  end

  @doc """
  Depth-first postorder traversal (leaves first, then parents).
  Used for upward inference.
  """
  @spec postorder(t()) :: [non_neg_integer()]
  def postorder(graph) do
    visited = MapSet.new()

    roots(graph)
    |> Enum.reduce({[], visited}, fn root, {order, vis} ->
      dfs_postorder(graph, root, vis, order)
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp dfs_postorder(graph, node, visited, order) do
    if MapSet.member?(visited, node) do
      {order, visited}
    else
      visited = MapSet.put(visited, node)

      {order, visited} = children(graph, node)
      |> Enum.reduce({order, visited}, fn child, {ord, vis} ->
        dfs_postorder(graph, child, vis, ord)
      end)

      {[node | order], visited}
    end
  end

  @doc """
  Reverse postorder (roots first, then children).
  Used for downward inference.
  """
  @spec reverse_postorder(t()) :: [non_neg_integer()]
  def reverse_postorder(graph) do
    postorder(graph) |> Enum.reverse()
  end

  @doc """
  Get number of nodes in graph.
  """
  @spec size(t()) :: non_neg_integer()
  def size(graph) do
    MapSet.size(graph.nodes)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp get_operands(formula) do
    cond do
      Map.has_key?(formula, :operands) -> formula.operands
      Map.has_key?(formula, :operand) -> [formula.operand]
      Map.has_key?(formula, :antecedent) -> [formula.antecedent, formula.consequent]
      Map.has_key?(formula, :left) -> [formula.left, formula.right]
      true -> []
    end
  end
end

