# ElixirSkills

Ship agent guidance alongside your Elixir hex package. `elixir_skills` scans
your deps for `priv/skills/SKILL.md` files and installs them as a single
merged `elixir-skills` skill under each detected agent's skills directory.

## Authoring a skill for your library

```
your_package/
└── skills/
    ├── SKILL.md                 # required — YAML frontmatter + body
    └── references/              # optional
        └── patterns.md
```

`SKILL.md` frontmatter:

```markdown
---
name: your-library-id
description: Use when … (broad trigger keywords go here)
---

# Your Library

Guidance for agents working with your-library.
```

A compile alias (`mix skills.build`) copies `skills/` into `priv/skills/` so
the files ship with your hex package.

## Installation (consumers)

```elixir
def deps do
  [
    {:elixir_skills, "~> 0.2.0"}
  ]
end
```

Then:

```
$ mix skills.list
$ mix skills.install          # project-local .claude/skills/
$ mix skills.install -g       # user-global ~/.claude/skills/
$ mix skills.install --agent cursor
```

Output per agent:

```
.claude/skills/elixir-skills/
├── SKILL.md                 # generated router
└── references/
    ├── your-library-id/     # symlink to the dep's priv/skills
    ├── lang-ex/
    └── …
```

## MCP server

```
$ mix skills.server               # stdio
$ mix skills.server --http 4242   # streamable HTTP
```

Exposed tools: `list_skills`, `get_skill`, `install_skill`, `uninstall_skill`
— all keyed by library id.

## License

MIT.
