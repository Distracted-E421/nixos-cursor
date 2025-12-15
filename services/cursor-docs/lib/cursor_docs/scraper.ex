defmodule CursorDocs.Scraper do
  @moduledoc """
  Documentation scraper coordinator.

  Orchestrates the scraping pipeline:
  1. Accept URL for indexing
  2. Queue initial page for scraping
  3. Scrape page, extract content and links
  4. Queue discovered links
  5. Repeat until max pages reached or no more links

  ## Usage

      # Add documentation for scraping
      {:ok, source} = Scraper.add("https://docs.example.com/")

      # Refresh existing documentation
      {:ok, source} = Scraper.refresh("source:abc123")

  """

  alias CursorDocs.{Storage.SQLite, Scraper.JobQueue, Scraper.Extractor}
  alias CursorDocs.{Scraper.RateLimiter, Telemetry}

  require Logger

  @default_max_pages 100
  @default_depth 3
  @chunk_size 1500
  @chunk_overlap 200

  @doc """
  Add a new documentation URL for scraping.

  ## Options

    * `:name` - Display name for the documentation
    * `:max_pages` - Maximum pages to scrape (default: 100)
    * `:depth` - Maximum crawl depth (default: 3)

  """
  @spec add(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add(url, opts \\ []) do
    name = Keyword.get(opts, :name, derive_name(url))
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)

    # Create source record
    source_attrs = %{
      url: url,
      name: name,
      config: %{
        max_pages: max_pages,
        depth: Keyword.get(opts, :depth, @default_depth)
      }
    }

    case SQLite.create_source(source_attrs) do
      {:ok, source} ->
        # Queue initial URL
        JobQueue.enqueue(source[:id], url, priority: 10)

        # Start processing asynchronously
        spawn(fn -> process_source(source[:id]) end)

        Logger.info("Started scraping #{name} (#{url})")
        Telemetry.scrape_start(url, source[:id])

        {:ok, source}

      error ->
        error
    end
  end

  @doc """
  Refresh an existing documentation source.
  """
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(source_id) do
    case SQLite.get_source(source_id) do
      {:ok, source} ->
        # Cancel existing jobs
        JobQueue.cancel(source_id)

        # Queue root URL again
        JobQueue.enqueue(source_id, source[:url], priority: 10)

        # Update status
        SQLite.update_source(source_id, %{status: "indexing"})

        # Start processing
        spawn(fn -> process_source(source_id) end)

        {:ok, source}

      error ->
        error
    end
  end

  # Private Functions

  defp process_source(source_id) do
    case JobQueue.dequeue() do
      {:ok, job} when job.source_id == source_id ->
        process_job(job)
        process_source(source_id)

      {:ok, job} ->
        # Job for different source, put it back and get ours
        JobQueue.enqueue(job.source_id, job.url, priority: job.priority)
        process_source(source_id)

      {:empty} ->
        # No more jobs, mark source as indexed
        SQLite.update_source(source_id, %{
          status: "indexed",
          last_indexed: DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.info("Completed scraping source #{source_id}")
    end
  end

  defp process_job(job) do
    # Rate limit
    RateLimiter.acquire()

    # Use simple HTTP fetching (no JS rendering for now)
    case fetch_and_extract(job.url) do
      {:ok, extracted} ->
        handle_extracted(job, extracted)
        JobQueue.complete(job.id)

      {:error, reason} ->
        Logger.warning("Fetch failed for #{job.url}: #{inspect(reason)}")
        JobQueue.fail(job.id, inspect(reason))
    end
  end

  defp fetch_and_extract(url) do
    case Req.get(url, headers: [{"user-agent", "CursorDocs/1.0 (Documentation Indexer)"}]) do
      {:ok, %{status: 200, body: body}} ->
        Extractor.extract_from_html(body, url)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_extracted(job, extracted) do
    # Create chunks from content
    chunks = chunk_content(extracted.content, extracted.title, job)

    # Store chunks
    case SQLite.store_chunks(chunks) do
      {:ok, count} ->
        Logger.debug("Stored #{count} chunks for #{job.url}")

        # Update source page count
        SQLite.update_source(job.source_id, %{
          pages_count: {:increment, 1},
          chunks_count: {:increment, count}
        })

      {:error, reason} ->
        Logger.error("Failed to store chunks: #{inspect(reason)}")
    end

    # Queue discovered links (limit to same domain)
    base_uri = URI.parse(job.url)

    extracted.links
    |> Enum.filter(fn link ->
      link_uri = URI.parse(link)
      link_uri.host == base_uri.host
    end)
    |> Enum.take(50)  # Limit links per page
    |> Enum.each(fn link ->
      JobQueue.enqueue(job.source_id, link, priority: 0)
    end)
  end

  defp chunk_content(content, title, job) do
    content
    |> split_into_chunks(@chunk_size, @chunk_overlap)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_content, position} ->
      %{
        source_id: job.source_id,
        url: job.url,
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

    next_start = start + String.length(chunk) - overlap

    do_split_chunks(text, size, overlap, max(next_start, start + 1), [chunk | acc])
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
