defmodule ElixirSkills.InstallerTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Installer, Skill}

  @fixtures_path Path.expand("../fixtures", __DIR__)

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "elixir_skills_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir, opts: [target_dir: tmp_dir]}
  end

  defp make_skill(id, package \\ :fake_dep) do
    source = Path.join([@fixtures_path, "fake_dep", "priv", "skills", "test-skill"])

    %Skill{
      id: id,
      namespaced_id: Skill.namespace(package, id),
      package: package,
      package_version: "1.0.0",
      description: "Test skill",
      source_path: source,
      mcp: nil
    }
  end

  describe "plan/1" do
    test "marks new skills as :new", %{opts: opts} do
      skill = make_skill("my-skill")
      [entry] = Installer.plan([skill], opts)
      assert entry.action === :new
    end

    test "marks installed same-version skills as :unchanged", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("my-skill")

      target = Path.join(tmp_dir, skill.namespaced_id)
      File.ln_s!(skill.source_path, target)

      tracking = %{
        skill.namespaced_id => %{
          "package" => "fake_dep",
          "package_version" => "1.0.0",
          "source_path" => skill.source_path,
          "installed_at" => "2026-01-01T00:00:00Z"
        }
      }

      write_tracking(tmp_dir, tracking)

      [entry] = Installer.plan([skill], opts)
      assert entry.action === :unchanged
    end

    test "marks conflicting unmanaged skills as :conflict", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("my-skill")
      target = Path.join(tmp_dir, skill.namespaced_id)
      File.mkdir_p!(target)

      [entry] = Installer.plan([skill], opts)
      assert entry.action === :conflict
    end
  end

  describe "execute/2" do
    test "creates symlinks for new skills", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("my-skill")
      plan = [%{skill: skill, action: :new, reason: nil}]

      assert {:ok, %{installed: [_], skipped: []}} = Installer.execute(plan, opts)

      target = Path.join(tmp_dir, skill.namespaced_id)
      assert File.exists?(target)
      assert {:ok, %{type: :symlink}} = File.lstat(target)
    end

    test "copies when :copy option is set", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("copy-skill")
      plan = [%{skill: skill, action: :new, reason: nil}]

      assert {:ok, %{installed: [_], skipped: []}} = Installer.execute(plan, [copy: true] ++ opts)

      target = Path.join(tmp_dir, skill.namespaced_id)
      assert File.exists?(target)
      assert {:ok, %{type: :directory}} = File.lstat(target)
    end

    test "skips conflicts without force", %{opts: opts} do
      skill = make_skill("conflict-skill")
      plan = [%{skill: skill, action: :conflict, reason: "exists"}]

      assert {:ok, %{installed: [], skipped: [_]}} = Installer.execute(plan, opts)
    end

    test "writes tracking file", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("tracked-skill")
      plan = [%{skill: skill, action: :new, reason: nil}]

      Installer.execute(plan, opts)

      tracking_path = Path.join(tmp_dir, ".elixir_skills.json")
      assert File.exists?(tracking_path)

      tracking = tracking_path |> File.read!() |> Jason.decode!()
      assert Map.has_key?(tracking["skills"], skill.namespaced_id)
    end
  end

  describe "uninstall/1" do
    test "removes installed skills", %{tmp_dir: tmp_dir, opts: opts} do
      skill = make_skill("remove-me")
      plan = [%{skill: skill, action: :new, reason: nil}]
      Installer.execute(plan, opts)

      target = Path.join(tmp_dir, skill.namespaced_id)
      assert File.exists?(target) or symlink?(target)

      {:ok, removed} = Installer.uninstall([skill.namespaced_id], opts)
      assert skill.namespaced_id in removed
      refute File.exists?(target)
    end

    test "uninstall :all removes everything", %{opts: opts} do
      skill1 = make_skill("skill-a")
      skill2 = make_skill("skill-b")

      plan = [
        %{skill: skill1, action: :new, reason: nil},
        %{skill: skill2, action: :new, reason: nil}
      ]

      Installer.execute(plan, opts)

      {:ok, removed} = Installer.uninstall(:all, opts)
      assert length(removed) === 2

      assert Enum.empty?(Installer.read_tracking(opts))
    end
  end

  defp write_tracking(tmp_dir, skills_map) do
    path = Path.join(tmp_dir, ".elixir_skills.json")
    data = %{"version" => 1, "skills" => skills_map}
    File.write!(path, Jason.encode!(data))
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> true
      _ -> false
    end
  end
end
