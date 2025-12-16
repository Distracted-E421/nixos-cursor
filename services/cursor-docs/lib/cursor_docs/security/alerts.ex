defmodule CursorDocs.Security.Alerts do
  @moduledoc """
  Security alert management and GUI integration.

  Provides:
  - Alert storage and retrieval
  - Safe snapshot generation for GUI display
  - Alert aggregation and statistics
  - Export format for cursor-studio integration
  """

  require Logger

  alias CursorDocs.Security.Quarantine

  @severity_labels %{
    1 => %{name: "Critical", color: "#FF0000", icon: "🚨"},
    2 => %{name: "High", color: "#FF6B00", icon: "⚠️"},
    3 => %{name: "Medium", color: "#FFB800", icon: "⚡"},
    4 => %{name: "Low", color: "#00B8FF", icon: "ℹ️"}
  }

  @type_descriptions %{
    hidden_content: "Content hidden using CSS techniques that could conceal malicious payloads",
    prompt_injection: "Patterns that attempt to manipulate AI behavior or extract information",
    low_quality: "Content quality below threshold - may not be useful documentation",
    quality_failure: "Content failed quality validation - may be error page or login wall"
  }

  # ============================================================================
  # Alert Retrieval
  # ============================================================================

  @doc """
  Get all alerts in a format suitable for GUI display.
  Returns sanitized, safe-to-render alert data.
  """
  def get_alerts_for_gui(opts \\ []) do
    case Quarantine.all_alerts(opts) do
      {:ok, alerts} ->
        gui_alerts = Enum.map(alerts, &format_for_gui/1)
        {:ok, gui_alerts}

      error ->
        error
    end
  end

  @doc """
  Get alerts grouped by source for dashboard view.
  """
  def get_alerts_by_source do
    case Quarantine.all_alerts() do
      {:ok, alerts} ->
        grouped = alerts
        |> Enum.group_by(& &1.source_url)
        |> Enum.map(fn {url, source_alerts} ->
          %{
            url: url,
            alert_count: length(source_alerts),
            max_severity: Enum.min_by(source_alerts, & &1.severity).severity,
            severity_label: get_severity_label(Enum.min_by(source_alerts, & &1.severity).severity),
            types: source_alerts |> Enum.map(& &1.type) |> Enum.uniq(),
            last_alert: source_alerts |> Enum.max_by(& &1.created_at) |> Map.get(:created_at)
          }
        end)
        |> Enum.sort_by(fn s -> {s.max_severity, s.last_alert} end)

        {:ok, grouped}

      error ->
        error
    end
  end

  @doc """
  Get alert statistics for dashboard.
  """
  def get_stats do
    case Quarantine.all_alerts() do
      {:ok, alerts} ->
        stats = %{
          total: length(alerts),
          by_severity: count_by_severity(alerts),
          by_type: count_by_type(alerts),
          recent_24h: count_recent(alerts, 24),
          recent_7d: count_recent(alerts, 24 * 7),
          sources_affected: alerts |> Enum.map(& &1.source_url) |> Enum.uniq() |> length()
        }
        {:ok, stats}

      error ->
        error
    end
  end

  @doc """
  Get a safe snapshot for displaying in GUI.
  This NEVER returns raw content - only sanitized previews.
  """
  def get_safe_snapshot(item_id) do
    case Quarantine.get_snapshot(item_id) do
      {:ok, snapshot} ->
        # Add GUI-specific formatting
        {:ok, %{
          snapshot: snapshot,
          display: format_snapshot_for_display(snapshot)
        }}

      error ->
        error
    end
  end

  # ============================================================================
  # GUI Formatting
  # ============================================================================

  defp format_for_gui(alert) do
    severity_info = @severity_labels[alert.severity] || @severity_labels[4]
    type_desc = @type_descriptions[alert.type] || "Unknown alert type"

    %{
      id: alert.id,
      type: alert.type,
      type_label: alert.type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
      type_description: type_desc,
      severity: alert.severity,
      severity_label: severity_info.name,
      severity_color: severity_info.color,
      severity_icon: severity_info.icon,
      source_url: alert.source_url,
      # NEVER include raw details - only safe summary
      description: alert.description,
      safe_details: sanitize_details(alert.details),
      created_at: alert.created_at,
      created_ago: time_ago(alert.created_at),
      actions: available_actions(alert)
    }
  end

  defp sanitize_details(details) when is_map(details) do
    # Remove any potentially dangerous fields
    details
    |> Map.drop([:raw_content, :html, :payload, :matches])
    |> Enum.map(fn {k, v} ->
      {k, sanitize_value(v)}
    end)
    |> Enum.into(%{})
  end

  defp sanitize_details(_), do: %{}

  defp sanitize_value(v) when is_binary(v) do
    # Truncate and escape
    v
    |> String.slice(0, 100)
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/[<>&"']/, "")
  end

  defp sanitize_value(v) when is_list(v) do
    Enum.map(v, &sanitize_value/1)
  end

  defp sanitize_value(v), do: v

  defp format_snapshot_for_display(snapshot) do
    %{
      title: snapshot.title,
      url: snapshot.url,
      preview: snapshot.preview,
      stats: %{
        characters: snapshot.char_count,
        words: snapshot.word_count,
        alerts: snapshot.alert_count,
        has_code: snapshot.has_code_blocks
      },
      alert_breakdown: format_alert_summary(snapshot.alert_summary),
      generated_at: snapshot.generated_at
    }
  end

  defp format_alert_summary(summary) when is_map(summary) do
    Enum.map(summary, fn {type, info} ->
      severity_info = @severity_labels[info.max_severity] || @severity_labels[4]
      %{
        type: type,
        type_label: type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
        count: info.count,
        severity: severity_info.name,
        color: severity_info.color
      }
    end)
  end

  defp format_alert_summary(_), do: []

  defp get_severity_label(severity) do
    (@severity_labels[severity] || @severity_labels[4]).name
  end

  defp available_actions(alert) do
    base_actions = [
      %{id: :view_snapshot, label: "View Safe Snapshot", icon: "👁️"},
      %{id: :dismiss, label: "Dismiss Alert", icon: "✓"}
    ]

    case alert.severity do
      1 -> base_actions ++ [%{id: :block_source, label: "Block Source", icon: "🚫"}]
      2 -> base_actions ++ [%{id: :review, label: "Request Review", icon: "📋"}]
      _ -> base_actions
    end
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  defp count_by_severity(alerts) do
    alerts
    |> Enum.group_by(& &1.severity)
    |> Enum.map(fn {sev, group} ->
      info = @severity_labels[sev] || @severity_labels[4]
      {info.name, length(group)}
    end)
    |> Enum.into(%{})
  end

  defp count_by_type(alerts) do
    alerts
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, group} -> {type, length(group)} end)
    |> Enum.into(%{})
  end

  defp count_recent(alerts, hours) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    Enum.count(alerts, fn alert ->
      DateTime.compare(alert.created_at, cutoff) == :gt
    end)
  end

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604800 -> "#{div(diff, 86400)} days ago"
      true -> "#{div(diff, 604800)} weeks ago"
    end
  end

  # ============================================================================
  # Export for cursor-studio
  # ============================================================================

  @doc """
  Export alerts in JSON format for cursor-studio GUI.
  """
  def export_for_cursor_studio do
    with {:ok, alerts} <- get_alerts_for_gui(),
         {:ok, stats} <- get_stats(),
         {:ok, by_source} <- get_alerts_by_source() do
      {:ok, %{
        version: "1.0",
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        stats: stats,
        sources: by_source,
        alerts: alerts,
        # Include severity legend for UI
        severity_levels: @severity_labels,
        type_descriptions: @type_descriptions
      }}
    end
  end

  @doc """
  Write alerts export to file for cursor-studio to read.
  """
  def write_export_file(path \\ nil) do
    path = path || Path.join(System.tmp_dir!(), "cursor-docs-alerts.json")

    case export_for_cursor_studio() do
      {:ok, data} ->
        json = Jason.encode!(data, pretty: true)
        File.write!(path, json)
        Logger.info("Wrote security alerts export to #{path}")
        {:ok, path}

      error ->
        error
    end
  end
end

