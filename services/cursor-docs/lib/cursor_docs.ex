defmodule CursorDocs do
  @moduledoc """
  CursorDocs - Local documentation indexing service for Cursor IDE.

  This service provides a reliable, local alternative to Cursor's built-in @docs
  feature, which frequently fails due to server-side crawling issues.

  ## Features

  - **Reliable Scraping**: Uses Playwright for full JavaScript rendering
  - **Local Storage**: SurrealDB for fast, queryable storage
  - **MCP Integration**: Seamless integration with Cursor via MCP protocol
  - **Fault Tolerant**: OTP supervision tree for automatic recovery

  ## Quick Start

      # Add documentation
      CursorDocs.add("https://docs.example.com/")

      # Search
      CursorDocs.search("authentication")

      # List all indexed docs
      CursorDocs.list()

  ## Architecture

  The service is built on these core components:

  - `CursorDocs.Scraper` - Playwright-based web scraping
  - `CursorDocs.Storage` - SurrealDB persistence layer
  - `CursorDocs.MCP` - Model Context Protocol server

  See individual module documentation for details.
  """

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

  Returns chunks matching the query, sorted by relevance.

  ## Options

    * `:limit` - Maximum results to return (default: 5)
    * `:sources` - Filter by specific source names (list)
    * `:min_score` - Minimum relevance score (default: 0.0)

  ## Examples

      iex> CursorDocs.search("database queries")
      {:ok, [%CursorDocs.Chunk{content: "...", score: 0.85}, ...]}

      iex> CursorDocs.search("authentication", sources: ["Ecto", "Phoenix"])
      {:ok, [...]}

  """
  @spec search(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def search(query, opts \\ []) do
    CursorDocs.Storage.Search.search(query, opts)
  end

  @doc """
  List all indexed documentation sources.

  ## Examples

      iex> CursorDocs.list()
      {:ok, [
        %CursorDocs.DocSource{name: "Ecto", pages: 234, status: :indexed},
        %CursorDocs.DocSource{name: "Phoenix", pages: 567, status: :indexing}
      ]}

  """
  @spec list() :: {:ok, list(map())} | {:error, term()}
  def list do
    CursorDocs.Storage.Surreal.list_sources()
  end

  @doc """
  Get status of scraping jobs.

  ## Options

    * `:source` - Filter by source name

  ## Examples

      iex> CursorDocs.status()
      {:ok, [
        %{source: "Ecto", status: :complete, pages: 234, errors: 2},
        %{source: "Phoenix", status: :in_progress, pages: 123, queued: 444}
      ]}

  """
  @spec status(keyword()) :: {:ok, list(map())} | {:error, term()}
  def status(opts \\ []) do
    CursorDocs.Scraper.Job.status(opts)
  end

  @doc """
  Remove a documentation source and all its chunks.

  ## Examples

      iex> CursorDocs.remove("ecto")
      :ok

  """
  @spec remove(String.t()) :: :ok | {:error, term()}
  def remove(source_id) do
    CursorDocs.Storage.Surreal.remove_source(source_id)
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
