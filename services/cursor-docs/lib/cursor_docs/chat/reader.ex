defmodule CursorDocs.Chat.Reader do
  @moduledoc """
  Reads chat conversations from Cursor's SQLite databases.

  Cursor stores chats in `state.vscdb` files:
  - Global: `~/.config/Cursor/User/globalStorage/state.vscdb`
  - Workspace: `~/.config/Cursor/User/workspaceStorage/{hash}/state.vscdb`

  ## Chat Structure

  Cursor stores chats in `cursorDiskKV` table with keys like:
  - `bubbleId:{conversation_id}:{message_index}` - Individual messages

  Each message value is JSON containing:
  - `type` - 0 = user, 1 = assistant
  - `text` - Rendered/formatted text
  - `rawText` - Original input (for user messages)
  - `bubbleId` - Conversation ID
  """

  require Logger

  @cursor_config_path "~/.config/Cursor"
  @global_storage_path "User/globalStorage/state.vscdb"
  @workspace_storage_pattern "User/workspaceStorage/*/state.vscdb"

  @type message :: %{
    id: String.t(),
    role: :user | :assistant,
    content: String.t(),
    raw_content: String.t() | nil,
    sequence: non_neg_integer(),
    metadata: map()
  }

  @type conversation :: %{
    id: String.t(),
    title: String.t(),
    messages: [message()],
    message_count: non_neg_integer(),
    source: String.t(),
    workspace: String.t() | nil
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  List all available Cursor databases.
  """
  @spec list_databases() :: {:ok, [map()]} | {:error, term()}
  def list_databases do
    cursor_path = Path.expand(@cursor_config_path)

    databases =
      [
        # Global database
        %{
          type: :global,
          path: Path.join(cursor_path, @global_storage_path),
          name: "Global"
        }
      ] ++
        # Workspace databases
        list_workspace_databases(cursor_path) ++
        # Version-specific installations
        list_version_databases()

    existing =
      databases
      |> Enum.filter(fn db -> File.exists?(db.path) end)
      |> Enum.map(fn db ->
        size = File.stat!(db.path).size
        Map.put(db, :size_bytes, size)
      end)

    {:ok, existing}
  end

  @doc """
  List all conversations from all available databases.
  """
  @spec list_conversations(keyword()) :: {:ok, [conversation()]} | {:error, term()}
  def list_conversations(opts \\ []) do
    with {:ok, databases} <- list_databases() do
      conversations =
        databases
        |> Enum.flat_map(fn db ->
          case read_conversations_from_db(db.path, db) do
            {:ok, convs} -> convs
            {:error, _} -> []
          end
        end)
        |> maybe_sort(opts[:sort])
        |> maybe_limit(opts[:limit])

      {:ok, conversations}
    end
  end

  @doc """
  Get a single conversation by ID.
  """
  @spec get_conversation(String.t()) :: {:ok, conversation()} | {:error, :not_found | term()}
  def get_conversation(conversation_id) do
    with {:ok, conversations} <- list_conversations() do
      case Enum.find(conversations, fn c -> c.id == conversation_id end) do
        nil -> {:error, :not_found}
        conv -> {:ok, conv}
      end
    end
  end

  @doc """
  Search conversations by content.
  """
  @spec search_conversations(String.t(), keyword()) :: {:ok, [conversation()]} | {:error, term()}
  def search_conversations(query, opts \\ []) do
    with {:ok, conversations} <- list_conversations() do
      query_lower = String.downcase(query)

      matching =
        conversations
        |> Enum.filter(fn conv ->
          # Search in title
          title_match = String.contains?(String.downcase(conv.title), query_lower)

          # Search in messages
          content_match =
            Enum.any?(conv.messages, fn msg ->
              String.contains?(String.downcase(msg.content), query_lower)
            end)

          title_match or content_match
        end)
        |> maybe_limit(opts[:limit])

      {:ok, matching}
    end
  end

  @doc """
  Get statistics about available chats.
  """
  @spec stats() :: {:ok, map()} | {:error, term()}
  def stats do
    with {:ok, databases} <- list_databases(),
         {:ok, conversations} <- list_conversations() do
      total_messages =
        conversations
        |> Enum.map(& &1.message_count)
        |> Enum.sum()

      by_source =
        conversations
        |> Enum.group_by(& &1.source)
        |> Enum.map(fn {source, convs} -> {source, length(convs)} end)
        |> Map.new()

      {:ok,
       %{
         databases: length(databases),
         conversations: length(conversations),
         messages: total_messages,
         by_source: by_source
       }}
    end
  end

  # ============================================================================
  # Private - Database Discovery
  # ============================================================================

  defp list_workspace_databases(cursor_path) do
    pattern = Path.join(cursor_path, @workspace_storage_pattern)

    pattern
    |> Path.wildcard()
    |> Enum.map(fn path ->
      workspace_hash = path |> Path.dirname() |> Path.basename()

      %{
        type: :workspace,
        path: path,
        name: "Workspace #{String.slice(workspace_hash, 0, 8)}",
        workspace_hash: workspace_hash
      }
    end)
  end

  defp list_version_databases do
    home = Path.expand("~")

    home
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, ".cursor-"))
    |> Enum.flat_map(fn dir ->
      version = String.replace_prefix(dir, ".cursor-", "")
      base_path = Path.join([home, dir])

      [
        %{
          type: :version,
          path: Path.join([base_path, "User/globalStorage/state.vscdb"]),
          name: "v#{version}",
          version: version
        }
      ] ++ list_workspace_databases(base_path)
    end)
  end

  # ============================================================================
  # Private - Database Reading
  # ============================================================================

  defp read_conversations_from_db(db_path, db_info) do
    if File.exists?(db_path) do
      # Use read-only mode to avoid locks
      db_uri = "file:#{db_path}?mode=ro"

      case Exqlite.Sqlite3.open(db_uri) do
        {:ok, conn} ->
          result = read_conversations(conn, db_info)
          Exqlite.Sqlite3.close(conn)
          result

        {:error, reason} ->
          Logger.warning("Failed to open #{db_path}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  defp read_conversations(conn, db_info) do
    # Find all unique conversation IDs
    sql = """
    SELECT DISTINCT substr(key, 10, 36) as conv_id
    FROM cursorDiskKV
    WHERE key LIKE 'bubbleId:%'
    """

    case execute_query(conn, sql) do
      {:ok, rows} ->
        conversations =
          rows
          |> Enum.map(fn [conv_id] -> conv_id end)
          |> Enum.map(fn conv_id ->
            read_single_conversation(conn, conv_id, db_info)
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, conversations}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_single_conversation(conn, conv_id, db_info) do
    sql = """
    SELECT key, value FROM cursorDiskKV
    WHERE key LIKE ?
    ORDER BY key
    """

    case execute_query(conn, sql, ["bubbleId:#{conv_id}:%"]) do
      {:ok, rows} when rows != [] ->
        messages =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {[key, value], index} ->
            parse_message(key, value, index)
          end)
          |> Enum.reject(&is_nil/1)

        title = generate_title(messages)

        %{
          id: conv_id,
          title: title,
          messages: messages,
          message_count: length(messages),
          source: db_info.name,
          workspace: Map.get(db_info, :workspace_hash)
        }

      _ ->
        nil
    end
  end

  defp parse_message(key, value, index) do
    with {:ok, data} <- Jason.decode(value) do
      msg_id = key |> String.split(":") |> List.last()
      role = if data["type"] == 1, do: :assistant, else: :user

      content = data["text"] || data["rawText"] || ""

      %{
        id: msg_id,
        role: role,
        content: content,
        raw_content: data["rawText"],
        sequence: index,
        metadata: %{
          type: data["type"],
          bubble_id: data["bubbleId"]
        }
      }
    else
      _ -> nil
    end
  end

  defp generate_title(messages) do
    # Use first user message as title
    first_user =
      messages
      |> Enum.find(fn msg -> msg.role == :user end)

    case first_user do
      %{content: content} when is_binary(content) and content != "" ->
        content
        |> String.slice(0, 80)
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> case do
          short when byte_size(short) < 60 -> short
          long -> String.slice(long, 0, 57) <> "..."
        end

      _ ->
        "Untitled Chat"
    end
  end

  defp execute_query(conn, sql, params \\ []) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql),
         :ok <- bind_params(stmt, params),
         {:ok, rows} <- fetch_all_rows(conn, stmt) do
      Exqlite.Sqlite3.release(conn, stmt)
      {:ok, rows}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp bind_params(_stmt, []), do: :ok

  defp bind_params(stmt, params) do
    Exqlite.Sqlite3.bind(stmt, params)
  end

  defp fetch_all_rows(conn, stmt, acc \\ []) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_all_rows(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Helpers

  defp maybe_sort(conversations, nil), do: conversations
  defp maybe_sort(conversations, :recent), do: Enum.reverse(conversations)

  defp maybe_sort(conversations, :messages) do
    Enum.sort_by(conversations, & &1.message_count, :desc)
  end

  defp maybe_sort(conversations, :title) do
    Enum.sort_by(conversations, & &1.title)
  end

  defp maybe_limit(conversations, nil), do: conversations
  defp maybe_limit(conversations, limit), do: Enum.take(conversations, limit)
end

