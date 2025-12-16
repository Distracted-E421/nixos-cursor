defmodule CursorDocs.Chat.Exporter do
  @moduledoc """
  Exports Cursor chat conversations to various formats.

  ## Supported Formats

  - **Markdown** (`.md`) - Human-readable, customizable formatting
  - **JSON** (`.json`) - Machine-readable, full data preservation
  - **JSONL** (`.jsonl`) - Line-delimited JSON for streaming/training
  - **HTML** (`.html`) - Viewable in browser, styled
  - **Plain Text** (`.txt`) - Simple, universal

  ## Markdown Options

  The markdown format supports extensive customization:

  ```elixir
  export(conv, :markdown, %{
    # Header style
    frontmatter: true,           # Include YAML frontmatter
    
    # Role formatting
    user_header: "## 👤 User",
    assistant_header: "## 🤖 Assistant",
    
    # Separators
    message_separator: "\\n---\\n",
    
    # Code handling
    syntax_highlight: true,      # Detect and mark code blocks
    
    # Content filtering
    include_metadata: true,
    max_message_length: nil,     # nil = no limit
    
    # Output
    line_width: 80              # Wrap long lines (nil = no wrap)
  })
  ```

  ## Training Data Export (JSONL)

  For AI training, use JSONL format which outputs each conversation
  as a single line JSON object:

  ```elixir
  export_all(:jsonl, %{
    format: :openai,       # OpenAI chat format
    # or
    format: :alpaca,       # Alpaca instruction format
    # or
    format: :sharegpt      # ShareGPT format
  })
  ```
  """

  alias CursorDocs.Chat.Reader

  require Logger

  @type format :: :markdown | :json | :jsonl | :html | :txt
  @type export_result :: {:ok, String.t()} | {:error, term()}

  @default_output_dir "~/.local/share/cursor-docs/exports"

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Export a single conversation.
  """
  @spec export(map(), format(), map()) :: export_result()
  def export(conversation, format, opts \\ %{}) do
    content = render(conversation, format, opts)
    {:ok, content}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Export a conversation to a file.
  """
  @spec export_to_file(map(), format(), String.t() | nil, map()) ::
          {:ok, String.t()} | {:error, term()}
  def export_to_file(conversation, format, output_path \\ nil, opts \\ %{}) do
    with {:ok, content} <- export(conversation, format, opts) do
      path = output_path || generate_filename(conversation, format, opts)
      dir = Path.dirname(path)

      File.mkdir_p!(dir)
      File.write!(path, content)

      Logger.info("Exported conversation to #{path}")
      {:ok, path}
    end
  end

  @doc """
  Export all conversations.
  """
  @spec export_all(format(), map()) :: {:ok, [String.t()]} | {:error, term()}
  def export_all(format, opts \\ %{}) do
    output_dir = Map.get(opts, :output_dir, @default_output_dir) |> Path.expand()

    with {:ok, conversations} <- Reader.list_conversations() do
      paths =
        conversations
        |> Enum.map(fn conv ->
          path = Path.join(output_dir, generate_basename(conv, format))

          case export_to_file(conv, format, path, opts) do
            {:ok, p} -> p
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, paths}
    end
  end

  @doc """
  Export conversations as a single merged file.
  """
  @spec export_merged(format(), map()) :: {:ok, String.t()} | {:error, term()}
  def export_merged(format, opts \\ %{}) do
    with {:ok, conversations} <- Reader.list_conversations(opts) do
      content =
        case format do
          :jsonl ->
            conversations
            |> Enum.map(&render(&1, :jsonl, opts))
            |> Enum.join("\n")

          :json ->
            conversations
            |> Enum.map(&conversation_to_map(&1, opts))
            |> Jason.encode!(pretty: Map.get(opts, :pretty, true))

          :markdown ->
            header = "# Cursor Chat Export\n\n*Exported: #{DateTime.utc_now()}*\n\n---\n\n"

            body =
              conversations
              |> Enum.map(&render(&1, :markdown, opts))
              |> Enum.join("\n\n---\n\n")

            header <> body

          _ ->
            conversations
            |> Enum.map(&render(&1, format, opts))
            |> Enum.join("\n\n========================================\n\n")
        end

      {:ok, content}
    end
  end

  @doc """
  List supported export formats with descriptions.
  """
  @spec formats() :: [map()]
  def formats do
    [
      %{
        id: :markdown,
        extension: ".md",
        name: "Markdown",
        description: "Human-readable with customizable formatting",
        options: [:frontmatter, :user_header, :assistant_header, :syntax_highlight]
      },
      %{
        id: :json,
        extension: ".json",
        name: "JSON",
        description: "Machine-readable, full data preservation",
        options: [:pretty, :include_metadata]
      },
      %{
        id: :jsonl,
        extension: ".jsonl",
        name: "JSONL",
        description: "Line-delimited JSON for training/streaming",
        options: [:format, :system_prompt]
      },
      %{
        id: :html,
        extension: ".html",
        name: "HTML",
        description: "Viewable in browser with styling",
        options: [:theme, :syntax_highlight]
      },
      %{
        id: :txt,
        extension: ".txt",
        name: "Plain Text",
        description: "Simple universal format",
        options: [:separator]
      }
    ]
  end

  # ============================================================================
  # Renderers
  # ============================================================================

  @doc false
  def render(conversation, :markdown, opts) do
    lines = []

    # YAML frontmatter
    lines =
      if Map.get(opts, :frontmatter, true) do
        fm =
          [
            "---",
            "id: #{conversation.id}",
            "title: \"#{escape_yaml(conversation.title)}\"",
            "messages: #{conversation.message_count}",
            "source: #{conversation.source}",
            "exported: #{DateTime.utc_now() |> DateTime.to_iso8601()}",
            "---",
            ""
          ]
          |> Enum.join("\n")

        [fm | lines]
      else
        lines
      end

    # Title
    title = "# #{conversation.title}\n"
    lines = lines ++ [title]

    # Messages
    user_header = Map.get(opts, :user_header, "## 👤 User")
    assistant_header = Map.get(opts, :assistant_header, "## 🤖 Assistant")
    separator = Map.get(opts, :message_separator, "\n---\n")

    message_content =
      conversation.messages
      |> Enum.map(fn msg ->
        header = if msg.role == :user, do: user_header, else: assistant_header
        content = maybe_format_code(msg.content, opts)
        content = maybe_wrap_lines(content, opts)

        "#{header}\n\n#{content}"
      end)
      |> Enum.join(separator)

    lines = lines ++ [message_content]

    Enum.join(lines, "\n")
  end

  def render(conversation, :json, opts) do
    conversation
    |> conversation_to_map(opts)
    |> Jason.encode!(pretty: Map.get(opts, :pretty, true))
  end

  def render(conversation, :jsonl, opts) do
    training_format = Map.get(opts, :format, :openai)

    case training_format do
      :openai -> render_openai_format(conversation, opts)
      :alpaca -> render_alpaca_format(conversation, opts)
      :sharegpt -> render_sharegpt_format(conversation, opts)
      _ -> render_openai_format(conversation, opts)
    end
  end

  def render(conversation, :html, opts) do
    theme = Map.get(opts, :theme, :light)

    css = html_css(theme)

    messages_html =
      conversation.messages
      |> Enum.map(fn msg ->
        role_class = if msg.role == :user, do: "user", else: "assistant"
        role_label = if msg.role == :user, do: "You", else: "Assistant"
        content = html_escape(msg.content) |> maybe_format_code_html()

        """
        <div class="message #{role_class}">
          <div class="role">#{role_label}</div>
          <div class="content">#{content}</div>
        </div>
        """
      end)
      |> Enum.join("\n")

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{html_escape(conversation.title)}</title>
      <style>#{css}</style>
    </head>
    <body>
      <div class="container">
        <h1>#{html_escape(conversation.title)}</h1>
        <div class="meta">
          <span>Source: #{conversation.source}</span>
          <span>Messages: #{conversation.message_count}</span>
        </div>
        <div class="messages">
          #{messages_html}
        </div>
      </div>
    </body>
    </html>
    """
  end

  def render(conversation, :txt, opts) do
    separator = Map.get(opts, :separator, "\n" <> String.duplicate("-", 40) <> "\n")

    header = """
    #{conversation.title}
    Source: #{conversation.source}
    Messages: #{conversation.message_count}
    #{String.duplicate("=", 60)}

    """

    messages =
      conversation.messages
      |> Enum.map(fn msg ->
        role = if msg.role == :user, do: "USER", else: "ASSISTANT"
        "[#{role}]\n#{msg.content}"
      end)
      |> Enum.join(separator)

    header <> messages
  end

  # ============================================================================
  # Training Format Renderers
  # ============================================================================

  defp render_openai_format(conversation, opts) do
    system_prompt = Map.get(opts, :system_prompt)

    messages =
      conversation.messages
      |> Enum.map(fn msg ->
        %{
          role: to_string(msg.role),
          content: msg.content
        }
      end)

    messages =
      if system_prompt do
        [%{role: "system", content: system_prompt} | messages]
      else
        messages
      end

    %{messages: messages}
    |> Jason.encode!()
  end

  defp render_alpaca_format(conversation, opts) do
    # Alpaca format pairs user/assistant messages as instruction/output
    system_prompt = Map.get(opts, :system_prompt, "")

    conversation.messages
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [%{role: :user} = user, %{role: :assistant} = assistant] ->
        %{
          instruction: user.content,
          input: "",
          output: assistant.content,
          system: system_prompt
        }
        |> Jason.encode!()

      [%{role: :user} = user] ->
        %{
          instruction: user.content,
          input: "",
          output: "",
          system: system_prompt
        }
        |> Jason.encode!()

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp render_sharegpt_format(conversation, _opts) do
    conversations =
      conversation.messages
      |> Enum.map(fn msg ->
        from = if msg.role == :user, do: "human", else: "gpt"
        %{from: from, value: msg.content}
      end)

    %{
      id: conversation.id,
      conversations: conversations
    }
    |> Jason.encode!()
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp conversation_to_map(conversation, opts) do
    base = %{
      id: conversation.id,
      title: conversation.title,
      message_count: conversation.message_count,
      source: conversation.source,
      messages:
        Enum.map(conversation.messages, fn msg ->
          %{
            role: msg.role,
            content: msg.content
          }
        end)
    }

    if Map.get(opts, :include_metadata, false) do
      Map.merge(base, %{
        workspace: conversation.workspace,
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    else
      base
    end
  end

  defp generate_filename(conversation, format, opts) do
    output_dir = Map.get(opts, :output_dir, @default_output_dir) |> Path.expand()
    basename = generate_basename(conversation, format)
    Path.join(output_dir, basename)
  end

  defp generate_basename(conversation, format) do
    ext = format_extension(format)
    safe_title = sanitize_filename(conversation.title)
    date = Date.utc_today() |> Date.to_iso8601()
    short_id = String.slice(conversation.id, 0, 8)

    "#{date}_#{safe_title}_#{short_id}#{ext}"
  end

  defp format_extension(:markdown), do: ".md"
  defp format_extension(:json), do: ".json"
  defp format_extension(:jsonl), do: ".jsonl"
  defp format_extension(:html), do: ".html"
  defp format_extension(:txt), do: ".txt"
  defp format_extension(_), do: ".txt"

  defp sanitize_filename(name) do
    name
    |> String.slice(0, 50)
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
    |> String.trim("_")
  end

  defp escape_yaml(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end

  defp html_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp maybe_format_code(content, opts) do
    if Map.get(opts, :syntax_highlight, true) do
      # Detect code blocks that aren't already fenced
      content
      |> String.replace(~r/(?<!\n)```/, "\n```")
      |> String.replace(~r/```(?!\n)/, "```\n")
    else
      content
    end
  end

  defp maybe_format_code_html(content) do
    # Convert markdown code blocks to HTML
    content
    |> String.replace(~r/```(\w*)\n(.*?)```/s, fn _, lang, code ->
      lang_class = if lang != "", do: " class=\"language-#{lang}\"", else: ""
      "<pre><code#{lang_class}>#{code}</code></pre>"
    end)
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace("\n", "<br>")
  end

  defp maybe_wrap_lines(content, opts) do
    case Map.get(opts, :line_width) do
      nil ->
        content

      width when is_integer(width) ->
        content
        |> String.split("\n")
        |> Enum.map(&wrap_line(&1, width))
        |> Enum.join("\n")
    end
  end

  defp wrap_line(line, width) when byte_size(line) <= width, do: line

  defp wrap_line(line, width) do
    # Don't wrap code blocks
    if String.starts_with?(String.trim(line), "```") or String.starts_with?(line, "    ") do
      line
    else
      line
      |> String.graphemes()
      |> Enum.chunk_every(width)
      |> Enum.map(&Enum.join/1)
      |> Enum.join("\n")
    end
  end

  defp html_css(:light) do
    """
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      line-height: 1.6;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
      background: #f5f5f5;
      color: #333;
    }
    .container {
      background: white;
      border-radius: 8px;
      padding: 2rem;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    h1 { margin-top: 0; color: #1a1a1a; }
    .meta { color: #666; font-size: 0.9rem; margin-bottom: 2rem; }
    .meta span { margin-right: 1rem; }
    .message { margin: 1.5rem 0; padding: 1rem; border-radius: 8px; }
    .message.user { background: #e3f2fd; }
    .message.assistant { background: #f5f5f5; }
    .role { font-weight: bold; margin-bottom: 0.5rem; color: #555; }
    .content { white-space: pre-wrap; }
    pre { background: #263238; color: #eee; padding: 1rem; border-radius: 4px; overflow-x: auto; }
    code { background: #e0e0e0; padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9rem; }
    pre code { background: none; padding: 0; }
    """
  end

  defp html_css(:dark) do
    """
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      line-height: 1.6;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
      background: #1a1a1a;
      color: #e0e0e0;
    }
    .container {
      background: #2d2d2d;
      border-radius: 8px;
      padding: 2rem;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
    }
    h1 { margin-top: 0; color: #fff; }
    .meta { color: #999; font-size: 0.9rem; margin-bottom: 2rem; }
    .meta span { margin-right: 1rem; }
    .message { margin: 1.5rem 0; padding: 1rem; border-radius: 8px; }
    .message.user { background: #1e3a5f; }
    .message.assistant { background: #3d3d3d; }
    .role { font-weight: bold; margin-bottom: 0.5rem; color: #aaa; }
    .content { white-space: pre-wrap; }
    pre { background: #1a1a1a; color: #e0e0e0; padding: 1rem; border-radius: 4px; overflow-x: auto; }
    code { background: #404040; padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9rem; }
    pre code { background: none; padding: 0; }
    """
  end
end


