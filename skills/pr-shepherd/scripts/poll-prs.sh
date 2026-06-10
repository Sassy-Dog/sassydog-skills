#!/usr/bin/env bash
# Poll one or more PRs every 60s; exit when all are terminal.
# Terminal = MERGED | CLOSED | (state=OPEN AND statusCheckRollup has no PENDING/IN_PROGRESS)
#
# Does NOT merge anything — coordinator inspects exit state and decides.
# Prints a one-line status table per tick to stderr; emits final JSON to stdout.
#
# Usage: poll-prs.sh <PR1> [PR2 ...]
# Env:   REPO=owner/name        target repo (default: inferred from cwd)
#        POLL_INTERVAL=60       seconds between ticks
#        POLL_MAX_TICKS=60      ceiling (60 * 60s = 1 hour)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <PR-number> [PR-number ...]" >&2
    exit 64
fi

PRS=("$@")
INTERVAL="${POLL_INTERVAL:-60}"
MAX_TICKS="${POLL_MAX_TICKS:-60}"  # 60 ticks * 60s = 1 hour ceiling

repo_flag=""
if [[ -n "${REPO:-}" ]]; then
    repo_flag="--repo $REPO"
elif ! gh repo view --json name --jq .name >/dev/null 2>&1; then
    echo "error: not in a GitHub repo and REPO env not set" >&2
    exit 64
fi

is_terminal() {
    local pr="$1"
    local view
    view=$(gh pr view "$pr" $repo_flag \
        --json state,mergeable,mergeStateStatus,statusCheckRollup 2>/dev/null) || return 1

    local state
    state=$(jq -r '.state' <<<"$view")
    case "$state" in
        MERGED|CLOSED) return 0 ;;
    esac

    # OPEN — terminal only if no checks are PENDING / IN_PROGRESS / QUEUED
    local in_flight
    in_flight=$(jq '[.statusCheckRollup[]?
        | select(.status=="IN_PROGRESS" or .status=="QUEUED" or .conclusion==null)] | length' <<<"$view")
    [[ "$in_flight" == "0" ]]
}

snapshot_line() {
    local pr="$1"
    local view
    view=$(gh pr view "$pr" $repo_flag \
        --json state,mergeable,mergeStateStatus,statusCheckRollup,title 2>/dev/null) \
        || { printf "PR #%-5s  ERROR (gh pr view failed)\n" "$pr"; return; }

    local state mergeable mergeStateStatus title
    state=$(jq -r '.state' <<<"$view")
    mergeable=$(jq -r '.mergeable' <<<"$view")
    mergeStateStatus=$(jq -r '.mergeStateStatus' <<<"$view")
    title=$(jq -r '.title' <<<"$view" | cut -c1-50)

    local total green failed pending
    total=$(jq '.statusCheckRollup | length' <<<"$view")
    green=$(jq '[.statusCheckRollup[]? | select(.conclusion=="SUCCESS")] | length' <<<"$view")
    failed=$(jq '[.statusCheckRollup[]? | select(.conclusion=="FAILURE" or .conclusion=="CANCELLED" or .conclusion=="TIMED_OUT")] | length' <<<"$view")
    pending=$(jq '[.statusCheckRollup[]? | select(.status=="IN_PROGRESS" or .status=="QUEUED" or .conclusion==null)] | length' <<<"$view")

    printf "PR #%-5s  %-8s  %-10s  checks: %d✅ %d❌ %d⏳ /%d  (%s)  %s\n" \
        "$pr" "$state" "$mergeStateStatus" "$green" "$failed" "$pending" "$total" "$mergeable" "$title"
}

tick=0
while true; do
    tick=$((tick + 1))
    echo "--- tick $tick / $MAX_TICKS  ($(date +%H:%M:%S)) ---" >&2
    all_done=1
    for pr in "${PRS[@]}"; do
        snapshot_line "$pr" >&2
        if ! is_terminal "$pr"; then
            all_done=0
        fi
    done

    if [[ "$all_done" == "1" ]]; then
        echo "--- all PRs terminal at tick $tick ---" >&2
        break
    fi

    if [[ "$tick" -ge "$MAX_TICKS" ]]; then
        echo "--- max ticks reached, exiting non-zero ---" >&2
        exit 124  # match GNU timeout's "timed out" convention
    fi

    sleep "$INTERVAL"
done

# Final JSON for the coordinator to parse + decide who to merge.
out='{"prs":['
first=1
for pr in "${PRS[@]}"; do
    view=$(gh pr view "$pr" $repo_flag \
        --json number,state,mergeable,mergeStateStatus,statusCheckRollup,title,headRefName 2>/dev/null \
        || echo '{}')
    [[ "$first" == "1" ]] || out+=','
    out+="$view"
    first=0
done
out+=']}'
echo "$out"
