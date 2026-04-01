defmodule ElixirSkills.Server do
  @moduledoc """
  MCP server that exposes skills discovered from hex dependencies.

  Agents connect via stdio or HTTP and can:
  - List available skills from the project's dependencies
  - Get skill content (the SKILL.md guidance)
  - Install skills to their local skill directory (auto-install hook)

  ## Starting the server

      # Via stdio (for Claude Code, Cursor, etc.)
      ElixirSkills.Server.start(:stdio)

      # Via HTTP
      ElixirSkills.Server.start({:streamable_http, port: 4242})

  ## Available tools

  - `list_skills` — returns all skills discovered from hex deps
  - `get_skill` — returns the content of a specific skill by namespaced ID
  - `install_skill` — installs a skill to the agent's local skill directory
  - `uninstall_skill` — removes a previously installed skill
  """

  use Hermes.Server,
    name: "elixir-mcp-skills",
    version: "0.1.0",
    capabilities: [:tools]

  alias Hermes.Server.Frame
  alias ElixirSkills.{Config, Discovery, Installer, Skill}

  @doc "Starts the MCP server with the given transport."
  def start(transport) do
    Hermes.Server.Supervisor.start_link(__MODULE__, transport: transport)
  end

  @impl true
  def init(_client_info, frame) do
    frame =
      frame
      |> Frame.register_tool("list_skills", description: "List all Claude Code skills available from project hex dependencies")
      |> Frame.register_tool("get_skill",
        description: "Get the content of a specific skill by its namespaced ID (e.g., oban--worker-patterns)",
        input_schema: %{
          type: :object,
          properties: %{skill_id: %{type: :string, description: "Namespaced skill ID (package--skill-name)"}},
          required: [:skill_id]
        }
      )
      |> Frame.register_tool("install_skill",
        description: "Install a skill by symlinking into detected agent skill directories (auto-detects Claude, Windsurf, Cursor, etc.)",
        input_schema: %{
          type: :object,
          properties: %{
            skill_id: %{type: :string, description: "Namespaced skill ID to install"},
            copy: %{type: :boolean, description: "Copy files instead of symlink (default: false)"},
            global: %{type: :boolean, description: "Install to global ~/.<agent>/skills/ instead of project-local (default: false)"},
            agent: %{type: :string, description: "Specific agent to install for: claude, windsurf, cursor, codex, amp (default: auto-detect all)"}
          },
          required: [:skill_id]
        }
      )
      |> Frame.register_tool("uninstall_skill",
        description: "Remove a previously installed skill from detected agent skill directories",
        input_schema: %{
          type: :object,
          properties: %{
            skill_id: %{type: :string, description: "Namespaced skill ID to uninstall"},
            global: %{type: :boolean, description: "Uninstall from global ~/.<agent>/skills/ instead of project-local (default: false)"},
            agent: %{type: :string, description: "Specific agent to uninstall from (default: auto-detect all)"}
          },
          required: [:skill_id]
        }
      )

    {:ok, frame}
  end

  @impl true
  def handle_tool_call("list_skills", _args, frame) do
    case Discovery.scan() do
      {:ok, skills} ->
        tracking = Installer.read_tracking()

        result =
          Enum.map(skills, fn skill ->
            installed? = Map.has_key?(tracking, skill.namespaced_id)

            %{
              id: skill.namespaced_id,
              package: to_string(skill.package),
              version: skill.package_version,
              description: skill.description,
              installed: installed?,
              has_mcp: not is_nil(skill.mcp),
              source: to_string(skill.source || :library)
            }
          end)

        {:reply, text_response(Jason.encode!(result, pretty: true)), frame}

      {:error, reason} ->
        {:reply, text_response("Error scanning skills: #{reason}"), frame}
    end
  end

  def handle_tool_call("get_skill", %{"skill_id" => skill_id}, frame) do
    case find_skill(skill_id) do
      {:ok, skill} ->
        skill_md = Path.join(skill.source_path, "SKILL.md")

        content =
          if File.exists?(skill_md) do
            File.read!(skill_md)
          else
            "No SKILL.md found for skill #{skill_id}"
          end

        {:reply, text_response(content), frame}

      {:error, reason} ->
        {:reply, text_response(reason), frame}
    end
  end

  def handle_tool_call("install_skill", %{"skill_id" => skill_id} = args, frame) do
    copy? = Map.get(args, "copy", false)
    global? = Map.get(args, "global", false)
    agent_opts = parse_agent_arg(args)
    target_dirs = Config.skills_target_dirs(agent_opts ++ [global: global?])

    case find_skill(skill_id) do
      {:ok, skill} ->
        results =
          Enum.map(target_dirs, fn target_dir ->
            plan_entry = %{skill: skill, action: :new, reason: nil}
            install_opts = [target_dir: target_dir, copy: copy?, force: true]
            {:ok, _} = Installer.execute([plan_entry], install_opts)
            "#{target_dir}/#{skill_id}"
          end)

        {:reply, text_response("Installed skill #{skill_id} to: #{Enum.join(results, ", ")}"), frame}

      {:error, reason} ->
        {:reply, text_response(reason), frame}
    end
  end

  def handle_tool_call("uninstall_skill", %{"skill_id" => skill_id} = args, frame) do
    global? = Map.get(args, "global", false)
    agent_opts = parse_agent_arg(args)
    target_dirs = Config.skills_target_dirs(agent_opts ++ [global: global?])

    all_removed =
      Enum.flat_map(target_dirs, fn target_dir ->
        {:ok, removed} = Installer.uninstall([skill_id], [target_dir: target_dir])
        Enum.map(removed, fn id -> "#{id} (#{target_dir})" end)
      end)

    if Enum.empty?(all_removed) do
      {:reply, text_response("Skill #{skill_id} not found in any installed agent directory"), frame}
    else
      {:reply, text_response("Uninstalled: #{Enum.join(all_removed, ", ")}"), frame}
    end
  end

  def handle_tool_call(name, _args, frame) do
    {:reply, text_response("Unknown tool: #{name}"), frame}
  end

  # -- Private --

  defp parse_agent_arg(%{"agent" => agent_str}) when is_binary(agent_str) do
    [agents: [String.to_existing_atom(agent_str)]]
  rescue
    ArgumentError -> []
  end

  defp parse_agent_arg(_), do: []

  defp text_response(text) do
    Hermes.Server.Response.tool() |> Hermes.Server.Response.text(text)
  end

  defp find_skill(namespaced_id) do
    case Discovery.scan() do
      {:ok, skills} ->
        case Enum.find(skills, fn skill -> skill.namespaced_id === namespaced_id end) do
          nil -> {:error, "Skill '#{namespaced_id}' not found in any dependency"}
          %Skill{} = skill -> {:ok, skill}
        end

      {:error, reason} ->
        {:error, "Discovery failed: #{reason}"}
    end
  end
end
