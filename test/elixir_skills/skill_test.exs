defmodule ElixirSkills.SkillTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Skill

  describe "namespace/2" do
    test "combines package and skill ID with double-dash" do
      assert Skill.namespace(:oban, "worker-patterns") === "oban--worker-patterns"
    end

    test "works with string package names" do
      assert Skill.namespace(:my_lib, "test") === "my_lib--test"
    end
  end

  describe "source field" do
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
  end
end
