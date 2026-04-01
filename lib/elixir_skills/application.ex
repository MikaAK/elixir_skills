defmodule ElixirSkills.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [Hermes.Server.Registry] ++
      if transport = Application.get_env(:elixir_skills, :transport) do
        [{Hermes.Server.Supervisor, {ElixirSkills.Server, transport: transport}}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ElixirSkills.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
