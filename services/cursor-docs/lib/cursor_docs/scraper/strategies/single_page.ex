defmodule CursorDocs.Scraper.Strategies.SinglePage do
  @moduledoc """
  Default crawler strategy for single-page documentation.

  Used when:
  - URL points to a single documentation page
  - No frameset detected
  - No sitemap available
  - User explicitly requested single-page mode

  This is the simplest strategy - just fetch and process the one URL.
  """

  @behaviour CursorDocs.Scraper.CrawlerStrategy

  @impl true
  def detect(_url, _html), do: :single_page

  @impl true
  def discover_urls(url, _html, _opts \\ []) do
    # Single page - just return the URL itself
    {:ok, [url]}
  end

  @impl true
  def process_content(_url, html, _opts \\ []) do
    # Use the existing extractor logic
    {:ok, html}
  end
end

