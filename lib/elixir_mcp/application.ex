defmodule ElixirMcp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [Hermes.Server.Registry] ++
      if transport = Application.get_env(:elixir_mcp, :transport) do
        [{Hermes.Server.Supervisor, {ElixirMcp.Server, transport: transport}}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ElixirMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
