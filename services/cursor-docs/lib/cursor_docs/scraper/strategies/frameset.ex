defmodule CursorDocs.Scraper.Strategies.Frameset do
  @moduledoc """
  Crawler strategy for frameset-based documentation (Javadoc, Doxygen).

  Javadoc structure typically:
  ```
  index.html (frameset)
  ├── overview-frame.html (package list)
  ├── allclasses-frame.html (class list)
  └── overview-summary.html (main content)
  
  Individual pages:
  ├── package-summary.html (per package)
  └── ClassName.html (per class)
  ```

  This strategy:
  1. Detects frameset in index page
  2. Extracts all frame src URLs
  3. Discovers class/method pages from frames
  4. Crawls each content page
  """

  @behaviour CursorDocs.Scraper.CrawlerStrategy

  require Logger

  @impl true
  def detect(_url, html) do
    if frameset?(html), do: :frameset, else: :unknown
  end

  @impl true
  def discover_urls(base_url, html, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 500)
    base_uri = URI.parse(base_url)

    Logger.info("Frameset strategy: discovering URLs from #{base_url}")

    with {:ok, frame_urls} <- extract_frame_urls(html, base_uri),
         {:ok, content_urls} <- discover_content_pages(frame_urls, base_uri, max_pages) do
      all_urls = Enum.uniq(frame_urls ++ content_urls)

      Logger.info("Frameset strategy: discovered #{length(all_urls)} URLs")
      {:ok, Enum.take(all_urls, max_pages)}
    end
  end

  @impl true
  def process_content(_url, html, _opts \\ []) do
    # Extract main content, removing navigation and boilerplate
    case extract_javadoc_content(html) do
      {:ok, content} when byte_size(content) > 100 ->
        {:ok, content}

      {:ok, _} ->
        {:error, :insufficient_content}

      error ->
        error
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp frameset?(html) do
    html
    |> String.downcase()
    |> String.contains?("<frameset")
  end

  defp extract_frame_urls(html, base_uri) do
    # Parse frameset and extract frame src attributes
    case Floki.parse_document(html) do
      {:ok, document} ->
        frame_urls =
          document
          |> Floki.find("frame, iframe")
          |> Enum.map(fn elem ->
            case Floki.attribute(elem, "src") do
              [src | _] -> resolve_url(src, base_uri)
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, frame_urls}

      {:error, reason} ->
        {:error, {:parse_failed, reason}}
    end
  end

  defp discover_content_pages(frame_urls, base_uri, max_pages) do
    # Fetch each frame and extract links to actual content pages
    content_urls =
      frame_urls
      |> Enum.flat_map(fn url ->
        case fetch_and_extract_links(url, base_uri) do
          {:ok, links} -> links
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.take(max_pages)

    {:ok, content_urls}
  end

  defp fetch_and_extract_links(url, base_uri) do
    case Req.get(url, receive_timeout: 10_000, redirect: true) do
      {:ok, %{status: 200, body: body}} ->
        extract_doc_links(body, base_uri)

      {:ok, %{status: status}} ->
        Logger.warning("Frame URL #{url} returned status #{status}")
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Failed to fetch frame #{url}: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp extract_doc_links(html, base_uri) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        links =
          document
          |> Floki.find("a[href]")
          |> Enum.map(fn elem ->
            case Floki.attribute(elem, "href") do
              [href | _] -> href
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&valid_doc_link?/1)
          |> Enum.map(&resolve_url(&1, base_uri))
          |> Enum.reject(&is_nil/1)

        {:ok, links}

      _ ->
        {:ok, []}
    end
  end

  defp valid_doc_link?(href) do
    # Filter to documentation pages, not external links or anchors
    cond do
      String.starts_with?(href, "#") -> false
      String.starts_with?(href, "javascript:") -> false
      String.starts_with?(href, "http://") -> false
      String.starts_with?(href, "https://") -> false
      String.ends_with?(href, ".html") -> true
      String.ends_with?(href, ".htm") -> true
      String.contains?(href, "/") and not String.contains?(href, "..") -> true
      true -> false
    end
  end

  defp resolve_url(href, base_uri) do
    # Handle relative URLs
    case URI.parse(href) do
      %URI{scheme: nil, host: nil} = _relative ->
        # Relative URL - resolve against base
        base_path = Path.dirname(base_uri.path || "/")
        resolved_path = Path.join(base_path, href) |> Path.expand()

        URI.to_string(%{base_uri | path: resolved_path, query: nil, fragment: nil})

      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Absolute URL - check if same domain
        parsed = URI.parse(href)

        if parsed.host == base_uri.host do
          href
        else
          nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_javadoc_content(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Try different Javadoc content selectors
        content =
          try_selectors(document, [
            # Modern Javadoc (11+)
            ".class-description",
            ".member-summary",
            ".detail",
            ".block",
            # Classic Javadoc
            ".contentContainer",
            ".description",
            "#class-description",
            # Fallback
            "body"
          ])

        # Clean up the content
        cleaned =
          content
          |> remove_navigation()
          |> Floki.text(sep: "\n")
          |> String.trim()
          |> collapse_whitespace()

        {:ok, cleaned}

      {:error, reason} ->
        {:error, {:parse_failed, reason}}
    end
  end

  defp try_selectors(document, [selector | rest]) do
    case Floki.find(document, selector) do
      [] -> try_selectors(document, rest)
      found -> found
    end
  end

  defp try_selectors(document, []), do: Floki.find(document, "body")

  defp remove_navigation(elements) do
    # Remove navigation elements
    nav_selectors = [
      "nav",
      ".nav",
      ".navbar",
      "#navbar",
      ".skipNav",
      ".topNav",
      ".bottomNav",
      ".header",
      ".footer",
      "script",
      "style",
      "noscript"
    ]

    Enum.reduce(nav_selectors, elements, fn selector, acc ->
      Floki.filter_out(acc, selector)
    end)
  end

  defp collapse_whitespace(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
  end
end

