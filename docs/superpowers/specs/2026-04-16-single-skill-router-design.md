# Single-Skill Router Refactor

**Date:** 2026-04-16
**Status:** Approved

## Summary

Collapse `elixir_skills` from "install one agent skill per library" to "install a
single `elixir-skills` router skill whose `references/` folder contains one
symlinked directory per library." The router `SKILL.md` is generated at install
time from every library's frontmatter and teaches the agent how to pick the
right library reference for the current task.

## Motivation

The current model surfaces every hex-package skill as its own entry under
`.claude/skills/`. As more libraries adopt, this pollutes the agent's skill
list with fine-grained entries and makes discovery noisy. A single router skill
with broad triggers and a catalog body is a better fit: one entry surfaces all
Elixir library guidance, and the agent narrows down by reading the specific
`references/<lib>/SKILL.md` it needs.

## Authoring format (library side)

Each hex package ships at most:

```
hex_package_root/
└── skills/
    ├── SKILL.md                    # required — YAML frontmatter + body
    └── references/                 # optional — deeper guidance files
        ├── patterns.md
        └── examples.md
```

Rules:

- `SKILL.md` uses the existing `name:` + `description:` frontmatter. The `name`
  is the library's logical skill name (e.g. `elixir-lang-ex`).
- One skill per hex package. The old multi-skill layout
  (`skills/<skill-name>/SKILL.md`) is no longer supported.
- The existing compile alias continues to copy `skills/` → `priv/skills/` so
  content ships with the hex package.

`elixir_skills` itself keeps a baseline set at
`priv/bundled_skills/<lib>/skills/` for libraries that have not yet adopted the
format. Baseline is lowest precedence.

**Precedence** (matched by `name` field in frontmatter):

1. Library-shipped skill (hex dep)
2. Baseline fallback shipped by `elixir_skills`

## Install output (consumer side)

`mix skills.install` produces a single merged skill directory per detected
agent:

```
.claude/skills/elixir-skills/
├── SKILL.md                        # generated router (real file, not symlink)
└── references/
    ├── elixir-lang-ex/             # symlink → <lang_ex dep>/priv/skills/
    │   ├── SKILL.md
    │   └── references/
    │       └── advanced-patterns.md
    ├── oban/                       # symlink → elixir_skills baseline
    │   └── SKILL.md
    └── ...
```

Key properties:

- Each library is a **directory-level symlink** into the dep's
  `priv/skills/` (or the baseline's `priv/bundled_skills/<lib>/skills/`). Any
  file added, removed, or edited upstream flows through without reinstalling.
- The router `SKILL.md` is a real file because its content aggregates
  frontmatters from every installed library. It cannot be a symlink.
- The layout is mirrored across every detected agent dotdir (`.claude/`,
  `.windsurf/`, `.cursor/`, `.codex/`, `.amp/`) as today.
- Collisions: because each library gets its own subfolder (keyed by `name:`),
  there are no filename collisions between libraries. Within a library, the
  upstream author is responsible for unique filenames.

## Tracking

`.elixir_skills.json` at the target root records per-library entries:

```json
{
  "elixir-lang-ex": {
    "package": "lang_ex",
    "package_version": "0.4.0",
    "source_path": "/path/to/deps/lang_ex/priv/skills",
    "installed_at": "2026-04-16T12:00:00Z"
  },
  "oban": {
    "package": "elixir_skills",
    "package_version": "0.2.0",
    "source_path": "/path/to/elixir_skills/priv/bundled_skills/oban/skills",
    "installed_at": "2026-04-16T12:00:00Z"
  }
}
```

`mix skills.install` diffs against this to decide new / update / unchanged /
stale entries and regenerates the router. Uninstall removes the whole
`elixir-skills/` directory and clears the tracking file.

## Router `SKILL.md` (generated)

Synthesized on every `mix skills.install`. Shape:

```markdown
---
name: elixir-skills
description: |
  Use when working with any Elixir library that ships guidance via elixir_skills.
  Covers: lang_ex (graph-based agent orchestration), oban (background jobs),
  ecto_shorts (Ecto helpers), ...
---

# Elixir Skills Router

Determine which libraries apply to the current task, then read the matching
reference file before taking action.

## How to route

1. Check the user's prompt for library names/imports listed below.
2. Check `mix.exs` deps and any open files for imports.
3. For each matching library, read `references/<lib>/SKILL.md` first;
   consult `references/<lib>/references/*.md` only if the SKILL.md points
   you there.

## Library catalog

### elixir-lang-ex — `references/elixir-lang-ex/SKILL.md`
Triggers: LangGraph for Elixir, StateGraph, conditional routing, checkpointing,
human-in-the-loop workflows, tool-calling agents, multi-step AI workflows in Elixir.

### oban — `references/oban/SKILL.md`
Triggers: background jobs, recurring jobs, retries...

...
```

Generation rules:

- Aggregated `description:` is built by concatenating a short phrase per
  library derived from each library's `description:` frontmatter. The router
  description is the single string Claude uses to trigger the skill, so it must
  mention the major library names/keywords.
- Each catalog section uses the library's `name:` as the heading, and its
  `description:` as the trigger body.
- Sections are sorted alphabetically by `name:` for stable diffs.

## Mix tasks

| Task | Behavior |
|------|----------|
| `skills.install` | Discover deps' `priv/skills/`, merge with baseline by `name:` (dep wins), symlink each library's `priv/skills/` → `references/<lib>/`, regenerate router `SKILL.md`, update tracking. Supports `-g`, `--agent`. |
| `skills.uninstall` | Remove `<agent>/skills/elixir-skills/` entirely and clear tracking file. |
| `skills.list` | Show per-library entries (what's inside the merged skill): name, source package, version, installed/not-installed. |
| `skills.init` | Scaffold `skills/SKILL.md` in the current project (single-skill flow). Drops the old multi-skill subfolder behavior. |
| `skills.server` | Start MCP server (unchanged transport flags). |
| `skills.build` | Compile alias that copies `skills/` → `priv/skills/` (unchanged). |

## MCP server

Tools remain the same names with adjusted semantics:

- `list_skills` — lists discovered per-library entries (same as `skills.list`).
- `get_skill` — returns the library's `SKILL.md` content for a given `name:`.
- `install_skill` — adds one library's symlink into the merged skill and
  regenerates the router. Accepts `agent`, `global`, `copy` flags as today.
- `uninstall_skill` — removes one library's symlink and regenerates the router.
  (Removing the last library deletes the `elixir-skills/` directory.)

## Out of scope

- Dynamic/per-session library detection at runtime. The router is content-only:
  the agent reads the catalog body and uses its existing context (prompt,
  `mix.exs`, open files) to pick the right reference. No MCP call at query
  time.
- Changing the hex-package compile alias. `skills/` → `priv/skills/` stays.
- Cross-agent per-file overrides. Each library is symlinked as a single
  directory; the library author owns the full subtree.

## Migration for existing authors

Libraries currently using the multi-skill layout
(`skills/<skill-name>/SKILL.md`) must flatten to `skills/SKILL.md`. The
`skills.init` scaffold produces the new layout. No compatibility shim — the
library count is small (this repo + examples).

## Open risks

- **Router description size.** With many libraries, the aggregated
  `description:` could grow past what Claude comfortably indexes. Mitigation:
  keep each library's contribution to a short phrase (≤80 chars), and let
  library authors tune via their own `description:` frontmatter.
- **Symlinks on Windows / CI.** Directory symlinks require appropriate
  permissions. Fall back to a recursive copy when symlink creation fails
  (existing `copy: true` flag in the MCP `install_skill` tool already covers
  this path).
