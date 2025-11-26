defmodule CursorTracker.CLI do
  @moduledoc """
  Command-line interface for CursorTracker.
  """
  alias CursorTracker.{GitBackend, Snapshot}

  def main(args) do
    case Optimus.parse!(cli_spec(), args) do
      {[:init], %{options: opts}} ->
        version = opts[:version] || "default"
        case CursorTracker.init(version: version) do
          {:ok, result} ->
            IO.puts("✓ Initialized tracking for Cursor #{version}")
            IO.puts("  Tracking dir: #{result.tracking_dir}")
          {:error, reason} ->
            IO.puts("✗ Failed: #{reason}")
            System.halt(1)
        end

      {[:snapshot], %{args: %{message: message}, options: opts}} ->
        version = opts[:version] || "default"
        case CursorTracker.snapshot(message, version: version) do
          {:ok, :committed} -> IO.puts("✓ Snapshot created")
          {:ok, :no_changes} -> IO.puts("ℹ No changes to snapshot")
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:status], %{options: opts}} ->
        version = opts[:version] || "default"
        case CursorTracker.status(version: version) do
          {:ok, :clean} -> IO.puts("✓ No uncommitted changes")
          {:ok, {:changes, files}} ->
            IO.puts("Modified files:")
            Enum.each(files, fn f -> IO.puts("  #{f.status} #{f.file}") end)
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:diff], %{args: %{ref: ref}, options: opts}} ->
        version = opts[:version] || "default"
        case CursorTracker.diff(ref, version: version) do
          {:ok, diff} -> IO.puts(diff)
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:history], %{options: opts}} ->
        version = opts[:version] || "default"
        limit = opts[:limit] || 20
        case CursorTracker.history(version: version, limit: limit) do
          {:ok, commits} ->
            Enum.each(commits, fn c -> IO.puts("#{c.hash} #{c.message}") end)
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:rollback], %{args: %{ref: ref}, options: opts}} ->
        version = opts[:version] || "default"
        case CursorTracker.rollback(ref, version: version) do
          {:ok, :rolled_back} -> IO.puts("✓ Rolled back to #{ref}")
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:list], _} ->
        case CursorTracker.list_instances() do
          {:ok, instances} ->
            IO.puts("Tracked Cursor instances:")
            Enum.each(instances, fn i ->
              IO.puts("  #{i.name} - #{i.snapshots} snapshots, last: #{i.last_update}")
            end)
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:watch], %{options: opts}} ->
        interval = (opts[:interval] || 5) * 60_000
        CursorTracker.watch(interval: interval)
        IO.puts("✓ Watching for changes (interval: #{opts[:interval] || 5} min)")
        IO.puts("  Press Ctrl+C to stop")
        Process.sleep(:infinity)

      # Garbage Collection Commands
      {[:analyze], _} ->
        case CursorTracker.analyze() do
          {:ok, analysis} ->
            IO.puts("📊 Cursor Disk Usage Analysis")
            IO.puts("")
            IO.puts("Total size:     #{format_size(analysis.total_size)}")
            IO.puts("Config size:    #{format_size(analysis.config_size)}")
            IO.puts("Cache size:     #{format_size(analysis.cache_size)}")
            IO.puts("")
            if length(analysis.version_dirs) > 0 do
              IO.puts("Version directories:")
              Enum.each(analysis.version_dirs, fn dir ->
                IO.puts("  #{dir.name}: #{format_size(dir.size)}")
              end)
            end
            if length(analysis.stale_caches) > 0 do
              IO.puts("")
              IO.puts("Stale caches (can be cleaned):")
              Enum.each(analysis.stale_caches, fn cache ->
                IO.puts("  #{Path.basename(cache.path)}: #{format_size(cache.size)}")
              end)
            end
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      {[:gc], %{options: opts}} ->
        dry_run = not opts[:force]
        case opts[:type] || "caches" do
          "caches" ->
            case CursorTracker.clean_caches(dry_run: dry_run) do
              {:ok, %{dry_run: true} = result} ->
                IO.puts("[DRY RUN] Would clean #{format_size(result.would_clean)} from #{result.count} directories")
                IO.puts("  Run with --force to actually clean")
              {:ok, result} ->
                IO.puts("✓ Cleaned #{format_size(result.cleaned)} from #{result.count} directories")
              {:error, reason} -> IO.puts("✗ Failed: #{reason}")
            end

          "orphaned" ->
            case CursorTracker.clean_orphaned(dry_run: dry_run) do
              {:ok, %{dry_run: true} = result} ->
                IO.puts("[DRY RUN] Would clean #{format_size(result.would_clean)} from #{result.count} orphaned directories")
                Enum.each(result.orphans, fn o -> IO.puts("  #{o.name}") end)
                IO.puts("  Run with --force to actually clean")
              {:ok, result} ->
                IO.puts("✓ Cleaned #{format_size(result.cleaned)} from #{result.count} orphaned directories")
              {:error, reason} -> IO.puts("✗ Failed: #{reason}")
            end

          "nix" ->
            case CursorTracker.nix_gc(dry_run: dry_run) do
              {:ok, %{dry_run: true} = result} ->
                IO.puts("[DRY RUN] Would collect #{result.would_collect} store paths")
                IO.puts("  Run with --force to actually collect")
              {:ok, result} ->
                IO.puts("✓ Collected #{result.collected} store paths")
              {:error, reason} -> IO.puts("✗ Failed: #{reason}")
            end

          "full" ->
            case CursorTracker.full_cleanup(dry_run: dry_run) do
              {:ok, result} ->
                if dry_run do
                  IO.puts("[DRY RUN] Full cleanup would free #{format_size(result.total)}")
                  IO.puts("  Run with --force to actually clean")
                else
                  IO.puts("✓ Full cleanup freed #{format_size(result.total)}")
                end
              {:error, reason} -> IO.puts("✗ Failed: #{reason}")
            end

          other ->
            IO.puts("Unknown gc type: #{other}")
            IO.puts("Valid types: caches, orphaned, nix, full")
        end

      {[:recommend], _} ->
        case CursorTracker.recommendations() do
          {:ok, []} ->
            IO.puts("✓ No cleanup recommendations - disk usage looks good!")
          {:ok, recs} ->
            IO.puts("📋 Cleanup Recommendations")
            IO.puts("")
            Enum.each(recs, fn r ->
              priority = case r.priority do
                :high -> "🔴"
                :medium -> "🟡"
                :low -> "🟢"
              end
              IO.puts("#{priority} #{r.message}")
              if r.potential_savings > 0 do
                IO.puts("   Potential savings: #{format_size(r.potential_savings)}")
              end
            end)
          {:error, reason} -> IO.puts("✗ Failed: #{reason}")
        end

      _ ->
        Optimus.parse!(cli_spec(), ["--help"])
    end
  end

  defp format_size(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end
  defp format_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end
  defp format_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end
  defp format_size(bytes), do: "#{bytes} B"

  defp cli_spec do
    Optimus.new!(
      name: "cursor-tracker",
      description: "Git-based tracking for Cursor user data",
      version: "0.1.0",
      subcommands: [
        init: [
          name: "init",
          about: "Initialize tracking for a Cursor instance",
          options: [version: [short: "-v", long: "--version", help: "Cursor version", required: false]]
        ],
        snapshot: [
          name: "snapshot",
          about: "Take a snapshot of current configuration",
          args: [message: [help: "Snapshot message", required: true]],
          options: [version: [short: "-v", long: "--version", help: "Cursor version", required: false]]
        ],
        status: [
          name: "status",
          about: "Show uncommitted changes",
          options: [version: [short: "-v", long: "--version", help: "Cursor version", required: false]]
        ],
        diff: [
          name: "diff",
          about: "Show diff from a reference",
          args: [ref: [help: "Git reference (e.g., HEAD~1)", required: true]],
          options: [version: [short: "-v", long: "--version", help: "Cursor version", required: false]]
        ],
        history: [
          name: "history",
          about: "Show snapshot history",
          options: [
            version: [short: "-v", long: "--version", help: "Cursor version", required: false],
            limit: [short: "-n", long: "--limit", help: "Number of commits", parser: :integer, required: false]
          ]
        ],
        rollback: [
          name: "rollback",
          about: "Rollback to a previous snapshot",
          args: [ref: [help: "Git reference to rollback to", required: true]],
          options: [version: [short: "-v", long: "--version", help: "Cursor version", required: false]]
        ],
        list: [
          name: "list",
          about: "List all tracked instances"
        ],
        watch: [
          name: "watch",
          about: "Watch for changes and auto-snapshot",
          options: [interval: [short: "-i", long: "--interval", help: "Minutes between snapshots", parser: :integer, required: false]]
        ],

        # Garbage Collection Commands
        analyze: [
          name: "analyze",
          about: "Analyze disk usage for Cursor directories"
        ],
        gc: [
          name: "gc",
          about: "Run garbage collection",
          options: [
            type: [short: "-t", long: "--type", help: "Type: caches, orphaned, nix, full (default: caches)", required: false],
            force: [short: "-f", long: "--force", help: "Actually perform cleanup (default: dry-run)", required: false]
          ]
        ],
        recommend: [
          name: "recommend",
          about: "Get cleanup recommendations based on disk usage"
        ]
      ]
    )
  end
end
