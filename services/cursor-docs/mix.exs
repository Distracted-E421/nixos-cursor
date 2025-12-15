defmodule CursorDocs.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Distracted-E421/nixos-cursor"

  def project do
    [
      app: :cursor_docs,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "CursorDocs",
      source_url: @source_url,
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {CursorDocs.Application, []}
    ]
  end

  defp deps do
    [
      # SQLite - for local storage AND reading Cursor's databases
      {:exqlite, "~> 0.23"},

      # HTTP client
      {:req, "~> 0.5"},
      {:finch, "~> 0.18"},

      # HTML parsing
      {:floki, "~> 0.36"},

      # Browser automation (ChromeDriver-based)
      {:wallaby, "~> 0.30", runtime: false},

      # JSON
      {:jason, "~> 1.4"},

      # CLI
      {:optimus, "~> 0.5"},

      # Process pooling
      {:nimble_pool, "~> 1.1"},

      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},

      # File watching (for Cursor DB changes)
      {:file_system, "~> 1.0"},

      # Development
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cursor_docs.setup"],
      "cursor_docs.setup": &setup_database/1,
      "cursor_docs.add": &add_docs/1,
      "cursor_docs.search": &search_docs/1,
      "cursor_docs.list": &list_docs/1,
      "cursor_docs.status": &status/1,
      "cursor_docs.sync": &sync_from_cursor/1,
      "cursor_docs.import": &import_cursor/1,
      "cursor_docs.cursor": &cursor_docs_list/1,
      "cursor_docs.server": &start_server/1,
      "cursor_docs.mcp": &start_mcp/1
    ]
  end

  defp setup_database(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.Storage.SQLite.setup()
  end

  defp add_docs(args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.add(args)
  end

  defp search_docs(args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.search(args)
  end

  defp list_docs(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.list()
  end

  defp status(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.status()
  end

  defp sync_from_cursor(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CursorIntegration.sync_docs()
  end

  defp import_cursor(args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.import_cursor(args)
  end

  defp cursor_docs_list(args) do
    Mix.Task.run("app.start", [])
    CursorDocs.CLI.cursor_docs(args)
  end

  defp start_server(_args) do
    Mix.Task.run("app.start", [])
    # Keep running
    Process.sleep(:infinity)
  end

  defp start_mcp(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.MCP.Server.start_stdio()
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
