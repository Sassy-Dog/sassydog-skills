#!/usr/bin/env bash
# Retry a `gh` command with exponential backoff on transient GitHub failures.
#
# Catches:
#   - HTTP 502/503/504 (Bad Gateway / Service Unavailable / Gateway Timeout)
#   - "Merge already in progress" (GitHub locks the PR after a 502'd merge call;
#     the lock typically clears within 30-60s but the underlying merge often
#     gets DROPPED — we have to retry to actually finish it)
#   - "Something went wrong while executing your query" (transient GraphQL)
#
# Does NOT retry on:
#   - 401/403/404 (auth/permission/not-found — retrying won't fix)
#   - Validation errors (bad input — retrying won't fix)
#   - Pre-existing successful state (e.g., PR already MERGED — caller should check first)
#
# Usage: gh-retry.sh [--max-attempts N] [--initial-delay S] -- <gh args...>
#
# Exit codes:
#   0 — success
#   1 — non-retriable failure (last gh output is on stderr)
#   124 — exhausted all attempts (last gh output is on stderr)

set -uo pipefail

MAX_ATTEMPTS=5
INITIAL_DELAY=5

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-attempts) MAX_ATTEMPTS="$2"; shift 2 ;;
        --initial-delay) INITIAL_DELAY="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "usage: gh-retry.sh [--max-attempts N] [--initial-delay S] -- <gh args>" >&2
    exit 64
fi

is_transient() {
    local out="$1"
    case "$out" in
        *"502 Bad Gateway"*|*"503 Service Unavailable"*|*"504 Gateway Timeout"*) return 0 ;;
        *"Merge already in progress"*) return 0 ;;
        *"Something went wrong while executing your query"*) return 0 ;;
        *"connection reset by peer"*|*"connection refused"*) return 0 ;;
        *) return 1 ;;
    esac
}

delay="$INITIAL_DELAY"
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    out=$(gh "$@" 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]]; then
        printf '%s' "$out"
        exit 0
    fi
    if ! is_transient "$out"; then
        echo "$out" >&2
        exit "$rc"
    fi
    echo "[gh-retry] attempt $attempt/$MAX_ATTEMPTS hit transient failure; retrying in ${delay}s" >&2
    echo "[gh-retry] gh stderr: $(echo "$out" | head -1)" >&2
    if [[ $attempt -lt $MAX_ATTEMPTS ]]; then
        sleep "$delay"
        delay=$(( delay * 2 ))
    fi
done

echo "$out" >&2
exit 124
