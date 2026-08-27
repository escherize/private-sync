# private-sync

A kit that installs a private, synced notes repo into any git project.

## The problem

Ten agents work on the same project across different machines and harnesses.
They need to share why-knowledge: decisions, findings, session logs, current
task state. None of it can live in the public repo - it is internal, sometimes
sensitive, and often embarrassing.

## The mechanism

`install.sh` seeds a `.private/` sidecar: a second, independent git repo
checked out inside the project. It is kept out of the public repo three ways:

1. `.gitignore` entry
2. `.git/info/exclude` entry (survives a clobbered .gitignore)
3. a pre-commit hook that blocks staging and auto-unstages anything under `.private/`

Sync between machines is plain `git push` / `git pull` on the sidecar's own
remote. Merge conflicts are avoided by design: every writer appends at its own
paths (`findings/<agent-id>/`, `worklogs/<agent-id>/<session>.md`).

## Quickstart

```sh
./install.sh /path/to/project [remote-url]
```

One command. The remote resolves convention-over-config: explicit arg >
`.private-remote` file > existing sidecar origin > a private GitHub repo
`private-<dirname>` under the logged-in `gh` user, created on demand. If the
remote already has history the sidecar is cloned from it; otherwise it is
seeded from the template, committed, and pushed.

Re-running `install.sh` is safe: an existing sidecar is left alone, tooling is
refreshed. Every install is recorded in `~/.config/private-sync/installs`;
`./install.sh --update-all` pulls the kit and refreshes them all.

## The layers

| Layer | Location | What |
|---|---|---|
| Wiki | `wiki/` | curated current truth, edited in place |
| Decisions | `decisions/` | ADRs, immutable, supersede-only |
| Findings | `findings/<agent-id>/` | per-agent discovery log, append-only |
| Tasks | `backlog/` | [Backlog.md](https://github.com/MrLesk/Backlog.md) tasks, CLI-managed markdown files |
| Worklogs | `worklogs/<agent-id>/` | one file per agent session, append-only |

Plus a derived index: `.private/index.jsonl`, rebuilt with
`.private/bin/private-index --out .private/index.jsonl`, gives jq-filterable
frontmatter for fast two-stage retrieval (jq filter first, then grep or optional
[qmd](https://github.com/tobi/qmd) semantic search). It is derived state -
never hand-edit it; it is gitignored and rebuildable anywhere.

## Where things land in the host project

- `.claude/skills/private-sync/SKILL.md` - the conventions skillfile agents read
- pre-commit hook - leak guard
- `.private-remote` - the sidecar's git URL, so fresh machines can clone

Conventions, file formats, frontmatter shapes: see `skill/SKILL.md`. This
README only explains the kit.
