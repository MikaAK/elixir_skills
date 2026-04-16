defmodule Mix.Tasks.Skills.Init do
  @shortdoc "Scaffolds a single SKILL.md in the project's skills/ directory"
  @moduledoc """
  Creates `skills/SKILL.md` in the current project with a frontmatter template.

      $ mix skills.init my-library-id
      $ mix skills.init my-library-id --mcp-type tool

  The `skills/` directory ships with your hex package (copied to `priv/skills/`
  by the compile alias) and is the single source of truth for your library's
  agent guidance.

  ## Options

    - `--mcp-type` — register the skill as an MCP component: tool, resource, prompt
  """

  use Mix.Task

  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [mcp_type: :string])

    case positional do
      [id] ->
        if Regex.match?(@valid_id_pattern, id) do
          create_skill(id, opts)
        else
          Mix.shell().error("Invalid library id '#{id}': must match [a-z0-9][a-z0-9-]*")
        end

      [] -> Mix.shell().error("Usage: mix skills.init <library-id>")
      _ -> Mix.shell().error("Expected exactly one library id argument.")
    end
  end

  defp create_skill(id, opts) do
    skill_md = Path.join("skills", "SKILL.md")

    if File.exists?(skill_md) do
      Mix.shell().info("#{skill_md} already exists, skipping.")
    else
      File.mkdir_p!("skills")
      File.write!(skill_md, template(id, opts))
      Mix.shell().info("Created #{skill_md}. Edit it to add your skill content.")
    end
  end

  defp template(id, opts) do
    mcp_line =
      case opts[:mcp_type] do
        nil -> ""
        type -> "mcp: #{type}:#{id}\n"
      end

    """
    ---
    name: #{id}
    description: Use when working with #{id} — TODO
    #{mcp_line}---

    # #{id |> String.replace("-", " ") |> String.capitalize()}

    TODO: Add library guidance here. Optional deep-dive references belong in `skills/references/<topic>.md`.
    """
  end
end
