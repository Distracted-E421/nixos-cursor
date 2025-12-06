defmodule CursorSync.Watcher do
  @moduledoc """
  File System Watcher for Cursor Databases.
  
  Watches for changes to:
  - Global state.vscdb
  - Workspace state.vscdb files
  
  Uses the `file_system` library which wraps inotify (Linux),
  FSEvents (macOS), and ReadDirectoryChangesW (Windows).
  
  ## Debouncing
  
  Database writes often come in bursts. We debounce events to avoid
  excessive sync operations. Default debounce is 500ms.
  
  ## Hot Reload
  
  The watcher can be hot-reloaded to add new paths without restart:
  
      iex> CursorSync.Watcher.add_path("/some/new/path")
  """
  
  use GenServer
  require Logger

  @type state :: %{
    watcher_pid: pid() | nil,
    watched_paths: [String.t()],
    pending_events: %{String.t() => reference()},
    debounce_ms: non_neg_integer()
  }

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a new path to watch"
  def add_path(path) do
    GenServer.call(__MODULE__, {:add_path, path})
  end

  @doc "Get list of watched paths"
  def watched_paths do
    GenServer.call(__MODULE__, :watched_paths)
  end

  @doc "Get watcher status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    Logger.info("Initializing FileSystem watcher")
    
    debounce_ms = Application.get_env(:cursor_sync, :debounce_ms, 500)
    
    # Collect paths to watch
    paths = collect_watch_paths()
    
    # Start the file system watcher
    {:ok, watcher_pid} = FileSystem.start_link(dirs: paths)
    FileSystem.subscribe(watcher_pid)
    
    Logger.info("Watching #{length(paths)} paths: #{inspect(paths)}")
    
    state = %{
      watcher_pid: watcher_pid,
      watched_paths: paths,
      pending_events: %{},
      debounce_ms: debounce_ms
    }
    
    {:ok, state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    # Only care about :modified events for .vscdb files
    if :modified in events and String.ends_with?(path, ".vscdb") do
      Logger.debug("Database modified: #{path}")
      state = schedule_sync(path, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warning("FileSystem watcher stopped unexpectedly")
    # Restart watcher
    send(self(), :restart_watcher)
    {:noreply, state}
  end

  @impl true
  def handle_info(:restart_watcher, state) do
    Logger.info("Restarting FileSystem watcher")
    
    # Stop old watcher if running
    if state.watcher_pid do
      FileSystem.stop(state.watcher_pid)
    end
    
    # Start new watcher
    {:ok, watcher_pid} = FileSystem.start_link(dirs: state.watched_paths)
    FileSystem.subscribe(watcher_pid)
    
    {:noreply, %{state | watcher_pid: watcher_pid}}
  end

  @impl true
  def handle_info({:debounced_sync, path}, state) do
    # Remove from pending and trigger sync
    {_ref, pending} = Map.pop(state.pending_events, path)
    
    Logger.info("Triggering sync for: #{path}")
    
    # Determine workspace from path
    workspace = extract_workspace(path)
    CursorSync.SyncEngine.sync(workspace)
    
    {:noreply, %{state | pending_events: pending}}
  end

  @impl true
  def handle_call({:add_path, path}, _from, state) do
    if File.exists?(path) do
      # Add to watched paths
      paths = [path | state.watched_paths] |> Enum.uniq()
      
      # Restart watcher with new paths
      FileSystem.stop(state.watcher_pid)
      {:ok, watcher_pid} = FileSystem.start_link(dirs: paths)
      FileSystem.subscribe(watcher_pid)
      
      Logger.info("Added watch path: #{path}")
      
      {:reply, :ok, %{state | watcher_pid: watcher_pid, watched_paths: paths}}
    else
      {:reply, {:error, :path_not_found}, state}
    end
  end

  @impl true
  def handle_call(:watched_paths, _from, state) do
    {:reply, state.watched_paths, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      watcher_running: state.watcher_pid != nil,
      watched_paths: state.watched_paths,
      pending_events: map_size(state.pending_events),
      debounce_ms: state.debounce_ms
    }
    {:reply, status, state}
  end

  # ============================================
  # Private Functions
  # ============================================

  defp collect_watch_paths do
    global_db = Application.get_env(:cursor_sync, :global_db)
    workspace_storage = Application.get_env(:cursor_sync, :workspace_storage)
    
    paths = []
    
    # Add global storage directory (parent of state.vscdb)
    paths = if global_db && File.exists?(global_db) do
      [Path.dirname(global_db) | paths]
    else
      Logger.warning("Global database not found: #{global_db}")
      paths
    end
    
    # Add workspace storage directory
    paths = if workspace_storage && File.dir?(workspace_storage) do
      [workspace_storage | paths]
    else
      Logger.warning("Workspace storage not found: #{workspace_storage}")
      paths
    end
    
    Enum.uniq(paths)
  end

  defp schedule_sync(path, state) do
    # Cancel existing timer for this path
    state = case Map.get(state.pending_events, path) do
      nil -> state
      ref -> 
        Process.cancel_timer(ref)
        %{state | pending_events: Map.delete(state.pending_events, path)}
    end
    
    # Schedule new debounced sync
    ref = Process.send_after(self(), {:debounced_sync, path}, state.debounce_ms)
    %{state | pending_events: Map.put(state.pending_events, path, ref)}
  end

  defp extract_workspace(path) do
    # Extract workspace hash from path like:
    # ~/.config/Cursor/User/workspaceStorage/abc123/state.vscdb
    case Regex.run(~r/workspaceStorage\/([^\/]+)\//, path) do
      [_, workspace_hash] -> workspace_hash
      _ -> nil
    end
  end
end
