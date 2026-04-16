defmodule ElixirSkills.Installer do
  @moduledoc """
  Installs library skills into the merged `elixir-skills` skill dir and
  regenerates the router `SKILL.md` whenever the library set changes.

  Layout produced (per agent, under `<target>/elixir-skills/`):

      SKILL.md                 # generated router
      references/
        <library-id>/          # symlink to the library's priv/skills dir
          SKILL.md
          references/...

  Tracking lives at `<target>/.elixir_skills.json` and is keyed by library id.
  """

  alias ElixirSkills.{Config, Router, Skill}

  @type action :: :new | :update | :conflict | :stale | :unchanged
  @type plan_entry :: %{skill: Skill.t(), action: action(), reason: String.t() | nil}
  @type install_result :: {:ok, %{installed: [String.t()], skipped: [String.t()]}}

  # -- Planning --

  @spec plan([Skill.t()], keyword()) :: [plan_entry()]
  def plan(skills, opts \\ []) do
    tracking = read_tracking(opts)
    refs_dir = references_dir(opts)

    Enum.map(skills, fn skill ->
      target = Path.join(refs_dir, skill.id)
      existing = Map.get(tracking, skill.id)

      cond do
        is_nil(existing) and not File.exists?(target) ->
          %{skill: skill, action: :new, reason: nil}

        is_nil(existing) and File.exists?(target) ->
          %{skill: skill, action: :conflict, reason: "Directory exists but was not installed by elixir_skills"}

        existing["package"] === to_string(skill.package) ->
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

  @spec stale_entries(keyword()) :: [%{library_id: String.t(), reason: String.t()}]
  def stale_entries(opts \\ []) do
    tracking = read_tracking(opts)
    refs_dir = references_dir(opts)

    tracking
    |> Enum.filter(fn {id, _meta} ->
      target = Path.join(refs_dir, id)
      not File.exists?(target) or broken_symlink?(target)
    end)
    |> Enum.map(fn {id, meta} ->
      %{library_id: id, reason: "Broken symlink from package: #{meta["package"]}"}
    end)
  end

  # -- Installation --

  @spec execute([plan_entry()], keyword()) :: install_result()
  def execute(plan_entries, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    copy? = Keyword.get(opts, :copy, false)

    refs_dir = references_dir(opts)
    File.mkdir_p!(refs_dir)

    {installed, skipped} =
      Enum.reduce(plan_entries, {[], []}, fn entry, {inst, skip} ->
        case execute_entry(entry, refs_dir, force?, copy?) do
          {:installed, id} -> {[id | inst], skip}
          {:skipped, id} -> {inst, [id | skip]}
        end
      end)

    installed = Enum.reverse(installed)
    skipped = Enum.reverse(skipped)

    update_tracking_for_installed(installed, plan_entries, opts)
    regenerate_router(opts)

    {:ok, %{installed: installed, skipped: skipped}}
  end

  defp execute_entry(%{action: :unchanged} = entry, _refs_dir, _force?, _copy?) do
    {:skipped, entry.skill.id}
  end

  defp execute_entry(%{action: :conflict} = entry, _refs_dir, false, _copy?) do
    {:skipped, entry.skill.id}
  end

  defp execute_entry(%{skill: skill, action: action}, refs_dir, _force?, copy?) when action in [:new, :update, :conflict] do
    target = Path.join(refs_dir, skill.id)

    if File.exists?(target) or symlink?(target) do
      File.rm_rf!(target)
    end

    if copy? do
      File.cp_r!(skill.source_path, target)
    else
      File.ln_s!(skill.source_path, target)
    end

    {:installed, skill.id}
  end

  # -- Uninstallation --

  @spec uninstall(:all | [String.t()], keyword()) :: {:ok, [String.t()]}
  def uninstall(:all, opts) do
    tracking = read_tracking(opts)
    ids = Map.keys(tracking)
    router_dir = Config.router_skill_dir(opts)

    if File.exists?(router_dir) or symlink?(router_dir) do
      File.rm_rf!(router_dir)
    end

    write_tracking(%{}, opts)
    {:ok, ids}
  end

  def uninstall(ids, opts) when is_list(ids) do
    tracking = read_tracking(opts)
    refs_dir = references_dir(opts)

    to_remove = Enum.filter(ids, &Map.has_key?(tracking, &1))

    Enum.each(to_remove, fn id ->
      target = Path.join(refs_dir, id)

      if File.exists?(target) or symlink?(target) do
        File.rm_rf!(target)
      end
    end)

    new_tracking = Map.drop(tracking, to_remove)
    write_tracking(new_tracking, opts)
    regenerate_router(opts)

    {:ok, to_remove}
  end

  @spec clean_stale(keyword()) :: {:ok, [String.t()]}
  def clean_stale(opts \\ []) do
    ids = stale_entries(opts) |> Enum.map(& &1.library_id)
    uninstall(ids, opts)
  end

  # -- Router regeneration --

  defp regenerate_router(opts) do
    router_dir = Config.router_skill_dir(opts)
    File.mkdir_p!(router_dir)

    tracking = read_tracking(opts)
    skills = tracking_to_skills(tracking)
    content = Router.generate(skills)
    File.write!(Path.join(router_dir, "SKILL.md"), content)
  end

  defp tracking_to_skills(tracking) do
    Enum.map(tracking, fn {id, meta} ->
      %Skill{
        id: id,
        package: safe_to_atom(meta["package"]),
        package_version: meta["package_version"],
        description: meta["description"],
        source_path: meta["source_path"]
      }
    end)
  end

  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> string
  end

  # -- Tracking --

  @spec read_tracking(keyword()) :: map()
  def read_tracking(opts \\ []) do
    path = Config.tracking_file_path(opts)

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"libraries" => libs}} -> libs
          {:ok, %{"skills" => legacy}} -> legacy
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
      |> Enum.map(fn %{skill: skill} -> {skill.id, skill} end)
      |> Map.new()

    new_entries =
      installed_ids
      |> Enum.map(fn id ->
        skill = Map.fetch!(skills_by_id, id)

        {id,
         %{
           "package" => to_string(skill.package),
           "package_version" => skill.package_version,
           "description" => skill.description,
           "source_path" => skill.source_path,
           "installed_at" => now
         }}
      end)
      |> Map.new()

    tracking
    |> Map.merge(new_entries)
    |> write_tracking(opts)
  end

  defp write_tracking(libraries_map, opts) do
    path = Config.tracking_file_path(opts)
    File.mkdir_p!(Path.dirname(path))
    data = %{"version" => 1, "libraries" => libraries_map}
    File.write!(path, Jason.encode!(data, pretty: true))
  end

  # -- Paths --

  defp references_dir(opts) do
    Path.join(Config.router_skill_dir(opts), "references")
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
