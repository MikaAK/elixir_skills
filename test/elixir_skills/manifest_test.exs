defmodule ElixirSkills.ManifestTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Manifest

  @fixtures_path Path.expand("../fixtures", __DIR__)
  @base_path Path.join([@fixtures_path, "fake_dep", "priv", "skills"])

  describe "scan/2" do
    test "discovers skills from directory structure" do
      assert {:ok, [skill]} = Manifest.scan(@base_path, :fake_dep)
      assert skill.id === "test-skill"
      assert skill.namespaced_id === "fake_dep--test-skill"
      assert skill.package === :fake_dep
      assert skill.description === "Use when testing elixir_skills functionality"
      assert skill.source_path === Path.join(@base_path, "test-skill")
      assert skill.mcp === %{type: :tool, name: "get_test_skill"}
    end

    test "returns error for nonexistent directory" do
      assert {:error, _} = Manifest.scan("/nonexistent/path", :fake)
    end

    test "skips directories without SKILL.md" do
      tmp = make_tmp_dir()
      File.mkdir_p!(Path.join(tmp, "no-skill-md"))

      assert {:ok, []} = Manifest.scan(tmp, :test)
    end

    test "skips directories with invalid IDs" do
      tmp = make_tmp_dir()
      bad_dir = Path.join(tmp, "INVALID NAME")
      File.mkdir_p!(bad_dir)
      File.write!(Path.join(bad_dir, "SKILL.md"), "---\nname: test\ndescription: test\n---\n")

      assert {:ok, []} = Manifest.scan(tmp, :test)
    end
  end

  describe "parse_frontmatter/1" do
    test "parses YAML frontmatter between --- delimiters" do
      content = "---\nname: my-skill\ndescription: A test skill\n---\n\n# Content"
      assert {:ok, frontmatter} = Manifest.parse_frontmatter(content)
      assert frontmatter["name"] === "my-skill"
      assert frontmatter["description"] === "A test skill"
    end

    test "returns empty map when no frontmatter" do
      assert {:ok, %{}} = Manifest.parse_frontmatter("# Just markdown")
    end

    test "parses mcp field" do
      content = "---\nname: test\ndescription: desc\nmcp: tool:my-tool\n---\n"
      assert {:ok, frontmatter} = Manifest.parse_frontmatter(content)
      assert frontmatter["mcp"] === "tool:my-tool"
    end
  end

  describe "parse_skill/4" do
    test "parses skill without mcp config" do
      tmp = make_tmp_dir()
      skill_dir = Path.join(tmp, "plain-skill")
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), "---\nname: test\ndescription: A skill\n---\n")

      assert {:ok, skill} = Manifest.parse_skill("plain-skill", Path.join(skill_dir, "SKILL.md"), :mylib, tmp)
      assert is_nil(skill.mcp)
      assert skill.description === "A skill"
    end
  end

  defp make_tmp_dir do
    tmp = Path.join(System.tmp_dir!(), "elixir_skills_manifest_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(tmp) end)
    tmp
  end
end
