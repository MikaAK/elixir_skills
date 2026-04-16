defmodule ElixirSkills.Manifest do
  @moduledoc """
  Discovers skills by scanning directories and parsing SKILL.md frontmatter.

  Each subdirectory under a skills base path that contains a `SKILL.md` file
  is treated as a skill. Metadata (description, mcp config) is extracted from
  YAML frontmatter delimited by `---` lines.
  """

  alias ElixirSkills.{Config, Skill}

  @type error :: {:error, String.t()}

  @doc """
  Scans a directory for skill subdirectories containing SKILL.md files.
  Returns a list of Skill structs built from frontmatter metadata.
  """
  @spec scan(String.t(), atom()) :: {:ok, [Skill.t()]} | error()
  def scan(base_path, package) do
    if File.dir?(base_path) do
      skills =
        base_path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.filter(fn name -> File.dir?(Path.join(base_path, name)) end)
        |> Enum.reduce([], fn dir_name, acc ->
          skill_md = Path.join([base_path, dir_name, "SKILL.md"])

          if File.exists?(skill_md) do
            case parse_skill(dir_name, skill_md, package, base_path) do
              {:ok, skill} -> [skill | acc]
              {:error, _} -> acc
            end
          else
            acc
          end
        end)
        |> Enum.reverse()

      {:ok, skills}
    else
      {:error, "Directory does not exist: #{base_path}"}
    end
  end

  @doc """
  Parses a single SKILL.md file and returns a Skill struct.
  """
  @spec parse_skill(String.t(), String.t(), atom(), String.t()) :: {:ok, Skill.t()} | error()
  def parse_skill(dir_name, skill_md_path, package, base_path) do
    with :ok <- validate_id(dir_name),
         {:ok, contents} <- File.read(skill_md_path),
         {:ok, frontmatter} <- parse_frontmatter(contents) do
      source_path = Path.join(base_path, dir_name)

      skill = %Skill{
        id: dir_name,
        package: package,
        description: frontmatter["description"],
        source_path: source_path,
        mcp: parse_mcp_config(frontmatter["mcp"])
      }

      {:ok, skill}
    end
  end

  @doc """
  Extracts YAML frontmatter from a string delimited by `---` lines.
  Returns a map of key-value pairs parsed from simple `key: value` lines.
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

  defp validate_id(id) do
    if Regex.match?(Config.valid_id_pattern(), id) do
      :ok
    else
      {:error, "Invalid skill id '#{id}': must match [a-z0-9][a-z0-9-]*"}
    end
  end

  defp parse_mcp_config(nil), do: nil

  defp parse_mcp_config(mcp_string) when is_binary(mcp_string) do
    # frontmatter mcp is a simple "type:name" format
    case String.split(mcp_string, ":", parts: 2) do
      [type, name] when type in ["tool", "resource", "prompt"] ->
        %{type: String.to_existing_atom(String.trim(type)), name: String.trim(name)}

      _ ->
        nil
    end
  end

  defp parse_mcp_config(_), do: nil
end
