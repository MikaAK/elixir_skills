defmodule ElixirSkills.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_skills,
      version: "0.1.0",
      start_permanent: Mix.env() === :prod,
      aliases: aliases(),
      deps: deps(),
      description: "Standardized skill bundling and MCP server for Elixir hex packages",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirSkills.Application, []}
    ]
  end

  defp package do
    [
      maintainers: ["Mika Kalathil"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/MikaAK/elixir_skills"},
      files: ~w(mix.exs README.md lib priv)
    ]
  end

  defp aliases, do: []

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:hermes_mcp, "~> 0.14.1"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
