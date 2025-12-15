import Config

# CursorDocs configuration
config :cursor_docs,
  # Database path (SurrealDB data directory)
  db_path: System.get_env("CURSOR_DOCS_DB_PATH", "~/.local/share/cursor-docs"),

  # Number of concurrent browser instances for scraping
  browser_pool_size: String.to_integer(System.get_env("CURSOR_DOCS_BROWSER_POOL", "3")),

  # Content chunking settings
  chunk_size: String.to_integer(System.get_env("CURSOR_DOCS_CHUNK_SIZE", "1500")),
  chunk_overlap: String.to_integer(System.get_env("CURSOR_DOCS_CHUNK_OVERLAP", "200")),

  # Scraping settings
  page_timeout: String.to_integer(System.get_env("CURSOR_DOCS_TIMEOUT", "30000")),
  max_retries: String.to_integer(System.get_env("CURSOR_DOCS_RETRIES", "3")),

  # Rate limiting
  rate_limit: [
    requests_per_second: 2,
    burst: 5
  ],

  # Default crawl settings
  default_max_pages: 100,
  default_depth: 3

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :source_id]

config :logger,
  level: :info

# Import environment specific config
import_config "#{config_env()}.exs"
