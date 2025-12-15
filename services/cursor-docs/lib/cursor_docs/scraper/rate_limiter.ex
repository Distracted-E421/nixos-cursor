defmodule CursorDocs.Scraper.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for documentation scraping.

  Prevents overwhelming documentation servers with too many requests.
  Uses a token bucket algorithm with configurable:
  - Requests per second
  - Burst capacity

  ## Configuration

      config :cursor_docs,
        rate_limit: [
          requests_per_second: 2,
          burst: 5
        ]

  ## Usage

      # Wait for permission to make a request
      :ok = RateLimiter.acquire()

      # Or check without blocking
      case RateLimiter.try_acquire() do
        :ok -> make_request()
        {:error, :rate_limited} -> wait_and_retry()
      end
  """

  use GenServer

  require Logger

  @default_rate 2  # requests per second
  @default_burst 5

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquire a token, blocking until one is available.
  """
  @spec acquire(timeout()) :: :ok | {:error, :timeout}
  def acquire(timeout \\ 5_000) do
    GenServer.call(__MODULE__, :acquire, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  Try to acquire a token without blocking.
  """
  @spec try_acquire() :: :ok | {:error, :rate_limited}
  def try_acquire do
    GenServer.call(__MODULE__, :try_acquire)
  end

  @doc """
  Get current rate limiter stats.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    rate = Keyword.get(opts, :requests_per_second, @default_rate)
    burst = Keyword.get(opts, :burst, @default_burst)

    state = %{
      tokens: burst,
      max_tokens: burst,
      rate: rate,
      last_refill: System.monotonic_time(:millisecond),
      waiting: :queue.new(),
      total_requests: 0,
      total_wait_ms: 0
    }

    # Schedule periodic refill
    schedule_refill(rate)

    Logger.info("Rate limiter started: #{rate} req/s, burst: #{burst}")

    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, from, state) do
    state = refill_tokens(state)

    if state.tokens >= 1 do
      # Token available
      {:reply, :ok, %{state | tokens: state.tokens - 1, total_requests: state.total_requests + 1}}
    else
      # Queue the request
      new_waiting = :queue.in({from, System.monotonic_time(:millisecond)}, state.waiting)
      {:noreply, %{state | waiting: new_waiting}}
    end
  end

  @impl true
  def handle_call(:try_acquire, _from, state) do
    state = refill_tokens(state)

    if state.tokens >= 1 do
      {:reply, :ok, %{state | tokens: state.tokens - 1, total_requests: state.total_requests + 1}}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      available_tokens: state.tokens,
      max_tokens: state.max_tokens,
      rate: state.rate,
      queued: :queue.len(state.waiting),
      total_requests: state.total_requests,
      avg_wait_ms: if(state.total_requests > 0,
        do: state.total_wait_ms / state.total_requests,
        else: 0)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:refill, state) do
    state = refill_tokens(state)
    state = process_waiting(state)

    schedule_refill(state.rate)

    {:noreply, state}
  end

  # Private Functions

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.last_refill

    # Add tokens based on elapsed time
    tokens_to_add = elapsed_ms / 1000 * state.rate
    new_tokens = min(state.tokens + tokens_to_add, state.max_tokens)

    %{state | tokens: new_tokens, last_refill: now}
  end

  defp process_waiting(state) do
    case :queue.out(state.waiting) do
      {{:value, {from, queued_at}}, new_waiting} when state.tokens >= 1 ->
        # Grant token to waiting request
        GenServer.reply(from, :ok)

        wait_ms = System.monotonic_time(:millisecond) - queued_at

        new_state = %{state |
          tokens: state.tokens - 1,
          waiting: new_waiting,
          total_requests: state.total_requests + 1,
          total_wait_ms: state.total_wait_ms + wait_ms
        }

        # Process more waiting requests if tokens available
        process_waiting(new_state)

      _ ->
        state
    end
  end

  defp schedule_refill(rate) do
    # Refill at rate frequency, minimum 100ms
    interval = max(trunc(1000 / rate), 100)
    Process.send_after(self(), :refill, interval)
  end
end

