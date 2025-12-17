defmodule CursorDocs.Scraper.CrawlerStrategy do
  @moduledoc """
  Behaviour for different crawling strategies.

  Supports:
  - Single page (default)
  - Frameset (Javadoc-style)
  - Sitemap (XML sitemap discovery)
  - Link following (recursive crawl)

  Each strategy knows how to discover and process URLs for a particular
  documentation format.
  """

  @type url :: String.t()
  @type html :: String.t()
  @type crawl_result :: {:ok, list(url())} | {:error, term()}
  @type doc_type :: :single_page | :frameset | :sitemap | :link_follow | :unknown

  @doc """
  Detect the documentation type from initial page content.
  """
  @callback detect(url(), html()) :: doc_type()

  @doc """
  Discover all URLs to crawl from the initial page.
  Returns list of URLs to fetch and process.
  """
  @callback discover_urls(url(), html(), keyword()) :: crawl_result()

  @doc """
  Process fetched content and extract documentation.
  May filter out navigation, boilerplate, etc.
  """
  @callback process_content(url(), html(), keyword()) :: {:ok, String.t()} | {:error, term()}

  # ============================================================================
  # Detection Logic
  # ============================================================================

  @doc """
  Auto-detect the best crawling strategy for a URL.
  """
  def detect_strategy(url, html) do
    cond do
      frameset?(html) -> :frameset
      has_sitemap?(url) -> :sitemap
      api_docs?(html) -> :link_follow
      true -> :single_page
    end
  end

  @doc """
  Get the module implementing a strategy.
  """
  def strategy_module(:single_page), do: CursorDocs.Scraper.Strategies.SinglePage
  def strategy_module(:frameset), do: CursorDocs.Scraper.Strategies.Frameset
  def strategy_module(:sitemap), do: CursorDocs.Scraper.Strategies.Sitemap
  def strategy_module(:link_follow), do: CursorDocs.Scraper.Strategies.LinkFollow

  # ============================================================================
  # Detection Helpers
  # ============================================================================

  defp frameset?(html) do
    html
    |> String.downcase()
    |> then(fn h ->
      String.contains?(h, "<frameset") or String.contains?(h, "<frame ")
    end)
  end

  defp has_sitemap?(url) do
    # Check if sitemap.xml exists at root
    uri = URI.parse(url)
    sitemap_url = "#{uri.scheme}://#{uri.host}/sitemap.xml"

    case Req.head(sitemap_url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp api_docs?(html) do
    # Heuristic: looks like API documentation (Javadoc, Doxygen, etc.)
    html_lower = String.downcase(html)

    api_signals = [
      "class-summary",
      "method-summary",
      "package-summary",
      "api-reference",
      "class=\"method\"",
      "class=\"type\"",
      "apidocs",
      "javadoc"
    ]

    Enum.any?(api_signals, &String.contains?(html_lower, &1))
  end
end

