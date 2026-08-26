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
#                  closes the issue but never strips labels). DELIBERATELY
#                  asymmetric with claim: it does not clear the assignee,
#                  because on a closed issue that assignee records who shipped
#                  it. The residue that leaves behind is cleared at promote,
#                  which is the only place it can do harm (issue #281).
#   block    N...  ensure `blocked` exists; strip ready + in-progress, add
#                  blocked, post the --comment (REQUIRED — a demotion to blocked
#                  without a reason is a silent failure for the next human).
#   promote  N...  ensure `ready` exists; add ready (groom-backlog promotion),
#                  and clear a RESIDUAL claim assignee — only the one shape that
#                  is residue by construction (assigned to exactly @me, with no
#                  in-progress label). Every other shape is REPORTED and left
#                  alone. See promote_residue_gate() below (issue #281).
#   demote   N...  remove ready, post the --comment (REQUIRED — never a silent
#                  strip; Ready is a promise and breaking it needs a why).
#   sync-labels    reconcile ALL FOUR dev-workflow labels in one pass without
#                  touching an issue — the propagation entry point for a repo
#                  that was onboarded before a colour changed.
#   taxonomy       print the table as `name|color|description` lines and exit.
#                  Needs no gh, no jq and no repo: it is how OTHER tools read
#                  this taxonomy (scripts/align-labels.sh's cross-set collision
#                  check) without forking a second copy of the values.
#
# Usage:
#   issue-claim.sh <claim|release|block|promote|demote> <N> [N ...] \
#     [--repo owner/name] [--comment "text"] [--force] [--dry-run]
#   issue-claim.sh sync-labels [--repo owner/name] [--dry-run]
#   issue-claim.sh taxonomy
#
# Env: DRY_RUN=1 equivalent to --dry-run. REPO honored if --repo absent.
#
# Output: one JSON line per issue on stdout:
#   {"issue":N,"op":"claim","result":"ok|skipped|would-claim|failed","detail":"..."}
# sync-labels emits one JSON line per label instead:
#   {"label":"ready","action":"ok|create|update|would-create|would-update|failed","detail":"..."}
# Human-readable notes go to stderr.
#
# Exit codes:
#   0  — every issue ok / skipped / dry-run
#   1  — missing tooling (gh/jq) or no repo
#   2  — at least one hard failure (the batch CONTINUES past failures — claim
#        failures are logged, never fatal, per the take-it/dispatch-ready contract)
#   64 — usage error
#
# Label ops are idempotent by nature (add existing / remove absent = no-op), so
# re-running any subcommand is safe. Mutations route through pr-shepherd's
# gh-retry.sh when present (exponential backoff on transient GitHub failures);
# resolved relative to this script, so the path holds wherever the plugin is
# installed (pr-shepherd is the script root: repo-cleanup ships none and calls
# its teardown.sh; this script calls its gh-retry.sh).
#
# COLOURS ARE MEASURED, NOT CHOSEN BY EYE (issue #161). All four sat at ΔE2000
# = 0 against a canonical label from the OTHER taxonomy
# (scripts/align-labels.sh) — ready/sev:low, in-progress/architecture,
# blocked/sev:critical and sentry-escalation/sev:critical each shared a hex
# exactly, and every dispatchable issue carries one label from each set, so the
# chips were routinely indistinguishable. The decision was that the
# dev-workflow side moves: severity keeps its conventional coding (red =
# critical) and #158's freshly measured canonical palette stays put. The
# replacements are the lexicographic-maximin point of a 1,440-colour HSL sweep
# scored with CIEDE2000 against the union of both taxonomies, GitHub's default
# labels and every one-off label live across the org — min ΔE2000 = 20.8
# overall, 24.4 across the two taxonomies (was 0.0). Re-"tidying" any of them
# back toward a palette default reintroduces the collision;
# `align-labels.sh --collisions` is the gate that catches it.

set -uo pipefail

# --- label taxonomy (canonical definition; SKILL.md documents this table) ---
READY_LABEL="ready"
READY_COLOR="38fa99"
READY_DESC="Dispatchable: a cold worktree agent could ship this (groom-backlog promoted)"
INPROG_LABEL="in-progress"
INPROG_COLOR="190132"
INPROG_DESC="Claimed by a take-it/dispatch-ready loop"
BLOCKED_LABEL="blocked"
BLOCKED_COLOR="52363d"
BLOCKED_DESC="Needs a human decision before it can be dispatched (dispatch-ready demoted)"
# Written by file-or-link-issue.sh's --ensure-label (its caller passes the
# spec), never by this script — but its VALUE lives here with the rest of the
# dev-workflow taxonomy, because a value with two homes is the drift both
# scripts exist to prevent. github-issues/SKILL.md quotes this row.
SENTRY_LABEL="sentry-escalation"
SENTRY_COLOR="9c846b"
SENTRY_DESC="Auto-filed from a Sentry hit"

# The table, built FROM the constants above — no second transcription.
DEVWORKFLOW_LABELS=(
    "$READY_LABEL|$READY_COLOR|$READY_DESC"
    "$INPROG_LABEL|$INPROG_COLOR|$INPROG_DESC"
    "$BLOCKED_LABEL|$BLOCKED_COLOR|$BLOCKED_DESC"
    "$SENTRY_LABEL|$SENTRY_COLOR|$SENTRY_DESC"
)

print_taxonomy() { printf '%s\n' "${DEVWORKFLOW_LABELS[@]}"; }

usage() {
    cat >&2 <<'EOF'
usage: issue-claim.sh <claim|release|block|promote|demote> <N> [N ...]
         [--repo owner/name] [--comment "text"] [--force] [--dry-run]
       issue-claim.sh sync-labels [--repo owner/name] [--dry-run]
       issue-claim.sh taxonomy
       block and demote REQUIRE --comment.
EOF
    exit 64
}

SUB="${1:-}"
case "$SUB" in
    claim|release|block|promote|demote|sync-labels) shift ;;
    # Data only: no tooling, no repo, no network. Keep it ahead of every check
    # below so a consumer can read the taxonomy from a bare checkout.
    taxonomy) print_taxonomy; exit 0 ;;
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

if [[ "$SUB" == "sync-labels" ]]; then
    if [[ ${#ISSUES[@]} -ne 0 ]]; then
        echo "issue-claim: sync-labels reconciles the label taxonomy, not issues" >&2
        usage
    fi
else
    [[ ${#ISSUES[@]} -eq 0 ]] && usage
    for n in ${ISSUES[@]+"${ISSUES[@]}"}; do
        case "$n" in
            ''|*[!0-9]*) echo "issue-claim: not an issue number: $n" >&2; exit 64 ;;
        esac
    done
fi

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

# Reconcile one label: create it when absent, CORRECT it when its colour or
# description has drifted, write nothing when it already matches.
#
# This used to be a bare `gh label create ... || true`. `gh label create` fails
# on a label that already exists and the failure was swallowed, so a colour
# change here reached only repos that did not yet have the label — every
# already-onboarded repo kept the old colour indefinitely and nothing said so
# (issue #161, the same silent-no-op class as #97/#98). Reading first is what
# makes a taxonomy change actually propagate. Modelled on align-labels.sh,
# which solves the same problem for the other taxonomy.
#
# Still benign on failure — a claim must never die because a label edit did —
# but never silent: every write and every failure is announced on stderr.
# Sets LABEL_ACTION/LABEL_DETAIL for sync-labels' JSON. Returns 1 on a failed
# write so a caller that cares can notice.
LABEL_ACTION=""
LABEL_DETAIL=""
ensure_label() {  # $1=name $2=color $3=description
    local name="$1" want_color="$2" desc="$3"
    local cur cur_color cur_desc drift rc err
    want_color=$(printf '%s' "$want_color" | tr '[:upper:]' '[:lower:]')

    if cur=$(gh api "repos/$REPO/labels/$name" \
                --jq '[(.color // ""), (.description // "")] | @tsv' 2>/dev/null); then
        IFS=$'\t' read -r cur_color cur_desc <<<"$cur"
        cur_color=$(printf '%s' "${cur_color:-}" | tr '[:upper:]' '[:lower:]')
        drift=""
        [[ "$cur_color" != "$want_color" ]] && drift="color $cur_color -> $want_color"
        if [[ "${cur_desc:-}" != "$desc" ]]; then
            drift="${drift:+$drift; }description \"${cur_desc:-}\" -> \"$desc\""
        fi
        if [[ -z "$drift" ]]; then
            LABEL_ACTION="ok"; LABEL_DETAIL=""
            return 0
        fi
        if [[ "$dry_run" == "1" ]]; then
            LABEL_ACTION="would-update"; LABEL_DETAIL="$drift"
            return 0
        fi
        rc=0
        err=$(ghw label edit "$name" --repo "$REPO" --color "$want_color" \
            --description "$desc" 2>&1 >/dev/null) || rc=$?
        if [[ "$rc" -ne 0 ]]; then
            LABEL_ACTION="failed"
            LABEL_DETAIL="$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
            echo "issue-claim: label '$name' is stale in $REPO ($drift) and the fix failed: $LABEL_DETAIL" >&2
            return 1
        fi
        LABEL_ACTION="update"; LABEL_DETAIL="$drift"
        echo "issue-claim: corrected label '$name' in $REPO ($drift)" >&2
        return 0
    fi

    # Absent, or the read itself failed. Creating is right in the first case
    # and harmless in the second (an "already exists" error is not retried by
    # gh-retry.sh), but it is REPORTED either way.
    if [[ "$dry_run" == "1" ]]; then
        LABEL_ACTION="would-create"; LABEL_DETAIL="absent"
        return 0
    fi
    rc=0
    err=$(ghw label create "$name" --repo "$REPO" --color "$want_color" \
        --description "$desc" 2>&1 >/dev/null) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        LABEL_ACTION="failed"
        LABEL_DETAIL="$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
        echo "issue-claim: could not ensure label '$name' in $REPO: $LABEL_DETAIL" >&2
        return 1
    fi
    LABEL_ACTION="create"; LABEL_DETAIL="absent"
    return 0
}

emit() {  # $1=issue $2=result $3=detail
    jq -cn --arg i "$1" --arg op "$SUB" --arg r "$2" --arg d "$3" \
        '{issue:($i|tonumber), op:$op, result:$r, detail:$d}'
}

emit_label() {  # $1=label $2=action $3=detail
    jq -cn --arg l "$1" --arg a "$2" --arg d "$3" \
        '{label:$l, action:$a, detail:$d}'
}

# sync-labels: reconcile the whole taxonomy without touching an issue. The
# transitions below heal a label the moment they use it, which covers a repo
# that keeps working; this covers the one that does not, and gives the org-wide
# propagation pass a single call per repo.
if [[ "$SUB" == "sync-labels" ]]; then
    sync_failed=0
    for spec in "${DEVWORKFLOW_LABELS[@]}"; do
        IFS='|' read -r l_name l_color l_desc <<<"$spec"
        ensure_label "$l_name" "$l_color" "$l_desc" || sync_failed=1
        emit_label "$l_name" "$LABEL_ACTION" "$LABEL_DETAIL"
    done
    [[ "$sync_failed" == "1" ]] && exit 2
    exit 0
fi

# Who am I. Two callers need it: claim's double-pick guard, and promote's
# residue gate, which can only tell residue from a live claim by comparing the
# assignee against @me. Degrades to no guard / no clear when unknown — an
# unresolved login is unknown, and unknown is not verified.
ME=""
if [[ "$SUB" == "claim" || "$SUB" == "promote" ]]; then
    ME=$(gh api user --jq .login 2>/dev/null || true)
fi

# --- promote's claim-residue gate (issue #281) --------------------------------
# A claim is WRITTEN as two things — `--add-assignee @me` AND `--add-label
# in-progress`, in one `gh issue edit` — and RELEASED as one, `--remove-label
# in-progress`. Nothing clears the assignee half, and on a CLOSED issue nothing
# should: that assignee records who shipped it, which is ordinary GitHub
# convention. Making `release` symmetric is the obvious tidy and it is the wrong
# trade — it destroys that record on every closed issue to fix a defect that is
# only reachable one way.
#
# That way is REOPEN. dispatch-ready's §4 Claimed filter skips on "assignee set
# OR label state" — a disjunction, deliberately, so that a human who assigns
# themselves without setting in-progress is still honoured — while its §3
# defines in-flight as assignee AND label, a conjunction. So a reopened,
# re-promoted issue arrives in ready[] still assigned and is silently skipped as
# "another session got it", which is false. It sits in Ready, never dispatches,
# and the stated reason is wrong. Do NOT "align" §3 and §4 to fix this; the
# asymmetry is the guard for the self-assigning human.
#
# Promotion is the moment the system asserts "this is dispatchable and
# unclaimed", so it is where the residue is cleared — and it fires only on
# issues actually about to be dispatched.
#
# THE SHAPE GATE. The loop only ever assigns @me, and `claim` ALWAYS pairs that
# with in-progress in a single edit, so:
#
#     assignees == exactly {@me}  AND  in-progress absent  AND  issue OPEN
#         -> the residue shape.
#
# Every other shape is a live claim: reported on stderr and in the JSON detail,
# never cleared.
#   - any other login among the assignees — a human took it, which is exactly
#     the signal §4's disjunction exists to honour;
#   - @me WITH in-progress — real in-flight work;
#   - a CLOSED issue — the who-shipped-it record, which is the whole reason
#     `release` is not symmetric; promote has no business there, and refusing in
#     this body rather than trusting the caller is the shape align-labels.sh's
#     delete gate established;
#   - a probe that could not run (login unresolved, read failed, malformed
#     result) — unknown is not verified.
#
# KNOWN LIMIT, stated rather than papered over. `@me` is the OPERATOR's login,
# not a loop identity, so the loop's residue and the operator's own
# self-assignment are byte-identical: an issue the operator assigned to
# themselves without setting in-progress matches the shape above and its
# assignment is cleared. #281 asserts the shape "cannot have come from anywhere
# else"; that is true of any OTHER account and false of the operator's own, and
# the honest form of the claim is the narrower one. Distinguishing them needs
# positive evidence of a completed claim cycle (a closing-PR reference, a
# reopen event, or a marker `release` leaves behind) — a fourth conjunct #281
# does not sanction and whose absence its acceptance criteria depend on, so it
# is filed as issue #287 rather than guessed at here. Note reopen evidence
# ALONE is not the fix: `block` strips both labels and leaves the assignee, so
# claim -> block -> promote is the same residue with no close in its history.
#
# `--force` deliberately does NOT widen this. It is claim's double-pick
# override; letting it strip an assignee here would hand the loop a way to
# unassign a human, which is the one outcome this gate exists to prevent.
#
# Sets RESIDUE_ARGS (the edit arguments, empty unless clearing), RESIDUE_REASON
# (why the clear applies — the caller composes the tense) and RESIDUE_NOTE (a
# finished decision line, for every path that writes nothing).
RESIDUE_ARGS=()
RESIDUE_NOTE=""
RESIDUE_REASON=""
promote_residue_gate() {  # $1=issue number
    RESIDUE_ARGS=()
    RESIDUE_NOTE=""
    RESIDUE_REASON=""
    local n="$1" view assignees labels state read_ok

    # A READ, so it runs bare rather than through gh-retry.sh — same as the
    # claim double-pick guard above. One value per LINE, never @tsv through
    # `read`: TAB is IFS *whitespace*, so IFS whitespace collapses a leading
    # empty field away, and the assignee field is empty on exactly the ordinary
    # case. Measured: `IFS=$'\t' read -r a l <<<$'\tready,bug'` yields
    # a=ready,bug — an unassigned issue reading its own LABELS as its assignees.
    # `IFS=` with one read per line preserves every field exactly as emitted.
    if ! view=$(gh issue view "$n" --repo "$REPO" --json assignees,labels,state \
        --jq '[([.assignees[]?.login] | join(",")), ([.labels[]?.name] | join(",")), (.state // "")] | .[]' 2>/dev/null); then
        RESIDUE_NOTE="assignee unchecked: could not read #$n"
        echo "issue-claim: #$n — assignees/labels unreadable, so a claim residue cannot be told from a live claim; left in place" >&2
        return 0
    fi
    read_ok=1
    {
        IFS= read -r assignees || read_ok=0
        IFS= read -r labels    || read_ok=0
        IFS= read -r state     || read_ok=0
    } <<<"$view"
    if [[ "$read_ok" != "1" ]]; then
        RESIDUE_NOTE="assignee unchecked: malformed probe result for #$n"
        echo "issue-claim: #$n — the assignee probe did not return all three fields; a claim residue, if any, is left in place" >&2
        return 0
    fi

    # Unassigned: the ordinary case. Nothing to clear and nothing to report.
    [[ -z "$assignees" ]] && return 0

    if [[ -z "$ME" ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: own login unresolved"
        echo "issue-claim: #$n is assigned to '$assignees' but this run could not resolve its own login — left alone" >&2
        return 0
    fi
    if [[ "$assignees" != "$ME" ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: not this session's claim"
        echo "issue-claim: #$n is assigned to '$assignees' — a live claim, left alone" >&2
        return 0
    fi
    if [[ ",$labels," == *",$INPROG_LABEL,"* ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: $INPROG_LABEL present, a live claim"
        echo "issue-claim: #$n is assigned to '$assignees' WITH $INPROG_LABEL — in-flight, left alone" >&2
        return 0
    fi
    if [[ "$state" != "OPEN" ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: #$n is $state, and that assignee records who shipped it"
        echo "issue-claim: #$n is $state — the assignee records who shipped it, left alone" >&2
        return 0
    fi

    # The inverse of the exact token `claim` wrote. The DECISION is recorded
    # here; the tense is not, because this runs before the edit does — a past
    # tense composed at this point would describe a write that has not been
    # attempted, and would survive one that failed.
    RESIDUE_ARGS=(--remove-assignee "@me")
    RESIDUE_REASON="assignee '$assignees', no $INPROG_LABEL"
    return 0
}

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

    # promote: classify any residual claim assignee (issue #281). The probe is
    # a READ and runs BEFORE the dry-run gate on purpose, so --dry-run previews
    # the assignee decision instead of hiding the one write it just learned to
    # make.
    # The reset lives in the gate alone — a second copy here would be redundant
    # and invites deleting both, which lets one issue's verdict leak into the
    # next one's edit in a batch (`promote N1 N2`, the form groom-backlog ships).
    [[ "$SUB" == "promote" ]] && promote_residue_gate "$n"

    if [[ "$dry_run" == "1" ]]; then
        # Only the residue case composes its note HERE; every left-alone path
        # already echoed its own line inside the gate, so echoing $RESIDUE_NOTE
        # unconditionally would print those twice.
        if [[ ${#RESIDUE_ARGS[@]} -gt 0 ]]; then
            RESIDUE_NOTE="would clear claim residue: $RESIDUE_REASON"
            echo "issue-claim: #$n — $RESIDUE_NOTE" >&2
        fi
        emit "$n" "would-$SUB" "dry-run: no writes${RESIDUE_NOTE:+ ($RESIDUE_NOTE)}"
        continue
    fi

    # Failure detection keys off the EXIT CODE, not stderr content — gh-retry.sh
    # writes "[gh-retry] attempt ..." progress to stderr even on eventual success.
    rc=0
    err=""
    case "$SUB" in
        claim)
            ensure_label "$INPROG_LABEL" "$INPROG_COLOR" "$INPROG_DESC" || true
            err=$(ghw issue edit "$n" --repo "$REPO" --add-assignee @me \
                --add-label "$INPROG_LABEL" --remove-label "$READY_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        release)
            err=$(ghw issue edit "$n" --repo "$REPO" \
                --remove-label "$INPROG_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        block)
            ensure_label "$BLOCKED_LABEL" "$BLOCKED_COLOR" "$BLOCKED_DESC" || true
            err=$(ghw issue edit "$n" --repo "$REPO" --remove-label "$READY_LABEL" \
                --remove-label "$INPROG_LABEL" --add-label "$BLOCKED_LABEL" 2>&1 >/dev/null) || rc=$?
            ;;
        promote)
            ensure_label "$READY_LABEL" "$READY_COLOR" "$READY_DESC" || true
            # One edit, as claim writes one edit. RESIDUE_ARGS is empty unless
            # the shape gate above found residue by construction; the bash 3.2
            # empty-array guard is what keeps that safe under `set -u`.
            err=$(ghw issue edit "$n" --repo "$REPO" \
                --add-label "$READY_LABEL" \
                ${RESIDUE_ARGS[@]+"${RESIDUE_ARGS[@]}"} 2>&1 >/dev/null) || rc=$?
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
    #
    # SCOPED to the subcommands that actually carry a --remove-label. `promote`
    # does not, and swallowing its failures let it report `ok` — with a cleared
    # assignee in the detail — on an edit that wrote nothing at all, neither the
    # removal nor the `ready` label the whole subcommand exists to add.
    tolerated=0
    case "$SUB" in
        claim|release|block|demote)
            if [[ "$rc" -ne 0 ]]; then
                case "$err" in
                    *"not found"*|*"could not be found"*) tolerated=1 ;;
                esac
            fi ;;
    esac
    if [[ "$rc" -ne 0 && "$tolerated" == "0" ]]; then
        detail="$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
        # UNVERIFIED, not "not cleared": gh sends labels via updateIssue and
        # assignees via replaceActorsForAssignable, so a non-zero rc on the
        # label half does not establish that the removal did not land.
        [[ ${#RESIDUE_ARGS[@]} -gt 0 ]] && detail="$detail; claim residue clear UNVERIFIED"
        emit "$n" "failed" "$detail"
        hard_failed=1
        continue
    fi

    # Past tense only now, downstream of the write that carries it.
    if [[ ${#RESIDUE_ARGS[@]} -gt 0 ]]; then
        RESIDUE_NOTE="cleared claim residue: $RESIDUE_REASON"
        echo "issue-claim: #$n — $RESIDUE_NOTE" >&2
    fi

    if [[ -n "$COMMENT" ]]; then
        crc=0
        cerr=$(ghw issue comment "$n" --repo "$REPO" --body "$COMMENT" 2>&1 >/dev/null) || crc=$?
        if [[ "$crc" -ne 0 ]]; then
            echo "issue-claim: #$n label edit ok but comment failed: $(echo "$cerr" | grep -v '^\[gh-retry\]' | head -1)" >&2
        fi
    fi

    emit "$n" "ok" "$RESIDUE_NOTE"
done

[[ "$hard_failed" == "1" ]] && exit 2
exit 0
