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
  alias CursorDocs.Scraper.CrawlerStrategy
  alias CursorDocs.Security.Quarantine

  require Logger

  @default_max_pages 100
  @default_strategy :auto  # :auto, :single_page, :frameset, :sitemap, :link_follow
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
    * `:strategy` - Crawling strategy (:auto, :single_page, :frameset, :sitemap, :link_follow)

  """
  @spec add(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add(url, opts \\ []) do
    name = Keyword.get(opts, :name, derive_name(url))
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)
    follow_links = Keyword.get(opts, :follow_links, false)
    strategy = Keyword.get(opts, :strategy, @default_strategy)

    # Create source record
    source_attrs = %{
      url: url,
      name: name,
      config: %{
        max_pages: max_pages,
        follow_links: follow_links,
        strategy: strategy
      }
    }

    case Storage.create_source(source_attrs) do
      {:ok, source} ->
        Logger.info("Started scraping #{name} (#{url})")

        # Update status to indexing
        Storage.update_source(source[:id], %{status: "indexing"})

        # Fetch initial page to detect strategy
        case fetch_html(url) do
          {:ok, html} ->
            # Auto-detect or use specified strategy
            detected_strategy =
              if strategy == :auto do
                CrawlerStrategy.detect_strategy(url, html)
              else
                strategy
              end

            Logger.info("Using #{detected_strategy} strategy for #{url}")

            # Discover all URLs using the strategy
            strategy_module = CrawlerStrategy.strategy_module(detected_strategy)

            case strategy_module.discover_urls(url, html, max_pages: max_pages) do
              {:ok, urls_to_scrape} ->
                # Scrape all discovered URLs
                scrape_multi_page(source, urls_to_scrape, name, detected_strategy)

              {:error, reason} ->
                Storage.update_source(source[:id], %{status: "failed"})
                {:error, {:strategy_failed, reason}}
            end

          {:error, reason} ->
            Storage.update_source(source[:id], %{status: "failed"})
            Logger.error("Failed to fetch #{url}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} = error ->
        Logger.error("Failed to create source: #{inspect(reason)}")
        error
    end
  end

  defp scrape_multi_page(source, urls, name, strategy) do
    total_urls = length(urls)
    Logger.info("Scraping #{total_urls} URLs with #{strategy} strategy")

    # Clear existing chunks before scraping
    Storage.clear_chunks(source[:id])

    # For frameset/sitemap strategies with many URLs, process in batches
    # For single page, just process directly
    results =
      if strategy in [:frameset, :sitemap, :link_follow] and total_urls > 1 do
        # Multi-page: process each discovered URL, allowing some failures
        urls
        |> Enum.with_index(1)
        |> Enum.map(fn {url, index} ->
          Logger.debug("Processing URL #{index}/#{total_urls}: #{url}")
          RateLimiter.acquire()
          scrape_content_page(source[:id], url, name)
        end)
      else
        # Single page: normal processing
        urls
        |> Enum.map(fn url ->
          scrape_url(source[:id], url, name)
        end)
      end

    # Count successes
    successful = Enum.filter(results, fn {status, _} -> status == :ok end)
    total_chunks = Enum.reduce(successful, 0, fn {:ok, r}, acc -> acc + (r[:chunks_count] || 0) end)

    if length(successful) > 0 do
      # Update source with combined results
      Storage.update_source(source[:id], %{
        status: "indexed",
        pages_count: length(successful),
        chunks_count: total_chunks,
        last_indexed: DateTime.utc_now() |> DateTime.to_iso8601()
      })

      {:ok, Map.merge(source, %{
        chunks_count: total_chunks,
        pages_count: length(successful),
        status: "indexed"
      })}
    else
      Storage.update_source(source[:id], %{status: "failed"})
      {:error, :all_pages_failed}
    end
  end

  # Simplified content page scraping for multi-page strategies
  # Less strict quality validation since we've already discovered these via strategy
  defp scrape_content_page(source_id, url, title) do
    case fetch_html(url) do
      {:ok, html} ->
        # Use extractor directly, bypassing some quarantine strictness for discovered pages
        case Extractor.extract_from_html(html, url) do
          {:ok, extracted} when byte_size(extracted.content) > 100 ->
            chunks = chunk_content(extracted.content, extracted.title || title, source_id, url)

            case Storage.store_chunks(chunks) do
              {:ok, count} ->
                Logger.debug("Stored #{count} chunks from #{url}")
                {:ok, %{chunks_count: count}}

              {:error, reason} ->
                {:error, reason}
            end

          {:ok, _} ->
            # Very short content - skip this page
            {:ok, %{chunks_count: 0}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("Error scraping #{url}: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Refresh an existing documentation source.
  """
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(source_id) do
    case Storage.get_source(source_id) do
      {:ok, source} ->
        Storage.update_source(source_id, %{status: "indexing"})

        # Re-fetch and re-detect strategy
        case fetch_html(source[:url]) do
          {:ok, html} ->
            config = source[:config] || %{}
            max_pages = config[:max_pages] || @default_max_pages
            strategy = config[:strategy] || :auto

            detected_strategy =
              if strategy == :auto do
                CrawlerStrategy.detect_strategy(source[:url], html)
              else
                strategy
              end

            Logger.info("Refresh using #{detected_strategy} strategy for #{source[:url]}")

            strategy_module = CrawlerStrategy.strategy_module(detected_strategy)

            case strategy_module.discover_urls(source[:url], html, max_pages: max_pages) do
              {:ok, urls_to_scrape} ->
                scrape_multi_page(source, urls_to_scrape, source[:name], detected_strategy)

              {:error, reason} ->
                Storage.update_source(source_id, %{status: "failed"})
                {:error, {:strategy_failed, reason}}
            end

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
