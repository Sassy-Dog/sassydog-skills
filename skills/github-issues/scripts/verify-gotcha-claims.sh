#!/usr/bin/env bash
# verify-gotcha-claims.sh — resolve a groom-backlog config's `gotcha_summary`
# against real issue state BEFORE any of it is copied into an issue body.
#
# Why this exists (issue #249). `gotcha_summary` is free prose living in a
# frontmatter slot, which means it inherits neither protection the config format
# provides: it is not derived (nothing recomputes it after setup) and it is not
# in the `##` prose lane a human consciously curates. It is therefore the one
# field that can assert a TIME-VARYING fact and have nothing — generator,
# contract, or habit — ever revisit it. `Sassy-Dog/solador`'s config asserted
# "#15 is not finished — #308 (updater) and #334 (Windows + Authenticode)
# remain" for nine days after all three closed, and the consumer of that text is
# a cold worktree agent with zero conversation context and no way to check it.
#
# WHAT "FAIL-CLOSED" MEANS HERE. A claim citing `#N` survives only when its
# asserted state is explicit AND currently true. Everything else is dropped with
# a reason: the state is wrong, the issue cannot be resolved, or the claim cites
# an issue without asserting anything checkable. UNKNOWN IS HELD, NEVER PASSED
# THROUGH — that is the whole design, so there is deliberately NO skip exit. A
# missing `gh`, an unknown repo, or a network failure makes every citing claim
# unresolvable and therefore dropped; it never makes them pass. A verifier that
# degrades to "assume fine" is indistinguishable from no verifier at all on the
# exact day it matters.
#
# Claims with no `#N` at all are invariants — "business logic lives in
# `crates/`, never in the Tauri shell" — and are kept untouched. They are what
# the field is for; see setup-config/references/config-contract.md.
#
# The caller copies the text between the SAFE GOTCHAS markers into the issue
# body. It never copies the raw config field: dropping a claim from a report
# while the body still carries it protects nobody.
#
# `--lint` is the offline half, for finding configs that already carry
# time-varying claims so a refresh can NAME them rather than silently preserving
# them. No `gh`, no network: it reports shapes (issue refs, state verbs, "as of
# <date>", roadmap status), never truth.
#
# Usage:
#   verify-gotcha-claims.sh --config <path> [--repo owner/name]
#   verify-gotcha-claims.sh --text-file <path> [--repo owner/name]
#   verify-gotcha-claims.sh --config <path> --lint
#
# Env:  REPO=owner/name  (fallback when --repo is absent; else inferred with
#                         `gh repo view` from cwd)
#
# Exit: 0 nothing dropped (or, under --lint, nothing found)
#       3 at least one claim dropped (or, under --lint, at least one finding)
#       64 usage
# Read-only: never writes, never mutates, one `gh issue view` per distinct ref.
set -uo pipefail

CONFIG=""
TEXT_FILE=""
REPO_SLUG="${REPO:-}"
LINT=0

usage() {
    cat >&2 <<'USAGE'
usage: verify-gotcha-claims.sh (--config PATH | --text-file PATH) [--repo owner/name] [--lint]
  --config PATH     a .claude/sassy-dog/groom-backlog.md; gotcha_summary is read from its frontmatter
  --text-file PATH  raw gotcha text instead of a config file
  --repo owner/name the repo the cited #N belong to (else $REPO, else `gh repo view`)
  --lint            offline: report time-varying shapes, resolve nothing
exit: 0 clean · 3 claims dropped / findings · 64 usage
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)    CONFIG="${2:-}"; shift 2 || true ;;
        --text-file) TEXT_FILE="${2:-}"; shift 2 || true ;;
        --repo)      REPO_SLUG="${2:-}"; shift 2 || true ;;
        --lint)      LINT=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "verify-gotcha-claims: unknown argument '$1'" >&2; usage; exit 64 ;;
    esac
done

if [ -n "$CONFIG" ] && [ -n "$TEXT_FILE" ]; then
    echo "verify-gotcha-claims: --config and --text-file are mutually exclusive" >&2
    exit 64
fi
if [ -z "$CONFIG" ] && [ -z "$TEXT_FILE" ]; then
    usage
    exit 64
fi

SRC="${CONFIG:-$TEXT_FILE}"
if [ ! -f "$SRC" ]; then
    echo "verify-gotcha-claims: no such file: $SRC" >&2
    exit 64
fi

# --- extract the field -------------------------------------------------------
# Frontmatter only, and only `gotcha_summary:`. Handles the inline scalar and
# the folded/literal block form the template renders (`gotcha_summary: >`).
extract_summary() {
    awk '
        NR == 1 && $0 == "---" { inf = 1; next }
        inf == 1 && $0 == "---" { exit }
        inf != 1 { next }
        grab == 1 {
            if ($0 ~ /^[ \t]*$/) { print ""; next }
            if ($0 ~ /^[ \t]+/) { sub(/^[ \t]+/, ""); print; next }
            grab = 0
        }
        /^gotcha_summary:/ {
            val = $0
            sub(/^gotcha_summary:[ \t]*/, "", val)
            if (val ~ /^[>|]/) { grab = 1 } else if (val != "") { print val }
            next
        }
    ' "$1"
}

if [ -n "$CONFIG" ]; then
    RAW="$(extract_summary "$CONFIG")"
else
    RAW="$(cat "$TEXT_FILE")"
fi

# Fold to one paragraph, then split into claims on sentence boundaries. A claim
# is the unit that is kept or dropped: discarding the whole field over one
# rotted sentence would throw away the invariants that make it worth having.
SUMMARY="$(printf '%s\n' "$RAW" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CLAIMS="$WORK/claims"
CACHE="$WORK/cache"
: >"$CACHE"

printf '%s\n' "$SUMMARY" \
    | sed -E 's/([.;!?]) +/\1\n/g' \
    | sed -E 's/^ +//; s/ +$//' \
    | grep -v '^$' >"$CLAIMS" || true

if [ ! -s "$CLAIMS" ]; then
    echo "gotcha-claims: gotcha_summary is empty in $SRC — nothing to verify" >&2
    echo "--- BEGIN SAFE GOTCHAS ---"
    echo "--- END SAFE GOTCHAS ---"
    exit 0
fi

# --- time-varying shapes -----------------------------------------------------
# Shapes, never truth: what the contract says may not live in this field. Used
# by --lint on a whole config, and again below to ANNOTATE a claim that is kept
# — an "as of <date>" or a roadmap status cites no `#N`, so nothing can resolve
# it, and passing it through unremarked is how it survives the next ten refreshes.
time_varying_kinds() {
    local claim="$1" lower kinds=""
    lower="$(printf '%s' "$claim" | tr '[:upper:]' '[:lower:]')"
    case "$claim" in *'#'[0-9]*) kinds="$kinds issue-ref" ;; esac
    case "$lower" in
        *remain*|*"still open"*|*"not finished"*|*unfinished*|*outstanding*|*"not yet"*|*shipped*|*landed*|*"is closed"*|*"already done"*)
            kinds="$kinds state-verb" ;;
    esac
    case "$lower" in
        *"as of "*) kinds="$kinds dated" ;;
        *20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) kinds="$kinds dated" ;;
    esac
    case "$lower" in
        *roadmap*|*milestone*|*"next up"*|*"planned for"*|*"coming in"*|*"will ship"*)
            kinds="$kinds roadmap" ;;
    esac
    printf '%s\n' "$(printf '%s' "$kinds" | sed -E 's/^ //; s/ /,/g')"
}

# --- lint mode: shapes, offline ---------------------------------------------
if [ "$LINT" -eq 1 ]; then
    findings=0
    while IFS= read -r claim; do
        kinds="$(time_varying_kinds "$claim")"
        if [ -n "$kinds" ]; then
            findings=$((findings + 1))
            printf 'TIME-VARYING %s · "%s"\n' "$kinds" "$claim"
        fi
    done <"$CLAIMS"
    if [ "$findings" -eq 0 ]; then
        echo "gotcha-claims lint: $SRC — no time-varying claims"
        exit 0
    fi
    echo "gotcha-claims lint: $SRC — $findings time-varying claim(s); gotcha_summary carries invariants only (config-contract.md)"
    exit 3
fi

# --- resolve the repo --------------------------------------------------------
# An undetermined repo is not a skip: it makes every citing claim unresolvable,
# and unresolvable is dropped.
if [ -z "$REPO_SLUG" ] && command -v gh >/dev/null 2>&1; then
    REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

# --- resolve one issue, cached ----------------------------------------------
resolve_issue() {
    local n="$1" cached raw state
    cached="$(awk -F'\t' -v n="$n" '$1 == n { print $2; exit }' "$CACHE")"
    if [ -n "$cached" ]; then
        printf '%s\n' "$cached"
        return 0
    fi
    state="UNRESOLVED"
    if [ -n "$REPO_SLUG" ] && command -v gh >/dev/null 2>&1; then
        if raw="$(gh issue view "$n" --repo "$REPO_SLUG" --json state --jq .state 2>/dev/null)"; then
            raw="$(printf '%s' "$raw" | tr -d '[:space:]"' | tr '[:lower:]' '[:upper:]')"
            case "$raw" in
                OPEN|CLOSED) state="$raw" ;;
            esac
        fi
    fi
    printf '%s\t%s\n' "$n" "$state" >>"$CACHE"
    printf '%s\n' "$state"
}

# --- what state does the claim assert? --------------------------------------
# Both classes matching, or neither, is UNKNOWN — and unknown is held.
asserted_state() {
    local text open=0 closed=0
    text="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$text" in
        *remain*|*"still open"*|*"still needs"*|*"still not"*|*"not finished"*|*unfinished*|*outstanding*|*pending*|*"not yet"*|*"is open"*|*"are open"*|*"stays open"*|*"blocked on"*|*"waiting on"*|*"in flight"*|*"to do"*|*todo*)
            open=1 ;;
    esac
    case "$text" in
        *closed*|*shipped*|*landed*|*merged*|*"is fixed"*|*"was fixed"*|*resolved*|*"is done"*|*"already done"*|*"is complete"*|*"is finished"*)
            closed=1 ;;
    esac
    if [ "$open" -eq 1 ] && [ "$closed" -eq 1 ]; then
        printf 'unknown\n'
    elif [ "$open" -eq 1 ]; then
        printf 'open\n'
    elif [ "$closed" -eq 1 ]; then
        printf 'closed\n'
    else
        printf 'unknown\n'
    fi
}

kept=0
dropped=0
total=0
KEPT_FILE="$WORK/kept"
: >"$KEPT_FILE"
REPORT="$WORK/report"
: >"$REPORT"

while IFS= read -r claim; do
    total=$((total + 1))
    refs="$(printf '%s\n' "$claim" | grep -oE '#[0-9]+' | tr -d '#' | sort -un || true)"
    if [ -z "$refs" ]; then
        kept=$((kept + 1))
        printf '%s\n' "$claim" >>"$KEPT_FILE"
        kinds="$(time_varying_kinds "$claim")"
        if [ -n "$kinds" ]; then
            printf 'KEEP  time-varying  %s (%s — nothing here can resolve it; the contract says invariants only)\n' "$claim" "$kinds" >>"$REPORT"
        else
            printf 'KEEP  invariant     %s\n' "$claim" >>"$REPORT"
        fi
        continue
    fi

    assert="$(asserted_state "$claim")"
    verdict="keep"
    reason=""
    for n in $refs; do
        state="$(resolve_issue "$n")"
        if [ "$state" = "UNRESOLVED" ]; then
            verdict="drop"
            if [ -n "$REPO_SLUG" ]; then
                reason="unresolvable   #${n} could not be resolved"
            else
                reason="unresolvable   #${n} could not be resolved (no repo determined)"
            fi
            break
        fi
        if [ "$assert" = "unknown" ]; then
            verdict="drop"
            reason="unverifiable   #${n} is cited with no checkable state assertion"
            break
        fi
        expected="OPEN"
        [ "$assert" = "closed" ] && expected="CLOSED"
        if [ "$state" != "$expected" ]; then
            verdict="drop"
            reason="contradicted   #${n} is ${state}, the claim asserts ${assert}"
            break
        fi
    done

    if [ "$verdict" = "drop" ]; then
        dropped=$((dropped + 1))
        printf 'DROP  %s · "%s"\n' "$reason" "$claim" >>"$REPORT"
    else
        kept=$((kept + 1))
        printf '%s\n' "$claim" >>"$KEPT_FILE"
        printf 'KEEP  confirmed     %s (state true right now; an issue-state claim rots — prefer an invariant)\n' "$claim" >>"$REPORT"
    fi
done <"$CLAIMS"

printf 'gotcha-claims: repo=%s claims=%d kept=%d dropped=%d\n' "${REPO_SLUG:-unknown}" "$total" "$kept" "$dropped"
cat "$REPORT"
echo "--- BEGIN SAFE GOTCHAS ---"
if [ -s "$KEPT_FILE" ]; then
    tr '\n' ' ' <"$KEPT_FILE" | sed -E 's/ +$//'
    echo
fi
echo "--- END SAFE GOTCHAS ---"

if [ "$dropped" -gt 0 ]; then
    exit 3
fi
exit 0
