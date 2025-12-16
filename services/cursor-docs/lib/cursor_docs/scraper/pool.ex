defmodule CursorDocs.Scraper.Pool do
  @moduledoc """
  Process pool for concurrent scraping.

  Currently uses simple HTTP fetching. Browser automation (Wallaby/Playwright)
  can be added later for JavaScript-rendered content.
  """

  use DynamicSupervisor

  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Get pool statistics.
  """
  @spec stats() :: map()
  def stats do
    try do
      children = DynamicSupervisor.count_children(__MODULE__)

      %{
        active: children[:active] || 0,
        specs: children[:specs] || 0,
        supervisors: children[:supervisors] || 0,
        workers: children[:workers] || 0
      }
    catch
      :exit, _ ->
        %{active: 0, specs: 0, supervisors: 0, workers: 0}
    end
  end

  @doc """
  Execute a function with rate limiting.
  """
  @spec with_worker(function()) :: {:ok, term()} | {:error, term()}
  def with_worker(fun) when is_function(fun, 0) do
    # Simple execution - rate limiting is handled elsewhere
    try do
      {:ok, fun.()}
    rescue
      e -> {:error, e}
    end
  end
end
