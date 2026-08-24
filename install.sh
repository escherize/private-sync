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
[ -d "$PROJECT/.git" ] || { echo "not a git repo: $PROJECT" >&2; exit 1; }

cd "$PROJECT"

# 1. gitignore, belt.
for pat in '.private/' '.private-remote'; do
  if ! grep -qxF "$pat" .gitignore 2>/dev/null; then
    printf '%s\n' "$pat" >> .gitignore
    echo "gitignore: added $pat"
  fi
done

# 2. info/exclude, suspenders. Survives a clobbered .gitignore.
mkdir -p .git/info
if ! grep -qxF '.private/' .git/info/exclude 2>/dev/null; then
  printf '.private/\n' >> .git/info/exclude
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

# 4. Remote pointer, so the skill can bootstrap a clone.
if [ -n "$REMOTE" ]; then
  printf '%s\n' "$REMOTE" > .private-remote
  echo "remote: wrote .private-remote"
elif [ ! -f .private-remote ]; then
  echo "note: no remote given. Write the sidecar's git URL to .private-remote"
  echo "      when you have one, so agents can clone it."
fi

# 5. Skillfile, so an agent that clones the public repo learns the rest.
mkdir -p .claude/skills/private-sync
cp "$KIT/skill/SKILL.md" .claude/skills/private-sync/SKILL.md
echo "skill: installed .claude/skills/private-sync/"

# 6. Seed .private/ only if absent. Never clobber real notes.
if [ -d .private ]; then
  echo "sidecar: .private/ already exists, left alone"
else
  cp -R "$KIT/template" .private
  echo "sidecar: seeded .private/ from template"
  SEEDED=1
fi

# 7. Index tooling, refreshed on every run (fresh and existing sidecars alike).
mkdir -p .private/bin
cp -f "$KIT/bin/private-index" .private/bin/private-index
chmod +x .private/bin/private-index
echo "bin: installed .private/bin/private-index"

if [ "${SEEDED:-0}" = "1" ]; then
  echo
  echo "Next: make it its own repo and push it somewhere private."
  echo "  git -C .private init && git -C .private add -A"
  echo "  git -C .private commit -m 'seed private notes'"
  echo "  git -C .private remote add origin <url> && git -C .private push -u origin main"
fi

echo
echo "Done. .private/ is gitignored, excluded, and hook-guarded."
