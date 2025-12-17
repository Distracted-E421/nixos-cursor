defmodule CursorDocs.HTTP.Router do
  @moduledoc """
  HTTP request router for CursorDocs API.
  """

  require Logger

  @doc """
  Route and handle an HTTP request.

  Returns `{status_code, headers_map, body_string}`.
  """
  def handle(%{method: method, path: path, query: params, body: body}) do
    method_str = method |> to_string() |> String.upcase()

    # Remove /api prefix if present
    path = String.replace_prefix(path, "/api", "")

    Logger.debug("HTTP #{method_str} #{path}")

    route(method_str, path, params, body)
  end

  # Health & Status

  defp route("GET", "/health", _params, _body) do
    json_response(200, %{status: "ok", service: "cursor-docs"})
  end

  defp route("GET", "/status", _params, _body) do
    status = CursorDocs.Storage.status()

    sources_count =
      case CursorDocs.Storage.list_sources() do
        {:ok, sources} -> length(sources)
        _ -> 0
      end

    json_response(200, %{
      status: "ok",
      backend: status.backend,
      sources_count: sources_count,
      features: status.features
    })
  end

  # Search

  defp route("GET", "/search", params, _body) do
    query = Map.get(params, "q", "")
    limit = get_int_param(params, "limit", 10)
    mode = Map.get(params, "mode", "auto") |> String.to_atom()

    if query == "" do
      json_response(400, %{error: "Missing query parameter 'q'"})
    else
      case CursorDocs.Search.query(query, limit: limit, mode: mode) do
        {:ok, results} ->
          json_response(200, %{query: query, results: format_search_results(results)})

        {:error, reason} ->
          json_response(500, %{error: inspect(reason)})
      end
    end
  end

  # Context generation

  defp route("GET", "/context", params, _body) do
    query = Map.get(params, "q", "")
    format = Map.get(params, "format", "markdown")
    limit = get_int_param(params, "limit", 5)

    if query == "" do
      json_response(400, %{error: "Missing query parameter 'q'"})
    else
      context = generate_context(query, limit)

      case format do
        "markdown" ->
          {200, %{"Content-Type" => "text/markdown; charset=utf-8"}, context}

        "json" ->
          json_response(200, %{query: query, context: context})

        _ ->
          json_response(400, %{error: "Unknown format: #{format}"})
      end
    end
  end

  defp route("GET", "/context/file", params, _body) do
    query = Map.get(params, "q", "")
    path = Map.get(params, "path", "/tmp/cursor-context.md")
    limit = get_int_param(params, "limit", 5)

    if query == "" do
      json_response(400, %{error: "Missing query parameter 'q'"})
    else
      context = generate_context(query, limit)

      case File.write(Path.expand(path), context) do
        :ok ->
          json_response(200, %{
            status: "ok",
            path: path,
            query: query,
            size: byte_size(context)
          })

        {:error, reason} ->
          json_response(500, %{error: "Failed to write file: #{inspect(reason)}"})
      end
    end
  end

  # Sources

  defp route("GET", "/sources", _params, _body) do
    case CursorDocs.Storage.list_sources() do
      {:ok, sources} ->
        json_response(200, %{sources: format_sources(sources)})

      {:error, reason} ->
        json_response(500, %{error: inspect(reason)})
    end
  end

  defp route("POST", "/sources", _params, body) do
    case Jason.decode(body) do
      {:ok, %{"url" => url} = data} ->
        name = Map.get(data, "name")
        max_pages = Map.get(data, "max_pages", 50)

        opts =
          [name: name, max_pages: max_pages]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        case CursorDocs.Scraper.add(url, opts) do
          {:ok, source} ->
            json_response(201, %{status: "ok", source: format_source(source)})

          {:error, reason} ->
            json_response(400, %{error: inspect(reason)})
        end

      {:ok, _} ->
        json_response(400, %{error: "Missing required field 'url'"})

      {:error, _} ->
        json_response(400, %{error: "Invalid JSON body"})
    end
  end

  defp route("DELETE", "/sources/" <> id, _params, _body) do
    case Integer.parse(id) do
      {source_id, ""} ->
        case CursorDocs.Storage.remove_source(source_id) do
          :ok ->
            json_response(200, %{status: "deleted", id: source_id})

          {:error, reason} ->
            json_response(400, %{error: inspect(reason)})
        end

      _ ->
        json_response(400, %{error: "Invalid source ID"})
    end
  end

  # Background Jobs

  defp route("GET", "/jobs", _params, _body) do
    jobs = CursorDocs.Scraper.Background.list_jobs()
    json_response(200, %{jobs: format_jobs(jobs)})
  end

  defp route("POST", "/jobs", _params, body) do
    case Jason.decode(body) do
      {:ok, %{"url" => url} = data} ->
        name = Map.get(data, "name")
        max_pages = Map.get(data, "max_pages", 100)

        case CursorDocs.Scraper.Background.start_crawl(url, name: name, max_pages: max_pages) do
          {:ok, job_id} ->
            json_response(201, %{status: "queued", job_id: job_id})

          {:error, reason} ->
            json_response(400, %{error: inspect(reason)})
        end

      {:ok, _} ->
        json_response(400, %{error: "Missing required field 'url'"})

      {:error, _} ->
        json_response(400, %{error: "Invalid JSON body"})
    end
  end

  defp route("GET", "/jobs/" <> job_id, _params, _body) do
    case CursorDocs.Scraper.Background.status(job_id) do
      {:ok, job} ->
        json_response(200, format_job(job))

      {:error, :not_found} ->
        json_response(404, %{error: "Job not found"})
    end
  end

  defp route("DELETE", "/jobs/" <> job_id, _params, _body) do
    case CursorDocs.Scraper.Background.cancel(job_id) do
      :ok ->
        json_response(200, %{status: "cancelled", job_id: job_id})

      {:error, reason} ->
        json_response(400, %{error: inspect(reason)})
    end
  end

  # 404 fallback
  defp route(method, path, _params, _body) do
    json_response(404, %{error: "Not found", method: method, path: path})
  end

  # Helpers

  defp generate_context(query, limit) do
    {:ok, results} = CursorDocs.Search.query(query, limit: limit, mode: :auto)

    header = """
    # Documentation Context

    Query: #{query}
    Results: #{length(results)} relevant sections

    ---

    """

    sections =
      Enum.map_join(results, "\n\n---\n\n", fn result ->
        """
        ## #{result.title || result.source_name}

        **Source:** #{result.source_name}
        **URL:** #{result.url}

        #{result.content}
        """
      end)

    header <> sections
  end

  defp format_search_results(results) do
    Enum.map(results, fn r ->
      %{
        id: r.id,
        source_id: r.source_id,
        source_name: r.source_name,
        title: r.title,
        url: r.url,
        content: String.slice(r.content, 0, 500),
        score: r[:score]
      }
    end)
  end

  defp format_sources(sources), do: Enum.map(sources, &format_source/1)

  defp format_source(source) do
    %{
      id: source.id,
      name: source.name,
      url: source.url,
      created_at: source.created_at,
      section_count: source[:section_count] || 0
    }
  end

  defp format_jobs(jobs), do: Enum.map(jobs, &format_job/1)

  defp format_job(job) do
    %{
      id: job.id,
      url: job.url,
      name: job.name,
      status: job.status,
      total_pages: job.total_pages,
      processed_pages: job.processed_pages,
      started_at: job.started_at,
      completed_at: job.completed_at,
      error: job.error
    }
  end

  defp get_int_param(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp json_response(status, data) do
    body = Jason.encode!(data)
    {status, %{"Content-Type" => "application/json"}, body}
  end
end

