#!/usr/bin/env bash
# pr-failure-log.sh — name a red PR's failing checks and print their failed-run
# log tails, one labeled section per failure.
#
# Replaces the fragile inline two-step (grep a run id out of a check's link URL,
# then `gh run view --log-failed | tail`) that broke on non-Actions checks:
# legacy StatusContext checks (Vercel, Netlify, classic CI) have links that
# are NOT Actions runs — there is no log to fetch; the link itself is the
# diagnostic. Those are printed as "external check" lines instead of erroring.
#
# Usage: pr-failure-log.sh <PR> [--repo owner/name] [--lines 50]
# Env:   REPO=owner/name (fallback when --repo absent; else inferred from cwd)
#
# Exit codes:
#   0  — every failing check reported (log tail printed, or external link named)
#   1  — at least one Actions log fetch failed (rest still printed)
#   10 — no failing checks on the PR
#   64 — usage
#
# Read-only.
set -euo pipefail

PR=""
REPO="${REPO:-}"
LINES=50

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  REPO="$2";  shift 2 ;;
        --lines) LINES="$2"; shift 2 ;;
        -*) echo "usage: pr-failure-log.sh <PR> [--repo owner/name] [--lines N]" >&2; exit 64 ;;
        *)  PR="$1"; shift ;;
    esac
done

case "$PR" in ''|*[!0-9]*) echo "usage: pr-failure-log.sh <PR> [--repo owner/name] [--lines N]" >&2; exit 64 ;; esac
case "$LINES" in ''|*[!0-9]*) echo "pr-failure-log: --lines must be a number" >&2; exit 64 ;; esac

repo_flag=""
if [[ -n "$REPO" ]]; then
    repo_flag="--repo $REPO"
elif ! gh repo view --json name --jq .name >/dev/null 2>&1; then
    echo "error: not in a GitHub repo and REPO/--repo not set" >&2
    exit 64
fi

# shellcheck disable=SC2086  # repo_flag is deliberately word-split (empty or two words)
checks=$(gh pr checks "$PR" $repo_flag --json name,state,link 2>/dev/null) \
    || { echo "pr-failure-log: could not read checks for PR #$PR" >&2; exit 1; }

failing=$(jq -c '[.[] | select(.state=="FAILURE" or .state=="ERROR" or .state=="CANCELLED" or .state=="TIMED_OUT")]' <<<"$checks")
count=$(jq 'length' <<<"$failing")
if [[ "$count" == "0" ]]; then
    echo "no failing checks on PR #$PR" >&2
    exit 10
fi

fetch_failed=0
while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    name=$(jq -r '.name' <<<"$item")
    state=$(jq -r '.state' <<<"$item")
    link=$(jq -r '.link // ""' <<<"$item")

    # Actions links look like .../actions/runs/<run-id>[/job/<job-id>].
    run_id=$(grep -oE '/actions/runs/[0-9]+' <<<"$link" | grep -oE '[0-9]+' | head -1 || true)

    if [[ -z "$run_id" ]]; then
        echo "== $name ($state) — external check, no Actions log; open: ${link:-<no link>} =="
        continue
    fi

    echo "== $name ($state, run $run_id) =="
    # shellcheck disable=SC2086
    if ! gh run view "$run_id" $repo_flag --log-failed 2>/dev/null | tail -n "$LINES"; then
        echo "  ⚠ could not fetch --log-failed for run $run_id (still running / expired?); open: $link"
        fetch_failed=1
    fi
done < <(jq -c '.[]' <<<"$failing")

exit "$fetch_failed"
