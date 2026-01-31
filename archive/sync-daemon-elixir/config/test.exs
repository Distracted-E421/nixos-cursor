import Config

# Test configuration
config :cursor_sync,
  debug_mode: true,
  global_db: "test/fixtures/state.vscdb",
  workspace_storage: "test/fixtures/workspaceStorage",
  sync_db: "test/tmp/conversations.db",
  command_pipe: "test/tmp/cmd.pipe",
  response_pipe: "test/tmp/resp.pipe"

config :logger,
  level: :warning
