# Changelog

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
