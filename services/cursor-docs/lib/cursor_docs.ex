defmodule CursorDocs do
  @moduledoc """
  CursorDocs - Local documentation indexing service for Cursor IDE.

  This service provides a reliable, local alternative to Cursor's built-in @docs
  feature, which frequently fails due to server-side crawling issues.

  ## Key Feature: Cursor Integration

  **No new workflow required!** CursorDocs automatically reads the same URLs
  you've added via Cursor's Settings → Indexing & Docs, then indexes them
  locally with much higher reliability.

  ## Features

  - **Cursor Sync**: Uses the same @docs URLs from Cursor's settings
  - **Reliable Scraping**: Full JavaScript rendering via headless browser
  - **Local Storage**: SQLite with FTS5 full-text search
  - **MCP Integration**: Seamless integration with Cursor via MCP protocol
  - **Fault Tolerant**: OTP supervision tree for automatic recovery

  ## Quick Start

      # Sync docs from Cursor's existing @docs
      CursorDocs.sync_from_cursor()

      # Or add documentation manually
      CursorDocs.add("https://docs.example.com/")

      # Search
      CursorDocs.search("authentication")

      # List all indexed docs
      CursorDocs.list()

  ## Architecture

  The service is built on these core components:

  - `CursorDocs.CursorIntegration` - Syncs with Cursor's @docs settings
  - `CursorDocs.Scraper` - Web scraping with JS rendering
  - `CursorDocs.Storage.SQLite` - Local SQLite with FTS5
  - `CursorDocs.MCP` - Model Context Protocol server

  See individual module documentation for details.
  """

  @doc """
  Sync documentation from Cursor's existing @docs settings.

  This is the **primary way** to use CursorDocs - it reads the same URLs
  you've already configured in Cursor's Settings → Indexing & Docs.

  ## Examples

      iex> CursorDocs.sync_from_cursor()
      {:ok, 5}  # Synced 5 docs from Cursor

  """
  @spec sync_from_cursor() :: {:ok, integer()} | {:error, term()}
  def sync_from_cursor do
    CursorDocs.CursorIntegration.sync_docs()
  end

  @doc """
  List documentation URLs configured in Cursor.

  Shows what Cursor has in its @docs settings without indexing them.
  """
  @spec list_cursor_docs() :: {:ok, list(map())} | {:error, term()}
  def list_cursor_docs do
    CursorDocs.CursorIntegration.list_cursor_docs()
  end

  @doc """
  Add a documentation URL to be indexed.

  ## Options

    * `:name` - Display name for the documentation source
    * `:max_pages` - Maximum number of pages to crawl (default: 100)
    * `:depth` - Maximum crawl depth (default: 3)

  ## Examples

      iex> CursorDocs.add("https://hexdocs.pm/ecto/Ecto.html")
      {:ok, %CursorDocs.DocSource{id: "abc123", ...}}

      iex> CursorDocs.add("https://docs.pola.rs/", name: "Polars", max_pages: 500)
      {:ok, %CursorDocs.DocSource{...}}

  """
  @spec add(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add(url, opts \\ []) do
    CursorDocs.Scraper.add(url, opts)
  end

  @doc """
  Search indexed documentation.

  Returns chunks matching the query, sorted by relevance using FTS5 BM25.

  ## Options

    * `:limit` - Maximum results to return (default: 5)
    * `:sources` - Filter by specific source IDs (list)

  ## Examples

      iex> CursorDocs.search("database queries")
      {:ok, [%{content: "...", score: 0.85}, ...]}

      iex> CursorDocs.search("authentication", sources: ["abc123"])
      {:ok, [...]}

  """
  @spec search(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search(query, opts \\ []) do
    CursorDocs.Storage.SQLite.search_chunks(query, opts)
  end

  @doc """
  List all indexed documentation sources.

  ## Examples

      iex> CursorDocs.list()
      {:ok, [
        %{name: "Ecto", pages_count: 234, status: "indexed"},
        %{name: "Phoenix", pages_count: 567, status: "indexing"}
      ]}

  """
  @spec list() :: {:ok, list(map())} | {:error, term()}
  def list do
    CursorDocs.Storage.SQLite.list_sources()
  end

  @doc """
  Get status of scraping jobs.

  ## Options

    * `:source` - Filter by source ID

  ## Examples

      iex> CursorDocs.status()
      {:ok, [
        %{source: "abc123", status: :complete, pages: 234},
        %{source: "def456", status: :in_progress, queued: 444}
      ]}

  """
  @spec status(keyword()) :: {:ok, list(map())} | {:error, term()}
  def status(opts \\ []) do
    CursorDocs.Scraper.JobQueue.status(opts)
  end

  @doc """
  Remove a documentation source and all its chunks.

  ## Examples

      iex> CursorDocs.remove("abc123")
      :ok

  """
  @spec remove(String.t()) :: :ok | {:error, term()}
  def remove(source_id) do
    CursorDocs.Storage.SQLite.remove_source(source_id)
  end

  @doc """
  Refresh a documentation source (re-scrape all pages).

  ## Examples

      iex> CursorDocs.refresh("ecto")
      {:ok, %CursorDocs.DocSource{status: :queued, ...}}

  """
  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(source_id) do
    CursorDocs.Scraper.refresh(source_id)
  end
end
