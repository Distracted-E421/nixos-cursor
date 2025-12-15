defmodule CursorDocs.Scraper.Extractor do
  @moduledoc """
  Content extraction from HTML pages.

  Handles:
  - Main content identification (removes nav, footer, sidebar, ads)
  - Metadata extraction (title, description)
  - Link discovery for crawling
  - Text cleaning and normalization
  """

  require Logger

  @doc """
  Extract content from a Playwright page.

  Returns a map with:
  - `:title` - Page title
  - `:description` - Meta description
  - `:content` - Clean text content
  - `:links` - Internal documentation links
  - `:code_blocks` - Extracted code examples
  """
  @spec extract(Playwright.Page.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def extract(page, base_url) do
    with {:ok, html} <- Playwright.Page.content(page),
         {:ok, document} <- Floki.parse_document(html) do
      title = extract_title(document)
      description = extract_description(document)
      content = extract_main_content(document)
      links = extract_links(document, base_url)
      code_blocks = extract_code_blocks(document)

      {:ok, %{
        title: title,
        description: description,
        content: content,
        links: links,
        code_blocks: code_blocks,
        word_count: word_count(content)
      }}
    end
  end

  @doc """
  Extract content from raw HTML string.
  """
  @spec extract_from_html(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def extract_from_html(html, base_url) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        {:ok, %{
          title: extract_title(document),
          description: extract_description(document),
          content: extract_main_content(document),
          links: extract_links(document, base_url),
          code_blocks: extract_code_blocks(document),
          word_count: word_count(extract_main_content(document))
        }}

      error ->
        error
    end
  end

  # Private extraction functions

  defp extract_title(document) do
    # Try multiple selectors in order of preference
    selectors = [
      "h1",
      "title",
      ~s{meta[property="og:title"]},
      ".page-title",
      ".article-title"
    ]

    Enum.find_value(selectors, "Untitled", fn selector ->
      case selector do
        "meta" <> _ ->
          document
          |> Floki.find(selector)
          |> Floki.attribute("content")
          |> List.first()

        _ ->
          document
          |> Floki.find(selector)
          |> Floki.text()
          |> case do
            "" -> nil
            text -> String.trim(text)
          end
      end
    end)
  end

  defp extract_description(document) do
    selectors = [
      ~s{meta[name="description"]},
      ~s{meta[property="og:description"]}
    ]

    Enum.find_value(selectors, "", fn selector ->
      document
      |> Floki.find(selector)
      |> Floki.attribute("content")
      |> List.first()
    end)
    |> Kernel.||("")
    |> String.trim()
    |> String.slice(0, 500)
  end

  defp extract_main_content(document) do
    # Remove unwanted elements
    document
    |> remove_elements([
      "script",
      "style",
      "nav",
      "footer",
      "header",
      "aside",
      ".sidebar",
      ".navigation",
      ".nav",
      ".footer",
      ".header",
      ".menu",
      ".ads",
      ".advertisement",
      ".cookie-banner",
      ".cookie-notice",
      "#cookie-consent",
      ".social-share",
      ".comments"
    ])
    |> find_main_content()
    |> Floki.text(sep: "\n")
    |> clean_text()
  end

  defp remove_elements(document, selectors) do
    Enum.reduce(selectors, document, fn selector, doc ->
      Floki.filter_out(doc, selector)
    end)
  end

  defp find_main_content(document) do
    # Try to find main content area
    main_selectors = [
      "main",
      "article",
      ~s{[role="main"]},
      ".content",
      ".main-content",
      ".article-content",
      ".documentation",
      ".docs-content",
      "#content",
      "#main"
    ]

    Enum.find_value(main_selectors, document, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        found -> found
      end
    end)
  end

  defp extract_links(document, base_url) do
    base_uri = URI.parse(base_url)

    document
    |> Floki.find("a")
    |> Floki.attribute("href")
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&resolve_url(&1, base_uri))
    |> Enum.filter(&is_internal_doc_link?(&1, base_uri))
    |> Enum.uniq()
  end

  defp resolve_url(href, base_uri) do
    case URI.parse(href) do
      %URI{host: nil, path: path} when is_binary(path) ->
        # Relative URL
        URI.merge(base_uri, href) |> URI.to_string()

      %URI{host: host} when is_binary(host) ->
        # Absolute URL
        href

      _ ->
        nil
    end
  end

  defp is_internal_doc_link?(nil, _base_uri), do: false
  defp is_internal_doc_link?(url, base_uri) do
    uri = URI.parse(url)

    # Same host
    uri.host == base_uri.host &&
      # Not an anchor-only link
      !is_nil(uri.path) &&
      # Not a file download
      !String.match?(uri.path || "", ~r/\.(pdf|zip|tar|gz|exe|dmg|pkg)$/i) &&
      # Not a media file
      !String.match?(uri.path || "", ~r/\.(jpg|jpeg|png|gif|svg|webp|mp4|webm)$/i)
  end

  defp extract_code_blocks(document) do
    document
    |> Floki.find("pre code, pre, code")
    |> Enum.map(fn element ->
      language = detect_language(element)
      code = Floki.text(element) |> String.trim()

      %{
        language: language,
        code: code
      }
    end)
    |> Enum.reject(fn %{code: code} -> String.length(code) < 10 end)
  end

  defp detect_language(element) do
    # Check class for language hint
    classes =
      element
      |> Floki.attribute("class")
      |> List.first()
      |> Kernel.||("")

    cond do
      String.contains?(classes, "language-") ->
        classes
        |> String.split()
        |> Enum.find(&String.starts_with?(&1, "language-"))
        |> String.replace_prefix("language-", "")

      String.contains?(classes, "highlight-") ->
        classes
        |> String.split()
        |> Enum.find(&String.starts_with?(&1, "highlight-"))
        |> String.replace_prefix("highlight-", "")

      true ->
        nil
    end
  end

  defp clean_text(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/^\s+$/m, "")
    |> String.trim()
  end

  defp word_count(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.count()
  end
end
