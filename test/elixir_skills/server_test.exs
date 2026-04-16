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

  test "start/1, init/2, handle_tool_call/3 are exported" do
    assert function_exported?(Server, :start, 1)
    assert function_exported?(Server, :init, 2)
    assert function_exported?(Server, :handle_tool_call, 3)
  end

  test "list_skills returns JSON text response without crashing" do
    {:reply, response, %{}} = Server.handle_tool_call("list_skills", %{}, %{})
    assert %Hermes.Server.Response{} = response
  end
end
