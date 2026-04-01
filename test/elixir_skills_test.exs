defmodule ElixirSkillsTest do
  use ExUnit.Case

  test "scan returns ok tuple" do
    assert {:ok, _skills} = ElixirSkills.scan()
  end

  test "installed returns a map" do
    assert is_map(ElixirSkills.installed())
  end

  test "plan returns a list" do
    assert is_list(ElixirSkills.plan([]))
  end
end
