# Bundled Fallback Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow elixir_mcp to ship a `skills/` directory at the project root containing fallback skills for libraries that don't bundle their own. Library-provided skills always take precedence over bundled fallbacks.

**Architecture:** Discovery gets a new source: the bundled `skills/` directory. Skills from both sources merge with a precedence rule — if a library ships a skill with the same base ID, the library's version wins. Bundled skills use a `default--` namespace prefix to distinguish them from library skills.

**Tech Stack:** Elixir, Jason, Hermes MCP (existing deps)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `skills/` (project root) | Create | Directory holding fallback SKILL.md dirs |
| `skills/manifest.json` | Create | Manifest for bundled fallback skills |
| `lib/elixir_mcp/config.ex` | Modify | Add `bundled_skills_dir/0` config |
| `lib/elixir_mcp/discovery.ex` | Modify | Add `scan_bundled/0`, merge with precedence in `scan/1` |
| `lib/elixir_mcp/skill.ex` | Modify | Add `:source` field (`:bundled` or `:library`) to struct |
| `test/elixir_mcp/discovery_test.exs` | Create | Test bundled discovery + precedence |
| `test/fixtures/bundled_skills/manifest.json` | Create | Test fixture for bundled skills |
| `test/fixtures/bundled_skills/oban-workers/SKILL.md` | Create | Test fixture skill |

---

### Task 1: Add `:source` field to Skill struct

**Files:**
- Modify: `lib/elixir_mcp/skill.ex`
- Test: `test/elixir_mcp/skill_test.exs`

- [ ] **Step 1: Write failing test for source field**

```elixir
# In test/elixir_mcp/skill_test.exs, add:

test "skill struct includes source field" do
  skill = %Skill{
    id: "test",
    namespaced_id: "pkg--test",
    package: :pkg,
    source_path: "/tmp",
    source: :library
  }

  assert skill.source === :library
end

test "source defaults to nil" do
  skill = %Skill{
    id: "test",
    namespaced_id: "pkg--test",
    package: :pkg,
    source_path: "/tmp"
  }

  assert is_nil(skill.source)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/elixir_mcp/skill_test.exs -v`
Expected: compilation error — `:source` not a valid key

- [ ] **Step 3: Add `:source` field to Skill struct**

In `lib/elixir_mcp/skill.ex`, add `:source` to the struct fields and type:

```elixir
@type t :: %__MODULE__{
        id: String.t(),
        namespaced_id: String.t(),
        package: atom(),
        package_version: String.t() | nil,
        description: String.t(),
        source_path: String.t(),
        mcp: mcp_config() | nil,
        source: :library | :bundled | nil
      }

defstruct [
  :id,
  :namespaced_id,
  :package,
  :package_version,
  :description,
  :source_path,
  :mcp,
  :source
]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/elixir_mcp/skill_test.exs -v`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_mcp/skill.ex test/elixir_mcp/skill_test.exs
git commit -m "feat: add :source field to Skill struct for precedence tracking"
```

---

### Task 2: Add bundled skills config

**Files:**
- Modify: `lib/elixir_mcp/config.ex`

- [ ] **Step 1: Add `bundled_skills_dir/0` to Config**

In `lib/elixir_mcp/config.ex`, add:

```elixir
@doc "Directory containing bundled fallback skills shipped with elixir_mcp."
@spec bundled_skills_dir() :: String.t()
def bundled_skills_dir do
  Application.get_env(:elixir_mcp, :bundled_skills_dir, default_bundled_skills_dir())
end

defp default_bundled_skills_dir do
  Application.app_dir(:elixir_mcp, "priv/bundled_skills")
end
```

Note: We use `priv/bundled_skills` (inside priv/) because `priv/` is the only directory guaranteed to be available at runtime for OTP applications. The user-facing `skills/` directory at the project root gets copied into `priv/bundled_skills/` during the build. We also need a `@bundled_package` config:

```elixir
@bundled_package :elixir_mcp

@doc "The package atom used for bundled fallback skills."
@spec bundled_package() :: atom()
def bundled_package, do: @bundled_package
```

- [ ] **Step 2: Run existing tests to verify no regressions**

Run: `mix test`
Expected: all 25 pass

- [ ] **Step 3: Commit**

```bash
git add lib/elixir_mcp/config.ex
git commit -m "feat: add bundled_skills_dir config for fallback skills"
```

---

### Task 3: Create bundled skills directory and fixture

**Files:**
- Create: `priv/bundled_skills/manifest.json`
- Create: `priv/bundled_skills/oban-workers/SKILL.md` (example fallback)
- Create: `test/fixtures/bundled_skills/manifest.json`
- Create: `test/fixtures/bundled_skills/oban-workers/SKILL.md`

- [ ] **Step 1: Create the priv/bundled_skills structure**

Create `priv/bundled_skills/manifest.json`:

```json
{
  "schema_version": 1,
  "skills": [
    {
      "id": "oban-workers",
      "description": "Use when implementing Oban background workers (fallback — install oban's own skill for the authoritative version)"
    }
  ]
}
```

Create `priv/bundled_skills/oban-workers/SKILL.md`:

```markdown
---
name: elixir_mcp--oban-workers
description: Use when implementing Oban background workers (bundled fallback)
---

# Oban Workers (Bundled Fallback)

This is a bundled fallback skill. If the `oban` package ships its own skill,
that version will take precedence over this one.

## Basic Worker Pattern

<!-- Minimal useful guidance here -->
```

- [ ] **Step 2: Create test fixture with same structure**

Create `test/fixtures/bundled_skills/manifest.json`:

```json
{
  "schema_version": 1,
  "skills": [
    {
      "id": "test-skill",
      "description": "Bundled fallback for test-skill"
    },
    {
      "id": "unique-bundled",
      "description": "Only exists in bundled, no library version"
    }
  ]
}
```

Create `test/fixtures/bundled_skills/test-skill/SKILL.md`:

```markdown
---
name: elixir_mcp--test-skill
description: Bundled fallback test skill
---

# Bundled fallback content
```

Create `test/fixtures/bundled_skills/unique-bundled/SKILL.md`:

```markdown
---
name: elixir_mcp--unique-bundled
description: A skill only in bundled defaults
---

# Unique bundled skill
```

- [ ] **Step 3: Commit**

```bash
git add priv/bundled_skills test/fixtures/bundled_skills
git commit -m "feat: add bundled fallback skills directory and test fixtures"
```

---

### Task 4: Add `scan_bundled/1` to Discovery

**Files:**
- Modify: `lib/elixir_mcp/discovery.ex`
- Create: `test/elixir_mcp/discovery_test.exs`

- [ ] **Step 1: Write failing test for scan_bundled**

Create `test/elixir_mcp/discovery_test.exs`:

```elixir
defmodule ElixirMcp.DiscoveryTest do
  use ExUnit.Case, async: true

  alias ElixirMcp.{Discovery, Skill}

  @bundled_path Path.expand("../fixtures/bundled_skills", __DIR__)

  describe "scan_bundled/1" do
    test "discovers skills from bundled directory" do
      {:ok, skills} = Discovery.scan_bundled(@bundled_path)
      assert length(skills) === 2

      ids = Enum.map(skills, & &1.id)
      assert "test-skill" in ids
      assert "unique-bundled" in ids
    end

    test "marks skills with source: :bundled" do
      {:ok, [skill | _]} = Discovery.scan_bundled(@bundled_path)
      assert skill.source === :bundled
    end

    test "uses elixir_mcp as package name" do
      {:ok, [skill | _]} = Discovery.scan_bundled(@bundled_path)
      assert skill.package === :elixir_mcp
    end

    test "namespaces with elixir_mcp prefix" do
      {:ok, skills} = Discovery.scan_bundled(@bundled_path)
      namespaced = Enum.map(skills, & &1.namespaced_id)
      assert "elixir_mcp--test-skill" in namespaced
      assert "elixir_mcp--unique-bundled" in namespaced
    end

    test "returns error for nonexistent directory" do
      assert {:error, _} = Discovery.scan_bundled("/nonexistent/path")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/elixir_mcp/discovery_test.exs -v`
Expected: FAIL — `scan_bundled/1` not defined

- [ ] **Step 3: Implement scan_bundled/1**

In `lib/elixir_mcp/discovery.ex`, add:

```elixir
@doc """
Scans a bundled skills directory for fallback skills.
These are skills shipped with elixir_mcp for libraries that don't bundle their own.
"""
@spec scan_bundled(String.t()) :: {:ok, [Skill.t()]} | {:error, String.t()}
def scan_bundled(bundled_dir \\ Config.bundled_skills_dir()) do
  manifest_path = Path.join(bundled_dir, Config.manifest_filename())

  if File.exists?(manifest_path) do
    with {:ok, skills} <- Manifest.parse(manifest_path, Config.bundled_package(), bundled_dir) do
      skills = Enum.map(skills, fn %Skill{} = skill -> %Skill{skill | source: :bundled} end)
      {:ok, skills}
    end
  else
    {:error, "No bundled skills manifest at #{manifest_path}"}
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/elixir_mcp/discovery_test.exs -v`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_mcp/discovery.ex test/elixir_mcp/discovery_test.exs
git commit -m "feat: add scan_bundled/1 for discovering fallback skills"
```

---

### Task 5: Add precedence merging to `scan/1`

**Files:**
- Modify: `lib/elixir_mcp/discovery.ex`
- Modify: `test/elixir_mcp/discovery_test.exs`

- [ ] **Step 1: Write failing test for precedence**

Add to `test/elixir_mcp/discovery_test.exs`:

```elixir
describe "merge_with_precedence/2" do
  test "library skills override bundled skills with same base ID" do
    library_skill = %Skill{
      id: "test-skill",
      namespaced_id: "fake_dep--test-skill",
      package: :fake_dep,
      source_path: "/lib/path",
      source: :library
    }

    bundled_skill = %Skill{
      id: "test-skill",
      namespaced_id: "elixir_mcp--test-skill",
      package: :elixir_mcp,
      source_path: "/bundled/path",
      source: :bundled
    }

    merged = Discovery.merge_with_precedence([library_skill], [bundled_skill])

    assert length(merged) === 1
    assert hd(merged).source === :library
    assert hd(merged).package === :fake_dep
  end

  test "bundled skills included when no library provides same base ID" do
    library_skill = %Skill{
      id: "other-skill",
      namespaced_id: "fake_dep--other-skill",
      package: :fake_dep,
      source_path: "/lib/path",
      source: :library
    }

    bundled_skill = %Skill{
      id: "unique-bundled",
      namespaced_id: "elixir_mcp--unique-bundled",
      package: :elixir_mcp,
      source_path: "/bundled/path",
      source: :bundled
    }

    merged = Discovery.merge_with_precedence([library_skill], [bundled_skill])

    assert length(merged) === 2
    ids = Enum.map(merged, & &1.id)
    assert "other-skill" in ids
    assert "unique-bundled" in ids
  end

  test "multiple libraries can override different bundled skills" do
    lib_a = %Skill{id: "auth", namespaced_id: "lib_a--auth", package: :lib_a, source_path: "/a", source: :library}
    lib_b = %Skill{id: "cache", namespaced_id: "lib_b--cache", package: :lib_b, source_path: "/b", source: :library}
    bundled_auth = %Skill{id: "auth", namespaced_id: "elixir_mcp--auth", package: :elixir_mcp, source_path: "/c", source: :bundled}
    bundled_cache = %Skill{id: "cache", namespaced_id: "elixir_mcp--cache", package: :elixir_mcp, source_path: "/d", source: :bundled}
    bundled_extra = %Skill{id: "extra", namespaced_id: "elixir_mcp--extra", package: :elixir_mcp, source_path: "/e", source: :bundled}

    merged = Discovery.merge_with_precedence([lib_a, lib_b], [bundled_auth, bundled_cache, bundled_extra])

    assert length(merged) === 3
    sources = merged |> Enum.map(& {&1.id, &1.source}) |> Map.new()
    assert sources["auth"] === :library
    assert sources["cache"] === :library
    assert sources["extra"] === :bundled
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/elixir_mcp/discovery_test.exs -v`
Expected: FAIL — `merge_with_precedence/2` not defined

- [ ] **Step 3: Implement merge_with_precedence/2**

In `lib/elixir_mcp/discovery.ex`, add:

```elixir
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/elixir_mcp/discovery_test.exs -v`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_mcp/discovery.ex test/elixir_mcp/discovery_test.exs
git commit -m "feat: add merge_with_precedence/2 for library > bundled ordering"
```

---

### Task 6: Wire bundled skills into `scan/1`

**Files:**
- Modify: `lib/elixir_mcp/discovery.ex`
- Modify: `test/elixir_mcp/discovery_test.exs`

- [ ] **Step 1: Write failing test for integrated scan**

Add to `test/elixir_mcp/discovery_test.exs`:

```elixir
describe "scan/1 with bundled_skills_dir option" do
  test "includes bundled skills when configured" do
    {:ok, skills} = Discovery.scan(bundled_skills_dir: @bundled_path)
    bundled = Enum.filter(skills, fn s -> s.source === :bundled end)
    refute Enum.empty?(bundled)
  end

  test "excludes bundled skills when no dir configured and default missing" do
    {:ok, skills} = Discovery.scan(bundled_skills_dir: "/nonexistent")
    bundled = Enum.filter(skills, fn s -> s.source === :bundled end)
    assert Enum.empty?(bundled)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/elixir_mcp/discovery_test.exs:"scan/1 with bundled" -v`
Expected: FAIL — scan doesn't accept or use `:bundled_skills_dir`

- [ ] **Step 3: Modify scan/1 to include bundled skills**

Update the `scan/1` function in `lib/elixir_mcp/discovery.ex`:

```elixir
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
        {:error, _} -> {:ok, acc}
      end
    end)

  with {:ok, library_skills} <- library_result do
    library_skills = Enum.map(library_skills, fn %Skill{} = s -> %Skill{s | source: :library} end)

    bundled_skills =
      case scan_bundled(bundled_dir) do
        {:ok, skills} -> skills
        {:error, _} -> []
      end

    {:ok, merge_with_precedence(library_skills, bundled_skills)}
  end
end
```

- [ ] **Step 4: Run ALL tests to verify nothing broke**

Run: `mix test -v`
Expected: all pass (existing tests may need minor tweaks if they relied on `source` being nil)

- [ ] **Step 5: Commit**

```bash
git add lib/elixir_mcp/discovery.ex test/elixir_mcp/discovery_test.exs
git commit -m "feat: wire bundled fallback skills into scan/1 with precedence"
```

---

### Task 7: Update MCP server and Mix tasks for source visibility

**Files:**
- Modify: `lib/elixir_mcp/server.ex`
- Modify: `lib/mix/tasks/claude_skills.list.ex`

- [ ] **Step 1: Update server list_skills to include source**

In `lib/elixir_mcp/server.ex`, in the `handle_tool_call("list_skills", ...)` function, add `source` to the result map:

```elixir
%{
  id: skill.namespaced_id,
  package: to_string(skill.package),
  version: skill.package_version,
  description: skill.description,
  installed: installed?,
  has_mcp: not is_nil(skill.mcp),
  source: to_string(skill.source || :library)
}
```

- [ ] **Step 2: Update Mix task list to show source**

In `lib/mix/tasks/claude_skills.list.ex`, update the header and row in `list_available/1`:

```elixir
Mix.shell().info(pad("PACKAGE", 20) <> pad("SKILL ID", 30) <> pad("SOURCE", 10) <> pad("STATUS", 12) <> "DESCRIPTION")
Mix.shell().info(String.duplicate("-", 100))

Enum.each(skills, fn skill ->
  status = if Map.has_key?(tracking, skill.namespaced_id), do: "[installed]", else: "[available]"
  source = to_string(skill.source || :library)
  desc = truncate(skill.description || "(no description)", 35)

  Mix.shell().info(
    pad(to_string(skill.package), 20) <>
      pad(skill.namespaced_id, 30) <>
      pad(source, 10) <>
      pad(status, 12) <>
      desc
  )
end)
```

- [ ] **Step 3: Run tests**

Run: `mix test -v`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add lib/elixir_mcp/server.ex lib/mix/tasks/claude_skills.list.ex
git commit -m "feat: show skill source (library/bundled) in list output and MCP tools"
```

---

### Task 8: Verify full integration

- [ ] **Step 1: Run full test suite**

Run: `mix test -v`
Expected: all pass, zero warnings

- [ ] **Step 2: Compile with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: clean compile

- [ ] **Step 3: Manual smoke test**

Run: `mix claude_skills.list`
Expected: shows bundled skills (with source "bundled") alongside any library skills

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "chore: fixups from integration verification"
```
