defmodule ElixirSkills.Hermes.Bridge do
  @moduledoc """
  Converts discovered skills with MCP configuration into Hermes MCP tool components.

  This module dynamically generates Hermes-compatible component modules at runtime
  so that skills can be registered with a Hermes MCP server.

  Requires `hermes_mcp` to be available — guarded by `Code.ensure_loaded?/1`.
  """

  alias ElixirSkills.Skill

  @doc """
  Generates dynamic Hermes component modules for all skills that have MCP config.

  Returns a list of `{module, type}` tuples that can be registered with a Hermes server.
  """
  @spec components_from_skills([Skill.t()]) :: [{module(), :tool | :resource | :prompt}]
  def components_from_skills(skills) do
    if hermes_available?() do
      skills
      |> Enum.filter(& &1.mcp)
      |> Enum.map(&build_component/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @doc """
  Builds a single dynamic component module for a skill.
  Returns `{module, type}` or nil if the skill has no MCP config.
  """
  @spec build_component(Skill.t()) :: {module(), atom()} | nil
  def build_component(%Skill{mcp: nil}), do: nil

  def build_component(%Skill{mcp: %{type: :tool}} = skill) do
    module_name = module_name_for(skill)
    skill_content = read_skill_content(skill)
    description = skill.description || "Skill: #{skill.id}"
    tool_name = skill.mcp.name || skill.id

    contents =
      quote do
        use Hermes.Server.Component, type: :tool

        @moduledoc unquote(description)

        schema do
          field(:query, :string, description: "Optional query to filter skill content")
        end

        def call(%{"query" => _query}) do
          {:ok, unquote(skill_content)}
        end

        def call(_params) do
          {:ok, unquote(skill_content)}
        end

        def __skill_name__, do: unquote(tool_name)
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    {module_name, :tool}
  end

  def build_component(%Skill{mcp: %{type: :resource}} = skill) do
    module_name = module_name_for(skill)
    skill_content = read_skill_content(skill)
    description = skill.description || "Skill: #{skill.id}"
    uri = "skill://#{skill.package}/#{skill.id}"

    contents =
      quote do
        use Hermes.Server.Component, type: :resource

        @moduledoc unquote(description)

        def uri, do: unquote(uri)
        def mime_type, do: "text/markdown"

        def read(_params, _frame) do
          {:ok, unquote(skill_content)}
        end
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    {module_name, :resource}
  end

  def build_component(%Skill{mcp: %{type: :prompt}} = skill) do
    module_name = module_name_for(skill)
    skill_content = read_skill_content(skill)
    description = skill.description || "Skill: #{skill.id}"

    contents =
      quote do
        use Hermes.Server.Component, type: :prompt

        @moduledoc unquote(description)

        schema do
          field(:context, :string, description: "Additional context for the prompt")
        end

        def get_messages(%{"context" => context}, _frame) do
          {:ok, [
            %{"role" => "user", "content" => %{
              "type" => "text",
              "text" => unquote(skill_content) <> "\n\nContext: " <> context
            }}
          ]}
        end

        def get_messages(_args, _frame) do
          {:ok, [
            %{"role" => "user", "content" => %{
              "type" => "text",
              "text" => unquote(skill_content)
            }}
          ]}
        end
      end

    Module.create(module_name, contents, Macro.Env.location(__ENV__))
    {module_name, :prompt}
  end

  defp module_name_for(%Skill{} = skill) do
    suffix =
      skill.id
      |> String.split("-")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join()

    Module.concat(ElixirSkills.Hermes.Generated, suffix)
  end

  defp read_skill_content(%Skill{source_path: source_path}) do
    skill_md = Path.join(source_path, "SKILL.md")

    if File.exists?(skill_md) do
      File.read!(skill_md)
    else
      "No SKILL.md found at #{skill_md}"
    end
  end

  defp hermes_available? do
    Code.ensure_loaded?(Hermes.Server.Component)
  end
end
