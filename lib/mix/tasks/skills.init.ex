defmodule Mix.Tasks.Skills.Init do
  @shortdoc "Scaffolds a skill in the current project's skills/ directory"
  @moduledoc """
  Creates the `skills/` directory structure for a new skill at the project root.

      $ mix skills.init my-skill-name
      $ mix skills.init my-skill-name --mcp-type tool

  This creates:
    - `skills/my-skill-name/SKILL.md` with a frontmatter template

  The `skills/` directory is the canonical authoring location — contributors
  see and edit skills here. Running `mix compile` automatically copies them
  to `priv/skills/` for runtime availability via a compile alias.

  ## Options

    - `--mcp-type` - register as an MCP component: tool, resource, or prompt
  """

  use Mix.Task

  alias ElixirSkills.Config

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [mcp_type: :string])

    case positional do
      [skill_id] ->
        if Regex.match?(Config.valid_id_pattern(), skill_id) do
          create_skill(skill_id, opts)
        else
          Mix.shell().error("Invalid skill ID '#{skill_id}': must match [a-z0-9][a-z0-9-]*")
        end

      [] ->
        Mix.shell().error("Usage: mix skills.init <skill-id>")

      _ ->
        Mix.shell().error("Expected exactly one skill ID argument.")
    end
  end

  defp create_skill(skill_id, opts) do
    base_dir = Config.skills_dir_name()
    skill_dir = Path.join(base_dir, skill_id)
    skill_md_path = Path.join(skill_dir, "SKILL.md")

    File.mkdir_p!(skill_dir)
    write_skill_md(skill_md_path, skill_id, opts)

    Mix.shell().info("Created skill scaffold:")
    Mix.shell().info("  #{skill_md_path}")
    Mix.shell().info("\nEdit #{skill_md_path} to add your skill content.")
    Mix.shell().info("Run `mix compile` to copy skills to priv/ for runtime availability.")
  end

  defp write_skill_md(path, skill_id, opts) do
    if File.exists?(path) do
      Mix.shell().info("#{path} already exists, skipping.")
    else
      app_name = Mix.Project.config()[:app] |> to_string()

      mcp_line =
        case opts[:mcp_type] do
          nil -> ""
          type -> "mcp: #{type}:#{skill_id}\n"
        end

      content = """
      ---
      name: #{app_name}--#{skill_id}
      description: Use when working with #{app_name} for TODO
      #{mcp_line}---

      # #{skill_id |> String.replace("-", " ") |> String.capitalize()}

      TODO: Add skill content here.
      """

      File.write!(path, content)
    end
  end
end
