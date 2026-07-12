#!/usr/bin/env bash
# issue-claim.sh — the fill/drain label-state write path: claim, release, block,
# promote, demote. The SECOND write-capable script in this skill (the first is
# file-or-link-issue.sh, which owns issue creation; this one owns label-state
# transitions). It is the single home of the ready/in-progress/blocked label
# taxonomy — never hand-roll `gh label create` or claim-label edits in a
# fill/drain flow, or the taxonomy drifts.
#
# Subcommands:
#   claim    N...  ensure `in-progress` exists; assignee @me + add in-progress,
#                  strip ready. SKIPS an issue already assigned to someone else
#                  (the double-pick guard) unless --force.
#   release  N...  remove in-progress (post-merge claim clearing — Closes #N
#                  closes the issue but never strips labels).
#   block    N...  ensure `blocked` exists; strip ready + in-progress, add
#                  blocked, post the --comment (REQUIRED — a demotion to blocked
#                  without a reason is a silent failure for the next human).
#   promote  N...  ensure `ready` exists; add ready (fill-it promotion).
#   demote   N...  remove ready, post the --comment (REQUIRED — never a silent
#                  strip; Ready is a promise and breaking it needs a why).
#
# Usage:
#   issue-claim.sh <claim|release|block|promote|demote> <N> [N ...] \
#     [--repo owner/name] [--comment "text"] [--force] [--dry-run]
#
# Env: DRY_RUN=1 equivalent to --dry-run. REPO honored if --repo absent.
#
# Output: one JSON line per issue on stdout:
#   {"issue":N,"op":"claim","result":"ok|skipped|would-claim|failed","detail":"..."}
# Human-readable notes go to stderr.
#
# Exit codes:
#   0  — every issue ok / skipped / dry-run
#   1  — missing tooling (gh/jq) or no repo
#   2  — at least one hard failure (the batch CONTINUES past failures — claim
#        failures are logged, never fatal, per the take-it/drain-it contract)
#   64 — usage error
#
# Label ops are idempotent by nature (add existing / remove absent = no-op), so
# re-running any subcommand is safe. Mutations route through pr-shepherd's
# gh-retry.sh when present (exponential backoff on transient GitHub failures);
# resolved relative to this script so the same path works in the plugin tree
# AND a vendored .claude/skills/ tree (pr-shepherd is the mandatory bundle root).

set -uo pipefail

# --- label taxonomy (canonical definition; SKILL.md documents this table) ---
READY_LABEL="ready"
READY_COLOR="0E8A16"
READY_DESC="Dispatchable: a cold worktree agent could ship this (fill-it promoted)"
INPROG_LABEL="in-progress"
INPROG_COLOR="1D76DB"
INPROG_DESC="Claimed by a take-it/drain-it loop"
BLOCKED_LABEL="blocked"
BLOCKED_COLOR="B60205"
BLOCKED_DESC="Needs a human decision before it can be dispatched (drain-it demoted)"

usage() {
    cat >&2 <<'EOF'
usage: issue-claim.sh <claim|release|block|promote|demote> <N> [N ...]
         [--repo owner/name] [--comment "text"] [--force] [--dry-run]
       block and demote REQUIRE --comment.
EOF
    exit 64
}

SUB="${1:-}"
case "$SUB" in
    claim|release|block|promote|demote) shift ;;
    *) usage ;;
esac

REPO="${REPO:-}"
COMMENT=""
FORCE=0
dry_run="${DRY_RUN:-0}"
ISSUES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)    REPO="$2";    shift 2 ;;
        --comment) COMMENT="$2"; shift 2 ;;
        --force)   FORCE=1;      shift ;;
        --dry-run) dry_run=1;    shift ;;
        -*) echo "issue-claim: unknown arg: $1" >&2; usage ;;
        *)  ISSUES+=("$1");      shift ;;
    esac
done

[[ ${#ISSUES[@]} -eq 0 ]] && usage
for n in ${ISSUES[@]+"${ISSUES[@]}"}; do
    case "$n" in
        ''|*[!0-9]*) echo "issue-claim: not an issue number: $n" >&2; exit 64 ;;
    esac
done

if [[ ("$SUB" == "block" || "$SUB" == "demote") && -z "$COMMENT" ]]; then
    echo "issue-claim: '$SUB' requires --comment (never a silent strip)" >&2
    exit 64
fi

command -v gh >/dev/null || { echo "issue-claim: gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "issue-claim: jq not on PATH" >&2; exit 1; }
[[ -z "$REPO" ]] && REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[[ -z "$REPO" ]] && { echo "issue-claim: not in a GitHub repo and --repo not given" >&2; exit 1; }

# Mutations go through pr-shepherd's gh-retry.sh when available. The relative
# path resolves in both layouts because pr-shepherd is the mandatory vendor-
# bundle root: <root>/{github-issues,pr-shepherd}/scripts/ side by side.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_RETRY="$SCRIPT_DIR/../../pr-shepherd/scripts/gh-retry.sh"
if [[ -f "$GH_RETRY" ]]; then
    ghw() { bash "$GH_RETRY" -- "$@"; }
else
    echo "issue-claim: gh-retry.sh not found at $GH_RETRY — mutations run without retry" >&2
    ghw() { gh "$@"; }
fi

ensure_label() {  # $1=name $2=color $3=description — idempotent, failure benign
    gh label create "$1" --repo "$REPO" --color "$2" --description "$3" \
        >/dev/null 2>&1 || true
}

emit() {  # $1=issue $2=result $3=detail
    jq -cn --arg i "$1" --arg op "$SUB" --arg r "$2" --arg d "$3" \
        '{issue:($i|tonumber), op:$op, result:$r, detail:$d}'
}

# Who am I (for the claim double-pick guard). Degrades to no guard if unknown.
ME=""
if [[ "$SUB" == "claim" ]]; then
    ME=$(gh api user --jq .login 2>/dev/null || true)
fi

hard_failed=0

for n in ${ISSUES[@]+"${ISSUES[@]}"}; do
    # claim: skip issues already assigned to someone else (double-pick guard).
    if [[ "$SUB" == "claim" && "$FORCE" == "0" ]]; then
        assignees=$(gh issue view "$n" --repo "$REPO" --json assignees \
            --jq '[.assignees[].login] | join(",")' 2>/dev/null || echo "")
        if [[ -n "$assignees" && -n "$ME" && ",$assignees," != *",$ME,"* ]]; then
            emit "$n" "skipped" "assigned to $assignees (use --force to override)"
            continue
        fi
    fi

    if [[ "$dry_run" == "1" ]]; then
        emit "$n" "would-$SUB" "dry-run: no writes"
        continue
    fi

    # Failure detection keys off the EXIT CODE, not stderr content — gh-retry.sh
    # writes "[gh-retry] attempt ..." progress to stderr even on eventual success.
    rc=0
    err=""
    case "$SUB" in
        claim)
            ensure_label "$INPROG_LABEL" "$INPROG_COLOR" "$INPROG_DESC"
            err=$(ghw issue edit "$n" --repo "$REPO" --add-assignee @me \
                --add-label "$INPROG_LABEL" --remove-label "$READY_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        release)
            err=$(ghw issue edit "$n" --repo "$REPO" \
                --remove-label "$INPROG_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        block)
            ensure_label "$BLOCKED_LABEL" "$BLOCKED_COLOR" "$BLOCKED_DESC"
            err=$(ghw issue edit "$n" --repo "$REPO" --remove-label "$READY_LABEL" \
                --remove-label "$INPROG_LABEL" --add-label "$BLOCKED_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        promote)
            ensure_label "$READY_LABEL" "$READY_COLOR" "$READY_DESC"
            err=$(ghw issue edit "$n" --repo "$REPO" \
                --add-label "$READY_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        demote)
            err=$(ghw issue edit "$n" --repo "$REPO" \
                --remove-label "$READY_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
    esac

    # `--remove-label` of a label that doesn't exist in the REPO at all is gh's
    # one non-idempotent edge: it errors instead of no-opping (removing a label
    # the issue merely doesn't carry is already a silent no-op). Nothing to
    # remove = the desired end state — treat "not found" errors as ok.
    if [[ "$rc" -ne 0 && "$err" != *"not found"* && "$err" != *"could not be found"* ]]; then
        emit "$n" "failed" "$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
        hard_failed=1
        continue
    fi

    if [[ -n "$COMMENT" ]]; then
        crc=0
        cerr=$(ghw issue comment "$n" --repo "$REPO" --body "$COMMENT" 2>&1 >/dev/null) || crc=$?
        if [[ "$crc" -ne 0 ]]; then
            echo "issue-claim: #$n label edit ok but comment failed: $(echo "$cerr" | grep -v '^\[gh-retry\]' | head -1)" >&2
        fi
    fi

    emit "$n" "ok" ""
done

[[ "$hard_failed" == "1" ]] && exit 2
exit 0
