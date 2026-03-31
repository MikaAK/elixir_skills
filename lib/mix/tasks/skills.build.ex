defmodule Mix.Tasks.Skills.Build do
  @shortdoc "Copies skills/ to priv/skills/ for runtime availability"
  @moduledoc """
  Copies the root `skills/` directory into `priv/skills/` so skills are
  available at runtime via `Application.app_dir/2`.

  Runs automatically before compile via aliases in `mix.exs`.

      $ mix skills.build
  """

  use Mix.Task

  @source_dir "skills"
  @target_dir "priv/skills"

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
