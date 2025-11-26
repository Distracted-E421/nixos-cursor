defmodule CursorTracker.Config do
  @moduledoc """
  Configuration management for CursorTracker.

  Stores:
  - Tracking directory paths
  - Cursor data directories
  - Tracked file patterns
  - Excluded patterns
  """
  use GenServer
  require Logger

  # ─────────────────────────────────────────────────────────────────────────────
  # Configuration Defaults
  # ─────────────────────────────────────────────────────────────────────────────

  @tracking_root Path.expand("~/.cursor-data-tracking")
  @cursor_home Path.expand("~/.cursor")
  @cursor_config Path.expand("~/.config/Cursor")

  # Files to track
  @tracked_files [
    "User/settings.json",
    "User/keybindings.json",
    "User/snippets"
  ]

  @tracked_cursor_files [
    "mcp.json",
    "argv.json",
    "agents",
    "rules"
  ]

  # Files to exclude (too large/binary)
  @excluded_patterns [
    "*.vscdb",
    "*.db",
    "*.db-journal",
    "Cache/",
    "CachedData/",
    "GPUCache/",
    "blob_storage/",
    "Crashpad/",
    "logs/",
    "*.log",
    "workspaceStorage/"
  ]

  # ─────────────────────────────────────────────────────────────────────────────
  # Client API
  # ─────────────────────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  def tracking_dir(version) do
    if version == "default" do
      Path.join(@tracking_root, "default")
    else
      Path.join(@tracking_root, "cursor-#{version}")
    end
  end

  def cursor_data_dir(version) do
    if version == "default" do
      @cursor_config
    else
      Path.expand("~/.cursor-#{version}")
    end
  end

  def tracked_files, do: @tracked_files
  def tracked_cursor_files, do: @tracked_cursor_files
  def excluded_patterns, do: @excluded_patterns
  def cursor_home, do: @cursor_home

  # ─────────────────────────────────────────────────────────────────────────────
  # Server Callbacks
  # ─────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    config = %{
      tracking_root: @tracking_root,
      cursor_home: @cursor_home,
      cursor_config: @cursor_config,
      tracked_files: @tracked_files,
      tracked_cursor_files: @tracked_cursor_files,
      excluded_patterns: @excluded_patterns
    }

    Logger.debug("CursorTracker.Config initialized: #{inspect(config)}")
    {:ok, config}
  end

  @impl true
  def handle_call({:get, key}, _from, config) do
    {:reply, Map.get(config, key), config}
  end

  @impl true
  def handle_call(:get_all, _from, config) do
    {:reply, config, config}
  end
end
