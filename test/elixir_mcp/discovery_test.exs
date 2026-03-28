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

  describe "scan/1 with bundled_skills_dir option" do
    test "includes bundled skills when configured" do
      {:ok, skills} = Discovery.scan(bundled_skills_dir: @bundled_path)
      bundled = Enum.filter(skills, fn s -> s.source === :bundled end)
      refute Enum.empty?(bundled)
    end

    test "excludes bundled skills when dir does not exist" do
      {:ok, skills} = Discovery.scan(bundled_skills_dir: "/nonexistent")
      bundled = Enum.filter(skills, fn s -> s.source === :bundled end)
      assert Enum.empty?(bundled)
    end
  end

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
end
