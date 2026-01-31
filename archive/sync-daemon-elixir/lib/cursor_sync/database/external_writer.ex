defmodule CursorSync.Database.ExternalWriter do
  @moduledoc """
  Writes synced data to the external SQLite database.
  
  Creates and maintains the schema for:
  - conversations - Conversation metadata
  - messages - Individual messages with context
  - tool_calls - Tool/MCP call records
  - sync_state - Sync tracking data
  """
  
  require Logger

  @schema """
  -- Conversations table
  CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    workspace TEXT,
    created_at INTEGER,
    updated_at INTEGER,
    is_archived INTEGER DEFAULT 0,
    message_count INTEGER DEFAULT 0,
    model TEXT,
    total_tokens INTEGER DEFAULT 0
  );

  -- Messages table
  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    message_type INTEGER,
    created_at INTEGER,
    model TEXT,
    token_count INTEGER DEFAULT 0,
    has_thinking INTEGER DEFAULT 0,
    has_tool_calls INTEGER DEFAULT 0,
    raw_data TEXT,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
  );

  -- Tool calls table
  CREATE TABLE IF NOT EXISTS tool_calls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id TEXT NOT NULL,
    name TEXT NOT NULL,
    server TEXT,
    success INTEGER DEFAULT 1,
    duration_ms INTEGER,
    error TEXT,
    FOREIGN KEY (message_id) REFERENCES messages(id)
  );

  -- Sync state table
  CREATE TABLE IF NOT EXISTS sync_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER
  );

  -- Indexes for performance
  CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
  CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
  CREATE INDEX IF NOT EXISTS idx_tool_calls_message ON tool_calls(message_id);
  CREATE INDEX IF NOT EXISTS idx_conversations_workspace ON conversations(workspace);
  """

  @doc "Ensure the database is initialized with schema"
  def ensure_initialized(db_path) do
    # Create parent directory if needed
    db_path
    |> Path.dirname()
    |> File.mkdir_p()
    
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path) do
      try do
        # Execute schema (each statement separately)
        @schema
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.each(fn sql ->
          case Exqlite.Sqlite3.execute(conn, sql) do
            :ok -> :ok
            {:error, reason} ->
              Logger.warning("Schema statement failed: #{inspect(reason)}")
          end
        end)
        
        :ok
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc "Write messages to the database"
  def write_messages(db_path, messages) when is_list(messages) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path) do
      try do
        count = 
          messages
          |> Enum.map(&write_message(conn, &1))
          |> Enum.count(&(&1 == :ok))
        
        {:ok, count}
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc "Write conversations to the database"
  def write_conversations(db_path, conversations) when is_list(conversations) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path) do
      try do
        count = 
          conversations
          |> Enum.map(&write_conversation(conn, &1))
          |> Enum.count(&(&1 == :ok))
        
        {:ok, count}
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc "Save sync state"
  def save_state(db_path, key, value) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path) do
      try do
        json = Jason.encode!(value)
        now = System.system_time(:second)
        
        sql = """
        INSERT OR REPLACE INTO sync_state (key, value, updated_at)
        VALUES (?1, ?2, ?3)
        """
        
        case Exqlite.Sqlite3.prepare(conn, sql) do
          {:ok, stmt} ->
            :ok = Exqlite.Sqlite3.bind(stmt, [key, json, now])
            result = Exqlite.Sqlite3.step(conn, stmt)
            Exqlite.Sqlite3.release(conn, stmt)
            
            case result do
              :done -> :ok
              {:error, reason} -> {:error, reason}
            end
            
          {:error, reason} ->
            {:error, reason}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc "Load sync state"
  def load_state(db_path, key) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path, mode: :readonly) do
      try do
        sql = "SELECT value FROM sync_state WHERE key = ?1"
        
        case Exqlite.Sqlite3.prepare(conn, sql) do
          {:ok, stmt} ->
            :ok = Exqlite.Sqlite3.bind(stmt, [key])
            
            result = case Exqlite.Sqlite3.step(conn, stmt) do
              {:row, [json]} -> 
                case Jason.decode(json) do
                  {:ok, value} -> {:ok, value}
                  {:error, _} -> {:error, :decode_failed}
                end
              :done -> {:error, :not_found}
              {:error, reason} -> {:error, reason}
            end
            
            Exqlite.Sqlite3.release(conn, stmt)
            result
            
          {:error, reason} ->
            {:error, reason}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc "Get database statistics"
  def stats(db_path) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db_path, mode: :readonly) do
      try do
        %{
          conversations: count_table(conn, "conversations"),
          messages: count_table(conn, "messages"),
          tool_calls: count_table(conn, "tool_calls"),
          size_bytes: File.stat!(db_path).size
        }
      after
        Exqlite.Sqlite3.close(conn)
      end
    else
      {:error, _} -> %{conversations: 0, messages: 0, tool_calls: 0, size_bytes: 0}
    end
  end

  # ============================================
  # Private Functions
  # ============================================

  defp write_message(conn, message) do
    sql = """
    INSERT OR REPLACE INTO messages 
    (id, conversation_id, message_type, created_at, model, token_count, 
     has_thinking, has_tool_calls, raw_data)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
    """
    
    # Handle token_count which might be a map or integer
    token_count = normalize_token_count(message.token_count)
    
    params = [
      message.id,
      message.conversation_id,
      normalize_integer(message.type),
      normalize_integer(message.created_at),
      to_string_or_nil(message.model),
      token_count,
      if(message.has_thinking, do: 1, else: 0),
      if(message.has_tool_calls, do: 1, else: 0),
      message.raw_data
    ]
    
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        :ok = Exqlite.Sqlite3.bind(stmt, params)
        result = Exqlite.Sqlite3.step(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        
        case result do
          :done -> :ok
          {:error, reason} -> 
            Logger.warning("Failed to write message #{message.id}: #{inspect(reason)}")
            :error
        end
        
      {:error, reason} ->
        Logger.warning("Failed to prepare message insert: #{inspect(reason)}")
        :error
    end
  end

  defp write_conversation(conn, conv) do
    sql = """
    INSERT OR REPLACE INTO conversations 
    (id, name, workspace, created_at, is_archived)
    VALUES (?1, ?2, ?3, ?4, ?5)
    """
    
    params = [
      conv.id,
      conv.name,
      conv.workspace,
      conv.created_at,
      if(conv.is_archived, do: 1, else: 0)
    ]
    
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        :ok = Exqlite.Sqlite3.bind(stmt, params)
        result = Exqlite.Sqlite3.step(conn, stmt)
        Exqlite.Sqlite3.release(conn, stmt)
        
        case result do
          :done -> :ok
          {:error, reason} -> 
            Logger.warning("Failed to write conversation #{conv.id}: #{inspect(reason)}")
            :error
        end
        
      {:error, reason} ->
        Logger.warning("Failed to prepare conversation insert: #{inspect(reason)}")
        :error
    end
  end

  defp count_table(conn, table) do
    sql = "SELECT COUNT(*) FROM #{table}"
    
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        case Exqlite.Sqlite3.step(conn, stmt) do
          {:row, [count]} ->
            Exqlite.Sqlite3.release(conn, stmt)
            count
          _ ->
            Exqlite.Sqlite3.release(conn, stmt)
            0
        end
      _ -> 0
    end
  end

  # Normalize token count - can be integer, map, or nil
  defp normalize_token_count(nil), do: 0
  defp normalize_token_count(count) when is_integer(count), do: count
  defp normalize_token_count(%{"inputTokens" => input, "outputTokens" => output}) do
    (input || 0) + (output || 0)
  end
  defp normalize_token_count(%{} = map) do
    # Try to sum any numeric values in the map
    map
    |> Map.values()
    |> Enum.filter(&is_integer/1)
    |> Enum.sum()
  end
  defp normalize_token_count(_), do: 0

  # Normalize integers (some fields might be strings or nil)
  defp normalize_integer(nil), do: nil
  defp normalize_integer(val) when is_integer(val), do: val
  defp normalize_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp normalize_integer(_), do: nil

  # Convert to string or nil
  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(val) when is_binary(val), do: val
  defp to_string_or_nil(val), do: inspect(val)
end
