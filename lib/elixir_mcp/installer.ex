defmodule ElixirMcp.Installer do
  @moduledoc """
  Installs and uninstalls Claude Code skills by symlinking or copying
  skill directories into `~/.claude/skills/`.

  Maintains a tracking file (`.elixir_mcp.json`) to record which skills
  were installed and from which package.
  """

  alias ElixirMcp.{Config, Skill}

  @type action :: :new | :update | :conflict | :stale | :unchanged
  @type plan_entry :: %{skill: Skill.t(), action: action(), reason: String.t() | nil}
  @type install_result :: {:ok, %{installed: [String.t()], skipped: [String.t()]}} | {:error, String.t()}

  # -- Planning --

  @doc """
  Creates an installation plan by comparing discovered skills against what's currently installed.
  Returns a list of `%{skill: skill, action: action, reason: reason}` entries.
  """
  @spec plan([Skill.t()]) :: [plan_entry()]
  def plan(skills) do
    tracking = read_tracking()
    target_dir = Config.skills_target_dir()

    Enum.map(skills, fn skill ->
      target = Path.join(target_dir, skill.namespaced_id)
      existing = Map.get(tracking, skill.namespaced_id)

      cond do
        is_nil(existing) and not File.exists?(target) ->
          %{skill: skill, action: :new, reason: nil}

        is_nil(existing) and File.exists?(target) ->
          %{skill: skill, action: :conflict, reason: "Directory exists but was not installed by elixir_mcp"}

        not is_nil(existing) and existing["package"] === to_string(skill.package) ->
          if existing["package_version"] !== skill.package_version do
            %{skill: skill, action: :update, reason: "Version changed: #{existing["package_version"]} → #{skill.package_version}"}
          else
            %{skill: skill, action: :unchanged, reason: nil}
          end

        true ->
          %{skill: skill, action: :conflict, reason: "Installed from different package: #{existing["package"]}"}
      end
    end)
  end

  @doc """
  Detects stale entries: skills in the tracking file whose symlinks are broken.
  """
  @spec stale_entries() :: [%{namespaced_id: String.t(), reason: String.t()}]
  def stale_entries do
    tracking = read_tracking()
    target_dir = Config.skills_target_dir()

    tracking
    |> Enum.filter(fn {id, _meta} ->
      target = Path.join(target_dir, id)
      not File.exists?(target) or broken_symlink?(target)
    end)
    |> Enum.map(fn {id, meta} ->
      %{namespaced_id: id, reason: "Broken symlink from package: #{meta["package"]}"}
    end)
  end

  # -- Installation --

  @doc """
  Executes an installation plan. Creates symlinks for :new and :update entries.

  Options:
    - `:force` - overwrite conflicts (default: false)
    - `:copy` - copy instead of symlink (default: false)
  """
  @spec execute([plan_entry()], keyword()) :: install_result()
  def execute(plan_entries, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    copy? = Keyword.get(opts, :copy, false)
    target_dir = Config.skills_target_dir()

    File.mkdir_p!(target_dir)

    {installed, skipped} =
      Enum.reduce(plan_entries, {[], []}, fn entry, {inst, skip} ->
        case execute_entry(entry, target_dir, force?, copy?) do
          {:installed, id} -> {[id | inst], skip}
          {:skipped, id} -> {inst, [id | skip]}
        end
      end)

    update_tracking_for_installed(Enum.reverse(installed), plan_entries)
    {:ok, %{installed: Enum.reverse(installed), skipped: Enum.reverse(skipped)}}
  end

  defp execute_entry(%{action: :unchanged} = entry, _target_dir, _force?, _copy?) do
    {:skipped, entry.skill.namespaced_id}
  end

  defp execute_entry(%{action: :conflict} = entry, _target_dir, false, _copy?) do
    {:skipped, entry.skill.namespaced_id}
  end

  defp execute_entry(%{skill: skill, action: action}, target_dir, _force?, copy?) when action in [:new, :update, :conflict] do
    target = Path.join(target_dir, skill.namespaced_id)

    if File.exists?(target) or symlink?(target) do
      File.rm_rf!(target)
    end

    if copy? do
      File.cp_r!(skill.source_path, target)
    else
      File.ln_s!(skill.source_path, target)
    end

    {:installed, skill.namespaced_id}
  end

  defp execute_entry(entry, _target_dir, _force?, _copy?) do
    {:skipped, entry.skill.namespaced_id}
  end

  # -- Uninstallation --

  @doc """
  Uninstalls skills by removing their symlinks/directories and cleaning the tracking file.

  Pass `:all` to remove everything managed by elixir_mcp, or a list of namespaced IDs.
  """
  @spec uninstall(:all | [String.t()]) :: {:ok, [String.t()]}
  def uninstall(ids) do
    tracking = read_tracking()
    target_dir = Config.skills_target_dir()

    ids_to_remove =
      case ids do
        :all -> Map.keys(tracking)
        list -> Enum.filter(list, &Map.has_key?(tracking, &1))
      end

    Enum.each(ids_to_remove, fn id ->
      target = Path.join(target_dir, id)

      if File.exists?(target) or symlink?(target) do
        File.rm_rf!(target)
      end
    end)

    new_tracking = Map.drop(tracking, ids_to_remove)
    write_tracking(new_tracking)

    {:ok, ids_to_remove}
  end

  @doc """
  Removes stale entries (broken symlinks) from the tracking file and filesystem.
  """
  @spec clean_stale() :: {:ok, [String.t()]}
  def clean_stale do
    stale = stale_entries()
    ids = Enum.map(stale, & &1.namespaced_id)
    uninstall(ids)
  end

  # -- Tracking file --

  @doc "Returns the current tracking data as a map of namespaced_id => metadata."
  @spec read_tracking() :: map()
  def read_tracking do
    path = Config.tracking_file_path()

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"skills" => skills}} -> skills
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp update_tracking_for_installed(installed_ids, plan_entries) do
    tracking = read_tracking()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    skills_by_id =
      plan_entries
      |> Enum.map(fn entry -> {entry.skill.namespaced_id, entry.skill} end)
      |> Map.new()

    new_entries =
      installed_ids
      |> Enum.map(fn id ->
        skill = Map.fetch!(skills_by_id, id)

        {id, %{
          "package" => to_string(skill.package),
          "package_version" => skill.package_version,
          "source_path" => skill.source_path,
          "installed_at" => now
        }}
      end)
      |> Map.new()

    tracking
    |> Map.merge(new_entries)
    |> write_tracking()
  end

  defp write_tracking(skills_map) do
    path = Config.tracking_file_path()
    data = %{"version" => 1, "skills" => skills_map}
    File.write!(path, Jason.encode!(data, pretty: true))
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _ -> false
    end
  end

  defp broken_symlink?(path) do
    symlink?(path) and not File.exists?(path)
  end
end
