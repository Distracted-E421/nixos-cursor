import Config

# Test configuration

# Separate test database
config :cursor_docs,
  db_path: "/tmp/cursor-docs-test"

# Minimal logging during tests
config :logger, :console,
  level: :warning

# Fast rate limiting for tests
config :cursor_docs, :rate_limit,
  requests_per_second: 100,
  burst: 100

