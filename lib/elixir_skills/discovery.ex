defmodule ElixirSkills.Discovery do
  @moduledoc """
  Discovers library skills from hex deps and `elixir_skills`'s bundled baselines.

  Each discovered entry is a single `Skill` struct representing one library's
  `SKILL.md`. The installer merges these into the `elixir-skills` router skill.
  """

  require Logger

  alias ElixirSkills.{Config, Manifest, Skill}

  @doc """
  Scans every dep for a `priv/skills/SKILL.md` plus the baseline fallbacks
  shipped in `elixir_skills`'s own `priv/bundled_skills/`.

  Options:
    - `:packages` — restrict scanning to these atoms
    - `:bundled_skills_dir` — override the baseline path (for tests)
  """
  @spec scan(keyword()) :: {:ok, [Skill.t()]}
  def scan(opts \\ []) do
    filter_packages = Keyword.get(opts, :packages, nil)
    bundled_dir = Keyword.get(opts, :bundled_skills_dir, Config.bundled_skills_dir())

    library_skills =
      deps_paths()
      |> maybe_filter_packages(filter_packages)
      |> maybe_filter_allowed()
      |> Enum.flat_map(fn {package, dep_path} ->
        case scan_dep(package, dep_path) do
          {:ok, skills} ->
            Enum.map(skills, fn %Skill{} = skill -> %Skill{skill | source: :library} end)

          {:error, reason} ->
            Logger.debug("#{__MODULE__}: skipping dep #{package}: #{inspect(reason)}")
            []
        end
      end)

    bundled_skills =
      case scan_bundled(bundled_dir) do
        {:ok, skills} -> skills
        {:error, _} -> []
      end

    {:ok, merge_with_precedence(library_skills, bundled_skills)}
  end

  @doc """
  Returns `{:ok, [Skill.t()]}` for a single dep. The list has zero or one
  entry — one library per dep under the new model.
  """
  @spec scan_dep(atom(), String.t()) :: {:ok, [Skill.t()]}
  def scan_dep(package, dep_path) do
    skills_path = Path.join([dep_path, "priv", Config.skills_dir_name()])

    case Manifest.parse_library(skills_path, package) do
      {:ok, %Skill{} = skill} ->
        version = read_dep_version(dep_path)
        {:ok, [%Skill{skill | package_version: version}]}

      :no_skill ->
        {:ok, []}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Scans `elixir_skills`'s baseline directory. Each subdirectory is treated
  as one library's content (`<bundled_dir>/<lib>/SKILL.md`).
  """
  @spec scan_bundled(String.t()) :: {:ok, [Skill.t()]} | {:error, String.t()}
  def scan_bundled(bundled_dir \\ Config.bundled_skills_dir()) do
    if File.dir?(bundled_dir) do
      skills =
        bundled_dir
        |> File.ls!()
        |> Enum.sort()
        |> Enum.filter(fn name -> File.dir?(Path.join(bundled_dir, name)) end)
        |> Enum.flat_map(fn lib_dir ->
          full = Path.join(bundled_dir, lib_dir)

          case Manifest.parse_library(full, Config.bundled_package()) do
            {:ok, %Skill{} = skill} -> [%Skill{skill | source: :bundled}]
            _ -> []
          end
        end)

      {:ok, skills}
    else
      {:error, "bundled_skills_dir does not exist: #{bundled_dir}"}
    end
  end

  @doc """
  Merges library skills with bundled skills. Library skills override bundled
  skills with the same `id`.
  """
  @spec merge_with_precedence([Skill.t()], [Skill.t()]) :: [Skill.t()]
  def merge_with_precedence(library_skills, bundled_skills) do
    library_ids = library_skills |> Enum.map(&(&1.id)) |> MapSet.new()
    kept_bundled = Enum.reject(bundled_skills, fn %Skill{id: id} ->
      MapSet.member?(library_ids, id)
    end)
    library_skills ++ kept_bundled
  end

  defp deps_paths do
    if function_exported?(Mix.Project, :deps_paths, 0) do
      Mix.Project.deps_paths()
    else
      %{}
    end
  end

  defp maybe_filter_packages(deps, nil), do: deps
  defp maybe_filter_packages(deps, packages) do
    Enum.filter(deps, fn {p, _} -> p in packages end)
  end

  defp maybe_filter_allowed(deps) do
    case Config.allowed_packages() do
      nil -> deps
      allowed -> Enum.filter(deps, fn {p, _} -> p in allowed end)
    end
  end

  defp read_dep_version(dep_path) do
    mix_exs = Path.join(dep_path, "mix.exs")

    with true <- File.exists?(mix_exs),
         {:ok, contents} <- File.read(mix_exs),
         [_, version] <- Regex.run(~r/version:\s*"([^"]+)"/, contents) do
      version
    else
      _ -> nil
    end
  end
end
