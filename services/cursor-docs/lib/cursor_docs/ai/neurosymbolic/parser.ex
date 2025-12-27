defmodule CursorDocs.AI.Neurosymbolic.Parser do
  @moduledoc """
  Natural language parser for neuro-symbolic reasoning.

  Converts natural language queries into structured representations
  suitable for symbol grounding and logical reasoning.

  ## Output Format

  The parser produces a structured intent:

      %{
        intent: :query | :assertion | :command,
        predicates: ["is_safe", "contains_bug"],
        entities: ["the_function", "line_42"],
        relations: [{:subject, :predicate, :object}],
        modifiers: %{negated: false, uncertain: true},
        raw_query: "original query text"
      }

  ## Models Used

  - Primary: `qwen2.5-coder:7b` (for code-related queries)
  - Fallback: `qwen2.5:7b` (general queries)
  """

  require Logger

  alias CursorDocs.Embeddings

  @parser_prompt """
  You are a semantic parser that converts natural language queries into structured representations.

  Given a query, extract:
  1. **intent**: Is this a question (query), statement (assertion), or request (command)?
  2. **predicates**: What properties or actions are being asked about?
  3. **entities**: What things/objects/concepts are mentioned?
  4. **relations**: How are entities related to each other?
  5. **modifiers**: Is the query negated? Uncertain? Conditional?

  Respond in JSON format:
  ```json
  {
    "intent": "query|assertion|command",
    "predicates": ["predicate1", "predicate2"],
    "entities": ["entity1", "entity2"],
    "relations": [["subject", "predicate", "object"]],
    "modifiers": {"negated": false, "uncertain": false, "conditional": false}
  }
  ```

  Query: {query}

  JSON response:
  """

  @doc """
  Parse a natural language query into structured form.

  ## Options

    * `:model` - Override the default model
    * `:endpoint` - Ollama endpoint to use

  ## Examples

      iex> Parser.parse("Is this function safe to use?")
      {:ok, %{
        intent: :query,
        predicates: ["safe", "usable"],
        entities: ["function"],
        relations: [],
        modifiers: %{negated: false}
      }}

  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(query, opts \\ []) do
    model = Keyword.get(opts, :model, select_model(query))
    endpoint = Keyword.get(opts, :endpoint, "http://localhost:11434")

    prompt = String.replace(@parser_prompt, "{query}", query)

    Logger.debug("[Parser] Parsing query with model #{model}")

    case call_llm(endpoint, model, prompt) do
      {:ok, response} ->
        case extract_json(response) do
          {:ok, parsed} ->
            {:ok, normalize_parsed(parsed, query)}

          {:error, reason} ->
            Logger.warning("[Parser] Failed to parse JSON: #{inspect(reason)}")
            # Fallback to simple heuristic parsing
            {:ok, heuristic_parse(query)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parse without LLM - uses heuristic rules.
  Faster but less accurate.
  """
  @spec parse_fast(String.t()) :: {:ok, map()}
  def parse_fast(query) do
    {:ok, heuristic_parse(query)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp select_model(query) do
    # Use coding model for code-related queries
    code_keywords = ~w(function code bug error compile runtime syntax)

    if Enum.any?(code_keywords, &String.contains?(String.downcase(query), &1)) do
      "qwen2.5-coder:7b"
    else
      "qwen2.5:7b"
    end
  end

  defp call_llm(endpoint, model, prompt) do
    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.1,  # Low temperature for consistent parsing
        num_predict: 500
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
    # Try to find JSON in the response
    case Regex.run(~r/\{[\s\S]*\}/, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          error -> error
        end

      nil ->
        {:error, :no_json_found}
    end
  end

  defp normalize_parsed(parsed, raw_query) do
    %{
      intent: normalize_intent(parsed["intent"]),
      predicates: parsed["predicates"] || [],
      entities: parsed["entities"] || [],
      relations: normalize_relations(parsed["relations"] || []),
      modifiers: normalize_modifiers(parsed["modifiers"] || %{}),
      raw_query: raw_query
    }
  end

  defp normalize_intent("query"), do: :query
  defp normalize_intent("assertion"), do: :assertion
  defp normalize_intent("command"), do: :command
  defp normalize_intent(_), do: :query

  defp normalize_relations(relations) when is_list(relations) do
    Enum.map(relations, fn
      [s, p, o] -> {s, p, o}
      rel -> rel
    end)
  end
  defp normalize_relations(_), do: []

  defp normalize_modifiers(modifiers) when is_map(modifiers) do
    %{
      negated: modifiers["negated"] == true,
      uncertain: modifiers["uncertain"] == true,
      conditional: modifiers["conditional"] == true
    }
  end
  defp normalize_modifiers(_), do: %{negated: false, uncertain: false, conditional: false}

  defp heuristic_parse(query) do
    query_lower = String.downcase(query)

    # Detect intent
    intent = cond do
      String.starts_with?(query_lower, ["is ", "are ", "does ", "do ", "can ", "will ", "what ", "how ", "why "]) ->
        :query

      String.ends_with?(query_lower, "?") ->
        :query

      String.starts_with?(query_lower, ["show ", "list ", "find ", "get ", "search "]) ->
        :command

      true ->
        :assertion
    end

    # Extract simple entities (nouns)
    words = String.split(query, ~r/\s+/)
    entities = words
      |> Enum.filter(&(String.length(&1) > 3))
      |> Enum.reject(&String.match?(&1, ~r/^(the|this|that|these|those|is|are|was|were|be|been|being|have|has|had)$/i))
      |> Enum.take(5)

    # Detect modifiers
    negated = String.contains?(query_lower, ["not ", "no ", "never ", "don't ", "doesn't ", "isn't ", "aren't "])
    uncertain = String.contains?(query_lower, ["maybe ", "might ", "could ", "possibly ", "perhaps "])

    %{
      intent: intent,
      predicates: [],  # Would need NLP for proper predicate extraction
      entities: entities,
      relations: [],
      modifiers: %{negated: negated, uncertain: uncertain, conditional: false},
      raw_query: query
    }
  end
end
