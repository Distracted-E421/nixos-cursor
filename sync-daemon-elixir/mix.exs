defmodule CursorSync.MixProject do
  use Mix.Project

  def project do
    [
      app: :cursor_sync,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),

      # Docs
      name: "Cursor Sync Daemon",
      description: "Elixir-based sync daemon for Cursor IDE data pipeline control",
      source_url: "https://github.com/Distracted-E421/nixos-cursor"
    ]
  end

  def application do
    [
      mod: {CursorSync.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      # SQLite for reading Cursor's databases
      {:exqlite, "~> 0.23"},
      
      # File system watching
      {:file_system, "~> 1.0"},
      
      # JSON parsing (for Cursor's JSON blobs)
      {:jason, "~> 1.4"},
      
      # Configuration management
      {:toml, "~> 0.7"},
      
      # Better DateTime handling
      {:timex, "~> 3.7"},
      
      # Telemetry for metrics/monitoring
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      
      # Development tools
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      cursor_sync: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
