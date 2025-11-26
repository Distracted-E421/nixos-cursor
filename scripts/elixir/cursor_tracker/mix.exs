defmodule CursorTracker.MixProject do
  use Mix.Project

  def project do
    [
      app: :cursor_tracker,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),

      # Documentation
      name: "CursorTracker",
      description: "Git-based tracking for Cursor user data with diff, blame, and rollback",
      source_url: "https://github.com/Distracted-E421/nixos-cursor"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CursorTracker.Application, []}
    ]
  end

  defp deps do
    [
      # File watching
      {:file_system, "~> 1.0"},

      # JSON handling
      {:jason, "~> 1.4"},

      # CLI
      {:optimus, "~> 0.5"},

      # Development
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      cursor_tracker: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
