---
type: wiki-index
tags: []
---

# Index

Entry point for this vault. Read this first when starting work; grep beats
reading everything else.

- [[decisions]] - ADRs: what we chose and why. Immutable.
- [[findings]] - per-agent discovery log: what agents learned the hard way.
- [[worklogs]] - per-session logs of what was done and why.
- [[tasks]] - current work items, tracked under `backlog/`.

## How to use this vault

Search first: `grep -ril "<term>" .private/` or filter the derived index
(`.private/index.jsonl`) with jq. Only read whole files when grep has already
narrowed the target.

Wiki pages (like this one) hold current truth and are edited in place.
Everything else is append-only: findings, decisions, and worklogs are new files,
never edits of old ones.

Link every new wiki page from this index or it will not be found.
