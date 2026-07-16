#!/usr/bin/env bash
#
# Claude Code hook: fetch with --prune and delete local branches whose
# upstream remote-tracking ref has been removed (marked [gone]).
#
# Safe by default:
#  - Runs only inside a git work tree
#  - Skips the current HEAD branch and a protected list
#  - Uses `git branch -d` (refuses to drop unmerged branches)
#  - Silent no-op on errors so it never blocks a Claude session
#
# Env overrides:
#   REMOTE=origin                  Remote to fetch/prune (default: origin)
#   PRUNE_DRY_RUN=1                Print actions but don't delete

set -u

REMOTE="${REMOTE:-origin}"
PROTECTED=("main" "master" "develop" "staging" "prerelease-4.5.0")

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  exit 0
fi

echo "[prune-gone-branches] fetching '$REMOTE' with --prune..."
git fetch --prune "$REMOTE" >/dev/null 2>&1 || { echo "[prune-gone-branches] fetch failed — skipping"; exit 0; }

current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"

is_protected() {
  local b="$1"
  [[ "$b" == "$current_branch" ]] && return 0
  for p in "${PROTECTED[@]}"; do
    [[ "$b" == "$p" ]] && return 0
  done
  return 1
}

deleted=0
skipped=0
while IFS='|' read -r branch track; do
  [[ "$track" == *"[gone]"* ]] || continue
  if is_protected "$branch"; then
    skipped=$((skipped + 1))
    continue
  fi
  if [[ "${PRUNE_DRY_RUN:-0}" == "1" ]]; then
    echo "[prune-gone-branches] would delete: $branch"
    continue
  fi
  if git branch -d "$branch" >/dev/null 2>&1; then
    echo "[prune-gone-branches] deleted: $branch"
    deleted=$((deleted + 1))
  else
    echo "[prune-gone-branches] kept (unmerged): $branch — use 'git branch -D $branch' to force"
  fi
done < <(git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads)

if [[ $deleted -eq 0 && $skipped -eq 0 ]]; then
  echo "[prune-gone-branches] no gone branches to clean"
fi

exit 0
