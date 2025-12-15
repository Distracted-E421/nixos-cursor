defmodule CursorDocs.Scraper.Pool do
  @moduledoc """
  Manages a pool of Playwright browser instances for concurrent scraping.

  The pool uses NimblePool for efficient resource management:
  - Browsers are pre-warmed on startup
  - Crashed browsers are automatically replaced
  - Resources are properly cleaned up on shutdown

  ## Configuration

      config :cursor_docs,
        browser_pool_size: 3,  # Number of browser instances
        page_timeout: 30_000   # Page load timeout in ms
  """

  use GenServer

  require Logger

  @default_pool_size 3
  @default_timeout 30_000

  # Client API

  @doc """
  Start the browser pool.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a function with a browser page from the pool.

  The page is automatically returned to the pool after the function completes.

  ## Examples

      Pool.with_page(fn page ->
        Playwright.Page.goto(page, "https://example.com")
        Playwright.Page.content(page)
      end)

  """
  @spec with_page((Playwright.Page.t() -> result)) :: {:ok, result} | {:error, term()}
        when result: term()
  def with_page(fun, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:with_page, fun, timeout}, timeout + 5_000)
  end

  @doc """
  Get current pool statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :size, @default_pool_size)

    Logger.info("Initializing browser pool with #{pool_size} instances")

    state = %{
      pool_size: pool_size,
      browsers: [],
      available: [],
      busy: %{},
      stats: %{
        total_requests: 0,
        successful: 0,
        failed: 0,
        timeouts: 0
      }
    }

    # Start browsers asynchronously
    send(self(), :init_browsers)

    {:ok, state}
  end

  @impl true
  def handle_info(:init_browsers, state) do
    browsers =
      1..state.pool_size
      |> Enum.map(fn _i ->
        case start_browser() do
          {:ok, browser} -> browser
          {:error, reason} ->
            Logger.warning("Failed to start browser: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Logger.info("Started #{length(browsers)} browser instances")

    {:noreply, %{state | browsers: browsers, available: browsers}}
  end

  @impl true
  def handle_call({:with_page, fun, timeout}, from, state) do
    case state.available do
      [browser | rest] ->
        # Got a browser, execute the function
        task_ref = make_ref()
        task = Task.async(fn -> execute_with_page(browser, fun, timeout) end)

        new_busy = Map.put(state.busy, task_ref, {browser, from, task})
        new_stats = Map.update!(state.stats, :total_requests, &(&1 + 1))

        {:noreply, %{state | available: rest, busy: new_busy, stats: new_stats}}

      [] ->
        # No browsers available, queue the request
        Logger.debug("No browsers available, request queued")
        {:reply, {:error, :pool_exhausted}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.merge(state.stats, %{
      available: length(state.available),
      busy: map_size(state.busy),
      total_browsers: length(state.browsers)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed
    case find_task_by_ref(state.busy, ref) do
      {task_ref, {browser, from, _task}} ->
        # Return result to caller
        case result do
          {:ok, _} = ok ->
            GenServer.reply(from, ok)
            new_stats = Map.update!(state.stats, :successful, &(&1 + 1))
            {:noreply, return_browser(state, task_ref, browser, new_stats)}

          {:error, reason} = error ->
            Logger.warning("Page execution failed: #{inspect(reason)}")
            GenServer.reply(from, error)
            new_stats = Map.update!(state.stats, :failed, &(&1 + 1))
            {:noreply, return_browser(state, task_ref, browser, new_stats)}
        end

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("Browser task crashed: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down browser pool")

    # Close all browsers
    Enum.each(state.browsers, fn browser ->
      try do
        Playwright.Browser.close(browser)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  # Private Functions

  defp start_browser do
    # Start Playwright and launch browser
    with {:ok, playwright} <- Playwright.start(),
         {:ok, browser} <- Playwright.launch(playwright, :chromium, headless: true) do
      {:ok, browser}
    end
  end

  defp execute_with_page(browser, fun, timeout) do
    # Create a new page for this request
    case Playwright.Browser.new_page(browser) do
      {:ok, page} ->
        try do
          # Set timeout
          Playwright.Page.set_default_timeout(page, timeout)

          # Execute the user's function
          result = fun.(page)
          {:ok, result}
        catch
          kind, reason ->
            {:error, {kind, reason, __STACKTRACE__}}
        after
          # Always close the page
          try do
            Playwright.Page.close(page)
          catch
            _, _ -> :ok
          end
        end

      {:error, reason} ->
        {:error, {:page_creation_failed, reason}}
    end
  end

  defp find_task_by_ref(busy, ref) do
    Enum.find(busy, fn {_task_ref, {_browser, _from, task}} ->
      task.ref == ref
    end)
  end

  defp return_browser(state, task_ref, browser, new_stats) do
    new_busy = Map.delete(state.busy, task_ref)
    new_available = [browser | state.available]

    %{state | busy: new_busy, available: new_available, stats: new_stats}
  end
end
