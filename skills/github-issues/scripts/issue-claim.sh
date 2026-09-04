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
# NAMED `requested:` RATHER THAN `stripped:`, deliberately and on review. Past
# tense in a field a coordinator reads is a hazard here specifically:
# `dispatch-ready` §2 carries a standing order to read a demotion "from live
# state, never from the exit code alone", and a past-tense token in the same
# JSON object invites exactly the reading that order forbids. The value is a
# claim about the REQUEST; the name now says so, and `removed:` is reserved for
# the live-state answer. Do not rename it back to match the verb the docs use
# for the operation.
#
# On an `ok`, `detail` carries `requested: <labels>` for the FOUR subcommands
# that remove one — claim, release, block, demote. It names the removals the
# edit REQUESTED (minus any dropped as absent from the repo), which a zero exit
# proves gh applied. It is NOT a claim the issue CARRIED them: `demote` on an
# issue with no `ready` succeeds, removes nothing, and says `requested: ready`
# all the same. (`block` would say `requested: ready,in-progress` — it always
# requests both.) Read it as the request, never as the effect. The effect is
# Label names are matched CASE-INSENSITIVELY, as gh matches them, and reported
# in taxonomy spelling rather than the repo's. The effect is
# `removed:`, which reads live state on the repair path and REPLACES
# `requested:` there — with ONE exception: when the probe could not answer,
# `removed: unknown` rides ALONGSIDE `requested:` rather than displacing it,
# because a non-answer must not suppress a computable fact (#323).
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
# Seconds of slack between a claim's LabeledEvent and its AssignedEvent. They
# come from ONE `gh issue edit` and are NOT simultaneous — measured one second
# apart, label first — so a zero grace rejects genuine residue. Wide enough to
# hold a same-edit pair, narrow enough that an assignment made after the last
# cycle ended is still a self-assignment. See promote_residue_gate() (#287).
RESIDUE_GRACE=120
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
# THAT LIMIT IS NOW CLOSED (issue #287), and the shape of the fix is worth more
# than the fix. `@me` is the OPERATOR's login, not a loop identity, so the
# loop's residue and the operator's own self-assignment were byte-identical:
# an issue the operator assigned to themselves without setting in-progress
# matched the three conjuncts above and had its assignment cleared. #281
# asserts the shape "cannot have come from anywhere else"; that is true of any
# OTHER account and false of the operator's own.
#
# The FOURTH conjunct is positive evidence of a completed claim cycle, and the
# evidence chosen is deliberately NOT the obvious one. #281 named a closing-PR
# reference or a reopen event; both miss the claim -> block -> promote path,
# which produces the same residue with no close and no reopen anywhere in its
# history, because `block` strips both labels and leaves the assignee. What
# covers every path is the in-progress LABELLING itself: `claim` writes the
# label and the assignee in ONE edit, so a real claim always leaves a
# LabeledEvent beside its AssignedEvent and a self-assignment leaves an
# AssignedEvent alone. See promote_residue_gate() for the grace window that
# same-edit pair requires — the two events are NOT simultaneous, and a rule
# without it rejects genuine residue.
#
# THE REMAINING LIMIT is narrower and is stated rather than closed: a human who
# self-assigns an issue and then adds `in-progress` BY HAND has performed
# something this gate cannot distinguish from a claim, because it is one in
# every observable respect. Failing to clear stays the safe direction, so the
# gate reports and a human clears by hand.
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
    # CASE-FOLDED on both sides, because gh is — the same measured reason
    # `labels_removed_detail` folds below (#326). gh resolves label names with
    # `strings.EqualFold` (`api/queries_repo.go`'s `LabelsToIDs`), so `claim`
    # writes the constant `in-progress` and a repo spelling it `In-Progress`
    # stores THAT. A byte-equal test then fails to see a LIVE claim: the gate
    # falls through to the timeline conjunct, classifies it `never_claimed`,
    # leaves the assignee, and reports a "self-assignment" — #281's silent skip
    # returning on that class of repo with the wrong cause named (#334).
    # LC_ALL=C pins the fold to ASCII, a strict SUBSET of EqualFold, so a Mac
    # and the runner cannot disagree.
    local labels_lc inprog_lc
    labels_lc="$(printf '%s' "$labels" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    inprog_lc="$(printf '%s' "$INPROG_LABEL" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    if [[ ",$labels_lc," == *",$inprog_lc,"* ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: $INPROG_LABEL present, a live claim"
        echo "issue-claim: #$n is assigned to '$assignees' WITH $INPROG_LABEL — in-flight, left alone" >&2
        return 0
    fi
    if [[ "$state" != "OPEN" ]]; then
        RESIDUE_NOTE="assignee '$assignees' left alone: #$n is $state, and that assignee records who shipped it"
        echo "issue-claim: #$n is $state — the assignee records who shipped it, left alone" >&2
        return 0
    fi

    # FOURTH CONJUNCT (#287) — positive evidence that a CLAIM CYCLE happened.
    #
    # The three conjuncts above are true of loop residue AND of an issue the
    # OPERATOR self-assigned, because `@me` is the operator's personal login
    # rather than a loop identity: `claim` assigns the human running the loop,
    # and every session shares it. #281's "it cannot have come from anywhere
    # else" is true of any OTHER account and false of the operator's own. Left
    # there, `promote` strips a human's own assignment, §4 stops skipping the
    # issue, and a cold worktree agent is dispatched onto work a human is
    # already doing — the double-pick the claim guard exists to prevent,
    # reached through the promotion path instead.
    #
    # The evidence is that `in-progress` was ever LABELLED on this issue at the
    # time of the assignment. `claim` writes both halves in ONE `gh issue edit`,
    # so a real claim always leaves a LabeledEvent beside its AssignedEvent;
    # a human who self-assigns leaves an AssignedEvent alone.
    #
    # WHY A GRACE WINDOW, and why the obvious rule is wrong. The two events are
    # written by one API call and DO NOT share a timestamp: measured on #286,
    # `LabeledEvent in-progress` at 14:38:41Z and `AssignedEvent` at 14:38:42Z —
    # the label lands one second BEFORE the assignment. So "the label event is
    # at or after the assign event" rejects genuine residue. The test is
    # `label >= assign - RESIDUE_GRACE` instead, which keeps a same-edit pair
    # together while still refusing an assignment made minutes or days after the
    # last claim cycle ended.
    #
    # This deliberately COVERS the claim -> block -> promote path, which has no
    # close and no reopen anywhere in its history and which a reopen-evidence
    # conjunct would miss: `block` strips both labels and leaves the assignee,
    # so the LabeledEvent from the original claim is still the discriminator.
    # That is #287's third acceptance item, decided rather than left to fall out.
    #
    # Timestamps are compared in jq (`fromdateiso8601`), never with `date`,
    # which takes incompatible flags on BSD and GNU.
    #
    # DEGRADES TO NOT CLEARING. Failing to clear is the safe direction — it
    # reports, and a human clears by hand — so an unreadable timeline, an
    # unparsable payload or a missing `gh` all leave the assignee in place.
    local tl cycle
    if ! tl=$(gh api graphql -f query='
        query($owner:String!,$name:String!,$num:Int!){
          repository(owner:$owner,name:$name){
            issue(number:$num){
              timelineItems(last:100, itemTypes:[ASSIGNED_EVENT,LABELED_EVENT]){
                nodes{ __typename
                  ... on AssignedEvent { createdAt assignee { ... on User { login } } }
                  ... on LabeledEvent  { createdAt label { name } } } } } } }' \
        -F owner="${REPO%%/*}" -F name="${REPO##*/}" -F num="$n" 2>/dev/null); then
        RESIDUE_NOTE="assignee '$assignees' left alone: claim-cycle history unreadable"
        echo "issue-claim: #$n — could not read the timeline, so a claim residue cannot be told from a self-assignment; left in place" >&2
        return 0
    fi
    # The LabeledEvent name is CASE-FOLDED against the constant for the same
    # reason as the label-presence test above: the timeline returns the label as
    # the repo SPELLS it, not as this script passes it. `ascii_downcase` is
    # jq's ASCII-only fold, matching the LC_ALL=C bound used there (#334).
    cycle=$(jq -r --arg me "$ME" --arg lab "$INPROG_LABEL" --argjson grace "$RESIDUE_GRACE" '
        (.data.repository.issue.timelineItems.nodes // []) as $ns
        | ([ $ns[] | select(.__typename == "AssignedEvent" and ((.assignee.login // "") == $me)) | .createdAt ] | last) as $a
        | ([ $ns[] | select(.__typename == "LabeledEvent"  and (((.label.name // "") | ascii_downcase) == ($lab | ascii_downcase))) | .createdAt ] | last) as $l
        | if   $a == null then "no_assign_event"
          elif $l == null then "never_claimed"
          elif (($l | fromdateiso8601) >= (($a | fromdateiso8601) - $grace)) then "residue"
          else "self_assigned"
          end' <<<"$tl" 2>/dev/null)
    case "$cycle" in
        residue) : ;;
        never_claimed|self_assigned)
            RESIDUE_NOTE="assignee '$assignees' left alone: no claim cycle precedes this assignment ($cycle)"
            echo "issue-claim: #$n is assigned to '$assignees' with no $INPROG_LABEL ever labelled at that assignment — a self-assignment, not loop residue; left alone" >&2
            return 0 ;;
        *)
            RESIDUE_NOTE="assignee '$assignees' left alone: claim-cycle probe returned '${cycle:-empty}'"
            echo "issue-claim: #$n — the claim-cycle probe returned '${cycle:-empty}'; unknown is not verified, so the assignee is left in place" >&2
            return 0 ;;
    esac

    # The inverse of the exact token `claim` wrote. The DECISION is recorded
    # here; the tense is not, because this runs before the edit does — a past
    # tense composed at this point would describe a write that has not been
    # attempted, and would survive one that failed.
    RESIDUE_ARGS=(--remove-assignee "@me")
    RESIDUE_REASON="assignee '$assignees', no $INPROG_LABEL"
    return 0
}

# --- what each subcommand REMOVES (issue #288) ---------------------------------
# The `not found` tolerance below keys on these tokens, so the labels each
# subcommand strips are named here as DATA — deliberately not a regex over "any
# label this subcommand mentions": `claim`'s `--add-label in-progress` and
# `block`'s `--add-label blocked` are exactly the tokens that must NOT be
# tolerated, so a match against the union re-admits the very bug the scoping
# fixes.
#
# `promote` removes nothing — it adds `ready` and clears a residue assignee —
# and its empty list is written out rather than left implicit, because that
# emptiness IS #281's fix and a reader following this table should not have to
# infer it from an absent arm. The arm is inert, the initialiser above already
# covering it, which is precisely what makes it safe to keep as documentation.
#
# The `--remove-label` flags stay SPELLED OUT in each edit below rather than
# being built from this list, which looks like the obvious de-duplication.
# `scripts/test-drain-terminal-states.sh` reads the `block)` arm's own text for
# one of the three cross-file facts its whole account of #282 rests on — that
# `block` strips BOTH labels — and it asserts that by LITERAL, so deriving the
# flags REDDENS that gate rather than quietly weakening it. Loud is the right
# direction, so the reason the duplication stays is not that the derivation is
# unsafe: it is that removing the duplication means repointing at this table the
# window of a gate that pins another issue's decisions, which is not this
# change's to make. That option is real and belongs to whoever owns gate 32; no
# figure for its size is quoted here, because none was measured here.
#
# What the duplication costs is a second home for the list, and the drift it
# admits is LOUD in the only direction that matters: a removal present in the
# edit and missing here stops being tolerated, so gh's `not found` becomes a
# hard failure rather than a silent success. The reverse cannot fire at all — an
# error naming a label the edit no longer mentions is not an error this edit can
# produce. The gate closes the loop from the other side: every tolerated-edge
# case asserts the failure it relies on was actually injected, so an edit arm
# that stops passing a removal this table names reddens it.
REMOVALS=()
case "$SUB" in
    claim)   REMOVALS=("$READY_LABEL") ;;
    release) REMOVALS=("$INPROG_LABEL") ;;
    block)   REMOVALS=("$READY_LABEL" "$INPROG_LABEL") ;;
    demote)  REMOVALS=("$READY_LABEL") ;;
    promote) REMOVALS=() ;;
esac

# --- what a strip actually did (issue #323, second half) -----------------------
# TWO different claims live in the `detail`, and conflating them is what #323's
# reporter asked to end:
#
#   `requested:` — the removals this edit REQUESTED, minus any dropped as absent
#                 from the repo. A zero exit proves gh applied that set, so it
#                 is a fact about the EDIT. It is NOT a claim the issue carried
#                 them: `demote` on an issue with no `ready` succeeds, removes
#                 nothing, and reports `requested: ready` all the same. `block`
#                 always requests BOTH of its labels, so its value there is
#                 `requested: ready,in-progress`.
#
#   `removed:`  — the labels that were genuinely ON the issue and are now gone,
#                 established by READING LIVE STATE. Only the repair path pays
#                 for it. That is deliberate rather than thrift: once the repair
#                 re-issues the edit, the ordinary path's rc is trustworthy, so
#                 a read there would cost one `gh` call per issue per tick in
#                 dispatch-ready's batched loops and buy back visibility nobody
#                 had lost. The repair path is where #323 actually bit.
#
# labels_removed_detail <issue> <label>...
#   -> echoes `removed: a,b` naming only those candidate labels the issue
#      ACTUALLY carried; `removed: ` (empty list) when it carried none.
#
# It is called BEFORE the repair re-issues, which is the only moment the
# pre-state is readable without a second call: the first edit abandoned every
# removal (measured — see the repair note below), so the labels are still
# intact here.
#
# Constraints for the body:
#   - bash 3.2 (macOS ships it) under `set -u`: guard every array expansion with
#     the `${arr[@]+"${arr[@]}"}` idiom used throughout this file.
#   - this probe is a READ and runs BARE `gh` with stderr discarded; every
#     WRITE in this script still routes through `ghw`. The reason is below and
#     `(e5)` pins it — do not "restore" the ghw call.
#   - a failed read is UNKNOWN, never "removed nothing". promote_residue_gate
#     sets the precedent (#281: unknown is not verified) — say so in the text
#     rather than echoing an empty list.
#   - KNOWN LIMIT, stated rather than closed: `join(",")` is ambiguous, and
#     GitHub permits a comma in a label name, so a label literally named
#     `foo,ready` makes this report `ready` as removed. Closing it means
#     abandoning the joined form for a per-label membership query, which costs
#     a call per candidate; the trade was judged not worth it for a name shape
#     nothing in this taxonomy uses.
#   - NEVER match a label name as a bare substring of anything that can hold the
#     repo slug: test-claim-lifecycle.sh's $MOCK_REPO is owned by `already`,
#     which ENDS IN `ready`. Compare label names for equality.
#   - the caller joins this onto $ok_detail with `; `, so emit no leading
#     separator and no trailing newline.
#
# IMPLEMENTED below. It always echoes a non-empty string — the `unknown` form,
# or the list form including the empty `removed: ` — so on the repair path the
# caller's `-n` test is always true.
labels_removed_detail() {  # $1=issue number, $2..=candidate labels
    local n="$1"; shift
    local view carried removed="" lbl
    # BARE `gh`, NOT `ghw`, and that is the fix rather than an oversight.
    # gh-retry.sh runs `out=$(gh "$@" 2>&1)` and prints that MERGED stream on
    # SUCCESS (gh-retry.sh:55,58), so anything gh writes to stderr during a
    # successful read lands on stdout. Reading bare keeps that text out of the
    # data and yields the TRUE answer; through `ghw` the multi-line guard below
    # catches it and degrades to `unknown`, which is safe but strictly worse.
    # (Measured: the ghw form reports `removed: unknown (malformed …)`, not an
    # empty list — the guard fires first. `unknown` therefore has exactly TWO
    # triggers, a failed read and a multi-line one; stderr-on-success is
    # PREVENTED here rather than reported.) Losing the
    # retry backoff on one READ is the cheaper half of that trade; every WRITE
    # in this script still routes through ghw.
    # DECLARE THEN ASSIGN. `local view="$(...)"` takes `local`'s exit status,
    # which is always 0, so a failed read would look like an issue carrying no
    # labels — the one outcome this function must never confuse with a real one.
    view="$(gh issue view "$n" --repo "$REPO" --json labels \
        --jq '[.labels[].name] | join(",")' 2>/dev/null)" || {
        # UNKNOWN IS NOT VERIFIED (#281's posture). An empty list already means
        # "carried none of them", which is a measured fact; a failed read must
        # not borrow it.
        echo "removed: unknown (could not read #$n)"
        return 0
    }
    # SHAPE, mirroring promote_residue_gate's read_ok: this probe emits exactly
    # ONE line, so a second line means the stream carried something the --jq
    # cannot produce. Unknown, never an empty list — the same reason the failed
    # read above does not borrow it.
    carried="$view"
    case "$view" in
        *$'\n'*)
            echo "removed: unknown (malformed label probe for #$n)"
            return 0 ;;
    esac
    # CASE-FOLDED, because gh is. Measured: `--remove-label READY` strips a
    # label named `ready`, rc 0 — gh resolves label names with a case-insensitive
    # compare. A byte-equal membership test therefore reports `removed: ` for a
    # repo whose label is `Ready`, i.e. "carried none of them", for a strip that
    # really happened — #323's own ask, inverted. The candidate is reported in
    # its canonical taxonomy casing rather than the repo's spelling.
    local carried_lc lbl_lc
    # LC_ALL=C pins the fold to ASCII, making it a strict SUBSET of gh's
    # EqualFold: BSD tr under a UTF-8 locale folds some non-ASCII codepoints
    # that Go does not, which would report a removal gh refused, and GNU tr
    # folds none — so the answer would differ between a Mac and the runner.
    carried_lc="$(printf '%s' "$carried" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    for lbl in "$@"; do
        lbl_lc="$(printf '%s' "$lbl" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
        # Comma-delimited on BOTH sides, so this is equality against a list
        # member rather than a substring test: `not-ready` must not answer for
        # `ready`, and the fixture that proves it is issue 21 in
        # test-claim-lifecycle.sh section 7e.
        case ",$carried_lc," in
            *",$lbl_lc,"*) removed="${removed:+$removed,}$lbl" ;;
        esac
    done
    # The empty list is DELIBERATELY still printed. `removed:` with nothing after
    # it is what makes a no-op strip visible, which is the half of #323 this
    # function exists for — dropping the field would make it indistinguishable
    # from a run that never looked.
    echo "removed: $removed"
}

# Scan a gh error for a NOT-FOUND naming one of THIS subcommand's own removal
# tokens and append any newly-named one to $DROPPED. Returns 0 when it appended
# at least one, 1 otherwise — so a caller can loop on it.
#
# ONE matcher, deliberately: the repair below re-issues after each drop and has
# to re-scan the new error, and a second copy of this predicate is a second
# place for the quoting to be relaxed. The token is matched QUOTED, the way gh
# writes it, because gh's message embeds the issue URL and a bare-substring
# match on `ready` is satisfied by an owner or repo named `already`.
collect_dropped_removals() {  # $1=gh stderr
    local err="$1" rl d already found=1
    case "$err" in
        *"not found"*|*"could not be found"*) ;;
        *) return 1 ;;
    esac
    for rl in ${REMOVALS[@]+"${REMOVALS[@]}"}; do
        if [[ "$err" == *"'$rl'"* ]]; then
            already=0
            for d in ${DROPPED[@]+"${DROPPED[@]}"}; do
                [[ "$rl" == "$d" ]] && already=1
            done
            if [[ "$already" == "0" ]]; then
                DROPPED+=("$rl")
                found=0
            fi
        fi
    done
    return "$found"
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
    # Each arm builds $EDIT_ARGS rather than calling `ghw` itself, because the
    # REPAIR below has to re-issue THIS edit minus one token (issue #323). The
    # `--remove-label` flags stay spelled out per arm — the note above explains
    # why deriving them from $REMOVALS is not this change's to make, and
    # test-drain-terminal-states.sh reads the `block)` arm's own text for ONE
    # of its three cross-file facts, asserting it by three literals.
    # Building an array preserves both: the literals
    # stay where that gate looks, and the repair filters the array instead of
    # rebuilding a second copy of every subcommand's ADDS. A repair that had to
    # respell the adds would be a second home for them, and #288's fixture is
    # precisely a repo where an add fails.
    EDIT_ARGS=()
    case "$SUB" in
        claim)
            ensure_label "$INPROG_LABEL" "$INPROG_COLOR" "$INPROG_DESC" || true
            EDIT_ARGS=(--add-assignee @me
                --add-label "$INPROG_LABEL" --remove-label "$READY_LABEL")
            ;;
        release)
            EDIT_ARGS=(--remove-label "$INPROG_LABEL")
            ;;
        block)
            ensure_label "$BLOCKED_LABEL" "$BLOCKED_COLOR" "$BLOCKED_DESC" || true
            EDIT_ARGS=(--remove-label "$READY_LABEL"
                --remove-label "$INPROG_LABEL" --add-label "$BLOCKED_LABEL")
            ;;
        promote)
            ensure_label "$READY_LABEL" "$READY_COLOR" "$READY_DESC" || true
            # One edit, as claim writes one edit. RESIDUE_ARGS is empty unless
            # the shape gate above found residue by construction; the bash 3.2
            # empty-array guard is what keeps that safe under `set -u`.
            EDIT_ARGS=(--add-label "$READY_LABEL"
                ${RESIDUE_ARGS[@]+"${RESIDUE_ARGS[@]}"})
            ;;
        demote)
            EDIT_ARGS=(--remove-label "$READY_LABEL")
            ;;
    esac
    err=$(ghw issue edit "$n" --repo "$REPO" \
        ${EDIT_ARGS[@]+"${EDIT_ARGS[@]}"} 2>&1 >/dev/null) || rc=$?

    # `--remove-label` of a label that doesn't exist in the REPO at all is gh's
    # one non-idempotent edge: it errors instead of no-opping (removing a label
    # the issue merely doesn't carry is already a silent no-op). Nothing to
    # remove = the desired end state — treat "not found" errors as ok.
    #
    # SCOPED TWICE, and the two scopes fix two halves of the same defect.
    #
    # (1) To the subcommands that actually carry a `--remove-label` — i.e. to a
    #     NON-EMPTY $REMOVALS. `promote` has none, and swallowing its failures
    #     let it report `ok` — with a cleared assignee in the detail — on an edit
    #     that wrote nothing at all, neither the removal nor the `ready` label
    #     the whole subcommand exists to add (issue #281).
    #
    # (2) To the REMOVAL's OWN label token. gh's error names one label and says
    #     nothing about which flag it came from, so `claim` and `block` — which
    #     carry an `--add-label` too — went on swallowing a wholly-failed edit
    #     whose failing operation was the ADD. `ensure_label` runs `|| true`, so
    #     on a repo where label creation fails (Terraform-managed labels, a
    #     restricted token) the whole edit fails: nothing is assigned,
    #     `in-progress` is never added, `ready` is never stripped — and `claim`
    #     reported `result: "ok"`, so the loop believed the claim landed and
    #     dispatch-ready handed the same issue to a second cold agent on its next
    #     tick. Two agents, two PRs, one issue: the double-pick the claim guard
    #     exists to prevent, reached through the silent-success path (#288).
    #
    # The token is matched QUOTED, the way gh writes it. gh's message embeds the
    # issue URL — `failed to update https://github.com/<owner>/<repo>/issues/N:
    # 'in-progress' not found` — so a bare-substring match on `ready` is
    # satisfied by an owner or repo named `already`, and the swallowed claim
    # comes back on that repo alone. If gh ever stops quoting, the tolerance
    # stops firing and the removal edge becomes a LOUD failure rather than a
    # silent success, which is the direction to fail in.
    #
    # The `could not be found` alternative is pre-existing and this change makes
    # it strictly NARROWER: it used to suffice on its own for every subcommand
    # carrying a removal, and now also needs a quoted removal token. What was
    # measured here is the form gh 2.98.0 emitted on the probe below — `'<label>'
    # not found`. Whether any gh wording reaches the other arm was NOT measured,
    # so it stays as a hedge, and no fixture exercises it: a narrowing recorded
    # rather than a path proved.
    #
    # WAS A KNOWN LIMIT, CLOSED BY #323 — and the correction is kept rather than
    # overwritten, because the wrong half was measured too and the next reader
    # needs to know which measurement covers what.
    #
    # #288 measured (gh 2.98.0, 2026-08-28) with two labels that exist in no
    # repo: when BOTH an add and a removal are unresolvable, gh refuses before
    # mutating anything. WHICH token it names when both sides are unresolvable
    # is NOT a rule and is not relied on here: gh applies the two operations as
    # separate goroutines and reports whichever errored first, so it is a
    # scheduling race (`pkg/cmd/pr/shared/editable_http.go`, `UpdateIssue`).
    # Both orderings converge on `failed`, by different routes: named-removal
    # tolerates, retries with the ADD still on it, and fails on the add; named-add
    # is not a $REMOVALS token, so the tolerance never fires at all. The token match below is scoped to
    # $REMOVALS for its own reason: an add must never be tolerated.
    #
    # What did NOT follow — and was written here as though it did — is "so an
    # edit that failed on the removal token wrote nothing either." #323 measured
    # the one-bad-token case (gh 2.100.0, 2026-09-04, live repo) and gh does the
    # opposite: adds and removes are INDEPENDENT operations, so an unresolvable
    # removal abandons every OTHER removal in that edit while the adds land.
    # `block` on a repo without `in-progress` therefore added `blocked`, left
    # `ready` standing, and reported `ok` — a demoted issue that stayed in every
    # `--label ready` queue. The repair below closes it.
    #
    # ITS PRECONDITION IS PER SUBCOMMAND, and stating it once for both gets one
    # of them wrong. The loop below carries no `break`, so ANY of a subcommand's
    # removal tokens tolerates: `claim` has one, `ready`, so `ready` absent is
    # enough; `block` has two, and EITHER absent is enough — for `block` the
    # "a repo carrying neither" form is the wrong one in the other direction.
    # The argument does NOT rest on `in-progress` being ensured above: that
    # ensure is `|| true`, and its failing is the very premise of the scenario.
    # Nor does it rest on which token gh names when both are unresolvable — see
    # above; that is a race, and both orderings reach the same verdict.
    #
    # `block` was the worse of the two and nothing observed it, which is how
    # #323 survived to be reported from a live drain rather than caught here.
    #
    # The closure is the SOUND one this note already named: re-issue the edit
    # with the named removal dropped. #288's acceptance is intact — the removal
    # edge is still tolerated for every subcommand that carries one, and
    # `release`/`demote`, whose removal is their only operation, still write
    # nothing and still report `ok`. `ensure_label`-ing the removals is still
    # NOT a closure and is still recorded so it is not mistaken for one: that
    # ensure is `|| true` on precisely the repos this edge is about, so it would
    # reintroduce #288 wearing a fix.
    #
    # What the tolerance is no longer is SILENT. It names the token it swallowed
    # on stderr and in the JSON detail, so an `ok` reached this way is at least
    # distinguishable from one that wrote something — which is the half of the
    # limit that could be closed without touching the verdict #288 freezes.
    tolerated=0
    TOLERATED_NOTE=""
    REMOVED_NOTE=""
    DROPPED=()
    # retry_args belongs to THIS issue, and unlike the four resets above it is
    # DEFENSIVE ONLY — deleting it leaves the gate green, measured, and that is
    # correct rather than a coverage hole: tolerated=1 implies a non-empty
    # $REMOVALS implies the loop body runs, which always reassigns it, so no
    # stale value is reachable today. It stays because that is a three-hop
    # invariant with no guard, and `${#unset[@]}` under `set -u` on bash 3.2 is
    # FATAL rather than zero — a future path setting tolerated=1 without
    # entering the loop would abort the batch and lose every remaining issue's
    # write. Do not delete it as dead, and do not hunt for the assertion that
    # would pin it; there cannot be one while the invariant holds.
    retry_args=()
    if [[ "$rc" -ne 0 ]] && collect_dropped_removals "$err"; then
        tolerated=1
    fi

    # THE REPAIR (issue #323). Tolerating the failure was never enough, because
    # gh does NOT abandon the whole edit: MEASURED on gh 2.100.0, 2026-09-04,
    # against a live repo, adds and removes are INDEPENDENT operations and an
    # unresolvable token kills only its OWN side.
    #
    #   remove ready + remove <absent> + add blocked  ->  blocked ADDED, ready KEPT
    #   remove ready + add <absent>                   ->  ready REMOVED, add dropped
    #   the same edit re-issued without the bad token ->  rc 0, end state correct
    #
    # The first line is #323 exactly: `block` reported `ok`, wrote `blocked`, and
    # left `ready` standing, so a demoted issue stayed in every `--label ready`
    # queue. The old note above this block asserted the opposite ("an edit that
    # failed on the removal token wrote nothing either") and the tolerance was
    # built on it. That premise was measured on a DIFFERENT case — #288 probed
    # two labels that exist in no repo, where BOTH sides are unresolvable and gh
    # refuses before mutating — and it does not generalise to one bad token.
    #
    # So re-issue the edit with the named removal dropped. A label absent from
    # the REPO is on no issue, so dropping it is a no-op by construction; every
    # surviving removal and every ADD gets its second chance. This is the
    # "SOUND closure" the note above names, and it is now affordable because the
    # arms build $EDIT_ARGS: the repair filters that array rather than respelling
    # each subcommand's adds. If the retry fails, it falls through to the hard
    # failure below UNTOLERATED — #288's wholly-failed-add case still reports
    # `failed`, because the retry names the add and its error names the add.
    #
    # The `removed:` hook. A repaired issue costs one extra `gh issue view`
    # here PLUS up to ${#REMOVALS[@]} re-issued `gh issue edit` calls — for
    # `block` on a repo carrying neither label, measured, that is 3 edits and
    # 1 view. Budget the bound, not the best case: this
    # runs inside `dispatch-ready`'s per-tick loops, the same budget
    # `queue-snapshot.sh` exists to cut. It is scoped to the repair path
    # precisely so the ordinary path stays free — there, a zero exit already
    # proves gh applied the removal set.
    #
    # The call site is HERE, before any retry, because that is the only moment
    # the pre-state is readable without a second call: the first edit abandoned
    # every removal, so the labels are still intact. It takes $REMOVALS whole
    # rather than a filtered survivor list — a label absent from the REPO is on
    # no ISSUE either, so the read excludes a dropped token by itself and no
    # scan has to duplicate the filter.
    if [[ "$tolerated" == "1" && ${#REMOVALS[@]} -gt 0 ]]; then
        REMOVED_NOTE="$(labels_removed_detail "$n" ${REMOVALS[@]+"${REMOVALS[@]}"})"
    fi

    # BOUNDED, and the bound is not cosmetic. gh names ONE unresolvable token
    # per error, so a single pass drops one label and re-issues — which is a
    # hard failure the moment a subcommand carries TWO removals and the repo has
    # NEITHER. `block` is exactly that subcommand, and the state is ordinary:
    # `block` ensures only `blocked`, so any repo that has never run
    # `promote`/`claim`/`sync-labels` carries neither label `block` strips.
    # Pre-#323 that case reported `ok` and POSTED ITS COMMENT; a single-pass
    # repair regressed it to `failed` + exit 2 with the `continue` below
    # skipping the comment entirely — an issue demoted with no reason on it,
    # which is the one thing `block`'s mandatory --comment exists to prevent,
    # and `dispatch-ready` §2 reads that failure as "still in-flight this tick".
    # So keep dropping newly-named removal tokens until the edit lands or the
    # error stops naming one. At most one pass per token this subcommand
    # carries, because every pass drops at least one and $REMOVALS is the whole
    # supply — an error naming nothing droppable breaks out to a hard failure.
    attempt=0
    while [[ "$tolerated" == "1" && "$rc" -ne 0 && $attempt -lt ${#REMOVALS[@]} ]]; do
        attempt=$((attempt + 1))
        retry_args=()
        ei=0
        while [[ $ei -lt ${#EDIT_ARGS[@]} ]]; do
            ea="${EDIT_ARGS[$ei]}"
            # EDIT_ARGS holds `--remove-label <token>` as an adjacent PAIR, the
            # one invariant these walks rest on; every arm above satisfies it.
            # The bound is checked, not assumed. Every arm satisfies the
            # adjacent-pair invariant today, but under this file's `set -u` an
            # out-of-range index is FATAL — it would abort the batch and lose
            # every remaining issue's write, the same failure the per-issue
            # reset above hardened against.
            if [[ "$ea" == "--remove-label" && $((ei + 1)) -lt ${#EDIT_ARGS[@]} ]]; then
                etok="${EDIT_ARGS[$((ei + 1))]}"
                edrop=0
                for d in ${DROPPED[@]+"${DROPPED[@]}"}; do
                    [[ "$etok" == "$d" ]] && edrop=1
                done
                [[ "$edrop" == "0" ]] && retry_args+=("$ea" "$etok")
                ei=$((ei + 2))
                continue
            fi
            retry_args+=("$ea")
            ei=$((ei + 1))
        done

        if [[ ${#retry_args[@]} -eq 0 ]]; then
            # `release`/`demote` whose ONLY operation was the absent removal.
            # No LABEL EDIT is left to write and the end state is already
            # correct — `demote` still posts its mandatory `--comment`.
            # `block` CANNOT reach here: its `--add-label blocked` is not a
            # removal pair, so the walk always copies it through and
            # $retry_args is never empty. Its both-absent case converges on the
            # loop's SECOND pass instead — which is what the bound above buys,
            # and why reducing that bound to one pass is the regression M15
            # exists to catch.
            # $rc MUST be cleared: it still carries the last edit's failure, and
            # the verdict line below turns a non-zero $rc back into a hard
            # failure regardless of $tolerated.
            rc=0
            err=""
            break
        fi

        rc=0
        err=""
        err=$(ghw issue edit "$n" --repo "$REPO" \
            "${retry_args[@]}" 2>&1 >/dev/null) || rc=$?
        [[ "$rc" -eq 0 ]] && break

        # Another removal token may be absent too. Go round on any NEWLY named
        # one; an error naming none is not this edge at all and must reach the
        # hard failure below untouched.
        collect_dropped_removals "$err" || break
    done

    # The note is composed whenever the tolerance FIRED, even if the repair then
    # failed — silence there is worse output, not safer, because the operator
    # needs to know a repair was attempted at all. What it must never do is
    # imply success, which is why the third arm below says so outright and the
    # VERDICT stays separate, decided by rc alone.
    if [[ "$tolerated" == "1" ]]; then
        # Comma-joined and number-agreed: this string reaches stderr AND the
        # machine-read `detail`, and `block` — the only two-removal subcommand —
        # is exactly the one whose detail an operator reads.
        _dq=()
        for _d in ${DROPPED[@]+"${DROPPED[@]}"}; do _dq+=("'$_d'"); done
        # Guarded like every other array read in this file: `${empty[*]}`
        # under `set -u` on bash 3.2 is fatal. Unreachable today (tolerated=1
        # implies DROPPED non-empty), which is exactly why it is cheap to hold.
        _dlist="$(IFS=,; echo "${_dq[*]+${_dq[*]}}")"
        _dlist="${_dlist//,/, }"
        if [[ ${#DROPPED[@]} -gt 1 ]]; then
            TOLERATED_NOTE="tolerated: $_dlist are absent from $REPO,"
            TOLERATED_NOTE="$TOLERATED_NOTE so removing them was already the end state"
            _reissued="re-issued the edit without them"
        else
            TOLERATED_NOTE="tolerated: $_dlist is absent from $REPO,"
            TOLERATED_NOTE="$TOLERATED_NOTE so removing it was already the end state"
            _reissued="re-issued the edit without it"
        fi
        if [[ ${#retry_args[@]} -eq 0 ]]; then
            TOLERATED_NOTE="$TOLERATED_NOTE; nothing else to write"
        elif [[ "$rc" -eq 0 ]]; then
            TOLERATED_NOTE="$TOLERATED_NOTE; $_reissued"
        else
            TOLERATED_NOTE="$TOLERATED_NOTE; the re-issued edit FAILED"
        fi
        echo "issue-claim: #$n — $TOLERATED_NOTE" >&2
    fi
    # A repair that still failed is a hard failure. Separate from the note above
    # so the note can report the attempt without ever implying it succeeded.
    [[ "$rc" -ne 0 ]] && tolerated=0
    if [[ "$rc" -ne 0 && "$tolerated" == "0" ]]; then
        detail="$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
        # The JSON is what a coordinator machine-reads; stderr is not. A repair
        # that was attempted and failed must say so HERE too, or the verdict
        # reports only the last error and nothing records that a token was
        # dropped and the edit re-issued.
        [[ -n "$TOLERATED_NOTE" ]] && detail="${TOLERATED_NOTE}; $detail"
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

    # A tolerated failure and a clean write both end here, so the detail has to
    # tell them apart — see the limit above.
    ok_detail="$RESIDUE_NOTE"
    if [[ -n "$TOLERATED_NOTE" ]]; then
        ok_detail="${ok_detail:+$ok_detail; }$TOLERATED_NOTE"
    fi
    # `removed:` (live state, repair path) outranks `requested:` (the request):
    # strictly better information about the same edit, so they are not both
    # emitted. EXCEPT when the probe could not answer — `removed: unknown` is
    # strictly WORSE than a computable `requested:`, so that one variant rides
    # ALONGSIDE it instead of displacing it. Letting a non-answer suppress a
    # fact is the same mistake as reporting the non-answer as a fact, which is
    # what the empty-list rule above forbids. Reachable only for `block`:
    # every other removing subcommand has ONE removal, which is always the
    # dropped one, so its `requested:` list is empty and there is nothing to
    # ride beside. A bare `removed: unknown` on a `release` is that, not a
    # misfire.
    if [[ -n "$REMOVED_NOTE" && "$REMOVED_NOTE" != *unknown* ]]; then
        ok_detail="${ok_detail:+$ok_detail; }$REMOVED_NOTE"
    else
        requested=()
        for rl in ${REMOVALS[@]+"${REMOVALS[@]}"}; do
            sdrop=0
            for d in ${DROPPED[@]+"${DROPPED[@]}"}; do
                [[ "$rl" == "$d" ]] && sdrop=1
            done
            [[ "$sdrop" == "0" ]] && requested+=("$rl")
        done
        if [[ ${#requested[@]} -gt 0 ]]; then
            ok_detail="${ok_detail:+$ok_detail; }requested: $(IFS=,; echo "${requested[*]}")"
        fi
        # the `unknown` variant, carried beside the request rather than instead
        [[ -n "$REMOVED_NOTE" ]] && ok_detail="${ok_detail:+$ok_detail; }$REMOVED_NOTE"
    fi
    emit "$n" "ok" "$ok_detail"
done

[[ "$hard_failed" == "1" ]] && exit 2
exit 0
