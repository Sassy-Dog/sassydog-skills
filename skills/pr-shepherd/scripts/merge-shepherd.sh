#!/usr/bin/env bash
# merge-shepherd.sh — stateless, idempotent single-writer merge step for ONE PR.
#
# Why this exists: the bundled pollers (poll-prs.sh, poll-queue.sh) are
# read-only WATCHERS — all writes stay with the coordinating session. But the
# write step is where long-lived sessions die: on a memory-pressured host,
# macOS memorystatus/jetsam reaps idle long-lived loops at aperiodic intervals,
# and a babysitting session dies mid-merge needing manual re-launch. This
# script inverts that: every run is a SHORT, STATELESS "advance one step"
# against live GitHub state, so a kill mid-run costs nothing — just run it
# again. Under a merge queue, `--auto` keeps the merge itself server-side and
# kill-proof; this adds resilient enqueue + confirmation + teardown.
#
# One step per run: mergeable check → red/pending gate → enqueue `--auto`
# with NO method flag (or `--direct` squash-merge) → GraphQL isInMergeQueue
# confirmation → teardown + ff-only default-branch reconcile.
#
# Usage:
#   merge-shepherd.sh <pr> [--repo owner/name] [--worktree <path>] [--direct]
#                     [--watch <secs>] [--poll <secs>]
#   Single-shot by default (advances one step, exits). --watch N polls up to N
#   seconds (keep N under the host's kill window, e.g. 240) then exits cleanly.
#   --direct: for repos WITHOUT a merge queue — squash-merge + --delete-branch
#   instead of enqueueing. Default is queue mode (--auto, NO method flag).
#   Repo defaults to the cwd checkout (gh repo view); --repo overrides.
#
# Env:
#   DEFAULT_BRANCH   reconcile target (default: origin/HEAD, fallback "main")
#                    — same contract as teardown.sh
#
# Exit codes: 0 merged(+teardown) · 10 enqueued · 11 waiting/in-flight (re-run)
#             · 20 red checks · 22 conflicting · 1 usage/error/closed
#
# SINGLE-WRITER CONTRACT: one owner per PR. Never point this writer and a
# watcher session — or two writers — at the same PR from different sessions.
#
# NOTE on queue ejects: a stateless run cannot distinguish "ejected from the
# queue" from "never enqueued" (head-commit checks stay green either way), so
# an ejected-but-CLEAN PR is simply re-enqueued on the next pass — the right
# recovery for transient/false ejects. A PR that keeps failing merge_group
# checks on the rebased ref will ping-pong; that needs a human (rebase +
# regenerate — see references/merge-queue.md "Eject recovery", and
# poll-queue.sh for eject-aware watching).
#
# Requires the sibling gh-retry.sh (transient/non-transient retry split) —
# copy both files together if lifting this script out of the plugin.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_RETRY="$SCRIPT_DIR/gh-retry.sh"

REPO=""; PR=""; WT=""; WATCH=0; POLL=30; DIRECT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --worktree) WT="$2"; shift 2 ;;
    --watch) WATCH="$2"; shift 2 ;;
    --poll) POLL="$2"; shift 2 ;;
    --direct) DIRECT=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [ -z "$PR" ]; then PR="$1"; shift; else echo "unexpected arg: $1" >&2; exit 1; fi ;;
  esac
done
[ -n "$PR" ] || { echo "usage: merge-shepherd.sh <pr> [--repo o/n] [--worktree p] [--direct] [--watch s] [--poll s]" >&2; exit 1; }
case "$PR" in *[!0-9]*|'') echo "PR must be numeric, got: $PR" >&2; exit 1 ;; esac
case "$WATCH" in *[!0-9]*|'') echo "--watch must be numeric, got: $WATCH" >&2; exit 1 ;; esac
case "$POLL" in *[!0-9]*|'') echo "--poll must be numeric, got: $POLL" >&2; exit 1 ;; esac

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "$REPO" ] || { echo "error: not in a GitHub repo and --repo not given" >&2; exit 1; }
fi
case "$REPO" in */*) : ;; *) echo "error: repo must be owner/name, got: $REPO" >&2; exit 1 ;; esac
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# The MAIN worktree is the first entry of `git worktree list` — NOT
# --show-toplevel, which returns the linked worktree when invoked from inside
# one (teardown would then no-op against the dir it's removing).
MAIN_WT="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
BRANCH="${DEFAULT_BRANCH:-$(git -C "${MAIN_WT:-.}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')}"
[ -z "$BRANCH" ] && BRANCH=main

# Retry transient git network failures (the pressure-induced gh-credential
# subprocess 401, plus 5xx and ref-lock contention). Backs off, then gives up.
git_retry() {
  local n=0 max=5
  until git "$@"; do
    n=$((n+1)); [ "$n" -ge "$max" ] && { echo "  git $1 failed after $max tries" >&2; return 1; }
    echo "  git $1 transient failure — retry $n/$max" >&2; sleep $((n*3))
  done
}

# isInMergeQueue is GraphQL-only (`gh pr view --json isInMergeQueue` fails
# with `Unknown JSON field`) — same query as poll-queue.sh.
pr_state() { # -> "STATE MERGESTATE INQUEUE"
  gh api graphql \
    -f query='query($owner:String!,$name:String!,$pr:Int!){
        repository(owner:$owner,name:$name){
            pullRequest(number:$pr){ state mergeStateStatus isInMergeQueue }}}' \
    -f owner="$OWNER" -f name="$NAME" -F pr="$PR" \
    --jq '.data.repository.pullRequest | "\(.state) \(.mergeStateStatus) \(.isInMergeQueue)"' 2>/dev/null
}

checks() { # -> "FAILS PENDING"
  # Handles both rollup node types (issue #17): CheckRun (.status/.conclusion)
  # and legacy StatusContext (.state only — a bare `.status!="COMPLETED"` or
  # `.conclusion==null` would count every StatusContext as forever-pending and
  # silently block the merge). EXPECTED counts as pending, matching
  # poll-prs.sh's PENDING_FILTER.
  gh pr view "$PR" --repo "$REPO" --json statusCheckRollup --jq \
    '"\([.statusCheckRollup[]?|select((.conclusion=="FAILURE"or .conclusion=="CANCELLED"or .conclusion=="TIMED_OUT") or (.state=="FAILURE"or .state=="ERROR"))]|length) \([.statusCheckRollup[]?|select((.status!=null and .status!="COMPLETED") or .state=="PENDING" or .state=="EXPECTED")]|length)"' 2>/dev/null
}

teardown() { # idempotent: safe whether or not the worktree/branch still exist
  [ -z "$MAIN_WT" ] && { echo "  (no local checkout — skipping teardown)"; return 0; }
  if [ -n "$WT" ] && [ -e "$WT" ]; then
    git -C "$MAIN_WT" worktree remove --force "$WT" 2>/dev/null && echo "  worktree removed" \
      || echo "  ⚠ worktree not removed (locked/dirty?) — teardown.sh --sweep mops up later"
  fi
  git -C "$MAIN_WT" worktree prune 2>/dev/null || true
  git -C "$MAIN_WT" switch "$BRANCH" >/dev/null 2>&1 || true
  git_retry -C "$MAIN_WT" fetch origin "$BRANCH" --quiet || true
  git -C "$MAIN_WT" merge --ff-only "origin/$BRANCH" >/dev/null 2>&1 \
    || echo "  ff reconcile skipped (residual local state — check by hand)"
  echo "  $BRANCH @ $(git -C "$MAIN_WT" log --oneline -1 2>/dev/null)"
}

advance() { # one idempotent step against live state
  local st ms inq fails pend
  read -r st ms inq <<<"$(pr_state)"
  [ -z "$st" ] && { echo "state unavailable (transient) — retry later"; return 11; }
  case "$st" in
    MERGED) echo "MERGED — tearing down"; teardown; return 0 ;;
    CLOSED) echo "CLOSED (not merged)"; return 1 ;;
  esac
  # OPEN:
  read -r fails pend <<<"$(checks)"
  [ "$ms" = CONFLICTING ] && { echo "CONFLICTING — needs human/rebase (do NOT auto-rebase)"; return 22; }
  if [ "$inq" = "true" ]; then echo "IN_QUEUE (waiting)"; return 11; fi
  # Deliberately conservative: counts ADVISORY failures too (e.g. a
  # non-blocking dependency scan), so a PR the queue would accept can still
  # report RED here. Fail-safe by design — a human decides, not the script.
  if [ "${fails:-0}" -gt 0 ] && [ "${pend:-0}" -eq 0 ] && [ "$ms" != CLEAN ]; then
    echo "RED — failing checks (do NOT merge):"
    gh pr checks "$PR" --repo "$REPO" 2>/dev/null | grep -i fail || true
    return 20
  fi
  if [ "$ms" = CLEAN ] && [ "${pend:-1}" -eq 0 ]; then
    if [ "$DIRECT" = 1 ]; then
      echo "CLEAN — direct merge (--squash --delete-branch)"
      bash "$GH_RETRY" -- pr merge "$PR" --repo "$REPO" --squash --delete-branch >/dev/null \
        || echo "  merge call failed (checking whether it took anyway)" >&2
      sleep 5
      read -r st _ _ <<<"$(pr_state)"
      if [ "$st" = MERGED ]; then echo "  MERGED — tearing down"; teardown; return 0; fi
      echo "  merge not confirmed — re-run"; return 11
    fi
    echo "CLEAN — enqueuing (--auto, no method flag)"
    bash "$GH_RETRY" -- pr merge "$PR" --repo "$REPO" --auto >/dev/null \
      || echo "  enqueue call failed (checking whether it took anyway)" >&2
    sleep 8
    read -r _ _ inq <<<"$(pr_state)"
    if [ "$inq" = "true" ]; then
      echo "  enqueued (isInMergeQueue=true)"; return 10
    else
      echo "  enqueue not confirmed — re-run"; return 11
    fi
  fi
  echo "WAITING (checks pending: ${pend:-?}, fails: ${fails:-0})"; return 11
}

# Single-shot, or bounded watch (exits cleanly within the host's kill window).
deadline=$((SECONDS + WATCH))
while :; do
  out="$(advance)"; rc=$?
  printf '[%ds] %s\n' "$SECONDS" "$out"
  case "$rc" in 0|1|20|22) exit "$rc" ;; esac    # terminal — stop
  [ "$WATCH" -le 0 ] && exit "$rc"               # single-shot
  [ "$SECONDS" -ge "$deadline" ] && { echo "[bounded-exit] still in-flight — re-run to resume"; exit "$rc"; }
  sleep "$POLL"
done
