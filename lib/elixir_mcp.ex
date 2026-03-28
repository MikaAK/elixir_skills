defmodule ElixirMcp do
  @moduledoc """
  Standardized Claude Code skill bundling for Elixir hex packages.

  ElixirMcp enables hex package authors to ship Claude Code skills alongside
  their library code, and provides Mix tasks for consumers to discover and
  install those skills.

  ## For library authors

  1. Run `mix claude_skills.init my-skill-name` to scaffold `priv/claude_skills/`
  2. Edit the generated `SKILL.md` with your skill content
  3. Publish to Hex — skills ship automatically via `priv/`

  ## For consumers

  1. Add `{:elixir_mcp, "~> 0.1.0"}` to your deps
  2. Run `mix claude_skills.list` to see available skills
  3. Run `mix claude_skills.install` to install them

  ## MCP server

  Start an MCP server that exposes skills to any agent:

      mix claude_skills.server              # stdio (for Claude Code config)
      mix claude_skills.server --http 4242  # HTTP transport

  Or programmatically:

      ElixirMcp.start_server(:stdio)
      ElixirMcp.start_server({:streamable_http, port: 4242})

  ## Hermes MCP integration

  Library authors can also create native Hermes MCP components backed by skills.
  See `ElixirMcp.HermesSkill` and `ElixirMcp.Hermes.Bridge` for details.
  """

  alias ElixirMcp.{Discovery, Installer}

  @doc "Scans all deps for bundled skills."
  defdelegate scan(opts \\ []), to: Discovery

  @doc "Plans installation by diffing discovered skills against installed ones."
  defdelegate plan(skills), to: Installer

  @doc "Executes an installation plan."
  defdelegate install(plan_entries, opts \\ []), to: Installer, as: :execute

  @doc "Uninstalls managed skills."
  defdelegate uninstall(ids), to: Installer

  @doc "Returns currently installed skills tracking data."
  defdelegate installed(), to: Installer, as: :read_tracking

  @doc "Starts the MCP server with the given transport (:stdio or {:streamable_http, port: N})."
  defdelegate start_server(transport), to: ElixirMcp.Server, as: :start
end
