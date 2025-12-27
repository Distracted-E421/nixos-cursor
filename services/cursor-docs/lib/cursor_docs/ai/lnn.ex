# lib/cursor_docs/ai/lnn.ex
defmodule CursorDocs.AI.LNN do
  @moduledoc """
  Elixir port of IBM's Logical Neural Networks (LNN).

  ## Overview

  LNNs provide a neuro-symbolic framework combining:
  - Neural networks (learning from data)
  - Symbolic logic (knowledge representation and reasoning)

  Every neuron has a logical meaning, enabling:
  - Interpretable AI decisions
  - Omnidirectional inference (not just forward pass)
  - Learning with incomplete/inconsistent data
  - Open-world assumption

  ## Quick Start

      alias CursorDocs.AI.LNN
      alias CursorDocs.AI.LNN.Connectives.{Proposition, Predicate, And, Or, Not, Implies}
      alias CursorDocs.AI.LNN.Formula.Fact

      # Create propositions
      raining = Proposition.new("Raining")
      wet = Proposition.new("Wet")

      # Create rule: Raining -> Wet
      rule = Implies.new(raining, wet)

      # Create model
      {:ok, model} = LNN.Model.new("Weather")
      {:ok, model} = LNN.Model.add_knowledge(model, rule)

      # Add data
      {:ok, model} = LNN.Model.add_data(model, raining, Fact.true_val())

      # Reason
      {:ok, model, _} = LNN.Model.infer(model)

      # Check wet status
      wet_bounds = model.nodes[wet.id].bounds
      # => {1.0, 1.0} (TRUE inferred via modus ponens)

  ## Architecture

  ```
  CursorDocs.AI.LNN
  ├── Model          # Container for formulae, inference, learning
  ├── Formula        # Base module with bound operations
  ├── Graph          # DAG for formula dependencies
  ├── Connectives
  │   ├── Proposition
  │   ├── Predicate
  │   ├── Not
  │   ├── And
  │   ├── Or
  │   ├── Implies
  │   └── Iff
  └── Python         # Optional Python interop for training
  ```

  ## Integration with cursor-docs

  The LNN module integrates with the neuro-symbolic search:

  1. **Query Parsing**: Natural language -> logical formula
  2. **Knowledge Base**: Documentation as predicates and rules
  3. **Reasoning**: LNN inference to find relevant docs
  4. **Explanation**: Trace inference path for explainability

  ## References

  - IBM LNN: https://github.com/IBM/LNN
  - Paper: "Logical Neural Networks" (Riegel et al., 2020)
  """

  alias CursorDocs.AI.LNN.{Model, Formula}
  alias CursorDocs.AI.LNN.Connectives.{Proposition, Predicate, And, Implies}

  # Re-export commonly used modules
  defdelegate new_model(name \\ "Model"), to: Model, as: :new
  defdelegate new_proposition(name, opts \\ []), to: Proposition, as: :new
  defdelegate new_predicate(name, arity \\ 1, opts \\ []), to: Predicate, as: :new

  @doc """
  Create a simple knowledge base from rules.

  ## Example

      rules = [
        {"Smokes", :implies, "HasLungRisk"},
        {"HasAsthma", :and, "Smokes", :implies, "HighRisk"}
      ]

      {:ok, model} = LNN.from_rules("HealthRisk", rules)
  """
  def from_rules(name, rules) do
    {:ok, model} = Model.new(name)

    {model, props} = Enum.reduce(rules, {model, %{}}, fn rule, {m, ps} ->
      case rule do
        {a, :implies, b} ->
          prop_a = Map.get_lazy(ps, a, fn -> Proposition.new(a) end)
          prop_b = Map.get_lazy(ps, b, fn -> Proposition.new(b) end)
          formula = Implies.new(prop_a, prop_b)
          {:ok, m2} = Model.add_knowledge(m, formula)
          {m2, ps |> Map.put(a, prop_a) |> Map.put(b, prop_b)}

        {a, :and, b, :implies, c} ->
          prop_a = Map.get_lazy(ps, a, fn -> Proposition.new(a) end)
          prop_b = Map.get_lazy(ps, b, fn -> Proposition.new(b) end)
          prop_c = Map.get_lazy(ps, c, fn -> Proposition.new(c) end)
          and_node = And.new(prop_a, prop_b)
          formula = Implies.new(and_node, prop_c)
          {:ok, m2} = Model.add_knowledge(m, formula)
          {m2, ps |> Map.put(a, prop_a) |> Map.put(b, prop_b) |> Map.put(c, prop_c)}

        _ ->
          {m, ps}
      end
    end)

    {:ok, model, props}
  end

  @doc """
  Quick inference on a model with given facts.

  ## Example

      facts = %{"Raining" => :true}
      {:ok, result} = LNN.quick_infer(model, props, facts)
      result["Wet"]  # => :true
  """
  def quick_infer(model, props, facts) do
    # Add facts
    model = Enum.reduce(facts, model, fn {name, value}, m ->
      case Map.get(props, name) do
        nil -> m
        prop ->
          bounds = case value do
            :true -> Formula.Fact.true_val()
            :false -> Formula.Fact.false_val()
            _ -> Formula.Fact.unknown()
          end
          {:ok, m2} = Model.add_data(m, prop, bounds)
          m2
      end
    end)

    # Infer
    {:ok, model, _stats} = Model.infer(model)

    # Extract results
    results = Enum.map(props, fn {name, prop} ->
      node = Map.get(model.nodes, prop.id, prop)
      {name, Formula.Fact.to_bool(node.bounds)}
    end)
    |> Map.new()

    {:ok, results}
  end

  @doc """
  Create a documentation knowledge base for neuro-symbolic search.

  This converts documentation metadata into LNN predicates:
  - HasTag(doc, tag)
  - HasKeyword(doc, keyword)
  - DependsOn(doc1, doc2)
  - RelevantTo(query, doc)
  """
  def create_doc_kb(docs) when is_list(docs) do
    {:ok, model} = Model.new("DocKB")

    # Create predicates
    has_tag = Predicate.new("HasTag", 2)
    has_keyword = Predicate.new("HasKeyword", 2)
    depends_on = Predicate.new("DependsOn", 2)
    relevant_to = Predicate.new("RelevantTo", 2)

    # Add predicates to model
    {:ok, model} = Model.add_knowledge(model, [has_tag, has_keyword, depends_on, relevant_to])

    # Add groundings for each doc
    model = Enum.reduce(docs, model, fn doc, m ->
      doc_id = doc[:id] || doc[:path]

      # Add tag groundings
      m = Enum.reduce(doc[:tags] || [], m, fn tag, m2 ->
        {:ok, m3} = Model.add_data(m2, has_tag, %{{doc_id, tag} => :true})
        m3
      end)

      # Add keyword groundings
      Enum.reduce(doc[:keywords] || [], m, fn kw, m2 ->
        {:ok, m3} = Model.add_data(m2, has_keyword, %{{doc_id, kw} => :true})
        m3
      end)
    end)

    {:ok, model, %{
      has_tag: has_tag,
      has_keyword: has_keyword,
      depends_on: depends_on,
      relevant_to: relevant_to
    }}
  end
end

