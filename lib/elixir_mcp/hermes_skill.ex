if Code.ensure_loaded?(Hermes.Server.Component) do
  defmodule ElixirMcp.HermesSkill do
    @moduledoc """
    Macro for library authors to create Hermes MCP components backed by a Claude Code skill.

    Requires `hermes_mcp` as a dependency. This module is only defined when hermes_mcp is available.

    ## Usage

        defmodule MyLib.Skills.WorkerPatterns do
          use ElixirMcp.HermesSkill,
            skill_id: "worker-patterns",
            type: :tool

          # Optional: override call/1 for dynamic behavior
          # Default returns the SKILL.md content
        end

    ## Options

      - `:skill_id` — the skill directory name under `priv/skills/` (required)
      - `:type` — MCP component type: `:tool`, `:resource`, or `:prompt` (default: `:tool`)
    """

    defmacro __using__(opts) do
      skill_id = Keyword.fetch!(opts, :skill_id)
      type = Keyword.get(opts, :type, :tool)

      quote do
        @skill_id unquote(skill_id)
        @skill_type unquote(type)

        @before_compile ElixirMcp.HermesSkill
      end
    end

    defmacro __before_compile__(env) do
      skill_id = Module.get_attribute(env.module, :skill_id)
      type = Module.get_attribute(env.module, :skill_type)
      app = Mix.Project.config()[:app]

      priv_dir = to_string(:code.priv_dir(app))
      skill_md_path = Path.join([priv_dir, "skills", skill_id, "SKILL.md"])

      content =
        if File.exists?(skill_md_path) do
          File.read!(skill_md_path)
        else
          IO.warn("SKILL.md not found at #{skill_md_path} — did you run `mix compile` to copy skills to priv/?")
          "Skill content not found at #{skill_md_path}"
        end

      has_call? = Module.defines?(env.module, {:call, 1})
      has_read? = Module.defines?(env.module, {:read, 2})
      has_get_messages? = Module.defines?(env.module, {:get_messages, 2})

      case type do
        :tool ->
          quote do
            use Hermes.Server.Component, type: :tool

            schema do
              field(:query, :string, description: "Optional query")
            end

            unless unquote(has_call?) do
              def call(_params) do
                {:ok, unquote(content)}
              end
            end

            def __skill_content__, do: unquote(content)
          end

        :resource ->
          uri = "skill://#{app}/#{skill_id}"

          quote do
            use Hermes.Server.Component, type: :resource

            def uri, do: unquote(uri)
            def mime_type, do: "text/markdown"

            unless unquote(has_read?) do
              def read(_params, _frame) do
                {:ok, unquote(content)}
              end
            end

            def __skill_content__, do: unquote(content)
          end

        :prompt ->
          quote do
            use Hermes.Server.Component, type: :prompt

            schema do
              field(:context, :string, description: "Additional context")
            end

            unless unquote(has_get_messages?) do
              def get_messages(_args, _frame) do
                {:ok, [
                  %{"role" => "user", "content" => %{
                    "type" => "text",
                    "text" => unquote(content)
                  }}
                ]}
              end
            end

            def __skill_content__, do: unquote(content)
          end
      end
    end
  end
end
