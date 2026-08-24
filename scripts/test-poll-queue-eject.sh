#!/usr/bin/env bash
# test-poll-queue-eject.sh — pins poll-queue.sh's OPEN/isInMergeQueue:false
# disambiguation (issue #234).
#
# Why this exists: the race guard added in #60 anticipates the PR-STATE flip
# lagging the queue-entry removal, and disambiguates on the last
# RemovedFromMergeQueueEvent's reason. But the removal EVENT can lag too. On
# qr-ninja#847 a tick landed in the sub-second window where GraphQL answered
# `isInMergeQueue:false` with an EMPTY timeline for a PR that had merged
# cleanly that same second, and the fallback called it `ejected` — a terminal,
# loud verdict whose attached guidance points at eject recovery, i.e. at
# re-enqueueing something that has already landed.
#
# What makes it worth a gate rather than a memo is that it is wrong in BOTH
# directions at once: the human-facing line shouts EJECTED about a merge, and
# the final JSON says `"result":"ejected"` with no warning at all, so a
# coordinator branching on that JSON takes the recovery path silently. An empty
# timeline simply does not distinguish "never enqueued" from "the removal event
# has not materialised yet" — and the script already holds the disproof in
# QSTATES, which it was printing in the very line that got it wrong.
#
# Six properties are asserted:
#
#   1. The lag case is NOT terminal: seen in the queue on an earlier tick, then
#      isInMergeQueue:false with an empty timeline, re-reads instead of
#      emitting a verdict — and keeps re-reading until the GLOBAL
#      POLL_MAX_TICKS ceiling stops it with exit 124 (undetermined). That
#      "runs to the ceiling" assertion is also how "no per-PR counter was
#      added" is enforced behaviourally: any per-PR fall-through would resolve
#      `ejected` before the ceiling and fail here.
#   2. The lag RESOLVES: once the removal event materialises with reason
#      "merged", the same PR terminates as `merged`. A non-terminal branch that
#      could never converge would be a hang, not a fix.
#   3. A genuine eject stays terminal and immediate: a removal event whose
#      reason is not "merged" still resolves `ejected` on the tick it appears.
#   4. A PR that truly never enqueued stays terminal and immediate: empty
#      QSTATES plus an empty timeline is still `ejected` — the --auto
#      method-flag trap must not be swallowed by the new branch.
#   5. #60's own case is untouched: reason "merged" resolves `merged`.
#   6. Source-level: exactly ONE assignment of `ejected` exists (a second one
#      is what a per-PR bounding counter would look like), and the two prose
#      call sites that documented the old two-way split — the header contract
#      and the operator guidance under EJECTED — no longer state it. Those
#      must-not-exist checks run against a WHITESPACE-FLATTENED copy of the
#      script, because both call sites are hard-wrapped comment/echo blocks and
#      a line-scoped grep for stale wording turns a re-wrap into a false PASS.
#
# Network-free: a PATH-shimmed mock `gh` serving recorded GraphQL payloads, one
# per call, from a scenario directory. poll-queue.sh's only other gh use is the
# repo lookup, which REPO= suppresses — so a machine with a real authenticated
# gh behaves exactly like CI, and any unexpected invocation makes the mock exit
# non-zero, which surfaces as a WARN line the passing scenarios refute.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-poll-queue-eject.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-poll-queue-eject: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

POLL="$REPO_ROOT/skills/pr-shepherd/scripts/poll-queue.sh"
[ -f "$POLL" ] || { echo "test-poll-queue-eject: $POLL not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-poll-queue-eject: jq is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "poll-queue-eject tests (work: $WORK)" >&2

# --- the mock gh --------------------------------------------------------------
# poll-queue.sh makes exactly one kind of gh call per PR per tick: `gh api
# graphql … --jq .data.repository.pullRequest`, i.e. it expects the pullRequest
# object itself on stdout. The mock serves the Nth call from <scenario>/N.json,
# falling back to <scenario>/repeat.json once the recorded ticks run out.
cat >"$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    api)
        n=$(( $(cat "$MOCK_COUNTER") + 1 ))
        echo "$n" >"$MOCK_COUNTER"
        echo "graphql" >>"$MOCK_CALLS"
        f="$SCENARIO_DIR/$n.json"
        [ -f "$f" ] || f="$SCENARIO_DIR/repeat.json"
        [ -f "$f" ] || { echo "mock gh: no payload for call $n in $SCENARIO_DIR" >&2; exit 1; }
        cat "$f"
        ;;
    *) echo "mock gh: unhandled invocation: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$BIN/gh"

# --- recorded payloads --------------------------------------------------------
# The three shapes the OPEN/false guard has to tell apart, plus the in-queue
# tick that is what populates QSTATES in the first place.
IN_QUEUE='{"state":"OPEN","isInMergeQueue":true,"mergeQueueEntry":{"state":"AWAITING_CHECKS","position":1},"timelineItems":{"nodes":[]}}'
GONE_NO_EVENT='{"state":"OPEN","isInMergeQueue":false,"mergeQueueEntry":null,"timelineItems":{"nodes":[]}}'
GONE_MERGED='{"state":"OPEN","isInMergeQueue":false,"mergeQueueEntry":null,"timelineItems":{"nodes":[{"reason":"merged"}]}}'
GONE_DEQUEUED='{"state":"OPEN","isInMergeQueue":false,"mergeQueueEntry":null,"timelineItems":{"nodes":[{"reason":"dequeued"}]}}'

scenario() { # <name> <payload> [payload ...]  — the last one also becomes repeat.json
    local dir="$WORK/scenario-$1" n=0 p=""
    shift
    mkdir -p "$dir"
    for p in "$@"; do
        n=$((n + 1))
        printf '%s\n' "$p" >"$dir/$n.json"
    done
    printf '%s\n' "$p" >"$dir/repeat.json"
    echo "$dir"
}

# --- runner + assertions ------------------------------------------------------
STDOUT=""
STDERR=""
STATUS=0
CALLS=0
run_poll() { # <scenario_dir> <max_ticks>
    local dir="$1" max="$2"
    echo 0 >"$WORK/counter"
    : >"$WORK/calls"
    PATH="$BIN:$PATH" \
    SCENARIO_DIR="$dir" MOCK_COUNTER="$WORK/counter" MOCK_CALLS="$WORK/calls" \
    REPO=mock-org/mock-repo POLL_INTERVAL=0 POLL_MAX_TICKS="$max" \
        bash "$POLL" 847 >"$WORK/stdout" 2>"$WORK/stderr"
    STATUS=$?
    STDOUT="$(cat "$WORK/stdout")"
    STDERR="$(cat "$WORK/stderr")"
    CALLS="$(grep -c . "$WORK/calls")"
}

dump() {
    printf '%s\n' "$STDERR" | sed 's/^/          | E /' >&2
    printf '%s\n' "$STDOUT" | sed 's/^/          | O /' >&2
}

expect_err() { # <label> <needle>
    if grep -qF -- "$2" <<<"$STDERR"; then ok "$1"; else bad "$1 — expected on stderr: $2"; dump; fi
}
refute_err() { # <label> <needle>
    if grep -qF -- "$2" <<<"$STDERR"; then bad "$1 — must NOT appear on stderr: $2"; dump; else ok "$1"; fi
}
expect_out() { # <label> <needle>
    if grep -qF -- "$2" <<<"$STDOUT"; then ok "$1"; else bad "$1 — expected on stdout: $2"; dump; fi
}
refute_out() { # <label> <needle>
    if grep -qF -- "$2" <<<"$STDOUT"; then bad "$1 — must NOT appear on stdout: $2"; dump; else ok "$1"; fi
}
expect_status() { # <label> <expected>
    if [ "$STATUS" = "$2" ]; then ok "$1 (exit $STATUS)"; else bad "$1 — exit $STATUS, expected $2"; dump; fi
}

# --- 1. the lag case is non-terminal and runs to the global ceiling -----------
# Tick 1 sees the PR in the queue (this is what fills QSTATES); every tick after
# that is the failing shape from #234 — entry gone, timeline still empty.
echo "1. removal-event lag stays non-terminal (issue #234)" >&2
D="$(scenario lag "$IN_QUEUE" "$GONE_NO_EVENT")"
run_poll "$D" 4
expect_status "unresolved run ends at the POLL_MAX_TICKS ceiling, not with a verdict" 124
expect_err "the lag is reported as a re-read" "queue entry gone, removal event not yet visible"
expect_err "  and it names the queue-entry state that disproves 'never enqueued'" "AWAITING_CHECKS"
refute_err "no EJECTED verdict for a PR that was seen in the queue" "EJECTED"
refute_out "no final JSON verdict either" '"result":"ejected"'
# The ceiling is the ONLY thing that stopped it: a per-PR counter with a
# fall-through would have resolved `ejected` before tick 4 (issue #234 decision).
expect_err "it kept re-reading all the way to the ceiling" "--- tick 4 / 4"
if [ "$CALLS" = "4" ]; then
    ok "one GraphQL read per tick, four ticks (no extra calls)"
else
    bad "expected 4 GraphQL reads, got $CALLS"
    dump
fi
refute_err "no gh call fell outside the mock's contract" "WARN:"

# --- 2. the lag resolves rather than hanging ---------------------------------
echo "2. once the removal event lands, the same PR terminates" >&2
D="$(scenario lag-resolves "$IN_QUEUE" "$GONE_NO_EVENT" "$GONE_MERGED")"
run_poll "$D" 8
expect_status "run completes normally" 0
expect_err "the intermediate tick re-read" "queue entry gone, removal event not yet visible"
expect_err "the PR resolves merged once the event materialises" 'removal reason "merged"'
expect_err "  terminal on the tick the event appeared" "--- all PRs terminal at tick 3 ---"
expect_out "final JSON reports merged" '"result":"merged"'
refute_out "final JSON never says ejected" '"result":"ejected"'

# --- 3. a genuine eject is still terminal and immediate ----------------------
echo "3. a real eject (removal event, reason not 'merged') still fires" >&2
D="$(scenario real-eject "$IN_QUEUE" "$GONE_DEQUEUED")"
run_poll "$D" 8
expect_status "run completes normally" 0
expect_err "EJECTED is reported" "EJECTED"
expect_err "  the reason is carried through" "removal reason: dequeued"
expect_err "  terminal on the tick the event appeared" "--- all PRs terminal at tick 2 ---"
expect_out "final JSON reports ejected" '"result":"ejected"'
expect_out "  and carries the last queue-entry state" '"queueEntryState":"AWAITING_CHECKS"'
refute_err "the eject is not softened into a re-read" "removal event not yet visible"

# --- 4. never enqueued is still terminal and immediate -----------------------
# The --auto method-flag trap: the enqueue never took, so the PR is OPEN,
# isInMergeQueue:false, timeline empty AND QSTATES empty. The new branch must
# not swallow this one — it is the case the loud verdict exists for.
echo "4. a PR that never enqueued is still called immediately" >&2
D="$(scenario never-enqueued "$GONE_NO_EVENT")"
run_poll "$D" 8
expect_status "run completes normally" 0
expect_err "EJECTED is reported" "EJECTED"
expect_err "  and says the PR was never seen in the queue" "never seen in queue"
expect_err "  terminal on the very first tick" "--- all PRs terminal at tick 1 ---"
expect_out "final JSON reports ejected" '"result":"ejected"'
expect_out "  with a null queue-entry state" '"queueEntryState":null'
refute_err "not softened into a re-read" "removal event not yet visible"

# --- 5. #60's case is untouched ----------------------------------------------
echo "5. the #60 merged-but-state-not-flipped race still resolves merged" >&2
D="$(scenario merged-race "$IN_QUEUE" "$GONE_MERGED")"
run_poll "$D" 8
expect_status "run completes normally" 0
expect_err "MERGED is reported with the lagging-flip note" 'removal reason "merged"; PR-state flip lagging'
expect_out "final JSON reports merged" '"result":"merged"'
refute_err "no eject" "EJECTED"

# --- 6. source-level guards ---------------------------------------------------
echo "6. source-level shape and prose guards" >&2
ejected_sites="$(grep -c 'RESULTS\[\$i\]="ejected"' "$POLL")"
if [ "$ejected_sites" = "1" ]; then
    ok "'ejected' is assigned at exactly one site"
else
    bad "'ejected' is assigned at $ejected_sites sites in $POLL — a second one is what a per-PR bounding counter looks like, and its fall-through verdict re-creates issue #234 on a merely slow timeline"
fi

# Both prose call sites are hard-wrapped, so a line-scoped grep would read a
# re-wrap as a removal. Flatten first: the question is whether the wording is
# still in the file at all, not which line it sits on.
FLAT="$WORK/poll-queue.flat"
tr '\n' ' ' <"$POLL" | tr -s ' \t' ' ' >"$FLAT"
refute_flat() { # <label> <needle>
    if grep -qF -- "$2" "$FLAT"; then
        bad "$1 — still present in $POLL: $2"
    else
        ok "$1"
    fi
}
expect_flat() { # <label> <needle>
    if grep -qF -- "$2" "$FLAT"; then ok "$1"; else bad "$1 — missing from $POLL: $2"; fi
}
refute_flat "header contract no longer collapses 'no event' into ejected" \
    'any other reason, or no event -> result "ejected"'
expect_flat "header contract documents the non-terminal third branch" \
    'no event, but seen in queue -> NOT terminal'
refute_flat "operator guidance no longer enumerates only two cases" \
    'Either the queue ejected it (merge_group failed on the rebased ref)'
expect_flat "operator guidance names the re-read case it no longer covers" \
    'stays non-terminal and re-reads (#234)'
expect_flat "the eject guidance still warns against blind re-enqueue" \
    'Do NOT blindly'

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "poll-queue-eject tests: all green" >&2
    exit 0
else
    echo "poll-queue-eject tests: FAILURES above" >&2
    exit 1
fi
