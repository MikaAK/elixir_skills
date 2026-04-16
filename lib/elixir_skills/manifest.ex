defmodule ElixirSkills.Manifest do
  @moduledoc """
  Parses a library's `SKILL.md` file and returns a `Skill` struct.

  A library directory looks like:

      <dir>/
        SKILL.md           # required — YAML frontmatter + body
        references/        # optional
          patterns.md

  The `name:` frontmatter field is the library's logical id; `description:`
  becomes the router catalog entry.
  """

  alias ElixirSkills.Skill

  @type error :: {:error, String.t()}
  @type result :: {:ok, Skill.t()} | :no_skill | error()

  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @doc """
  Parses `<dir>/SKILL.md` and returns a Skill. Returns `:no_skill` when the
  file is absent (not an error — the dir just doesn't host a library skill).
  """
  @spec parse_library(String.t(), atom()) :: result()
  def parse_library(dir, package) do
    skill_md = Path.join(dir, "SKILL.md")

    cond do
      not File.dir?(dir) -> :no_skill
      not File.exists?(skill_md) -> :no_skill
      true -> read_and_build(skill_md, dir, package)
    end
  end

  defp read_and_build(skill_md, dir, package) do
    with {:ok, contents} <- File.read(skill_md),
         {:ok, frontmatter} <- parse_frontmatter(contents),
         {:ok, id} <- fetch_id(frontmatter) do
      skill = %Skill{
        id: id,
        package: package,
        description: frontmatter["description"],
        source_path: dir,
        mcp: parse_mcp_config(frontmatter["mcp"])
      }

      {:ok, skill}
    end
  end

  @doc """
  Extracts YAML frontmatter delimited by `---` lines. Returns `{:ok, map}`;
  empty map when no frontmatter is present.
  """
  @spec parse_frontmatter(String.t()) :: {:ok, map()} | error()
  def parse_frontmatter(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      [_, yaml, _] -> {:ok, parse_yaml(yaml)}
      _ -> {:ok, %{}}
    end
  end

  defp parse_yaml(yaml_string) do
    yaml_string
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^(\w[\w-]*):\s*(.+)$/, String.trim(line)) do
        [_, key, value] -> Map.put(acc, key, String.trim(value))
        _ -> acc
      end
    end)
  end

  defp fetch_id(%{"name" => id}) when is_binary(id) do
    if Regex.match?(@valid_id_pattern, id) do
      {:ok, id}
    else
      {:error, "Invalid 'name:' frontmatter '#{id}': must match [a-z0-9][a-z0-9-]*"}
    end
  end

  defp fetch_id(_), do: {:error, "missing 'name:' frontmatter"}

  defp parse_mcp_config(nil), do: nil

  defp parse_mcp_config(mcp_string) when is_binary(mcp_string) do
    case String.split(mcp_string, ":", parts: 2) do
      [type, name] when type in ["tool", "resource", "prompt"] ->
        %{type: String.to_existing_atom(String.trim(type)), name: String.trim(name)}

      _ ->
        nil
    end
  end

  defp parse_mcp_config(_), do: nil
end
