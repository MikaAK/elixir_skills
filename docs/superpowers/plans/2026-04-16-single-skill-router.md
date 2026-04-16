# Single-Skill Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `elixir_skills` so `mix skills.install` produces one merged `elixir-skills` skill per agent with symlinked per-library subfolders under `references/` and a synthesized router `SKILL.md`, replacing today's one-agent-skill-per-library output.

**Architecture:** Library authors ship `skills/SKILL.md` (+ optional `skills/references/*.md`) in their hex package. `elixir_skills` still keeps baseline fallbacks — moved from `skills/*` to `priv/bundled_skills/<lib>/`. `Discovery` returns one `Skill` struct per library (keyed by the `name:` frontmatter field). `Installer` symlinks each library's `priv/skills/` dir into `.claude/skills/elixir-skills/references/<lib>/` and invokes a new `Router` module to synthesize `.claude/skills/elixir-skills/SKILL.md`. The tracking file still lives at `.claude/skills/.elixir_skills.json` but its keys are library names (no more `package--skill` namespacing — one skill per library).

**Tech Stack:** Elixir, Mix tasks, `Hermes.Server` for MCP, `Jason` for tracking-file JSON.

---

## Reference — Spec

See `docs/superpowers/specs/2026-04-16-single-skill-router-design.md`.

## File Structure

### Source files to modify / create

| File | Change |
|------|--------|
| `lib/elixir_skills/skill.ex` | Drop `namespaced_id` + `namespace/2`; keep `id` as the library name (from `name:` frontmatter) |
| `lib/elixir_skills/manifest.ex` | Replace `scan/2` with `parse_library/2` — reads `<dir>/SKILL.md` directly (no subdir enumeration) |
| `lib/elixir_skills/discovery.ex` | Call `Manifest.parse_library/2` for each dep's `priv/skills/`; baseline scan walks `priv/bundled_skills/<lib>/` |
| `lib/elixir_skills/config.ex` | Add `router_skill_name/0` and `router_skill_dir/1`; bump `@tracking_filename` comment |
| `lib/elixir_skills/router.ex` | **NEW** — `generate/1` builds router SKILL.md content from a list of skills |
| `lib/elixir_skills/installer.ex` | Rewrite `plan/execute/uninstall`: symlink each library into `<merged>/references/<lib>/`, regenerate router after each mutation, track by library name |
| `lib/elixir_skills/server.ex` | Update tool semantics — `install_skill`/`uninstall_skill` operate on the merged skill |
| `lib/elixir_skills.ex` | Delegate signatures unchanged; docs updated to reflect merged-skill model |
| `lib/mix/tasks/skills.install.ex` | Output per-library plan; print path to merged skill |
| `lib/mix/tasks/skills.uninstall.ex` | Default to removing the whole merged skill; `--library <name>` removes one lib |
| `lib/mix/tasks/skills.list.ex` | List per-library entries (discovered + installed state) |
| `lib/mix/tasks/skills.init.ex` | Scaffold `skills/SKILL.md` (no subdir); remove `<app>--<id>` namespacing in template |
| `mix.exs` | Drop the `compile`/`test` aliases that run `skills.build` (elixir_skills has no library skill to ship) |

### Repo content moves

| From | To |
|------|-----|
| `skills/elixir-lang-ex/SKILL.md` | `priv/bundled_skills/elixir-lang-ex/SKILL.md` |
| `skills/elixir-lang-ex/references/advanced-patterns.md` | `priv/bundled_skills/elixir-lang-ex/references/advanced-patterns.md` |
| `skills/oban-workers/SKILL.md` | `priv/bundled_skills/oban-workers/SKILL.md` |
| `priv/skills/` (compile output) | **Delete** |
| `priv/bundled_skills/oban-workers/` (old path) | Replaced by move above |

### Test files

| File | Change |
|------|--------|
| `test/elixir_skills/skill_test.exs` | Drop namespacing tests |
| `test/elixir_skills/manifest_test.exs` | Rewrite around `parse_library/2` |
| `test/elixir_skills/discovery_test.exs` | Update for single-library-per-dep layout |
| `test/elixir_skills/installer_test.exs` | Rewrite: merged skill, router regeneration, per-library tracking |
| `test/elixir_skills/router_test.exs` | **NEW** |
| `test/elixir_skills/server_test.exs` | Update tool-call expectations |
| `test/fixtures/fake_dep/priv/skills/test-skill/SKILL.md` | Move to `test/fixtures/fake_dep/priv/skills/SKILL.md` |
| `test/fixtures/fake_dep_two/priv/skills/SKILL.md` | **NEW** — second fake dep to exercise multi-library merge |
| `test/fixtures/bundled_skills/test-skill/SKILL.md` | Keep (layout already matches `<lib>/SKILL.md`) |
| `test/fixtures/bundled_skills/unique-bundled/SKILL.md` | Keep |

---

## Task 1: Update `Skill` struct — drop namespacing

**Rationale:** One skill per library under the new model, so `namespaced_id` and `Skill.namespace/2` are dead.

**Files:**
- Modify: `lib/elixir_skills/skill.ex`
- Modify: `test/elixir_skills/skill_test.exs`

- [ ] **Step 1: Update the skill_test.exs to reflect the new struct**

```elixir
defmodule ElixirSkills.SkillTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Skill

  describe "struct" do
    test "requires id, package, source_path" do
      skill = %Skill{
        id: "elixir-lang-ex",
        package: :lang_ex,
        source_path: "/tmp/lang_ex/priv/skills"
      }

      assert skill.id === "elixir-lang-ex"
      assert skill.package === :lang_ex
      assert skill.source_path === "/tmp/lang_ex/priv/skills"
    end

    test "raises when enforced keys missing" do
      assert_raise ArgumentError, fn ->
        struct!(Skill, id: "x")
      end
    end
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/elixir_skills/skill_test.exs`
Expected: compilation or assertion failure (old struct still has `namespaced_id`).

- [ ] **Step 3: Rewrite `lib/elixir_skills/skill.ex`**

```elixir
defmodule ElixirSkills.Skill do
  @moduledoc """
  Represents one library's contribution to the merged `elixir-skills` skill.

  The `id` is the library's logical name (from the `name:` frontmatter field
  in the library's `skills/SKILL.md`) and must be unique across all discovered
  libraries. Each library's `source_path` is the directory containing
  `SKILL.md` and an optional `references/` subdirectory.
  """

  @type mcp_config :: %{type: :tool | :resource | :prompt, name: String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          package: atom(),
          package_version: String.t() | nil,
          description: String.t() | nil,
          source_path: String.t(),
          mcp: mcp_config() | nil,
          source: :library | :bundled | nil
        }

  @enforce_keys [:id, :package, :source_path]
  defstruct [
    :id,
    :package,
    :package_version,
    :description,
    :source_path,
    :mcp,
    :source
  ]
end
```

- [ ] **Step 4: Run test — confirm pass**

Run: `mix test test/elixir_skills/skill_test.exs`
Expected: 2 tests, 0 failures. (Other tests will still be broken — that's fine.)

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/skill.ex test/elixir_skills/skill_test.exs
git commit -m "refactor(skill): drop namespaced_id, one skill per library"
```

---

## Task 2: Rewrite `Manifest` to parse a single library dir

**Rationale:** Under the new model, each `priv/skills/` dir is one library (not a parent of many skills). Manifest needs a single-dir parser.

**Files:**
- Modify: `lib/elixir_skills/manifest.ex`
- Modify: `test/elixir_skills/manifest_test.exs`
- Move: `test/fixtures/fake_dep/priv/skills/test-skill/SKILL.md` → `test/fixtures/fake_dep/priv/skills/SKILL.md`
- Create: `test/fixtures/fake_dep_two/mix.exs` + `test/fixtures/fake_dep_two/priv/skills/SKILL.md`

- [ ] **Step 1: Move existing fixture to the new layout**

```bash
mv test/fixtures/fake_dep/priv/skills/test-skill/SKILL.md test/fixtures/fake_dep/priv/skills/SKILL.md
rmdir test/fixtures/fake_dep/priv/skills/test-skill
```

Update the contents so the `name:` frontmatter reflects the new model (no more package double-dash namespacing):

```markdown
---
name: fake-dep
description: Use when testing elixir_skills functionality
mcp: tool:get_test_skill
---

# Test Skill

This is a test skill for elixir_skills.
```

Write this to `test/fixtures/fake_dep/priv/skills/SKILL.md`.

- [ ] **Step 2: Create a second fake dep for multi-library tests**

Write `test/fixtures/fake_dep_two/mix.exs`:

```elixir
defmodule FakeDepTwo.MixProject do
  use Mix.Project

  def project do
    [app: :fake_dep_two, version: "2.1.0"]
  end
end
```

Write `test/fixtures/fake_dep_two/priv/skills/SKILL.md`:

```markdown
---
name: fake-dep-two
description: Second test library with no references
---

# Fake Dep Two

Body content for the second test library.
```

- [ ] **Step 3: Replace `test/elixir_skills/manifest_test.exs`**

```elixir
defmodule ElixirSkills.ManifestTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Manifest, Skill}

  @fixtures Path.expand("../fixtures", __DIR__)

  describe "parse_library/2" do
    test "returns a Skill for a dir with SKILL.md" do
      path = Path.join(@fixtures, "fake_dep/priv/skills")
      assert {:ok, %Skill{} = skill} = Manifest.parse_library(path, :fake_dep)
      assert skill.id === "fake-dep"
      assert skill.description === "Use when testing elixir_skills functionality"
      assert skill.package === :fake_dep
      assert skill.source_path === path
      assert skill.mcp === %{type: :tool, name: "get_test_skill"}
    end

    test "returns :no_skill when SKILL.md is missing" do
      path = Path.join(@fixtures, "fake_dep_missing")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)

      assert Manifest.parse_library(path, :fake_dep_missing) === :no_skill
    end

    test "returns error when name: frontmatter missing" do
      dir = Path.join(System.tmp_dir!(), "elixir_skills_manifest_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "SKILL.md"), "---\ndescription: no name\n---\nbody")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, msg} = Manifest.parse_library(dir, :broken)
      assert msg =~ "missing 'name:' frontmatter"
    end
  end

  describe "parse_frontmatter/1" do
    test "extracts key: value pairs delimited by ---" do
      source = "---\nname: foo\ndescription: bar\n---\nbody"
      assert {:ok, %{"name" => "foo", "description" => "bar"}} = Manifest.parse_frontmatter(source)
    end

    test "returns empty map when no frontmatter" do
      assert {:ok, %{}} = Manifest.parse_frontmatter("just body")
    end
  end
end
```

- [ ] **Step 4: Run tests — confirm they fail**

Run: `mix test test/elixir_skills/manifest_test.exs`
Expected: compile/undefined-function errors — `Manifest.parse_library/2` doesn't exist yet.

- [ ] **Step 5: Rewrite `lib/elixir_skills/manifest.ex`**

```elixir
defmodule ElixirSkills.Manifest do
  @moduledoc """
  Parses a library's `SKILL.md` file and returns a `Skill` struct.

  A library directory looks like:

      <dir>/
        SKILL.md           # required — YAML frontmatter + body
        references/        # optional
          patterns.md

  The `name:` frontmatter field is the library's logical id; `description:`
  becomes the router catalog entry.
  """

  alias ElixirSkills.Skill

  @type error :: {:error, String.t()}
  @type result :: {:ok, Skill.t()} | :no_skill | error()

  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @doc """
  Parses `<dir>/SKILL.md` and returns a Skill. Returns `:no_skill` when the
  file is absent (not an error — the dir just doesn't host a library skill).
  """
  @spec parse_library(String.t(), atom()) :: result()
  def parse_library(dir, package) do
    skill_md = Path.join(dir, "SKILL.md")

    cond do
      not File.dir?(dir) -> :no_skill
      not File.exists?(skill_md) -> :no_skill
      true -> read_and_build(skill_md, dir, package)
    end
  end

  defp read_and_build(skill_md, dir, package) do
    with {:ok, contents} <- File.read(skill_md),
         {:ok, frontmatter} <- parse_frontmatter(contents),
         {:ok, id} <- fetch_id(frontmatter) do
      skill = %Skill{
        id: id,
        package: package,
        description: frontmatter["description"],
        source_path: dir,
        mcp: parse_mcp_config(frontmatter["mcp"])
      }

      {:ok, skill}
    end
  end

  @doc """
  Extracts YAML frontmatter delimited by `---` lines. Returns `{:ok, map}`;
  empty map when no frontmatter is present.
  """
  @spec parse_frontmatter(String.t()) :: {:ok, map()} | error()
  def parse_frontmatter(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      [_, yaml, _] -> {:ok, parse_yaml(yaml)}
      _ -> {:ok, %{}}
    end
  end

  defp parse_yaml(yaml_string) do
    yaml_string
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^(\w[\w-]*):\s*(.+)$/, String.trim(line)) do
        [_, key, value] -> Map.put(acc, key, String.trim(value))
        _ -> acc
      end
    end)
  end

  defp fetch_id(%{"name" => id}) when is_binary(id) do
    if Regex.match?(@valid_id_pattern, id) do
      {:ok, id}
    else
      {:error, "Invalid 'name:' frontmatter '#{id}': must match [a-z0-9][a-z0-9-]*"}
    end
  end

  defp fetch_id(_), do: {:error, "missing 'name:' frontmatter"}

  defp parse_mcp_config(nil), do: nil

  defp parse_mcp_config(mcp_string) when is_binary(mcp_string) do
    case String.split(mcp_string, ":", parts: 2) do
      [type, name] when type in ["tool", "resource", "prompt"] ->
        %{type: String.to_existing_atom(String.trim(type)), name: String.trim(name)}

      _ ->
        nil
    end
  end

  defp parse_mcp_config(_), do: nil
end
```

- [ ] **Step 6: Run tests — confirm pass**

Run: `mix test test/elixir_skills/manifest_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/elixir_skills/manifest.ex test/elixir_skills/manifest_test.exs test/fixtures
git commit -m "refactor(manifest): parse single library dir, drop multi-skill enumeration"
```

---

## Task 3: Update `Config` — router helpers + drop legacy helpers

**Files:**
- Modify: `lib/elixir_skills/config.ex`
- Modify: `test/elixir_skills/config_test.exs` (create if missing)

- [ ] **Step 1: Add/extend test for router helpers**

Check whether `test/elixir_skills/config_test.exs` exists. If not, create it:

```elixir
defmodule ElixirSkills.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Config

  describe "router_skill_name/0" do
    test "returns the canonical name" do
      assert Config.router_skill_name() === "elixir-skills"
    end
  end

  describe "router_skill_dir/1" do
    test "joins the agent skills dir with the router name" do
      tmp = Path.join(System.tmp_dir!(), "router_dir_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert Config.router_skill_dir(target_dir: tmp) === Path.join(tmp, "elixir-skills")
    end
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

Run: `mix test test/elixir_skills/config_test.exs`
Expected: undefined function errors for `router_skill_name/0` and `router_skill_dir/1`.

- [ ] **Step 3: Extend `lib/elixir_skills/config.ex`**

Add under the `STATIC CONFIG` section:

```elixir
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
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `mix test test/elixir_skills/config_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/config.ex test/elixir_skills/config_test.exs
git commit -m "feat(config): add router_skill_name and router_skill_dir helpers"
```

---

## Task 4: Rewrite `Discovery` to return one skill per library

**Files:**
- Modify: `lib/elixir_skills/discovery.ex`
- Modify: `test/elixir_skills/discovery_test.exs`

- [ ] **Step 1: Replace `test/elixir_skills/discovery_test.exs`**

```elixir
defmodule ElixirSkills.DiscoveryTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Discovery, Skill}

  @fixtures Path.expand("../fixtures", __DIR__)

  describe "scan_dep/2" do
    test "returns one skill for a dep with priv/skills/SKILL.md" do
      dep_path = Path.join(@fixtures, "fake_dep")
      assert {:ok, [%Skill{id: "fake-dep"} = skill]} = Discovery.scan_dep(:fake_dep, dep_path)
      assert skill.source === nil
      # source_path points to the dep's priv/skills dir
      assert skill.source_path === Path.join(dep_path, "priv/skills")
    end

    test "returns empty list for a dep without priv/skills" do
      tmp = Path.join(System.tmp_dir!(), "no_skills_dep_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, []} = Discovery.scan_dep(:empty, tmp)
    end
  end

  describe "scan_bundled/1" do
    test "returns one skill per subdirectory that has SKILL.md" do
      bundled = Path.join(@fixtures, "bundled_skills")
      assert {:ok, skills} = Discovery.scan_bundled(bundled)

      ids = skills |> Enum.map(& &1.id) |> Enum.sort()
      assert "fake-dep" in ids or "test-skill" in ids
      assert Enum.all?(skills, fn s -> s.source === :bundled end)
    end
  end

  describe "merge_with_precedence/2" do
    test "library skills override bundled skills with the same id" do
      lib = %Skill{id: "shared", package: :lang_ex, source_path: "/lib", source: :library}
      bundled_same = %Skill{id: "shared", package: :elixir_skills, source_path: "/bundled", source: :bundled}
      bundled_other = %Skill{id: "only-bundled", package: :elixir_skills, source_path: "/only", source: :bundled}

      merged = Discovery.merge_with_precedence([lib], [bundled_same, bundled_other])
      ids = Enum.map(merged, & &1.id) |> Enum.sort()
      assert ids === ["only-bundled", "shared"]
      assert Enum.find(merged, &(&1.id === "shared")).source === :library
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm failure**

Run: `mix test test/elixir_skills/discovery_test.exs`
Expected: `Discovery.scan_dep/2` now returns `[]` for fake_dep because the old multi-skill scan looks for subdirs with SKILL.md and there aren't any. Or compile error if the old impl references `Manifest.scan/2`.

- [ ] **Step 3: Rewrite `lib/elixir_skills/discovery.ex`**

```elixir
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
  @spec scan(keyword()) :: {:ok, [Skill.t()]} | {:error, String.t()}
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
    library_ids = library_skills |> Enum.map(& &1.id) |> MapSet.new()
    kept_bundled = Enum.reject(bundled_skills, fn %Skill{id: id} -> MapSet.member?(library_ids, id) end)
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
  defp maybe_filter_packages(deps, packages), do: Enum.filter(deps, fn {p, _} -> p in packages end)

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
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `mix test test/elixir_skills/discovery_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/discovery.ex test/elixir_skills/discovery_test.exs
git commit -m "refactor(discovery): one skill per library; baseline scan by lib subdir"
```

---

## Task 5: Create `Router` module

**Rationale:** The router `SKILL.md` is synthesized per install. Extract this into its own module so it's testable in isolation.

**Files:**
- Create: `lib/elixir_skills/router.ex`
- Create: `test/elixir_skills/router_test.exs`

- [ ] **Step 1: Write `test/elixir_skills/router_test.exs`**

```elixir
defmodule ElixirSkills.RouterTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Router, Skill}

  defp skill(id, description) do
    %Skill{id: id, package: :pkg, source_path: "/tmp/#{id}", description: description}
  end

  describe "generate/1" do
    test "starts with YAML frontmatter naming the router" do
      content = Router.generate([skill("lang-ex", "Use when X")])

      assert content =~ ~r/\A---\nname: elixir-skills\n/
      assert content =~ ~r/^description: /m
    end

    test "aggregates each library description into the router description" do
      content =
        Router.generate([
          skill("lang-ex", "Use when building graph-based agents"),
          skill("oban", "Use when running background jobs")
        ])

      assert content =~ "lang-ex"
      assert content =~ "oban"
      # Both description snippets appear
      assert content =~ "graph-based agents"
      assert content =~ "background jobs"
    end

    test "catalog sections link to references/<id>/SKILL.md" do
      content = Router.generate([skill("lang-ex", "Use when X")])
      assert content =~ "references/lang-ex/SKILL.md"
    end

    test "sorts library catalog sections alphabetically by id" do
      content =
        Router.generate([
          skill("zeta", "Z"),
          skill("alpha", "A")
        ])

      alpha_pos = :binary.match(content, "### alpha") |> elem(0)
      zeta_pos = :binary.match(content, "### zeta") |> elem(0)
      assert alpha_pos < zeta_pos
    end

    test "handles empty list with an empty catalog and a neutral description" do
      content = Router.generate([])
      assert content =~ ~r/\A---\nname: elixir-skills\n/
      assert content =~ "No libraries installed yet"
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm failure**

Run: `mix test test/elixir_skills/router_test.exs`
Expected: `(UndefinedFunctionError) ElixirSkills.Router.generate/1`.

- [ ] **Step 3: Write `lib/elixir_skills/router.ex`**

```elixir
defmodule ElixirSkills.Router do
  @moduledoc """
  Synthesizes the router `SKILL.md` for the merged `elixir-skills` skill.

  The router's frontmatter `description:` aggregates a short phrase per library
  so Claude's skill matcher can trigger the router on any of them. The body is
  a catalog that lists each library with a pointer to its
  `references/<id>/SKILL.md`.
  """

  alias ElixirSkills.{Config, Skill}

  @doc """
  Returns the full text of the router `SKILL.md` for the given list of skills.
  """
  @spec generate([Skill.t()]) :: String.t()
  def generate(skills) do
    sorted = Enum.sort_by(skills, & &1.id)

    [
      frontmatter(sorted),
      "\n",
      header(),
      "\n",
      routing_instructions(),
      "\n",
      catalog(sorted)
    ]
    |> IO.iodata_to_binary()
  end

  defp frontmatter([]) do
    """
    ---
    name: #{Config.router_skill_name()}
    description: Elixir skills router (no libraries installed yet).
    ---
    """
  end

  defp frontmatter(skills) do
    summary =
      skills
      |> Enum.map(fn %Skill{id: id, description: desc} -> "#{id} (#{truncate(desc, 80)})" end)
      |> Enum.join(", ")

    """
    ---
    name: #{Config.router_skill_name()}
    description: Use when working with any Elixir library that ships guidance via elixir_skills. Covers: #{summary}.
    ---
    """
  end

  defp header do
    """

    # Elixir Skills Router

    Determine which libraries apply to the current task, then read the matching
    reference file before taking action.
    """
  end

  defp routing_instructions do
    """

    ## How to route

    1. Check the user's prompt for library names/imports listed below.
    2. Check `mix.exs` deps and any open files for imports.
    3. For each matching library, read `references/<lib>/SKILL.md` first;
       consult `references/<lib>/references/*.md` only if the SKILL.md
       points you there.
    """
  end

  defp catalog([]) do
    """

    ## Library catalog

    No libraries installed yet. Add an Elixir dep that ships `skills/SKILL.md`
    and run `mix skills.install`.
    """
  end

  defp catalog(skills) do
    entries =
      skills
      |> Enum.map(fn %Skill{id: id, description: desc} ->
        """
        ### #{id} — `references/#{id}/SKILL.md`
        #{desc || "(no description)"}
        """
      end)
      |> Enum.join("\n")

    """

    ## Library catalog

    #{entries}
    """
  end

  defp truncate(nil, _), do: "no description"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) <= max, do: text, else: String.slice(text, 0, max - 1) <> "…"
  end
end
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `mix test test/elixir_skills/router_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/router.ex test/elixir_skills/router_test.exs
git commit -m "feat(router): synthesize elixir-skills SKILL.md from library catalog"
```

---

## Task 6: Rewrite `Installer` around the merged skill

**Rationale:** Biggest change in the refactor. `plan/execute/uninstall` now operate on entries inside `<target>/elixir-skills/references/` and regenerate the router on every mutation.

**Files:**
- Modify: `lib/elixir_skills/installer.ex`
- Modify: `test/elixir_skills/installer_test.exs`

- [ ] **Step 1: Replace `test/elixir_skills/installer_test.exs`**

```elixir
defmodule ElixirSkills.InstallerTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Installer, Skill}

  @fixtures Path.expand("../fixtures", __DIR__)

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "elixir_skills_installer_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir, opts: [target_dir: tmp_dir]}
  end

  defp make_skill(id, package \\ :fake_dep, version \\ "1.0.0") do
    source = Path.join([@fixtures, "fake_dep", "priv", "skills"])

    %Skill{
      id: id,
      package: package,
      package_version: version,
      description: "Trigger on #{id}",
      source_path: source,
      mcp: nil,
      source: :library
    }
  end

  describe "plan/2" do
    test "marks new libraries as :new", %{opts: opts} do
      skill = make_skill("fake-dep")
      [entry] = Installer.plan([skill], opts)
      assert entry.action === :new
      assert entry.skill.id === "fake-dep"
    end

    test "marks same-version tracked libraries as :unchanged", %{tmp_dir: tmp, opts: opts} do
      skill = make_skill("fake-dep")
      # Pre-install to create the symlink
      {:ok, _} = Installer.execute([%{skill: skill, action: :new, reason: nil}], opts)

      [entry] = Installer.plan([skill], opts)
      assert entry.action === :unchanged
    end

    test "marks version bumps as :update", %{opts: opts} do
      old = make_skill("fake-dep", :fake_dep, "1.0.0")
      {:ok, _} = Installer.execute([%{skill: old, action: :new, reason: nil}], opts)

      new = make_skill("fake-dep", :fake_dep, "2.0.0")
      [entry] = Installer.plan([new], opts)
      assert entry.action === :update
      assert entry.reason =~ "1.0.0 → 2.0.0"
    end
  end

  describe "execute/2" do
    test "creates references/<id> as a symlink and writes router SKILL.md", %{tmp_dir: tmp, opts: opts} do
      skill = make_skill("fake-dep")
      {:ok, result} = Installer.execute([%{skill: skill, action: :new, reason: nil}], opts)

      assert result.installed === ["fake-dep"]

      router_dir = Path.join(tmp, "elixir-skills")
      link = Path.join([router_dir, "references", "fake-dep"])
      assert {:ok, %{type: :symlink}} = File.lstat(link)

      router_md = File.read!(Path.join(router_dir, "SKILL.md"))
      assert router_md =~ "fake-dep"
      assert router_md =~ "name: elixir-skills"
    end

    test "regenerates router when a library is re-installed with copy mode", %{opts: opts} do
      skill = make_skill("fake-dep")

      {:ok, _} =
        Installer.execute(
          [%{skill: skill, action: :new, reason: nil}],
          Keyword.put(opts, :copy, true)
        )

      link = Path.join([opts[:target_dir], "elixir-skills", "references", "fake-dep"])
      assert File.dir?(link)
      assert {:ok, %{type: :directory}} = File.lstat(link)
    end
  end

  describe "uninstall/2" do
    test "removes one library and regenerates router", %{tmp_dir: tmp, opts: opts} do
      skill = make_skill("fake-dep")
      {:ok, _} = Installer.execute([%{skill: skill, action: :new, reason: nil}], opts)

      assert {:ok, ["fake-dep"]} = Installer.uninstall(["fake-dep"], opts)

      refute File.exists?(Path.join([tmp, "elixir-skills", "references", "fake-dep"]))
      # router still exists but with empty catalog
      router_md = File.read!(Path.join([tmp, "elixir-skills", "SKILL.md"]))
      assert router_md =~ "No libraries installed yet"
    end

    test ":all removes the whole merged skill directory", %{tmp_dir: tmp, opts: opts} do
      skill = make_skill("fake-dep")
      {:ok, _} = Installer.execute([%{skill: skill, action: :new, reason: nil}], opts)

      {:ok, removed} = Installer.uninstall(:all, opts)
      assert "fake-dep" in removed
      refute File.exists?(Path.join(tmp, "elixir-skills"))
    end
  end

  describe "read_tracking/1" do
    test "returns map keyed by library id", %{opts: opts} do
      skill = make_skill("fake-dep")
      {:ok, _} = Installer.execute([%{skill: skill, action: :new, reason: nil}], opts)

      tracking = Installer.read_tracking(opts)
      assert Map.has_key?(tracking, "fake-dep")
      assert tracking["fake-dep"]["package"] === "fake_dep"
      assert tracking["fake-dep"]["package_version"] === "1.0.0"
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm failure**

Run: `mix test test/elixir_skills/installer_test.exs`
Expected: many failures/compile errors — old installer still references `namespaced_id`.

- [ ] **Step 3: Rewrite `lib/elixir_skills/installer.ex`**

```elixir
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
        package: String.to_atom(meta["package"]),
        package_version: meta["package_version"],
        description: meta["description"],
        source_path: meta["source_path"]
      }
    end)
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
      |> Enum.map(fn %{skill: s} -> {s.id, s} end)
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
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `mix test test/elixir_skills/installer_test.exs`
Expected: 8 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/installer.ex test/elixir_skills/installer_test.exs
git commit -m "refactor(installer): merged-skill layout with symlinked references and router regen"
```

---

## Task 7: Update MCP server tool semantics

**Files:**
- Modify: `lib/elixir_skills/server.ex`
- Modify: `test/elixir_skills/server_test.exs`

- [ ] **Step 1: Read current server test to understand the shape**

Run: `mix test test/elixir_skills/server_test.exs --trace` (expect baseline failures from earlier tasks; goal is to see existing test names).

- [ ] **Step 2: Rewrite `test/elixir_skills/server_test.exs`**

```elixir
defmodule ElixirSkills.ServerTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Server

  describe "handle_tool_call/3 — list_skills" do
    test "returns an array of library entries with installed flag" do
      frame = %{}
      {:reply, response, ^frame} = Server.handle_tool_call("list_skills", %{}, frame)
      text = text_of(response)

      assert {:ok, [entry | _]} = Jason.decode(text)
      assert Map.has_key?(entry, "id")
      assert Map.has_key?(entry, "installed")
      refute Map.has_key?(entry, "namespaced_id")
    end
  end

  describe "handle_tool_call/3 — get_skill" do
    test "accepts a plain library id" do
      frame = %{}
      {:reply, _, ^frame} = Server.handle_tool_call("get_skill", %{"skill_id" => "does-not-exist"}, frame)
    end
  end

  defp text_of(%Hermes.Server.Response{content: [%{"text" => text}]}), do: text
  defp text_of(other), do: inspect(other)
end
```

(If the existing `server_test.exs` has richer fixtures, preserve anything still valid and only change the assertions that reference `namespaced_id`. Treat the snippet above as the minimum.)

- [ ] **Step 3: Rewrite the `server.ex` tool handlers**

Update three things:

1. The `list_skills` output maps over `skill.id` instead of `skill.namespaced_id`.
2. The `install_skill`/`uninstall_skill` tools take `skill_id` but treat it as the **library id** and operate on the merged skill.
3. The input_schema `skill_id` descriptions change to say "Library id (from SKILL.md `name:` frontmatter)" — drop the `package--skill` framing.

Full file (replace existing):

```elixir
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
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `mix test test/elixir_skills/server_test.exs`
Expected: tests pass (they're minimal smoke tests; richer integration tests can come later).

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_skills/server.ex test/elixir_skills/server_test.exs
git commit -m "refactor(server): library-id semantics for install/uninstall tools"
```

---

## Task 8: Update the four Mix tasks

**Files:**
- Modify: `lib/mix/tasks/skills.install.ex`
- Modify: `lib/mix/tasks/skills.uninstall.ex`
- Modify: `lib/mix/tasks/skills.list.ex`
- Modify: `lib/mix/tasks/skills.init.ex`

No dedicated unit tests for mix tasks (they're integration-shaped); manual verification at the end.

- [ ] **Step 1: Update `skills.install.ex`**

Changes:
- Drop references to `namespaced_id`; use `skill.id`.
- In the success message, report the single merged-skill path per agent instead of per-skill paths.
- Keep `-g`, `--agent`, `--copy`, `--force` flags.

Read the current file and rewrite it so the core block looks like:

```elixir
{:ok, skills} = Discovery.scan()
plan = Installer.plan(skills, opts)

{:ok, %{installed: installed, skipped: skipped}} = Installer.execute(plan, opts)

Mix.shell().info("Installed libraries into merged skill:")
Enum.each(Config.skills_target_dirs(opts), fn dir ->
  Mix.shell().info("  #{Path.join(dir, Config.router_skill_name())}")
end)

Enum.each(installed, fn id -> Mix.shell().info("  + #{id}") end)
Enum.each(skipped, fn id -> Mix.shell().info("  = #{id} (unchanged)") end)
```

- [ ] **Step 2: Update `skills.uninstall.ex`**

Default behavior: remove the whole merged skill (`Installer.uninstall(:all, opts)`).
With `--library <id>`: remove just one library.

```elixir
{opts_args, _, _} =
  OptionParser.parse(args,
    strict: [global: :boolean, agent: :string, library: :string]
  )

opts = [
  global: Keyword.get(opts_args, :global, false),
  agents: agents_opt(opts_args)
]

target = Keyword.get(opts_args, :library)

result =
  case target do
    nil -> Installer.uninstall(:all, opts)
    id -> Installer.uninstall([id], opts)
  end

{:ok, removed} = result
Mix.shell().info("Removed: #{Enum.join(removed, ", ")}")
```

(Helper `agents_opt/1` same as in `skills.install`.)

- [ ] **Step 3: Update `skills.list.ex`**

Output rows per library with its installed state:

```elixir
{:ok, skills} = Discovery.scan()
tracking = Installer.read_tracking(opts)

Enum.each(skills, fn skill ->
  installed = if Map.has_key?(tracking, skill.id), do: "installed", else: "available"
  Mix.shell().info("#{skill.id}  [#{installed}]  (#{skill.package} #{skill.package_version || ""})")
  Mix.shell().info("    #{skill.description}")
end)
```

- [ ] **Step 4: Update `skills.init.ex`**

Target is `skills/SKILL.md` (single file, no subdir). Drop `<app>--<id>` namespacing; use a user-supplied id that matches the `name:` field.

```elixir
defmodule Mix.Tasks.Skills.Init do
  @shortdoc "Scaffolds a single SKILL.md in the project's skills/ directory"
  @moduledoc """
  Creates `skills/SKILL.md` in the current project with a frontmatter template.

      $ mix skills.init my-library-id
      $ mix skills.init my-library-id --mcp-type tool

  The `skills/` directory ships with your hex package (copied to `priv/skills/`
  by the compile alias) and is the single source of truth for your library's
  agent guidance.

  ## Options

    - `--mcp-type` — register the skill as an MCP component: tool, resource, prompt
  """

  use Mix.Task

  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [mcp_type: :string])

    case positional do
      [id] ->
        if Regex.match?(@valid_id_pattern, id) do
          create_skill(id, opts)
        else
          Mix.shell().error("Invalid library id '#{id}': must match [a-z0-9][a-z0-9-]*")
        end

      [] -> Mix.shell().error("Usage: mix skills.init <library-id>")
      _ -> Mix.shell().error("Expected exactly one library id argument.")
    end
  end

  defp create_skill(id, opts) do
    skill_md = Path.join("skills", "SKILL.md")

    if File.exists?(skill_md) do
      Mix.shell().info("#{skill_md} already exists, skipping.")
    else
      File.mkdir_p!("skills")
      File.write!(skill_md, template(id, opts))
      Mix.shell().info("Created #{skill_md}. Edit it to add your skill content.")
    end
  end

  defp template(id, opts) do
    mcp_line =
      case opts[:mcp_type] do
        nil -> ""
        type -> "mcp: #{type}:#{id}\n"
      end

    """
    ---
    name: #{id}
    description: Use when working with #{id} — TODO
    #{mcp_line}---

    # #{id |> String.replace("-", " ") |> String.capitalize()}

    TODO: Add library guidance here. Optional deep-dive references belong in `skills/references/<topic>.md`.
    """
  end
end
```

- [ ] **Step 5: Run the whole test suite**

Run: `mix test`
Expected: everything green.

- [ ] **Step 6: Commit**

```bash
git add lib/mix/tasks/skills.install.ex lib/mix/tasks/skills.uninstall.ex lib/mix/tasks/skills.list.ex lib/mix/tasks/skills.init.ex
git commit -m "refactor(mix tasks): align with merged-skill layout"
```

---

## Task 9: Migrate this repo's baselines and drop the local compile alias

**Rationale:** elixir_skills itself no longer ships a `skills/` directory; baselines for other libraries live under `priv/bundled_skills/<lib>/`.

**Files:**
- Move: `skills/elixir-lang-ex/**` → `priv/bundled_skills/elixir-lang-ex/**`
- Move: `skills/oban-workers/**` → `priv/bundled_skills/oban-workers/**`
- Delete: `priv/skills/` (was the compile output)
- Modify: `mix.exs` — drop the aliases function contents

- [ ] **Step 1: Move content**

```bash
mkdir -p priv/bundled_skills
mv skills/elixir-lang-ex priv/bundled_skills/elixir-lang-ex
mv skills/oban-workers priv/bundled_skills/oban-workers
rmdir skills
rm -rf priv/skills
```

- [ ] **Step 2: Update frontmatter names**

Both baseline SKILL.md files currently use namespaced ids (e.g. `elixir_skills--oban-workers`). Rewrite each `name:` to match the library (`oban-workers`, `elixir-lang-ex`).

`priv/bundled_skills/elixir-lang-ex/SKILL.md` header:

```markdown
---
name: elixir-lang-ex
description: Use when building graph-based agent orchestration, stateful multi-step LLM workflows, AI agent pipelines, or any system using the lang_ex library (LangGraph for Elixir). Trigger whenever the user mentions lang_ex, LangEx, LangGraph, graph-based agents, agent orchestration, StateGraph, conditional routing, human-in-the-loop workflows, tool-calling agents, checkpointing agent state, or building multi-step AI workflows in Elixir. Also trigger when you see imports of LangEx.Graph, LangEx.ChatModel, LangEx.ToolNode, or LangEx.Interrupt in existing code.
---
```

`priv/bundled_skills/oban-workers/SKILL.md` header:

```markdown
---
name: oban-workers
description: Use when implementing Oban background workers (bundled fallback)
---
```

- [ ] **Step 3: Simplify `mix.exs` aliases**

Replace the `aliases/0` function with:

```elixir
defp aliases, do: []
```

(Elixir_skills has no `skills/` to build. The `skills.build` task remains available for consuming libraries, just not wired into elixir_skills's own compile.)

- [ ] **Step 4: Run the full test suite**

Run: `mix test`
Expected: green. (Discovery baseline scan now reads `priv/bundled_skills/` directly.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: move baselines to priv/bundled_skills, drop local skills/ and compile alias"
```

---

## Task 10: Update top-level module and docs

**Files:**
- Modify: `lib/elixir_skills.ex`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Rewrite `lib/elixir_skills.ex` module doc**

Replace the `@moduledoc` body with the merged-skill explanation (authoring flow unchanged; install flow now produces one merged skill per agent). Keep delegate function signatures as-is — their names still map.

Target `@moduledoc`:

```elixir
@moduledoc """
Standardized skill bundling for Elixir hex packages.

`elixir_skills` lets hex package authors ship one agent skill per library
and installs them as a single merged `elixir-skills` skill per agent. Each
library's content appears under `references/<library-id>/` inside that
merged skill; the top-level `SKILL.md` is a generated router that points
the agent to the right library for the current task.

## For library authors

1. Run `mix skills.init my-library-id` to scaffold `skills/SKILL.md` at
   your project root.
2. Optional: add deeper guidance in `skills/references/<topic>.md`.
3. `mix compile` copies `skills/` → `priv/skills/` so the content ships
   with your hex package.

## For consumers

1. Add `{:elixir_skills, "~> 0.2.0"}` to your deps.
2. `mix skills.list` shows every discovered library.
3. `mix skills.install` creates
   `.claude/skills/elixir-skills/` (mirrored across any detected agent
   dotdirs) with a symlink per library and a generated router SKILL.md.
4. `mix skills.install -g` installs into `~/.<agent>/skills/` instead.

## MCP server

    mix skills.server              # stdio
    mix skills.server --http 4242  # streamable HTTP
"""
```

- [ ] **Step 2: Rewrite README.md**

Write `README.md`:

````markdown
# ElixirSkills

Ship agent guidance alongside your Elixir hex package. `elixir_skills` scans
your deps for `priv/skills/SKILL.md` files and installs them as a single
merged `elixir-skills` skill under each detected agent's skills directory.

## Authoring a skill for your library

```
your_package/
└── skills/
    ├── SKILL.md                 # required — YAML frontmatter + body
    └── references/              # optional
        └── patterns.md
```

`SKILL.md` frontmatter:

```markdown
---
name: your-library-id
description: Use when … (broad trigger keywords go here)
---

# Your Library

Guidance for agents working with your-library.
```

A compile alias (`mix skills.build`) copies `skills/` into `priv/skills/` so
the files ship with your hex package.

## Installation (consumers)

```elixir
def deps do
  [
    {:elixir_skills, "~> 0.2.0"}
  ]
end
```

Then:

```
$ mix skills.list
$ mix skills.install          # project-local .claude/skills/
$ mix skills.install -g       # user-global ~/.claude/skills/
$ mix skills.install --agent cursor
```

Output per agent:

```
.claude/skills/elixir-skills/
├── SKILL.md                 # generated router
└── references/
    ├── your-library-id/     # symlink to the dep's priv/skills
    ├── lang-ex/
    └── …
```

## MCP server

```
$ mix skills.server               # stdio
$ mix skills.server --http 4242   # streamable HTTP
```

Exposed tools: `list_skills`, `get_skill`, `install_skill`, `uninstall_skill`
— all keyed by library id.

## License

MIT.
````

- [ ] **Step 3: Add CHANGELOG entry**

Prepend to `CHANGELOG.md`:

```markdown
## 0.2.0 (2026-04-16)

### Changed

- **BREAKING:** `mix skills.install` now produces a single merged `elixir-skills` skill per agent (`<agent>/skills/elixir-skills/`) instead of one skill directory per library. Library content is symlinked under `references/<library-id>/`.
- **BREAKING:** library authors now ship a single `skills/SKILL.md` (+ optional `skills/references/`) instead of one subdirectory per skill. The `name:` frontmatter field is the library id; `package--skill` namespacing is gone.
- `Skill` struct lost `namespaced_id`; `id` is now the library id.
- Tracking file key format: library ids (`"libraries"` top-level key). Legacy `"skills"` key read for one-version migration.
- Mix task renames preserved; `skills.init` produces the new single-file layout.

### Added

- `ElixirSkills.Router` — synthesizes the router SKILL.md.
- `Config.router_skill_name/0`, `Config.router_skill_dir/1`.

### Removed

- `ElixirSkills.Skill.namespace/2` and `namespaced_id` field.
- `ElixirSkills.Manifest.scan/2` and `parse_skill/4` (replaced by `parse_library/2`).
- `skills/` directory in the `elixir_skills` repo (baselines moved to `priv/bundled_skills/<lib>/`).
```

- [ ] **Step 4: Run the full quality gate**

Run: `mix test && mix credo --strict`
Expected: both green (fix any warnings/credo violations immediately; do not suppress).

- [ ] **Step 5: Manual smoke test**

From this repo's root:

```
rm -rf .claude
mix skills.install
```

Expected: `.claude/skills/elixir-skills/SKILL.md` exists; `.claude/skills/elixir-skills/references/oban-workers` and `.claude/skills/elixir-skills/references/elixir-lang-ex` are symlinks into `priv/bundled_skills/`.

```
cat .claude/skills/elixir-skills/SKILL.md | head -30
```

Expected: frontmatter lists both library ids in the aggregated description, body has catalog sections for each.

```
mix skills.uninstall --library oban-workers
```

Expected: `.claude/skills/elixir-skills/references/oban-workers` removed; router regenerated without it.

```
mix skills.uninstall
```

Expected: `.claude/skills/elixir-skills/` removed entirely.

- [ ] **Step 6: Commit**

```bash
git add lib/elixir_skills.ex README.md CHANGELOG.md
git commit -m "docs: README, moduledoc, and CHANGELOG for single-skill router model"
```

---

## Self-Review

**Spec coverage:**
- Authoring format (`skills/SKILL.md` + optional `skills/references/`): Tasks 2, 4, 8 (skills.init), 9.
- Install output (merged skill with symlinked refs, generated router): Tasks 5, 6.
- Tracking keyed by library id: Task 6.
- Router aggregation rules: Task 5.
- Mix tasks (install / uninstall / list / init): Task 8.
- MCP server semantics: Task 7.
- Out-of-scope items (no runtime MCP call for routing, compile alias unchanged for consumers): honored throughout.
- Migration for existing authors (no compat shim): Task 9.
- Risks (symlink fallback to copy): preserved via `:copy` option in Installer and server.

**Placeholder scan:** No TBD/TODO in the code blocks. Every code step shows the concrete code to write.

**Type consistency:**
- `Skill.t()` used consistently; `id` (not `namespaced_id`) everywhere after Task 1.
- `Installer.plan/2` → `Installer.execute/2` → `Installer.read_tracking/1` argument shapes stable.
- `Router.generate/1` accepts `[Skill.t()]`; installer calls it with `tracking_to_skills(tracking)` which returns the same type.
- Tracking-file shape: outer `"libraries"` key + inner per-library metadata map — matches `update_tracking_for_installed` and `read_tracking`.
- `Config.router_skill_dir/1` and `references_dir/1` chain: `skills_target_dir → router_skill_dir → references_dir`. Consistent across installer and server.

No gaps identified.
