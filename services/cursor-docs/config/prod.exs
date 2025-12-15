import Config

# Production configuration
config :cursor_docs,
  db_path: System.get_env("CURSOR_DOCS_DB_PATH", "~/.local/share/cursor-docs"),
  browser_pool_size: 3

config :logger,
  level: :info
