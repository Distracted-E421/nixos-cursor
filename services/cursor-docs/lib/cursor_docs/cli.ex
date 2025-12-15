defmodule CursorDocs.CLI do
  @moduledoc """
  Command-line interface for CursorDocs.

  Provides mix tasks for:
  - Adding documentation
  - Searching indexed content
  - Listing sources
  - Checking status

  ## Usage

      mix cursor_docs.add https://docs.example.com/
      mix cursor_docs.search "authentication"
      mix cursor_docs.list
      mix cursor_docs.status
  """

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
            do_refresh(source[:id])

          {:not_found, _} ->
            IO.puts("📥 Adding documentation: #{url}")
            IO.puts("   (This may take a moment...)\n")

            add_opts = [
              name: opts[:name],
              max_pages: opts[:max_pages] || 100,
              follow_links: opts[:follow] || false
            ] |> Enum.reject(fn {_k, v} -> is_nil(v) end)

            case CursorDocs.add(url, add_opts) do
              {:ok, source} ->
                IO.puts("✅ Indexed successfully!")
                IO.puts("   Name: #{source[:name]}")
                IO.puts("   ID: #{source[:id]}")
                IO.puts("   Chunks: #{source[:chunks_count] || 0}")
                IO.puts("")
                IO.puts("Search with: mix cursor_docs.search \"your query\"")

              {:error, reason} ->
                IO.puts("❌ Failed: #{inspect(reason)}")
            end
        end
    end
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
end
