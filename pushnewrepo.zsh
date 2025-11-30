#!/bin/zsh
set -euo pipefail

# ----- Config -----
REQUIRED_USER="mohdazlanabas"
DEFAULT_VISIBILITY="public"

# ----- Input -----
print -n "Enter new repo name: "
read -r REPO_NAME
[ -z "${REPO_NAME:-}" ] && print "Repo name required." && exit 1

print -n "Visibility [public/private] (default: $DEFAULT_VISIBILITY): "
read -r VISIBILITY
VISIBILITY="${VISIBILITY:-$DEFAULT_VISIBILITY}"
[[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" ]] && { print "Visibility must be public or private."; exit 1; }

# ----- Preconditions -----
command -v gh >/dev/null || { print "Install GitHub CLI: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { print "Not logged in. Run: gh auth login"; exit 1; }

CURRENT_USER="$(gh api user -q .login)"
if [[ "$CURRENT_USER" != "$REQUIRED_USER" ]]; then
  print "You are logged in as '$CURRENT_USER', but must be '$REQUIRED_USER'."
  print "Re-authenticating..."
  gh auth logout --hostname github.com
  gh auth login --hostname github.com
  CURRENT_USER="$(gh api user -q .login)"
  [[ "$CURRENT_USER" != "$REQUIRED_USER" ]] && { print "Still logged in as '$CURRENT_USER'. Aborting."; exit 1; }
fi

# ----- Git init & first commit -----
if [ ! -d .git ]; then git init; fi
git checkout -B main
# stage anything new
git add -A
# ensure at least one commit
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git commit -m "Initial commit - ${REPO_NAME}"
else
  if ! git diff --cached --quiet; then
    git commit -m "Initial commit (additional files) - ${REPO_NAME}"
  fi
fi

# remove stale origin if any
git remote remove origin 2>/dev/null || true

# ----- Create repo & push -----
print "Creating $VISIBILITY repo on GitHub: ${REQUIRED_USER}/${REPO_NAME}"
gh repo create "${REQUIRED_USER}/${REPO_NAME}" --"$VISIBILITY" --source=. --remote=origin --push

# make sure remote is SSH
git remote set-url origin "git@github.com:${REQUIRED_USER}/${REPO_NAME}.git"
git push -u origin main

# ----- Open -----
gh repo view "${REQUIRED_USER}/${REPO_NAME}" --web
print "✅ Done: ${REQUIRED_USER}/${REPO_NAME}"
