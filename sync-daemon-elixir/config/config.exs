import Config

# Cursor Sync Daemon Configuration
# ================================
# This configuration is loaded at compile time.
# Runtime configuration is in config/runtime.exs

config :cursor_sync,
  # Named pipe paths for IPC with cursor-studio
  command_pipe: "/tmp/cursor-sync-cmd.pipe",
  response_pipe: "/tmp/cursor-sync-resp.pipe",
  
  # Cursor database paths (will be overridden at runtime based on $HOME)
  global_db: nil,
  workspace_storage: nil,
  
  # External sync database path
  sync_db: nil,
  
  # Sync settings
  debounce_ms: 500,
  poll_interval_ms: 30_000,
  sync_on_start: true

config :logger,
  level: :info,
  backends: [:console]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:module, :function]

# Import environment specific config
import_config "#{config_env()}.exs"
