defmodule Mix.Tasks.ClaudeSkills.Build do
  @shortdoc "Copies skills/ to priv/bundled_skills/"
  @moduledoc """
  Copies the root `skills/` directory into `priv/bundled_skills/` so bundled
  fallback skills are available at runtime via `Application.app_dir/2`.

  This runs automatically before `mix compile` via the project aliases.

      $ mix claude_skills.build
  """

  use Mix.Task

  @source_dir "skills"
  @target_dir "priv/bundled_skills"

  @impl Mix.Task
  def run(_args) do
    if File.dir?(@source_dir) do
      File.mkdir_p!(Path.dirname(@target_dir))
      File.rm_rf!(@target_dir)
      File.cp_r!(@source_dir, @target_dir)
    end

    :ok
  end
end
