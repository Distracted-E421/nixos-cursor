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
    {opts, [url | _], _} = OptionParser.parse(args,
      strict: [name: :string, max_pages: :integer]
    )

    IO.puts("📥 Adding documentation: #{url}")

    case CursorDocs.add(url, opts) do
      {:ok, source} ->
        IO.puts("✅ Queued for indexing")
        IO.puts("   Name: #{source[:name]}")
        IO.puts("   ID: #{source[:id]}")
        IO.puts("")
        IO.puts("Use `mix cursor_docs.status` to check progress")

      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
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

    IO.puts("🔍 Searching: #{query}\n")

    search_opts = [
      limit: opts[:limit] || 5,
      sources: if(opts[:source], do: [opts[:source]], else: [])
    ]

    case CursorDocs.search(query, search_opts) do
      {:ok, []} ->
        IO.puts("No results found.")

      {:ok, results} ->
        Enum.each(results, fn result ->
          IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
          IO.puts("📄 #{result[:title]}")
          IO.puts("   URL: #{result[:url]}")
          IO.puts("   Score: #{Float.round(result[:score] || 0.0, 2)}")
          IO.puts("")
          IO.puts(result[:snippet] || String.slice(result[:content], 0, 300))
          IO.puts("")
        end)

      {:error, reason} ->
        IO.puts("❌ Search failed: #{inspect(reason)}")
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
        IO.puts(String.pad_trailing("Name", 20) <>
                String.pad_trailing("Pages", 8) <>
                String.pad_trailing("Status", 12) <>
                "URL")
        IO.puts(String.duplicate("─", 80))

        Enum.each(sources, fn source ->
          status_icon = case source[:status] do
            "indexed" -> "✅"
            "indexing" -> "⏳"
            "failed" -> "❌"
            _ -> "⏸️"
          end

          IO.puts(
            String.pad_trailing(source[:name] || "Unknown", 20) <>
            String.pad_trailing("#{source[:pages_count] || 0}", 8) <>
            String.pad_trailing("#{status_icon} #{source[:status]}", 12) <>
            (source[:url] || "")
          )
        end)

      {:error, reason} ->
        IO.puts("❌ Failed to list: #{inspect(reason)}")
    end
  end

  @doc """
  Check scraping job status.
  """
  def status do
    IO.puts("📊 Scraping Status\n")

    case CursorDocs.status() do
      {:ok, []} ->
        IO.puts("No active scraping jobs.")

      {:ok, jobs} ->
        Enum.each(jobs, fn job ->
          IO.puts("• #{job[:source] || "Unknown"}")
          IO.puts("  Status: #{job[:status]}")
          IO.puts("  Pages: #{job[:pages] || 0}")
          IO.puts("  Queued: #{job[:queued] || 0}")
          IO.puts("")
        end)

      {:error, reason} ->
        IO.puts("❌ Failed to get status: #{inspect(reason)}")
    end
  end
end

