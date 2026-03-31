defmodule Mix.Tasks.Skills.List do
  @shortdoc "Lists skills available from project dependencies"
  @moduledoc """
  Lists all skills discoverable in the project's hex dependencies.

      $ mix skills.list
      $ mix skills.list --installed
      $ mix skills.list --installed -g
      $ mix skills.list --package oban
      $ mix skills.list --agent claude

  ## Options

    - `--installed` - show only skills currently installed by elixir_mcp
    - `--package` - filter by source package name
    - `--agent` - check a specific agent's skills dir (default: auto-detect)
    - `-g` / `--global` - check user-global `~/.<agent>/skills/` instead of project-local
  """

  use Mix.Task

  alias ElixirMcp.{Config, Discovery, Installer}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [installed: :boolean, package: :string, global: :boolean, agent: :string],
        aliases: [g: :global]
      )

    agent_opts = parse_agent_opt(opts[:agent])
    scope_opts = agent_opts ++ [global: opts[:global] || false]

    if opts[:installed] do
      list_installed(scope_opts)
    else
      list_available(opts[:package], scope_opts)
    end
  end

  defp list_available(package_filter, scope_opts) do
    scan_opts =
      if package_filter do
        pkg =
          try do
            String.to_existing_atom(package_filter)
          rescue
            ArgumentError -> Mix.raise("Unknown package: #{package_filter}")
          end

        [packages: [pkg]]
      else
        []
      end

    case Discovery.scan(scan_opts) do
      {:ok, []} ->
        Mix.shell().info("No skills found in dependencies.")

      {:ok, skills} ->
        tracking = Installer.read_tracking(scope_opts)

        Mix.shell().info("\nAvailable skills:\n")
        Mix.shell().info(pad("PACKAGE", 20) <> pad("SKILL ID", 30) <> pad("SOURCE", 10) <> pad("STATUS", 12) <> "DESCRIPTION")
        Mix.shell().info(String.duplicate("-", 100))

        Enum.each(skills, fn skill ->
          status = if Map.has_key?(tracking, skill.namespaced_id), do: "[installed]", else: "[available]"
          source = to_string(skill.source || :library)
          desc = truncate(skill.description || "(no description)", 35)

          Mix.shell().info(
            pad(to_string(skill.package), 20) <>
              pad(skill.namespaced_id, 30) <>
              pad(source, 10) <>
              pad(status, 12) <>
              desc
          )
        end)

        Mix.shell().info("")
    end
  end

  defp list_installed(scope_opts) do
    target_dirs = Config.skills_target_dirs(scope_opts)

    if Enum.empty?(target_dirs) do
      Mix.shell().info("No agent directories detected.")
    else
      Enum.each(target_dirs, fn target_dir ->
        dir_opts = [target_dir: target_dir]
        tracking = Installer.read_tracking(dir_opts)

        if Enum.empty?(tracking) do
          Mix.shell().info("No skills installed in #{target_dir}.")
        else
          Mix.shell().info("\nInstalled skills (#{target_dir}):\n")
          Mix.shell().info(pad("SKILL ID", 30) <> pad("PACKAGE", 15) <> pad("VERSION", 12) <> "INSTALLED AT")
          Mix.shell().info(String.duplicate("-", 80))

          Enum.each(tracking, fn {id, meta} ->
            Mix.shell().info(
              pad(id, 30) <>
                pad(meta["package"] || "?", 15) <>
                pad(meta["package_version"] || "?", 12) <>
                (meta["installed_at"] || "?")
            )
          end)

          Mix.shell().info("")
        end
      end)
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

  defp pad(str, width), do: String.pad_trailing(str, width)

  defp truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end
end
