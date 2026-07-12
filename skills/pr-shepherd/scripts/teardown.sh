#!/usr/bin/env bash
#
# Batch teardown — remove a batch's agent worktrees + local branches and
# reconcile the default branch, so a parallel-shipping run leaves NO debris.
# Run after the coordinator merge loop, every batch.
#
# Usage:
#   teardown.sh <worktree_path> [<worktree_path> ...]   # explicit, from the batch manifest
#   teardown.sh --sweep                                  # every .claude/worktrees/agent-*
#                                                        #   whose remote branch is gone, PLUS
#                                                        #   orphan isolation branches whose
#                                                        #   worktree is already gone
#   teardown.sh --reconcile-only                         # skip all worktree/branch phases; just
#                                                        #   the default-branch reconcile (switch,
#                                                        #   fetch --prune, clear ff-blocking
#                                                        #   stragglers, pull --ff-only) + report.
#                                                        #   A failed ff exits 1 in this mode
#                                                        #   (other modes warn and continue).
# Env:
#   DEFAULT_BRANCH            override the reconcile target (default: origin/HEAD, fallback "main")
#   ISOLATION_BRANCH_PREFIX   prefix of the Agent runtime's isolation branches
#                             (default "worktree-agent-")
#
# Why "remote branch gone", not `git branch --merged`:
#   Squash-merged feature branches' tips are NOT ancestors of the default branch
#   — `git branch --merged` reports them UNMERGED (false negative). As long as
#   merges delete the remote branch (delete_branch_on_merge, or the merge queue's
#   own deletion), "origin no longer has this branch" is the reliable merged signal.
#
# Isolation branches (issue #26): the Agent runtime checks each agent worktree out
# on a worktree-agent-<id> branch. The PR merges from the agent's FEATURE branch,
# so the isolation branch never gets an upstream — never [gone], and once the
# worktree directory is torn down there is no path to sweep either; one orphan
# accumulates per merge. So: removing a worktree here ALSO deletes its isolation
# branch (prevention), and --sweep classifies leftover orphans (worktree gone) by
# default-branch ancestry OR a MERGED PR containing the tip (squash-merge
# false-negative safe); genuinely unmerged ones are surfaced, never auto-deleted.
# Isolation branches whose worktree is still present are LIVE agents — --sweep
# never touches them ("no upstream" is their normal state, not a merged signal).
#
# Worktrees are removed with `-f -f` because the Agent runtime leaves them locked.
# Stashes are reported but NEVER auto-dropped (destructive — human's call).
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && { echo "teardown: not in a git repo" >&2; exit 1; }
cd "$ROOT" || { echo "teardown: cannot cd to $ROOT" >&2; exit 1; }

BRANCH="${DEFAULT_BRANCH:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')}"
[ -z "$BRANCH" ] && BRANCH=main

ISO_PREFIX="${ISOLATION_BRANCH_PREFIX:-worktree-agent-}"

branch_in_live_worktree() {  # $1 = branch — true if ANY worktree has it checked out
  git worktree list --porcelain | grep -qxF "branch refs/heads/$1"
}

# Delete an isolation branch left behind by its worktree. No-op unless the name
# matches the isolation prefix; never the default branch; never a branch a live
# worktree has checked out.
delete_isolation_branch() {  # $1 = candidate branch name (may be empty / non-isolation)
  local br="$1"
  [ -n "$br" ] || return 0
  case "$br" in "$ISO_PREFIX"*) : ;; *) return 0 ;; esac
  [ "$br" = "$BRANCH" ] && return 0
  git show-ref --verify --quiet "refs/heads/$br" || return 0
  if branch_in_live_worktree "$br"; then
    echo "    KEEP isolation branch $br (checked out by a live worktree)"; return 0
  fi
  git branch -D "$br" >/dev/null 2>&1 && echo "    deleted isolation branch $br" \
    || echo "    ⚠ could not delete isolation branch $br"
}

remove_worktree() {  # $1 = worktree path
  local path="$1" br iso
  # The isolation branch the runtime created this worktree on (worktree-<dirname>).
  # Derived from the PATH, not the checkout: if the agent switched to a feature
  # branch, `branch --show-current` no longer names it — yet it still exists and
  # would otherwise be orphaned (issue #26).
  iso="worktree-$(basename "$path")"
  if [ ! -d "$path" ]; then
    echo "  (already gone) $path"
    delete_isolation_branch "$iso"
    return
  fi
  br="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  if git worktree remove -f -f "$path" 2>/dev/null; then
    echo "  removed worktree $path${br:+ [$br]}"
  else
    echo "  ⚠ could not remove $path (still locked / dirty?)"; return
  fi
  if [ -n "$br" ]; then
    git branch -D "$br" >/dev/null 2>&1 && echo "    deleted local branch $br" || true
  fi
  if [ "$iso" != "$br" ]; then delete_isolation_branch "$iso"; fi
}

RECONCILE_ONLY=0
if [ "${1:-}" = "--reconcile-only" ]; then
  RECONCILE_ONLY=1
elif [ "${1:-}" = "--sweep" ]; then
  echo "== sweep: agent worktrees whose remote branch is gone (squash-merged + deleted) =="
  git fetch --prune --quiet origin 2>/dev/null || true
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    br="$(git -C "$path" branch --show-current 2>/dev/null || true)"
    if [ -z "$br" ]; then echo "  detached → removing: $path"; remove_worktree "$path"; continue; fi
    case "$br" in
      "$ISO_PREFIX"*)
        # Still checked out on its isolation branch: possibly a LIVE agent that has
        # not branched yet. "No remote" is this branch's NORMAL state — not a merged
        # signal — so never sweep it by inference; pass the path explicitly if it's
        # known debris (crashed run).
        echo "  KEEP (live isolation worktree — pass its path explicitly if debris): $path [$br]"
        continue ;;
    esac
    if git ls-remote --exit-code --heads origin "$br" >/dev/null 2>&1; then
      echo "  KEEP (remote branch still exists, PR likely open): $path [$br]"
    else
      echo "  gone/merged: $path [$br]"; remove_worktree "$path"
    fi
  done < <(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/.claude/worktrees/" || true)

  echo "== sweep: orphan ${ISO_PREFIX}* isolation branches (worktree gone — never [gone]) =="
  # Left behind when a per-merge teardown removed the worktree but not the branch
  # (pre-#26 flows, crashed runs). Ancestry alone is NOT enough: a squash-merge
  # leaves the pre-squash tip dangling (same false negative as feature branches),
  # so a non-ancestor tip is checked against MERGED PRs before deciding.
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  while read -r br tip; do
    [ -z "$br" ] && continue
    [ "$br" = "$BRANCH" ] && continue
    if branch_in_live_worktree "$br"; then
      echo "  KEEP $br (worktree still present — live)"; continue
    fi
    if git merge-base --is-ancestor "$tip" "origin/$BRANCH" 2>/dev/null; then
      git branch -D "$br" >/dev/null 2>&1 && echo "  deleted $br (tip already in origin/$BRANCH)"
      continue
    fi
    merged_pr=""
    [ -n "$REPO_SLUG" ] && merged_pr="$(gh api "repos/$REPO_SLUG/commits/$tip/pulls" \
      --jq '[.[] | select(.merged_at != null)][0].number // empty' 2>/dev/null || true)"
    if [ -n "$merged_pr" ]; then
      git branch -D "$br" >/dev/null 2>&1 && echo "  deleted $br (shipped via merged PR #$merged_pr)"
    else
      echo "  ⚠ KEEP $br — tip ${tip:0:7} not in origin/$BRANCH and no merged PR contains it; possibly unmerged work — review by hand"
    fi
  done < <(git for-each-ref --format='%(refname:short) %(objectname)' "refs/heads/${ISO_PREFIX}*" || true)
elif [ "$#" -gt 0 ]; then
  echo "== explicit teardown of $# worktree(s) =="
  for path in "$@"; do remove_worktree "$path"; done
else
  echo "teardown: pass worktree path(s), --sweep, or --reconcile-only" >&2; exit 2
fi

[ "$RECONCILE_ONLY" = "1" ] || git worktree prune

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
  # In --reconcile-only mode the ff IS the job — surface the failure to the caller.
  # Explicit/sweep modes keep warn-and-continue: teardown already did its real work.
  [ "$RECONCILE_ONLY" = "1" ] && exit 1
fi

echo "== residual =="
RW=$(git worktree list | grep -c "/.claude/worktrees/" || true)
echo "  agent worktrees remaining: $RW"
IB=$(git for-each-ref --format='%(refname:short)' "refs/heads/${ISO_PREFIX}*" | wc -l | tr -d ' ')
[ "$IB" != "0" ] && echo "  ⚠ $IB isolation branch(es) (${ISO_PREFIX}*) remaining — live or unmerged; see above"
SL=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
[ "$SL" != "0" ] && echo "  ⚠ $SL stash(es) present — teardown does NOT auto-drop; review by hand"
exit 0
