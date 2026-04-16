defmodule ElixirSkills.Router do
  @moduledoc """
  Synthesizes the router `SKILL.md` for the merged `elixir-skills` skill.

  The router's frontmatter `description:` aggregates a short phrase per library
  so Claude's skill matcher can trigger the router on any of them. The body is
  a catalog that lists each library with a pointer to its
  `references/<id>/SKILL.md`.
  """

  alias ElixirSkills.{Config, Skill}

  @doc """
  Returns the full text of the router `SKILL.md` for the given list of skills.
  """
  @spec generate([Skill.t()]) :: String.t()
  def generate(skills) do
    sorted = Enum.sort_by(skills, & &1.id)

    [
      frontmatter(sorted),
      "\n",
      header(),
      "\n",
      routing_instructions(),
      "\n",
      catalog(sorted)
    ]
    |> IO.iodata_to_binary()
  end

  defp frontmatter([]) do
    """
    ---
    name: #{Config.router_skill_name()}
    description: Elixir skills router (no libraries installed yet).
    ---
    """
  end

  defp frontmatter(skills) do
    summary =
      skills
      |> Enum.map(fn %Skill{id: id, description: desc} -> "#{id} (#{truncate(desc, 80)})" end)
      |> Enum.join(", ")

    """
    ---
    name: #{Config.router_skill_name()}
    description: Use when working with any Elixir library that ships guidance via elixir_skills. Covers: #{summary}.
    ---
    """
  end

  defp header do
    """

    # Elixir Skills Router

    Determine which libraries apply to the current task, then read the matching
    reference file before taking action.
    """
  end

  defp routing_instructions do
    """

    ## How to route

    1. Check the user's prompt for library names/imports listed below.
    2. Check `mix.exs` deps and any open files for imports.
    3. For each matching library, read `references/<lib>/SKILL.md` first;
       consult `references/<lib>/references/*.md` only if the SKILL.md
       points you there.
    """
  end

  defp catalog([]) do
    """

    ## Library catalog

    No libraries installed yet. Add an Elixir dep that ships `skills/SKILL.md`
    and run `mix skills.install`.
    """
  end

  defp catalog(skills) do
    entries =
      skills
      |> Enum.map(fn %Skill{id: id, description: desc} ->
        """
        ### #{id} — `references/#{id}/SKILL.md`
        #{desc || "(no description)"}
        """
      end)
      |> Enum.join("\n")

    """

    ## Library catalog

    #{entries}
    """
  end

  defp truncate(nil, _), do: "no description"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) <= max, do: text, else: String.slice(text, 0, max - 1) <> "…"
  end
end
