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

    test "returns :no_skill when dir does not exist" do
      assert Manifest.parse_library("/nonexistent/elixir_skills_path", :ghost) === :no_skill
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
