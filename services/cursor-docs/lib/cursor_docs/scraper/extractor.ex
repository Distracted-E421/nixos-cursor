defmodule CursorDocs.Scraper.Extractor do
  @moduledoc """
  HTML content extraction and processing with security validation.

  Features:
  - Extracts clean text from HTML, removing boilerplate
  - Detects hidden content and prompt injection attempts
  - Validates content quality before indexing
  - Produces AI-optimized semantic chunks
  """

  require Logger

  alias CursorDocs.Scraper.ContentValidator

  @doc """
  Extract and validate content from HTML string.
  Returns validated, security-checked content ready for indexing.
  """
  @spec extract_from_html(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def extract_from_html(html, url) do
    try do
      # Step 1: Security checks on raw HTML
      {security_status, html} = run_security_checks(html, url)

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
        |> Floki.filter_out("[hidden]")
        |> Floki.filter_out("[aria-hidden=true]")

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

      # Step 2: Quality validation
      case ContentValidator.validate_quality(text) do
        {:valid, quality_score} ->
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
            url: url,
            quality_score: quality_score,
            security_status: security_status
          }}

        {:invalid, reasons} ->
          Logger.warning("Quality check failed for #{url}: #{inspect(reasons)}")
          {:error, {:quality_failed, reasons}}
      end
    rescue
      e ->
        Logger.error("Extraction failed for #{url}: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Extract and chunk content with full security and quality pipeline.
  """
  @spec extract_and_chunk(String.t(), String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def extract_and_chunk(html, url, opts \\ []) do
    source_name = Keyword.get(opts, :name, extract_source_name(url))

    case extract_from_html(html, url) do
      {:ok, extracted} ->
        # Create semantic chunks
        chunks = ContentValidator.semantic_chunk(extracted.content, opts)

        formatted_chunks =
          Enum.map(chunks, fn chunk ->
            %{
              content: chunk.content,
              title: extracted.title,
              url: url,
              source_name: source_name,
              position: chunk.position,
              total_chunks: chunk.total,
              quality_score: extracted.quality_score,
              security_status: extracted.security_status,
              char_count: chunk.char_count,
              word_count: chunk.word_count,
              has_code: chunk.has_code
            }
          end)

        {:ok, %{chunks: formatted_chunks, links: extracted.links}}

      error ->
        error
    end
  end

  # Run security checks and return sanitized HTML
  defp run_security_checks(html, url) do
    # Check for hidden content
    hidden_result = ContentValidator.detect_hidden_content(html)
    html = case hidden_result do
      {:ok, clean} -> clean
      {:suspicious, reasons, clean} ->
        Logger.warning("Hidden content in #{url}: #{inspect(reasons)}")
        clean
    end

    # Check for prompt injection
    injection_result = ContentValidator.detect_prompt_injection(html)
    case injection_result do
      {:safe, _} ->
        {:clean, html}

      {:suspicious, threats, _} ->
        Logger.warning("Suspicious patterns in #{url}: #{inspect(threats)}")
        {:suspicious, html}

      {:dangerous, threats, sanitized} ->
        Logger.error("Prompt injection detected in #{url}: #{inspect(threats)}")
        {:sanitized, sanitized}
    end
  end

  defp extract_source_name(url) do
    uri = URI.parse(url)
    uri.host || "Unknown"
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
