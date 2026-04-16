defmodule Mix.Tasks.Skills.Install do
  @shortdoc "Installs skills from project dependencies for detected agents"
  @moduledoc """
  Discovers and installs skills bundled in hex dependencies by symlinking
  them into each detected agent's skills directory.

  By default, auto-detects which agents are present (Claude Code, Windsurf,
  Cursor, etc.) by checking for their dotdirs, and installs to all of them.

      $ mix skills.install
      $ mix skills.install oban
      $ mix skills.install --agent claude
      $ mix skills.install --global
      $ mix skills.install -g
      $ mix skills.install --dry-run
      $ mix skills.install --copy
      $ mix skills.install --force
      $ mix skills.install --yes

  ## Options

    - `--agent` - install for a specific agent only (claude, windsurf, cursor, codex, amp)
    - `-g` / `--global` - install to user-global `~/.<agent>/skills/` instead of project-local
    - `--dry-run` - show what would be installed without making changes
    - `--copy` - copy files instead of creating symlinks
    - `--force` - overwrite conflicting skills
    - `--yes` - skip confirmation prompt
  """

  use Mix.Task

  alias ElixirSkills.{Config, Discovery, Installer}

  @impl Mix.Task
  def run(args) do
    {opts, packages, _} =
      OptionParser.parse(args,
        strict: [
          global: :boolean,
          dry_run: :boolean,
          copy: :boolean,
          force: :boolean,
          yes: :boolean,
          agent: :string
        ],
        aliases: [g: :global]
      )

    agent_opts = parse_agent_opt(opts[:agent])
    global? = opts[:global] || false

    scan_opts =
      if Enum.empty?(packages) do
        []
      else
        [packages: Enum.map(packages, fn pkg ->
          try do
            String.to_existing_atom(pkg)
          rescue
            ArgumentError -> Mix.raise("Unknown package: #{pkg}")
          end
        end)]
      end

    case Discovery.scan(scan_opts) do
      {:ok, []} ->
        Mix.shell().info("No skills found in dependencies.")

      {:ok, skills} ->
        target_dirs = Config.skills_target_dirs(agent_opts ++ [global: global?])

        if Enum.empty?(target_dirs) do
          Mix.shell().info("No agent directories detected. Create a .claude/, .windsurf/, or .cursor/ directory, or pass --agent.")
        else
          Enum.each(target_dirs, fn target_dir ->
            install_for_target(skills, target_dir, opts)
          end)
        end
    end
  end

  defp install_for_target(skills, target_dir, opts) do
    scope_opts = [target_dir: target_dir]

    plan = Installer.plan(skills, scope_opts)
    actionable = Enum.filter(plan, &(&1.action in [:new, :update, :conflict]))
    stale = Installer.stale_entries(scope_opts)

    Mix.shell().info("Target: #{target_dir}")
    print_plan(plan, stale)

    if Enum.empty?(actionable) and Enum.empty?(stale) do
      Mix.shell().info("Everything is up to date.\n")
    else
      if opts[:dry_run] do
        Mix.shell().info("Dry run — no changes made.\n")
      else
        proceed? = opts[:yes] || Mix.shell().yes?("Install #{length(actionable)} skill(s)?")

        if proceed? do
          entries_to_install =
            if opts[:force] do
              Enum.filter(plan, &(&1.action in [:new, :update, :conflict]))
            else
              Enum.filter(plan, &(&1.action in [:new, :update]))
            end

          install_opts = Keyword.merge(scope_opts, force: opts[:force] || false, copy: opts[:copy] || false)
          {:ok, %{installed: installed, skipped: skipped}} = Installer.execute(entries_to_install, install_opts)
          Mix.shell().info("\nInstalled #{length(installed)} skill(s), skipped #{length(skipped)}.")
          Mix.shell().info("Merged skill: #{Path.join(target_dir, Config.router_skill_name())}")

          if not Enum.empty?(stale) do
            if Mix.shell().yes?("Clean #{length(stale)} stale entry/entries?") do
              Installer.clean_stale(scope_opts)
              Mix.shell().info("Cleaned stale entries.")
            end
          end

          Mix.shell().info("")
        else
          Mix.shell().info("Aborted.\n")
        end
      end
    end
  end

  defp parse_agent_opt(nil), do: []

  defp parse_agent_opt(agent_str) do
    agent =
      try do
        String.to_existing_atom(agent_str)
      rescue
        ArgumentError -> Mix.raise("Unknown agent: #{agent_str}. Known agents: #{inspect(Config.known_agents())}")
      end

    if agent in Config.known_agents() do
      [agents: [agent]]
    else
      Mix.raise("Unknown agent: #{agent_str}. Known agents: #{inspect(Config.known_agents())}")
    end
  end

  defp print_plan(plan, stale) do
    Mix.shell().info("")

    Enum.each(plan, fn entry ->
      tag =
        case entry.action do
          :new -> "[NEW]      "
          :update -> "[UPDATE]   "
          :conflict -> "[CONFLICT] "
          :unchanged -> "[OK]       "
          :stale -> "[STALE]    "
        end

      reason = if entry.reason, do: " — #{entry.reason}", else: ""
      Mix.shell().info("  #{tag} #{entry.skill.id}#{reason}")
    end)

    Enum.each(stale, fn entry ->
      Mix.shell().info("  [STALE]     #{entry.library_id} — #{entry.reason}")
    end)

    Mix.shell().info("")
  end
end
