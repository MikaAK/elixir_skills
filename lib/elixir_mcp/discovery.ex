defmodule ElixirMcp.Discovery do
  @moduledoc """
  Scans project dependencies for bundled Claude Code skills in `priv/skills/`.
  """

  require Logger

  alias ElixirMcp.{Config, Manifest, Skill}

  @doc """
  Scans all project dependencies for bundled skills.

  Options:
    - `:packages` - list of package atoms to restrict scanning to (default: all)
    - `:bundled_skills_dir` - path to bundled fallback skills (default: `Config.bundled_skills_dir()`)
  """
  @spec scan(keyword()) :: {:ok, [Skill.t()]} | {:error, String.t()}
  def scan(opts \\ []) do
    filter_packages = Keyword.get(opts, :packages, nil)
    bundled_dir = Keyword.get(opts, :bundled_skills_dir, Config.bundled_skills_dir())

    deps_paths = deps_paths()

    library_result =
      deps_paths
      |> maybe_filter_packages(filter_packages)
      |> maybe_filter_allowed()
      |> Enum.reduce({:ok, []}, fn {package, dep_path}, {:ok, acc} ->
        case scan_dep(package, dep_path) do
          {:ok, skills} -> {:ok, acc ++ skills}
          {:error, reason} ->
            Logger.debug("#{__MODULE__}: skipping dep #{package}, scan failed: #{inspect(reason)}")
            {:ok, acc}
        end
      end)

    with {:ok, library_skills} <- library_result do
      library_skills = Enum.map(library_skills, fn %Skill{} = skill -> %Skill{skill | source: :library} end)

      bundled_skills =
        case scan_bundled(bundled_dir) do
          {:ok, skills} -> skills
          {:error, _} -> []
        end

      {:ok, merge_with_precedence(library_skills, bundled_skills)}
    end
  end

  @doc """
  Scans a single dependency for bundled skills.
  """
  @spec scan_dep(atom(), String.t()) :: {:ok, [Skill.t()]} | {:error, String.t()}
  def scan_dep(package, dep_path) do
    skills_base = Path.join([dep_path, "priv", Config.skills_dir_name()])

    case Manifest.scan(skills_base, package) do
      {:ok, skills} ->
        version = read_dep_version(dep_path)
        skills = Enum.map(skills, fn %Skill{} = skill -> %Skill{skill | package_version: version} end)
        {:ok, skills}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Scans a bundled skills directory for fallback skills.
  These are skills shipped with elixir_mcp for libraries that don't bundle their own.
  """
  @spec scan_bundled(String.t()) :: {:ok, [Skill.t()]} | {:error, String.t()}
  def scan_bundled(bundled_dir \\ Config.bundled_skills_dir()) do
    case Manifest.scan(bundled_dir, Config.bundled_package()) do
      {:ok, skills} ->
        skills = Enum.map(skills, fn %Skill{} = skill -> %Skill{skill | source: :bundled} end)
        {:ok, skills}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Merges library skills with bundled fallback skills.
  Library skills always take precedence — if any library provides a skill with
  the same base `id`, the bundled version with that id is excluded.
  """
  @spec merge_with_precedence([Skill.t()], [Skill.t()]) :: [Skill.t()]
  def merge_with_precedence(library_skills, bundled_skills) do
    library_ids = library_skills |> Enum.map(& &1.id) |> MapSet.new()

    kept_bundled = Enum.reject(bundled_skills, fn skill -> MapSet.member?(library_ids, skill.id) end)

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
    Enum.filter(deps, fn {pkg, _} -> pkg in packages end)
  end

  defp maybe_filter_allowed(deps) do
    case Config.allowed_packages() do
      nil -> deps
      allowed -> Enum.filter(deps, fn {pkg, _} -> pkg in allowed end)
    end
  end

  defp read_dep_version(dep_path) do
    mix_exs = Path.join(dep_path, "mix.exs")

    if File.exists?(mix_exs) do
      case File.read(mix_exs) do
        {:ok, contents} ->
          case Regex.run(~r/version:\s*"([^"]+)"/, contents) do
            [_, version] -> version
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end
end
