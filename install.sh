#!/bin/sh
# Install the .private/ sidecar into a project.
#
#   ./install.sh /path/to/project [remote-url]
#
# Idempotent: safe to re-run. Never overwrites an existing .private/.
set -eu

KIT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:?usage: install.sh /path/to/project [remote-url]}"
REMOTE="${2:-}"

[ -d "$PROJECT" ] || { echo "no such directory: $PROJECT" >&2; exit 1; }
git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "not a git repo: $PROJECT" >&2; exit 1; }

# In a linked worktree .git is a file; shared state lives in the common dir.
COMMON_GIT="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)"

cd "$PROJECT"

# 1. gitignore, belt.
for pat in '.private/' '.private-remote'; do
  if ! grep -qxF "$pat" .gitignore 2>/dev/null; then
    printf '%s\n' "$pat" >> .gitignore
    echo "gitignore: added $pat"
  fi
done

# 2. info/exclude, suspenders. Survives a clobbered .gitignore. Lives in the
# common dir, so one install covers every linked worktree.
mkdir -p "$COMMON_GIT/info"
if ! grep -qxF '.private/' "$COMMON_GIT/info/exclude" 2>/dev/null; then
  printf '.private/\n' >> "$COMMON_GIT/info/exclude"
  echo "info/exclude: added .private/"
fi

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
LEAKED=$(git diff --cached --name-only | grep '^\.private/' || true)
if [ -n "$LEAKED" ]; then
  echo "BLOCKED: .private/ is staged for the public repo." >&2
  echo "$LEAKED" | sed 's/^/  /' >&2
  git restore --staged .private 2>/dev/null || git reset -q HEAD -- .private 2>/dev/null || true
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
mkdir -p .claude/skills/private-sync
cp "$KIT/skill/SKILL.md" .claude/skills/private-sync/SKILL.md
echo "skill: installed .claude/skills/private-sync/"

# 5b. Memory-file pointer: ambient knowledge for agents that read memory but
# never check skills. CLAUDE.md (Claude Code, omp) and AGENTS.md (pi/codex
# style). Appended once each, marker-guarded.
for MEMFILE in CLAUDE.md AGENTS.md; do
  if ! grep -q 'private-sync pointer' "$MEMFILE" 2>/dev/null; then
    cat "$KIT/claude-md-pointer.md" >> "$MEMFILE"
    echo "$MEMFILE: appended .private/ pointer"
  fi
done

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

# 7. Index tooling, refreshed on every run (fresh and existing sidecars alike).
mkdir -p .private/bin
cp -f "$KIT/bin/private-index" .private/bin/private-index
chmod +x .private/bin/private-index
echo "bin: installed .private/bin/private-index"

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

echo
echo "Done. .private/ is gitignored, excluded, and hook-guarded."
