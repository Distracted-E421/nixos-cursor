defmodule CursorDocs.Scraper.Background do
  @moduledoc """
  Background crawler with live progress updates.
  
  Key features:
  - Non-blocking crawling in separate process
  - Live progress updates via PubSub
  - Multiple concurrent crawl jobs
  - Proof-of-work display for AI and human visibility
  
  Usage:
      # Start a background crawl
      {:ok, job_id} = Background.start_crawl("https://docs.example.com", name: "Example Docs")
      
      # Check status
      Background.status(job_id)
      
      # List all jobs
      Background.list_jobs()
      
      # Subscribe to updates
      Background.subscribe(job_id)
  """
  
  use GenServer
  require Logger
  
  alias CursorDocs.Scraper
  
  @type job_id :: String.t()
  @type job_status :: :pending | :discovering | :crawling | :completed | :failed | :cancelled
  
  defstruct [
    :id,
    :url,
    :name,
    :status,
    :strategy,
    :started_at,
    :updated_at,
    :completed_at,
    :total_pages,
    :processed_pages,
    :successful_pages,
    :failed_pages,
    :current_url,
    :error,
    :progress_log,
    :task_ref,
    :task_pid
  ]
  
  @type t :: %__MODULE__{
    id: job_id(),
    url: String.t(),
    name: String.t(),
    status: job_status(),
    strategy: atom() | nil,
    started_at: DateTime.t(),
    updated_at: DateTime.t(),
    completed_at: DateTime.t() | nil,
    total_pages: non_neg_integer(),
    processed_pages: non_neg_integer(),
    successful_pages: non_neg_integer(),
    failed_pages: non_neg_integer(),
    current_url: String.t() | nil,
    error: String.t() | nil,
    progress_log: list(String.t()),
    task_ref: reference() | nil,
    task_pid: pid() | nil
  }
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Start a background crawl job"
  @spec start_crawl(String.t(), keyword()) :: {:ok, job_id()} | {:error, term()}
  def start_crawl(url, opts \\ []) do
    GenServer.call(__MODULE__, {:start_crawl, url, opts})
  end
  
  @doc "Get status of a specific job"
  @spec status(job_id()) :: {:ok, t()} | {:error, :not_found}
  def status(job_id) do
    GenServer.call(__MODULE__, {:status, job_id})
  end
  
  @doc "List all jobs (active and recent)"
  @spec list_jobs() :: [t()]
  def list_jobs do
    GenServer.call(__MODULE__, :list_jobs)
  end
  
  @doc "List only active (running) jobs"
  @spec active_jobs() :: [t()]
  def active_jobs do
    GenServer.call(__MODULE__, :active_jobs)
  end
  
  @doc "Cancel a running job"
  @spec cancel(job_id()) :: :ok | {:error, :not_found | :not_running}
  def cancel(job_id) do
    GenServer.call(__MODULE__, {:cancel, job_id})
  end
  
  @doc "Subscribe to job updates (returns a stream)"
  @spec subscribe(job_id()) :: {:ok, pid()} | {:error, :not_found}
  def subscribe(job_id) do
    GenServer.call(__MODULE__, {:subscribe, job_id})
  end
  
  @doc "Get live progress display (for CLI)"
  @spec progress_display() :: String.t()
  def progress_display do
    GenServer.call(__MODULE__, :progress_display)
  end
  
  # ============================================================================
  # Server Callbacks
  # ============================================================================
  
  @impl true
  def init(_opts) do
    # Keep last 10 completed jobs for history
    state = %{
      jobs: %{},
      subscribers: %{},
      max_concurrent: 3,
      history_limit: 10
    }
    
    Logger.info("Background crawler started (max #{state.max_concurrent} concurrent jobs)")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_crawl, url, opts}, _from, state) do
    job_id = generate_job_id()
    name = Keyword.get(opts, :name, extract_name(url))
    
    job = %__MODULE__{
      id: job_id,
      url: url,
      name: name,
      status: :pending,
      strategy: nil,
      started_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      completed_at: nil,
      total_pages: 0,
      processed_pages: 0,
      successful_pages: 0,
      failed_pages: 0,
      current_url: nil,
      error: nil,
      progress_log: ["Job created for #{name}"],
      task_ref: nil,
      task_pid: nil
    }
    
    # Count active jobs
    active_count = state.jobs
      |> Map.values()
      |> Enum.count(fn j -> j.status in [:pending, :discovering, :crawling] end)
    
    if active_count >= state.max_concurrent do
      {:reply, {:error, :too_many_jobs}, state}
    else
      # Start the crawl task
      parent = self()
      task = Task.async(fn ->
        run_crawl(job_id, url, opts, parent)
      end)
      
      job = %{job | task_ref: task.ref, task_pid: task.pid, status: :discovering}
      state = put_in(state.jobs[job_id], job)
      
      log_progress(job_id, "🚀 Started background crawl")
      {:reply, {:ok, job_id}, state}
    end
  end
  
  @impl true
  def handle_call({:status, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil -> {:reply, {:error, :not_found}, state}
      job -> {:reply, {:ok, job}, state}
    end
  end
  
  @impl true
  def handle_call(:list_jobs, _from, state) do
    jobs = state.jobs
      |> Map.values()
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
    {:reply, jobs, state}
  end
  
  @impl true
  def handle_call(:active_jobs, _from, state) do
    jobs = state.jobs
      |> Map.values()
      |> Enum.filter(fn j -> j.status in [:pending, :discovering, :crawling] end)
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
    {:reply, jobs, state}
  end
  
  @impl true
  def handle_call({:cancel, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil -> 
        {:reply, {:error, :not_found}, state}
      
      %{status: status} when status not in [:pending, :discovering, :crawling] ->
        {:reply, {:error, :not_running}, state}
      
      job ->
        # Cancel the task
        if job.task_pid && Process.alive?(job.task_pid) do
          Process.exit(job.task_pid, :kill)
        end
        if job.task_ref do
          Process.demonitor(job.task_ref, [:flush])
        end
        
        job = %{job | 
          status: :cancelled, 
          completed_at: DateTime.utc_now(),
          progress_log: job.progress_log ++ ["❌ Cancelled by user"]
        }
        
        state = put_in(state.jobs[job_id], job)
        notify_subscribers(state, job_id, {:cancelled, job})
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call({:subscribe, job_id}, {pid, _}, state) do
    case Map.get(state.jobs, job_id) do
      nil -> 
        {:reply, {:error, :not_found}, state}
      
      _job ->
        # Monitor the subscriber
        Process.monitor(pid)
        
        subscribers = Map.get(state.subscribers, job_id, [])
        state = put_in(state.subscribers[job_id], [pid | subscribers])
        {:reply, {:ok, pid}, state}
    end
  end
  
  @impl true
  def handle_call(:progress_display, _from, state) do
    display = format_progress_display(state.jobs)
    {:reply, display, state}
  end
  
  @impl true
  def handle_info({:job_update, job_id, update}, state) do
    case Map.get(state.jobs, job_id) do
      nil -> 
        {:noreply, state}
      
      job ->
        job = apply_update(job, update)
        state = put_in(state.jobs[job_id], job)
        notify_subscribers(state, job_id, {:update, job})
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed
    job_id = find_job_by_ref(state.jobs, ref)
    
    if job_id do
      job = state.jobs[job_id]
      
      job = case result do
        {:ok, stats} ->
          %{job |
            status: :completed,
            completed_at: DateTime.utc_now(),
            total_pages: stats.total,
            processed_pages: stats.processed,
            successful_pages: stats.successful,
            failed_pages: stats.failed,
            progress_log: job.progress_log ++ ["✅ Completed! #{stats.successful}/#{stats.total} pages indexed"]
          }
        
        {:error, reason} ->
          %{job |
            status: :failed,
            completed_at: DateTime.utc_now(),
            error: inspect(reason),
            progress_log: job.progress_log ++ ["❌ Failed: #{inspect(reason)}"]
          }
      end
      
      state = put_in(state.jobs[job_id], job)
      notify_subscribers(state, job_id, {:completed, job})
      
      # Prune old jobs
      state = prune_old_jobs(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Task crashed
    job_id = find_job_by_ref(state.jobs, ref)
    
    if job_id do
      job = state.jobs[job_id]
      job = %{job |
        status: :failed,
        completed_at: DateTime.utc_now(),
        error: "Task crashed unexpectedly",
        progress_log: job.progress_log ++ ["💥 Task crashed"]
      }
      
      state = put_in(state.jobs[job_id], job)
      notify_subscribers(state, job_id, {:crashed, job})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp run_crawl(job_id, url, opts, parent) do
    max_pages = Keyword.get(opts, :max_pages, 100)
    name = Keyword.get(opts, :name, "Unknown")
    
    send(parent, {:job_update, job_id, {:log, "📥 Starting crawl of #{url}..."}})
    
    # Use the existing Scraper.add which handles everything
    # but inject progress callbacks
    scraper_opts = [
      name: name,
      max_pages: max_pages,
      strategy: :auto
    ]
    
    # Wrap in progress tracking
    send(parent, {:job_update, job_id, {:status, :discovering}})
    
    case Scraper.add(url, scraper_opts) do
      {:ok, source} ->
        chunks_count = source[:chunks_count] || 0
        send(parent, {:job_update, job_id, {:log, "✅ Completed: #{chunks_count} chunks indexed"}})
        
        {:ok, %{
          total: 1,
          processed: 1,
          successful: 1,
          failed: 0
        }}
      
      {:error, reason} ->
        send(parent, {:job_update, job_id, {:log, "❌ Failed: #{inspect(reason)}"}})
        {:error, reason}
    end
  end
  
  defp apply_update(job, update) do
    now = DateTime.utc_now()
    
    case update do
      {:status, status} ->
        %{job | status: status, updated_at: now}
      
      {:strategy, strategy} ->
        %{job | strategy: strategy, updated_at: now}
      
      {:total_pages, count} ->
        %{job | total_pages: count, updated_at: now}
      
      {:current_url, url} ->
        %{job | current_url: url, updated_at: now}
      
      {:page_success, _url} ->
        %{job | 
          processed_pages: job.processed_pages + 1,
          successful_pages: job.successful_pages + 1,
          updated_at: now
        }
      
      {:page_failed, _url, _reason} ->
        %{job | 
          processed_pages: job.processed_pages + 1,
          failed_pages: job.failed_pages + 1,
          updated_at: now
        }
      
      {:log, message} ->
        %{job | 
          progress_log: job.progress_log ++ [message],
          updated_at: now
        }
      
      {:progress, %{discovered: discovered}} ->
        %{job | 
          total_pages: discovered,
          updated_at: now
        }
      
      _ ->
        job
    end
  end
  
  defp notify_subscribers(state, job_id, message) do
    subscribers = Map.get(state.subscribers, job_id, [])
    Enum.each(subscribers, fn pid ->
      send(pid, {:crawl_update, job_id, message})
    end)
  end
  
  defp find_job_by_ref(jobs, ref) do
    jobs
    |> Enum.find(fn {_id, job} -> job.task_ref == ref end)
    |> case do
      {id, _job} -> id
      nil -> nil
    end
  end
  
  defp prune_old_jobs(state) do
    completed = state.jobs
      |> Map.values()
      |> Enum.filter(fn j -> j.status in [:completed, :failed, :cancelled] end)
      |> Enum.sort_by(& &1.completed_at, {:desc, DateTime})
    
    to_remove = completed
      |> Enum.drop(state.history_limit)
      |> Enum.map(& &1.id)
    
    jobs = Enum.reduce(to_remove, state.jobs, fn id, acc ->
      Map.delete(acc, id)
    end)
    
    %{state | jobs: jobs}
  end
  
  defp format_progress_display(jobs) do
    active = jobs
      |> Map.values()
      |> Enum.filter(fn j -> j.status in [:pending, :discovering, :crawling] end)
      |> Enum.sort_by(& &1.started_at, {:asc, DateTime})
    
    if Enum.empty?(active) do
      "No active crawl jobs"
    else
      lines = Enum.map(active, fn job ->
        progress = if job.total_pages > 0 do
          pct = round(job.processed_pages / job.total_pages * 100)
          bar = progress_bar(pct, 20)
          "#{bar} #{pct}% (#{job.processed_pages}/#{job.total_pages})"
        else
          status_emoji(job.status)
        end
        
        "#{job.name}: #{progress}"
      end)
      
      Enum.join(lines, "\n")
    end
  end
  
  defp progress_bar(percent, width) do
    filled = round(percent / 100 * width)
    empty = width - filled
    "[#{String.duplicate("█", filled)}#{String.duplicate("░", empty)}]"
  end
  
  defp status_emoji(:pending), do: "⏳ Pending"
  defp status_emoji(:discovering), do: "🔍 Discovering pages..."
  defp status_emoji(:crawling), do: "📥 Crawling..."
  defp status_emoji(:completed), do: "✅ Completed"
  defp status_emoji(:failed), do: "❌ Failed"
  defp status_emoji(:cancelled), do: "🚫 Cancelled"
  
  defp generate_job_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp extract_name(url) do
    case URI.parse(url) do
      %{host: host} when is_binary(host) -> 
        host |> String.replace("www.", "") |> String.split(".") |> hd()
      _ -> 
        "unknown"
    end
  end
  
  defp log_progress(job_id, message) do
    Logger.info("[Crawl #{job_id}] #{message}")
  end
end

