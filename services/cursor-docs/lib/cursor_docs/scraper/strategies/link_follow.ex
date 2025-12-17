defmodule CursorDocs.Scraper.Strategies.LinkFollow do
  @moduledoc """
  Crawler strategy that follows internal links recursively.

  Used for documentation sites without sitemaps that have interlinked pages.
  Implements breadth-first crawling with:
  - Same-domain restriction
  - Depth limiting
  - URL deduplication
  - Politeness delays

  Example sites:
  - ReadTheDocs documentation
  - MkDocs sites
  - Static documentation generators
  """

  @behaviour CursorDocs.Scraper.CrawlerStrategy

  require Logger

  @default_max_depth 3
  @default_max_pages 100
  @crawl_delay_ms 200

  @impl true
  def detect(_url, _html), do: :link_follow

  @impl true
  def discover_urls(start_url, html, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    base_uri = URI.parse(start_url)

    Logger.info("LinkFollow strategy: crawling from #{start_url}, max_depth=#{max_depth}, max_pages=#{max_pages}")

    # Start with links from the initial page (already fetched)
    initial_links = extract_same_domain_links(html, base_uri)
    Logger.debug("Found #{length(initial_links)} initial links from index page")

    # Convert initial links to queue items at depth 1
    initial_queue = Enum.map(initial_links, fn url -> {url, 1} end)

    # BFS crawl starting from the discovered links (not re-fetching the start URL)
    discovered =
      crawl_bfs(
        initial_queue,
        MapSet.new([start_url | initial_links]),  # Mark all initial links as seen
        base_uri,
        max_depth,
        max_pages
      )

    # Include the start URL in results
    all_discovered = MapSet.put(discovered, start_url)

    Logger.info("LinkFollow strategy: discovered #{MapSet.size(all_discovered)} URLs")
    {:ok, MapSet.to_list(all_discovered)}
  end

  @impl true
  def process_content(_url, html, _opts \\ []) do
    {:ok, html}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp crawl_bfs([], seen, _base_uri, _max_depth, _max_pages) do
    seen
  end

  defp crawl_bfs(_queue, seen, _base_uri, _max_depth, max_pages)
       when map_size(seen) >= max_pages do
    seen
  end

  defp crawl_bfs([{_url, depth} | rest], seen, base_uri, max_depth, max_pages)
       when depth >= max_depth do
    crawl_bfs(rest, seen, base_uri, max_depth, max_pages)
  end

  defp crawl_bfs([{url, depth} | rest], seen, base_uri, max_depth, max_pages) do
    # URLs are already marked as seen when added to queue
    # Just process to find more links if within depth
    new_links =
      case fetch_page(url) do
        {:ok, html} ->
          extract_same_domain_links(html, base_uri)
          |> Enum.reject(&MapSet.member?(seen, &1))

        {:error, _} ->
          []
      end

    # Politeness delay
    Process.sleep(@crawl_delay_ms)

    # Add new links to queue at depth+1
    new_queue = rest ++ Enum.map(new_links, &{&1, depth + 1})
    new_seen = Enum.reduce(new_links, seen, &MapSet.put(&2, &1))

    crawl_bfs(new_queue, new_seen, base_uri, max_depth, max_pages)
  end

  defp fetch_page(url) do
    case Req.get(url, receive_timeout: 10_000, redirect: true) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_same_domain_links(html, base_uri) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find("a[href]")
        |> Enum.map(fn elem ->
          case Floki.attribute(elem, "href") do
            [href | _] -> normalize_href(href, base_uri)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(&same_domain?(&1, base_uri))
        |> Enum.filter(&valid_doc_url?/1)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp normalize_href(href, base_uri) do
    cond do
      # Skip anchors, javascript, mailto, etc.
      String.starts_with?(href, "#") -> nil
      String.starts_with?(href, "javascript:") -> nil
      String.starts_with?(href, "mailto:") -> nil
      # Absolute URL
      String.starts_with?(href, "http://") or String.starts_with?(href, "https://") -> href
      # Protocol-relative
      String.starts_with?(href, "//") -> "#{base_uri.scheme}:#{href}"
      # Relative URL
      true -> resolve_relative(href, base_uri)
    end
  rescue
    _ -> nil
  end

  defp resolve_relative(href, base_uri) do
    base_path = base_uri.path || "/"

    resolved_path =
      if String.starts_with?(href, "/") do
        href
      else
        base_path
        |> Path.dirname()
        |> Path.join(href)
        |> normalize_path()
      end

    # Remove query strings and fragments for deduplication
    resolved_path = resolved_path |> String.split("?") |> hd() |> String.split("#") |> hd()

    "#{base_uri.scheme}://#{base_uri.host}#{resolved_path}"
  end

  defp normalize_path(path) do
    path
    |> String.split("/")
    |> Enum.reduce([], fn
      "..", [_ | rest] -> rest
      "..", [] -> []
      ".", acc -> acc
      "", acc -> acc
      segment, acc -> [segment | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("/")
    |> then(&("/" <> &1))
  end

  defp same_domain?(url, base_uri) do
    case URI.parse(url) do
      %URI{host: host} -> host == base_uri.host
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_doc_url?(url) do
    # Filter out non-documentation URLs
    cond do
      String.contains?(url, "/cdn-cgi/") -> false
      String.contains?(url, "/assets/") -> false
      String.contains?(url, "/static/") -> false
      String.ends_with?(url, ".css") -> false
      String.ends_with?(url, ".js") -> false
      String.ends_with?(url, ".png") -> false
      String.ends_with?(url, ".jpg") -> false
      String.ends_with?(url, ".gif") -> false
      String.ends_with?(url, ".svg") -> false
      String.ends_with?(url, ".ico") -> false
      String.ends_with?(url, ".woff") -> false
      String.ends_with?(url, ".woff2") -> false
      true -> true
    end
  end
end

