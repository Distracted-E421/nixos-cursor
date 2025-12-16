defmodule CursorSync.Application do
  @moduledoc """
  OTP Application for Cursor Sync Daemon.
  
  Supervision tree:
  
      CursorSync.Supervisor
      ├── CursorSync.PipeServer      # Named pipe IPC with cursor-studio
      ├── CursorSync.Watcher         # File system watcher for Cursor DBs
      ├── CursorSync.SyncEngine      # Core sync logic
      └── CursorSync.Telemetry       # Metrics and monitoring
  
  The supervision strategy is :one_for_one, meaning if one child crashes,
  only that child is restarted. This ensures fault isolation.
  """
  
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Cursor Sync Daemon v#{Application.spec(:cursor_sync, :vsn)}")
    
    children = [
      # Telemetry supervisor (start first for metrics)
      {CursorSync.Telemetry, []},
      
      # Named pipe server for IPC
      {CursorSync.PipeServer, []},
      
      # File system watcher
      {CursorSync.Watcher, []},
      
      # Sync engine (depends on watcher)
      {CursorSync.SyncEngine, []}
    ]

    opts = [strategy: :one_for_one, name: CursorSync.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Cursor Sync Daemon started successfully")
        maybe_sync_on_start()
        {:ok, pid}
        
      {:error, reason} = error ->
        Logger.error("Failed to start Cursor Sync Daemon: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping Cursor Sync Daemon")
    :ok
  end
  
  defp maybe_sync_on_start do
    if Application.get_env(:cursor_sync, :sync_on_start, true) do
      # Delay sync slightly to ensure everything is initialized
      Process.send_after(CursorSync.SyncEngine, :sync_all, 1000)
    end
  end
end
