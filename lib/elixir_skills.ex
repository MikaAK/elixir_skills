defmodule ElixirSkills do
  @moduledoc """
  Standardized skill bundling for Elixir hex packages.

  `elixir_skills` lets hex package authors ship one agent skill per library
  and installs them as a single merged `elixir-skills` skill per agent. Each
  library's content appears under `references/<library-id>/` inside that
  merged skill; the top-level `SKILL.md` is a generated router that points
  the agent to the right library for the current task.

  ## For library authors

  1. Run `mix skills.init my-library-id` to scaffold `skills/SKILL.md` at
     your project root.
  2. Optional: add deeper guidance in `skills/references/<topic>.md`.
  3. `mix compile` copies `skills/` → `priv/skills/` so the content ships
     with your hex package.

  ## For consumers

  1. Add `{:elixir_skills, "~> 0.2.0"}` to your deps.
  2. `mix skills.list` shows every discovered library.
  3. `mix skills.install` creates
     `.claude/skills/elixir-skills/` (mirrored across any detected agent
     dotdirs) with a symlink per library and a generated router SKILL.md.
  4. `mix skills.install -g` installs into `~/.<agent>/skills/` instead.

  ## MCP server

      mix skills.server              # stdio
      mix skills.server --http 4242  # streamable HTTP
  """

  alias ElixirSkills.{Discovery, Installer}

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
  defdelegate start_server(transport), to: ElixirSkills.Server, as: :start
end
