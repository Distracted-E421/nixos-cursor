defmodule CursorDocs.Progress do
  @moduledoc """
  Structured progress reporting for CLI consumers.

  Emits JSON-formatted progress updates that can be parsed by GUIs.
  Format: {"type": "<event>", "data": {...}}

  ## Event Types

  - `started` - Indexing started
  - `page` - Page progress update
  - `complete` - Indexing completed
  - `error` - Error occurred
  - `security` - Security alert
  """

  @doc """
  Report that indexing has started.
  """
  def started(url, name, max_pages) do
    emit(%{
      type: "started",
      data: %{
        url: url,
        name: name,
        max_pages: max_pages,
        timestamp: timestamp()
      }
    })
  end

  @doc """
  Report page progress.
  """
  def page(url, current, total, status) do
    emit(%{
      type: "page",
      data: %{
        url: url,
        current: current,
        total: total,
        status: status,
        timestamp: timestamp()
      }
    })
  end

  @doc """
  Report security alert.
  """
  def security_alert(url, tier, alert_count) do
    emit(%{
      type: "security",
      data: %{
        url: url,
        tier: tier,
        alert_count: alert_count,
        timestamp: timestamp()
      }
    })
  end

  @doc """
  Report completion.
  """
  def complete(url, name, id, chunks_count, duration_ms) do
    emit(%{
      type: "complete",
      data: %{
        url: url,
        name: name,
        id: id,
        chunks: chunks_count,
        duration_ms: duration_ms,
        timestamp: timestamp()
      }
    })
  end

  @doc """
  Report error.
  """
  def error(url, reason) do
    emit(%{
      type: "error",
      data: %{
        url: url,
        reason: format_reason(reason),
        timestamp: timestamp()
      }
    })
  end

  # Emit JSON to stdout (prefixed with PROGRESS: for easy parsing)
  defp emit(event) do
    json = Jason.encode!(event)
    IO.puts("PROGRESS:#{json}")
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
