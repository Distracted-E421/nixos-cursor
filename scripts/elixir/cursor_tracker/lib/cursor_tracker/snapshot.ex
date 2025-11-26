defmodule CursorTracker.Snapshot do
  @moduledoc """
  Snapshot management for CursorTracker.

  Handles:
  - Taking snapshots (commits)
  - Rollback operations
  - Comparing between instances
  """
  require Logger

  alias CursorTracker.{Config, GitBackend}

  @doc """
  Take a snapshot of the current Cursor configuration.
  """
  def take(version, message) do
    GitBackend.commit(version, message)
  end

  @doc """
  Rollback to a previous snapshot.
  """
  def rollback(version, ref) do
    tracking_dir = Config.tracking_dir(version)
    cursor_dir = Config.cursor_data_dir(version)

    with {:ok, _} <- create_backup_branch(tracking_dir),
         {:ok, _} <- git_checkout(tracking_dir, ref),
         :ok <- restore_files(tracking_dir, cursor_dir) do
      Logger.info("Rolled back Cursor #{version} to #{ref}")
      {:ok, :rolled_back}
    end
  end

  @doc """
  Compare two Cursor instances.
  """
  def compare(version1, version2) do
    dir1 = Config.tracking_dir(version1)
    dir2 = Config.tracking_dir(version2)

    with true <- File.dir?(dir1) || {:error, "Instance #{version1} not found"},
         true <- File.dir?(dir2) || {:error, "Instance #{version2} not found"} do
      {:ok, %{
        version1: version1,
        version2: version2,
        settings: compare_files(Path.join(dir1, "User/settings.json"), Path.join(dir2, "User/settings.json")),
        keybindings: compare_files(Path.join(dir1, "User/keybindings.json"), Path.join(dir2, "User/keybindings.json")),
        mcp: compare_files(Path.join(dir1, "cursor-home/mcp.json"), Path.join(dir2, "cursor-home/mcp.json"))
      }}
    end
  end

  @doc """
  List all snapshots for a version.
  """
  def list(version, opts \\ []) do
    GitBackend.history(version, Keyword.get(opts, :limit, 20))
  end

  defp create_backup_branch(tracking_dir) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    git_cmd(tracking_dir, ["branch", "backup-#{timestamp}"])
  end

  defp git_checkout(tracking_dir, ref) do
    git_cmd(tracking_dir, ["checkout", ref, "--", "."])
  end

  defp restore_files(tracking_dir, cursor_dir) do
    tracking_user = Path.join(tracking_dir, "User")
    cursor_user = Path.join(cursor_dir, "User")

    if File.dir?(tracking_user) and File.dir?(cursor_user) do
      for file <- ["settings.json", "keybindings.json"] do
        src = Path.join(tracking_user, file)
        dst = Path.join(cursor_user, file)
        if File.exists?(src), do: File.cp(src, dst)
      end
    end

    :ok
  end

  defp compare_files(file1, file2) do
    case {File.read(file1), File.read(file2)} do
      {{:ok, c1}, {:ok, c2}} when c1 == c2 -> :identical
      {{:ok, _}, {:ok, _}} -> :different
      {{:ok, _}, {:error, _}} -> {:only_in, :first}
      {{:error, _}, {:ok, _}} -> {:only_in, :second}
      _ -> :neither_exists
    end
  end

  defp git_cmd(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end
end
