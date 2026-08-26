#!/usr/bin/env bash
# test-claim-lifecycle.sh — a claim is WRITTEN as two things and CLEARED as one,
# and `promote` may only clear the half that is residue (issue #281).
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
                case "${MOCK_FAIL_EDIT:-0}" in
                    notfound)
                        # gh's own wording for the edge the tolerance was
                        # written for. Nothing is recorded: the edit did not
                        # apply, which is the whole point.
                        echo "gh: 'ready' not found" >&2
                        exit 1 ;;
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

export MOCK_REPO="mock-org/mock-repo"
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
{
    printf '10\ttester\t\tOPEN\n'
    printf '11\tsomeone-else\t\tOPEN\n'
    printf '12\ttester\t%s\tOPEN\n' "$INPROG"
    printf '13\t\t\tOPEN\n'
    printf '14\ttester,someone-else\t\tOPEN\n'
    printf '15\t\tbug,sev:high\tOPEN\n'
    printf '16\ttester\t\tCLOSED\n'
} >"$MOCK_ISSUES"

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
elif [ -z "$(detail_of)" ]; then
    bad "an unresolved login left the assignee in place SILENTLY"
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
MOCK_FAIL_EDIT=notfound run_claim promote 10
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
if has "$ERR" "cleared claim residue"; then
    bad "stderr asserted the clear on a promote whose edit failed outright"
else
    ok "a hard-failed promote edit never announces a clear on stderr either"
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
run_claim promote 10 11
if has "$(edit_for 11)" "--remove-assignee"; then
    bad "BATCH LEAK: #10's residue verdict reached #11's edit — a human's assignee stripped: $(edit_for 11)"
elif ! has "$(edit_for 10)" "--remove-assignee"; then
    bad "batch promote lost #10's clear: $(edit_for 10)"
elif [ "$(n_edits)" != "2" ]; then
    bad "batch promote wrote $(n_edits) edits for 2 issues"
else
    ok "batch promote 10 11: the clear lands on #10 only, and #11's edit is untouched"
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
"M5 unreadable probe clears anyway	        RESIDUE_NOTE=\"assignee unchecked: could not read #\$n\"	        RESIDUE_ARGS=(--remove-assignee \"@me\")	MOCK_FAIL_VIEW=1	promote 10	cleared	treating an unreadable probe as residue strips an assignee never read"
"M6 --force widens the gate	    if [[ \"\$assignees\" != \"\$ME\" ]]; then	    if [[ \"\$assignees\" != \"\$ME\" && \"\$FORCE\" == \"0\" ]]; then	-	promote 11 --force	cleared	--force widened to promote strips a HUMAN's assignee"
"M7 the gate stops resetting its verdict	    RESIDUE_ARGS=()	    :	-	promote 10 11	cleared-11	one issue's verdict leaks into the next one's edit in a batch"
"M9 short-read guard	    if [[ \"\$read_ok\" != \"1\" ]]; then	    if false; then	MOCK_SHORT_VIEW=1	promote 10	no-malformed	a truncated probe result stops being reported as malformed"
"M8 not-found tolerance re-widened to promote	        claim|release|block|demote)	        claim|release|block|demote|promote)	MOCK_FAIL_EDIT=notfound	promote 10	false-clear	a promote that wrote nothing reports ok and claims the residue was cleared"
)

mut_ran=0
for row in "${MUTANTS[@]}"; do
    IFS=$'\t' read -r m_label m_from m_to m_env m_args m_expect m_why <<<"$row"
    apply_mutation "$m_label" "$m_from" "$m_to" || continue
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
        cleared-11)
            if has "$(edit_for 11)" "--remove-assignee"; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the reset was removed and no leak followed — the batch case proves nothing"
            fi ;;
        no-malformed)
            if has "$(detail_of)" "malformed"; then
                bad "$m_label UNDETECTED: the guard was removed and the run still reported malformed — its case proves nothing"
            else
                ok "$m_label CAUGHT: $m_why"
            fi ;;
        false-clear)
            if [ "$(result_of)" = "ok" ] && has "$(detail_of)" "cleared claim residue"; then
                ok "$m_label CAUGHT: $m_why"
            else
                bad "$m_label UNDETECTED: the tolerance was re-widened and no false clear followed — section 7 proves nothing"
            fi ;;
        *) bad "$m_label — unknown expectation '$m_expect'" ;;
    esac
done

if [ "$mut_ran" -eq "${#MUTANTS[@]}" ]; then
    ok "every declared mutant ran (${#MUTANTS[@]} of ${#MUTANTS[@]})"
else
    bad "only $mut_ran of ${#MUTANTS[@]} declared mutants ran — the rest proved nothing"
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
EXPECTED_ASSERTS=$(( ${#MUTANTS[@]} + 22 ))
if [ "$asserts" -ne "$EXPECTED_ASSERTS" ]; then
    bad "$asserts assertions ran, expected $EXPECTED_ASSERTS (${#MUTANTS[@]} mutants + 22 cases) — a case was added or skipped; if deliberate, bump the constant"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "claim-lifecycle tests: all pass ($asserts assertions, ${#MUTANTS[@]} mutants)" >&2
    exit 0
fi
echo "claim-lifecycle tests: FAILURES above ($asserts assertions, ${#MUTANTS[@]} mutants)" >&2
exit 1
