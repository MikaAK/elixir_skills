defmodule Mix.Tasks.Skills.Uninstall do
  @shortdoc "Uninstalls skills managed by elixir_skills"
  @moduledoc """
  Removes skills installed by `mix skills.install`.

      $ mix skills.uninstall              # Remove all managed skills
      $ mix skills.uninstall fake-dep     # Remove specific library
      $ mix skills.uninstall --stale       # Remove only stale/broken entries
      $ mix skills.uninstall --agent claude
      $ mix skills.uninstall -g            # Remove from global ~/.<agent>/skills/
  """

  use Mix.Task

  alias ElixirSkills.{Config, Installer}

  @impl Mix.Task
  def run(args) do
    {opts, ids, _} =
      OptionParser.parse(args,
        strict: [stale: :boolean, global: :boolean, agent: :string],
        aliases: [g: :global]
      )

    agent_opts = parse_agent_opt(opts[:agent])
    global? = opts[:global] || false
    target_dirs = Config.skills_target_dirs(agent_opts ++ [global: global?])

    if Enum.empty?(target_dirs) do
      Mix.shell().info("No agent directories detected.")
    else
      Enum.each(target_dirs, fn target_dir ->
        uninstall_for_target(target_dir, ids, opts)
      end)
    end
  end

  defp uninstall_for_target(target_dir, ids, opts) do
    scope_opts = [target_dir: target_dir]
    Mix.shell().info("Target: #{target_dir}")

    cond do
      opts[:stale] ->
        case Installer.clean_stale(scope_opts) do
          {:ok, []} -> Mix.shell().info("No stale entries found.")
          {:ok, removed} -> Mix.shell().info("Removed #{length(removed)} stale entry/entries: #{Enum.join(removed, ", ")}")
        end

      Enum.empty?(ids) ->
        tracking = Installer.read_tracking(scope_opts)

        if Enum.empty?(tracking) do
          Mix.shell().info("No skills installed by elixir_skills.")
        else
          count = map_size(tracking)

          if Mix.shell().yes?("Remove all #{count} managed skill(s)?") do
            {:ok, removed} = Installer.uninstall(:all, scope_opts)
            Mix.shell().info("Removed #{length(removed)} skill(s).")
          else
            Mix.shell().info("Aborted.")
          end
        end

      true ->
        {:ok, removed} = Installer.uninstall(ids, scope_opts)

        if Enum.empty?(removed) do
          Mix.shell().info("No matching managed skills found for: #{Enum.join(ids, ", ")}")
        else
          Mix.shell().info("Removed: #{Enum.join(removed, ", ")}")
        end
    end

    Mix.shell().info("")
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
end
