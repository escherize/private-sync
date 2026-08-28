#!/bin/sh
# Install the .private/ sidecar into a project.
#
#   ./install.sh /path/to/project [remote-url]
#
# Idempotent: safe to re-run. Never overwrites an existing .private/.
set -eu

KIT="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="$HOME/.config/private-sync/installs"

# --update-all: pull the kit, then re-run the (idempotent) install on every
# registered project. This is the auto-update path; cron it if you like.
if [ "${1:-}" = "--update-all" ]; then
  git -C "$KIT" pull --ff-only -q && echo "kit: pulled $(git -C "$KIT" rev-parse --short HEAD)"
  # Installs are discovered, not just remembered, from three sources:
  # local sidecar markers under ~/dv, the GitHub account's private-<name>
  # sidecar repos (the global registry, by naming convention), and the
  # per-machine registry for projects living outside ~/dv.
  GH_USER=""
  command -v gh >/dev/null 2>&1 && GH_USER="$(gh api user -q .login 2>/dev/null || true)"
  {
    for D in "$HOME"/dv/*/; do
      [ -e "${D}.private" ] || [ -e "${D}.private-remote" ] && printf '%s\n' "${D%/}"
    done
    if [ -n "$GH_USER" ]; then
      gh repo list "$GH_USER" --limit 200 --json name,visibility \
          -q '.[] | select(.visibility=="PRIVATE") | .name' 2>/dev/null \
        | sed -n 's/^private-//p' | while IFS= read -r N; do
            if [ -d "$HOME/dv/$N" ]; then
              printf '%s\n' "$HOME/dv/$N"
            else
              echo "not on this machine: $N (clone it, then install.sh adopts the sidecar)" >&2
            fi
          done
    fi
    [ -f "$REGISTRY" ] && cat "$REGISTRY"
  } | sort -u | while IFS= read -r P; do
    [ -d "$P" ] || { echo "skip (gone): $P"; continue; }
    echo "== $P"
    "$KIT/install.sh" "$P"
  done
  exit 0
fi

PROJECT="${1:?usage: install.sh /path/to/project [remote-url] | --update-all}"
REMOTE="${2:-}"

[ -d "$PROJECT" ] || { echo "no such directory: $PROJECT" >&2; exit 1; }
git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "not a git repo: $PROJECT" >&2; exit 1; }

# In a linked worktree .git is a file; shared state lives in the common dir.
COMMON_GIT="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)"
GIT_DIR="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-dir)"

# A linked worktree gets no sidecar of its own: install into the main
# checkout, then share its .private/ by symlink (one working copy, no drift).
if [ "$GIT_DIR" != "$COMMON_GIT" ]; then
  MAIN_ROOT="$(dirname "$COMMON_GIT")"
  "$KIT/install.sh" "$MAIN_ROOT" ${REMOTE:+"$REMOTE"}
  cd "$PROJECT"
  [ -e .private ] || { ln -s "$MAIN_ROOT/.private" .private; echo "worktree: linked .private -> $MAIN_ROOT/.private"; }
  exit 0
fi

cd "$PROJECT"

# 1. gitignore, belt. The bare '.private' pattern also covers a worktree's
# symlink, which git sees as a file and the '.private/' pattern misses.
for pat in '.private' '.private/' '.private-remote'; do
  if ! grep -qxF "$pat" .gitignore 2>/dev/null; then
    printf '%s\n' "$pat" >> .gitignore
    echo "gitignore: added $pat"
  fi
done

# 2. info/exclude, suspenders. Survives a clobbered .gitignore. Lives in the
# common dir, so one install covers every linked worktree.
mkdir -p "$COMMON_GIT/info"
for pat in '.private' '.private/' '.private-remote'; do
  if ! grep -qxF "$pat" "$COMMON_GIT/info/exclude" 2>/dev/null; then
    printf '%s\n' "$pat" >> "$COMMON_GIT/info/exclude"
    echo "info/exclude: added $pat"
  fi
done

# 3. The hook. This is what actually stops distribution; the name never did.
HOOK_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOK_DIR"
HOOK="$HOOK_DIR/pre-commit"

if [ -e "$HOOK" ] && ! grep -q 'private-sync guard' "$HOOK" 2>/dev/null; then
  echo "WARNING: $HOOK exists and is not ours; not touching it." >&2
  echo "         Add this check to it by hand:" >&2
  echo "           git diff --cached --name-only | grep -q '^\\.private/' && exit 1" >&2
else
  cat > "$HOOK" <<'HOOK_EOF'
#!/bin/sh
# private-sync guard: refuse to commit sidecar contents to the public repo.
#
# Note: some git builds (observed on Apple Git 2.39.5) report exit 0 from
# `git commit` even when a pre-commit hook exits nonzero. The commit is still
# correctly refused, but `git commit && git push` would read that as success.
# So we also UNSTAGE the offending paths: the block then shows up in
# `git status` and cannot be mistaken for a successful write.
LEAKED=$(git diff --cached --name-only | grep -E '^\.private(/|-remote$|$)' || true)
if [ -n "$LEAKED" ]; then
  echo "BLOCKED: .private/ is staged for the public repo." >&2
  echo "$LEAKED" | sed 's/^/  /' >&2
  git restore --staged .private .private-remote 2>/dev/null \
    || git reset -q HEAD -- .private .private-remote 2>/dev/null || true
  echo "Unstaged automatically. Those notes belong in the sidecar:" >&2
  echo "  git -C .private add -A && git -C .private commit && git -C .private push" >&2
  exit 1
fi
HOOK_EOF
  chmod +x "$HOOK"
  echo "hook: installed pre-commit guard"
fi

# 4. Resolve the remote: arg > .private-remote > existing sidecar origin >
# convention: gh repo "private-<dirname>" under the logged-in user, created
# on demand. Config beats convention; convention beats asking.
if [ -z "$REMOTE" ] && [ -f .private-remote ]; then
  REMOTE="$(cat .private-remote)"
fi
if [ -z "$REMOTE" ] && [ -d .private/.git ]; then
  REMOTE="$(git -C .private remote get-url origin 2>/dev/null || true)"
fi
if [ -z "$REMOTE" ] && command -v gh >/dev/null 2>&1; then
  GH_USER="$(gh api user -q .login 2>/dev/null || true)"
  if [ -n "$GH_USER" ]; then
    NAME="private-$(basename "$PWD")"
    if ! gh repo view "$GH_USER/$NAME" >/dev/null 2>&1; then
      gh repo create "$GH_USER/$NAME" --private >/dev/null
      echo "remote: created private GitHub repo $GH_USER/$NAME"
    fi
    REMOTE="git@github.com:$GH_USER/$NAME.git"
  fi
fi
if [ -n "$REMOTE" ]; then
  printf '%s\n' "$REMOTE" > .private-remote
  echo "remote: $REMOTE"
else
  echo "note: no remote (no arg, no .private-remote, gh unavailable)."
  echo "      Write the sidecar's git URL to .private-remote when you have one."
fi

# 5. Skillfile, so an agent that clones the public repo learns the rest.
# A symlink here means the project distributes the skill through its sidecar
# (.private/skills/): that copy syncs via sidecar push/pull and is never
# clobbered from the kit. Kit edits reach it by deliberate merge.
mkdir -p .claude/skills/private-sync
if [ -L .claude/skills/private-sync/SKILL.md ]; then
  echo "skill: sidecar-managed (symlink into .private/skills/), left alone"
else
  cp "$KIT/skill/SKILL.md" .claude/skills/private-sync/SKILL.md
  echo "skill: installed .claude/skills/private-sync/"
fi

# 5b. Memory-file pointer: ambient knowledge for agents that read memory but
# never check skills. CLAUDE.md (Claude Code, omp) and AGENTS.md (pi/codex
# style). Replaced between markers on every run so pointer updates propagate.
# A legacy block without the end marker sits at EOF, so delete-to-EOF is safe.
for MEMFILE in CLAUDE.md AGENTS.md; do
  if grep -q 'private-sync pointer' "$MEMFILE" 2>/dev/null; then
    awk '/<!-- private-sync pointer -->/{skip=1} !skip{print} /<!-- \/private-sync pointer -->/{skip=0}' \
      "$MEMFILE" > "$MEMFILE.tmp" && mv "$MEMFILE.tmp" "$MEMFILE"
  fi
  cat "$KIT/claude-md-pointer.md" >> "$MEMFILE"
done
echo "pointer: refreshed in CLAUDE.md + AGENTS.md"

# 6. Materialize .private/: clone if the remote has history, seed from the
# template otherwise. Never clobber real notes.
if [ -d .private ]; then
  echo "sidecar: .private/ already exists, left alone"
elif [ -n "$REMOTE" ] && [ -n "$(git ls-remote "$REMOTE" 2>/dev/null)" ]; then
  git clone -q "$REMOTE" .private
  echo "sidecar: cloned from $REMOTE"
else
  cp -R "$KIT/template" .private
  echo "sidecar: seeded .private/ from template"
fi

# 6b. Tool manifest, added to existing sidecars that predate it.
[ -f .private/mise.toml ] || cp "$KIT/template/mise.toml" .private/mise.toml

# 7. Sidecar tooling, refreshed on every run (fresh and existing alike).
mkdir -p .private/bin
for TOOL in private-index private-session-start; do
  cp -f "$KIT/bin/$TOOL" ".private/bin/$TOOL"
  chmod +x ".private/bin/$TOOL"
done
echo "bin: installed .private/bin/{private-index,private-session-start}"

# 7b. SessionStart hook: pull the sidecar, rebuild the index, surface stale
# claims - every session starts current. Merged into existing settings with
# jq, never clobbered.
SESSION_CMD=".private/bin/private-session-start"
if [ ! -f .claude/settings.json ]; then
  printf '{\n  "hooks": {\n    "SessionStart": [\n      { "hooks": [ { "type": "command", "command": "%s" } ] }\n    ]\n  }\n}\n' "$SESSION_CMD" > .claude/settings.json
  echo "settings: created .claude/settings.json with SessionStart hook"
elif ! grep -qF "$SESSION_CMD" .claude/settings.json; then
  if command -v jq >/dev/null 2>&1; then
    jq --arg cmd "$SESSION_CMD" \
      '.hooks.SessionStart = ((.hooks.SessionStart // []) + [{"hooks":[{"type":"command","command":$cmd}]}])' \
      .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
    echo "settings: merged SessionStart hook into .claude/settings.json"
  else
    echo "WARNING: .claude/settings.json exists and jq is missing; add by hand:" >&2
    echo "         SessionStart hook command: $SESSION_CMD" >&2
  fi
fi

# 7d. Share the sidecar into any linked worktrees of this checkout.
git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r WT; do
  [ "$WT" = "$(pwd -P)" ] && continue
  [ -e "$WT/.private" ] || { ln -s "$(pwd -P)/.private" "$WT/.private"; echo "worktree: linked $WT/.private"; }
done

# 8. Make the sidecar a live repo: init+commit if fresh, wire origin, push
# if it has never been pushed. Idempotent like everything above.
if [ ! -d .private/.git ]; then
  git -C .private init -q -b main
  git -C .private add -A
  git -C .private commit -q -m 'seed private notes'
  echo "sidecar: committed seed"
fi
if [ -n "$REMOTE" ]; then
  git -C .private remote add origin "$REMOTE" 2>/dev/null \
    || git -C .private remote set-url origin "$REMOTE"
  if ! git -C .private rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    if git -C .private push -q -u origin main; then
      echo "sidecar: pushed to $REMOTE"
    else
      echo "WARNING: push to $REMOTE failed; push by hand:" >&2
      echo "  git -C .private push -u origin main" >&2
    fi
  fi
else
  echo
  echo "Next: push it somewhere private, then record the URL:"
  echo "  git -C .private remote add origin <url> && git -C .private push -u origin main"
  echo "  echo <url> > .private-remote"
fi

# 8b. Sidecar-internal hooks. post-commit: push in the background, so claims
# and findings propagate without discipline. pre-commit: secret tripwire.
SIDECAR_HOOKS="$(git -C .private rev-parse --path-format=absolute --git-path hooks)"
mkdir -p "$SIDECAR_HOOKS"
for H in post-commit pre-commit; do
  if [ -e "$SIDECAR_HOOKS/$H" ] && ! grep -q 'private-sync' "$SIDECAR_HOOKS/$H" 2>/dev/null; then
    echo "WARNING: sidecar $H hook exists and is not ours; not touching it." >&2
  fi
done
if [ ! -e "$SIDECAR_HOOKS/post-commit" ] || grep -q 'private-sync' "$SIDECAR_HOOKS/post-commit" 2>/dev/null; then
  cat > "$SIDECAR_HOOKS/post-commit" <<'PC_EOF'
#!/bin/sh
# private-sync auto-push: done means pushed, without relying on discipline.
(git push -q origin HEAD 2>/dev/null || true) &
PC_EOF
  chmod +x "$SIDECAR_HOOKS/post-commit"
fi
if [ ! -e "$SIDECAR_HOOKS/pre-commit" ] || grep -q 'private-sync' "$SIDECAR_HOOKS/pre-commit" 2>/dev/null; then
  cat > "$SIDECAR_HOOKS/pre-commit" <<'SC_EOF'
#!/bin/sh
# private-sync secret tripwire: notes reference where a secret lives, never
# its value. Override for a false positive: PRIVATE_SYNC_ALLOW_SECRETS=1
[ -n "${PRIVATE_SYNC_ALLOW_SECRETS:-}" ] && exit 0
HITS=$(git diff --cached -U0 \
  | grep -nE '(ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-[A-Za-z0-9-]{10,}|sk-(ant-)?[A-Za-z0-9-]{20,})' \
  || true)
if [ -n "$HITS" ]; then
  echo "BLOCKED: possible secret staged in the sidecar:" >&2
  echo "$HITS" | head -5 | sed 's/^/  /' >&2
  echo "Reference the secret's location, never its value (private-sync skill)." >&2
  echo "False positive? PRIVATE_SYNC_ALLOW_SECRETS=1 git -C .private commit ..." >&2
  exit 1
fi
SC_EOF
  chmod +x "$SIDECAR_HOOKS/pre-commit"
fi
echo "sidecar hooks: auto-push (post-commit) + secret tripwire (pre-commit)"

# 9. Backlog task tracking, initialized non-interactively if absent.
if [ ! -d .private/backlog ]; then
  if command -v backlog >/dev/null 2>&1; then
    PROJ_NAME="$(basename "$PWD")"
    (cd .private && backlog init "$PROJ_NAME" --defaults --agent-instructions claude,agents >/dev/null)
    git -C .private add -A
    git -C .private commit -q -m 'backlog init' 2>/dev/null || true
    { [ -n "$REMOTE" ] && git -C .private push -q 2>/dev/null; } || true
    echo "backlog: initialized in .private/"
  else
    echo "note: backlog CLI missing (npm i -g backlog.md) - task tracking degrades to WIP markers"
  fi
fi

# 10. Register this install so --update-all finds it.
mkdir -p "$(dirname "$REGISTRY")"
grep -qxF "$PWD" "$REGISTRY" 2>/dev/null || printf '%s\n' "$PWD" >> "$REGISTRY"

echo
echo "Done. .private/ is gitignored, excluded, and hook-guarded."
