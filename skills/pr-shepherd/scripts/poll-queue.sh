#!/usr/bin/env bash
# Poll merge-queue state for one or more enqueued PRs; exit when all are terminal.
# Queue-phase companion to poll-prs.sh: poll-prs.sh waits for *checks* to finish;
# this waits for the *queue* to finish after `gh pr merge --auto` has enqueued.
#
# Terminal per PR:
#   MERGED                        -> result "merged"   (queue succeeded)
#   OPEN  + isInMergeQueue:false  -> result "ejected"  (queue ejected it — or it never enqueued)
#   CLOSED (not merged)           -> result "closed"   (closed without merge)
#
# Does NOT merge, re-enqueue, or recover — coordinator inspects exit state and decides.
# Prints a one-line status per PR per tick to stderr; emits final JSON to stdout:
#   {"prs":[{"pr":N,"result":"merged|ejected|closed","queueEntryState":"..."}]}
# A failed `gh api graphql` call logs and retries next tick — it never kills the watch.
#
# Usage: poll-queue.sh <PR1> [PR2 ...]
# Env:   REPO=owner/name        target repo (default: inferred from cwd)
#        POLL_INTERVAL=60       seconds between ticks (queue cycles are slow)
#        POLL_MAX_TICKS=60      ceiling (60 * 60s = 1 hour); exit 124 when hit

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <PR-number> [PR-number ...]" >&2
    exit 64
fi

PRS=("$@")
for pr in "${PRS[@]}"; do
    if [[ ! "$pr" =~ ^[0-9]+$ ]]; then
        echo "error: '$pr' is not a PR number" >&2
        exit 64
    fi
done

INTERVAL="${POLL_INTERVAL:-60}"
MAX_TICKS="${POLL_MAX_TICKS:-60}"  # 60 ticks * 60s = 1 hour ceiling

if [[ -n "${REPO:-}" ]]; then
    if [[ "$REPO" != */* ]]; then
        echo "error: REPO must be owner/name" >&2
        exit 64
    fi
    OWNER="${REPO%%/*}"
    NAME="${REPO##*/}"
else
    if ! repo_json=$(gh repo view --json owner,name 2>/dev/null); then
        echo "error: not in a GitHub repo and REPO env not set" >&2
        exit 64
    fi
    OWNER=$(jq -r '.owner.login' <<<"$repo_json")
    NAME=$(jq -r '.name' <<<"$repo_json")
fi

# isInMergeQueue / mergeQueueEntry are GraphQL-only — `gh pr view --json
# isInMergeQueue` fails with `Unknown JSON field`. This is the query from
# references/merge-queue.md "Confirm the enqueue took".
query_pr() {
    local pr="$1"
    gh api graphql \
        -f query='query($owner:String!,$name:String!,$pr:Int!){
            repository(owner:$owner,name:$name){
                pullRequest(number:$pr){ state isInMergeQueue mergeQueueEntry{ state position } }}}' \
        -f owner="$OWNER" -f name="$NAME" -F pr="$pr" \
        --jq '.data.repository.pullRequest' 2>/dev/null
}

# Parallel arrays aligned with PRS (no associative arrays — macOS bash 3.2).
RESULTS=()  # "" until terminal, then merged|ejected|closed
QSTATES=()  # last seen mergeQueueEntry.state, "" if never seen in queue
for i in "${!PRS[@]}"; do
    RESULTS[i]=""
    QSTATES[i]=""
done

tick=0
while true; do
    tick=$((tick + 1))
    echo "--- tick $tick / $MAX_TICKS  ($(date +%H:%M:%S)) ---" >&2
    all_done=1
    for i in "${!PRS[@]}"; do
        pr="${PRS[$i]}"
        if [[ -n "${RESULTS[$i]}" ]]; then
            printf 'PR #%-5s  terminal: %s\n' "$pr" "${RESULTS[$i]}" >&2
            continue
        fi

        if ! view=$(query_pr "$pr") || [[ -z "$view" || "$view" == "null" ]]; then
            echo "PR #$pr   WARN: gh api graphql failed (transient — retrying next tick)" >&2
            all_done=0
            continue
        fi

        state=$(jq -r '.state' <<<"$view")
        in_queue=$(jq -r '.isInMergeQueue' <<<"$view")
        q_state=$(jq -r '.mergeQueueEntry.state // empty' <<<"$view")
        q_pos=$(jq -r '.mergeQueueEntry.position // empty' <<<"$view")
        [[ -n "$q_state" ]] && QSTATES[$i]="$q_state"

        case "$state/$in_queue" in
            MERGED/*)
                RESULTS[$i]="merged"
                printf 'PR #%-5s  MERGED ✅\n' "$pr" >&2
                ;;
            CLOSED/*)
                RESULTS[$i]="closed"
                printf 'PR #%-5s  CLOSED without merge ❌\n' "$pr" >&2
                ;;
            OPEN/true)
                all_done=0
                printf 'PR #%-5s  OPEN  in queue  entry: %s  position: %s\n' \
                    "$pr" "${q_state:-?}" "${q_pos:-?}" >&2
                ;;
            OPEN/false)
                RESULTS[$i]="ejected"
                {
                    printf 'PR #%-5s  EJECTED 🚨  OPEN with isInMergeQueue:false (last queue-entry state: %s)\n' \
                        "$pr" "${QSTATES[$i]:-never seen in queue}"
                    echo "           Either the queue ejected it (merge_group failed on the rebased ref)"
                    echo "           or it never enqueued (the --auto method-flag trap). Do NOT blindly"
                    echo "           re-enqueue — see 'Eject recovery' in references/merge-queue.md."
                } >&2
                ;;
            *)
                echo "PR #$pr   WARN: unexpected response ($state / inQueue=$in_queue) — retrying next tick" >&2
                all_done=0
                ;;
        esac
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

# Final JSON for the coordinator to parse + decide (merged vs eject recovery).
out='{"prs":['
first=1
for i in "${!PRS[@]}"; do
    [[ "$first" == "1" ]] || out+=','
    out+=$(jq -cn --argjson pr "${PRS[$i]}" --arg result "${RESULTS[$i]}" --arg qs "${QSTATES[$i]}" \
        '{pr:$pr, result:$result, queueEntryState:(if $qs=="" then null else $qs end)}')
    first=0
done
out+=']}'
echo "$out"
