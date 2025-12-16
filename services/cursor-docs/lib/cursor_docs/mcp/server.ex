defmodule CursorDocs.MCP.Server do
  @moduledoc """
  Model Context Protocol (MCP) server for CursorDocs.

  Provides MCP tools for Cursor IDE integration:
  - `cursor_docs_add` - Add documentation for indexing
  - `cursor_docs_search` - Search indexed documentation
  - `cursor_docs_list` - List indexed sources
  - `cursor_docs_status` - Check scraping status

  ## Usage

  Add to your Cursor MCP configuration:

      {
        "mcpServers": {
          "cursor-docs": {
            "command": "mix",
            "args": ["cursor_docs.mcp"],
            "cwd": "/path/to/cursor-docs"
          }
        }
      }

  """

  require Logger

  @tools [
    %{
      name: "cursor_docs_add",
      description: "Add a documentation URL to be indexed locally. Reliably indexes documentation that Cursor's built-in @docs fails to index.",
      inputSchema: %{
        type: "object",
        properties: %{
          url: %{type: "string", description: "Documentation URL to index"},
          name: %{type: "string", description: "Display name for the docs (optional)"},
          max_pages: %{type: "integer", description: "Maximum pages to crawl (default: 100)"}
        },
        required: ["url"]
      }
    },
    %{
      name: "cursor_docs_search",
      description: "Search locally indexed documentation. Returns relevant chunks with source citations.",
      inputSchema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "Search query"},
          limit: %{type: "integer", description: "Max results (default: 5)"},
          sources: %{type: "array", items: %{type: "string"}, description: "Filter by source names"}
        },
        required: ["query"]
      }
    },
    %{
      name: "cursor_docs_list",
      description: "List all locally indexed documentation sources with their status and page counts.",
      inputSchema: %{
        type: "object",
        properties: %{}
      }
    },
    %{
      name: "cursor_docs_status",
      description: "Check the status of documentation scraping jobs.",
      inputSchema: %{
        type: "object",
        properties: %{
          source: %{type: "string", description: "Filter by source name (optional)"}
        }
      }
    },
    %{
      name: "cursor_docs_remove",
      description: "Remove a documentation source and all its indexed content.",
      inputSchema: %{
        type: "object",
        properties: %{
          source_id: %{type: "string", description: "Source ID or name to remove"}
        },
        required: ["source_id"]
      }
    }
  ]

  @doc """
  Start the MCP server using stdio transport.
  """
  def start_stdio do
    Logger.info("Starting CursorDocs MCP server (stdio)")

    # Initialize the server
    send_response(%{
      jsonrpc: "2.0",
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{}
        },
        serverInfo: %{
          name: "cursor-docs",
          version: "0.1.0"
        }
      }
    })

    # Enter the main loop
    stdio_loop()
  end

  @doc """
  Get the list of available tools.
  """
  def tools, do: @tools

  # Main stdio loop
  defp stdio_loop do
    case IO.gets("") do
      :eof ->
        Logger.info("MCP server received EOF, shutting down")
        :ok

      {:error, reason} ->
        Logger.error("MCP server IO error: #{inspect(reason)}")
        :error

      line when is_binary(line) ->
        handle_line(String.trim(line))
        stdio_loop()
    end
  end

  defp handle_line(""), do: :ok
  defp handle_line(line) do
    case Jason.decode(line) do
      {:ok, request} ->
        response = handle_request(request)
        send_response(response)

      {:error, reason} ->
        Logger.warning("Invalid JSON: #{inspect(reason)}")
        send_error(-32700, "Parse error", nil)
    end
  end

  defp handle_request(%{"method" => "initialize", "id" => id}) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{}
        },
        serverInfo: %{
          name: "cursor-docs",
          version: "0.1.0"
        }
      }
    }
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        tools: @tools
      }
    }
  end

  defp handle_request(%{"method" => "tools/call", "id" => id, "params" => params}) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}

    result = call_tool(tool_name, arguments)

    case result do
      {:ok, content} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            content: [%{type: "text", text: content}]
          }
        }

      {:error, message} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            content: [%{type: "text", text: "Error: #{message}"}],
            isError: true
          }
        }
    end
  end

  defp handle_request(%{"method" => method, "id" => id}) do
    %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: -32601,
        message: "Method not found: #{method}"
      }
    }
  end

  defp handle_request(%{"method" => _method}) do
    # Notification, no response needed
    nil
  end

  # Tool implementations

  defp call_tool("cursor_docs_add", %{"url" => url} = args) do
    opts = [
      name: args["name"],
      max_pages: args["max_pages"] || 100
    ] |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case CursorDocs.add(url, opts) do
      {:ok, source} ->
        {:ok, """
        ✅ Documentation queued for indexing

        **Source:** #{source[:name] || url}
        **URL:** #{url}
        **Status:** #{source[:status]}
        **Max Pages:** #{opts[:max_pages] || 100}

        Use `cursor_docs_status` to check progress.
        """}

      {:error, reason} ->
        {:error, "Failed to add documentation: #{inspect(reason)}"}
    end
  end

  defp call_tool("cursor_docs_search", %{"query" => query} = args) do
    opts = [
      limit: args["limit"] || 5,
      sources: args["sources"] || []
    ]

    case CursorDocs.search(query, opts) do
      {:ok, chunks} when chunks == [] ->
        {:ok, "No results found for: #{query}"}

      {:ok, chunks} ->
        results = Enum.map_join(chunks, "\n\n---\n\n", fn chunk ->
          """
          ### #{chunk[:title]}
          **Source:** #{chunk[:url]}

          #{chunk[:content]}
          """
        end)

        {:ok, "Found #{length(chunks)} results for \"#{query}\":\n\n#{results}"}

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  defp call_tool("cursor_docs_list", _args) do
    case CursorDocs.list() do
      {:ok, sources} when sources == [] ->
        {:ok, """
        No documentation indexed yet.

        Add some with: `cursor_docs_add https://docs.example.com/`
        """}

      {:ok, sources} ->
        table = Enum.map_join(sources, "\n", fn source ->
          status_icon = case source[:status] do
            "indexed" -> "✅"
            "indexing" -> "⏳"
            "failed" -> "❌"
            _ -> "⏸️"
          end

          "#{status_icon} **#{source[:name]}** - #{source[:pages_count]} pages | #{source[:url]}"
        end)

        {:ok, "## Indexed Documentation\n\n#{table}"}

      {:error, reason} ->
        {:error, "Failed to list sources: #{inspect(reason)}"}
    end
  end

  defp call_tool("cursor_docs_status", args) do
    opts = if args["source"], do: [source: args["source"]], else: []

    case CursorDocs.status(opts) do
      {:ok, jobs} when jobs == [] ->
        {:ok, "No active scraping jobs."}

      {:ok, jobs} ->
        status = Enum.map_join(jobs, "\n", fn job ->
          "- **#{job[:source]}**: #{job[:status]} (#{job[:pages]} pages, #{job[:queued]} queued)"
        end)

        {:ok, "## Scraping Status\n\n#{status}"}

      {:error, reason} ->
        {:error, "Failed to get status: #{inspect(reason)}"}
    end
  end

  defp call_tool("cursor_docs_remove", %{"source_id" => source_id}) do
    case CursorDocs.remove(source_id) do
      :ok ->
        {:ok, "✅ Removed documentation source: #{source_id}"}

      {:error, reason} ->
        {:error, "Failed to remove: #{inspect(reason)}"}
    end
  end

  defp call_tool(tool_name, _args) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  # Response helpers

  defp send_response(nil), do: :ok
  defp send_response(response) do
    json = Jason.encode!(response)
    IO.puts(json)
  end

  defp send_error(code, message, id) do
    send_response(%{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: code,
        message: message
      }
    })
  end
end
