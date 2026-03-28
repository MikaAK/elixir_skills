defmodule Mix.Tasks.ClaudeSkills.List do
  @shortdoc "Lists Claude Code skills available from project dependencies"
  @moduledoc """
  Lists all Claude Code skills discoverable in the project's hex dependencies.

      $ mix claude_skills.list
      $ mix claude_skills.list --installed
      $ mix claude_skills.list --package oban

  ## Options

    - `--installed` - show only skills currently installed by elixir_mcp
    - `--package` - filter by source package name
  """

  use Mix.Task

  alias ElixirMcp.{Discovery, Installer}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [installed: :boolean, package: :string])

    if opts[:installed] do
      list_installed()
    else
      list_available(opts[:package])
    end
  end

  defp list_available(package_filter) do
    scan_opts =
      if package_filter do
        [packages: [String.to_atom(package_filter)]]
      else
        []
      end

    case Discovery.scan(scan_opts) do
      {:ok, []} ->
        Mix.shell().info("No Claude Code skills found in dependencies.")

      {:ok, skills} ->
        tracking = Installer.read_tracking()

        Mix.shell().info("\nAvailable Claude Code skills:\n")
        Mix.shell().info(pad("PACKAGE", 20) <> pad("SKILL ID", 30) <> pad("SOURCE", 10) <> pad("STATUS", 12) <> "DESCRIPTION")
        Mix.shell().info(String.duplicate("-", 100))

        Enum.each(skills, fn skill ->
          status =
            cond do
              Map.has_key?(tracking, skill.namespaced_id) -> "[installed]"
              true -> "[available]"
            end

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

  defp list_installed do
    tracking = Installer.read_tracking()

    if Enum.empty?(tracking) do
      Mix.shell().info("No skills installed by elixir_mcp.")
    else
      Mix.shell().info("\nInstalled Claude Code skills:\n")
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
  end

  defp pad(str, width) do
    String.pad_trailing(str, width)
  end

  defp truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end
end
