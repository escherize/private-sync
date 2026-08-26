---
title: "private-sync: a private brain for every repo"
---

# Your agents keep re-learning the same things. Give the repo a private brain.

private-sync installs a second, private git repo inside any project: a
gitignored `.private/` sidecar that holds decisions, findings, worklogs, and a
task board. Every agent on every machine reads it, writes it, and syncs it
with plain `git push`. Nothing in it can leak into the public repo. One
command installs it.

```sh
./install.sh /path/to/project
```

That is the whole pitch. The rest is why it works.

## The public repo cannot hold the knowledge that matters most

Run several coding agents on one project across different machines and
harnesses, and the expensive knowledge is never the code. It is the
why-knowledge:

- why we chose SQLite WAL over the obvious default
- the flaky test that cost an afternoon, and the fix
- who is working on what right now
- what the last session tried and abandoned

None of it belongs in the public repo. It is internal, sometimes sensitive,
often embarrassing. So today it dies in chat transcripts, and every new
session pays to rediscover it.

## A sidecar git repo solves sync, auth, and history for free

`.private/` is an independent git repo checked out inside the project, with
its own private remote. That one design choice does most of the work:

- **Sync** is `git push` and `git pull`. No server, no daemon, no service.
- **Auth** is whatever git auth each machine already has.
- **History** is git log. "What did other agents learn this week" is one command.

Merge conflicts are designed out instead of handled. Every agent writes at
its own paths (`findings/<agent>/`, `worklogs/<agent>/<session>.md`),
decisions are immutable append-only files, and the task board is managed by
[Backlog.md](https://github.com/MrLesk/Backlog.md), which owns ID allocation.
Ten concurrent writers never touch the same file.

## Three layers keep it out of the public repo

A gitignore entry is a promise, not a guarantee. The installer adds:

1. `.gitignore` entries for `.private/` and `.private-remote`
2. the same entries in `.git/info/exclude`, which survive a clobbered gitignore
3. a pre-commit hook that blocks and auto-unstages anything under those paths

The hook is the real guard. Even `git add -f` followed by a commit gets
refused, unstaged, and explained.

## The knowledge has a shape, not just a folder

Each layer has one write pattern, so agents know where things go and readers
know what to trust:

| Layer | What | Pattern |
|---|---|---|
| `wiki/` | current truth | edited in place |
| `decisions/` | ADRs | immutable, supersede-only |
| `findings/<agent>/` | hard-won learnings | append-only |
| `worklogs/<agent>/` | session logs | append-only |
| `backlog/` | tasks | CLI-managed |

The workflow mirrors an issue tracker, minus the tracker: find or create a
task, claim it (`In Progress`, assigned, pushed immediately), record decisions
as ADRs while you work, mark it Done with a worklog. An unpushed claim
protects nobody, so the convention is: push the claim before the first edit.

## Convention over config: the installer resolves everything

No remote configured? The installer derives one: a private GitHub repo named
`private-<project>` under your `gh` login, created on demand. Remote already
has history? It clones instead of seeding. Fresh sidecar? Seeded from a
template, committed, pushed. Task board absent? `backlog init` runs
non-interactively.

Every step is guarded, so re-running the installer is the update mechanism.
New machine, existing install, six months later: same command.

## It meets agents where they already look

Agents do not read documentation. They read their memory files. The installer
writes a pointer block into both `CLAUDE.md` and `AGENTS.md`, so Claude Code,
omp, and codex-style harnesses all learn the same thing ambiently: where
knowledge lives, how to claim work, how to bootstrap a missing sidecar. A
fuller skill (`.claude/skills/private-sync/`) carries the deep conventions.
The pointer block is replaced between markers on every install run, so
convention updates reach every project the next time you run the installer.

## Try it

```sh
git clone https://github.com/escherize/private-sync
./private-sync/install.sh /path/to/your/project
```

Requirements: git, and optionally `gh` (remote auto-creation) and
[Backlog.md](https://github.com/MrLesk/Backlog.md) (task board). Everything
degrades gracefully when a tool is missing.

Your next agent session starts by reading what the last one learned. That is
the entire point.
