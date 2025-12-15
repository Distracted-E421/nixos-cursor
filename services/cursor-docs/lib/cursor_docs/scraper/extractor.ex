defmodule CursorDocs.Scraper.Extractor do
  @moduledoc """
  HTML content extraction and processing.

  Extracts clean text content from HTML pages, removing boilerplate
  (navigation, footers, scripts) and extracting main content.
  """

  require Logger

  @doc """
  Extract content from HTML string.
  """
  @spec extract_from_html(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def extract_from_html(html, url) do
    try do
      {:ok, document} = Floki.parse_document(html)

      # Remove unwanted elements
      document =
        document
        |> Floki.filter_out("script")
        |> Floki.filter_out("style")
        |> Floki.filter_out("nav")
        |> Floki.filter_out("footer")
        |> Floki.filter_out("header")
        |> Floki.filter_out("aside")
        |> Floki.filter_out("noscript")
        |> Floki.filter_out(".sidebar")
        |> Floki.filter_out(".navigation")
        |> Floki.filter_out(".toc")
        |> Floki.filter_out("[role=navigation]")

      # Extract title
      title =
        case Floki.find(document, "title") do
          [] -> url
          elements -> elements |> Floki.text() |> String.trim()
        end

      title = if title == "", do: url, else: title

      # Extract description
      description =
        case Floki.find(document, "meta[name=description]") do
          [] -> ""
          elements ->
            elements
            |> Floki.attribute("content")
            |> List.first()
            |> Kernel.||("")
            |> String.trim()
        end

      # Get main content - prefer main/article, fallback to body
      main_content =
        case Floki.find(document, "main, article, [role=main]") do
          [] -> document
          elements -> elements
        end

      # Extract text
      text =
        main_content
        |> Floki.text(sep: "\n")
        |> String.trim()
        |> clean_text()

      # Extract links for crawling
      links =
        document
        |> Floki.find("a[href]")
        |> Floki.attribute("href")
        |> Enum.map(&resolve_url(&1, url))
        |> Enum.filter(&valid_doc_url?/1)
        |> Enum.uniq()

      {:ok, %{
        title: title,
        description: description,
        content: text,
        links: links,
        url: url
      }}
    rescue
      e ->
        Logger.error("Extraction failed for #{url}: #{inspect(e)}")
        {:error, e}
    end
  end

  # Clean up extracted text
  defp clean_text(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")  # Collapse multiple newlines
    |> String.replace(~r/ {2,}/, " ")       # Collapse multiple spaces
    |> String.replace(~r/\t+/, " ")         # Replace tabs
  end

  # Resolve relative URLs to absolute
  defp resolve_url(href, base_url) when is_binary(href) do
    href = String.trim(href)

    cond do
      String.starts_with?(href, "http://") or String.starts_with?(href, "https://") ->
        href

      String.starts_with?(href, "//") ->
        "https:" <> href

      String.starts_with?(href, "/") ->
        base_uri = URI.parse(base_url)
        "#{base_uri.scheme}://#{base_uri.host}#{href}"

      String.starts_with?(href, "#") ->
        nil  # Skip anchors

      String.starts_with?(href, "mailto:") or String.starts_with?(href, "javascript:") ->
        nil

      true ->
        # Relative path
        base_uri = URI.parse(base_url)
        base_path = base_uri.path || "/"
        dir = Path.dirname(base_path)
        "#{base_uri.scheme}://#{base_uri.host}#{Path.join(dir, href)}"
    end
  end

  defp resolve_url(_, _), do: nil

  # Filter to only valid documentation URLs
  defp valid_doc_url?(nil), do: false
  defp valid_doc_url?(url) when is_binary(url) do
    uri = URI.parse(url)

    # Must have scheme and host
    uri.scheme in ["http", "https"] and
      is_binary(uri.host) and
      uri.host != "" and
      # Skip non-doc extensions
      not String.match?(url, ~r/\.(png|jpg|jpeg|gif|svg|pdf|zip|tar|gz|mp4|mp3|wav)$/i) and
      # Skip common non-content paths
      not String.contains?(url, ["/login", "/signup", "/auth", "/api/", "/_"])
  end

  defp valid_doc_url?(_), do: false
end
