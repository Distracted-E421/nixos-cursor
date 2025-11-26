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

      _ ->
        Optimus.parse!(cli_spec(), ["--help"])
    end
  end

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
        ]
      ]
    )
  end
end
