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

      ids = skills |> Enum.map(&(&1.id)) |> Enum.sort()
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
