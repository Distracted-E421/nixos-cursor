defmodule CursorDocs.AI.Neurosymbolic.Reasoner do
  @moduledoc """
  Symbolic reasoning engine for neuro-symbolic AI.

  Performs logical inference over grounded symbols. Currently supports:
  - Simple rule-based reasoning
  - LLM-assisted logical inference
  - (Future) Integration with IBM LNN or Clingo ASP

  ## Architecture

  The reasoner operates in three modes:

  1. **Rule-Based**: Apply predefined rules to grounded facts
  2. **LLM-Guided**: Use LLM to generate and validate logical steps
  3. **Hybrid**: Combine rule-based with LLM for complex reasoning

  ## Output Format

      %{
        conclusions: [
          %{
            statement: "Mortal(socrates)",
            truth_bounds: {0.95, 1.0},
            derivation: [:fact, :rule_1, :modus_ponens]
          }
        ],
        proof_steps: [
          %{step: 1, statement: "Person(socrates)", source: :fact},
          %{step: 2, statement: "Person(x) → Mortal(x)", source: :rule},
          %{step: 3, statement: "Mortal(socrates)", source: :inference}
        ],
        confidence: 0.95
      }

  """

  require Logger

  @reasoning_prompt """
  You are a logical reasoner. Given grounded symbols and facts, perform logical inference.

  ## Input
  - Query intent: {intent}
  - Entities: {entities}
  - Predicates: {predicates}
  - Known facts from knowledge base: {kb_facts}

  ## Task
  1. Identify relevant logical rules
  2. Apply inference (modus ponens, modus tollens, etc.)
  3. Generate conclusions with confidence bounds
  4. Provide step-by-step derivation

  ## Respond in JSON:
  ```json
  {
    "conclusions": [
      {
        "statement": "Conclusion in predicate form",
        "confidence": 0.95,
        "derivation": ["step1", "step2", "inference"]
      }
    ],
    "proof_steps": [
      {"step": 1, "statement": "Fact or rule", "type": "fact|rule|inference"}
    ],
    "overall_confidence": 0.9,
    "reasoning_notes": "Any caveats or limitations"
  }
  ```

  JSON response:
  """

  @doc """
  Perform logical inference over parsed and grounded inputs.

  ## Options

    * `:mode` - Reasoning mode: `:rule_based`, `:llm_guided`, or `:hybrid` (default)
    * `:max_depth` - Maximum inference depth (default: 5)
    * `:timeout` - Reasoning timeout in ms (default: 30000)

  ## Returns

    * `{:ok, inference}` - Successfully inferred
    * `{:yield, :need_facts, context}` - Need additional facts to continue
    * `{:error, reason}` - Reasoning failed

  """
  @spec infer(map(), map(), keyword()) :: {:ok, map()} | {:yield, atom(), map()} | {:error, term()}
  def infer(parsed, grounded, opts \\ []) do
    mode = Keyword.get(opts, :mode, :hybrid)

    Logger.debug("[Reasoner] Starting inference in #{mode} mode")

    case mode do
      :rule_based -> rule_based_inference(parsed, grounded, opts)
      :llm_guided -> llm_guided_inference(parsed, grounded, opts)
      :hybrid -> hybrid_inference(parsed, grounded, opts)
    end
  end

  @doc """
  Quick inference using only rule-based reasoning (no LLM).
  """
  @spec infer_fast(map(), map(), keyword()) :: {:ok, map()}
  def infer_fast(parsed, grounded, opts \\ []) do
    rule_based_inference(parsed, grounded, opts)
  end

  # ============================================================================
  # Rule-Based Reasoning
  # ============================================================================

  defp rule_based_inference(parsed, grounded, _opts) do
    # Simple forward-chaining inference
    facts = extract_facts(grounded)
    rules = get_applicable_rules(parsed, grounded)

    conclusions = apply_rules(facts, rules)

    {:ok, %{
      conclusions: conclusions,
      proof_steps: build_proof_trace(facts, rules, conclusions),
      confidence: calculate_confidence(conclusions),
      mode: :rule_based
    }}
  end

  defp extract_facts(grounded) do
    # Convert grounded entities to facts
    grounded.entities
    |> Enum.flat_map(fn {text, info} ->
      case info.type do
        :instance -> [{:fact, info.id, text}]
        :concept -> [{:type, text, info.id}]
        _ -> []
      end
    end)
  end

  defp get_applicable_rules(_parsed, _grounded) do
    # Built-in rules for common reasoning patterns
    [
      # Type inheritance
      {:rule, :type_inheritance,
        fn facts ->
          for {:type, entity, type} <- facts,
              {:subtype, ^type, supertype} <- get_type_hierarchy(),
              do: {:type, entity, supertype}
        end},

      # Property propagation
      {:rule, :property_propagation,
        fn facts ->
          for {:has_property, entity, prop} <- facts,
              {:property_implies, ^prop, implied} <- get_property_implications(),
              do: {:has_property, entity, implied}
        end}
    ]
  end

  defp get_type_hierarchy do
    # Simple type hierarchy - would come from knowledge graph
    [
      {:subtype, "person", "entity"},
      {:subtype, "function", "code_element"},
      {:subtype, "variable", "code_element"},
      {:subtype, "code_element", "artifact"}
    ]
  end

  defp get_property_implications do
    # Property implications - would come from knowledge graph
    [
      {:property_implies, "deprecated", "should_not_use"},
      {:property_implies, "unsafe", "requires_review"},
      {:property_implies, "experimental", "may_change"}
    ]
  end

  defp apply_rules(facts, rules) do
    # Simple fixed-point iteration
    apply_rules_iter(facts, rules, 5)
  end

  defp apply_rules_iter(facts, _rules, 0), do: facts_to_conclusions(facts)
  defp apply_rules_iter(facts, rules, depth) do
    new_facts = Enum.flat_map(rules, fn {:rule, _name, rule_fn} ->
      try do
        rule_fn.(facts)
      rescue
        _ -> []
      end
    end)

    all_facts = Enum.uniq(facts ++ new_facts)

    if length(all_facts) == length(facts) do
      facts_to_conclusions(all_facts)
    else
      apply_rules_iter(all_facts, rules, depth - 1)
    end
  end

  defp facts_to_conclusions(facts) do
    Enum.map(facts, fn
      {:fact, id, text} ->
        %{statement: "#{id}(#{text})", confidence: 0.9, derivation: [:fact]}

      {:type, entity, type} ->
        %{statement: "type(#{entity}, #{type})", confidence: 0.85, derivation: [:type_inference]}

      {:has_property, entity, prop} ->
        %{statement: "has_property(#{entity}, #{prop})", confidence: 0.8, derivation: [:property_inference]}

      other ->
        %{statement: inspect(other), confidence: 0.5, derivation: [:unknown]}
    end)
  end

  defp build_proof_trace(facts, _rules, _conclusions) do
    facts
    |> Enum.with_index(1)
    |> Enum.map(fn {fact, idx} ->
      %{step: idx, statement: inspect(fact), type: :fact}
    end)
  end

  defp calculate_confidence(conclusions) do
    if conclusions == [] do
      0.0
    else
      conclusions
      |> Enum.map(& &1.confidence)
      |> Enum.sum()
      |> Kernel./(length(conclusions))
    end
  end

  # ============================================================================
  # LLM-Guided Reasoning
  # ============================================================================

  defp llm_guided_inference(parsed, grounded, opts) do
    model = Keyword.get(opts, :model, "qwen2.5:7b")
    endpoint = Keyword.get(opts, :endpoint, "http://localhost:11434")

    # Get relevant facts from knowledge base
    kb_facts = get_kb_facts(grounded)

    prompt = @reasoning_prompt
      |> String.replace("{intent}", inspect(parsed.intent))
      |> String.replace("{entities}", Jason.encode!(grounded.entities))
      |> String.replace("{predicates}", Jason.encode!(grounded.predicates))
      |> String.replace("{kb_facts}", inspect(kb_facts))

    case call_llm(endpoint, model, prompt) do
      {:ok, response} ->
        case extract_json(response) do
          {:ok, inference} ->
            {:ok, normalize_inference(inference)}

          {:error, reason} ->
            Logger.warning("[Reasoner] Failed to parse LLM response: #{inspect(reason)}")
            # Fallback to rule-based
            rule_based_inference(parsed, grounded, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_kb_facts(_grounded) do
    # Would query the knowledge base for relevant facts
    # For now, return empty
    []
  end

  defp call_llm(endpoint, model, prompt) do
    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.2,
        num_predict: 1000
      }
    }

    case Req.post(
      "#{endpoint}/api/generate",
      json: request_body,
      receive_timeout: 30_000
    ) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_json(response) do
    case Regex.run(~r/\{[\s\S]*\}/, response) do
      [json_str] -> Jason.decode(json_str)
      nil -> {:error, :no_json_found}
    end
  end

  defp normalize_inference(inference) do
    %{
      conclusions: normalize_conclusions(inference["conclusions"] || []),
      proof_steps: normalize_proof_steps(inference["proof_steps"] || []),
      confidence: inference["overall_confidence"] || 0.5,
      reasoning_notes: inference["reasoning_notes"],
      mode: :llm_guided
    }
  end

  defp normalize_conclusions(conclusions) when is_list(conclusions) do
    Enum.map(conclusions, fn c ->
      %{
        statement: c["statement"] || "unknown",
        confidence: c["confidence"] || 0.5,
        derivation: c["derivation"] || []
      }
    end)
  end
  defp normalize_conclusions(_), do: []

  defp normalize_proof_steps(steps) when is_list(steps) do
    Enum.map(steps, fn s ->
      %{
        step: s["step"] || 0,
        statement: s["statement"] || "",
        type: String.to_atom(s["type"] || "unknown")
      }
    end)
  end
  defp normalize_proof_steps(_), do: []

  # ============================================================================
  # Hybrid Reasoning
  # ============================================================================

  defp hybrid_inference(parsed, grounded, opts) do
    # First, try rule-based for quick wins
    {:ok, rule_result} = rule_based_inference(parsed, grounded, opts)

    # If rule-based found useful conclusions, check with LLM
    if rule_result.confidence > 0.7 do
      {:ok, rule_result}
    else
      # Fall back to LLM for deeper reasoning
      case llm_guided_inference(parsed, grounded, opts) do
        {:ok, llm_result} ->
          # Merge results, preferring higher confidence
          {:ok, merge_results(rule_result, llm_result)}

        {:error, _} ->
          # Return rule-based result even if low confidence
          {:ok, rule_result}
      end
    end
  end

  defp merge_results(rule_result, llm_result) do
    # Combine conclusions from both, removing duplicates
    all_conclusions = (rule_result.conclusions ++ llm_result.conclusions)
      |> Enum.uniq_by(& &1.statement)
      |> Enum.sort_by(& &1.confidence, :desc)

    %{
      conclusions: all_conclusions,
      proof_steps: llm_result.proof_steps,
      confidence: max(rule_result.confidence, llm_result.confidence),
      reasoning_notes: llm_result.reasoning_notes,
      mode: :hybrid
    }
  end
end
