defmodule CursorDocs.CursorIntegration do
  @moduledoc """
  Integration with Cursor IDE's existing @docs system.

  This module reads documentation URLs from Cursor's SQLite databases,
  allowing cursor-docs to use the **exact same entry points** as Cursor's
  built-in @docs feature - no new workflow required.

  ## How It Works

  1. Reads `selectedDocs` from Cursor's globalStorage SQLite database
  2. Extracts URLs that users have already added via Cursor's Settings
  3. Queues those URLs for reliable local scraping
  4. Monitors for changes to pick up newly added docs automatically

  ## Cursor Database Locations

  - Global: `~/.config/Cursor/User/globalStorage/state.vscdb`
  - Workspace: `~/.config/Cursor/User/workspaceStorage/{hash}/state.vscdb`

  ## Usage

      # Sync all docs from Cursor's database
      CursorIntegration.sync_docs()

      # Watch for new docs being added in Cursor
      CursorIntegration.start_watcher()

      # Get list of Cursor's configured doc URLs
      {:ok, docs} = CursorIntegration.list_cursor_docs()
  """

  use GenServer

  require Logger

  alias CursorDocs.Scraper
  alias Exqlite.Sqlite3

  @cursor_config_base "~/.config/Cursor"
  @global_storage_path "User/globalStorage/state.vscdb"
  @workspace_storage_pattern "User/workspaceStorage/*/state.vscdb"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sync all documentation URLs from Cursor's databases.

  Reads Cursor's configured @docs URLs and queues them for local indexing.
  This is the main entry point for seamless integration.
  """
  @spec sync_docs() :: {:ok, integer()} | {:error, term()}
  def sync_docs do
    GenServer.call(__MODULE__, :sync_docs, 30_000)
  end

  @doc """
  List all documentation URLs configured in Cursor.
  """
  @spec list_cursor_docs() :: {:ok, list(map())} | {:error, term()}
  def list_cursor_docs do
    GenServer.call(__MODULE__, :list_cursor_docs)
  end

  @doc """
  Start watching Cursor's databases for new doc additions.
  """
  @spec start_watcher() :: :ok
  def start_watcher do
    GenServer.cast(__MODULE__, :start_watcher)
  end

  @doc """
  Get the path to Cursor's global storage database.
  """
  @spec global_db_path() :: String.t()
  def global_db_path do
    Path.expand(Path.join(@cursor_config_base, @global_storage_path))
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      watcher_pid: nil,
      last_sync: nil,
      known_docs: MapSet.new()
    }

    # Initial sync on startup (delayed to not block startup)
    Process.send_after(self(), :initial_sync, 1000)

    {:ok, state}
  end

  @impl true
  def handle_info(:initial_sync, state) do
    {count, new_state} = do_sync_docs(state)
    if count > 0 do
      Logger.info("Initial sync: found #{count} docs from Cursor")
    else
      Logger.debug("Initial sync: no docs found in Cursor")
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    if String.ends_with?(path, "state.vscdb") do
      Logger.debug("Cursor database changed: #{path}")
      # Debounce - wait a bit for Cursor to finish writing
      Process.send_after(self(), {:resync, path}, 2_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:resync, _path}, state) do
    {count, new_state} = do_sync_docs(state)
    if count > 0 do
      Logger.info("Found #{count} new docs from Cursor")
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:sync_docs, _from, state) do
    {count, new_state} = do_sync_docs(state)
    {:reply, {:ok, count}, new_state}
  end

  @impl true
  def handle_call(:list_cursor_docs, _from, state) do
    docs = read_all_cursor_docs()
    {:reply, {:ok, docs}, state}
  end

  @impl true
  def handle_cast(:start_watcher, state) do
    case start_file_watcher() do
      {:ok, pid} ->
        Logger.info("Started watching Cursor databases for changes")
        {:noreply, %{state | watcher_pid: pid}}

      {:error, reason} ->
        Logger.warning("Failed to start watcher: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private Functions

  defp do_sync_docs(state) do
    docs = read_all_cursor_docs()

    # Find new docs not already known
    new_docs =
      docs
      |> Enum.reject(fn doc -> MapSet.member?(state.known_docs, doc.url) end)

    # Queue new docs for scraping
    queued_count =
      Enum.reduce(new_docs, 0, fn doc, count ->
        case Scraper.add(doc.url, name: doc.name, max_pages: 200) do
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)

    # Update known docs
    new_known =
      Enum.reduce(docs, state.known_docs, fn doc, set ->
        MapSet.put(set, doc.url)
      end)

    new_state = %{state |
      known_docs: new_known,
      last_sync: DateTime.utc_now()
    }

    {queued_count, new_state}
  end

  defp read_all_cursor_docs do
    # Read from global storage
    global_docs = read_docs_from_db(global_db_path())

    # Read from all workspace storages
    workspace_docs =
      find_workspace_dbs()
      |> Enum.flat_map(&read_docs_from_db/1)

    # Deduplicate by URL and remove nils
    (global_docs ++ workspace_docs)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp read_docs_from_db(db_path) do
    if File.exists?(db_path) do
      case Sqlite3.open(db_path, mode: :readonly) do
        {:ok, conn} ->
          docs = extract_docs_from_db(conn)
          Sqlite3.close(conn)
          docs

        {:error, reason} ->
          Logger.debug("Could not open #{db_path}: #{inspect(reason)}")
          []
      end
    else
      Logger.debug("Cursor database not found: #{db_path}")
      []
    end
  end

  defp extract_docs_from_db(conn) do
    # Try multiple table/key patterns Cursor might use
    item_docs = safe_query_docs(conn, "ItemTable")
    kv_docs = safe_query_docs(conn, "cursorDiskKV")

    item_docs ++ kv_docs
  end

  defp safe_query_docs(conn, table_name) do
    # First check if the table exists
    check_sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"

    case query_rows(conn, check_sql, [table_name]) do
      {:ok, [_row | _]} ->
        # Table exists, query it
        query_sql = """
        SELECT key, value FROM #{table_name}
        WHERE key LIKE '%docs%' OR key LIKE '%Docs%' OR key LIKE 'selectedDocs%'
        """

        case query_rows(conn, query_sql, []) do
          {:ok, rows} ->
            rows
            |> Enum.flat_map(fn [_key, value] -> parse_docs_value(value) end)
            |> Enum.reject(&is_nil/1)

          {:error, reason} ->
            Logger.debug("Query failed on #{table_name}: #{inspect(reason)}")
            []
        end

      _ ->
        # Table doesn't exist
        []
    end
  end

  # Query helper using prepare/bind/step pattern
  defp query_rows(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        if params != [] do
          Sqlite3.bind(stmt, params)
        end
        rows = collect_rows(conn, stmt, [])
        Sqlite3.release(conn, stmt)
        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_rows(conn, stmt, acc) do
    case Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
      {:error, _reason} -> Enum.reverse(acc)
    end
  end

  defp parse_docs_value(nil), do: []
  defp parse_docs_value(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, data} when is_list(data) ->
        # List of doc objects
        data
        |> Enum.map(&normalize_doc/1)
        |> Enum.reject(&is_nil/1)

      {:ok, %{"docs" => docs}} when is_list(docs) ->
        docs
        |> Enum.map(&normalize_doc/1)
        |> Enum.reject(&is_nil/1)

      {:ok, %{"url" => _url} = doc} ->
        case normalize_doc(doc) do
          nil -> []
          doc -> [doc]
        end

      {:ok, _} ->
        []

      {:error, _} ->
        # Try as plain URL
        if String.starts_with?(value, "http") do
          [%{url: String.trim(value), name: derive_name(value), status: "unknown", pages_indexed: 0}]
        else
          []
        end
    end
  end

  defp parse_docs_value(_), do: []

  defp normalize_doc(%{"url" => url} = doc) when is_binary(url) and url != "" do
    %{
      url: url,
      name: doc["name"] || doc["title"] || derive_name(url),
      status: doc["status"] || "unknown",
      pages_indexed: doc["pagesIndexed"] || doc["pages"] || 0
    }
  end

  defp normalize_doc(%{url: url} = doc) when is_binary(url) and url != "" do
    %{
      url: url,
      name: doc[:name] || derive_name(url),
      status: doc[:status] || "unknown",
      pages_indexed: doc[:pages_indexed] || 0
    }
  end

  defp normalize_doc(_), do: nil

  defp derive_name(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host || ""

    # Extract meaningful name from host
    name =
      host
      |> String.split(".")
      |> Enum.reject(&(&1 in ["www", "docs", "api", "com", "org", "io", "dev", "net"]))
      |> List.first()

    if name && name != "" do
      String.capitalize(name)
    else
      "Docs"
    end
  end

  defp derive_name(_), do: "Unknown"

  defp find_workspace_dbs do
    pattern = Path.expand(Path.join(@cursor_config_base, @workspace_storage_pattern))

    pattern
    |> Path.wildcard()
    |> Enum.filter(&File.exists?/1)
  end

  defp start_file_watcher do
    # Watch the Cursor config directory for database changes
    config_dir = Path.expand(@cursor_config_base)

    if File.dir?(config_dir) do
      case FileSystem.start_link(dirs: [config_dir]) do
        {:ok, pid} ->
          FileSystem.subscribe(pid)
          {:ok, pid}

        error ->
          error
      end
    else
      {:error, :cursor_config_not_found}
    end
  end
end
