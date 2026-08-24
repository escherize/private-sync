# .private/

This is a private sidecar git repo, checked out inside the parent project. It
holds what the public repo cannot: shared context, decisions, findings, worklogs,
and tasks for every agent working on this project, across machines and harnesses.

**Never commit anything from here into the parent repo.** It is gitignored,
excluded via `.git/info/exclude`, and a pre-commit hook blocks it. If you find
yourself working around any of those, stop.

## Layout

```
.private/
  README.md              what this is, warning, conventions
  wiki/                  current shared truth, edited in place
    index.md             entry point, links to everything
  decisions/             ADRs, immutable, append-only
  findings/<agent-id>/   per-agent discovery log, append-only
  worklogs/<agent-id>/   per-session logs, append-only
  backlog/               tasks, managed entirely by the backlog CLI
  index.jsonl            derived search filter layer, gitignored, rebuildable
```

Five directories because they have different write patterns:

| | Write pattern | Frequency | Contention |
|---|---|---|---|
| `wiki/` | edit in place | low | real, but rare |
| `decisions/` | append new file | low | none (immutable) |
| `findings/` | append new file | high | none (per-agent paths) |
| `worklogs/` | append new file | high | none (per-session paths) |
| `backlog/` | CLI-mediated edits | medium | upstream locking + ID allocation |

Findings and worklogs are namespaced per agent (and per session) so ten
concurrent writers never touch the same file. That is what makes this work
without locking.

## Conventions

The installed skill file (`.claude/skills/private-sync/SKILL.md` in the parent
repo) defines file formats, frontmatter shapes, linking rules, and the commit
flow. Read it before writing anything here.

Quick rules:

- Start at `wiki/index.md`. Grep beats reading.
- Never put a secret value in a note. Reference its location instead.
- Decisions are immutable; supersede them, never edit them.
- Tasks are created and changed only through the `backlog` CLI, never by hand.
- Commit here (`git -C .private add -A && git commit && git push`); other agents
  only see pushed work.
