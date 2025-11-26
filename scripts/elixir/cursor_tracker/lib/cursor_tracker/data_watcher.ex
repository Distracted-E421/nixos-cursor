defmodule CursorTracker.DataWatcher do
  @moduledoc """
  File system watcher for Cursor data directories.

  Monitors configuration files and automatically creates snapshots
  when significant changes are detected.

  ## Options
    - `:interval` - Minimum time between auto-snapshots (default: 5 minutes)
    - `:debounce` - Debounce time for file changes (default: 5 seconds)
  """
  use GenServer
  require Logger

  alias CursorTracker.{Config, GitBackend}

  @default_interval :timer.minutes(5)
  @default_debounce :timer.seconds(5)

  # ─────────────────────────────────────────────────────────────────────────────
  # Client API
  # ─────────────────────────────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start watching for file changes.
  """
  def start_watching(opts \\ []) do
    GenServer.call(__MODULE__, {:start_watching, opts})
  end

  @doc """
  Stop watching for file changes.
  """
  def stop_watching do
    GenServer.call(__MODULE__, :stop_watching)
  end

  @doc """
  Check if currently watching.
  """
  def watching? do
    GenServer.call(__MODULE__, :watching?)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Server Callbacks
  # ─────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    state = %{
      watching: false,
      watcher_pid: nil,
      last_snapshot: nil,
      pending_changes: [],
      interval: @default_interval,
      debounce: @default_debounce,
      debounce_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_watching, opts}, _from, state) do
    if state.watching do
      {:reply, {:error, :already_watching}, state}
    else
      interval = Keyword.get(opts, :interval, @default_interval)
      debounce = Keyword.get(opts, :debounce, @default_debounce)

      # Get paths to watch
      cursor_config = Config.cursor_data_dir("default")
      cursor_home = Config.cursor_home()
      paths = [cursor_config, cursor_home] |> Enum.filter(&File.dir?/1)

      case FileSystem.start_link(dirs: paths) do
        {:ok, watcher_pid} ->
          FileSystem.subscribe(watcher_pid)
          Logger.info("Started watching: #{inspect(paths)}")

          new_state = %{
            state
            | watching: true,
              watcher_pid: watcher_pid,
              interval: interval,
              debounce: debounce
          }

          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:stop_watching, _from, state) do
    if state.watching and state.watcher_pid do
      FileSystem.stop(state.watcher_pid)
      Logger.info("Stopped watching")
    end

    new_state = %{state | watching: false, watcher_pid: nil}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:watching?, _from, state) do
    {:reply, state.watching, state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    # Filter out events we don't care about
    if should_track_event?(path, events) do
      Logger.debug("File change detected: #{path} #{inspect(events)}")

      # Cancel existing debounce timer
      if state.debounce_timer do
        Process.cancel_timer(state.debounce_timer)
      end

      # Start new debounce timer
      timer = Process.send_after(self(), :debounce_snapshot, state.debounce)

      new_state = %{
        state
        | pending_changes: [path | state.pending_changes],
          debounce_timer: timer
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.warn("File watcher stopped unexpectedly")
    {:noreply, %{state | watching: false, watcher_pid: nil}}
  end

  @impl true
  def handle_info(:debounce_snapshot, state) do
    # Check if enough time has passed since last snapshot
    should_snapshot =
      case state.last_snapshot do
        nil ->
          true

        last ->
          diff = DateTime.diff(DateTime.utc_now(), last, :millisecond)
          diff >= state.interval
      end

    if should_snapshot and length(state.pending_changes) > 0 do
      # Take snapshot
      file_count = length(Enum.uniq(state.pending_changes))
      message = "Auto-snapshot: #{file_count} file(s) changed"

      case GitBackend.commit("default", message) do
        {:ok, :committed} ->
          Logger.info("Auto-snapshot created: #{message}")

        {:ok, :no_changes} ->
          Logger.debug("No changes to snapshot")

        {:error, reason} ->
          Logger.warn("Failed to create auto-snapshot: #{inspect(reason)}")
      end

      new_state = %{
        state
        | last_snapshot: DateTime.utc_now(),
          pending_changes: [],
          debounce_timer: nil
      }

      {:noreply, new_state}
    else
      {:noreply, %{state | debounce_timer: nil}}
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────────────────

  defp should_track_event?(path, events) do
    # Only track modified/created events
    tracked_events = [:modified, :created, :renamed]
    has_tracked_event = Enum.any?(events, &(&1 in tracked_events))

    # Check if file is in our tracked list
    is_tracked_file =
      Enum.any?(Config.tracked_files() ++ Config.tracked_cursor_files(), fn pattern ->
        String.contains?(path, pattern)
      end)

    # Check if file should be excluded
    is_excluded =
      Enum.any?(Config.excluded_patterns(), fn pattern ->
        pattern = String.replace(pattern, "*", ".*")
        String.match?(path, ~r/#{pattern}/)
      end)

    has_tracked_event and is_tracked_file and not is_excluded
  end
end
