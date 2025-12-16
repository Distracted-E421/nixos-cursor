defmodule CursorDocs.Storage.Vector.Disabled do
  @moduledoc """
  Disabled vector storage - FTS5 keyword search only.

  This is the zero-setup tier for users who:
  - Just want Cursor to work out of the box
  - Don't have hardware for local AI
  - Prefer keyword search over semantic search
  - Want minimal resource usage

  ## Behavior

  All vector operations return graceful errors indicating
  that vector search is disabled. The application falls back
  to SQLite FTS5 for text search.

  ## Enabling Vector Search

  To enable vector search:

      # Option 1: sqlite-vss (recommended, no daemon)
      config :cursor_docs, :vector_backend, CursorDocs.Storage.Vector.SQLiteVss

      # Option 2: SurrealDB (full features)
      config :cursor_docs, :vector_backend, CursorDocs.Storage.Vector.SurrealDB

  """

  @behaviour CursorDocs.Storage.Vector

  # No-op start_link for supervisor compatibility
  def start_link(_opts \\ []) do
    :ignore
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @impl true
  def name, do: "Disabled (FTS5 only)"

  @impl true
  def available?, do: true  # Always available as fallback

  @impl true
  def tier, do: :disabled

  @impl true
  def start(_opts) do
    :ignore
  end

  @impl true
  def store(_chunk_id, _embedding, _metadata) do
    {:error, :vector_storage_disabled}
  end

  @impl true
  def store_batch(_items) do
    {:error, :vector_storage_disabled}
  end

  @impl true
  def search(_embedding, _opts) do
    {:error, :vector_storage_disabled}
  end

  @impl true
  def delete_for_source(_source_id) do
    # No-op when disabled
    :ok
  end

  @impl true
  def stats do
    %{
      total_vectors: 0,
      dimensions: nil,
      storage_bytes: 0
    }
  end

  @impl true
  def healthy?, do: true
end
