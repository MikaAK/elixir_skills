defmodule ElixirSkills.Server do
  @moduledoc """
  MCP server that exposes library skills discovered from hex dependencies.

  Tools operate on the merged `elixir-skills` skill that lives under each
  detected agent's skills directory. `install_skill` adds a library's
  references symlink and regenerates the router; `uninstall_skill` removes it.
  """

  use Hermes.Server,
    name: "elixir-mcp-skills",
    version: "0.1.0",
    capabilities: [:tools]

  alias Hermes.Server.Frame
  alias ElixirSkills.{Config, Discovery, Installer, Skill}

  def start(transport) do
    Hermes.Server.Supervisor.start_link(__MODULE__, transport: transport)
  end

  @impl true
  def init(_client_info, frame) do
    frame =
      frame
      |> Frame.register_tool("list_skills",
        description: "List library skills discovered from project hex dependencies"
      )
      |> Frame.register_tool("get_skill",
        description: "Return the content of a library's SKILL.md",
        input_schema: %{
          type: :object,
          properties: %{
            skill_id: %{type: :string, description: "Library id (from SKILL.md 'name:' frontmatter)"}
          },
          required: [:skill_id]
        }
      )
      |> Frame.register_tool("install_skill",
        description: "Add a library to the merged elixir-skills skill (symlink + router regeneration)",
        input_schema: %{
          type: :object,
          properties: %{
            skill_id: %{type: :string, description: "Library id to install"},
            copy: %{type: :boolean, description: "Copy files instead of symlink (default: false)"},
            global: %{type: :boolean, description: "Install to ~/.<agent>/skills/ (default: false)"},
            agent: %{type: :string, description: "Target agent: claude, windsurf, cursor, codex, amp"}
          },
          required: [:skill_id]
        }
      )
      |> Frame.register_tool("uninstall_skill",
        description: "Remove a library from the merged elixir-skills skill",
        input_schema: %{
          type: :object,
          properties: %{
            skill_id: %{type: :string, description: "Library id to uninstall"},
            global: %{type: :boolean, description: "Uninstall from ~/.<agent>/skills/"},
            agent: %{type: :string, description: "Target agent (default: auto-detect all)"}
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
            %{
              id: skill.id,
              package: to_string(skill.package),
              version: skill.package_version,
              description: skill.description,
              installed: Map.has_key?(tracking, skill.id),
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
        content =
          case File.read(Path.join(skill.source_path, "SKILL.md")) do
            {:ok, body} -> body
            _ -> "No SKILL.md found for library #{skill_id}"
          end

        {:reply, text_response(content), frame}

      {:error, reason} ->
        {:reply, text_response(reason), frame}
    end
  end

  def handle_tool_call("install_skill", %{"skill_id" => skill_id} = args, frame) do
    case find_skill(skill_id) do
      {:ok, skill} ->
        agent_opts = parse_agent_arg(args)
        copy? = Map.get(args, "copy", false)
        global? = Map.get(args, "global", false)

        results =
          Enum.map(Config.skills_target_dirs(agent_opts ++ [global: global?]), fn target_dir ->
            opts = [target_dir: target_dir, copy: copy?, force: true]
            plan = Installer.plan([skill], opts)
            {:ok, _} = Installer.execute(plan, opts)
            Path.join(target_dir, Config.router_skill_name())
          end)

        {:reply, text_response("Installed library #{skill_id} into merged skill at: #{Enum.join(results, ", ")}"), frame}

      {:error, reason} ->
        {:reply, text_response(reason), frame}
    end
  end

  def handle_tool_call("uninstall_skill", %{"skill_id" => skill_id} = args, frame) do
    agent_opts = parse_agent_arg(args)
    global? = Map.get(args, "global", false)

    removed =
      Enum.flat_map(Config.skills_target_dirs(agent_opts ++ [global: global?]), fn target_dir ->
        {:ok, ids} = Installer.uninstall([skill_id], target_dir: target_dir)
        Enum.map(ids, fn id -> "#{id} (#{target_dir})" end)
      end)

    if Enum.empty?(removed) do
      {:reply, text_response("Library #{skill_id} not installed in any agent directory"), frame}
    else
      {:reply, text_response("Uninstalled: #{Enum.join(removed, ", ")}"), frame}
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

  defp find_skill(library_id) do
    case Discovery.scan() do
      {:ok, skills} ->
        case Enum.find(skills, fn %Skill{id: id} -> id === library_id end) do
          nil -> {:error, "Library '#{library_id}' not found in any dependency"}
          %Skill{} = skill -> {:ok, skill}
        end

      {:error, reason} ->
        {:error, "Discovery failed: #{reason}"}
    end
  end
end
