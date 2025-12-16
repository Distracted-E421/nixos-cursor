defmodule CursorDocs.Chat.Formatter do
  @moduledoc """
  Advanced markdown formatting options for chat exports.

  ## Presets

  Use built-in presets for common use cases:

  ```elixir
  Formatter.preset(:obsidian)   # Optimized for Obsidian vault
  Formatter.preset(:github)     # GitHub-flavored markdown
  Formatter.preset(:notion)     # Notion-compatible
  Formatter.preset(:docusaurus) # Docusaurus docs
  Formatter.preset(:minimal)    # Clean, no extras
  ```

  ## Custom Formatting

  Build custom formatters:

  ```elixir
  Formatter.build()
  |> Formatter.with_frontmatter(true)
  |> Formatter.with_headers(:emoji)
  |> Formatter.with_code_blocks(:fenced)
  |> Formatter.with_callouts(:admonition)
  |> Formatter.to_opts()
  ```
  """

  @type header_style :: :emoji | :text | :bold | :custom
  @type code_style :: :fenced | :indented | :none
  @type callout_style :: :admonition | :blockquote | :github | :none

  @presets %{
    obsidian: %{
      frontmatter: true,
      frontmatter_format: :yaml,
      user_header: "## 👤 User",
      assistant_header: "## 🤖 Assistant",
      message_separator: "\n---\n",
      syntax_highlight: true,
      callout_style: :admonition,
      wikilinks: true,
      tags_in_frontmatter: true
    },
    github: %{
      frontmatter: false,
      user_header: "### User",
      assistant_header: "### Assistant",
      message_separator: "\n---\n",
      syntax_highlight: true,
      callout_style: :blockquote,
      task_lists: true
    },
    notion: %{
      frontmatter: false,
      user_header: "## 💬 User",
      assistant_header: "## 🤖 Assistant",
      message_separator: "\n\n",
      syntax_highlight: true,
      callout_style: :blockquote,
      toggle_blocks: true
    },
    docusaurus: %{
      frontmatter: true,
      frontmatter_format: :yaml,
      frontmatter_fields: [:title, :description, :tags, :sidebar_position],
      user_header: "### User",
      assistant_header: "### Assistant",
      message_separator: "\n\n---\n\n",
      syntax_highlight: true,
      callout_style: :admonition,
      admonition_prefix: ":::"
    },
    minimal: %{
      frontmatter: false,
      user_header: "**User:**",
      assistant_header: "**Assistant:**",
      message_separator: "\n\n",
      syntax_highlight: false,
      callout_style: :none
    },
    training: %{
      frontmatter: false,
      user_header: "",
      assistant_header: "",
      message_separator: "\n",
      syntax_highlight: false,
      strip_formatting: true,
      raw_content: true
    }
  }

  # ============================================================================
  # Presets
  # ============================================================================

  @doc """
  Get a formatting preset by name.
  """
  @spec preset(atom()) :: map()
  def preset(name) when is_atom(name) do
    Map.get(@presets, name, @presets.minimal)
  end

  @doc """
  List all available presets.
  """
  @spec presets() :: [atom()]
  def presets, do: Map.keys(@presets)

  @doc """
  Get preset with description.
  """
  @spec preset_info(atom()) :: map()
  def preset_info(name) do
    descriptions = %{
      obsidian: "Optimized for Obsidian vault with YAML frontmatter and callouts",
      github: "GitHub-flavored markdown with task lists",
      notion: "Notion-compatible with toggle blocks",
      docusaurus: "Docusaurus documentation site format",
      minimal: "Clean output with minimal formatting",
      training: "Raw format for AI training data"
    }

    %{
      name: name,
      description: Map.get(descriptions, name, ""),
      options: preset(name)
    }
  end

  # ============================================================================
  # Builder API
  # ============================================================================

  @doc """
  Start building a custom formatter.
  """
  @spec build() :: map()
  def build do
    %{
      frontmatter: false,
      frontmatter_format: :yaml,
      frontmatter_fields: [:id, :title, :messages, :source, :exported],
      user_header: "## User",
      assistant_header: "## Assistant",
      message_separator: "\n---\n",
      syntax_highlight: true,
      callout_style: :none,
      line_width: nil,
      include_metadata: false
    }
  end

  @doc """
  Start from a preset and customize.
  """
  @spec from_preset(atom()) :: map()
  def from_preset(name) do
    build() |> Map.merge(preset(name))
  end

  @doc """
  Enable/configure frontmatter.
  """
  @spec with_frontmatter(map(), boolean() | keyword()) :: map()
  def with_frontmatter(formatter, true) do
    Map.put(formatter, :frontmatter, true)
  end

  def with_frontmatter(formatter, false) do
    Map.put(formatter, :frontmatter, false)
  end

  def with_frontmatter(formatter, opts) when is_list(opts) do
    formatter
    |> Map.put(:frontmatter, true)
    |> Map.put(:frontmatter_format, Keyword.get(opts, :format, :yaml))
    |> Map.put(:frontmatter_fields, Keyword.get(opts, :fields, formatter.frontmatter_fields))
  end

  @doc """
  Configure role headers.
  """
  @spec with_headers(map(), header_style() | keyword()) :: map()
  def with_headers(formatter, :emoji) do
    formatter
    |> Map.put(:user_header, "## 👤 User")
    |> Map.put(:assistant_header, "## 🤖 Assistant")
  end

  def with_headers(formatter, :text) do
    formatter
    |> Map.put(:user_header, "## User")
    |> Map.put(:assistant_header, "## Assistant")
  end

  def with_headers(formatter, :bold) do
    formatter
    |> Map.put(:user_header, "**User:**")
    |> Map.put(:assistant_header, "**Assistant:**")
  end

  def with_headers(formatter, opts) when is_list(opts) do
    formatter
    |> Map.put(:user_header, Keyword.get(opts, :user, formatter.user_header))
    |> Map.put(:assistant_header, Keyword.get(opts, :assistant, formatter.assistant_header))
  end

  @doc """
  Configure message separators.
  """
  @spec with_separator(map(), String.t()) :: map()
  def with_separator(formatter, separator) do
    Map.put(formatter, :message_separator, separator)
  end

  @doc """
  Configure code block handling.
  """
  @spec with_code_blocks(map(), code_style() | keyword()) :: map()
  def with_code_blocks(formatter, :fenced) do
    Map.put(formatter, :syntax_highlight, true)
  end

  def with_code_blocks(formatter, :none) do
    Map.put(formatter, :syntax_highlight, false)
  end

  def with_code_blocks(formatter, opts) when is_list(opts) do
    formatter
    |> Map.put(:syntax_highlight, Keyword.get(opts, :highlight, true))
  end

  @doc """
  Configure callout/admonition style.
  """
  @spec with_callouts(map(), callout_style()) :: map()
  def with_callouts(formatter, style) do
    Map.put(formatter, :callout_style, style)
  end

  @doc """
  Set line width for wrapping.
  """
  @spec with_line_width(map(), non_neg_integer() | nil) :: map()
  def with_line_width(formatter, width) do
    Map.put(formatter, :line_width, width)
  end

  @doc """
  Include full metadata in export.
  """
  @spec with_metadata(map(), boolean()) :: map()
  def with_metadata(formatter, include) do
    Map.put(formatter, :include_metadata, include)
  end

  @doc """
  Convert builder to options map for Exporter.
  """
  @spec to_opts(map()) :: map()
  def to_opts(formatter), do: formatter

  # ============================================================================
  # Template Helpers
  # ============================================================================

  @doc """
  Generate frontmatter string from conversation data.
  """
  @spec render_frontmatter(map(), map()) :: String.t()
  def render_frontmatter(conversation, opts) do
    fields = Map.get(opts, :frontmatter_fields, [:id, :title, :messages, :source, :exported])

    values =
      Enum.map(fields, fn field ->
        value =
          case field do
            :id -> conversation.id
            :title -> conversation.title
            :messages -> conversation.message_count
            :source -> conversation.source
            :exported -> DateTime.utc_now() |> DateTime.to_iso8601()
            :tags -> "[]"
            :description -> truncate(conversation.title, 100)
            :sidebar_position -> 1
            _ -> nil
          end

        {field, value}
      end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    case Map.get(opts, :frontmatter_format, :yaml) do
      :yaml ->
        yaml_lines =
          values
          |> Enum.map(fn {k, v} ->
            formatted =
              cond do
                is_binary(v) and String.contains?(v, ":") -> "\"#{v}\""
                is_binary(v) -> v
                true -> inspect(v)
              end

            "#{k}: #{formatted}"
          end)

        "---\n#{Enum.join(yaml_lines, "\n")}\n---\n"

      :toml ->
        toml_lines =
          values
          |> Enum.map(fn {k, v} ->
            formatted =
              cond do
                is_binary(v) -> "\"#{v}\""
                true -> inspect(v)
              end

            "#{k} = #{formatted}"
          end)

        "+++\n#{Enum.join(toml_lines, "\n")}\n+++\n"

      :json ->
        values
        |> Map.new()
        |> Jason.encode!(pretty: true)
        |> then(&"```json\n#{&1}\n```\n")
    end
  end

  @doc """
  Format a message according to formatter options.
  """
  @spec format_message(map(), map()) :: String.t()
  def format_message(message, opts) do
    header =
      if message.role == :user do
        Map.get(opts, :user_header, "## User")
      else
        Map.get(opts, :assistant_header, "## Assistant")
      end

    content =
      message.content
      |> maybe_strip_formatting(opts)
      |> maybe_highlight_code(opts)
      |> maybe_wrap(opts)

    if header == "" do
      content
    else
      "#{header}\n\n#{content}"
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - 3) <> "..."
    else
      string
    end
  end

  defp maybe_strip_formatting(content, %{strip_formatting: true}) do
    content
    |> String.replace(~r/\*\*([^*]+)\*\*/, "\\1")
    |> String.replace(~r/\*([^*]+)\*/, "\\1")
    |> String.replace(~r/_([^_]+)_/, "\\1")
    |> String.replace(~r/`([^`]+)`/, "\\1")
  end

  defp maybe_strip_formatting(content, _opts), do: content

  defp maybe_highlight_code(content, %{syntax_highlight: true}) do
    # Ensure code blocks are properly fenced
    content
    |> String.replace(~r/(?<!\n)```/, "\n```")
    |> String.replace(~r/```(?!\n)/, "```\n")
  end

  defp maybe_highlight_code(content, _opts), do: content

  defp maybe_wrap(content, %{line_width: width}) when is_integer(width) and width > 0 do
    content
    |> String.split("\n")
    |> Enum.map(&wrap_line(&1, width))
    |> Enum.join("\n")
  end

  defp maybe_wrap(content, _opts), do: content

  defp wrap_line(line, _width) when byte_size(line) == 0, do: line

  defp wrap_line(line, width) do
    # Don't wrap code blocks or indented lines
    if String.starts_with?(String.trim(line), "```") or
         String.starts_with?(line, "    ") or
         String.starts_with?(line, "\t") do
      line
    else
      wrap_words(line, width)
    end
  end

  defp wrap_words(line, width) do
    words = String.split(line, " ")

    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        candidate =
          if current == "" do
            word
          else
            current <> " " <> word
          end

        if String.length(candidate) > width and current != "" do
          {[current | lines], word}
        else
          {lines, candidate}
        end
      end)

    ([current | lines] |> Enum.reverse() |> Enum.reject(&(&1 == "")))
    |> Enum.join("\n")
  end
end


