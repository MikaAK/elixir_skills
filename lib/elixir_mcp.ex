defmodule ElixirMcp do
  @moduledoc """
  Standardized skill bundling for Elixir hex packages.

  ElixirMcp enables hex package authors to ship agent skills alongside
  their library code. Skills are agent-agnostic — any MCP-compatible
  agent (Claude Code, Cursor, Windsurf, etc.) can discover and use them.

  ## For library authors

  1. Run `mix skills.init my-skill-name` to scaffold a `skills/` directory at your project root
  2. Edit the generated `SKILL.md` with your skill content
  3. `mix compile` automatically copies `skills/` → `priv/skills/` via a compile alias
  4. Publish to Hex — skills ship automatically via `priv/`

  The `skills/` directory at the project root is the canonical authoring location.
  Contributors see and edit skills there. The `priv/skills/` directory is a
  build artifact generated at compile time.

  ## For consumers

  1. Add `{:elixir_mcp, "~> 0.1.0"}` to your deps
  2. Run `mix skills.list` to see available skills from all deps
  3. Run `mix skills.install` to symlink into detected agent dirs (`.claude/skills/`, `.windsurf/skills/`, etc.)
  4. Run `mix skills.install -g` to install to user-global `~/.<agent>/skills/` instead

  ## MCP server

  Start an MCP server that exposes skills to any agent:

      mix skills.server              # stdio transport
      mix skills.server --http 4242  # HTTP transport

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
  defdelegate plan(skills, opts \\ []), to: Installer

  @doc "Executes an installation plan."
  defdelegate install(plan_entries, opts \\ []), to: Installer, as: :execute

  @doc "Uninstalls managed skills."
  defdelegate uninstall(ids, opts \\ []), to: Installer

  @doc "Returns currently installed skills tracking data."
  defdelegate installed(opts \\ []), to: Installer, as: :read_tracking

  @doc "Starts the MCP server with the given transport (:stdio or {:streamable_http, port: N})."
  defdelegate start_server(transport), to: ElixirMcp.Server, as: :start
end
