defmodule ElixirSkills.Config do
  @moduledoc """
  Configuration for ElixirSkills skill discovery and installation.

  ## Agent support

  ElixirSkills can install skills for multiple agents (Claude Code, Windsurf, Cursor, etc.).
  Each agent has a dotdir (e.g. `.claude/`, `.windsurf/`) where skills are installed.

  Configure which agents to target:

      # config/config.exs
      config :elixir_skills, agents: [:claude, :cursor]

  Or let auto-detection find which agent dotdirs exist:

      config :elixir_skills, agents: :auto  # default

  Supported agents: #{inspect([:claude, :windsurf, :cursor, :codex, :amp])}
  """

  @agents Application.compile_env(:elixir_skills, :agents, :auto)
  @bundled_skills_dir Application.compile_env(:elixir_skills, :bundled_skills_dir, nil)
  @allowed_packages Application.compile_env(:elixir_skills, :allowed_packages, nil)

  @skills_dir_name "skills"
  @tracking_filename ".elixir_skills.json"
  @bundled_package :elixir_skills
  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @known_agents %{
    claude: ".claude",
    windsurf: ".windsurf",
    cursor: ".cursor",
    codex: ".codex",
    amp: ".amp"
  }

  # AGENT RESOLUTION

  @doc """
  Returns the list of agents to install skills for.

  Resolution order:
    1. Explicit `agents: [...]` in opts
    2. Compile-time config `config :elixir_skills, agents: [...]`
    3. Auto-detection: scans project root for known agent dotdirs
  """
  @spec resolve_agents(keyword()) :: [atom()]
  def resolve_agents(opts \\ []) do
    case Keyword.get(opts, :agents, @agents) do
      :auto -> detect_agents()
      agents when is_list(agents) -> agents
    end
  end

  @doc """
  Detects which agents have dotdirs in the project root.
  Returns atoms for each detected agent (e.g. `[:claude, :cursor]`).
  """
  @spec detect_agents() :: [atom()]
  def detect_agents do
    root = project_root()

    @known_agents
    |> Enum.filter(fn {_agent, dotdir} -> File.dir?(Path.join(root, dotdir)) end)
    |> Enum.map(fn {agent, _} -> agent end)
    |> Enum.sort()
  end

  @doc "Returns the dotdir name for a known agent (e.g. `:claude` → `\".claude\"`)."
  @spec agent_dotdir(atom()) :: String.t()
  def agent_dotdir(agent), do: Map.fetch!(@known_agents, agent)

  @doc "Returns the list of known/supported agent names."
  @spec known_agents() :: [atom()]
  def known_agents, do: Map.keys(@known_agents)

  # TARGET DIRECTORIES

  @doc """
  Returns all target directories for skill installation based on resolved agents.

  Options:
    - `:agents` - explicit agent list or `:auto`
    - `:global` - use global home dirs instead of project-local
    - `:target_dir` - override completely (single dir, ignores agents)
  """
  @spec skills_target_dirs(keyword()) :: [String.t()]
  def skills_target_dirs(opts \\ []) do
    case Keyword.get(opts, :target_dir) do
      nil ->
        global? = Keyword.get(opts, :global, false)

        opts
        |> resolve_agents()
        |> Enum.map(fn agent -> agent_skills_dir(agent, global?) end)

      dir ->
        [dir]
    end
  end

  @doc """
  Returns a single target directory for backwards compatibility.
  Uses the first resolved agent, falling back to `:claude`.
  """
  @spec skills_target_dir(keyword()) :: String.t()
  def skills_target_dir(opts \\ []) do
    case Keyword.get(opts, :target_dir) do
      nil ->
        agent =
          opts
          |> resolve_agents()
          |> List.first()
          |> Kernel.||(:claude)

        agent_skills_dir(agent, Keyword.get(opts, :global, false))

      dir ->
        dir
    end
  end

  @doc "Skills directory for a specific agent and scope."
  @spec agent_skills_dir(atom(), boolean()) :: String.t()
  def agent_skills_dir(agent, global?) do
    dotdir = agent_dotdir(agent)

    if global? do
      Path.expand(Path.join(["~", dotdir, "skills"]))
    else
      Path.join([project_root(), dotdir, "skills"])
    end
  end

  # TRACKING

  @doc "Full path to the tracking file for the given scope."
  @spec tracking_file_path(keyword()) :: String.t()
  def tracking_file_path(opts \\ []) do
    Path.join(skills_target_dir(opts), @tracking_filename)
  end

  # STATIC CONFIG

  @router_skill_name "elixir-skills"

  @spec router_skill_name() :: String.t()
  def router_skill_name, do: @router_skill_name

  @doc """
  Full path to the merged `elixir-skills` skill directory for a given target.
  Accepts the same opts as `skills_target_dir/1`.
  """
  @spec router_skill_dir(keyword()) :: String.t()
  def router_skill_dir(opts \\ []) do
    Path.join(skills_target_dir(opts), @router_skill_name)
  end

  @spec skills_dir_name() :: String.t()
  def skills_dir_name, do: @skills_dir_name

  @spec tracking_filename() :: String.t()
  def tracking_filename, do: @tracking_filename

  @spec valid_id_pattern() :: Regex.t()
  def valid_id_pattern, do: @valid_id_pattern

  @spec bundled_package() :: atom()
  def bundled_package, do: @bundled_package

  @spec bundled_skills_dir() :: String.t()
  def bundled_skills_dir do
    @bundled_skills_dir || Application.app_dir(:elixir_skills, "priv/bundled_skills")
  end

  @spec allowed_packages() :: [atom()] | nil
  def allowed_packages, do: @allowed_packages

  # PRIVATE

  @doc false
  def project_root do
    if function_exported?(Mix.Project, :project_file, 0) do
      Path.dirname(Mix.Project.project_file())
    else
      File.cwd!()
    end
  end
end
