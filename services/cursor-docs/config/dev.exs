import Config

# Development configuration

# Use a separate dev database
config :cursor_docs,
  db_path: "~/.local/share/cursor-docs-dev"

# More verbose logging in development
config :logger, :console,
  level: :debug

# Faster rate limiting for testing
config :cursor_docs, :rate_limit,
  requests_per_second: 5,
  burst: 10
