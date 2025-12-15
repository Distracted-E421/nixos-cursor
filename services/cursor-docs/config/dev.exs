import Config

# Development configuration
config :cursor_docs,
  db_path: "~/.local/share/cursor-docs-dev",
  browser_pool_size: 2

config :logger,
  level: :debug
