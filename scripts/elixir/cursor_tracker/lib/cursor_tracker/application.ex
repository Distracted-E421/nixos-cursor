defmodule CursorTracker.Application do
  @moduledoc """
  OTP Application for CursorTracker.

  Starts the supervision tree with:
  - Config server (application configuration)
  - GitBackend server (git operations)
  - DataWatcher server (file system monitoring)
  - GarbageCollector server (disk space management)
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting CursorTracker...")

    children = [
      # Configuration server
      CursorTracker.Config,

      # Git backend for snapshots
      CursorTracker.GitBackend,

      # File watcher (optional, can be enabled later)
      {CursorTracker.DataWatcher, []},

      # Garbage collector for disk space management
      CursorTracker.GarbageCollector
    ]

    opts = [strategy: :one_for_one, name: CursorTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
