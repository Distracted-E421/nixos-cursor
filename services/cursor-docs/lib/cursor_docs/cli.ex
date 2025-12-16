defmodule CursorDocs.CLI do
  @moduledoc """
  Command-line interface for CursorDocs.

  Provides mix tasks for:
  - Adding documentation
  - Searching indexed content
  - Listing sources
  - Checking status
  - Security alerts and quarantine
  - Chat export

  ## Usage

      mix cursor_docs.add https://docs.example.com/
      mix cursor_docs.search "authentication"
      mix cursor_docs.list
      mix cursor_docs.status
      mix cursor_docs.alerts
      mix cursor_docs.quarantine
      mix cursor_docs.chat list
      mix cursor_docs.chat export <id> --format markdown
      mix cursor_docs.chat export-all --format jsonl
  """

  alias CursorDocs.Security.{Alerts, Quarantine}
  alias CursorDocs.Chat.{Reader, Exporter, Formatter}
  alias CursorDocs.Progress

  @doc """
  Add documentation from CLI.
  """
  def add(args) do
    {opts, urls, _} = OptionParser.parse(args,
      strict: [name: :string, max_pages: :integer, follow: :boolean, force: :boolean]
    )

    case urls do
      [] ->
        IO.puts("❌ Usage: mix cursor_docs.add URL [--name NAME] [--max-pages N] [--force]")

      [url | _] ->
        force? = opts[:force] == true
        max_pages = opts[:max_pages] || 100
        name = opts[:name] || derive_name_from_url(url)

        # Check if URL already exists
        case {check_existing_url(url), force?} do
          {{:exists, source}, false} ->
            IO.puts("ℹ️  Already indexed: #{source[:name]} (#{source[:chunks_count]} chunks)")
            IO.puts("   Last indexed: #{source[:last_indexed]}")
            IO.puts("")
            IO.puts("To re-index, use: mix cursor_docs.add #{url} --force")

          {{:exists, source}, true} ->
            IO.puts("🔄 Re-indexing: #{url}")
            IO.puts("   (This may take a moment...)\n")
            
            # Emit progress: started
            Progress.started(url, source[:name], max_pages)
            start_time = System.monotonic_time(:millisecond)
            
            result = do_refresh(source[:id])
            
            duration = System.monotonic_time(:millisecond) - start_time
            emit_completion_progress(result, url, source[:name], duration)

          {:not_found, _} ->
            IO.puts("📥 Adding documentation: #{url}")
            IO.puts("   (This may take a moment...)\n")

            add_opts = [
              name: opts[:name],
              max_pages: max_pages,
              follow_links: opts[:follow] || false
            ] |> Enum.reject(fn {_k, v} -> is_nil(v) end)

            # Emit progress: started
            Progress.started(url, name, max_pages)
            start_time = System.monotonic_time(:millisecond)
            
            result = CursorDocs.add(url, add_opts)
            
            duration = System.monotonic_time(:millisecond) - start_time
            
            case result do
              {:ok, source} ->
                # Emit progress: complete
                Progress.complete(url, source[:name], source[:id], source[:chunks_count] || 0, duration)
                
                IO.puts("✅ Indexed successfully!")
                IO.puts("   Name: #{source[:name]}")
                IO.puts("   ID: #{source[:id]}")
                IO.puts("   Chunks: #{source[:chunks_count] || 0}")
                IO.puts("")
                IO.puts("Search with: mix cursor_docs.search \"your query\"")

              {:error, reason} ->
                # Emit progress: error
                Progress.error(url, reason)
                IO.puts("❌ Failed: #{inspect(reason)}")
            end
        end
    end
  end
  
  defp emit_completion_progress({:ok, source}, url, _name, duration) do
    Progress.complete(url, source[:name], source[:id], source[:chunks_count] || 0, duration)
  end
  
  defp emit_completion_progress({:error, reason}, url, _name, _duration) do
    Progress.error(url, reason)
  end
  
  defp derive_name_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:host, "docs")
    |> String.replace_prefix("www.", "")
    |> String.split(".")
    |> List.first()
    |> String.capitalize()
  end

  defp check_existing_url(url) do
    case CursorDocs.list() do
      {:ok, sources} ->
        case Enum.find(sources, fn s -> s[:url] == url end) do
          nil -> :not_found
          source -> {:exists, source}
        end
      _ -> :not_found
    end
  end

  defp do_refresh(source_id) do
    case CursorDocs.refresh(source_id) do
      {:ok, source} ->
        IO.puts("✅ Re-indexed successfully!")
        IO.puts("   Name: #{source[:name]}")
        IO.puts("   ID: #{source[:id]}")

      {:error, reason} ->
        IO.puts("❌ Refresh failed: #{inspect(reason)}")
    end
  end

  @doc """
  Search documentation from CLI.
  """
  def search(args) do
    {opts, query_parts, _} = OptionParser.parse(args,
      strict: [limit: :integer, source: :string]
    )

    query = Enum.join(query_parts, " ")

    if query == "" do
      IO.puts("❌ Usage: mix cursor_docs.search \"your query\" [--limit N]")
    else
      IO.puts("🔍 Searching: #{query}\n")

      search_opts = [
        limit: opts[:limit] || 5,
        sources: if(opts[:source], do: [opts[:source]], else: [])
      ]

      case CursorDocs.search(query, search_opts) do
        {:ok, []} ->
          IO.puts("No results found.")
          IO.puts("\nTip: Make sure you've added some documentation first:")
          IO.puts("  mix cursor_docs.add https://hexdocs.pm/ecto/")

        {:ok, results} ->
          IO.puts("Found #{length(results)} result(s):\n")

          Enum.each(results, fn result ->
            IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            IO.puts("📄 #{result[:title] || "Untitled"}")
            IO.puts("   URL: #{result[:url]}")

            score = result[:score]
            if score do
              IO.puts("   Relevance: #{Float.round(abs(score), 2)}")
            end

            IO.puts("")

            # Show snippet
            content = result[:content] || ""
            snippet = String.slice(content, 0, 400)
            snippet = if String.length(content) > 400, do: snippet <> "...", else: snippet
            IO.puts(snippet)
            IO.puts("")
          end)

        {:error, reason} ->
          IO.puts("❌ Search failed: #{inspect(reason)}")
      end
    end
  end

  @doc """
  List all indexed documentation sources.
  """
  def list do
    IO.puts("📚 Indexed Documentation\n")

    case CursorDocs.list() do
      {:ok, []} ->
        IO.puts("No documentation indexed yet.")
        IO.puts("Add some with: mix cursor_docs.add <url>")

      {:ok, sources} ->
        # Header
        IO.puts(String.pad_trailing("Name", 25) <>
                String.pad_trailing("Chunks", 10) <>
                String.pad_trailing("Status", 12) <>
                "URL")
        IO.puts(String.duplicate("─", 90))

        Enum.each(sources, fn source ->
          status_icon = case source[:status] do
            "indexed" -> "✅"
            "indexing" -> "⏳"
            "failed" -> "❌"
            "pending" -> "⏸️"
            _ -> "❓"
          end

          name = String.slice(source[:name] || "Unknown", 0, 23)
          url = String.slice(source[:url] || "", 0, 45)

          IO.puts(
            String.pad_trailing(name, 25) <>
            String.pad_trailing("#{source[:chunks_count] || 0}", 10) <>
            String.pad_trailing("#{status_icon} #{source[:status]}", 12) <>
            url
          )
        end)

        IO.puts("")
        IO.puts("Total: #{length(sources)} source(s)")

      {:error, reason} ->
        IO.puts("❌ Failed to list: #{inspect(reason)}")
    end
  end

  @doc """
  Import docs from Cursor's database.
  """
  def import_cursor(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [limit: :integer, dry_run: :boolean]
    )

    limit = opts[:limit] || 10
    dry_run? = opts[:dry_run] == true

    IO.puts("🔍 Reading docs from Cursor's database...")

    case read_cursor_docs() do
      {:ok, docs} ->
        success_docs = Enum.filter(docs, fn d -> d["indexingStatus"] == "success" end)
        IO.puts("   Found #{length(docs)} total docs (#{length(success_docs)} successfully indexed)")
        IO.puts("")

        # Sort by number of pages and take top N
        sorted = success_docs
          |> Enum.sort_by(fn d -> d["numPages"] || 0 end, :desc)
          |> Enum.take(limit)

        if dry_run? do
          IO.puts("📋 Would import these #{length(sorted)} docs:")
          Enum.each(sorted, fn doc ->
            IO.puts("   📄 #{doc["name"]} (#{doc["numPages"]} pages)")
            IO.puts("      #{doc["url"]}")
          end)
          IO.puts("\nRun without --dry-run to actually import.")
        else
          IO.puts("📥 Importing #{length(sorted)} docs...\n")

          results = Enum.map(sorted, fn doc ->
            url = doc["url"]
            name = doc["name"]
            IO.puts("   ⏳ #{name}...")

            case CursorDocs.add(url, name: name, max_pages: 1, follow_links: false) do
              {:ok, source} ->
                IO.puts("   ✅ #{name} (#{source[:chunks_count]} chunks)")
                {:ok, source}
              {:error, reason} ->
                IO.puts("   ❌ #{name}: #{inspect(reason)}")
                {:error, reason}
            end
          end)

          success = Enum.count(results, fn {status, _} -> status == :ok end)
          IO.puts("\n✅ Imported #{success}/#{length(sorted)} docs")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to read Cursor docs: #{inspect(reason)}")
        IO.puts("   Make sure Cursor is installed at ~/.config/Cursor")
    end
  end

  defp read_cursor_docs do
    db_path = Path.expand("~/.config/Cursor/User/globalStorage/state.vscdb")

    if File.exists?(db_path) do
      # Use sqlite3 CLI to avoid opening the database (might be locked)
      case System.cmd("sqlite3", [
        db_path,
        "SELECT value FROM ItemTable WHERE key = 'src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser'"
      ]) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, data} -> {:ok, data["personalDocs"] || []}
            {:error, _} -> {:error, :json_parse_failed}
          end
        {error, _} ->
          {:error, error}
      end
    else
      {:error, :cursor_not_found}
    end
  end

  @doc """
  List docs in Cursor's database (without importing).
  """
  def cursor_docs(_args \\ []) do
    IO.puts("📚 Docs configured in Cursor\n")

    case read_cursor_docs() do
      {:ok, docs} ->
        success = Enum.filter(docs, fn d -> d["indexingStatus"] == "success" end)
        failed = Enum.filter(docs, fn d -> d["indexingStatus"] == "failure" end)

        IO.puts("Status:")
        IO.puts("  ✅ Successfully indexed: #{length(success)}")
        IO.puts("  ❌ Failed to index: #{length(failed)}")
        IO.puts("")

        if length(failed) > 0 do
          IO.puts("❌ Failed docs (these need our local scraper!):")
          Enum.each(failed, fn d ->
            IO.puts("   - #{d["name"]}: #{d["url"]}")
          end)
          IO.puts("")
        end

        IO.puts("✅ Top successfully indexed docs:")
        success
        |> Enum.sort_by(fn d -> d["numPages"] || 0 end, :desc)
        |> Enum.take(20)
        |> Enum.each(fn d ->
          IO.puts("   📄 #{String.pad_trailing(d["name"], 25)} (#{String.pad_leading("#{d["numPages"]}", 5)} pages)")
        end)

      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
  end

  @doc """
  Check scraping status - shows all sources and their indexing state.
  """
  def status do
    IO.puts("📊 Documentation Status\n")

    case CursorDocs.list() do
      {:ok, []} ->
        IO.puts("No documentation sources found.")
        IO.puts("Add some with: mix cursor_docs.add <url>")

      {:ok, sources} ->
        indexing = Enum.filter(sources, fn s -> s[:status] == "indexing" end)
        indexed = Enum.filter(sources, fn s -> s[:status] == "indexed" end)
        failed = Enum.filter(sources, fn s -> s[:status] == "failed" end)
        pending = Enum.filter(sources, fn s -> s[:status] == "pending" end)

        total_chunks = Enum.reduce(sources, 0, fn s, acc -> acc + (s[:chunks_count] || 0) end)

        IO.puts("Summary:")
        IO.puts("  ✅ Indexed: #{length(indexed)}")
        IO.puts("  ⏳ Indexing: #{length(indexing)}")
        IO.puts("  ⏸️  Pending: #{length(pending)}")
        IO.puts("  ❌ Failed: #{length(failed)}")
        IO.puts("  📊 Total chunks: #{total_chunks}")
        IO.puts("")

        if length(sources) > 0 do
          IO.puts("Sources:")
          Enum.each(sources, fn source ->
            status_icon = case source[:status] do
              "indexed" -> "✅"
              "indexing" -> "⏳"
              "failed" -> "❌"
              _ -> "⏸️"
            end

            IO.puts("  #{status_icon} #{source[:name]} (#{source[:chunks_count] || 0} chunks)")
            IO.puts("     #{source[:url]}")

            if source[:last_indexed] do
              IO.puts("     Last indexed: #{source[:last_indexed]}")
            end

            IO.puts("")
          end)
        end

      {:error, reason} ->
        IO.puts("❌ Failed to get status: #{inspect(reason)}")
    end
  end

  # ============================================================================
  # Security Commands
  # ============================================================================

  @doc """
  Show security alerts.
  """
  def alerts(args \\ []) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [severity: :string, export: :boolean]
    )

    if opts[:export] do
      export_alerts()
    else
      show_alerts(opts)
    end
  end

  defp show_alerts(_opts) do
    IO.puts("🔒 Security Alerts\n")

    case Alerts.get_stats() do
      {:ok, stats} ->
        IO.puts("Summary:")
        IO.puts("  📊 Total alerts: #{stats.total}")
        IO.puts("  🏠 Sources affected: #{stats.sources_affected}")
        IO.puts("  📅 Last 24h: #{stats.recent_24h}")
        IO.puts("  📅 Last 7d: #{stats.recent_7d}")
        IO.puts("")

        IO.puts("By Severity:")
        Enum.each(stats.by_severity, fn {sev, count} ->
          icon = case sev do
            "Critical" -> "🚨"
            "High" -> "⚠️"
            "Medium" -> "⚡"
            _ -> "ℹ️"
          end
          IO.puts("  #{icon} #{sev}: #{count}")
        end)
        IO.puts("")

        IO.puts("By Type:")
        Enum.each(stats.by_type, fn {type, count} ->
          IO.puts("  • #{type}: #{count}")
        end)

      {:error, reason} ->
        IO.puts("❌ Failed to get alerts: #{inspect(reason)}")
    end

    IO.puts("")

    # Show recent alerts
    case Alerts.get_alerts_for_gui(min_severity: 3) do
      {:ok, [_ | _] = alerts} ->
        IO.puts("Recent Alerts (Medium+):")
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        alerts
        |> Enum.take(10)
        |> Enum.each(fn alert ->
          IO.puts("#{alert.severity_icon} #{alert.severity_label} | #{alert.type_label}")
          IO.puts("  URL: #{alert.source_url}")
          IO.puts("  #{alert.description}")
          IO.puts("  #{alert.created_ago}")
          IO.puts("")
        end)

      {:ok, []} ->
        IO.puts("✅ No significant alerts!")

      {:error, reason} ->
        IO.puts("❌ Failed to get alerts: #{inspect(reason)}")
    end
  end

  defp export_alerts do
    IO.puts("📤 Exporting alerts for cursor-studio...")

    case Alerts.write_export_file() do
      {:ok, path} ->
        IO.puts("✅ Exported to: #{path}")

      {:error, reason} ->
        IO.puts("❌ Export failed: #{inspect(reason)}")
    end
  end

  @doc """
  Show quarantined items pending review.
  """
  def quarantine(args \\ []) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [review: :string, action: :string]
    )

    if opts[:review] do
      review_item(opts[:review], opts[:action])
    else
      show_quarantine()
    end
  end

  defp show_quarantine do
    IO.puts("🔒 Quarantine Zone\n")

    case Quarantine.pending_review() do
      {:ok, []} ->
        IO.puts("✅ No items pending review!")

      {:ok, items} ->
        IO.puts("⚠️  #{length(items)} items pending review:\n")

        Enum.each(items, fn item ->
          IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
          IO.puts("ID: #{item.id}")
          IO.puts("Source: #{item.source_name}")
          IO.puts("URL: #{item.source_url}")
          IO.puts("Tier: #{item.tier}")
          IO.puts("Alerts: #{length(item.alerts)}")
          IO.puts("Validated: #{item.validated_at}")

          if item.snapshot do
            IO.puts("")
            IO.puts("Preview (safe):")
            IO.puts("  #{item.snapshot.preview}")
          end

          IO.puts("")
        end)

        IO.puts("To review: mix cursor_docs.quarantine --review <id> --action <approve|reject|keep_flagged>")

      {:error, reason} ->
        IO.puts("❌ Failed to get quarantine: #{inspect(reason)}")
    end
  end

  defp review_item(item_id, action_str) do
    action = case action_str do
      "approve" -> :approve
      "reject" -> :reject
      "keep_flagged" -> :keep_flagged
      _ ->
        IO.puts("❌ Invalid action. Use: approve, reject, or keep_flagged")
        nil
    end

    if action do
      case Quarantine.mark_reviewed(item_id, "cli_user", action) do
        {:ok, item} ->
          IO.puts("✅ Item #{item_id} marked as #{item.tier}")

        {:error, :not_found} ->
          IO.puts("❌ Item not found: #{item_id}")

        {:error, reason} ->
          IO.puts("❌ Review failed: #{inspect(reason)}")
      end
    end
  end

  # ============================================================================
  # Chat Export Commands
  # ============================================================================

  @doc """
  Chat export CLI.

  ## Commands

      mix cursor_docs.chat list                    # List all chats
      mix cursor_docs.chat stats                   # Show chat statistics
      mix cursor_docs.chat search "query"          # Search chats
      mix cursor_docs.chat show <id>               # Show single chat
      mix cursor_docs.chat export <id>             # Export single chat
      mix cursor_docs.chat export-all              # Export all chats
      mix cursor_docs.chat formats                 # List export formats
      mix cursor_docs.chat presets                 # List markdown presets

  ## Export Options

      --format FORMAT     Export format (markdown, json, jsonl, html, txt)
      --preset PRESET     Markdown preset (obsidian, github, notion, minimal)
      --output DIR        Output directory
      --merged            Export as single merged file

  ## Examples

      mix cursor_docs.chat export abc123 --format markdown --preset obsidian
      mix cursor_docs.chat export-all --format jsonl --output ~/training-data
      mix cursor_docs.chat export-all --format markdown --merged
  """
  def chat(args) do
    {opts, cmd_args, _} = OptionParser.parse(args,
      strict: [
        format: :string,
        preset: :string,
        output: :string,
        merged: :boolean,
        limit: :integer,
        theme: :string
      ]
    )

    case cmd_args do
      ["list" | _] -> chat_list(opts)
      ["stats" | _] -> chat_stats()
      ["search", query | _] -> chat_search(query, opts)
      ["show", id | _] -> chat_show(id)
      ["export", id | _] -> chat_export(id, opts)
      ["export-all" | _] -> chat_export_all(opts)
      ["formats" | _] -> chat_formats()
      ["presets" | _] -> chat_presets()
      _ -> chat_help()
    end
  end

  defp chat_help do
    IO.puts("""
    💬 Cursor Chat Export

    Commands:
      list                    List all chats
      stats                   Show chat statistics
      search "query"          Search chats by content
      show <id>               Display a single chat
      export <id>             Export a single chat
      export-all              Export all chats
      formats                 List supported export formats
      presets                 List markdown formatting presets

    Export Options:
      --format FORMAT         markdown, json, jsonl, html, txt (default: markdown)
      --preset PRESET         obsidian, github, notion, minimal (default: minimal)
      --output DIR            Output directory
      --merged                Export all as single merged file
      --limit N               Limit number of chats
      --theme THEME           HTML theme: light, dark (default: light)

    Examples:
      mix cursor_docs.chat list
      mix cursor_docs.chat export abc123 --format markdown --preset obsidian
      mix cursor_docs.chat export-all --format jsonl --output ~/training
      mix cursor_docs.chat export-all --merged --preset github
    """)
  end

  defp chat_list(opts) do
    IO.puts("💬 Cursor Chats\n")

    case Reader.list_conversations(limit: opts[:limit]) do
      {:ok, []} ->
        IO.puts("No chats found.")
        IO.puts("")
        IO.puts("Make sure Cursor is installed and has chat history.")

      {:ok, conversations} ->
        IO.puts("Found #{length(conversations)} conversations:\n")

        conversations
        |> Enum.take(opts[:limit] || 50)
        |> Enum.each(fn conv ->
          id_short = String.slice(conv.id, 0, 8)
          title = truncate_string(conv.title, 60)
          IO.puts("  [#{id_short}] #{title}")
          IO.puts("           #{conv.message_count} msgs | #{conv.source}")
        end)

        IO.puts("")
        IO.puts("Use: mix cursor_docs.chat show <id> to view a conversation")
        IO.puts("Use: mix cursor_docs.chat export <id> to export")

      {:error, reason} ->
        IO.puts("❌ Failed to list chats: #{inspect(reason)}")
    end
  end

  defp chat_stats do
    IO.puts("📊 Chat Statistics\n")

    case Reader.stats() do
      {:ok, stats} ->
        IO.puts("  📁 Databases: #{stats.databases}")
        IO.puts("  💬 Conversations: #{stats.conversations}")
        IO.puts("  📝 Messages: #{stats.messages}")
        IO.puts("")
        IO.puts("By Source:")
        Enum.each(stats.by_source, fn {source, count} ->
          IO.puts("  • #{source}: #{count}")
        end)

      {:error, reason} ->
        IO.puts("❌ Failed to get stats: #{inspect(reason)}")
    end
  end

  defp chat_search(query, opts) do
    IO.puts("🔍 Searching for: \"#{query}\"\n")

    case Reader.search_conversations(query, limit: opts[:limit] || 20) do
      {:ok, []} ->
        IO.puts("No matching conversations found.")

      {:ok, conversations} ->
        IO.puts("Found #{length(conversations)} matching conversations:\n")

        Enum.each(conversations, fn conv ->
          id_short = String.slice(conv.id, 0, 8)
          title = truncate_string(conv.title, 60)
          IO.puts("  [#{id_short}] #{title}")
          IO.puts("           #{conv.message_count} msgs | #{conv.source}")
        end)

      {:error, reason} ->
        IO.puts("❌ Search failed: #{inspect(reason)}")
    end
  end

  defp chat_show(id) do
    # Allow partial ID matching
    with {:ok, conversations} <- Reader.list_conversations(),
         conv when not is_nil(conv) <- Enum.find(conversations, fn c ->
           String.starts_with?(c.id, id)
         end) do

      IO.puts("💬 #{conv.title}\n")
      IO.puts("ID: #{conv.id}")
      IO.puts("Source: #{conv.source}")
      IO.puts("Messages: #{conv.message_count}")
      IO.puts("")
      IO.puts(String.duplicate("─", 60))
      IO.puts("")

      Enum.each(conv.messages, fn msg ->
        role = if msg.role == :user, do: "👤 User", else: "🤖 Assistant"
        IO.puts("#{role}")
        IO.puts("")

        msg.content
        |> String.split("\n")
        |> Enum.each(fn line ->
          IO.puts("  #{line}")
        end)

        IO.puts("")
        IO.puts(String.duplicate("─", 60))
        IO.puts("")
      end)

    else
      nil ->
        IO.puts("❌ Conversation not found: #{id}")
        IO.puts("Use: mix cursor_docs.chat list to see available IDs")

      {:error, reason} ->
        IO.puts("❌ Failed to get conversation: #{inspect(reason)}")
    end
  end

  defp chat_export(id, opts) do
    format = parse_format(opts[:format])
    export_opts = build_export_opts(opts)

    with {:ok, conversations} <- Reader.list_conversations(),
         conv when not is_nil(conv) <- Enum.find(conversations, fn c ->
           String.starts_with?(c.id, id)
         end),
         {:ok, path} <- Exporter.export_to_file(conv, format, nil, export_opts) do

      IO.puts("✅ Exported to: #{path}")

    else
      nil ->
        IO.puts("❌ Conversation not found: #{id}")

      {:error, reason} ->
        IO.puts("❌ Export failed: #{inspect(reason)}")
    end
  end

  defp chat_export_all(opts) do
    format = parse_format(opts[:format])
    export_opts = build_export_opts(opts)
    merged = opts[:merged] || false

    IO.puts("📤 Exporting all chats as #{format}...")

    result =
      if merged do
        with {:ok, content} <- Exporter.export_merged(format, export_opts) do
          output_dir = Map.get(export_opts, :output_dir, "~/.local/share/cursor-docs/exports")
                       |> Path.expand()
          File.mkdir_p!(output_dir)

          ext = format_extension(format)
          filename = "cursor_chats_merged_#{Date.utc_today()}#{ext}"
          path = Path.join(output_dir, filename)

          File.write!(path, content)
          {:ok, [path]}
        end
      else
        Exporter.export_all(format, export_opts)
      end

    case result do
      {:ok, paths} ->
        IO.puts("✅ Exported #{length(paths)} files")
        IO.puts("")
        paths |> Enum.take(10) |> Enum.each(&IO.puts("   #{&1}"))
        if length(paths) > 10 do
          IO.puts("   ... and #{length(paths) - 10} more")
        end

      {:error, reason} ->
        IO.puts("❌ Export failed: #{inspect(reason)}")
    end
  end

  defp chat_formats do
    IO.puts("📄 Supported Export Formats\n")

    Exporter.formats()
    |> Enum.each(fn fmt ->
      IO.puts("  #{fmt.id} (#{fmt.extension})")
      IO.puts("    #{fmt.description}")
      IO.puts("    Options: #{Enum.join(Enum.map(fmt.options, &to_string/1), ", ")}")
      IO.puts("")
    end)
  end

  defp chat_presets do
    IO.puts("🎨 Markdown Formatting Presets\n")

    Formatter.presets()
    |> Enum.each(fn name ->
      info = Formatter.preset_info(name)
      IO.puts("  #{name}")
      IO.puts("    #{info.description}")
      IO.puts("")
    end)

    IO.puts("Usage: mix cursor_docs.chat export <id> --preset obsidian")
  end

  # Chat export helpers

  defp parse_format(nil), do: :markdown
  defp parse_format("markdown"), do: :markdown
  defp parse_format("md"), do: :markdown
  defp parse_format("json"), do: :json
  defp parse_format("jsonl"), do: :jsonl
  defp parse_format("html"), do: :html
  defp parse_format("txt"), do: :txt
  defp parse_format("text"), do: :txt
  defp parse_format(_), do: :markdown

  defp format_extension(:markdown), do: ".md"
  defp format_extension(:json), do: ".json"
  defp format_extension(:jsonl), do: ".jsonl"
  defp format_extension(:html), do: ".html"
  defp format_extension(:txt), do: ".txt"
  defp format_extension(_), do: ".txt"

  defp build_export_opts(opts) do
    base =
      if opts[:preset] do
        Formatter.preset(String.to_atom(opts[:preset]))
      else
        %{}
      end

    base
    |> Map.put(:output_dir, opts[:output] || "~/.local/share/cursor-docs/exports")
    |> Map.put(:theme, parse_theme(opts[:theme]))
    |> Map.put(:pretty, true)
    |> Map.put(:include_metadata, true)
  end

  defp parse_theme(nil), do: :light
  defp parse_theme("dark"), do: :dark
  defp parse_theme("light"), do: :light
  defp parse_theme(_), do: :light

  defp truncate_string(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end
end
