defmodule ElixirMcp.Skill do
  @moduledoc """
  Represents a Claude Code skill bundled in a hex package's `priv/claude_skills/` directory.
  """

  @type mcp_config :: %{
          type: :tool | :resource | :prompt,
          name: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          namespaced_id: String.t(),
          package: atom(),
          package_version: String.t() | nil,
          description: String.t(),
          source_path: String.t(),
          mcp: mcp_config() | nil,
          source: :library | :bundled | nil
        }

  @enforce_keys [:id, :namespaced_id, :package, :source_path]
  defstruct [
    :id,
    :namespaced_id,
    :package,
    :package_version,
    :description,
    :source_path,
    :mcp,
    :source
  ]

  @doc """
  Builds the namespaced skill ID from package name and skill ID.
  Uses double-dash separator to distinguish package prefix from skill ID.
  """
  @spec namespace(atom(), String.t()) :: String.t()
  def namespace(package, skill_id) do
    "#{package}--#{skill_id}"
  end
end
