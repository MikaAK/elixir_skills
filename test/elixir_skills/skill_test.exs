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
