defmodule ElixirSkills.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.Config

  describe "router_skill_name/0" do
    test "returns the canonical name" do
      assert Config.router_skill_name() === "elixir-skills"
    end
  end

  describe "router_skill_dir/1" do
    test "joins the agent skills dir with the router name" do
      tmp = Path.join(System.tmp_dir!(), "router_dir_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert Config.router_skill_dir(target_dir: tmp) === Path.join(tmp, "elixir-skills")
    end
  end
end
