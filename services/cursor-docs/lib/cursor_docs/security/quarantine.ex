defmodule CursorDocs.Security.Quarantine do
  @moduledoc """
  Data quarantine and security tier management.

  ## Security Philosophy

  ALL external data is treated as RADIOACTIVE until proven safe:
  1. Data never touches the "clean" plane until fully validated
  2. Suspicious content is quarantined, not mixed with clean data
  3. Users review flagged content via safe snapshots, never raw data
  4. Even "trusted" sources (like Cursor-indexed docs) are re-validated

  ## Security Tiers

  - `clean` - Fully validated, no security issues detected
  - `flagged` - Passed basic checks but has warnings worth reviewing
  - `quarantined` - Failed security checks, isolated from search
  - `blocked` - Rejected entirely, deemed malicious

  ## Data Flow

  ```
  External URL → Fetch → [QUARANTINE ZONE] → Validate → Clean/Flag/Block
                              ↓
                        Security Scan
                              ↓
                        Quality Check
                              ↓
                        Store with Tier
  ```

  All validation happens in the quarantine zone before data enters
  the searchable index.
  """

  use GenServer

  require Logger

  alias CursorDocs.Scraper.ContentValidator

  @tiers [:clean, :flagged, :quarantined, :blocked]

  # Alert severity levels
  @severity_critical 1
  @severity_high 2
  @severity_medium 3
  @severity_low 4

  defstruct [
    :id,
    :source_url,
    :source_name,
    :tier,
    :alerts,
    :snapshot,
    :raw_hash,
    :validated_at,
    :reviewed_by,
    :reviewed_at
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process content through the quarantine pipeline.
  Returns {:ok, tier, alerts} or {:error, reason}
  """
  def process(html, url, opts \\ []) do
    GenServer.call(__MODULE__, {:process, html, url, opts}, 60_000)
  end

  @doc """
  Get all quarantined items pending review.
  """
  def pending_review do
    GenServer.call(__MODULE__, :pending_review)
  end

  @doc """
  Get security alerts for a source.
  """
  def get_alerts(source_id) do
    GenServer.call(__MODULE__, {:get_alerts, source_id})
  end

  @doc """
  Get all alerts (for GUI display).
  """
  def all_alerts(opts \\ []) do
    GenServer.call(__MODULE__, {:all_alerts, opts})
  end

  @doc """
  Mark a quarantined item as reviewed.
  """
  def mark_reviewed(item_id, reviewer, action) when action in [:approve, :reject, :keep_flagged] do
    GenServer.call(__MODULE__, {:mark_reviewed, item_id, reviewer, action})
  end

  @doc """
  Get a safe snapshot for UI display (never raw content).
  """
  def get_snapshot(item_id) do
    GenServer.call(__MODULE__, {:get_snapshot, item_id})
  end

  # ============================================================================
  # Server Implementation
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create quarantine tables
    :ets.new(:quarantine_items, [:set, :named_table, :public])
    :ets.new(:security_alerts, [:bag, :named_table, :public])

    {:ok, %{processed_count: 0, blocked_count: 0}}
  end

  @impl true
  def handle_call({:process, html, url, opts}, _from, state) do
    result = run_quarantine_pipeline(html, url, opts)
    new_state = update_stats(state, result)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:pending_review, _from, state) do
    items = :ets.match_object(:quarantine_items, {:_, %{tier: :quarantined}})
    |> Enum.map(fn {_, item} -> item end)
    {:reply, {:ok, items}, state}
  end

  @impl true
  def handle_call({:get_alerts, source_id}, _from, state) do
    alerts = :ets.lookup(:security_alerts, source_id)
    |> Enum.map(fn {_, alert} -> alert end)
    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_call({:all_alerts, opts}, _from, state) do
    min_severity = Keyword.get(opts, :min_severity, @severity_low)
    
    alerts = :ets.tab2list(:security_alerts)
    |> Enum.map(fn {_, alert} -> alert end)
    |> Enum.filter(fn alert -> alert.severity <= min_severity end)
    |> Enum.sort_by(fn alert -> {alert.severity, alert.created_at} end)
    
    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_call({:get_snapshot, item_id}, _from, state) do
    case :ets.lookup(:quarantine_items, item_id) do
      [{_, item}] -> {:reply, {:ok, item.snapshot}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:mark_reviewed, item_id, reviewer, action}, _from, state) do
    case :ets.lookup(:quarantine_items, item_id) do
      [{_, item}] ->
        new_tier = case action do
          :approve -> :clean
          :reject -> :blocked
          :keep_flagged -> :flagged
        end
        
        updated = %{item | 
          tier: new_tier,
          reviewed_by: reviewer,
          reviewed_at: DateTime.utc_now()
        }
        
        :ets.insert(:quarantine_items, {item_id, updated})
        Logger.info("Quarantine item #{item_id} marked as #{new_tier} by #{reviewer}")
        {:reply, {:ok, updated}, state}
        
      [] -> 
        {:reply, {:error, :not_found}, state}
    end
  end

  # ============================================================================
  # Quarantine Pipeline
  # ============================================================================

  defp run_quarantine_pipeline(html, url, opts) do
    source_name = Keyword.get(opts, :name, extract_domain(url))
    item_id = generate_id()

    Logger.debug("Processing #{url} through quarantine pipeline")

    # Phase 1: Hidden content detection
    {hidden_status, hidden_alerts, clean_html} = check_hidden_content(html, url)

    # Phase 2: Prompt injection scan
    {injection_status, injection_alerts, sanitized_html} = check_prompt_injection(clean_html, url)

    # Phase 3: Quality validation
    {quality_status, quality_alerts} = check_quality(sanitized_html, url)

    # Aggregate alerts
    all_alerts = hidden_alerts ++ injection_alerts ++ quality_alerts

    # Determine final tier
    tier = determine_tier(hidden_status, injection_status, quality_status)

    # Create safe snapshot for review
    snapshot = create_safe_snapshot(sanitized_html, url, all_alerts)

    # Store in quarantine
    item = %__MODULE__{
      id: item_id,
      source_url: url,
      source_name: source_name,
      tier: tier,
      alerts: all_alerts,
      snapshot: snapshot,
      raw_hash: :crypto.hash(:sha256, html) |> Base.encode16(case: :lower),
      validated_at: DateTime.utc_now(),
      reviewed_by: nil,
      reviewed_at: nil
    }

    :ets.insert(:quarantine_items, {item_id, item})

    # Store alerts for quick lookup
    Enum.each(all_alerts, fn alert ->
      :ets.insert(:security_alerts, {item_id, alert})
    end)

    if tier == :blocked do
      Logger.error("Content BLOCKED from #{url}: #{length(all_alerts)} security issues")
      {:blocked, all_alerts, nil}
    else
      Logger.info("Content from #{url} assigned tier: #{tier} (#{length(all_alerts)} alerts)")
      {:ok, tier, all_alerts, sanitized_html, item_id}
    end
  end

  defp check_hidden_content(html, url) do
    case ContentValidator.detect_hidden_content(html) do
      {:ok, clean} ->
        {:clean, [], clean}

      {:suspicious, reasons, clean} ->
        alerts = Enum.map(reasons, fn reason ->
          %{
            id: generate_id(),
            type: :hidden_content,
            severity: @severity_medium,
            source_url: url,
            description: "Hidden content detected: #{reason}",
            details: %{technique: reason},
            created_at: DateTime.utc_now()
          }
        end)
        {:flagged, alerts, clean}
    end
  end

  defp check_prompt_injection(html, url) do
    case ContentValidator.detect_prompt_injection(html) do
      {:safe, _} ->
        {:clean, [], html}

      {:suspicious, threats, _} ->
        alerts = Enum.map(threats, fn {type, severity, matches} ->
          %{
            id: generate_id(),
            type: :prompt_injection,
            severity: severity_to_int(severity),
            source_url: url,
            description: "Potential prompt injection: #{type}",
            details: %{
              injection_type: type,
              matches: Enum.take(matches, 3)  # Limit exposed matches
            },
            created_at: DateTime.utc_now()
          }
        end)
        {:flagged, alerts, html}

      {:dangerous, threats, sanitized} ->
        alerts = Enum.map(threats, fn {type, severity, matches} ->
          %{
            id: generate_id(),
            type: :prompt_injection,
            severity: @severity_critical,
            source_url: url,
            description: "DANGEROUS prompt injection: #{type}",
            details: %{
              injection_type: type,
              matches: ["[REDACTED - #{length(matches)} matches]"],  # Don't expose actual payloads
              auto_sanitized: true
            },
            created_at: DateTime.utc_now()
          }
        end)
        {:quarantined, alerts, sanitized}
    end
  end

  defp check_quality(html, url) do
    text = extract_text_safely(html)

    case ContentValidator.validate_quality(text) do
      {:valid, score} when score >= 0.6 ->
        {:clean, []}

      {:valid, score} ->
        alert = %{
          id: generate_id(),
          type: :low_quality,
          severity: @severity_low,
          source_url: url,
          description: "Low quality score: #{score}",
          details: %{quality_score: score},
          created_at: DateTime.utc_now()
        }
        {:flagged, [alert]}

      {:invalid, reasons} ->
        alerts = Enum.map(reasons, fn reason ->
          %{
            id: generate_id(),
            type: :quality_failure,
            severity: @severity_medium,
            source_url: url,
            description: "Quality check failed: #{inspect(reason)}",
            details: %{reason: reason},
            created_at: DateTime.utc_now()
          }
        end)
        {:quarantined, alerts}
    end
  end

  defp determine_tier(hidden, injection, quality) do
    statuses = [hidden, injection, quality]

    cond do
      :blocked in statuses -> :blocked
      :quarantined in statuses -> :quarantined
      :flagged in statuses -> :flagged
      true -> :clean
    end
  end

  # ============================================================================
  # Safe Snapshot Generation
  # ============================================================================

  @doc """
  Creates a safe snapshot for UI display.
  Never includes raw HTML or potentially dangerous content.
  """
  defp create_safe_snapshot(html, url, alerts) do
    text = extract_text_safely(html)

    %{
      url: url,
      title: extract_title_safely(html),
      preview: String.slice(text, 0, 500) <> "...",
      char_count: String.length(text),
      word_count: length(String.split(text)),
      alert_count: length(alerts),
      alert_summary: summarize_alerts(alerts),
      has_code_blocks: String.contains?(text, "```"),
      generated_at: DateTime.utc_now()
    }
  end

  defp summarize_alerts(alerts) do
    alerts
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, group} ->
      {type, %{
        count: length(group),
        max_severity: Enum.min_by(group, & &1.severity).severity
      }}
    end)
    |> Enum.into(%{})
  end

  defp extract_text_safely(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.filter_out("script")
        |> Floki.filter_out("style")
        |> Floki.text(sep: "\n")
        |> String.trim()
      _ ->
        ""
    end
  end

  defp extract_title_safely(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        case Floki.find(doc, "title") do
          [title | _] -> Floki.text(title) |> String.slice(0, 200)
          _ -> "Unknown"
        end
      _ ->
        "Unknown"
    end
  end

  defp extract_domain(url) do
    case URI.parse(url) do
      %{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end

  defp severity_to_int(:high), do: @severity_high
  defp severity_to_int(:medium), do: @severity_medium
  defp severity_to_int(:low), do: @severity_low
  defp severity_to_int(_), do: @severity_medium

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp update_stats(state, result) do
    case result do
      {:blocked, _, _} ->
        %{state | processed_count: state.processed_count + 1, blocked_count: state.blocked_count + 1}
      _ ->
        %{state | processed_count: state.processed_count + 1}
    end
  end
end

