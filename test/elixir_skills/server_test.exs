defmodule ElixirSkills.ServerTest do
  use ExUnit.Case

  alias ElixirSkills.Server

  test "server module is defined and uses Hermes.Server" do
    assert {:module, Server} === Code.ensure_loaded(Server)

    behaviours =
      Server.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert Hermes.Server in behaviours
  end

  test "start/1 accepts transport config" do
    assert function_exported?(Server, :start, 1)
  end

  test "init/2 registers expected tools" do
    assert function_exported?(Server, :init, 2)
  end

  test "handle_tool_call/3 is implemented" do
    assert function_exported?(Server, :handle_tool_call, 3)
  end
end
