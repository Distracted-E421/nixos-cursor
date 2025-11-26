defmodule CursorTracker do
  @moduledoc """
  CursorTracker - Git-based tracking for Cursor user data.

  This OTP application provides:
  - Automatic file watching for Cursor configuration changes
  - Git-based snapshots with diff and blame capabilities
  - Rollback to previous configurations
  - Comparison between Cursor instances

  ## Usage

  Start the application:

      iex -S mix

  Or run as a release:

      ./cursor_tracker start

  ## Architecture

  ```
  CursorTracker.Application
  └── CursorTracker.Supervisor
      ├── CursorTracker.Config (GenServer - configuration)
      ├── CursorTracker.GitBackend (GenServer - git operations)
      └── CursorTracker.DataWatcher (GenServer - file watching)
  ```
  """

  alias CursorTracker.{Config, GitBackend, Snapshot}

  @doc """
  Initialize tracking for a Cursor instance.

  ## Options
    - `:version` - Cursor version (default: "default")
    - `:cursor_dir` - Path to Cursor config (default: ~/.config/Cursor)

  ## Examples

      CursorTracker.init()
      CursorTracker.init(version: "2.0.77")
  """
  def init(opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    GitBackend.init(version)
  end

  @doc """
  Take a snapshot of the current Cursor configuration.

  ## Examples

      CursorTracker.snapshot("Before upgrade")
      CursorTracker.snapshot("Testing new settings", version: "2.1.34")
  """
  def snapshot(message, opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    Snapshot.take(version, message)
  end

  @doc """
  Show the current status (uncommitted changes).

  ## Examples

      CursorTracker.status()
      CursorTracker.status(version: "2.0.77")
  """
  def status(opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    GitBackend.status(version)
  end

  @doc """
  Show diff between current state and a reference.

  ## Examples

      CursorTracker.diff()
      CursorTracker.diff("HEAD~1")
      CursorTracker.diff("HEAD~3", version: "2.0.77")
  """
  def diff(ref \\ "HEAD~1", opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    GitBackend.diff(version, ref)
  end

  @doc """
  Show commit history.

  ## Examples

      CursorTracker.history()
      CursorTracker.history(limit: 5)
  """
  def history(opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    limit = Keyword.get(opts, :limit, 20)
    GitBackend.history(version, limit)
  end

  @doc """
  Show blame for a specific file.

  ## Examples

      CursorTracker.blame("User/settings.json")
  """
  def blame(file, opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    GitBackend.blame(version, file)
  end

  @doc """
  Rollback to a previous snapshot.

  ## Examples

      CursorTracker.rollback("HEAD~1")
      CursorTracker.rollback("abc123", version: "2.0.77")
  """
  def rollback(ref, opts \\ []) do
    version = Keyword.get(opts, :version, "default")
    Snapshot.rollback(version, ref)
  end

  @doc """
  Compare two Cursor instances.

  ## Examples

      CursorTracker.compare("2.0.77", "2.1.34")
  """
  def compare(version1, version2) do
    Snapshot.compare(version1, version2)
  end

  @doc """
  List all tracked instances.
  """
  def list_instances do
    GitBackend.list_instances()
  end

  @doc """
  Start watching for file changes (auto-snapshot mode).

  ## Options
    - `:interval` - Minimum time between auto-snapshots (default: 5 minutes)

  ## Examples

      CursorTracker.watch()
      CursorTracker.watch(interval: :timer.minutes(10))
  """
  def watch(opts \\ []) do
    CursorTracker.DataWatcher.start_watching(opts)
  end

  @doc """
  Stop watching for file changes.
  """
  def unwatch do
    CursorTracker.DataWatcher.stop_watching()
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Garbage Collection
  # ─────────────────────────────────────────────────────────────────────────────

  @doc """
  Analyze disk usage across all Cursor-related directories.

  ## Examples

      CursorTracker.analyze()
  """
  def analyze do
    CursorTracker.GarbageCollector.analyze()
  end

  @doc """
  Clean old cache directories.

  ## Options
    - `:dry_run` - If true, only report what would be cleaned (default: true)
    - `:older_than` - Clean caches older than N days (default: 30)

  ## Examples

      CursorTracker.clean_caches()                    # Dry run
      CursorTracker.clean_caches(dry_run: false)      # Actually clean
  """
  def clean_caches(opts \\ []) do
    CursorTracker.GarbageCollector.clean_caches(opts)
  end

  @doc """
  Find and optionally remove orphaned version directories.

  ## Examples

      CursorTracker.clean_orphaned()                  # Dry run
      CursorTracker.clean_orphaned(dry_run: false)    # Actually clean
  """
  def clean_orphaned(opts \\ []) do
    CursorTracker.GarbageCollector.clean_orphaned(opts)
  end

  @doc """
  Run Nix garbage collection for Cursor packages.

  ## Examples

      CursorTracker.nix_gc()                          # Dry run
      CursorTracker.nix_gc(dry_run: false)            # Actually collect
  """
  def nix_gc(opts \\ []) do
    CursorTracker.GarbageCollector.nix_gc(opts)
  end

  @doc """
  Perform full cleanup: caches + orphaned + nix gc.

  ## Examples

      CursorTracker.full_cleanup()                    # Dry run
      CursorTracker.full_cleanup(dry_run: false)      # Actually clean
  """
  def full_cleanup(opts \\ []) do
    CursorTracker.GarbageCollector.full_cleanup(opts)
  end

  @doc """
  Get disk space recommendations.

  Returns prioritized list of cleanup actions based on disk usage.

  ## Examples

      CursorTracker.recommendations()
  """
  def recommendations do
    CursorTracker.GarbageCollector.recommendations()
  end
end
