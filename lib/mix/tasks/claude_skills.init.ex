defmodule Mix.Tasks.ClaudeSkills.Init do
  @shortdoc "Scaffolds a Claude Code skill in the current project"
  @moduledoc """
  Creates the `priv/claude_skills/` directory structure for a new skill.

      $ mix claude_skills.init my-skill-name

  This creates:
    - `priv/claude_skills/manifest.json` (or appends to existing)
    - `priv/claude_skills/my-skill-name/SKILL.md` with a frontmatter template

  ## Options

    - `--mcp-type` - register as an MCP component: tool, resource, or prompt
  """

  use Mix.Task

  alias ElixirMcp.Config

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
        Mix.shell().error("Usage: mix claude_skills.init <skill-id>")

      _ ->
        Mix.shell().error("Expected exactly one skill ID argument.")
    end
  end

  defp create_skill(skill_id, opts) do
    base_dir = Path.join(["priv", Config.skills_dir_name()])
    skill_dir = Path.join(base_dir, skill_id)
    manifest_path = Path.join(base_dir, Config.manifest_filename())
    skill_md_path = Path.join(skill_dir, "SKILL.md")

    File.mkdir_p!(skill_dir)

    update_manifest(manifest_path, skill_id, opts)
    write_skill_md(skill_md_path, skill_id)

    Mix.shell().info("Created skill scaffold:")
    Mix.shell().info("  #{manifest_path}")
    Mix.shell().info("  #{skill_md_path}")
    Mix.shell().info("\nEdit #{skill_md_path} to add your skill content.")
  end

  defp update_manifest(manifest_path, skill_id, opts) do
    manifest =
      if File.exists?(manifest_path) do
        manifest_path
        |> File.read!()
        |> Jason.decode!()
      else
        %{"schema_version" => 1, "skills" => []}
      end

    already_exists? = Enum.any?(manifest["skills"], &(&1["id"] === skill_id))

    if already_exists? do
      Mix.shell().info("Skill '#{skill_id}' already in manifest, skipping manifest update.")
    else
      new_entry = %{"id" => skill_id, "description" => "TODO: describe when to use this skill"}

      new_entry =
        case opts[:mcp_type] do
          nil -> new_entry
          type -> Map.put(new_entry, "mcp", %{"type" => type, "name" => skill_id})
        end

      updated = Map.update!(manifest, "skills", &(&1 ++ [new_entry]))
      File.write!(manifest_path, Jason.encode!(updated, pretty: true))
    end
  end

  defp write_skill_md(path, skill_id) do
    if File.exists?(path) do
      Mix.shell().info("#{path} already exists, skipping.")
    else
      app_name = Mix.Project.config()[:app] |> to_string()

      content = """
      ---
      name: #{app_name}--#{skill_id}
      description: Use when working with #{app_name} for TODO
      ---

      # #{skill_id |> String.replace("-", " ") |> String.capitalize()}

      TODO: Add skill content here.
      """

      File.write!(path, content)
    end
  end
end
