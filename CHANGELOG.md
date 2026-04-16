# Changelog

## 0.2.0 (2026-04-16)

### Changed

- **BREAKING:** `mix skills.install` now produces a single merged `elixir-skills` skill per agent (`<agent>/skills/elixir-skills/`) instead of one skill directory per library. Library content is symlinked under `references/<library-id>/`.
- **BREAKING:** library authors now ship a single `skills/SKILL.md` (+ optional `skills/references/`) instead of one subdirectory per skill. The `name:` frontmatter field is the library id; `package--skill` namespacing is gone.
- `Skill` struct lost `namespaced_id`; `id` is now the library id.
- Tracking file key format: library ids (`"libraries"` top-level key). Legacy `"skills"` key read for one-version migration.
- Mix task renames preserved; `skills.init` produces the new single-file layout.

### Added

- `ElixirSkills.Router` — synthesizes the router SKILL.md.
- `Config.router_skill_name/0`, `Config.router_skill_dir/1`.

### Removed

- `ElixirSkills.Skill.namespace/2` and `namespaced_id` field.
- `ElixirSkills.Manifest.scan/2` and `parse_skill/4` (replaced by `parse_library/2`).
- `skills/` directory in the `elixir_skills` repo (baselines moved to `priv/bundled_skills/<lib>/`).

## 0.1.1 (2026-03-31)

### Added

- Multi-agent support: auto-detects `.claude/`, `.windsurf/`, `.cursor/`, `.codex/`, `.amp/` directories and installs skills to all detected agents
- `--agent` flag on `mix skills.install`, `mix skills.uninstall`, and `mix skills.list` to target a specific agent
- `config :elixir_skills, agents: [:claude, :cursor]` compile-time config to set explicit agent list (default: `:auto`)
- MCP server `install_skill` and `uninstall_skill` tools accept optional `agent` parameter
- `Config.detect_agents/0`, `Config.resolve_agents/1`, `Config.skills_target_dirs/1` for multi-agent path resolution

### Changed

- Renamed all Mix tasks from `mix claude_skills.*` to `mix skills.*`
- Removed `manifest.json` — skills are now discovered by scanning directories for `SKILL.md` frontmatter
- `Manifest` module rewritten: `scan/2` scans dirs, `parse_skill/4` reads frontmatter, `parse_frontmatter/1` extracts YAML
- `Config` now uses `Application.compile_env/3` instead of `Application.get_env/3`
- `Hermes.Server.Registry` started in application supervision tree (fixes `unknown registry` error)
- Compile aliases guarded to only apply when elixir_skills is the root project (fixes path-dep env mismatch)
- Test suite uses dependency injection (`target_dir` opt) instead of `Application.put_env`
- All tests run with `async: true`

### Removed

- `manifest.json` files and `Config.manifest_filename/0`
- `doc/` directory (stale generated docs)
- Hardcoded `.claude/` paths — replaced with agent-aware resolution

## 0.1.0 (2026-03-29)

- Initial release: MCP server, skill discovery, installation, and bundled fallbacks
