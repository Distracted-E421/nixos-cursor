import Config

# Runtime configuration
# =====================
# This file is executed at runtime (not compile time)
# Great for environment-specific or system-dependent config

home = System.get_env("HOME", "/home/e421")
config_dir = System.get_env("XDG_CONFIG_HOME", Path.join(home, ".config"))

config :cursor_sync,
  # Cursor database paths
  global_db: Path.join([config_dir, "Cursor", "User", "globalStorage", "state.vscdb"]),
  workspace_storage: Path.join([config_dir, "Cursor", "User", "workspaceStorage"]),
  
  # External sync database
  sync_db: Path.join([config_dir, "cursor-studio", "conversations.db"]),
  
  # Named pipes (can be overridden)
  command_pipe: System.get_env("CURSOR_SYNC_CMD_PIPE", "/tmp/cursor-sync-cmd.pipe"),
  response_pipe: System.get_env("CURSOR_SYNC_RESP_PIPE", "/tmp/cursor-sync-resp.pipe")

# Log level from environment
if log_level = System.get_env("CURSOR_SYNC_LOG_LEVEL") do
  config :logger, level: String.to_atom(log_level)
end
