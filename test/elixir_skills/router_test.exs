defmodule ElixirSkills.RouterTest do
  use ExUnit.Case, async: true

  alias ElixirSkills.{Router, Skill}

  defp skill(id, description) do
    %Skill{id: id, package: :pkg, source_path: "/tmp/#{id}", description: description}
  end

  describe "generate/1" do
    test "starts with YAML frontmatter naming the router" do
      content = Router.generate([skill("lang-ex", "Use when X")])

      assert content =~ ~r/\A---\nname: elixir-skills\n/
      assert content =~ ~r/^description: /m
    end

    test "aggregates each library description into the router description" do
      content =
        Router.generate([
          skill("lang-ex", "Use when building graph-based agents"),
          skill("oban", "Use when running background jobs")
        ])

      assert content =~ "lang-ex"
      assert content =~ "oban"
      # Both description snippets appear
      assert content =~ "graph-based agents"
      assert content =~ "background jobs"
    end

    test "catalog sections link to references/<id>/SKILL.md" do
      content = Router.generate([skill("lang-ex", "Use when X")])
      assert content =~ "references/lang-ex/SKILL.md"
    end

    test "sorts library catalog sections alphabetically by id" do
      content =
        Router.generate([
          skill("zeta", "Z"),
          skill("alpha", "A")
        ])

      alpha_pos = :binary.match(content, "### alpha") |> elem(0)
      zeta_pos = :binary.match(content, "### zeta") |> elem(0)
      assert alpha_pos < zeta_pos
    end

    test "handles empty list with an empty catalog and a neutral description" do
      content = Router.generate([])
      assert content =~ ~r/\A---\nname: elixir-skills\n/
      assert content =~ "No libraries installed yet"
    end
  end
end
