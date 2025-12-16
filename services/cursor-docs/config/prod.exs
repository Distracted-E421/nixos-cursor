import Config

# Production configuration

# Standard database location
config :cursor_docs,
  db_path: System.get_env("CURSOR_DOCS_DB_PATH", "~/.local/share/cursor-docs")

# Less verbose logging
config :logger, :console,
  level: :info

# Conservative rate limiting in production
config :cursor_docs, :rate_limit,
  requests_per_second: 1,
  burst: 3
