defmodule ElixirMcpTest do
  use ExUnit.Case
  doctest ElixirMcp

  test "greets the world" do
    assert ElixirMcp.hello() == :world
  end
end
