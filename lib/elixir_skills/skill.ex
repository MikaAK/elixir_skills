defmodule ElixirSkills.Skill do
  @moduledoc """
  Represents one library's contribution to the merged `elixir-skills` skill.

  The `id` is the library's logical name (from the `name:` frontmatter field
  in the library's `skills/SKILL.md`) and must be unique across all discovered
  libraries. Each library's `source_path` is the directory containing
  `SKILL.md` and an optional `references/` subdirectory.
  """

  @enforce_keys [:id, :package, :source_path]
  defstruct [
    :id,
    :package,
    :package_version,
    :description,
    :source_path,
    :mcp,
    :source
  ]

  @type mcp_config :: %{type: :tool | :resource | :prompt, name: String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          package: atom(),
          package_version: String.t() | nil,
          description: String.t() | nil,
          source_path: String.t(),
          mcp: mcp_config() | nil,
          source: :library | :bundled | nil
        }
end
