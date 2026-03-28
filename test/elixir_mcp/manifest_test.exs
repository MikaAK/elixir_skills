defmodule ElixirMcp.ManifestTest do
  use ExUnit.Case, async: true

  alias ElixirMcp.Manifest

  @fixtures_path Path.expand("../fixtures", __DIR__)
  @manifest_path Path.join([@fixtures_path, "fake_dep", "priv", "claude_skills", "manifest.json"])
  @base_path Path.join([@fixtures_path, "fake_dep", "priv", "claude_skills"])

  describe "parse/3" do
    test "parses a valid manifest" do
      assert {:ok, [skill]} = Manifest.parse(@manifest_path, :fake_dep, @base_path)
      assert skill.id === "test-skill"
      assert skill.namespaced_id === "fake_dep--test-skill"
      assert skill.package === :fake_dep
      assert skill.description === "Use when testing elixir_mcp functionality"
      assert skill.source_path === Path.join(@base_path, "test-skill")
      assert skill.mcp === %{type: :tool, name: "get_test_skill"}
    end

    test "returns error for missing file" do
      assert {:error, msg} = Manifest.parse("/nonexistent/manifest.json", :fake, "/base")
      assert msg =~ "Failed to read"
    end

    test "returns error for invalid JSON" do
      path = Path.join(System.tmp_dir!(), "bad_manifest.json")
      File.write!(path, "not json")

      assert {:error, msg} = Manifest.parse(path, :fake, "/base")
      assert msg =~ "Invalid JSON"
    after
      File.rm(Path.join(System.tmp_dir!(), "bad_manifest.json"))
    end

    test "returns error for missing schema_version" do
      path = Path.join(System.tmp_dir!(), "no_version.json")
      File.write!(path, Jason.encode!(%{"skills" => []}))

      assert {:error, msg} = Manifest.parse(path, :fake, "/base")
      assert msg =~ "Missing schema_version"
    after
      File.rm(Path.join(System.tmp_dir!(), "no_version.json"))
    end

    test "returns error for unsupported schema_version" do
      path = Path.join(System.tmp_dir!(), "bad_version.json")
      File.write!(path, Jason.encode!(%{"schema_version" => 99, "skills" => []}))

      assert {:error, msg} = Manifest.parse(path, :fake, "/base")
      assert msg =~ "Unsupported manifest schema_version"
    after
      File.rm(Path.join(System.tmp_dir!(), "bad_version.json"))
    end

    test "returns error for invalid skill ID" do
      path = Path.join(System.tmp_dir!(), "bad_id.json")
      data = %{"schema_version" => 1, "skills" => [%{"id" => "INVALID ID!"}]}
      File.write!(path, Jason.encode!(data))

      assert {:error, msg} = Manifest.parse(path, :fake, "/base")
      assert msg =~ "Invalid skill id"
    after
      File.rm(Path.join(System.tmp_dir!(), "bad_id.json"))
    end

    test "parses skill without mcp config" do
      path = Path.join(System.tmp_dir!(), "no_mcp.json")
      data = %{"schema_version" => 1, "skills" => [%{"id" => "plain-skill", "description" => "A skill"}]}
      File.write!(path, Jason.encode!(data))

      assert {:ok, [skill]} = Manifest.parse(path, :mylib, "/base")
      assert is_nil(skill.mcp)
      assert skill.description === "A skill"
    after
      File.rm(Path.join(System.tmp_dir!(), "no_mcp.json"))
    end
  end
end
