defmodule ElixirMcp.Installer do
  @moduledoc """
  Installs and uninstalls agent skills by symlinking or copying
  skill directories into detected agent skill directories
  (`.claude/skills/`, `.windsurf/skills/`, `.cursor/skills/`, etc.).

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

  Options:
    - `:global` - plan against user-global skills dir (default: false, uses project-local)
  """
  @spec plan([Skill.t()], keyword()) :: [plan_entry()]
  def plan(skills, opts \\ []) do
    tracking = read_tracking(opts)
    target_dir = Config.skills_target_dir(opts)

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

  Options:
    - `:global` - check user-global skills dir (default: false)
  """
  @spec stale_entries(keyword()) :: [%{namespaced_id: String.t(), reason: String.t()}]
  def stale_entries(opts \\ []) do
    tracking = read_tracking(opts)
    target_dir = Config.skills_target_dir(opts)

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
    - `:global` - install to user-global skills dir (default: false)
  """
  @spec execute([plan_entry()], keyword()) :: install_result()
  def execute(plan_entries, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    copy? = Keyword.get(opts, :copy, false)
    target_dir = Config.skills_target_dir(opts)

    File.mkdir_p!(target_dir)

    {installed, skipped} =
      Enum.reduce(plan_entries, {[], []}, fn entry, {inst, skip} ->
        case execute_entry(entry, target_dir, force?, copy?) do
          {:installed, id} -> {[id | inst], skip}
          {:skipped, id} -> {inst, [id | skip]}
        end
      end)

    update_tracking_for_installed(Enum.reverse(installed), plan_entries, opts)
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

  # -- Uninstallation --

  @doc """
  Uninstalls skills by removing their symlinks/directories and cleaning the tracking file.

  Pass `:all` to remove everything managed by elixir_mcp, or a list of namespaced IDs.

  Options:
    - `:global` - uninstall from user-global skills dir (default: false)
  """
  @spec uninstall(:all | [String.t()], keyword()) :: {:ok, [String.t()]}
  def uninstall(ids, opts \\ []) do
    tracking = read_tracking(opts)
    target_dir = Config.skills_target_dir(opts)

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
    write_tracking(new_tracking, opts)

    {:ok, ids_to_remove}
  end

  @doc """
  Removes stale entries (broken symlinks) from the tracking file and filesystem.

  Options:
    - `:global` - clean stale entries from user-global skills dir (default: false)
  """
  @spec clean_stale(keyword()) :: {:ok, [String.t()]}
  def clean_stale(opts \\ []) do
    stale = stale_entries(opts)
    ids = Enum.map(stale, & &1.namespaced_id)
    uninstall(ids, opts)
  end

  # -- Tracking file --

  @doc """
  Returns the current tracking data as a map of namespaced_id => metadata.

  Options:
    - `:global` - read from user-global tracking file (default: false)
  """
  @spec read_tracking(keyword()) :: map()
  def read_tracking(opts \\ []) do
    path = Config.tracking_file_path(opts)

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

  defp update_tracking_for_installed(installed_ids, plan_entries, opts) do
    tracking = read_tracking(opts)
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
    |> write_tracking(opts)
  end

  defp write_tracking(skills_map, opts) do
    path = Config.tracking_file_path(opts)
    File.mkdir_p!(Path.dirname(path))
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
