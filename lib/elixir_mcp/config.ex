defmodule ElixirMcp.Config do
  @moduledoc """
  Configuration for ElixirMcp skill discovery and installation.
  """

  @default_skills_dir Path.expand("~/.claude/skills")
  @manifest_filename "manifest.json"
  @skills_dir_name "claude_skills"
  @tracking_filename ".elixir_mcp.json"
  @bundled_package :elixir_mcp
  @valid_id_pattern ~r/^[a-z0-9][a-z0-9-]*$/

  @doc "Target directory for installed skills."
  @spec skills_target_dir() :: String.t()
  def skills_target_dir do
    Application.get_env(:elixir_mcp, :skills_target_dir, @default_skills_dir)
  end

  @doc "Name of the manifest file inside priv/claude_skills/."
  @spec manifest_filename() :: String.t()
  def manifest_filename, do: @manifest_filename

  @doc "Name of the skills directory inside priv/."
  @spec skills_dir_name() :: String.t()
  def skills_dir_name, do: @skills_dir_name

  @doc "Name of the tracking file written to the skills target dir."
  @spec tracking_filename() :: String.t()
  def tracking_filename, do: @tracking_filename

  @doc "Full path to the tracking file."
  @spec tracking_file_path() :: String.t()
  def tracking_file_path do
    Path.join(skills_target_dir(), @tracking_filename)
  end

  @doc "Regex pattern that valid skill IDs must match."
  @spec valid_id_pattern() :: Regex.t()
  def valid_id_pattern, do: @valid_id_pattern

  @doc "Directory containing bundled fallback skills shipped with elixir_mcp."
  @spec bundled_skills_dir() :: String.t()
  def bundled_skills_dir do
    Application.get_env(:elixir_mcp, :bundled_skills_dir, default_bundled_skills_dir())
  end

  @doc "The package atom used for bundled fallback skills."
  @spec bundled_package() :: atom()
  def bundled_package, do: @bundled_package

  @doc "Optional allowlist of packages permitted to install skills."
  @spec allowed_packages() :: [atom()] | nil
  def allowed_packages do
    Application.get_env(:elixir_mcp, :allowed_packages, nil)
  end

  defp default_bundled_skills_dir do
    Application.app_dir(:elixir_mcp, "priv/bundled_skills")
  end
end
