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
      extra_applications: [:logger],
      mod: {CursorDocs.Application, []}
    ]
  end

  defp deps do
    [
      # Web scraping
      {:playwright, "~> 1.0"},
      {:floki, "~> 0.36"},

      # Database
      {:surrealdb, "~> 0.2"},

      # HTTP/Networking
      {:req, "~> 0.5"},
      {:mint, "~> 1.6"},

      # JSON handling
      {:jason, "~> 1.4"},

      # CLI
      {:optimus, "~> 0.5"},

      # MCP Protocol
      {:plug_cowboy, "~> 2.7"},

      # Utilities
      {:nimble_pool, "~> 1.1"},
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},

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
      "cursor_docs.server": &start_server/1,
      "cursor_docs.mcp": &start_mcp/1
    ]
  end

  defp setup_database(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.Storage.Surreal.setup()
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

  defp start_server(_args) do
    Mix.Task.run("app.start", [])
    CursorDocs.Server.start()
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
