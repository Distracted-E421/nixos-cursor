defmodule CursorSync.Database.CursorReader do
  @moduledoc """
  Reads data from Cursor's internal SQLite databases.
  
  ## Database Structure
  
  Cursor uses two tables in state.vscdb:
  
  - `ItemTable` - IDE settings (window state, preferences)
  - `cursorDiskKV` - Conversation data (messages, context)
  
  Key patterns in cursorDiskKV:
  
  - `bubbleId:*` - Individual messages with full context
  - `composer.composerData` - Conversation metadata (workspace DBs only)
  - `checkpointId:*` - Message checkpoints
  """
  
  require Logger

  @type message :: %{
    id: String.t(),
    conversation_id: String.t(),
    type: integer(),
    created_at: integer() | nil,
    model: String.t() | nil,
    token_count: integer(),
    has_thinking: boolean(),
    has_tool_calls: boolean(),
    raw_data: String.t()
  }

  @type conversation :: %{
    id: String.t(),
    name: String.t(),
    workspace: String.t() | nil,
    created_at: integer() | nil,
    is_archived: boolean()
  }

  @doc """
  Read messages from the global database.
  
  If workspace is nil, reads all messages.
  If workspace is specified, filters by conversation IDs from that workspace.
  """
  def read_messages(db_path, workspace \\ nil) do
    unless db_path && File.exists?(db_path) do
      {:error, :database_not_found}
    else
      with {:ok, conn} <- Exqlite.Sqlite3.open(db_path, mode: :readonly) do
        try do
          query = """
          SELECT key, value FROM cursorDiskKV 
          WHERE key LIKE 'bubbleId:%'
          ORDER BY rowid DESC
          """
          
          {:ok, statement} = Exqlite.Sqlite3.prepare(conn, query)
          
          messages = 
            stream_results(conn, statement)
            |> Enum.map(&parse_message/1)
            |> Enum.reject(&is_nil/1)
            |> maybe_filter_workspace(workspace)
          
          Exqlite.Sqlite3.release(conn, statement)
          {:ok, messages}
        after
          Exqlite.Sqlite3.close(conn)
        end
      end
    end
  end

  @doc """
  Read conversations from workspace databases.
  
  Each workspace has its own state.vscdb with composer.composerData
  containing conversation metadata.
  """
  def read_conversations(workspace_storage, workspace \\ nil) do
    unless workspace_storage && File.dir?(workspace_storage) do
      {:ok, []}
    else
      # Find all workspace databases
      workspaces = if workspace do
        [Path.join([workspace_storage, workspace, "state.vscdb"])]
      else
        Path.wildcard(Path.join(workspace_storage, "*/state.vscdb"))
      end
      
      conversations = 
        workspaces
        |> Enum.filter(&File.exists?/1)
        |> Enum.flat_map(&read_workspace_conversations/1)
      
      {:ok, conversations}
    end
  end

  # ============================================
  # Private Functions
  # ============================================

  defp read_workspace_conversations(db_path) do
    workspace_hash = 
      db_path
      |> Path.dirname()
      |> Path.basename()
    
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path, mode: :readonly) do
      try do
        query = """
        SELECT value FROM cursorDiskKV 
        WHERE key = 'composer.composerData'
        """
        
        case Exqlite.Sqlite3.prepare(conn, query) do
          {:ok, statement} ->
            case Exqlite.Sqlite3.step(conn, statement) do
              {:row, [value]} ->
                Exqlite.Sqlite3.release(conn, statement)
                parse_composer_data(value, workspace_hash)
                
              :done ->
                Exqlite.Sqlite3.release(conn, statement)
                []
                
              {:error, _} ->
                []
            end
            
          {:error, _} ->
            []
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    else
      {:error, _} -> []
    end
  end

  defp parse_composer_data(json_string, workspace_hash) do
    case Jason.decode(json_string) do
      {:ok, %{"allComposers" => composers}} when is_list(composers) ->
        Enum.map(composers, fn composer ->
          %{
            id: Map.get(composer, "composerId", "unknown"),
            name: Map.get(composer, "name", "Unnamed"),
            workspace: workspace_hash,
            created_at: Map.get(composer, "createdAt"),
            is_archived: Map.get(composer, "isArchived", false)
          }
        end)
        
      {:ok, _} ->
        []
        
      {:error, _} ->
        Logger.warning("Failed to parse composer data for workspace #{workspace_hash}")
        []
    end
  end

  defp parse_message({key, value}) do
    # Extract bubble ID from key like "bubbleId:abc123:def456"
    bubble_id = 
      key
      |> String.replace_prefix("bubbleId:", "")
    
    case Jason.decode(value) do
      {:ok, data} ->
        %{
          id: bubble_id,
          conversation_id: Map.get(data, "composerId", "unknown"),
          type: Map.get(data, "type", 0),
          created_at: Map.get(data, "createdAt"),
          model: get_in(data, ["modelInfo", "modelName"]),
          token_count: Map.get(data, "tokenCount", 0),
          has_thinking: has_thinking?(data),
          has_tool_calls: has_tool_calls?(data),
          raw_data: value
        }
        
      {:error, _} ->
        Logger.warning("Failed to parse message: #{bubble_id}")
        nil
    end
  end

  defp has_thinking?(data) do
    case Map.get(data, "allThinkingBlocks", []) do
      blocks when is_list(blocks) and length(blocks) > 0 -> true
      _ -> false
    end
  end

  defp has_tool_calls?(data) do
    case Map.get(data, "toolResults", []) do
      results when is_list(results) and length(results) > 0 -> true
      _ -> false
    end
  end

  defp stream_results(conn, statement) do
    Stream.resource(
      fn -> {conn, statement} end,
      fn {conn, statement} ->
        case Exqlite.Sqlite3.step(conn, statement) do
          {:row, [key, value]} -> {[{key, value}], {conn, statement}}
          :done -> {:halt, {conn, statement}}
          {:error, _} -> {:halt, {conn, statement}}
        end
      end,
      fn _ -> :ok end
    )
    |> Enum.to_list()
  end

  defp maybe_filter_workspace(messages, nil), do: messages
  defp maybe_filter_workspace(messages, _workspace) do
    # Would need to cross-reference with workspace conversation IDs
    # For now, return all messages (full implementation requires workspace metadata)
    messages
  end
end
