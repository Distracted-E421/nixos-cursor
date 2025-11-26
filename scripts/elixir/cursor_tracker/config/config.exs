import Config

config :logger,
  level: :info

config :cursor_tracker,
  tracking_root: "~/.cursor-data-tracking",
  auto_watch: false,
  snapshot_interval_minutes: 5

# Import environment specific config
import_config "#{config_env()}.exs"
