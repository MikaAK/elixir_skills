defmodule Mix.Tasks.ClaudeSkills.Uninstall do
  @shortdoc "Uninstalls Claude Code skills managed by elixir_mcp"
  @moduledoc """
  Removes skills installed by `mix claude_skills.install`.

      $ mix claude_skills.uninstall              # Remove all managed skills
      $ mix claude_skills.uninstall oban--workers # Remove specific skill
      $ mix claude_skills.uninstall --stale       # Remove only stale/broken entries
  """

  use Mix.Task

  alias ElixirMcp.Installer

  @impl Mix.Task
  def run(args) do
    {opts, ids, _} = OptionParser.parse(args, strict: [stale: :boolean])

    cond do
      opts[:stale] ->
        case Installer.clean_stale() do
          {:ok, []} -> Mix.shell().info("No stale entries found.")
          {:ok, removed} -> Mix.shell().info("Removed #{length(removed)} stale entry/entries: #{Enum.join(removed, ", ")}")
        end

      Enum.empty?(ids) ->
        tracking = Installer.read_tracking()

        if Enum.empty?(tracking) do
          Mix.shell().info("No skills installed by elixir_mcp.")
        else
          count = map_size(tracking)

          if Mix.shell().yes?("Remove all #{count} managed skill(s)?") do
            {:ok, removed} = Installer.uninstall(:all)
            Mix.shell().info("Removed #{length(removed)} skill(s).")
          else
            Mix.shell().info("Aborted.")
          end
        end

      true ->
        {:ok, removed} = Installer.uninstall(ids)

        if Enum.empty?(removed) do
          Mix.shell().info("No matching managed skills found for: #{Enum.join(ids, ", ")}")
        else
          Mix.shell().info("Removed: #{Enum.join(removed, ", ")}")
        end
    end
  end
end
