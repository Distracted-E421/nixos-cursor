defmodule CursorTracker.GarbageCollector do
  @moduledoc """
  Garbage collection and disk space management for Cursor installations.

  This module provides:
  - Cache cleanup for Cursor installations
  - Orphaned version directory detection and cleanup
  - Nix store garbage collection integration
  - Disk usage analysis and reporting
  - Automatic cleanup scheduling

  ## Usage

      # Analyze disk usage
      CursorTracker.GarbageCollector.analyze()

      # Clean old caches (dry-run by default)
      CursorTracker.GarbageCollector.clean_caches()

      # Actually perform cleanup
      CursorTracker.GarbageCollector.clean_caches(dry_run: false)

      # Full cleanup (caches + orphaned + nix gc)
      CursorTracker.GarbageCollector.full_cleanup(dry_run: false)
  """
  use GenServer
  require Logger

  alias CursorTracker.Config

  # ─────────────────────────────────────────────────────────────────────────────
  # Configuration
  # ─────────────────────────────────────────────────────────────────────────────

  @cache_dirs [
    "Cache",
    "CachedData",
    "CachedExtensions",
    "CachedExtensionVSIXs",
    "GPUCache",
    "Code Cache",
    "blob_storage",
    "Crashpad",
    "logs",
    "Service Worker/CacheStorage"
  ]

  @orphan_check_dirs [
    "~/.cursor-*",
    "~/.config/Cursor/User/workspaceStorage/*"
  ]

  # Files older than this many days are considered stale
  @stale_threshold_days 30

  # ─────────────────────────────────────────────────────────────────────────────
  # Client API
  # ─────────────────────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Analyze disk usage across all Cursor-related directories.

  Returns a map with:
  - `:total_size` - Total bytes used
  - `:cache_size` - Bytes used by caches
  - `:config_size` - Bytes used by configs
  - `:version_dirs` - List of version directories with sizes
  - `:stale_caches` - Caches that can be cleaned
  """
  def analyze do
    GenServer.call(__MODULE__, :analyze, :infinity)
  end

  @doc """
  Clean old cache directories.

  ## Options
    - `:dry_run` - If true, only report what would be cleaned (default: true)
    - `:older_than` - Clean caches older than N days (default: 30)

  ## Returns
    - `{:ok, %{cleaned: bytes, files: count}}` on success
    - `{:error, reason}` on failure
  """
  def clean_caches(opts \\ []) do
    GenServer.call(__MODULE__, {:clean_caches, opts}, :infinity)
  end

  @doc """
  Find and optionally remove orphaned version directories.

  Orphaned directories are version-specific data dirs (e.g., ~/.cursor-2.0.64)
  that no longer have corresponding installed versions.

  ## Options
    - `:dry_run` - If true, only report orphans (default: true)
  """
  def clean_orphaned(opts \\ []) do
    GenServer.call(__MODULE__, {:clean_orphaned, opts}, :infinity)
  end

  @doc """
  Run Nix garbage collection for Cursor packages.

  ## Options
    - `:dry_run` - If true, only report what would be removed (default: true)
    - `:older_than` - Remove generations older than N days (default: 30)
  """
  def nix_gc(opts \\ []) do
    GenServer.call(__MODULE__, {:nix_gc, opts}, :infinity)
  end

  @doc """
  Perform full cleanup: caches + orphaned + nix gc.

  ## Options
    - `:dry_run` - If true, only report what would be cleaned (default: true)
  """
  def full_cleanup(opts \\ []) do
    GenServer.call(__MODULE__, {:full_cleanup, opts}, :infinity)
  end

  @doc """
  Get disk space recommendations.

  Returns prioritized list of cleanup actions based on disk usage.
  """
  def recommendations do
    GenServer.call(__MODULE__, :recommendations, :infinity)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Server Callbacks
  # ─────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.info("GarbageCollector initialized")
    {:ok, %{last_analysis: nil}}
  end

  @impl true
  def handle_call(:analyze, _from, state) do
    analysis = do_analyze()
    {:reply, {:ok, analysis}, %{state | last_analysis: analysis}}
  end

  @impl true
  def handle_call({:clean_caches, opts}, _from, state) do
    result = do_clean_caches(opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:clean_orphaned, opts}, _from, state) do
    result = do_clean_orphaned(opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:nix_gc, opts}, _from, state) do
    result = do_nix_gc(opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:full_cleanup, opts}, _from, state) do
    result = do_full_cleanup(opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:recommendations, _from, state) do
    analysis = state.last_analysis || do_analyze()
    result = do_recommendations(analysis)
    {:reply, {:ok, result}, %{state | last_analysis: analysis}}
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Implementation
  # ─────────────────────────────────────────────────────────────────────────────

  defp do_analyze do
    cursor_config = Config.cursor_data_dir("default")
    cursor_home = Config.cursor_home()

    # Analyze main config directory
    config_size = dir_size(cursor_config)

    # Analyze cache directories
    cache_info = analyze_caches(cursor_config)

    # Find version directories
    version_dirs = find_version_dirs()

    # Find stale workspace storage
    stale_workspaces = find_stale_workspaces(cursor_config)

    %{
      total_size: config_size + Enum.sum(Enum.map(version_dirs, & &1.size)),
      config_size: config_size,
      cache_size: cache_info.total_size,
      version_dirs: version_dirs,
      stale_caches: cache_info.stale,
      stale_workspaces: stale_workspaces,
      cursor_home: cursor_home,
      cursor_config: cursor_config
    }
  end

  defp analyze_caches(base_dir) do
    caches = Enum.map(@cache_dirs, fn dir ->
      path = Path.join(base_dir, dir)
      if File.exists?(path) do
        size = dir_size(path)
        mtime = get_mtime(path)
        stale = stale?(mtime, @stale_threshold_days)
        %{path: path, size: size, mtime: mtime, stale: stale}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    %{
      dirs: caches,
      total_size: Enum.sum(Enum.map(caches, & &1.size)),
      stale: Enum.filter(caches, & &1.stale)
    }
  end

  defp find_version_dirs do
    home = System.user_home!()
    pattern = Path.join(home, ".cursor-*")

    Path.wildcard(pattern)
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn path ->
      name = Path.basename(path)
      version = String.replace_prefix(name, ".cursor-", "")
      size = dir_size(path)
      mtime = get_mtime(path)

      %{
        path: path,
        name: name,
        version: version,
        size: size,
        mtime: mtime
      }
    end)
  end

  defp find_stale_workspaces(cursor_config) do
    workspace_dir = Path.join(cursor_config, "User/workspaceStorage")

    if File.exists?(workspace_dir) do
      File.ls!(workspace_dir)
      |> Enum.map(fn dir ->
        path = Path.join(workspace_dir, dir)
        size = dir_size(path)
        mtime = get_mtime(path)
        workspace_json = Path.join(path, "workspace.json")

        # Check if workspace still exists
        orphaned = if File.exists?(workspace_json) do
          case File.read(workspace_json) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, %{"folder" => folder}} -> not File.exists?(folder)
                _ -> false
              end
            _ -> false
          end
        else
          true
        end

        %{
          path: path,
          id: dir,
          size: size,
          mtime: mtime,
          orphaned: orphaned,
          stale: stale?(mtime, @stale_threshold_days) or orphaned
        }
      end)
      |> Enum.filter(& &1.stale)
    else
      []
    end
  end

  defp do_clean_caches(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)
    older_than = Keyword.get(opts, :older_than, @stale_threshold_days)

    cursor_config = Config.cursor_data_dir("default")

    to_clean = Enum.flat_map(@cache_dirs, fn dir ->
      path = Path.join(cursor_config, dir)
      if File.exists?(path) and stale?(get_mtime(path), older_than) do
        [%{path: path, size: dir_size(path)}]
      else
        []
      end
    end)

    total_size = Enum.sum(Enum.map(to_clean, & &1.size))
    count = length(to_clean)

    if dry_run do
      Logger.info("[DRY RUN] Would clean #{format_size(total_size)} from #{count} cache dirs")
      {:ok, %{would_clean: total_size, count: count, dirs: to_clean, dry_run: true}}
    else
      Enum.each(to_clean, fn %{path: path} ->
        Logger.info("Cleaning: #{path}")
        File.rm_rf!(path)
      end)
      Logger.info("Cleaned #{format_size(total_size)} from #{count} cache directories")
      {:ok, %{cleaned: total_size, count: count, dry_run: false}}
    end
  end

  defp do_clean_orphaned(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)

    # Find installed versions (check Nix store or PATH)
    installed = find_installed_versions()

    # Find all version data directories
    version_dirs = find_version_dirs()

    # Orphans are data dirs without installed versions
    orphans = Enum.filter(version_dirs, fn dir ->
      not MapSet.member?(installed, dir.version) and dir.version != "default"
    end)

    total_size = Enum.sum(Enum.map(orphans, & &1.size))
    count = length(orphans)

    if dry_run do
      Logger.info("[DRY RUN] Would clean #{format_size(total_size)} from #{count} orphaned dirs")
      {:ok, %{would_clean: total_size, count: count, orphans: orphans, dry_run: true}}
    else
      Enum.each(orphans, fn %{path: path} ->
        Logger.info("Removing orphaned: #{path}")
        File.rm_rf!(path)
      end)
      Logger.info("Cleaned #{format_size(total_size)} from #{count} orphaned directories")
      {:ok, %{cleaned: total_size, count: count, dry_run: false}}
    end
  end

  defp do_nix_gc(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)
    older_than = Keyword.get(opts, :older_than, @stale_threshold_days)

    # Run nix-store --gc with dry-run option
    args = if dry_run do
      ["--gc", "--print-dead"]
    else
      ["--gc"]
    end

    case System.cmd("nix-store", args, stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output to estimate size
        paths = String.split(output, "\n", trim: true)
        count = length(paths)

        if dry_run do
          Logger.info("[DRY RUN] Would collect #{count} dead store paths")
          {:ok, %{would_collect: count, paths: Enum.take(paths, 20), dry_run: true}}
        else
          Logger.info("Collected garbage from Nix store")
          {:ok, %{collected: count, dry_run: false}}
        end

      {error, code} ->
        Logger.error("Nix GC failed (#{code}): #{error}")
        {:error, "Nix GC failed: #{error}"}
    end
  rescue
    _ -> {:error, "nix-store not available"}
  end

  defp do_full_cleanup(opts) do
    dry_run = Keyword.get(opts, :dry_run, true)

    results = %{
      caches: do_clean_caches(opts),
      orphaned: do_clean_orphaned(opts),
      nix_gc: do_nix_gc(opts)
    }

    total_cleaned = calculate_total_cleaned(results)

    if dry_run do
      Logger.info("[DRY RUN] Full cleanup would free #{format_size(total_cleaned)}")
    else
      Logger.info("Full cleanup complete - freed #{format_size(total_cleaned)}")
    end

    {:ok, Map.put(results, :total, total_cleaned)}
  end

  defp do_recommendations(analysis) do
    recommendations = []

    # Check cache size
    if analysis.cache_size > 500_000_000 do
      recommendations = [
        %{
          priority: :high,
          action: :clean_caches,
          message: "Cache directories using #{format_size(analysis.cache_size)} - recommend cleanup",
          potential_savings: analysis.cache_size
        }
        | recommendations
      ]
    end

    # Check for stale workspaces
    stale_size = Enum.sum(Enum.map(analysis.stale_workspaces, & &1.size))
    if stale_size > 100_000_000 do
      recommendations = [
        %{
          priority: :medium,
          action: :clean_workspaces,
          message: "#{length(analysis.stale_workspaces)} stale workspaces using #{format_size(stale_size)}",
          potential_savings: stale_size
        }
        | recommendations
      ]
    end

    # Check for version directories
    if length(analysis.version_dirs) > 3 do
      total = Enum.sum(Enum.map(analysis.version_dirs, & &1.size))
      recommendations = [
        %{
          priority: :low,
          action: :review_versions,
          message: "#{length(analysis.version_dirs)} version directories using #{format_size(total)}",
          potential_savings: 0
        }
        | recommendations
      ]
    end

    Enum.sort_by(recommendations, &priority_order/1)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────────────────

  defp dir_size(path) do
    case System.cmd("du", ["-sb", path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split()
        |> List.first()
        |> String.to_integer()
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp get_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp stale?(mtime, days) do
    threshold = :os.system_time(:second) - (days * 24 * 60 * 60)
    mtime < threshold
  end

  defp find_installed_versions do
    # Check which cursor versions are installed via `which` or Nix store
    versions = case System.cmd("bash", ["-c", "compgen -c | grep '^cursor-' | sort -u"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.replace_prefix(&1, "cursor-", ""))
      _ -> []
    end

    MapSet.new(versions)
  rescue
    _ -> MapSet.new()
  end

  defp calculate_total_cleaned(%{caches: caches, orphaned: orphaned}) do
    cache_size = case caches do
      {:ok, %{cleaned: n}} -> n
      {:ok, %{would_clean: n}} -> n
      _ -> 0
    end

    orphan_size = case orphaned do
      {:ok, %{cleaned: n}} -> n
      {:ok, %{would_clean: n}} -> n
      _ -> 0
    end

    cache_size + orphan_size
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

  defp priority_order(%{priority: :high}), do: 0
  defp priority_order(%{priority: :medium}), do: 1
  defp priority_order(%{priority: :low}), do: 2
end
