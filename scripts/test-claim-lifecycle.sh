#!/usr/bin/env bash
# test-claim-lifecycle.sh — a claim is WRITTEN as two things and CLEARED as one,
# and `promote` may only clear the half that is residue (issue #281); and the
# `not found` tolerance may only swallow a failure that IS a removal (#288).
#
# What the defect is. `issue-claim.sh claim` writes `--add-assignee @me` AND
# `--add-label in-progress` in ONE `gh issue edit`; `release` writes
# `--remove-label in-progress` and nothing else. Nothing in the tree clears the
# assignee, and on a CLOSED issue nothing should — that assignee records who
# shipped it. The residue is only reachable on REOPEN, where dispatch-ready's §4
# Claimed filter skips on "assignee set OR label state" (a disjunction) while
# its §3 defines in-flight as assignee AND label (a conjunction). So a reopened,
# re-promoted issue arrives in ready[] still assigned and is skipped as "another
# session got it" — false, silent, and it never dispatches.
#
# THE SECOND DEFECT THIS FILE PINS (issue #288, section 7b). The `not found`
# tolerance exists for gh's one non-idempotent edge — `--remove-label` of a
# label the REPO does not carry errors instead of no-opping — and it matched
# gh's bare error string. #281 scoped it to the subcommands that carry a
# removal, which fixed `promote` and left the other half standing: gh's error
# names one label and says nothing about which FLAG it came from, so `claim` and
# `block`, which carry an `--add-label` too, went on swallowing a WHOLLY-failed
# edit whose failing operation was the ADD. `ensure_label` runs `|| true`, so on
# a repo where label creation fails the whole edit fails — nothing assigned, no
# `in-progress`, `ready` never stripped — and the run reported `ok`, which is
# all a coordinator ever sees: dispatch-ready re-dispatches the same issue on
# its next tick, two cold agents, two PRs, one issue. The tolerance is now keyed
# on each subcommand's OWN removal tokens, and BOTH halves are pinned, because
# either alone is wrong — the strict cases are satisfied by deleting the
# tolerance outright, and the tolerated-edge cases by never scoping it. `block`
# appears TWICE in that table because it is the only subcommand with two
# removals, and a list that dropped its second token would still pass a
# single-token case.
#
# MEASURED, NOT ASSUMED (gh 2.98.0, 2026-08-28, probed with two labels that
# exist in no repo, which gh refuses before it mutates anything): the message is
# `failed to update <issue-url>: '<label>' not found`, identical for an add and
# for a removal, and when BOTH are unresolvable it names the REMOVAL. The mock
# reproduces that message WHOLE, and errors only for a label the invocation
# actually names — both halves are load-bearing here. The URL is why $MOCK_REPO
# is owned by `already`: the shipped tolerance matches the QUOTED token, and
# without a URL in the fixture a bare-substring match would pass every case.
# Scanning the argv is why a tolerated-edge row cannot certify its own premise:
# the removal list has two homes, and a knob that errored unconditionally
# reported `ok` about a removal the subcommand had stopped performing.
#
# One residue is STATED rather than closed: an edit that failed on the removal
# token wrote nothing either, so `claim`/`block` still report `ok` when the repo
# lacks THAT SUBCOMMAND'S REMOVAL LABEL — for `claim`, `ready` alone, since
# `claim` ensures `in-progress` itself and nothing in its path ever creates
# `ready`. #288's acceptance requires the removal edge to stay tolerated for all
# four, so the shipped script states the limit and its two available closures.
#
# Why the two obvious fixes are NOT what is tested here. Both were considered
# and rejected on #281, and both are the shape a later "make this symmetric"
# sweep reaches for, so each is pinned as a NEGATIVE:
#   - making `release` symmetric destroys the who-shipped-it record on every
#     closed issue, so section 5 asserts `release` still clears no assignee;
#   - aligning §4's disjunction to §3's conjunction throws away the guard for a
#     human who self-assigned without setting in-progress, so this gate never
#     reads dispatch-ready/SKILL.md at all and nothing here licenses that edit.
#
# THE PREMISE IS ASSERTED, NOT ASSUMED (section 2). The discriminator is only
# sound because `claim` always writes both halves together. If `claim` ever
# splits that into two edits or drops the label, it silently stops
# discriminating and this gate's whole argument collapses — with every case in
# section 3 still green, because they exercise `promote`. So the pairing is
# pinned behaviourally on its own.
#
# THE PROBE'S TRANSPORT IS ITS OWN FAILURE MODE (section 4). The gate reads
# assignees and labels in one call, and the assignee field is EMPTY on the
# ordinary promotion. `@tsv` through `read` cannot carry that: TAB is IFS
# *whitespace*, so a leading empty field collapses and an unassigned issue reads
# its own LABELS as its assignees — measured, `IFS=$'\t' read -r a l` on
# $'\tready,bug' yields a=ready,bug. The shipped probe emits one value per line
# and reads with `IFS=`. That bug is invisible to an unassigned fixture carrying
# NO labels, which is the one unassigned shape the broken idiom reads correctly,
# so section 4 fixes both the fixture and, following #263 and gate 11, proves
# the fixture adequate by running the pre-fix idiom against it.
#
# EVERY ASSERTION ABOUT THE GUARD'S BEHAVIOUR IS BEHAVIOURAL, against a mock
# `gh` that records writes. That is deliberate: a source-level grep for the
# guard's wording is satisfied by a guard that no longer runs, and the failure
# this gate exists to catch is an assignee stripped from a human's issue —
# which is a WRITE, so a write is what gets measured. It also means no mutation
# here can be the tautological kind this repo's CLAUDE.md warns about: each is
# caught by the edit it causes, never by a literal an assertion greps for.
# Section 10 is the ONE source-level check, and it reads `SKILL.md` rather than
# the guard — it exists so the shipped documentation cannot drift away from a
# subcommand that now performs an assignee write (the #220 class).
#
# The mutants are applied by EXACT WHOLE-LINE match through awk rather than by
# sed regex, and awk exits non-zero unless the target matched exactly ONCE — the
# #262 lesson, one door further along. `cmp -s` alone is not enough (it exits 2
# on a missing file, which an `if` reads as "differs", so a sed that matched
# nothing reports "mutation applied" and every negative assertion after it
# passes against a file that was never run); "matched exactly once" also refuses
# a mutation that silently rewrote two sites or drifted onto none. The mutant
# inventory is the MUTANTS array below — the run prints its length and asserts
# every member actually ran, so no count here or elsewhere can go stale (#276).
#
# No taxonomy value is transcribed here. The mock's label store is seeded from
# `issue-claim.sh taxonomy`, because a colour pasted into this file would be the
# third-copy defect gate 8 exists to catch (issue #167) and this file is not on
# its allowlist.
#
# KNOWN LIMIT, not covered and deliberately so: `@me` is the OPERATOR's login,
# so the loop's residue and the operator's own self-assignment are
# indistinguishable here. Narrowing that needs positive evidence of a completed
# claim cycle, a fourth conjunct #281 does not sanction; it is filed as #287.
#
# Mock `gh` only: no repo, no network, no live issue ever read or written.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-claim-lifecycle.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-claim-lifecycle: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

CLAIM="skills/github-issues/scripts/issue-claim.sh"
RETRY="skills/pr-shepherd/scripts/gh-retry.sh"
SKILL="skills/github-issues/SKILL.md"

for f in "$CLAIM" "$RETRY" "$SKILL"; do
    [ -f "$f" ] || { echo "test-claim-lifecycle: $f missing" >&2; exit 1; }
done

# A missing jq is a courtesy skip locally and a HARD FAILURE in CI: the mock IS
# jq, so a skipped run measures nothing at all, and preflight renders a skip
# that exits 0 as PASS. Same split as test-template-actionlint.sh.
if ! command -v jq >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
        echo "test-claim-lifecycle: jq is REQUIRED in CI — this gate cannot run without it" >&2
        exit 1
    fi
    echo "test-claim-lifecycle: SKIP (jq not installed — CI still enforces)" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1" >&2; }
bad() { asserts=$((asserts + 1)); fail=1; echo "  FAIL  $1" >&2; }

echo "claim-lifecycle tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
# An issue store ($MOCK_ISSUES: number<TAB>assignees<TAB>labels<TAB>state, the
# two lists CSV), a label store ($MOCK_LABELS, seeded from the shipped taxonomy
# so ensure_label finds every label aligned and writes nothing), and an
# append-only record of every MUTATING call ($MOCK_WRITES). Reads never touch
# $MOCK_WRITES, so "what did this run write" is exactly what the log holds.
#
# The mock feeds REAL jq real JSON, so the --jq expressions in the script under
# test are genuinely exercised rather than stubbed — which is the only reason
# the transport bug in section 4 is reproducible here at all.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

jq_expr=""
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jq_expr="$a"
    prev="$a"
done

row() { awk -F'\t' -v k="$2" '$1 == k { print; exit }' "$1"; }

cmd="$1"; shift
case "$cmd" in
    api)
        path="$1"
        case "$path" in
            user)
                # An empty MOCK_LOGIN models a token whose login cannot be
                # resolved — the degradation case, not a stub.
                if [ -z "${MOCK_LOGIN:-}" ]; then
                    echo "gh: HTTP 401 Bad credentials" >&2
                    exit 1
                fi
                jq -n --arg l "$MOCK_LOGIN" '{login: $l}' | jq -r "${jq_expr:-.}" ;;
            repos/*/labels/*)
                name="${path##*/}"
                line=$(row "$MOCK_LABELS" "$name")
                [ -z "$line" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                color=$(printf '%s' "$line" | cut -f2)
                desc=$(printf '%s' "$line" | cut -f3)
                jq -n --arg c "$color" --arg d "$desc" \
                    '{color: $c, description: $d}' | jq -r "${jq_expr:-.}" ;;
            graphql)
                # The claim-cycle timeline (#287). A row is
                #   number<TAB>assigned_at<TAB>inprogress_labeled_at
                # and an EMPTY label time models an issue that was never
                # claimed — the operator's own self-assignment, which is the
                # shape this whole conjunct exists to tell apart.
                if [ "${MOCK_FAIL_TIMELINE:-0}" = "1" ]; then
                    echo "gh: HTTP 502 Bad Gateway" >&2
                    exit 1
                fi
                gnum=""
                for a in "$@"; do
                    case "$a" in num=*) gnum="${a#num=}" ;; esac
                done
                line=$(row "$MOCK_TIMELINE" "$gnum")
                g_as=$(printf '%s' "$line" | cut -f2)
                g_lb=$(printf '%s' "$line" | cut -f3)
                jq -n --arg me "${MOCK_LOGIN:-tester}" --arg a "$g_as" --arg l "$g_lb" '
                    { data: { repository: { issue: { timelineItems: { nodes:
                        ( (if $a == "" then [] else
                            [{__typename:"AssignedEvent", createdAt:$a, assignee:{login:$me}}] end)
                        + (if $l == "" then [] else
                            [{__typename:"LabeledEvent", createdAt:$l, label:{name:"in-progress"}}] end)
                        ) } } } } }' ;;
            *) echo "mock gh: unhandled api path: $path" >&2; exit 1 ;;
        esac ;;
    issue)
        sub="$1"; shift
        num="${1:-}"
        case "$sub" in
            view)
                if [ "${MOCK_FAIL_VIEW:-0}" = "1" ]; then
                    echo "gh: Could not resolve to an Issue (HTTP 404)" >&2
                    exit 1
                fi
                if [ "${MOCK_SHORT_VIEW:-0}" = "1" ]; then
                    # A TRUNCATED result: one line where the probe asked for
                    # three. Raw, bypassing jq, because the point is what the
                    # caller does with fewer fields than it requested.
                    printf 'tester\n'
                    exit 0
                fi
                line=$(row "$MOCK_ISSUES" "$num")
                [ -z "$line" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                a=$(printf '%s' "$line" | cut -f2)
                l=$(printf '%s' "$line" | cut -f3)
                st=$(printf '%s' "$line" | cut -f4)
                jq -n --arg a "$a" --arg l "$l" --arg s "$st" \
                    '{assignees: ($a | if . == "" then [] else split(",") end | map({login: .})),
                      labels:    ($l | if . == "" then [] else split(",") end | map({name: .})),
                      state:     $s}' \
                    | jq -r "${jq_expr:-.}" ;;
            edit|comment)
                # An arbitrary terminal error, so a failure that is NOT the
                # not-found edge can be exercised — including one that QUOTES a
                # removal token, which is what pins the phrase conjunct rather
                # than leaving the token match to carry the whole decision.
                if [ -n "${MOCK_EDIT_ERROR:-}" ]; then
                    echo "$MOCK_EDIT_ERROR" >&2
                    exit 1
                fi
                # $MOCK_MISSING_LABEL is the label this fixture treats as
                # absent from the REPO — the edge the tolerance was written for.
                # The label STORE still holds it, deliberately: `ensure_label`
                # has to find the taxonomy aligned, and what is modelled here is
                # gh's EDIT-TIME resolution failing, not a reconcile. gh errors
                # only for a label the invocation actually NAMES, so the mock
                # scans the argv it was handed rather than trusting the fixture
                # to say what the script passed. That is what stops a
                # tolerated-edge row certifying its own premise: an edit arm
                # that stopped passing the removal the row names injects no
                # failure at all, records a write, and is caught — where a knob
                # that errored unconditionally printed `ok` about a removal the
                # subcommand no longer performs.
                #
                # The wording is gh 2.98.0's, reproduced whole because BOTH
                # halves are load-bearing: it names one QUOTED label and says
                # nothing about which flag it came from (#288's whole question),
                # and it embeds the issue URL — which is why $MOCK_REPO's owner
                # contains `ready` inside `already`, so a match on the bare
                # token rather than the quoted one is caught here.
                if [ -n "${MOCK_MISSING_LABEL:-}" ]; then
                    prev_flag=""
                    for a in "$@"; do
                        case "$prev_flag" in
                            --add-label|--remove-label)
                                if [ "$a" = "$MOCK_MISSING_LABEL" ]; then
                                    echo "failed to update https://github.com/$MOCK_REPO/issues/$num: '$MOCK_MISSING_LABEL' not found" >&2
                                    exit 1
                                fi ;;
                        esac
                        prev_flag="$a"
                    done
                fi
                case "${MOCK_FAIL_EDIT:-0}" in
                    1)
                        echo "gh: HTTP 500 Internal Server Error" >&2
                        exit 1 ;;
                esac
                echo "issue $sub $*" >>"$MOCK_WRITES" ;;
            *) echo "mock gh: unhandled issue subcommand: $sub" >&2; exit 1 ;;
        esac ;;
    label)
        echo "label $*" >>"$MOCK_WRITES" ;;
    repo)
        echo "$MOCK_REPO" ;;
    *) echo "mock gh: unhandled command: $cmd" >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

# The owner is not decorative: gh's error embeds the issue URL, so an owner
# containing `ready` inside `already` is what makes the difference between the
# QUOTED token match the script ships and a bare-substring one observable here.
export MOCK_REPO="already/mock-repo"
export MOCK_ISSUES="$WORK/issues.tsv"
export MOCK_LABELS="$WORK/labels.tsv"
export MOCK_WRITES="$WORK/writes.log"
export MOCK_LOGIN="tester"

# Label store seeded FROM the emitter — never transcribed (issue #167).
: >"$MOCK_LABELS"
while IFS='|' read -r l_name l_color l_desc; do
    [ -z "$l_name" ] && continue
    printf '%s\t%s\t%s\n' "$l_name" "$l_color" "$l_desc" >>"$MOCK_LABELS"
done < <(bash "$CLAIM" taxonomy)
if [ "$(wc -l <"$MOCK_LABELS" | tr -d ' ')" -ge 4 ]; then
    ok "label store seeded from the taxonomy emitter (no colour transcribed here)"
else
    bad "the taxonomy emitter produced fewer than 4 rows — the mock would report every label absent"
fi

# The issue store. `tester` is MOCK_LOGIN, i.e. @me.
#   10  residue: @me, no in-progress, OPEN      -> the ONLY clearable shape
#   11  a human took it                          -> live claim
#   12  @me WITH in-progress                     -> live in-flight claim
#   13  unassigned, NO labels                    -> the ordinary promote
#   14  @me AND a human                          -> NOT residue (section 3e)
#   15  unassigned WITH labels                   -> the ordinary promote, and
#                                                   the shape the pre-fix TSV
#                                                   split mis-reads (section 4)
#   16  @me, no in-progress, but CLOSED          -> the who-shipped-it record
INPROG="in-progress"
READY="ready"
BLOCKED="blocked"
{
    printf '10\ttester\t\tOPEN\n'
    printf '11\tsomeone-else\t\tOPEN\n'
    printf '12\ttester\t%s\tOPEN\n' "$INPROG"
    printf '13\t\t\tOPEN\n'
    printf '14\ttester,someone-else\t\tOPEN\n'
    printf '15\t\tbug,sev:high\tOPEN\n'
    printf '16\ttester\t\tCLOSED\n'
    printf '17\ttester\t\tOPEN\n'
    printf '18\ttester\t\tOPEN\n'
} >"$MOCK_ISSUES"

# The claim-cycle timeline (#287). Every shape above that is assigned to @me
# needs a row, because the fourth conjunct reads it before clearing anything.
#
# The DEFAULT pair mirrors what was MEASURED on a real claim: `claim` writes the
# label and the assignee in ONE `gh issue edit`, and they do NOT share a
# timestamp — the label lands one second BEFORE the assignment. A fixture with
# identical timestamps would let a `>=` rule pass that real residue defeats, so
# the ordering is part of the fixture rather than an incidental detail.
#
#   17  @me, assigned LONG AFTER the last claim cycle -> self-assignment
#   18  @me, never claimed at all (no label event)     -> self-assignment
export MOCK_TIMELINE="$WORK/timeline.tsv"
{
    printf '10\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n'
    # 11 carries a PAST @me claim cycle even though a human holds it now — @me
    # claimed it, released, and someone took it. Without this row the FOURTH
    # conjunct is what stops the clear rather than the arm under test, and M1
    # and M6 report `UNDETECTED` for a reason unrelated to what they mutate.
    # Measured: they did exactly that until this row existed.
    printf '11\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n' 
    printf '12\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n'
    printf '14\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n'
    printf '16\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n'
    printf '17\t2026-08-30T18:00:00Z\t2026-08-30T14:38:41Z\n'
    printf '18\t2026-08-30T18:00:00Z\t\n'
} >"$MOCK_TIMELINE"

# --- helpers -----------------------------------------------------------------
# OUT/ERR/RC hold the last run; EDITS holds only the `issue edit` lines it wrote.
run_claim_script() {  # $1=script, rest=args
    local script="$1"; shift
    : >"$MOCK_WRITES"
    OUT=$(PATH="$WORK/bin:$PATH" bash "$script" "$@" --repo "$MOCK_REPO" 2>"$WORK/err.txt")
    RC=$?
    ERR=$(cat "$WORK/err.txt")
    EDITS=$(grep '^issue edit' "$MOCK_WRITES" 2>/dev/null)
    return 0
}
run_claim() { run_claim_script "$CLAIM" "$@"; }

# Slurped rather than piped into `head`: a `jq | head -1` under pipefail is the
# #256 shape, and the first emitted object is what every single-issue case wants.
detail_of() { printf '%s' "$OUT" | jq -r -s '.[0].detail // ""'; }
result_of() { printf '%s' "$OUT" | jq -r -s '.[0].result // ""'; }
n_edits()   { printf '%s' "$EDITS" | grep -c '^issue edit' 2>/dev/null || true; }
edit_for()  { printf '%s' "$EDITS" | grep "^issue edit $1 " 2>/dev/null || true; }
# Per-issue, for the batch case: `.[0]` reads the FIRST issue's verdict, which is
# exactly the one a leak into the SECOND issue hides behind.
detail_for() { printf '%s' "$OUT" | jq -r -s --argjson n "$1" '[.[] | select(.issue == $n) | .detail] | first // ""'; }

# Did this run write a `--remove-assignee` at all? The one question every case
# below turns on.
cleared() { case "$EDITS" in *"--remove-assignee"*) return 0 ;; *) return 1 ;; esac; }
has()     { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# --- 1. vacuity: the mock is actually reached --------------------------------
# A mock that is never consulted answers every question the same way a correct
# script does, so this runs first and everything after it is read in its light.
run_claim promote 13
if [ "$RC" -eq 0 ] && [ "$(result_of)" = "ok" ] && [ "$(n_edits)" = "1" ]; then
    ok "the mock is on PATH and promote reaches it (one recorded edit, result=ok)"
else
    bad "promote against the mock did not produce one edit: rc=$RC result=$(result_of) edits=$(n_edits)"
fi

# --- 2. THE PREMISE: claim writes both halves in ONE edit --------------------
# "residue by construction" is an argument about `claim`, not about `promote`.
# Every case in section 3 stays green if `claim` stops pairing the two halves,
# and the discriminator silently becomes a guess. So the pairing is pinned here,
# on its own, and a failure in this section invalidates the rest of the file
# rather than merely reporting a second defect.
run_claim claim 13
if cleared; then
    bad "claim wrote a --remove-assignee — claim is a claim, not a release"
elif ! has "$EDITS" "--add-assignee @me"; then
    bad "claim no longer writes --add-assignee @me: $EDITS"
elif ! has "$EDITS" "--add-label $INPROG"; then
    bad "claim no longer writes --add-label $INPROG: $EDITS"
elif [ "$(n_edits)" != "1" ]; then
    bad "claim wrote $(n_edits) edits — the two halves must land together, or the promote discriminator is a guess"
else
    ok "PREMISE: claim writes assignee @me AND $INPROG in ONE edit (what makes the discriminator sound)"
fi

# --- 3. the acceptance shapes ------------------------------------------------
# (a) @me, no in-progress, OPEN -> the residue shape. Cleared, and SAID.
run_claim promote 10
if ! cleared; then
    bad "(a) residue not cleared: edits=$EDITS"
elif [ "$(n_edits)" != "1" ]; then
    bad "(a) the clear did not ride in the promote edit — $(n_edits) edits written"
elif ! has "$EDITS" "--add-label ready"; then
    bad "(a) the promote edit lost its --add-label ready: $EDITS"
elif ! has "$(detail_of)" "cleared claim residue"; then
    bad "(a) the assignee was cleared without saying so in the JSON detail: '$(detail_of)'"
elif ! has "$ERR" "claim residue"; then
    bad "(a) nothing on stderr said a claim residue was cleared"
else
    ok "(a) @me with no $INPROG on an OPEN issue: cleared in the SAME edit as ready, reported on stdout and stderr"
fi

# (b) a different assignee -> a human took it. Left alone, and REPORTED.
run_claim promote 11
if cleared; then
    bad "(b) promote cleared a HUMAN's assignee — the one outcome the gate exists to prevent: $EDITS"
elif [ "$(result_of)" != "ok" ]; then
    bad "(b) promote did not complete on a human-assigned issue: result=$(result_of)"
elif ! has "$(detail_of)" "someone-else"; then
    bad "(b) the retained assignee was not named in the detail: '$(detail_of)'"
elif ! has "$ERR" "left alone"; then
    bad "(b) nothing on stderr reported the retained assignee"
else
    ok "(b) a different assignee is left alone and REPORTED, never cleared"
fi

# (c) @me WITH in-progress -> real in-flight work.
run_claim promote 12
if cleared; then
    bad "(c) promote cleared a LIVE claim (@me + $INPROG): $EDITS"
elif ! has "$(detail_of)" "$INPROG"; then
    bad "(c) the live claim was left alone but the reason did not name $INPROG: '$(detail_of)'"
else
    ok "(c) @me WITH $INPROG is a live claim: left alone and reported"
fi

# (d) unassigned -> the ordinary promote, unchanged.
run_claim promote 13
if cleared; then
    bad "(d) promote wrote a --remove-assignee on an UNASSIGNED issue: $EDITS"
elif [ -n "$(detail_of)" ]; then
    bad "(d) an unassigned promote grew a detail ('$(detail_of)') — the ordinary path must stay quiet"
elif ! has "$EDITS" "--add-label ready"; then
    bad "(d) the unassigned promote lost its --add-label ready: $EDITS"
else
    ok "(d) an unassigned promote is unchanged: adds ready, clears nothing, says nothing"
fi

# (e) @me AND a human is NOT residue. The discriminator is an EQUALITY against
# @me, deliberately not the substring idiom claim's double-pick guard uses
# (`,$assignees,` == *",$ME,"*). Aligning the two reads like an obvious tidy and
# is wrong here: a human who added themselves alongside the loop is a human
# involved in the issue. Mutation M2 below is exactly that tidy.
run_claim promote 14
if cleared; then
    bad "(e) promote cleared an assignee on an issue a human ALSO holds: $EDITS"
elif [ -z "$(detail_of)" ]; then
    bad "(e) the mixed-assignee issue was left alone silently"
else
    ok "(e) @me alongside a human is not residue: left alone and reported"
fi

# (f) CLOSED -> the who-shipped-it record, which is the entire reason `release`
# is not symmetric. Refused in the gate's own body rather than trusted to the
# caller, the shape align-labels.sh's delete gate established.
run_claim promote 16
if cleared; then
    bad "(f) promote stripped the who-shipped-it record from a CLOSED issue: $EDITS"
elif ! has "$(detail_of)" "CLOSED"; then
    bad "(f) the closed issue was left alone but the reason did not say why: '$(detail_of)'"
else
    ok "(f) a CLOSED issue keeps its assignee: the who-shipped-it record survives promote"
fi

# --- 3b. the operator's OWN self-assignment (issue #287) ---------------------
# `@me` is the operator's personal login, not a loop identity, so the three
# conjuncts above are true of loop residue AND of an issue the human running the
# loop assigned to themselves. The discriminator is whether `in-progress` was
# ever LABELLED at that assignment, since `claim` writes both halves together.

# (r1) assigned LONG AFTER the last claim cycle ended -> a fresh human act.
run_claim promote 17
if cleared; then
    bad "(r1) promote stripped a self-assignment made after the last claim cycle: $EDITS"
elif [ "$(result_of)" != "ok" ]; then
    bad "(r1) promote did not complete: result=$(result_of)"
elif ! has "$ERR" "self-assignment"; then
    bad "(r1) nothing on stderr called it a self-assignment: $ERR"
else
    ok "(r1) an assignment made after the last cycle is left alone and REPORTED"
fi

# (r2) never claimed at all — no in-progress LabeledEvent anywhere.
run_claim promote 18
if cleared; then
    bad "(r2) promote stripped an assignee on an issue that was never claimed: $EDITS"
elif ! has "$ERR" "self-assignment"; then
    bad "(r2) nothing on stderr called it a self-assignment: $ERR"
else
    ok "(r2) an issue that was never claimed keeps its assignee"
fi

# (r3) THE CONTROL. Without it (g) and (h) pass on a gate that clears nothing at
# all, which is the same green a broken timeline probe produces.
run_claim promote 10
if cleared; then
    ok "(r3) and genuine residue STILL clears, so the conjunct discriminates rather than just refusing"
else
    bad "(r3) the claim-cycle conjunct blocked genuine residue too — it refuses everything: $EDITS"
fi

# (r4) THE claim -> block -> promote PATH, decided explicitly (#287 acceptance 3).
# `block` strips both labels and leaves the assignee, so this residue has no
# close and no reopen anywhere in its history — a reopen-evidence conjunct would
# miss it entirely. The in-progress LabeledEvent from the original claim is
# still there, so it CLEARS, and that is the decision rather than a side effect.
printf '19\ttester\t%s\tOPEN\n' "$BLOCKED" >>"$MOCK_ISSUES"
printf '19\t2026-08-30T14:38:42Z\t2026-08-30T14:38:41Z\n' >>"$MOCK_TIMELINE"
run_claim promote 19
if cleared; then
    ok "(r4) claim -> block -> promote residue clears: no close, no reopen, but the claim cycle is in the timeline"
else
    bad "(r4) the block path's residue was not cleared, and #287 requires that path to be decided: $EDITS"
fi

# --- 4. the probe's transport ------------------------------------------------
# An unassigned issue that CARRIES LABELS is the ordinary groom-backlog
# promotion, and it is the shape a TSV-through-`read` probe mis-reads.
run_claim promote 15
if cleared; then
    bad "(g) promote cleared an assignee on an unassigned labelled issue: $EDITS"
elif [ -n "$(detail_of)" ]; then
    bad "(g) an unassigned LABELLED issue reported an assignee ('$(detail_of)') — the probe desynced its fields"
elif ! has "$EDITS" "--add-label ready"; then
    bad "(g) the promote edit is missing --add-label ready: $EDITS"
else
    ok "(g) an unassigned issue WITH labels reads as unassigned (the field-desync shape)"
fi

# Fixture adequacy, measured rather than asserted — gate 11's posture, and #263's
# lesson that the load-bearing question is whether the fixture can EXPOSE the
# bug. The pre-fix idiom is transcribed verbatim and run against the exact three
# shapes the mock emits. If it ever stops desyncing, case (g) has gone vacuous.
# THREE fields, because the shipped probe emits three. Both readers are driven
# from $MOCK_ISSUES itself rather than from hand-written literals: a proof that
# quotes a shape the fixture no longer has is a proof of nothing, and the
# fixture is the thing under test here.
prefix_read() {  # $1=TAB-joined probe result
    local a l st
    IFS=$'\t' read -r a l st <<<"$1"
    printf '%s|%s|%s' "${a:-}" "${l:-}" "${st:-}"
}
line_read() {    # the shipped transport: one value per LINE, read with IFS=
    local a l st
    { IFS= read -r a; IFS= read -r l; IFS= read -r st; } <<<"$1"
    printf '%s|%s|%s' "${a:-}" "${l:-}" "${st:-}"
}
fixture_fields() {  # $1=issue number -> assignees<TAB>labels<TAB>state
    awk -F'\t' -v k="$1" '$1 == k { printf "%s\t%s\t%s", $2, $3, $4; exit }' "$MOCK_ISSUES"
}
# Quoted through variables throughout: an unquoted $'\t...' argument is split on
# the very IFS whitespace this probe is about, which would hand both readers a
# pre-trimmed string and make them agree.
adequacy_fail=0
for probe_issue in 15 13; do
    tsv_shape=$(fixture_fields "$probe_issue")
    if [ -z "$tsv_shape" ]; then
        bad "fixture #$probe_issue is missing from the issue store — the adequacy proof has nothing to run on"
        adequacy_fail=1
        continue
    fi
    line_shape=$(printf '%s' "$tsv_shape" | tr '\t' '\n')
    correct="$(printf '%s' "$tsv_shape" | tr '\t' '|')"
    prefix_out=$(prefix_read "$tsv_shape")
    line_out=$(line_read "$line_shape")
    if [ "$line_out" != "$correct" ]; then
        bad "the shipped line transport mis-read fixture #$probe_issue: got '$line_out', want '$correct'"
        adequacy_fail=1
    elif [ "$prefix_out" = "$correct" ]; then
        bad "the pre-fix TSV idiom no longer desyncs fixture #$probe_issue — case (g) proves nothing and the fixture has gone vacuous"
        adequacy_fail=1
    fi
done
if [ "$adequacy_fail" = "0" ]; then
    # BOTH unassigned fixtures desync, and that is the corrected finding: with
    # `state` as a third field the broken idiom shifts EVERY unassigned shape,
    # not just the labelled one. It was invisible in the two-field draft this
    # replaced, where an unassigned issue with NO labels was the one shape it
    # read correctly — which is exactly how that draft's fixture missed it.
    ok "FIXTURE ADEQUACY: the pre-fix TSV idiom desyncs both unassigned fixtures (#15 and #13); the shipped line transport reads both correctly"
fi

# --- 5. release stays asymmetric (the rejected alternative) ------------------
# "Make release symmetric" is the simplest fix and the one #281 rejects: it
# destroys the who-shipped-it record on every closed issue. Nothing but this
# assertion stands between that record and a tidying editor.
run_claim release 10
if cleared; then
    bad "release now clears the assignee — the rejected fix (#281): it destroys the who-shipped-it record on every closed issue"
elif ! has "$EDITS" "--remove-label $INPROG"; then
    bad "release no longer removes $INPROG: $EDITS"
else
    ok "release still clears the LABEL only — the who-shipped-it record survives"
fi

# --- 6. degradation: unknown is not verified ---------------------------------
# Both of these could plausibly be read as "promote asserts unclaimed, so clear
# it". They are not: an unresolvable login and an unreadable issue are UNKNOWN,
# and the same rule align-labels.sh applies to a delete applies here.
MOCK_LOGIN="" run_claim promote 10
if cleared; then
    bad "promote cleared an assignee it could not compare against @me (login unresolved)"
elif ! has "$(detail_of)" "own login unresolved"; then
    # Discriminating, like (b)/(c)/(f): a bare non-empty detail is satisfied by
    # ANY other arm's reason, so neutering this arm would leave the case green
    # while the run reported the wrong cause.
    bad "an unresolved login was left alone for the wrong stated reason: '$(detail_of)'"
else
    ok "an unresolved own-login clears nothing and reports why"
fi

# A probe that returns FEWER fields than asked for is unknown, not empty. The
# state arm is the actual backstop (a short read leaves state="" which is not
# OPEN), so the guard's value is an accurate message rather than the refusal —
# but an inaccurate message about a write path is how the next reader is misled.
MOCK_SHORT_VIEW=1 run_claim promote 10
if cleared; then
    bad "promote cleared an assignee on a truncated probe result"
elif ! has "$(detail_of)" "malformed"; then
    bad "a short probe read was not reported as malformed: '$(detail_of)'"
else
    ok "a short probe read is reported as malformed and clears nothing"
fi

MOCK_FAIL_VIEW=1 run_claim promote 10
if cleared; then
    bad "promote cleared an assignee it never read"
elif [ -z "$(detail_of)" ]; then
    bad "an unreadable issue left the assignee in place SILENTLY"
elif [ "$(result_of)" != "ok" ]; then
    bad "an unreadable assignee probe broke the promote itself: result=$(result_of)"
else
    ok "an unreadable probe clears nothing, reports why, and still promotes"
fi

# --- 7. a clear is never reported before the write that carries it -----------
# The decision is made before the edit runs, so a past tense composed at
# decision time describes a write that has not been attempted — and survives one
# that failed. The `not found` tolerance made that worse than cosmetic: written
# for --remove-label, which promote does not carry, it turned a completely
# failed edit into `result:"ok"` plus "cleared claim residue" with zero writes.
MOCK_MISSING_LABEL=$READY run_claim promote 10
if [ "$(result_of)" = "ok" ]; then
    bad "a promote whose edit wrote NOTHING reported ok — the not-found tolerance is not scoped to --remove-label"
elif has "$(detail_of)" "cleared claim residue"; then
    bad "a failed promote still claimed the residue was cleared: '$(detail_of)'"
elif [ "$(result_of)" != "failed" ]; then
    bad "a failed promote edit did not report failed: result=$(result_of)"
else
    ok "a promote edit that did not apply reports failed and never claims a clear"
fi

MOCK_FAIL_EDIT=1 run_claim promote 10
if [ "$(result_of)" != "failed" ]; then
    # The control: without it, a run that never reached the edit at all passes
    # this case exactly like one that reached it and stayed quiet.
    bad "the hard-failed-edit case did not reach a failed promote (result=$(result_of)) — it proves nothing"
elif has "$ERR" "cleared claim residue"; then
    bad "stderr asserted the clear on a promote whose edit failed outright"
else
    ok "a hard-failed promote edit reports failed and never announces a clear on stderr"
fi

# --- 7b. the tolerance is scoped to the REMOVAL's own token (issue #288) -----
# #281 scoped the tolerance to the subcommands that carry a `--remove-label`,
# which fixed `promote` and left the other half standing: gh's error names one
# label and says nothing about which FLAG it came from, so `claim` and `block` —
# which carry an `--add-label` too — went on swallowing a wholly-failed edit
# whose failing operation was the ADD. `ensure_label` runs `|| true`, so on a
# repo where label creation fails the whole edit fails, nothing is assigned,
# `in-progress` is never added, `ready` is never stripped — and the run reported
# `ok`, so the loop believed the claim landed and dispatch-ready handed the same
# issue to a second cold agent on its next tick.
MOCK_MISSING_LABEL=$INPROG run_claim claim 13
if [ "$(result_of)" = "ok" ]; then
    bad "a claim whose --add-label $INPROG failed reported ok — nothing was assigned and nothing was labelled, so the loop dispatches this issue twice (#288)"
elif [ "$(result_of)" != "failed" ]; then
    bad "a claim whose add half failed did not report failed: result=$(result_of)"
elif [ "$RC" -ne 2 ]; then
    bad "a wholly-failed claim exited $RC, not 2 — a hard failure must reach the caller's exit code too"
else
    ok "a claim whose --add-label $INPROG failed reports failed and exits 2 (#288)"
fi

# `block`'s add half is a different label from `claim`'s, and its removals are
# the only pair in the table — proving one subcommand's add is not proving the
# other's, since the discriminator is per-subcommand DATA.
MOCK_MISSING_LABEL=$BLOCKED run_claim block 13 --comment "why"
if [ "$(result_of)" != "failed" ]; then
    bad "a block whose --add-label $BLOCKED failed reported $(result_of) — the label the subcommand exists to add never landed, and nothing said so"
elif [ "$RC" -ne 2 ]; then
    bad "a wholly-failed block exited $RC, not 2 — a hard failure must reach the caller's exit code too"
else
    ok "a block whose --add-label $BLOCKED failed reports failed and exits 2 (#288)"
fi

# The tolerance was SCOPED, not deleted. `--remove-label` of a label the repo
# does not carry is gh's one non-idempotent edge, and every subcommand that
# carries a removal still depends on it — a fix that quietly removed it would
# turn each such no-op into a hard failure, and nothing else here would notice.
# One row per subcommand, and `block` twice because it is the only one with TWO
# removals: a list that dropped its second token would still pass a single-token
# case. Each row names the label gh's error would carry.
#   label <TAB> args <TAB> the removal gh names
TOLERATED_EDGES=(
"claim	claim 13	$READY"
"release	release 10	$INPROG"
"block ($READY)	block 13 --comment why	$READY"
"block ($INPROG)	block 13 --comment why	$INPROG"
"demote	demote 10 --comment why	$READY"
)
for row in "${TOLERATED_EDGES[@]}"; do
    IFS=$'\t' read -r t_label t_args t_token <<<"$row"
    # shellcheck disable=SC2086
    MOCK_MISSING_LABEL="$t_token" run_claim $t_args
    # THE KNOB MUST HAVE FIRED. A failed edit records nothing, so a recorded
    # `issue edit` means the mock saw no missing label in the argv — the row's
    # subcommand no longer passes the removal this row names, and `ok` below
    # would be the ordinary path's verdict rather than the tolerance's. It is
    # the same control the short-read mutant uses, and it is what stops the
    # duplicated removal list being policed in one direction only.
    if [ -n "$EDITS" ]; then
        bad "$t_label recorded an edit ($EDITS) — the invocation never named '$t_token', so no tolerance was exercised and this row proves nothing"
    elif [ "$(result_of)" != "ok" ]; then
        bad "$t_label lost the 'not found' tolerance for its OWN removal '$t_token': result=$(result_of) — the scoping deleted the edge instead of narrowing it"
    elif [ "$RC" -ne 0 ]; then
        bad "$t_label tolerated '$t_token' not found but still exited $RC"
    elif ! has "$(detail_of)" "$t_token"; then
        bad "$t_label tolerated '$t_token' but its detail was '$(detail_of)' — an ok that names nothing is indistinguishable from one that wrote something"
    elif ! has "$ERR" "tolerated"; then
        bad "$t_label swallowed '$t_token' with nothing on stderr saying so"
    else
        ok "$t_label still tolerates '$t_token' not found — its own removal, the edge the tolerance was written for"
    fi
done

# FIXTURE ADEQUACY for the QUOTED match — measured, not argued, the posture
# #263 established and this file already uses for the TSV transport at section
# 4. The shipped tolerance matches `'<token>'` rather than the bare token only
# because gh's message embeds the issue URL, and the fixture can only expose a
# relaxation while the pre-fix predicate ANSWERS DIFFERENTLY from the shipped
# one on that message. $MOCK_REPO's `already` owner is the entire reason it
# does; a neutral owner makes every case here pass with the quoting removed,
# and reads like a spelling choice one tidy away.
adequacy_err="failed to update https://github.com/$MOCK_REPO/issues/13: '$INPROG' not found"
if [ "${adequacy_err#*"'$READY'"}" != "$adequacy_err" ]; then
    bad "the QUOTED predicate matched '$READY' in an error naming only $INPROG — the shipped match is not the one this file claims"
elif [ "${adequacy_err#*"$READY"}" = "$adequacy_err" ]; then
    bad "the bare-substring predicate does not match '$READY' in the mock's error at all, so relaxing the quoting would be invisible here: MOCK_REPO ('$MOCK_REPO') no longer carries it"
else
    ok "FIXTURE ADEQUACY: the mock's message separates the two predicates — '$READY' appears in it, and never quoted"
fi

# The tolerance is an EDGE, not a blanket: a failure that is not the not-found
# edge at all must still be a hard failure for a subcommand whose only operation
# is the removal. `release` and `demote` appear nowhere else except the tolerated
# path, so without this the gate asserts their tolerance and never its absence —
# and a swallowed `release` leaves `in-progress` set, so the issue reads in-flight
# forever.
MOCK_FAIL_EDIT=1 run_claim release 10
if [ "$(result_of)" != "failed" ]; then
    bad "release tolerated a failure that was not the not-found edge: result=$(result_of)"
else
    ok "release reports failed on an error that is not the not-found edge"
fi

# And the not-found PHRASE is a conjunct in its own right: an error that quotes
# the subcommand's removal token but is not that edge must NOT be tolerated.
# Without this the token match carries the whole decision and the phrase test
# could be widened to anything with nothing noticing.
MOCK_EDIT_ERROR="failed to update https://github.com/$MOCK_REPO/issues/10: HTTP 500 while removing '$INPROG'" run_claim release 10
if [ "$(result_of)" != "failed" ]; then
    bad "release tolerated an error QUOTING its own removal that was not a not-found: result=$(result_of) — the phrase conjunct is doing nothing"
else
    ok "an error quoting the removal token WITHOUT the not-found phrase is not tolerated"
fi

# --- 8. --dry-run previews the decision instead of hiding it -----------------
run_claim promote 10 --dry-run
if [ -s "$MOCK_WRITES" ]; then
    bad "--dry-run wrote: $(tr '\n' '; ' <"$MOCK_WRITES")"
elif [ "$(result_of)" != "would-promote" ]; then
    bad "--dry-run did not report would-promote: result=$(result_of)"
elif ! has "$(detail_of)" "would clear"; then
    bad "--dry-run hid the assignee decision: '$(detail_of)'"
elif has "$(detail_of)" "cleared claim residue"; then
    bad "--dry-run reported a completed clear it did not perform: '$(detail_of)'"
else
    ok "--dry-run writes nothing and previews the clear as 'would clear'"
fi

# --- 9. the batch form, and --force ------------------------------------------
# `groom-backlog` ships `issue-claim.sh promote N1 N2`, so a verdict leaking
# from one issue into the next one's EDIT is a live shape, not a hypothetical.
# The pair is 10 then 13 — residue, then UNASSIGNED — and the second number is
# load-bearing. A verdict is two things, RESIDUE_ARGS and RESIDUE_NOTE, and both
# are reset in one place. Pairing 10 with an ASSIGNED issue (#11) can only see
# the first: #11's gate runs to one of the left-alone arms and re-sets the note
# on every path, so a lost `RESIDUE_NOTE=""` is masked. #13 returns at the
# unassigned early-out, which is the one path that sets no note at all — so it
# carries #10's note forward and the JSON reports a clear on an issue whose only
# edit was `--add-label ready`. That record is what a coordinator reads.
run_claim promote 10 13
if has "$(edit_for 13)" "--remove-assignee"; then
    bad "BATCH LEAK (args): #10's residue verdict reached #13's edit: $(edit_for 13)"
elif has "$(detail_for 13)" "cleared claim residue"; then
    bad "BATCH LEAK (note): #13 reported '$(detail_for 13)' but its only edit was $(edit_for 13) — a confident record of a write that never happened"
elif ! has "$(edit_for 10)" "--remove-assignee"; then
    bad "batch promote lost #10's clear: $(edit_for 10)"
elif ! has "$(detail_for 10)" "cleared claim residue"; then
    bad "batch promote lost #10's report: '$(detail_for 10)'"
elif [ "$(n_edits)" != "2" ]; then
    bad "batch promote wrote $(n_edits) edits for 2 issues"
else
    ok "batch promote 10 13: both halves of the verdict stay with #10 — #13's edit and its REPORT are untouched"
fi

# --force is claim's double-pick override. Widening it to promote would hand the
# loop a way to unassign a human — the one outcome the gate exists to prevent.
run_claim promote 11 --force
if cleared; then
    bad "--force widened the residue gate and stripped a HUMAN's assignee: $EDITS"
elif ! has "$EDITS" "--add-label ready"; then
    # The positive control: without it, a --force that was REJECTED before ever
    # reaching the gate (exit 64, nothing written) passes this case identically.
    bad "--force promote wrote no ready label — it failed before reaching the gate, so this case proves nothing: rc=$RC"
else
    ok "--force does not widen the residue gate: the promote lands and a human's assignee survives it"
fi

# The same, against the state arm: --force must not reach the who-shipped-it
# record either. One arm proved is not the flag proved.
run_claim promote 16 --force
if cleared; then
    bad "--force stripped the who-shipped-it record off CLOSED #16: $EDITS"
elif ! has "$EDITS" "--add-label ready"; then
    bad "--force promote on #16 wrote no ready label — it failed before reaching the gate, so this case proves nothing: rc=$RC"
else
    ok "--force does not reach the state arm either: a CLOSED issue keeps its assignee"
fi

# --- 10. the docs say what the script does -----------------------------------
# The ONE source-level check in this file, and it reads SKILL.md rather than the
# guard: a subcommand that now performs an assignee write must say so where a
# caller reads before invoking it (the #220 class). The window is cut at the
# `promote` bullet, because the file mentions "claim-residue" elsewhere and a
# whole-file grep would be satisfied by that alone.
skill_flat=$(tr '\n' ' ' <"$SKILL" | tr -s ' ')
promote_tail="${skill_flat#*- \`promote\` — }"
promote_bullet="${promote_tail%%- \`block\`*}"
# BOTH ends are proved, because each fails the same silent way: an unmatched
# prefix returns the whole file, and an unmatched SUFFIX returns the whole tail
# — a window running to EOF, where "residue" is satisfied by the bundled-scripts
# row far below and this check degrades into the whole-file grep the header
# forbids. The old size guard could never fire: the prefix strip always shortens
# when it matches, so `-ge` was unreachable and the suffix was guarded by
# nothing. The overrun arm is the `window_is_bounded` shape from
# test-sentry-verification.sh: every bullet in that list opens with "- `", so a
# window holding one has swallowed the next bullet.
if [ "$promote_tail" = "$skill_flat" ]; then
    bad "SKILL.md's \`promote\` bullet did not resolve — this check would cover the whole file instead"
elif [ "$promote_bullet" = "$promote_tail" ]; then
    bad "SKILL.md's \`promote\` window found no \`block\` stop marker — it runs to EOF, so it is no longer scoped to the bullet"
elif has "$promote_bullet" "- \`"; then
    bad "SKILL.md's \`promote\` window overran into the next bullet: '${promote_bullet}'"
elif ! has "$promote_bullet" "residue"; then
    bad "SKILL.md's promote bullet does not mention the claim residue it now clears (issue #281)"
elif ! has "$promote_bullet" "left alone"; then
    bad "SKILL.md's promote bullet documents the clear without documenting that every other shape is left alone"
elif ! has "$promote_bullet" "OPEN"; then
    bad "SKILL.md's promote bullet states the residue shape without the OPEN conjunct the code enforces — read alone it says promote strips the who-shipped-it record off a CLOSED issue, which is the rejected #281 alternative arrived at from the docs"
elif has "$promote_bullet" "cannot have come from anywhere else"; then
    bad "SKILL.md's promote bullet still asserts the absolute the code itself calls false (#287): true of any OTHER account, false of the operator's own"
else
    ok "SKILL.md's promote bullet states all three conjuncts, both halves, and no absolute the code contradicts"
fi

# --- 11. mutation proofs ------------------------------------------------------
# Each mutant neuters ONE decision and is proved by the WRITE it causes, never by
# a literal an assertion greps for. The mirror tree keeps the layout faithful so
# the mutant resolves pr-shepherd's gh-retry.sh exactly as the shipped script
# does. The inventory is this array: the run prints its length and asserts every
# member ran, so no transcribed count can go stale (#276).
MIRROR="$WORK/tree/skills/github-issues/scripts"
mkdir -p "$MIRROR" "$WORK/tree/skills/pr-shepherd/scripts"
cp "$RETRY" "$WORK/tree/skills/pr-shepherd/scripts/gh-retry.sh"
MUTANT="$MIRROR/issue-claim.sh"

apply_mutation() {  # $1=label $2=exact source line $3=replacement line
    local label="$1" from="$2" to="$3" rc=0
    # Whole-line EQUALITY, and awk fails unless it matched exactly once. `cmp -s`
    # alone cannot carry this: it exits 2 on a missing file, which an `if` reads
    # as "differs", so a mutation that matched nothing would report as applied
    # and every negative assertion after it would pass against a file that was
    # never run (the #262 lesson).
    awk -v from="$from" -v to="$to" '
        BEGIN { n = 0 }
        $0 == from { print to; n++; next }
        { print }
        END { if (n != 1) exit 3 }
    ' "$CLAIM" >"$MUTANT" || rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$label — the target line did not match exactly once (awk rc=$rc); the mutation is stale"
        return 1
    fi
    if [ ! -s "$MUTANT" ]; then
        bad "$label — the mutant is empty"
        return 1
    fi
    if cmp -s "$CLAIM" "$MUTANT"; then
        bad "$label — the mutation changed nothing, the proof would be vacuous"
        return 1
    fi
    return 0
}

# The mutant must still RUN, or "it did not clear" is meaningless.
mutant_ran() {  # $1=label
    case "$(result_of)" in
        ok|would-promote|failed) return 0 ;;
    esac
    bad "$1 — the mutant did not complete (result='$(result_of)' rc=$RC), so its verdict proves nothing"
    return 1
}

# Each row: label <TAB> from-line <TAB> to-line <TAB> env <TAB> args <TAB> expect
#   expect=cleared     — the mutation must cause a --remove-assignee
#   expect=false-clear — the mutation must cause a "cleared" claim with no write
MUTANTS=(
"M1 different-assignee arm	    if [[ \"\$assignees\" != \"\$ME\" ]]; then	    if false; then	-	promote 11	cleared	without the different-assignee arm, promote strips a HUMAN's assignee"
"M2 equality relaxed to claim's substring idiom	    if [[ \"\$assignees\" != \"\$ME\" ]]; then	    if [[ \",\$assignees,\" != *\",\$ME,\"* ]]; then	-	promote 14	cleared	the substring idiom clears on an issue a human ALSO holds"
"M3 in-progress arm	    if [[ \",\$labels,\" == *\",\$INPROG_LABEL,\"* ]]; then	    if false; then	-	promote 12	cleared	without the in-progress arm, promote strips a LIVE in-flight claim"
"M4 closed-state arm	    if [[ \"\$state\" != \"OPEN\" ]]; then	    if false; then	-	promote 16	cleared	without the state arm, promote strips the who-shipped-it record off a CLOSED issue"
"M5 unreadable probe clears anyway	        RESIDUE_NOTE=\"assignee unchecked: could not read #\$n\"	        RESIDUE_ARGS=(--remove-assignee \"@me\")	MOCK_FAIL_VIEW=1	promote 11	cleared	treating an unreadable probe as residue strips a HUMAN's assignee, never read"
"M6 --force widens the gate	    if [[ \"\$assignees\" != \"\$ME\" ]]; then	    if [[ \"\$assignees\" != \"\$ME\" && \"\$FORCE\" == \"0\" ]]; then	-	promote 11 --force	cleared	--force widened to promote strips a HUMAN's assignee"
"M7 the gate stops resetting its verdict	    RESIDUE_ARGS=()	    :	-	promote 10 13	cleared-13	one issue's ARGS leak into the next one's edit in a batch"
"M9 short-read guard	    if [[ \"\$read_ok\" != \"1\" ]]; then	    if false; then	MOCK_SHORT_VIEW=1	promote 10	state-arm	a truncated probe result is reported as the state arm's verdict instead of malformed"
"M10 the gate stops resetting its reported verdict	    RESIDUE_NOTE=\"\"	    :	-	promote 10 13	false-detail-13	one issue's REPORT leaks into the next one's JSON, claiming a write that never happened"
"M8 not-found tolerance re-widened to promote	    promote) REMOVALS=() ;;	    promote) REMOVALS=(\"\$READY_LABEL\") ;;	MOCK_MISSING_LABEL=$READY	promote 10	false-clear	a promote that wrote nothing reports ok and claims the residue was cleared"
"M12 the claim-cycle conjunct is neutered	    case \"\$cycle\" in	    case \"residue\" in	-	promote 18	cleared	without the claim-cycle conjunct, promote strips the OPERATOR's own self-assignment and a cold agent is dispatched onto work a human is already doing"
"M11 removal-token match re-widened to the bare error string	                    if [[ \"\$err\" == *\"'\$rl'\"* ]]; then	                    if true; then	MOCK_MISSING_LABEL=$INPROG	claim 13	false-ok	a claim whose ADD half failed reports ok, so the loop believes an unclaimed issue was claimed and dispatches it again"
)

mut_ran=0
env_knobs_checked=0
for row in "${MUTANTS[@]}"; do
    IFS=$'\t' read -r m_label m_from m_to m_env m_args m_expect m_why <<<"$row"
    apply_mutation "$m_label" "$m_from" "$m_to" || continue
    # VACUITY GUARD. A mutant whose fixture knob never fires is indistinguishable
    # from a guard being caught — the mutation is applied, the run completes, and
    # the expectation is met by the ordinary path. Measured: renaming two env
    # cells to dead names left both rows reporting CAUGHT and the whole run
    # green. So the knob's NAME must actually be consulted by the mock, and the
    # cell must be `-` or a NAME=VALUE, never blank.
    if [ "$m_env" != "-" ]; then
        m_envname="${m_env%%=*}"
        if [ -z "$m_envname" ] || [ "$m_envname" = "$m_env" ]; then
            bad "$m_label — env cell '$m_env' is not '-' and not a NAME=VALUE assignment"
            continue
        fi
        if ! grep -q "$m_envname" "$WORK/bin/gh"; then
            bad "$m_label — the mock never reads '$m_envname', so this mutant's fixture knob is DEAD and its verdict would be the ordinary path's"
            continue
        fi
        env_knobs_checked=$((env_knobs_checked + 1))
    fi
    # The env cell is a literal NAME=VALUE assignment applied with `export`, so
    # the table stays data — no eval, and no second copy of the mock's knobs.
    [ "$m_env" = "-" ] || export "${m_env?}"
    # shellcheck disable=SC2086
    run_claim_script "$MUTANT" $m_args
    [ "$m_env" = "-" ] || unset "${m_env%%=*}"
    mutant_ran "$m_label" || continue
    mut_ran=$((mut_ran + 1))
    case "$m_expect" in
        cleared)
            if cleared; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the decision was neutered and nothing cleared — its case proves nothing"
            fi ;;
        cleared-13)
            if has "$(edit_for 13)" "--remove-assignee"; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the reset was removed and no leak followed — the batch case proves nothing"
            fi ;;
        false-detail-13)
            if has "$(detail_for 13)" "cleared claim residue"; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the note reset was removed and #13 still reported '$(detail_for 13)'"
            fi ;;
        state-arm)
            # POSITIVE, not an absence: "does not say malformed" is satisfied by
            # any run at all, including one whose knob never fired. Requiring the
            # state arm's own words proves the short read HAPPENED and then fell
            # through to a different arm — a dead knob reports 'cleared claim
            # residue' here and is caught as inconclusive.
            if has "$(detail_of)" "malformed"; then
                bad "$m_label UNDETECTED: the guard was removed and the run still reported malformed — its case proves nothing"
            elif ! has "$(detail_of)" "left alone"; then
                bad "$m_label INCONCLUSIVE: without the guard the run reported '$(detail_of)' — neither malformed nor a left-alone arm, so the short-read knob may never have fired"
            else
                ok "$m_label CAUGHT: $m_why"
            fi ;;
        false-clear)
            if [ "$(result_of)" = "ok" ] && has "$(detail_of)" "cleared claim residue"; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the tolerance was re-widened and no false clear followed — section 7 proves nothing"
            fi ;;
        false-ok)
            # The harm here is a SILENT SUCCESS, not a false detail: a claim that
            # wrote nothing reports ok, and #288's whole point is that the
            # verdict is all a coordinator ever sees. The recorded-edit control
            # is the one the tolerated-edge rows carry — without it a knob that
            # never fired reports CAUGHT on the ordinary path's verdict.
            if [ -n "$EDITS" ]; then
                bad "$m_label INCONCLUSIVE: an edit was recorded, so no failure was injected and 'ok' is the ordinary path's verdict"
            elif [ "$(result_of)" = "ok" ]; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the token match was re-widened to the bare error string and the wholly-failed claim still reported '$(result_of)' — section 7b proves nothing"
            fi ;;
        *) bad "$m_label — unknown expectation '$m_expect'" ;;
    esac
done

if [ "$mut_ran" -eq "${#MUTANTS[@]}" ]; then
    ok "every declared mutant ran (${#MUTANTS[@]} of ${#MUTANTS[@]})"
else
    bad "only $mut_ran of ${#MUTANTS[@]} declared mutants ran — the rest proved nothing"
fi

# The knob guard itself can go vacuous: if every env cell became `-`, it would
# check nothing and still pass. Today four mutants carry a knob.
if [ "$env_knobs_checked" -ge 4 ]; then
    ok "every mutant fixture knob ($env_knobs_checked) is one the mock actually reads"
else
    bad "only $env_knobs_checked mutant env knobs were checked — fewer than the 4 carried today; did a knob-driven mutant lose its cell?"
fi

# --- vacuity floor ------------------------------------------------------------
# A broken harness reports a clean tree exactly like a correct one, so the run
# states how much it actually measured. This is an EQUALITY, not a floor: every
# case above runs exactly one assertion on every path (each if/elif chain ends
# in exactly one ok/bad, and each mutant contributes exactly one whether it is
# applied, run, or refused), so the total is deterministic. A floor is what this
# was, and it was measured useless — at `${#MUTANTS[@]} + 2` the whole of
# sections 3 through 9 could be deleted and the run still passed. An equality
# cannot rot silently in either direction: deleting a case fails it, and adding
# one forces a deliberate bump here rather than a quiet drift.
# ONE transcription, used in both the arithmetic and the message. It was written
# twice, and a live edition during review carried 24 against 22 actual cases —
# adding one case while removing another nets zero and passes silently either
# way, so the number that cannot be re-derived is at least only written once.
EXPECTED_CASES=38
EXPECTED_ASSERTS=$(( ${#MUTANTS[@]} + EXPECTED_CASES ))
if [ "$asserts" -ne "$EXPECTED_ASSERTS" ]; then
    bad "$asserts assertions ran, expected $EXPECTED_ASSERTS (${#MUTANTS[@]} mutants + $EXPECTED_CASES cases) — a case was added or skipped; if deliberate, bump EXPECTED_CASES"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "claim-lifecycle tests: all pass ($asserts assertions, ${#MUTANTS[@]} mutants)" >&2
    exit 0
fi
echo "claim-lifecycle tests: FAILURES above ($asserts assertions, ${#MUTANTS[@]} mutants)" >&2
exit 1
