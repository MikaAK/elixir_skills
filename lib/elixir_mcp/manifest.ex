defmodule ElixirMcp.Manifest do
  @moduledoc """
  Parses and validates `manifest.json` files from `priv/claude_skills/`.
  """

  alias ElixirMcp.{Config, Skill}

  @type error :: {:error, String.t()}

  @doc """
  Parses a manifest.json file at the given path and returns a list of Skill structs.

  The `package` and `base_path` are used to resolve full paths and namespacing.
  """
  @spec parse(String.t(), atom(), String.t()) :: {:ok, [Skill.t()]} | error()
  def parse(manifest_path, package, base_path) do
    with {:ok, contents} <- File.read(manifest_path),
         {:ok, json} <- Jason.decode(contents),
         :ok <- validate_schema_version(json),
         {:ok, skills} <- parse_skills(json, package, base_path) do
      {:ok, skills}
    else
      {:error, %Jason.DecodeError{} = err} -> {:error, "Invalid JSON in #{manifest_path}: #{Exception.message(err)}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "Failed to read #{manifest_path}: #{inspect(reason)}"}
    end
  end

  defp validate_schema_version(%{"schema_version" => 1}), do: :ok
  defp validate_schema_version(%{"schema_version" => v}), do: {:error, "Unsupported manifest schema_version: #{v}"}
  defp validate_schema_version(_), do: {:error, "Missing schema_version in manifest"}

  defp parse_skills(%{"skills" => skills}, package, base_path) when is_list(skills) do
    results =
      Enum.reduce_while(skills, {:ok, []}, fn entry, {:ok, acc} ->
        case parse_skill_entry(entry, package, base_path) do
          {:ok, skill} -> {:cont, {:ok, [skill | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, skills} -> {:ok, Enum.reverse(skills)}
      error -> error
    end
  end

  defp parse_skills(_, _, _), do: {:error, "Missing or invalid 'skills' array in manifest"}

  defp parse_skill_entry(%{"id" => id} = entry, package, base_path) do
    with :ok <- validate_id(id) do
      source_path = Path.join(base_path, id)
      mcp = parse_mcp_config(entry["mcp"])

      skill = %Skill{
        id: id,
        namespaced_id: Skill.namespace(package, id),
        package: package,
        description: entry["description"],
        source_path: source_path,
        mcp: mcp
      }

      {:ok, skill}
    end
  end

  defp parse_skill_entry(_, _, _), do: {:error, "Skill entry missing required 'id' field"}

  defp validate_id(id) do
    if Regex.match?(Config.valid_id_pattern(), id) do
      :ok
    else
      {:error, "Invalid skill id '#{id}': must match [a-z0-9][a-z0-9-]*"}
    end
  end

  defp parse_mcp_config(nil), do: nil

  defp parse_mcp_config(%{"type" => type, "name" => name}) when type in ["tool", "resource", "prompt"] do
    %{type: String.to_existing_atom(type), name: name}
  end

  defp parse_mcp_config(%{"type" => type, "name" => name}) do
    try do
      %{type: String.to_atom(type), name: name}
    rescue
      _ -> nil
    end
  end

  defp parse_mcp_config(_), do: nil
end
