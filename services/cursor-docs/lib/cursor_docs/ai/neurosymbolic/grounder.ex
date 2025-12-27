defmodule CursorDocs.AI.Neurosymbolic.Grounder do
  @moduledoc """
  Symbol grounder for neuro-symbolic reasoning.

  Maps parsed natural language entities and predicates to grounded symbols
  in a knowledge graph or embedding space.

  ## Grounding Strategies

  1. **Entity Grounding**: Map entity mentions to knowledge graph nodes
  2. **Predicate Grounding**: Map predicates to known relations/properties
  3. **Embedding Grounding**: Use vector similarity for fuzzy matching

  ## Output Format

      %{
        entities: %{
          "function" => %{id: "entity:function_42", confidence: 0.95},
          "bug" => %{id: "concept:software_bug", confidence: 0.88}
        },
        predicates: %{
          "safe" => %{id: "predicate:is_safe", type: :boolean},
          "contains" => %{id: "relation:contains", type: :relation}
        },
        ungrounded: ["unknown_term"]
      }

  """

  require Logger

  alias CursorDocs.Embeddings
  alias CursorDocs.Storage

  @grounding_prompt """
  You are a symbol grounder. Given parsed entities and predicates, map them to formal symbols.

  For each entity, provide:
  - A formal identifier (lowercase, underscored)
  - A type (concept, instance, or unknown)
  - Confidence (0.0 to 1.0)

  For each predicate, provide:
  - A formal identifier
  - The predicate type (property, relation, or action)
  - Arity (how many arguments it takes)

  Parsed Input:
  - Entities: {entities}
  - Predicates: {predicates}
  - Context: {query}

  Respond in JSON:
  ```json
  {
    "entities": {
      "entity_text": {"id": "formal_id", "type": "concept|instance|unknown", "confidence": 0.9}
    },
    "predicates": {
      "predicate_text": {"id": "formal_id", "type": "property|relation|action", "arity": 1}
    },
    "ungrounded": ["items that could not be grounded"]
  }
  ```

  JSON response:
  """

  @doc """
  Ground parsed entities and predicates to formal symbols.

  ## Options

    * `:use_embeddings` - Use embedding similarity for grounding (default: true)
    * `:threshold` - Minimum confidence threshold (default: 0.5)
    * `:knowledge_base` - Override knowledge base for entity lookup

  ## Returns

    * `{:ok, grounded}` - Successfully grounded
    * `{:yield, :need_clarification, context}` - Ambiguous, needs user input
    * `{:error, reason}` - Failed to ground

  """
  @spec ground(map(), keyword()) :: {:ok, map()} | {:yield, atom(), map()} | {:error, term()}
  def ground(parsed, opts \\ []) do
    use_embeddings = Keyword.get(opts, :use_embeddings, true)
    threshold = Keyword.get(opts, :threshold, 0.5)

    Logger.debug("[Grounder] Grounding #{length(parsed.entities)} entities, #{length(parsed.predicates)} predicates")

    # Try LLM-based grounding first
    case llm_ground(parsed, opts) do
      {:ok, grounded} ->
        # Augment with embedding-based matching if enabled
        grounded = if use_embeddings do
          augment_with_embeddings(grounded, parsed, opts)
        else
          grounded
        end

        # Check for ambiguous groundings
        case check_ambiguity(grounded, threshold) do
          :ok ->
            {:ok, grounded}

          {:ambiguous, ambiguous_items} ->
            {:yield, :need_clarification, %{
              ambiguous: ambiguous_items,
              grounded: grounded,
              parsed: parsed
            }}
        end

      {:error, reason} ->
        # Fallback to heuristic grounding
        Logger.warning("[Grounder] LLM grounding failed, using heuristics: #{inspect(reason)}")
        {:ok, heuristic_ground(parsed)}
    end
  end

  @doc """
  Ground without LLM - uses heuristic rules and embeddings only.
  """
  @spec ground_fast(map(), keyword()) :: {:ok, map()}
  def ground_fast(parsed, opts \\ []) do
    grounded = heuristic_ground(parsed)

    if Keyword.get(opts, :use_embeddings, true) do
      {:ok, augment_with_embeddings(grounded, parsed, opts)}
    else
      {:ok, grounded}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp llm_ground(parsed, opts) do
    model = Keyword.get(opts, :model, "qwen2.5:7b")
    endpoint = Keyword.get(opts, :endpoint, "http://localhost:11434")

    prompt = @grounding_prompt
      |> String.replace("{entities}", inspect(parsed.entities))
      |> String.replace("{predicates}", inspect(parsed.predicates))
      |> String.replace("{query}", parsed.raw_query)

    case call_llm(endpoint, model, prompt) do
      {:ok, response} ->
        extract_json(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(endpoint, model, prompt) do
    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.1,
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
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, normalize_grounded(parsed)}
          error -> error
        end

      nil ->
        {:error, :no_json_found}
    end
  end

  defp normalize_grounded(grounded) do
    %{
      entities: normalize_entity_map(grounded["entities"] || %{}),
      predicates: normalize_predicate_map(grounded["predicates"] || %{}),
      ungrounded: grounded["ungrounded"] || []
    }
  end

  defp normalize_entity_map(entities) when is_map(entities) do
    Enum.into(entities, %{}, fn {text, info} ->
      {text, %{
        id: info["id"] || "unknown:#{text}",
        type: String.to_atom(info["type"] || "unknown"),
        confidence: info["confidence"] || 0.5
      }}
    end)
  end
  defp normalize_entity_map(_), do: %{}

  defp normalize_predicate_map(predicates) when is_map(predicates) do
    Enum.into(predicates, %{}, fn {text, info} ->
      {text, %{
        id: info["id"] || "pred:#{text}",
        type: String.to_atom(info["type"] || "property"),
        arity: info["arity"] || 1
      }}
    end)
  end
  defp normalize_predicate_map(_), do: %{}

  defp heuristic_ground(parsed) do
    entities = Enum.into(parsed.entities, %{}, fn entity ->
      {entity, %{
        id: "entity:#{String.downcase(entity) |> String.replace(~r/\s+/, "_")}",
        type: :unknown,
        confidence: 0.7
      }}
    end)

    predicates = Enum.into(parsed.predicates, %{}, fn pred ->
      {pred, %{
        id: "pred:#{String.downcase(pred) |> String.replace(~r/\s+/, "_")}",
        type: :property,
        arity: 1
      }}
    end)

    %{
      entities: entities,
      predicates: predicates,
      ungrounded: []
    }
  end

  defp augment_with_embeddings(grounded, parsed, _opts) do
    # Try to find similar entities in our indexed documentation
    case Embeddings.available?() do
      true ->
        # For each entity, find similar concepts in our knowledge base
        augmented_entities = Enum.into(grounded.entities, %{}, fn {text, info} ->
          case find_similar_in_kb(text) do
            {:ok, matches} when matches != [] ->
              best_match = hd(matches)
              {text, Map.merge(info, %{
                kb_match: best_match.id,
                kb_confidence: best_match.score
              })}

            _ ->
              {text, info}
          end
        end)

        %{grounded | entities: augmented_entities}

      false ->
        grounded
    end
  end

  defp find_similar_in_kb(text) do
    # This would query our documentation storage for similar concepts
    case Storage.search(text, limit: 3) do
      {:ok, results} ->
        {:ok, Enum.map(results, fn r ->
          %{id: r[:id], score: r[:score] || 0.5}
        end)}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  defp check_ambiguity(grounded, threshold) do
    low_confidence = grounded.entities
      |> Enum.filter(fn {_, info} -> info.confidence < threshold end)
      |> Enum.map(fn {text, _} -> text end)

    if length(low_confidence) > 0 do
      {:ambiguous, low_confidence}
    else
      :ok
    end
  end
end
