defmodule CursorDocs.Scraper.Strategies.Sitemap do
  @moduledoc """
  Crawler strategy using XML sitemap for URL discovery.

  Sitemaps are the most efficient way to discover all pages:
  - Single request to get all URLs
  - Respects site owner's intentions
  - Often includes lastmod for freshness checking

  Sitemap format:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
      <loc>https://example.com/page1</loc>
      <lastmod>2025-01-01</lastmod>
    </url>
    ...
  </urlset>
  ```

  Also handles sitemap index files:
  ```xml
  <sitemapindex>
    <sitemap>
      <loc>https://example.com/sitemap-docs.xml</loc>
    </sitemap>
  </sitemapindex>
  ```
  """

  @behaviour CursorDocs.Scraper.CrawlerStrategy

  require Logger

  @impl true
  def detect(_url, _html), do: :sitemap

  @impl true
  def discover_urls(base_url, _html, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 500)
    base_uri = URI.parse(base_url)

    # Try to find sitemap
    sitemap_url = find_sitemap_url(base_uri)

    case sitemap_url do
      nil ->
        Logger.warning("No sitemap found for #{base_url}")
        {:ok, [base_url]}

      url ->
        Logger.info("Sitemap strategy: using #{url}")

        case fetch_and_parse_sitemap(url, max_pages) do
          {:ok, urls} ->
            Logger.info("Sitemap strategy: found #{length(urls)} URLs")
            {:ok, urls}

          {:error, reason} ->
            Logger.warning("Failed to parse sitemap: #{inspect(reason)}")
            {:ok, [base_url]}
        end
    end
  end

  @impl true
  def process_content(_url, html, _opts \\ []) do
    {:ok, html}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp find_sitemap_url(base_uri) do
    # Common sitemap locations
    candidates = [
      "#{base_uri.scheme}://#{base_uri.host}/sitemap.xml",
      "#{base_uri.scheme}://#{base_uri.host}/sitemap_index.xml",
      "#{base_uri.scheme}://#{base_uri.host}/sitemap/sitemap.xml"
    ]

    Enum.find(candidates, fn url ->
      case Req.head(url, receive_timeout: 5_000) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
    end)
  rescue
    _ -> nil
  end

  defp fetch_and_parse_sitemap(url, max_pages) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        parse_sitemap(body, url, max_pages)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_sitemap(xml, _sitemap_url, max_pages) do
    case parse_xml(xml) do
      {:ok, {:sitemapindex, sitemaps}} ->
        # Sitemap index - fetch child sitemaps
        urls =
          sitemaps
          |> Enum.flat_map(fn child_url ->
            case fetch_and_parse_sitemap(child_url, max_pages) do
              {:ok, child_urls} -> child_urls
              _ -> []
            end
          end)
          |> Enum.take(max_pages)

        {:ok, urls}

      {:ok, {:urlset, urls}} ->
        {:ok, Enum.take(urls, max_pages)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:parse_error, e}}
  end

  defp parse_xml(xml) do
    # Simple XML parsing for sitemap format
    cond do
      String.contains?(xml, "<sitemapindex") ->
        urls = extract_locs(xml, "sitemap")
        {:ok, {:sitemapindex, urls}}

      String.contains?(xml, "<urlset") ->
        urls = extract_locs(xml, "url")
        {:ok, {:urlset, urls}}

      true ->
        {:error, :unknown_format}
    end
  end

  defp extract_locs(xml, container_tag) do
    # Extract <loc> elements from within container tags
    # Using simple regex since sitemaps have consistent format
    pattern = ~r/<#{container_tag}[^>]*>.*?<loc>([^<]+)<\/loc>.*?<\/#{container_tag}>/s

    Regex.scan(pattern, xml, capture: :all_but_first)
    |> Enum.map(fn [url] -> String.trim(url) end)
    |> Enum.filter(&valid_url?/1)
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end
end

