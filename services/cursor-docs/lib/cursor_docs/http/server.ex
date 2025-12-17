defmodule CursorDocs.HTTP.Server do
  @moduledoc """
  Simple HTTP API server for CursorDocs.

  Uses Erlang's :gen_tcp for a lightweight HTTP server.
  No external dependencies required.

  ## Endpoints

  ### Search & Context

  - `GET /api/search?q=query` - Search indexed documentation
  - `GET /api/context?q=query` - Get formatted context for AI injection
  - `GET /api/context/file?q=query&path=/tmp/context.md` - Write context to file

  ### Sources

  - `GET /api/sources` - List all indexed sources
  - `POST /api/sources` - Add new source
  - `DELETE /api/sources/:id` - Remove a source

  ### Status

  - `GET /api/status` - Server and index status
  - `GET /api/health` - Health check

  ### Background Jobs

  - `GET /api/jobs` - List background crawl jobs
  - `POST /api/jobs` - Start background crawl
  - `GET /api/jobs/:id` - Get job status
  - `DELETE /api/jobs/:id` - Cancel job

  ## Usage

      # Start server
      mix cursor_docs.server

      # Or with custom port
      mix cursor_docs.server 8080
  """

  use GenServer
  require Logger

  @default_port 4242

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    port = opts[:port] || @default_port

    # Start listening
    case :gen_tcp.listen(port, [
           :binary,
           packet: :http_bin,
           active: false,
           reuseaddr: true
         ]) do
      {:ok, listen_socket} ->
        Logger.info("CursorDocs HTTP server listening on port #{port}")

        # Start acceptor
        {:ok, _pid} = Task.start_link(fn -> accept_loop(listen_socket) end)

        {:ok, %{socket: listen_socket, port: port}}

      {:error, reason} ->
        Logger.error("Failed to start HTTP server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state[:socket] do
      :gen_tcp.close(state.socket)
    end

    :ok
  end

  # Connection handling

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Handle in separate process
        Task.start(fn -> handle_connection(client_socket) end)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        accept_loop(listen_socket)
    end
  end

  defp handle_connection(socket) do
    case read_request(socket) do
      {:ok, request} ->
        response = CursorDocs.HTTP.Router.handle(request)
        send_response(socket, response)

      {:error, reason} ->
        Logger.debug("Request error: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  defp read_request(socket) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, {:http_request, method, {:abs_path, path}, _version}} ->
        {path, query} = parse_path(path)
        headers = read_headers(socket, [])
        body = read_body(socket, headers)

        {:ok,
         %{
           method: method,
           path: path,
           query: query,
           headers: headers,
           body: body
         }}

      {:ok, {:http_error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_path(path) do
    path = to_string(path)

    case String.split(path, "?", parts: 2) do
      [p, q] -> {p, parse_query_string(q)}
      [p] -> {p, %{}}
    end
  end

  defp parse_query_string(qs) do
    qs
    |> String.split("&")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> {URI.decode(key), URI.decode(value)}
        [key] -> {URI.decode(key), ""}
      end
    end)
    |> Map.new()
  end

  defp read_headers(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, {:http_header, _, key, _, value}} ->
        key = key |> to_string() |> String.downcase()
        read_headers(socket, [{key, to_string(value)} | acc])

      {:ok, :http_eoh} ->
        Map.new(acc)

      _ ->
        Map.new(acc)
    end
  end

  defp read_body(socket, headers) do
    content_length =
      case Map.get(headers, "content-length") do
        nil -> 0
        len -> String.to_integer(len)
      end

    if content_length > 0 do
      # Switch to raw mode to read body
      :inet.setopts(socket, packet: :raw)

      case :gen_tcp.recv(socket, content_length, 5000) do
        {:ok, body} -> body
        _ -> ""
      end
    else
      ""
    end
  end

  defp send_response(socket, {status, headers, body}) do
    status_line = "HTTP/1.1 #{status} #{status_text(status)}\r\n"

    headers_text =
      headers
      |> Map.put("Content-Length", byte_size(body))
      |> Map.put("Connection", "close")
      |> Enum.map(fn {k, v} -> "#{k}: #{v}\r\n" end)
      |> Enum.join()

    response = status_line <> headers_text <> "\r\n" <> body
    :gen_tcp.send(socket, response)
  end

  defp status_text(200), do: "OK"
  defp status_text(201), do: "Created"
  defp status_text(400), do: "Bad Request"
  defp status_text(404), do: "Not Found"
  defp status_text(500), do: "Internal Server Error"
  defp status_text(_), do: "Unknown"
end
