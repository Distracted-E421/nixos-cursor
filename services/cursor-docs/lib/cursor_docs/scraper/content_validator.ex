defmodule CursorDocs.Scraper.ContentValidator do
  @moduledoc """
  Content validation, sanitization, and security checks for scraped documentation.

  ## Security Checks

  1. **Hidden Text Detection** - Finds CSS-hidden content, white-on-white text,
     zero-height elements that could contain prompt injections invisible to humans

  2. **Prompt Injection Detection** - Scans for common injection patterns like
     "ignore previous instructions", base64-encoded prompts, instruction override attempts

  3. **Quality Validation** - Ensures content is actual documentation, not error pages,
     login walls, or garbage

  ## AI Optimization

  1. **Semantic Chunking** - Splits content at natural boundaries (headings, paragraphs)
     rather than arbitrary character limits

  2. **Context Preservation** - Maintains enough context for AI comprehension without
     overwhelming token budgets

  3. **Metadata Enrichment** - Adds source info, chunk position, and semantic tags
     for better retrieval
  """

  require Logger

  # ============================================================================
  # SECURITY: Hidden Text Detection
  # ============================================================================

  @doc """
  Detects hidden text that could contain prompt injections.
  Returns {:ok, clean_html} or {:suspicious, reasons, clean_html}
  """
  def detect_hidden_content(html) when is_binary(html) do
    reasons = []

    # Check for CSS hiding techniques
    reasons = reasons ++ detect_css_hidden(html)

    # Check for invisible text (same color as background)
    reasons = reasons ++ detect_invisible_text(html)

    # Check for zero-dimension elements
    reasons = reasons ++ detect_zero_dimension(html)

    # Check for off-screen positioning
    reasons = reasons ++ detect_offscreen(html)

    if Enum.empty?(reasons) do
      {:ok, html}
    else
      Logger.warning("Hidden content detected: #{inspect(reasons)}")
      {:suspicious, reasons, remove_hidden_elements(html)}
    end
  end

  defp detect_css_hidden(html) do
    patterns = [
      {~r/display\s*:\s*none/i, "display:none"},
      {~r/visibility\s*:\s*hidden/i, "visibility:hidden"},
      {~r/opacity\s*:\s*0[^.]|opacity\s*:\s*0;/i, "opacity:0"},
      {~r/font-size\s*:\s*0/i, "font-size:0"},
      {~r/height\s*:\s*0[^.]|height\s*:\s*0;/i, "height:0"},
      {~r/width\s*:\s*0[^.]|width\s*:\s*0;/i, "width:0"},
      {~r/overflow\s*:\s*hidden.*height\s*:\s*0/is, "overflow:hidden+height:0"}
    ]

    Enum.reduce(patterns, [], fn {pattern, name}, acc ->
      if Regex.match?(pattern, html), do: [name | acc], else: acc
    end)
  end

  defp detect_invisible_text(html) do
    # White text on white background patterns
    patterns = [
      {~r/color\s*:\s*#fff.*background[^:]*:\s*#fff/is, "white-on-white"},
      {~r/color\s*:\s*white.*background[^:]*:\s*white/is, "white-on-white"},
      {~r/color\s*:\s*transparent/i, "transparent-text"},
      {~r/color\s*:\s*rgba\s*\([^)]*,\s*0\s*\)/i, "rgba-transparent"}
    ]

    Enum.reduce(patterns, [], fn {pattern, name}, acc ->
      if Regex.match?(pattern, html), do: [name | acc], else: acc
    end)
  end

  defp detect_zero_dimension(html) do
    if Regex.match?(~r/<[^>]+style\s*=\s*"[^"]*(?:width|height)\s*:\s*0[^0-9]/i, html) do
      ["zero-dimension-element"]
    else
      []
    end
  end

  defp detect_offscreen(html) do
    patterns = [
      {~r/position\s*:\s*absolute.*(?:left|top)\s*:\s*-\d{4,}/is, "offscreen-positioning"},
      {~r/text-indent\s*:\s*-\d{4,}/i, "negative-text-indent"},
      {~r/margin-left\s*:\s*-\d{4,}/i, "negative-margin"}
    ]

    Enum.reduce(patterns, [], fn {pattern, name}, acc ->
      if Regex.match?(pattern, html), do: [name | acc], else: acc
    end)
  end

  defp remove_hidden_elements(html) do
    # Remove elements with hiding styles
    html
    |> String.replace(~r/<[^>]+style\s*=\s*"[^"]*display\s*:\s*none[^"]*"[^>]*>.*?<\/[^>]+>/is, "")
    |> String.replace(~r/<[^>]+style\s*=\s*"[^"]*visibility\s*:\s*hidden[^"]*"[^>]*>.*?<\/[^>]+>/is, "")
    |> String.replace(~r/<[^>]+hidden[^>]*>.*?<\/[^>]+>/is, "")
  end

  # ============================================================================
  # SECURITY: Prompt Injection Detection
  # ============================================================================

  @injection_patterns [
    # Direct instruction overrides
    {~r/ignore\s+(?:all\s+)?previous\s+instructions?/i, :instruction_override, :high},
    {~r/disregard\s+(?:all\s+)?(?:previous|prior|above)\s+(?:instructions?|context)/i, :instruction_override, :high},
    {~r/forget\s+(?:everything|all|what)\s+(?:you\s+)?(?:know|learned|were\s+told)/i, :instruction_override, :high},

    # Role manipulation
    {~r/you\s+are\s+now\s+(?:a|an)\s+/i, :role_manipulation, :high},
    {~r/pretend\s+(?:to\s+be|you\s+are)/i, :role_manipulation, :medium},
    {~r/act\s+as\s+(?:if\s+you\s+are|a|an)/i, :role_manipulation, :medium},

    # System prompt extraction
    {~r/(?:print|show|reveal|display)\s+(?:your\s+)?(?:system\s+)?(?:prompt|instructions?)/i, :prompt_extraction, :high},
    {~r/what\s+(?:are\s+)?your\s+(?:system\s+)?instructions?/i, :prompt_extraction, :medium},

    # Output manipulation
    {~r/respond\s+(?:only\s+)?with\s+(?:yes|no|true|false)/i, :output_manipulation, :medium},
    {~r/always\s+(?:say|respond|answer)/i, :output_manipulation, :low},

    # Encoding bypasses (only flag suspicious patterns, not common entities)
    {~r/base64\s*:\s*[A-Za-z0-9+\/=]{50,}/i, :encoded_payload, :high},
    {~r/\\x[0-9a-f]{2}(?:\\x[0-9a-f]{2}){5,}/i, :hex_encoding, :medium},
    # Skip common HTML entities (39=', 34=", 60=<, 62=>, 38=&, 160=nbsp)
    {~r/&#x?(?![0-9]{1,3};)[0-9a-f]{4,};/i, :html_encoding, :low},

    # Delimiter attacks
    {~r/<\|(?:system|user|assistant)\|>/i, :delimiter_injection, :high},
    {~r/\[INST\]|\[\/INST\]/i, :delimiter_injection, :high},
    {~r/###\s*(?:System|User|Assistant)/i, :delimiter_injection, :medium},

    # Jailbreak patterns
    {~r/DAN\s+(?:mode|prompt)/i, :jailbreak, :high},
    {~r/developer\s+mode\s+enabled/i, :jailbreak, :high},
    {~r/bypass\s+(?:safety|content|filter)/i, :jailbreak, :high}
  ]

  @doc """
  Scans content for potential prompt injection attacks.
  Returns {:safe, content} or {:dangerous, threats, sanitized_content}
  """
  def detect_prompt_injection(content) when is_binary(content) do
    threats =
      @injection_patterns
      |> Enum.reduce([], fn {pattern, type, severity}, acc ->
        if Regex.match?(pattern, content) do
          matches = Regex.scan(pattern, content) |> Enum.map(&List.first/1)
          [{type, severity, matches} | acc]
        else
          acc
        end
      end)

    high_threats = Enum.filter(threats, fn {_, severity, _} -> severity == :high end)

    cond do
      length(high_threats) > 0 ->
        Logger.error("High-severity prompt injection detected: #{inspect(high_threats)}")
        {:dangerous, threats, sanitize_injections(content)}

      length(threats) > 0 ->
        Logger.warning("Potential prompt injection patterns: #{inspect(threats)}")
        {:suspicious, threats, content}

      true ->
        {:safe, content}
    end
  end

  defp sanitize_injections(content) do
    # Remove or neutralize dangerous patterns
    content
    |> String.replace(~r/ignore\s+(?:all\s+)?previous\s+instructions?/i, "[REDACTED]")
    |> String.replace(~r/you\s+are\s+now\s+(?:a|an)\s+/i, "[REDACTED] ")
    |> String.replace(~r/<\|(?:system|user|assistant)\|>/i, "[DELIMITER]")
    |> String.replace(~r/\[INST\]|\[\/INST\]/i, "[DELIMITER]")
  end

  # ============================================================================
  # QUALITY: Content Validation
  # ============================================================================

  @min_content_length 100
  @max_boilerplate_ratio 0.7
  @min_text_density 0.1

  @doc """
  Validates that content is actual documentation, not junk.
  Returns {:valid, quality_score} or {:invalid, reasons}
  """
  def validate_quality(content, opts \\ []) when is_binary(content) do
    min_length = Keyword.get(opts, :min_length, @min_content_length)

    checks = [
      check_length(content, min_length),
      check_not_error_page(content),
      check_not_login_wall(content),
      check_text_density(content),
      check_not_mostly_boilerplate(content),
      check_has_semantic_content(content)
    ]

    failures = Enum.filter(checks, fn {status, _} -> status == :fail end)

    if Enum.empty?(failures) do
      score = calculate_quality_score(content, checks)
      {:valid, score}
    else
      reasons = Enum.map(failures, fn {:fail, reason} -> reason end)
      {:invalid, reasons}
    end
  end

  defp check_length(content, min_length) do
    if String.length(content) >= min_length do
      {:pass, :length}
    else
      {:fail, {:too_short, String.length(content), min_length}}
    end
  end

  defp check_not_error_page(content) do
    error_patterns = [
      ~r/404\s*[-–—]\s*(?:page\s+)?not\s+found/i,
      ~r/403\s*[-–—]\s*forbidden/i,
      ~r/500\s*[-–—]\s*internal\s+server\s+error/i,
      ~r/page\s+(?:not\s+found|doesn'?t\s+exist)/i,
      ~r/this\s+page\s+(?:is\s+)?(?:no\s+longer|not)\s+available/i,
      ~r/error\s+loading\s+page/i
    ]

    if Enum.any?(error_patterns, &Regex.match?(&1, content)) do
      {:fail, :error_page}
    else
      {:pass, :not_error}
    end
  end

  defp check_not_login_wall(content) do
    login_patterns = [
      ~r/(?:sign|log)\s*in\s+(?:to\s+)?(?:continue|access|view)/i,
      ~r/(?:create|sign\s+up\s+for)\s+(?:an?\s+)?account\s+to/i,
      ~r/authentication\s+required/i,
      ~r/please\s+(?:sign|log)\s*in/i,
      ~r/you\s+must\s+be\s+(?:logged|signed)\s*in/i
    ]

    if Enum.any?(login_patterns, &Regex.match?(&1, content)) do
      {:fail, :login_required}
    else
      {:pass, :no_login_wall}
    end
  end

  defp check_text_density(content) do
    # Ratio of actual text to total content
    text_only = String.replace(content, ~r/<[^>]+>/, "")
    text_only = String.replace(text_only, ~r/\s+/, " ")

    density = String.length(text_only) / max(String.length(content), 1)

    if density >= @min_text_density do
      {:pass, {:text_density, density}}
    else
      {:fail, {:low_text_density, density}}
    end
  end

  defp check_not_mostly_boilerplate(content) do
    # Common boilerplate patterns
    boilerplate_patterns = [
      ~r/copyright\s+©?\s*\d{4}/i,
      ~r/all\s+rights\s+reserved/i,
      ~r/privacy\s+policy/i,
      ~r/terms\s+(?:of\s+)?(?:service|use)/i,
      ~r/cookie\s+(?:policy|notice|consent)/i,
      ~r/subscribe\s+to\s+(?:our\s+)?newsletter/i
    ]

    boilerplate_matches = Enum.count(boilerplate_patterns, &Regex.match?(&1, content))
    total_sentences = length(String.split(content, ~r/[.!?]+/))

    ratio = boilerplate_matches / max(total_sentences, 1)

    if ratio <= @max_boilerplate_ratio do
      {:pass, {:boilerplate_ratio, ratio}}
    else
      {:fail, {:too_much_boilerplate, ratio}}
    end
  end

  defp check_has_semantic_content(content) do
    # Look for documentation-like patterns
    doc_patterns = [
      ~r/(?:function|method|class|module|package)\s+\w+/i,
      ~r/(?:parameter|argument|return|example)s?\s*:/i,
      ~r/```[\s\S]*?```/,  # Code blocks
      ~r/`[^`]+`/,         # Inline code
      ~r/##?\s+\w+/,       # Headings
      ~r/(?:note|warning|tip|important):/i
    ]

    matches = Enum.count(doc_patterns, &Regex.match?(&1, content))

    if matches >= 2 do
      {:pass, {:semantic_signals, matches}}
    else
      {:fail, {:lacks_documentation_structure, matches}}
    end
  end

  defp calculate_quality_score(content, checks) do
    base_score = 0.5

    # Bonus for length
    length_bonus = min(String.length(content) / 5000, 0.2)

    # Bonus for semantic signals
    semantic_bonus =
      case Enum.find(checks, fn {_, tag} -> match?({:semantic_signals, _}, tag) end) do
        {:pass, {:semantic_signals, n}} -> min(n * 0.05, 0.2)
        _ -> 0
      end

    # Bonus for good text density
    density_bonus =
      case Enum.find(checks, fn {_, tag} -> match?({:text_density, _}, tag) end) do
        {:pass, {:text_density, d}} -> d * 0.1
        _ -> 0
      end

    Float.round(base_score + length_bonus + semantic_bonus + density_bonus, 2)
  end

  # ============================================================================
  # AI OPTIMIZATION: Semantic Chunking
  # ============================================================================

  @default_chunk_size 1500      # Target chars per chunk
  @max_chunk_size 3000          # Hard limit
  @min_chunk_size 200           # Don't create tiny chunks
  @overlap_size 100             # Overlap between chunks for context

  @doc """
  Splits content into AI-optimized chunks with semantic awareness.

  Options:
    - chunk_size: Target size in characters (default: 1500)
    - overlap: Characters to overlap between chunks (default: 100)
    - preserve_code: Keep code blocks intact (default: true)
  """
  def semantic_chunk(content, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @overlap_size)
    preserve_code = Keyword.get(opts, :preserve_code, true)

    content
    |> split_by_semantic_boundaries(preserve_code)
    |> merge_small_chunks(@min_chunk_size)
    |> split_large_chunks(chunk_size, @max_chunk_size)
    |> add_overlap(overlap)
    |> add_chunk_metadata()
  end

  defp split_by_semantic_boundaries(content, preserve_code) do
    # First, extract and protect code blocks
    {content, code_blocks} = if preserve_code do
      extract_code_blocks(content)
    else
      {content, %{}}
    end

    # Split on semantic boundaries (headers, paragraphs, lists)
    chunks =
      content
      |> String.split(~r/(?=^\#{1,3}\s+|\n\n+)/m)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Restore code blocks
    if preserve_code do
      restore_code_blocks(chunks, code_blocks)
    else
      chunks
    end
  end

  defp extract_code_blocks(content) do
    # Replace code blocks with placeholders
    {result, blocks} =
      Regex.scan(~r/```[\s\S]*?```/, content)
      |> Enum.with_index()
      |> Enum.reduce({content, %{}}, fn {[block], idx}, {text, blocks} ->
        placeholder = "[[CODE_BLOCK_#{idx}]]"
        {String.replace(text, block, placeholder, global: false), Map.put(blocks, placeholder, block)}
      end)

    {result, blocks}
  end

  defp restore_code_blocks(chunks, blocks) do
    Enum.map(chunks, fn chunk ->
      Enum.reduce(blocks, chunk, fn {placeholder, code}, acc ->
        String.replace(acc, placeholder, code)
      end)
    end)
  end

  defp merge_small_chunks(chunks, min_size) do
    chunks
    |> Enum.reduce([], fn chunk, acc ->
      case acc do
        [] ->
          [chunk]

        [last | rest] when byte_size(last) < min_size ->
          [last <> "\n\n" <> chunk | rest]

        _ ->
          [chunk | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp split_large_chunks(chunks, target_size, max_size) do
    Enum.flat_map(chunks, fn chunk ->
      if String.length(chunk) > max_size do
        split_chunk_smartly(chunk, target_size)
      else
        [chunk]
      end
    end)
  end

  defp split_chunk_smartly(chunk, target_size) do
    # Try to split at sentence boundaries
    sentences = String.split(chunk, ~r/(?<=[.!?])\s+/)

    {result, current} =
      Enum.reduce(sentences, {[], ""}, fn sentence, {acc, current} ->
        new_current = if current == "", do: sentence, else: current <> " " <> sentence

        if String.length(new_current) > target_size and current != "" do
          {[current | acc], sentence}
        else
          {acc, new_current}
        end
      end)

    result = if current != "", do: [current | result], else: result
    Enum.reverse(result)
  end

  defp add_overlap(chunks, overlap_size) do
    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      prev_overlap = if idx > 0 do
        prev = Enum.at(chunks, idx - 1)
        "..." <> String.slice(prev, -overlap_size, overlap_size)
      else
        ""
      end

      %{
        content: chunk,
        context_before: prev_overlap,
        position: idx,
        total: length(chunks)
      }
    end)
  end

  defp add_chunk_metadata(chunks) do
    Enum.map(chunks, fn chunk ->
      Map.merge(chunk, %{
        char_count: String.length(chunk.content),
        word_count: length(String.split(chunk.content)),
        has_code: String.contains?(chunk.content, "```"),
        has_heading: Regex.match?(~r/^\#{1,3}\s+/m, chunk.content)
      })
    end)
  end

  # ============================================================================
  # AI OPTIMIZATION: Content Formatting
  # ============================================================================

  @doc """
  Formats content for optimal AI consumption.
  Adds structure, removes noise, preserves semantic meaning.
  """
  def format_for_ai(content, source_metadata \\ %{}) do
    content
    |> normalize_whitespace()
    |> normalize_code_blocks()
    |> add_source_context(source_metadata)
    |> truncate_if_needed()
  end

  defp normalize_whitespace(content) do
    content
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end

  defp normalize_code_blocks(content) do
    # Ensure code blocks are properly formatted
    content
    |> String.replace(~r/```(\w*)\n/, "```\\1\n")  # Normalize language tag
    |> String.replace(~r/\n```/, "\n```")          # Ensure newline before closing
  end

  defp add_source_context(content, metadata) do
    source = metadata[:source] || "Unknown"
    url = metadata[:url] || ""
    title = metadata[:title] || ""

    header = """
    [Source: #{source}]
    #{if title != "", do: "[Title: #{title}]", else: ""}
    #{if url != "", do: "[URL: #{url}]", else: ""}

    """

    String.trim(header) <> "\n\n" <> content
  end

  defp truncate_if_needed(content, max_chars \\ 10_000) do
    if String.length(content) > max_chars do
      truncated = String.slice(content, 0, max_chars)
      # Try to end at a sentence boundary
      case Regex.run(~r/^(.+[.!?])\s*[^.!?]*$/s, truncated) do
        [_, clean] -> clean <> "\n\n[Content truncated...]"
        _ -> truncated <> "...\n\n[Content truncated...]"
      end
    else
      content
    end
  end

  # ============================================================================
  # MAIN PIPELINE: Full Validation
  # ============================================================================

  @doc """
  Runs full validation pipeline on scraped content.
  Returns {:ok, validated_chunks} or {:error, reasons}
  """
  def validate_and_process(html, opts \\ []) do
    source_url = Keyword.get(opts, :url, "")
    source_name = Keyword.get(opts, :name, "")

    with {:hidden, {:ok, clean_html}} <- {:hidden, detect_hidden_content(html)},
         {:injection, result} when result in [:safe, :suspicious] <- {:injection, elem(detect_prompt_injection(clean_html), 0)},
         text <- extract_text(clean_html),
         {:quality, {:valid, score}} <- {:quality, validate_quality(text)} do

      chunks = semantic_chunk(text, opts)

      formatted_chunks =
        Enum.map(chunks, fn chunk ->
          formatted = format_for_ai(chunk.content, %{
            source: source_name,
            url: source_url,
            title: extract_title(clean_html)
          })

          %{
            content: formatted,
            position: chunk.position,
            total_chunks: chunk.total,
            quality_score: score,
            char_count: chunk.char_count,
            word_count: chunk.word_count,
            has_code: chunk.has_code
          }
        end)

      Logger.info("Validated #{length(formatted_chunks)} chunks (quality: #{score})")
      {:ok, formatted_chunks}

    else
      {:hidden, {:suspicious, reasons, _}} ->
        Logger.warning("Hidden content detected, proceeding with caution: #{inspect(reasons)}")
        # Could still process with the cleaned HTML
        {:warning, :hidden_content_detected, reasons}

      {:injection, :dangerous} ->
        Logger.error("Dangerous prompt injection detected, rejecting content")
        {:error, :prompt_injection_detected}

      {:quality, {:invalid, reasons}} ->
        Logger.warning("Content quality validation failed: #{inspect(reasons)}")
        {:error, {:quality_failed, reasons}}
    end
  end

  defp extract_text(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("body")
    |> Floki.text(sep: "\n")
    |> String.trim()
  end

  defp extract_title(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        case Floki.find(doc, "title") do
          [title | _] -> Floki.text(title)
          _ -> ""
        end
      _ -> ""
    end
  end
end

