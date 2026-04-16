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

    test "marks same-version tracked libraries as :unchanged", %{opts: opts} do
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
