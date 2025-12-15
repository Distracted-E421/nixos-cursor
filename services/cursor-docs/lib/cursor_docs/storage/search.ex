defmodule CursorDocs.Storage.Search do
  @moduledoc """
  Full-text search functionality for CursorDocs.

  Provides semantic search across indexed documentation using SurrealDB's
  built-in full-text search with BM25 ranking.

  ## Features

  - BM25 relevance scoring
  - Source filtering
  - Snippet generation with context
  - Result highlighting

  ## Usage

      # Basic search
      {:ok, results} = Search.search("authentication")

      # Search with options
      {:ok, results} = Search.search("database queries",
        limit: 10,
        sources: ["Ecto", "Phoenix"],
        min_score: 0.5
      )
  """

  alias CursorDocs.{Storage.SQLite, Telemetry}

  require Logger

  @default_limit 5
  @snippet_length 300

  @doc """
  Search indexed documentation for matching content.

  ## Options

    * `:limit` - Maximum results (default: 5)
    * `:sources` - Filter by source names (list)
    * `:min_score` - Minimum relevance score (default: 0.0)
    * `:with_snippets` - Include highlighted snippets (default: true)

  ## Returns

  A list of matching chunks with:
    * `:content` - Full content or snippet
    * `:title` - Page title
    * `:url` - Source URL
    * `:source_name` - Documentation source name
    * `:score` - BM25 relevance score
    * `:snippet` - Highlighted snippet (if requested)
  """
  @spec search(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search(query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    limit = Keyword.get(opts, :limit, @default_limit)
    sources = Keyword.get(opts, :sources, [])
    min_score = Keyword.get(opts, :min_score, 0.0)
    with_snippets = Keyword.get(opts, :with_snippets, true)

    # Sanitize query
    sanitized_query = sanitize_query(query)

    case SQLite.search_chunks(sanitized_query, limit: limit * 2, sources: sources) do
      {:ok, chunks} ->
        results =
          chunks
          |> Enum.filter(fn chunk -> (chunk[:score] || 0) >= min_score end)
          |> Enum.take(limit)
          |> Enum.map(fn chunk -> format_result(chunk, query, with_snippets) end)

        duration_ms = System.monotonic_time(:millisecond) - start_time
        Telemetry.search_query(query, length(results), duration_ms)

        Logger.debug("Search '#{query}' returned #{length(results)} results in #{duration_ms}ms")

        {:ok, results}

      {:error, reason} = error ->
        Logger.error("Search failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Search and group results by source.
  """
  @spec search_grouped(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def search_grouped(query, opts \\ []) do
    case search(query, Keyword.put(opts, :limit, (opts[:limit] || @default_limit) * 3)) do
      {:ok, results} ->
        grouped =
          results
          |> Enum.group_by(& &1[:source_name])
          |> Enum.map(fn {source, chunks} ->
            {source, Enum.take(chunks, opts[:per_source] || 3)}
          end)
          |> Map.new()

        {:ok, grouped}

      error ->
        error
    end
  end

  @doc """
  Get search suggestions based on indexed content.
  """
  @spec suggest(String.t(), keyword()) :: {:ok, list(String.t())} | {:error, term()}
  def suggest(_prefix, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 5)

    # Simple prefix matching on titles
    # In a real implementation, this would use a proper autocomplete index
    {:ok, []}  # Placeholder
  end

  # Private Functions

  defp sanitize_query(query) do
    query
    |> String.trim()
    |> String.replace(~r/[^\w\s\-\.]/, " ")
    |> String.replace(~r/\s+/, " ")
  end

  defp format_result(chunk, query, with_snippets) do
    base = %{
      content: chunk[:content],
      title: chunk[:title],
      url: chunk[:url],
      source_id: chunk[:source_id],
      source_name: extract_source_name(chunk[:source_id]),
      score: chunk[:score] || 0,
      position: chunk[:position]
    }

    if with_snippets do
      Map.put(base, :snippet, generate_snippet(chunk[:content], query))
    else
      base
    end
  end

  defp extract_source_name(nil), do: "Unknown"
  defp extract_source_name(source_id) do
    # Extract name from source_id or look up in database
    source_id
    |> String.replace_prefix("source:", "")
    |> String.split("_")
    |> List.first()
    |> String.capitalize()
  end

  defp generate_snippet(content, query) when is_binary(content) do
    # Find the best matching section
    query_words = String.downcase(query) |> String.split()
    content_lower = String.downcase(content)

    # Find position of first query word
    position =
      query_words
      |> Enum.find_value(0, fn word ->
        case :binary.match(content_lower, word) do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)

    # Extract snippet around the match
    start_pos = max(0, position - div(@snippet_length, 3))
    snippet = String.slice(content, start_pos, @snippet_length)

    # Clean up snippet boundaries
    snippet =
      if start_pos > 0 do
        # Find first space to start at word boundary
        case String.split(snippet, " ", parts: 2) do
          [_, rest] -> "..." <> rest
          _ -> "..." <> snippet
        end
      else
        snippet
      end

    # Trim at word boundary at end
    if String.length(content) > start_pos + @snippet_length do
      words = String.split(snippet, " ")
      words
      |> Enum.take(length(words) - 1)
      |> Enum.join(" ")
      |> Kernel.<>("...")
    else
      snippet
    end
  end

  defp generate_snippet(_, _), do: ""
end
