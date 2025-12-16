defmodule CursorDocs.Scraper do
  @moduledoc """
  Documentation scraper coordinator with security quarantine.

  Orchestrates the scraping pipeline:
  1. Accept URL for indexing
  2. Fetch page through QUARANTINE ZONE
  3. Security validation (hidden content, prompt injection)
  4. Quality validation
  5. Store validated chunks in SQLite
  6. Optionally follow discovered links

  ## Security Model

  ALL external content is treated as potentially malicious:
  - Content passes through security quarantine before indexing
  - Hidden text and prompt injections are detected and sanitized
  - Quality validation prevents junk from entering the index
  - Security alerts are logged for user review

  ## Usage

      # Add documentation for scraping (synchronous, blocks until first page done)
      {:ok, source} = Scraper.add("https://docs.example.com/")

      # Refresh existing documentation
      {:ok, source} = Scraper.refresh("source:abc123")

  """

  alias CursorDocs.{Storage, Scraper.Extractor, Scraper.RateLimiter}
  alias CursorDocs.Security.Quarantine

  require Logger

  @default_max_pages 100
  @chunk_size 1500
  @chunk_overlap 200

  @doc """
  Add a new documentation URL for scraping.

  This function scrapes the initial URL synchronously, so it blocks until
  the first page is indexed. This ensures the CLI shows meaningful results.

  ## Options

    * `:name` - Display name for the documentation
    * `:max_pages` - Maximum pages to scrape (default: 100)
    * `:follow_links` - Whether to follow discovered links (default: false for now)

  """
  @spec add(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add(url, opts \\ []) do
    name = Keyword.get(opts, :name, derive_name(url))
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)
    follow_links = Keyword.get(opts, :follow_links, false)

    # Create source record
    source_attrs = %{
      url: url,
      name: name,
      config: %{
        max_pages: max_pages,
        follow_links: follow_links
      }
    }

    case Storage.create_source(source_attrs) do
      {:ok, source} ->
        Logger.info("Started scraping #{name} (#{url})")

        # Update status to indexing
        Storage.update_source(source[:id], %{status: "indexing"})

        # Scrape the initial URL synchronously
        case scrape_url(source[:id], url, name) do
          {:ok, result} ->
            # Update source with results
            Storage.update_source(source[:id], %{
              status: "indexed",
              security_tier: result[:security_tier] || "clean",
              pages_count: 1,
              chunks_count: result.chunks_count,
              last_indexed: DateTime.utc_now() |> DateTime.to_iso8601()
            })

            # Optionally follow links in background
            if follow_links and length(result.links) > 0 do
              spawn(fn -> follow_links_async(source[:id], result.links, max_pages - 1) end)
            end

            {:ok, Map.merge(source, %{chunks_count: result.chunks_count, status: "indexed"})}

          {:error, reason} ->
            Storage.update_source(source[:id], %{status: "failed"})
            Logger.error("Failed to scrape #{url}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} = error ->
        Logger.error("Failed to create source: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Refresh an existing documentation source.
  """
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(source_id) do
    case Storage.get_source(source_id) do
      {:ok, source} ->
        Storage.update_source(source_id, %{status: "indexing"})

        case scrape_url(source_id, source[:url], source[:name]) do
          {:ok, result} ->
            Storage.update_source(source_id, %{
              status: "indexed",
              security_tier: result[:security_tier] || "clean",
              pages_count: 1,
              chunks_count: result.chunks_count,
              last_indexed: DateTime.utc_now() |> DateTime.to_iso8601()
            })

            {:ok, source}

          {:error, reason} ->
            Storage.update_source(source_id, %{status: "failed"})
            {:error, reason}
        end

      error ->
        error
    end
  end

  # Private Functions

  defp scrape_url(source_id, url, title) do
    # Rate limit
    RateLimiter.acquire()

    Logger.debug("Fetching #{url}")

    case fetch_html(url) do
      {:ok, html} ->
        # Process through security quarantine
        case process_through_quarantine(html, url, title) do
          {:ok, extracted, security_tier} ->
            # Clear existing chunks for this source (prevents duplicates)
            Storage.clear_chunks(source_id)

            # Create and store chunks (with embeddings if SurrealDB available)
            chunks = chunk_content(extracted.content, extracted.title || title, source_id, url)

            case Storage.store_chunks(chunks) do
              {:ok, count} ->
                Logger.info("Stored #{count} chunks for #{url} (security: #{security_tier})")
                {:ok, %{chunks_count: count, links: extracted.links, security_tier: security_tier}}

              {:error, reason} ->
                Logger.error("Failed to store chunks: #{inspect(reason)}")
                {:error, reason}
            end

          {:blocked, alerts} ->
            Logger.error("Content blocked for #{url}: #{length(alerts)} security issues")
            {:error, {:security_blocked, alerts}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_html(url) do
    case Req.get(url,
           headers: [{"user-agent", "CursorDocs/1.0 (Documentation Indexer)"}],
           receive_timeout: 30_000,
           redirect: true,
           max_redirects: 5
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %{reason: reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_through_quarantine(html, url, name) do
    # Route all content through security quarantine
    case Quarantine.process(html, url, name: name) do
      {:ok, tier, alerts, sanitized_html, _item_id} when tier in [:clean, :flagged] ->
        # Content is safe enough to index
        if length(alerts) > 0 do
          Logger.warning("#{url} passed with #{length(alerts)} alerts (tier: #{tier})")
        end
        # Extract content from sanitized HTML
        case Extractor.extract_from_html(sanitized_html, url) do
          {:ok, extracted} -> {:ok, extracted, tier}
          error -> error
        end

      {:ok, :quarantined, alerts, _html, _item_id} ->
        # Quarantined - needs human review before indexing
        Logger.warning("#{url} quarantined with #{length(alerts)} alerts - needs review")
        # For now, still extract but flag it
        case Extractor.extract_from_html(html, url) do
          {:ok, extracted} -> {:ok, extracted, :quarantined}
          error -> error
        end

      {:blocked, alerts, _} ->
        {:blocked, alerts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp follow_links_async(source_id, links, remaining) when remaining > 0 and links != [] do
    # Get base domain to stay on same site
    [first_link | rest] = links

    case scrape_url(source_id, first_link, nil) do
      {:ok, result} ->
        Storage.update_source(source_id, %{
          pages_count: {:increment, 1},
          chunks_count: {:increment, result.chunks_count}
        })

        follow_links_async(source_id, rest, remaining - 1)

      {:error, _reason} ->
        # Skip failed links, continue with rest
        follow_links_async(source_id, rest, remaining)
    end
  end

  defp follow_links_async(_source_id, _links, _remaining), do: :ok

  defp chunk_content(content, title, source_id, url) do
    content
    |> split_into_chunks(@chunk_size, @chunk_overlap)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_content, position} ->
      %{
        source_id: source_id,
        url: url,
        title: title,
        content: chunk_content,
        position: position
      }
    end)
  end

  defp split_into_chunks(text, size, overlap) do
    do_split_chunks(text, size, overlap, 0, [])
  end

  defp do_split_chunks(text, _size, _overlap, start, acc) when start >= byte_size(text) do
    Enum.reverse(acc)
  end

  defp do_split_chunks(text, size, overlap, start, acc) do
    chunk = String.slice(text, start, size)

    # Try to break at paragraph or sentence boundary
    chunk =
      if String.length(chunk) == size do
        case find_break_point(chunk) do
          nil -> chunk
          pos -> String.slice(chunk, 0, pos)
        end
      else
        chunk
      end

    # Skip empty chunks
    if String.trim(chunk) == "" do
      do_split_chunks(text, size, overlap, start + size, acc)
    else
      next_start = start + String.length(chunk) - overlap
      do_split_chunks(text, size, overlap, max(next_start, start + 1), [chunk | acc])
    end
  end

  defp find_break_point(text) do
    # Look for paragraph break in second half
    text_bytes = byte_size(text)
    half = div(text_bytes, 2)

    case :binary.match(text, "\n\n", scope: {half, text_bytes - half}) do
      {pos, _} ->
        pos + 2
      :nomatch ->
        # Look for sentence break
        case Regex.run(~r/\. /, text, return: :index) do
          [{pos, _}] when pos > half -> pos + 2
          _ -> nil
        end
    end
  end

  defp derive_name(url) do
    uri = URI.parse(url)

    # Try to derive a nice name from the URL
    parts = String.split(uri.host || "", ".")
    domain = Enum.at(parts, -2) || Enum.at(parts, 0) || "docs"

    String.capitalize(domain)
  end
end
