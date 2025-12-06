defmodule CursorSync.PipeServer do
  @moduledoc """
  Named Pipe IPC Server.
  
  Handles bidirectional communication with cursor-studio (Rust) via named pipes.
  
  ## Protocol
  
  Commands are JSON messages sent to the command pipe:
  
      {"cmd": "sync", "workspace": null}           # Sync all
      {"cmd": "sync", "workspace": "hash123"}      # Sync specific workspace
      {"cmd": "status"}                            # Get daemon status
      {"cmd": "stats"}                             # Get sync statistics
      {"cmd": "stop"}                              # Graceful shutdown
  
  Responses are JSON messages written to the response pipe:
  
      {"ok": true, "data": {...}}
      {"ok": false, "error": "message"}
  
  ## Hot Reload
  
  This module can be hot-reloaded without losing pipe connections:
  
      iex> r CursorSync.PipeServer
  
  State persists across reloads because we store the file descriptors
  in the GenServer state.
  """
  
  use GenServer
  require Logger

  @type state :: %{
    cmd_pipe: String.t(),
    resp_pipe: String.t(),
    cmd_file: :file.io_device() | nil,
    reader_task: Task.t() | nil
  }

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Send a response to cursor-studio"
  def send_response(response) when is_map(response) do
    GenServer.cast(__MODULE__, {:send_response, response})
  end

  @doc "Get current pipe status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    cmd_pipe = Application.get_env(:cursor_sync, :command_pipe)
    resp_pipe = Application.get_env(:cursor_sync, :response_pipe)
    
    Logger.info("Initializing PipeServer: cmd=#{cmd_pipe}, resp=#{resp_pipe}")
    
    # Create pipes if they don't exist
    ensure_pipe(cmd_pipe)
    ensure_pipe(resp_pipe)
    
    # Start reading from command pipe in a separate task
    state = %{
      cmd_pipe: cmd_pipe,
      resp_pipe: resp_pipe,
      cmd_file: nil,
      reader_task: nil
    }
    
    # Schedule pipe opening (non-blocking)
    send(self(), :open_pipes)
    
    {:ok, state}
  end

  @impl true
  def handle_info(:open_pipes, state) do
    # Open command pipe for reading (this will block until writer connects)
    # We do this in a separate task to not block the GenServer
    task = Task.async(fn -> open_and_read_pipe(state.cmd_pipe) end)
    {:noreply, %{state | reader_task: task}}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed
    Task.shutdown(state.reader_task, :brutal_kill)
    
    case result do
      {:ok, data} ->
        handle_command(data, state)
        # Restart reading
        task = Task.async(fn -> open_and_read_pipe(state.cmd_pipe) end)
        {:noreply, %{state | reader_task: task}}
        
      {:error, reason} ->
        Logger.warning("Pipe read error: #{inspect(reason)}, restarting...")
        Process.send_after(self(), :open_pipes, 1000)
        {:noreply, %{state | reader_task: nil}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task crashed, restart
    Logger.warning("Pipe reader task crashed, restarting...")
    Process.send_after(self(), :open_pipes, 1000)
    {:noreply, %{state | reader_task: nil}}
  end

  @impl true
  def handle_cast({:send_response, response}, state) do
    write_to_pipe(state.resp_pipe, response)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      cmd_pipe: state.cmd_pipe,
      resp_pipe: state.resp_pipe,
      reader_active: state.reader_task != nil,
      pipes_exist: File.exists?(state.cmd_pipe) and File.exists?(state.resp_pipe)
    }
    {:reply, status, state}
  end

  # ============================================
  # Private Functions
  # ============================================

  defp ensure_pipe(path) do
    unless File.exists?(path) do
      Logger.info("Creating named pipe: #{path}")
      case System.cmd("mkfifo", [path]) do
        {_, 0} -> :ok
        {error, _} -> Logger.error("Failed to create pipe: #{error}")
      end
    end
  end

  defp open_and_read_pipe(path) do
    Logger.debug("Opening command pipe for reading: #{path}")
    
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        # Read until EOF (pipe closes)
        data = IO.binread(file, :eof)
        File.close(file)
        
        case data do
          :eof -> {:error, :eof}
          {:error, reason} -> {:error, reason}
          binary when is_binary(binary) and byte_size(binary) > 0 ->
            {:ok, binary}
          _ -> {:error, :empty}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_to_pipe(path, data) do
    json = Jason.encode!(data)
    Logger.debug("Writing to response pipe: #{json}")
    
    case File.open(path, [:write, :binary]) do
      {:ok, file} ->
        IO.binwrite(file, json <> "\n")
        File.close(file)
        :ok
        
      {:error, reason} ->
        Logger.error("Failed to write to pipe: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_command(data, state) do
    case Jason.decode(data) do
      {:ok, %{"cmd" => cmd} = command} ->
        Logger.info("Received command: #{cmd}")
        result = execute_command(cmd, command)
        write_to_pipe(state.resp_pipe, result)
        
      {:error, reason} ->
        Logger.warning("Invalid JSON command: #{inspect(reason)}")
        error = %{ok: false, error: "Invalid JSON: #{inspect(reason)}"}
        write_to_pipe(state.resp_pipe, error)
    end
  end

  defp execute_command("sync", command) do
    workspace = Map.get(command, "workspace")
    
    case CursorSync.SyncEngine.sync(workspace) do
      {:ok, stats} -> %{ok: true, data: stats}
      {:error, reason} -> %{ok: false, error: inspect(reason)}
    end
  end

  defp execute_command("status", _command) do
    status = CursorSync.SyncEngine.status()
    %{ok: true, data: status}
  end

  defp execute_command("stats", _command) do
    stats = CursorSync.SyncEngine.stats()
    %{ok: true, data: stats}
  end

  defp execute_command("stop", _command) do
    Logger.info("Received stop command, shutting down...")
    # Graceful shutdown after response
    spawn(fn ->
      Process.sleep(100)
      System.stop(0)
    end)
    %{ok: true, data: %{message: "Shutting down"}}
  end

  defp execute_command(unknown, _command) do
    Logger.warning("Unknown command: #{unknown}")
    %{ok: false, error: "Unknown command: #{unknown}"}
  end
end
