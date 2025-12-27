defmodule CursorDocs.AI.Neurosymbolic.Explainer do
  @moduledoc """
  Natural language explanation generator for neuro-symbolic reasoning.

  Takes inference results and generates human-readable explanations
  with varying levels of detail.

  ## Explanation Levels

  - `:brief` - One-sentence summary
  - `:standard` - Key points with reasoning steps
  - `:detailed` - Full proof trace with confidence analysis

  ## Output Format

  The explainer produces structured explanations:

      %{
        summary: "Brief one-line answer",
        reasoning: "Multi-paragraph explanation",
        confidence: 0.95,
        caveats: ["List of limitations or assumptions"],
        sources: ["References to knowledge base entries"]
      }

  """

  require Logger

  @explanation_prompt """
  You are an explanation generator for a neuro-symbolic AI system.

  Given the reasoning results, generate a clear, human-readable explanation.

  ## Reasoning Input
  - Original query: {query}
  - Conclusions: {conclusions}
  - Proof steps: {proof_steps}
  - Overall confidence: {confidence}

  ## Task
  Generate an explanation that:
  1. Directly answers the original query
  2. Shows the key reasoning steps
  3. Acknowledges uncertainty where appropriate
  4. Is easy for a non-expert to understand

  ## Respond in JSON:
  ```json
  {
    "summary": "One-sentence direct answer",
    "reasoning": "Detailed explanation of how we arrived at this conclusion...",
    "confidence_statement": "How confident we are and why",
    "caveats": ["Any limitations or assumptions"]
  }
  ```

  JSON response:
  """

  @doc """
  Generate explanation from reasoning results.

  ## Options

    * `:level` - Detail level: `:brief`, `:standard`, or `:detailed` (default: :standard)
    * `:include_proof` - Include formal proof steps (default: false)
    * `:model` - LLM model for generation

  """
  @spec explain(map(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def explain(parsed, grounded, inference, opts \\ []) do
    level = Keyword.get(opts, :level, :standard)

    Logger.debug("[Explainer] Generating #{level} explanation")

    case level do
      :brief -> explain_brief(parsed, inference)
      :standard -> explain_standard(parsed, grounded, inference, opts)
      :detailed -> explain_detailed(parsed, grounded, inference, opts)
    end
  end

  @doc """
  Generate explanation without LLM - uses templates.
  """
  @spec explain_fast(map(), map(), map()) :: {:ok, map()}
  def explain_fast(parsed, _grounded, inference) do
    summary = generate_template_summary(parsed, inference)
    reasoning = generate_template_reasoning(inference)

    {:ok, %{
      summary: summary,
      reasoning: reasoning,
      confidence: inference.confidence,
      caveats: generate_caveats(inference),
      sources: [],
      level: :template
    }}
  end

  # ============================================================================
  # Brief Explanation
  # ============================================================================

  defp explain_brief(parsed, inference) do
    summary = cond do
      inference.conclusions == [] ->
        "Unable to determine an answer based on available information."

      inference.confidence >= 0.9 ->
        conclusion = hd(inference.conclusions)
        "Yes, #{conclusion.statement} (high confidence: #{round(inference.confidence * 100)}%)."

      inference.confidence >= 0.7 ->
        conclusion = hd(inference.conclusions)
        "Likely #{conclusion.statement} (confidence: #{round(inference.confidence * 100)}%)."

      inference.confidence >= 0.5 ->
        conclusion = hd(inference.conclusions)
        "Possibly #{conclusion.statement} (uncertain: #{round(inference.confidence * 100)}%)."

      true ->
        "Uncertain. The evidence is inconclusive."
    end

    {:ok, %{
      summary: summary,
      reasoning: nil,
      confidence: inference.confidence,
      caveats: [],
      sources: [],
      level: :brief
    }}
  end

  # ============================================================================
  # Standard Explanation
  # ============================================================================

  defp explain_standard(parsed, _grounded, inference, opts) do
    model = Keyword.get(opts, :model, "qwen2.5:7b")
    endpoint = Keyword.get(opts, :endpoint, "http://localhost:11434")

    prompt = @explanation_prompt
      |> String.replace("{query}", parsed.raw_query)
      |> String.replace("{conclusions}", Jason.encode!(inference.conclusions))
      |> String.replace("{proof_steps}", Jason.encode!(inference.proof_steps))
      |> String.replace("{confidence}", to_string(inference.confidence))

    case call_llm(endpoint, model, prompt) do
      {:ok, response} ->
        case extract_json(response) do
          {:ok, explanation} ->
            {:ok, normalize_explanation(explanation, inference, :standard)}

          {:error, _} ->
            # Fallback to template
            explain_fast(parsed, nil, inference)
        end

      {:error, reason} ->
        Logger.warning("[Explainer] LLM failed, using template: #{inspect(reason)}")
        explain_fast(parsed, nil, inference)
    end
  end

  # ============================================================================
  # Detailed Explanation
  # ============================================================================

  defp explain_detailed(parsed, grounded, inference, opts) do
    # Get standard explanation first
    {:ok, standard} = explain_standard(parsed, grounded, inference, opts)

    # Add detailed components
    detailed = Map.merge(standard, %{
      grounding_details: format_grounding(grounded),
      proof_trace: format_proof(inference.proof_steps),
      confidence_breakdown: format_confidence(inference),
      level: :detailed
    })

    {:ok, detailed}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp call_llm(endpoint, model, prompt) do
    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.3,
        num_predict: 800
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

  defp normalize_explanation(exp, inference, level) do
    %{
      summary: exp["summary"] || "No summary available.",
      reasoning: exp["reasoning"] || "No detailed reasoning available.",
      confidence: inference.confidence,
      confidence_statement: exp["confidence_statement"],
      caveats: exp["caveats"] || [],
      sources: [],
      level: level
    }
  end

  defp generate_template_summary(parsed, inference) do
    intent = parsed.intent

    case {intent, inference.confidence} do
      {:query, c} when c >= 0.8 ->
        conclusion = hd(inference.conclusions || [%{statement: "unknown"}])
        "Based on analysis: #{conclusion.statement}"

      {:query, c} when c >= 0.5 ->
        "The analysis suggests a possible answer, but with limited confidence (#{round(c * 100)}%)."

      {:query, _} ->
        "Unable to provide a definitive answer based on available information."

      {:command, _} ->
        "Command acknowledged. #{length(inference.conclusions)} actions identified."

      {:assertion, c} when c >= 0.7 ->
        "The assertion appears to be supported by the evidence."

      {:assertion, _} ->
        "The assertion could not be fully verified."
    end
  end

  defp generate_template_reasoning(inference) do
    steps = inference.proof_steps
      |> Enum.map(fn step ->
        "#{step.step}. [#{step.type}] #{step.statement}"
      end)
      |> Enum.join("\n")

    conclusions = inference.conclusions
      |> Enum.map(fn c ->
        "• #{c.statement} (confidence: #{round(c.confidence * 100)}%)"
      end)
      |> Enum.join("\n")

    """
    ## Reasoning Steps
    #{steps}

    ## Conclusions
    #{conclusions}

    ## Method
    Reasoning mode: #{inference[:mode] || "unknown"}
    """
  end

  defp generate_caveats(inference) do
    caveats = []

    caveats = if inference.confidence < 0.7 do
      ["Low confidence - results should be verified" | caveats]
    else
      caveats
    end

    caveats = if inference[:mode] == :rule_based do
      ["Based on predefined rules only" | caveats]
    else
      caveats
    end

    caveats = if length(inference.conclusions) == 0 do
      ["No conclusions could be drawn" | caveats]
    else
      caveats
    end

    caveats
  end

  defp format_grounding(grounded) do
    entities = grounded.entities
      |> Enum.map(fn {text, info} ->
        "• '#{text}' → #{info.id} (#{info.type}, conf: #{round(info.confidence * 100)}%)"
      end)
      |> Enum.join("\n")

    predicates = grounded.predicates
      |> Enum.map(fn {text, info} ->
        "• '#{text}' → #{info.id} (#{info.type}, arity: #{info.arity})"
      end)
      |> Enum.join("\n")

    """
    ### Entity Grounding
    #{entities}

    ### Predicate Grounding
    #{predicates}

    ### Ungrounded Terms
    #{Enum.join(grounded.ungrounded, ", ")}
    """
  end

  defp format_proof(proof_steps) do
    proof_steps
    |> Enum.map(fn step ->
      "#{step.step}. [#{String.upcase(to_string(step.type))}] #{step.statement}"
    end)
    |> Enum.join("\n")
  end

  defp format_confidence(inference) do
    conclusions = inference.conclusions

    if conclusions == [] do
      "No conclusions to analyze."
    else
      avg_conf = inference.confidence
      min_conf = conclusions |> Enum.map(& &1.confidence) |> Enum.min(fn -> 0 end)
      max_conf = conclusions |> Enum.map(& &1.confidence) |> Enum.max(fn -> 0 end)

      """
      • Average confidence: #{round(avg_conf * 100)}%
      • Range: #{round(min_conf * 100)}% - #{round(max_conf * 100)}%
      • Number of conclusions: #{length(conclusions)}
      """
    end
  end
end
