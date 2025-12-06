defmodule CursorSync.Telemetry do
  @moduledoc """
  Telemetry and metrics for Cursor Sync Daemon.
  
  Emits telemetry events for:
  - Sync operations (start, stop, duration, counts)
  - Pipe communication (commands received, responses sent)
  - File watcher events (database changes detected)
  - Errors and warnings
  
  ## Metrics
  
  Use with telemetry_metrics to expose:
  
      [
        counter("cursor_sync.sync.completed.count"),
        sum("cursor_sync.sync.messages.count"),
        last_value("cursor_sync.sync.duration.milliseconds"),
        counter("cursor_sync.pipe.commands.count"),
        counter("cursor_sync.watcher.events.count")
      ]
  """
  
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Periodic metrics reporter
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    
    # Attach event handlers
    attach_handlers()
    
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ============================================
  # Event Handlers
  # ============================================

  defp attach_handlers do
    :telemetry.attach_many(
      "cursor-sync-logger",
      [
        [:cursor_sync, :sync, :start],
        [:cursor_sync, :sync, :stop],
        [:cursor_sync, :sync, :exception],
        [:cursor_sync, :pipe, :command],
        [:cursor_sync, :watcher, :event]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:cursor_sync, :sync, :start], _measurements, metadata, _config) do
    Logger.debug("Sync started: workspace=#{inspect(metadata[:workspace])}")
  end

  def handle_event([:cursor_sync, :sync, :stop], measurements, metadata, _config) do
    Logger.info(
      "Sync completed: messages=#{measurements[:messages]}, " <>
      "conversations=#{measurements[:conversations]}, " <>
      "duration=#{measurements[:duration]}ms"
    )
  end

  def handle_event([:cursor_sync, :sync, :exception], _measurements, metadata, _config) do
    Logger.error("Sync exception: #{inspect(metadata[:reason])}")
  end

  def handle_event([:cursor_sync, :pipe, :command], _measurements, metadata, _config) do
    Logger.debug("Pipe command: #{metadata[:command]}")
  end

  def handle_event([:cursor_sync, :watcher, :event], _measurements, metadata, _config) do
    Logger.debug("Watcher event: #{metadata[:path]}")
  end

  # ============================================
  # Periodic Measurements
  # ============================================

  defp periodic_measurements do
    [
      {__MODULE__, :measure_sync_stats, []},
      {__MODULE__, :measure_memory, []}
    ]
  end

  def measure_sync_stats do
    stats = CursorSync.SyncEngine.stats()
    
    :telemetry.execute(
      [:cursor_sync, :stats],
      %{
        total_syncs: stats.total_syncs,
        successful_syncs: stats.successful_syncs,
        failed_syncs: stats.failed_syncs,
        messages_synced: stats.messages_synced,
        avg_duration: stats.avg_duration_ms
      },
      %{}
    )
  rescue
    _ -> :ok
  end

  def measure_memory do
    memory = :erlang.memory()
    
    :telemetry.execute(
      [:cursor_sync, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        ets: memory[:ets]
      },
      %{}
    )
  end

  # ============================================
  # Public Telemetry Helpers
  # ============================================

  @doc "Emit sync start event"
  def sync_start(workspace \\ nil) do
    :telemetry.execute(
      [:cursor_sync, :sync, :start],
      %{system_time: System.system_time()},
      %{workspace: workspace}
    )
  end

  @doc "Emit sync stop event"
  def sync_stop(messages, conversations, duration_ms) do
    :telemetry.execute(
      [:cursor_sync, :sync, :stop],
      %{
        messages: messages,
        conversations: conversations,
        duration: duration_ms
      },
      %{}
    )
  end

  @doc "Emit sync exception event"
  def sync_exception(reason) do
    :telemetry.execute(
      [:cursor_sync, :sync, :exception],
      %{},
      %{reason: reason}
    )
  end

  @doc "Emit pipe command event"
  def pipe_command(command) do
    :telemetry.execute(
      [:cursor_sync, :pipe, :command],
      %{system_time: System.system_time()},
      %{command: command}
    )
  end

  @doc "Emit watcher event"
  def watcher_event(path, events) do
    :telemetry.execute(
      [:cursor_sync, :watcher, :event],
      %{system_time: System.system_time()},
      %{path: path, events: events}
    )
  end
end
