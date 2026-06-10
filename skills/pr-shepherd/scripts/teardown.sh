#!/usr/bin/env bash
#
# Batch teardown — remove a batch's agent worktrees + local branches and
# reconcile the default branch, so a parallel-shipping run leaves NO debris.
# Run after the coordinator merge loop, every batch.
#
# Usage:
#   teardown.sh <worktree_path> [<worktree_path> ...]   # explicit, from the batch manifest
#   teardown.sh --sweep                                  # every .claude/worktrees/agent-*
#                                                        #   whose remote branch is gone
# Env:
#   DEFAULT_BRANCH   override the reconcile target (default: origin/HEAD, fallback "main")
#
# Why "remote branch gone", not `git branch --merged`:
#   Squash-merged feature branches' tips are NOT ancestors of the default branch
#   — `git branch --merged` reports them UNMERGED (false negative). As long as
#   merges delete the remote branch (delete_branch_on_merge, or the merge queue's
#   own deletion), "origin no longer has this branch" is the reliable merged signal.
#
# Worktrees are removed with `-f -f` because the Agent runtime leaves them locked.
# Stashes are reported but NEVER auto-dropped (destructive — human's call).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && { echo "teardown: not in a git repo" >&2; exit 1; }
cd "$ROOT" || { echo "teardown: cannot cd to $ROOT" >&2; exit 1; }

BRANCH="${DEFAULT_BRANCH:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')}"
[ -z "$BRANCH" ] && BRANCH=main

remove_worktree() {  # $1 = worktree path
  local path="$1" br
  if [ ! -d "$path" ]; then echo "  (already gone) $path"; return; fi
  br="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  if git worktree remove -f -f "$path" 2>/dev/null; then
    echo "  removed worktree $path${br:+ [$br]}"
  else
    echo "  ⚠ could not remove $path (still locked / dirty?)"; return
  fi
  if [ -n "$br" ]; then
    git branch -D "$br" >/dev/null 2>&1 && echo "    deleted local branch $br" || true
  fi
}

if [ "${1:-}" = "--sweep" ]; then
  echo "== sweep: agent worktrees whose remote branch is gone (squash-merged + deleted) =="
  git fetch --prune --quiet origin 2>/dev/null || true
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    br="$(git -C "$path" branch --show-current 2>/dev/null || true)"
    if [ -z "$br" ]; then echo "  detached → removing: $path"; remove_worktree "$path"; continue; fi
    if git ls-remote --exit-code --heads origin "$br" >/dev/null 2>&1; then
      echo "  KEEP (remote branch still exists, PR likely open): $path [$br]"
    else
      echo "  gone/merged: $path [$br]"; remove_worktree "$path"
    fi
  done < <(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/.claude/worktrees/" || true)
elif [ "$#" -gt 0 ]; then
  echo "== explicit teardown of $# worktree(s) =="
  for path in "$@"; do remove_worktree "$path"; done
else
  echo "teardown: pass worktree path(s) or --sweep" >&2; exit 2
fi

git worktree prune

echo "== reconcile $BRANCH =="
git switch "$BRANCH" >/dev/null 2>&1 || true
git fetch origin "$BRANCH" --prune --quiet
# Clear cwd-reset stragglers: untracked files that are now TRACKED on origin/<branch>
# AND byte-identical there (so nothing is lost) — these block the ff otherwise.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if git cat-file -e "origin/$BRANCH:$f" 2>/dev/null && git show "origin/$BRANCH:$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1; then
    rm -f "$f" && echo "  cleared straggler (identical to origin/$BRANCH): $f"
  fi
done < <(git ls-files --others --exclude-standard || true)
if git pull --ff-only origin "$BRANCH" >/dev/null 2>&1; then
  echo "  $BRANCH @ $(git rev-parse --short HEAD)"
else
  echo "  ⚠ ff-only reconcile failed — residual local changes; clean up by hand"
fi

echo "== residual =="
RW=$(git worktree list | grep -c "/.claude/worktrees/" || true)
echo "  agent worktrees remaining: $RW"
SL=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
[ "$SL" != "0" ] && echo "  ⚠ $SL stash(es) present — teardown does NOT auto-drop; review by hand"
exit 0
