#!/usr/bin/env bash
# stack-probe.sh — the single detection primitive for GitHub Stacked PRs.
#
# Why this exists: stack support needs TWO different probes, and collapsing
# them is a correctness bug, not a shortcut.
#
#   * "Is this repo enabled for stacks?"  -> REST GET /repos/{o}/{n}/stacks
#                                            200 = available, 404 = not enabled
#                                            (or no access — same conclusion).
#   * "Is THIS PR in a stack?"            -> GraphQL PullRequest.stack
#
# GraphQL returns `null` for BOTH "the repo isn't enabled" and "the PR isn't
# stacked". A caller that reads that single null concludes "not stacked, safe
# to merge" on a repo where it never actually checked. Hence both probes, in
# one place, so no caller re-derives the rule.
#
# `gh pr view --json` has NO `stack` field (same shape as `isInMergeQueue`),
# which is why membership goes through `gh api graphql` here.
#
# The stacked-PR REST surface is list/create/add/unstack only — there is no
# merge endpoint. Stacks merge bottom-up one layer at a time via plain
# `gh pr merge`, which is why `lower_open` below is the field that matters.
#
# Usage:
#   stack-probe.sh <pr> [--repo owner/name]   # membership for one PR
#   stack-probe.sh [--repo owner/name]        # repo probe + open-stack listing
#   Repo defaults to the cwd checkout (gh repo view); --repo overrides.
#
# Emits one JSON object on stdout. PR mode adds the derived fields the merge
# gate reads:
#   lower_open              layers BELOW this PR still OPEN -> must merge first
#   lower_closed_unmerged   layers BELOW this PR closed without merging ->
#                           the stack is broken; a human decides
#
# Exit codes (same convention as merge-shepherd.sh):
#   0   PR is in a stack (PR mode) / stacks available (repo mode)
#   10  stacks available in this repo, but this PR is not in one
#   11  stacks unavailable in this repo (not enabled, or no access)
#   1   usage or API error
#
# Read-only. Never creates, extends, dissolves, or merges anything.
set -uo pipefail

REPO=""; PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [ -z "$PR" ]; then PR="$1"; shift; else echo "unexpected arg: $1" >&2; exit 1; fi ;;
  esac
done

if [ -n "$PR" ]; then
  case "$PR" in *[!0-9]*) echo "PR must be numeric, got: $PR" >&2; exit 1 ;; esac
fi

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "$REPO" ] || { echo "error: not in a GitHub repo and --repo not given" >&2; exit 1; }
fi
case "$REPO" in */*) : ;; *) echo "error: repo must be owner/name, got: $REPO" >&2; exit 1 ;; esac
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

# --- availability -----------------------------------------------------------
# `gh api --include` writes the status line to stdout even on a 4xx (the body
# goes to stderr), so one call classifies the repo without a second round-trip.
# No status line at all = the request never completed (network/auth) -> error,
# NOT "unavailable"; silently degrading a transient failure into "no stacks
# here" is how a merge gate gets skipped exactly when it is needed.
probe="$(gh api "repos/$REPO/stacks?per_page=1" --include 2>/dev/null)"
http="$(printf '%s\n' "$probe" | sed -n 's|^HTTP/[0-9.]* \([0-9][0-9][0-9]\).*|\1|p' | tail -1)"

case "$http" in
  200)
    : ;;
  404|403)
    jq -nc --arg repo "$REPO" --arg http "$http" \
      '{repo:$repo, available:false, http:($http|tonumber), in_stack:false}'
    exit 11 ;;
  "")
    echo "error: stacks availability probe did not complete for $REPO (network/auth?)" >&2
    exit 1 ;;
  *)
    echo "error: unexpected HTTP $http from repos/$REPO/stacks" >&2
    exit 1 ;;
esac

# --- repo mode: list open stacks -------------------------------------------
if [ -z "$PR" ]; then
  stacks="$(gh api "repos/$REPO/stacks" --paginate 2>/dev/null)"
  [ -n "$stacks" ] || stacks='[]'
  printf '%s' "$stacks" | jq -c --arg repo "$REPO" \
    '{repo:$repo, available:true, pr:null,
      open_stacks:[ .[] | select(.open) | {
        stack_number:.number,
        base_ref:.base.ref,
        size:(.pull_requests|length),
        pull_requests:[.pull_requests[].number]
      } ]}'
  exit 0
fi

# --- PR mode: membership ----------------------------------------------------
# entries(first:100) is not paginated: `size` is emitted alongside so a caller
# can detect the (implausible) truncation rather than silently under-reporting
# lower layers.
raw="$(gh api graphql \
  -f query='query($owner:String!,$name:String!,$pr:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$pr){
          number
          stackEntry{ position }
          stack{
            number size baseRefName
            entries(first:100){ nodes{
              position
              pullRequest{ number state merged headRefName }
            }}
          }
        }
      }
    }' \
  -f owner="$OWNER" -f name="$NAME" -F pr="$PR" 2>/dev/null)"

[ -n "$raw" ] || { echo "error: stack membership query failed for $REPO#$PR" >&2; exit 1; }

pr_node="$(printf '%s' "$raw" | jq -c '.data.repository.pullRequest // empty')"
[ -n "$pr_node" ] || { echo "error: $REPO#$PR not found" >&2; exit 1; }

if [ "$(printf '%s' "$pr_node" | jq -r '.stack // "null"')" = "null" ]; then
  jq -nc --arg repo "$REPO" --argjson pr "$PR" \
    '{repo:$repo, available:true, pr:$pr, in_stack:false}'
  exit 10
fi

# `position` is 1-based (verified against github/gh-stack stack 350).
printf '%s' "$pr_node" | jq -c --arg repo "$REPO" '
  . as $p
  | ($p.stackEntry.position) as $pos
  | [ $p.stack.entries.nodes[] | {
        number: .pullRequest.number,
        position: .position,
        state: .pullRequest.state,
        merged: .pullRequest.merged,
        head_ref: .pullRequest.headRefName
      } ] as $entries
  | {
      repo: $repo,
      available: true,
      pr: $p.number,
      in_stack: true,
      stack_number: $p.stack.number,
      size: $p.stack.size,
      base_ref: $p.stack.baseRefName,
      position: $pos,
      entries: $entries,
      lower_open: [ $entries[] | select(.position < $pos and .state == "OPEN") | .number ],
      lower_closed_unmerged: [ $entries[]
        | select(.position < $pos and .state == "CLOSED" and .merged == false) | .number ],
      truncated: (($entries|length) < $p.stack.size)
    }'
exit 0
