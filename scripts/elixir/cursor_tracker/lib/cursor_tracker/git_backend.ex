defmodule CursorTracker.GitBackend do
  @moduledoc """
  Git backend for CursorTracker.

  Handles all git operations:
  - Repository initialization
  - Commits (snapshots)
  - Diffs
  - History
  - Blame
  """
  use GenServer
  require Logger

  alias CursorTracker.Config

  # ─────────────────────────────────────────────────────────────────────────────
  # Client API
  # ─────────────────────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Initialize a git repository for tracking.
  """
  def init(version) do
    GenServer.call(__MODULE__, {:init, version})
  end

  @doc """
  Get git status for a version.
  """
  def status(version) do
    GenServer.call(__MODULE__, {:status, version})
  end

  @doc """
  Show diff from a reference.
  """
  def diff(version, ref) do
    GenServer.call(__MODULE__, {:diff, version, ref})
  end

  @doc """
  Get commit history.
  """
  def history(version, limit) do
    GenServer.call(__MODULE__, {:history, version, limit})
  end

  @doc """
  Show blame for a file.
  """
  def blame(version, file) do
    GenServer.call(__MODULE__, {:blame, version, file})
  end

  @doc """
  Commit changes with a message.
  """
  def commit(version, message) do
    GenServer.call(__MODULE__, {:commit, version, message})
  end

  @doc """
  List all tracked instances.
  """
  def list_instances do
    GenServer.call(__MODULE__, :list_instances)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Server Callbacks
  # ─────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:init, version}, _from, state) do
    tracking_dir = Config.tracking_dir(version)
    cursor_dir = Config.cursor_data_dir(version)

    result =
      with :ok <- ensure_cursor_dir(cursor_dir),
           :ok <- ensure_tracking_dir(tracking_dir),
           :ok <- init_git_repo(tracking_dir),
           :ok <- create_gitignore(tracking_dir),
           :ok <- create_metadata(tracking_dir, version, cursor_dir),
           :ok <- sync_files(tracking_dir, cursor_dir, version),
           {:ok, commit} <- initial_commit(tracking_dir, version) do
        Logger.info("Initialized tracking for Cursor #{version}")
        {:ok, %{tracking_dir: tracking_dir, commit: commit}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:status, version}, _from, state) do
    tracking_dir = Config.tracking_dir(version)

    result =
      case git_cmd(tracking_dir, ["status", "--porcelain"]) do
        {:ok, ""} -> {:ok, :clean}
        {:ok, output} -> {:ok, {:changes, parse_status(output)}}
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:diff, version, ref}, _from, state) do
    tracking_dir = Config.tracking_dir(version)
    result = git_cmd(tracking_dir, ["diff", ref])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:history, version, limit}, _from, state) do
    tracking_dir = Config.tracking_dir(version)

    result =
      case git_cmd(tracking_dir, ["log", "--oneline", "-n", to_string(limit)]) do
        {:ok, output} -> {:ok, parse_history(output)}
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:blame, version, file}, _from, state) do
    tracking_dir = Config.tracking_dir(version)
    result = git_cmd(tracking_dir, ["blame", file])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:commit, version, message}, _from, state) do
    tracking_dir = Config.tracking_dir(version)
    cursor_dir = Config.cursor_data_dir(version)

    result =
      with :ok <- sync_files(tracking_dir, cursor_dir, version),
           {:ok, _} <- git_cmd(tracking_dir, ["add", "-A"]),
           {:ok, _} <- git_cmd(tracking_dir, ["commit", "-m", message]) do
        {:ok, :committed}
      else
        {:error, "nothing to commit" <> _} -> {:ok, :no_changes}
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_instances, _from, state) do
    tracking_root = Config.get(:tracking_root)

    instances =
      case File.ls(tracking_root) do
        {:ok, dirs} ->
          dirs
          |> Enum.filter(fn dir ->
            git_dir = Path.join([tracking_root, dir, ".git"])
            File.dir?(git_dir)
          end)
          |> Enum.map(fn dir ->
            tracking_dir = Path.join(tracking_root, dir)

            %{
              name: dir,
              path: tracking_dir,
              snapshots: count_commits(tracking_dir),
              last_update: last_commit_time(tracking_dir)
            }
          end)

        {:error, _} ->
          []
      end

    {:reply, {:ok, instances}, state}
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────────────────

  defp ensure_cursor_dir(path) do
    if File.dir?(path), do: :ok, else: {:error, "Cursor data directory not found: #{path}"}
  end

  defp ensure_tracking_dir(path) do
    File.mkdir_p(path)
  end

  defp init_git_repo(path) do
    git_dir = Path.join(path, ".git")

    if File.dir?(git_dir) do
      :ok
    else
      case git_cmd(path, ["init", "--quiet"]) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  defp create_gitignore(path) do
    gitignore = """
    # Large binary files
    *.vscdb
    *.db
    *.db-journal
    *.db-shm
    *.db-wal

    # Cache directories
    Cache/
    CachedData/
    CachedProfilesData/
    Code Cache/
    GPUCache/

    # Temporary/runtime files
    blob_storage/
    Crashpad/
    logs/
    *.log
    *.tmp
    Cookies
    Cookies-journal

    # Workspace-specific
    workspaceStorage/

    # OS files
    .DS_Store
    Thumbs.db
    """

    File.write(Path.join(path, ".gitignore"), gitignore)
  end

  defp create_metadata(path, version, cursor_dir) do
    metadata = %{
      version: version,
      cursor_dir: cursor_dir,
      cursor_home: Config.cursor_home(),
      created: DateTime.utc_now() |> DateTime.to_iso8601(),
      updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write(
      Path.join(path, ".cursor-tracking.json"),
      Jason.encode!(metadata, pretty: true)
    )
  end

  defp sync_files(tracking_dir, cursor_dir, _version) do
    # Sync User settings
    user_dir = Path.join(cursor_dir, "User")

    if File.dir?(user_dir) do
      tracking_user = Path.join(tracking_dir, "User")
      File.mkdir_p(tracking_user)

      for file <- ["settings.json", "keybindings.json"] do
        src = Path.join(user_dir, file)
        dst = Path.join(tracking_user, file)
        if File.exists?(src), do: File.cp(src, dst)
      end

      # Sync snippets
      snippets_src = Path.join(user_dir, "snippets")
      snippets_dst = Path.join(tracking_user, "snippets")

      if File.dir?(snippets_src) do
        File.cp_r(snippets_src, snippets_dst)
      end
    end

    # Sync .cursor files
    cursor_home = Config.cursor_home()
    tracking_cursor = Path.join(tracking_dir, "cursor-home")
    File.mkdir_p(tracking_cursor)

    for item <- Config.tracked_cursor_files() do
      src = Path.join(cursor_home, item)

      if File.exists?(src) do
        dst = Path.join(tracking_cursor, item)

        if File.dir?(src) do
          File.cp_r(src, dst)
        else
          File.cp(src, dst)
        end
      end
    end

    :ok
  end

  defp initial_commit(tracking_dir, version) do
    with {:ok, _} <- git_cmd(tracking_dir, ["add", "-A"]),
         {:ok, output} <- git_cmd(tracking_dir, ["commit", "-m", "Initial tracking snapshot for Cursor #{version}", "--quiet"]) do
      {:ok, output}
    else
      {:error, msg} when is_binary(msg) ->
        if String.contains?(msg, "nothing to commit") do
          {:ok, "no changes"}
        else
          {:error, msg}
        end
      error -> error
    end
  end

  defp git_cmd(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp parse_status(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [status, file] = String.split(line, " ", parts: 2)
      %{status: status, file: String.trim(file)}
    end)
  end

  defp parse_history(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [hash | rest] = String.split(line, " ", parts: 2)
      %{hash: hash, message: Enum.join(rest, " ")}
    end)
  end

  defp count_commits(tracking_dir) do
    case git_cmd(tracking_dir, ["rev-list", "--count", "HEAD"]) do
      {:ok, count} -> String.to_integer(count)
      _ -> 0
    end
  end

  defp last_commit_time(tracking_dir) do
    case git_cmd(tracking_dir, ["log", "-1", "--format=%cr"]) do
      {:ok, time} -> time
      _ -> "never"
    end
  end
end
