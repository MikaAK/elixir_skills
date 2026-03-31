defmodule Mix.Tasks.Skills.Server do
  @shortdoc "Starts the MCP server for skill discovery and installation"
  @moduledoc """
  Starts an MCP server that exposes skills from hex dependencies to any MCP client.

      $ mix skills.server              # stdio transport (default)
      $ mix skills.server --http 4242  # HTTP transport on port 4242

  ## Claude Code integration

  Add to your Claude Code MCP config:

      {
        "mcpServers": {
          "elixir-skills": {
            "command": "mix",
            "args": ["skills.server"],
            "cwd": "/path/to/your/project"
          }
        }
      }
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [http: :integer])

    transport =
      case opts[:http] do
        nil -> :stdio
        port -> {:streamable_http, port: port}
      end

    {:ok, _pid} = ElixirMcp.Server.start(transport)

    case transport do
      :stdio ->
        Process.sleep(:infinity)

      {:streamable_http, port: port} ->
        Mix.shell().info("MCP server running on http://localhost:#{port}")
        Process.sleep(:infinity)
    end
  end
end
