import Config

# CursorDocs configuration

# Database location
config :cursor_docs,
  db_path: "~/.local/share/cursor-docs"

# Rate limiting for web scraping
config :cursor_docs, :rate_limit,
  requests_per_second: 2,
  burst: 5

# Scraping defaults
config :cursor_docs, :scraping,
  max_pages: 100,
  max_depth: 3,
  chunk_size: 1500,
  chunk_overlap: 200,
  timeout: 30_000

# Logger configuration
config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:file, :line, :module]

# Import environment specific config
import_config "#{config_env()}.exs"
