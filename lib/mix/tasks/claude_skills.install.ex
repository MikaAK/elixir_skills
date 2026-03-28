defmodule Mix.Tasks.ClaudeSkills.Install do
  @shortdoc "Installs Claude Code skills from project dependencies"
  @moduledoc """
  Discovers and installs Claude Code skills bundled in hex dependencies
  by symlinking them into `~/.claude/skills/`.

      $ mix claude_skills.install
      $ mix claude_skills.install oban phoenix
      $ mix claude_skills.install --dry-run
      $ mix claude_skills.install --copy
      $ mix claude_skills.install --force
      $ mix claude_skills.install --yes

  ## Options

    - `--dry-run` - show what would be installed without making changes
    - `--copy` - copy files instead of creating symlinks
    - `--force` - overwrite conflicting skills
    - `--yes` - skip confirmation prompt
  """

  use Mix.Task

  alias ElixirMcp.{Discovery, Installer}

  @impl Mix.Task
  def run(args) do
    {opts, packages, _} =
      OptionParser.parse(args, strict: [
        dry_run: :boolean,
        copy: :boolean,
        force: :boolean,
        yes: :boolean
      ])

    scan_opts =
      if Enum.empty?(packages) do
        []
      else
        [packages: Enum.map(packages, &String.to_atom/1)]
      end

    case Discovery.scan(scan_opts) do
      {:ok, []} ->
        Mix.shell().info("No Claude Code skills found in dependencies.")

      {:ok, skills} ->
        plan = Installer.plan(skills)
        actionable = Enum.filter(plan, &(&1.action in [:new, :update, :conflict]))
        stale = Installer.stale_entries()

        print_plan(plan, stale)

        if Enum.empty?(actionable) and Enum.empty?(stale) do
          Mix.shell().info("Everything is up to date.")
        else
          if opts[:dry_run] do
            Mix.shell().info("Dry run — no changes made.")
          else
            proceed? = opts[:yes] || Mix.shell().yes?("Install #{length(actionable)} skill(s)?")

            if proceed? do
              entries_to_install =
                if opts[:force] do
                  Enum.filter(plan, &(&1.action in [:new, :update, :conflict]))
                else
                  Enum.filter(plan, &(&1.action in [:new, :update]))
                end

              {:ok, %{installed: installed, skipped: skipped}} =
                Installer.execute(entries_to_install, force: opts[:force] || false, copy: opts[:copy] || false)

              Mix.shell().info("\nInstalled #{length(installed)} skill(s), skipped #{length(skipped)}.")

              if not Enum.empty?(stale) do
                if Mix.shell().yes?("Clean #{length(stale)} stale entry/entries?") do
                  Installer.clean_stale()
                  Mix.shell().info("Cleaned stale entries.")
                end
              end
            else
              Mix.shell().info("Aborted.")
            end
          end
        end
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
      Mix.shell().info("  #{tag} #{entry.skill.namespaced_id}#{reason}")
    end)

    Enum.each(stale, fn entry ->
      Mix.shell().info("  [STALE]     #{entry.namespaced_id} — #{entry.reason}")
    end)

    Mix.shell().info("")
  end
end
