
<!-- private-sync pointer -->
## Project knowledge lives in .private/

Sidecar git repo (gitignored, own remote, synced via plain git). Use the
`private-sync` skill for full conventions. Quick map:

- `.private/wiki/` - current truth, start at wiki/index.md
- `.private/decisions/` - ADRs, immutable, supersede-only
- `.private/findings/<agent>/` - things learned the hard way, append-only
- `.private/worklogs/<agent>/` - session logs, append-only
- `.private/backlog/` - tasks, via the backlog CLI only

Before starting work: read `.private/wiki/index.md`, then
`git -C .private log --oneline -20`. Commit and push sidecar changes
separately: `git -C .private add -A && git -C .private commit && git -C .private push`.
If `.private/` is missing: `git clone "$(cat .private-remote)" .private`.
Never commit `.private/` contents or secret values to the public repo.
