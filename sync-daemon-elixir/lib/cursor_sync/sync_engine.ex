defmodule CursorSync.SyncEngine do
  @moduledoc """
  Core Sync Engine.
  
  Handles reading from Cursor's databases and writing to the external
  sync database. Maintains sync state and statistics.
  
  ## Hot Reload Example
  
  Change sync logic and reload without stopping:
  
      # Edit this file
      iex> r CursorSync.SyncEngine
      # State preserved, new logic active!
  
  ## Sync Flow
  
  1. Read messages from Cursor's cursorDiskKV table
  2. Parse JSON blobs for conversation data
  3. Deduplicate against last sync state
  4. Write to external database
  5. Update sync state and stats
  """
  
  use GenServer
  require Logger

  alias CursorSync.Database.{CursorReader, ExternalWriter}

  @type stats :: %{
    total_syncs: non_neg_integer(),
    successful_syncs: non_neg_integer(),
    failed_syncs: non_neg_integer(),
    messages_synced: non_neg_integer(),
    conversations_synced: non_neg_integer(),
    last_sync: DateTime.t() | nil,
    last_error: String.t() | nil,
    avg_duration_ms: float()
  }

  @type sync_state :: %{
    last_message_ids: %{String.t() => String.t()},
    workspaces_synced: [String.t()]
  }

  @type state :: %{
    stats: stats(),
    sync_state: sync_state(),
    syncing: boolean()
  }

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger a sync operation"
  def sync(workspace \\ nil) do
    GenServer.call(__MODULE__, {:sync, workspace}, :infinity)
  end

  @doc "Get current status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Get sync statistics"
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Reset statistics"
  def reset_stats do
    GenServer.cast(__MODULE__, :reset_stats)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    Logger.info("Initializing SyncEngine")
    
    state = %{
      stats: initial_stats(),
      sync_state: initial_sync_state(),
      syncing: false
    }
    
    {:ok, state}
  end

  @impl true
  def handle_info(:sync_all, state) do
    # Non-blocking sync triggered from Application
    spawn(fn -> sync(nil) end)
    {:noreply, state}
  end

  @impl true
  def handle_call({:sync, _workspace}, _from, %{syncing: true} = state) do
    Logger.warning("Sync already in progress, skipping")
    {:reply, {:error, :sync_in_progress}, state}
  end

  @impl true
  def handle_call({:sync, workspace}, _from, state) do
    state = %{state | syncing: true}
    
    start_time = System.monotonic_time(:millisecond)
    
    result = case do_sync(workspace, state) do
      {:ok, sync_result, new_sync_state} ->
        duration = System.monotonic_time(:millisecond) - start_time
        stats = update_stats_success(state.stats, sync_result, duration)
        
        Logger.info("Sync completed: #{sync_result.messages} messages, " <>
                   "#{sync_result.conversations} conversations in #{duration}ms")
        
        new_state = %{state | 
          stats: stats,
          sync_state: new_sync_state,
          syncing: false
        }
        
        {:ok, sync_result, new_state}
        
      {:error, reason} = error ->
        duration = System.monotonic_time(:millisecond) - start_time
        stats = update_stats_failure(state.stats, reason, duration)
        
        Logger.error("Sync failed: #{inspect(reason)}")
        
        new_state = %{state | stats: stats, syncing: false}
        {error, new_state}
    end
    
    case result do
      {:ok, sync_result, new_state} ->
        {:reply, {:ok, sync_result}, new_state}
      {{:error, _} = error, new_state} ->
        {:reply, error, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      syncing: state.syncing,
      last_sync: state.stats.last_sync,
      workspaces_synced: length(state.sync_state.workspaces_synced),
      total_syncs: state.stats.total_syncs
    }
    {:reply, status, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast(:reset_stats, state) do
    {:noreply, %{state | stats: initial_stats()}}
  end

  # ============================================
  # Private Functions
  # ============================================

  defp initial_stats do
    %{
      total_syncs: 0,
      successful_syncs: 0,
      failed_syncs: 0,
      messages_synced: 0,
      conversations_synced: 0,
      last_sync: nil,
      last_error: nil,
      avg_duration_ms: 0.0
    }
  end

  defp initial_sync_state do
    %{
      last_message_ids: %{},
      workspaces_synced: []
    }
  end

  defp do_sync(workspace, state) do
    # Ensure external database is initialized
    sync_db = Application.get_env(:cursor_sync, :sync_db)
    
    with :ok <- ExternalWriter.ensure_initialized(sync_db),
         {:ok, messages} <- read_messages(workspace),
         {:ok, conversations} <- read_conversations(workspace),
         {:ok, written} <- write_data(sync_db, messages, conversations) do
      
      sync_result = %{
        messages: length(messages),
        conversations: length(conversations),
        written: written
      }
      
      new_sync_state = update_sync_state(state.sync_state, workspace, messages)
      
      {:ok, sync_result, new_sync_state}
    end
  end

  defp read_messages(workspace) do
    global_db = Application.get_env(:cursor_sync, :global_db)
    
    case CursorReader.read_messages(global_db, workspace) do
      {:ok, messages} -> {:ok, messages}
      {:error, reason} -> {:error, {:read_messages, reason}}
    end
  end

  defp read_conversations(workspace) do
    workspace_storage = Application.get_env(:cursor_sync, :workspace_storage)
    # read_conversations always returns {:ok, _}, errors are handled internally
    CursorReader.read_conversations(workspace_storage, workspace)
  end

  defp write_data(sync_db, messages, conversations) do
    with {:ok, msg_count} <- ExternalWriter.write_messages(sync_db, messages),
         {:ok, conv_count} <- ExternalWriter.write_conversations(sync_db, conversations) do
      {:ok, %{messages: msg_count, conversations: conv_count}}
    end
  end

  defp update_sync_state(sync_state, workspace, messages) do
    # Track last message ID per conversation
    last_ids = Enum.reduce(messages, sync_state.last_message_ids, fn msg, acc ->
      Map.put(acc, msg.conversation_id, msg.id)
    end)
    
    # Track synced workspaces
    workspaces = if workspace do
      Enum.uniq([workspace | sync_state.workspaces_synced])
    else
      sync_state.workspaces_synced
    end
    
    %{sync_state | last_message_ids: last_ids, workspaces_synced: workspaces}
  end

  defp update_stats_success(stats, result, duration_ms) do
    n = stats.total_syncs + 1
    new_avg = (stats.avg_duration_ms * stats.total_syncs + duration_ms) / n
    
    %{stats |
      total_syncs: n,
      successful_syncs: stats.successful_syncs + 1,
      messages_synced: stats.messages_synced + result.messages,
      conversations_synced: stats.conversations_synced + result.conversations,
      last_sync: DateTime.utc_now(),
      last_error: nil,
      avg_duration_ms: new_avg
    }
  end

  defp update_stats_failure(stats, reason, _duration_ms) do
    %{stats |
      total_syncs: stats.total_syncs + 1,
      failed_syncs: stats.failed_syncs + 1,
      last_error: inspect(reason)
    }
  end
end
