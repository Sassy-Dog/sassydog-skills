#!/usr/bin/env bash
# test-drain-terminal-states.sh — pins dispatch-ready §7's terminal-state
# coverage: the uncovered state #282 found, the discriminator that makes the
# fix safe, and the four things the fix must NOT have moved.
#
# THE BUG. §7 defined exactly two terminal states and between them they did not
# cover "Ready empty, in-flight zero, and an open unmerged PR this loop is not
# permitted to advance". COMPLETE was vetoed by the open PR; STALLED required
# Ready non-empty. Neither branch was reachable, so the loop ticked forever —
# reporting the state accurately and doing nothing, with no way to self-cancel.
# The stall record could not help either: it was written only INSIDE the STALLED
# branch, so the two-tick confirmation clock never started.
#
# THE ACTION THAT CREATES THE STATE IS THE ACTION THAT HIDES IT. `issue-claim.sh
# block` strips `ready` and `in-progress` together — correct, a blocked issue is
# neither dispatchable nor in flight — which also removes it from `ready[]`, the
# one set the old conjunct consulted. Recording "a human must decide this" was
# precisely what blinded the stall detector to it. Observed 2026-08-26 on #273 /
# PR #279; the loop was cancelled by hand (issue #282).
#
# WHY THE FIX IS A DISCRIMINATOR AND NOT A DELETED CONJUNCT. Simply dropping
# "Ready non-empty" is the obvious fix and it is wrong — it is also the shape a
# later "this conjunct does nothing" sweep re-derives, which is why the rejected
# option is pinned here as a NEGATIVE rather than merely described. An open PR
# is not automatically a human gate: one whose checks are still running or red
# can still advance on its own, and firing STALLED there cancels a loop that was
# about to make progress. So the third conjunct is "nothing this loop is
# permitted to advance", and the four-row discriminator table is what decides
# which side of that an open PR falls on.
#
# WHAT IS ASSERTED, AND WHY EACH ONE READS LIKE DRIFT TO A LATER SWEEP:
#
#   1. THE THIRD CONJUNCT. STALLED's opening sentence must carry "nothing this
#      loop is permitted to advance" and must NOT have re-acquired "Ready
#      non-empty". The must-not-exist is scoped to that OPENING PARAGRAPH on
#      purpose: the prose below it quotes the old conjunct twice while
#      explaining what replaced it, so a window-wide veto would redden on
#      correct text and a file-wide one is guaranteed to.
#   2. THE DISCRIMINATOR ROWS ARE ACCOUNTED FOR, NOT COUNTED. Every body row of
#      the table must classify as held or alive by its EFFECT cell, and its
#      answer cell must agree with it. A tally of two patterns leaves a fifth
#      row matching neither invisible — the failure CLAUDE.md records about
#      test-sentry-verification.sh — and a row whose `**No**` sits beside
#      "keeps the loop alive" is a contradiction no presence check can see.
#      The four rows are ALSO asserted individually, because accounting alone
#      is satisfied by a table that swapped which condition carries which
#      effect, which is exactly the regression acceptance boxes 1-3 enumerate.
#   3. THE HELD SET MUST BE NON-EMPTY. Without it "nothing to advance" is
#      satisfied vacuously by a queue that simply finished, and STALLED races
#      COMPLETE on the state COMPLETE owns. This is the assertion a reader who
#      sees only "the two states are now disjoint" deletes as belt-and-braces.
#   4. BOTH CARVE-OUTS SURVIVE UNCHANGED, and they are compared against
#      CANONICAL LITERALS HELD IN THIS GATE — not merely to each other, and not
#      by a keyword. #282 requires them unchanged, so the strongest available
#      bound is byte identity against text living outside the file under test:
#      an edit applied to the file alone reddens. The stated cost, in the idiom
#      test-review-gate-decisions.sh uses for its own canonical literal: a
#      LEGITIMATE reword must be made in two places at once and fails loudly
#      until it is. The list is also required to hold exactly those two
#      bullets, so a third one weakening them is caught by arithmetic.
#   5. COMPLETE IS UNCHANGED, VETO INCLUDED. Its condition line, its verbatim
#      announcement, and the safety-rail wording that vetoes it on an open PR
#      are all pinned. The rail is pinned as a FIXED STRING it carries, so a
#      softening rewrite deletes the literal and a must-exist catches what no
#      prose veto could — the shape decision 5 of the review-gate gate uses.
#   6. THE RECORD IS WRITTEN FROM THE HELD SET, NEVER FROM `ready[]`. That is
#      the half that makes the two-tick clock reachable in the uncovered state.
#      The confirmation itself must survive: announcing on ONE tick is the
#      tempting "but it is obviously terminal" simplification.
#   7. ONE STOP PATH, TWO TERMINAL STATES. §7 still ends itself in exactly two
#      states — #282 adds coverage, not a third state — and a held set of
#      nothing but PRs takes the SAME stop path, cron self-cancel included.
#
# Why source-level. There is no renderer and no runtime: the artifact IS the
# instruction the loop follows. Same shape as test-review-gate-decisions.sh,
# test-visibility-preconditions.sh and test-sentry-verification.sh.
#
# WHITESPACE FLATTENING. Prose assertions run against a flattened copy of their
# window, never against raw lines: this repo hard-wraps, so a phrase routinely
# straddles a line break — and for a MUST-NOT-EXIST check that miss is a false
# PASS. Structural assertions — table rows, the fenced announcement lines, the
# condition line — stay line-scoped on purpose, because their shape IS the
# thing under test. The flatten strips leading blockquote markers for the reason
# test-doc-reconciliation.sh does; §7 carries none today, and the day one
# arrives a marker-preserving flatten would read the phrase as absent.
#
# NO `-ef` PRECONDITION, deliberately, and what follows is the reasoning
# test-review-gate-decisions.sh's section 9 paid for rather than its conclusion.
# That gate needs the precondition because its subject is its OWN source, so a
# copy measures the wrong file. This gate's subject is another tracked file,
# resolved against `git rev-parse --show-toplevel`, so running it from a copy
# still measures the tracked SKILL.md — which is what a mutation harness wants.
# The mirror hazard is real and belongs to the HARNESS: mutate the tracked
# skills/dispatch-ready/SKILL.md in place and restore it. Mutating a tmpdir copy
# of it makes every assertion here report on the unmutated tracked file and
# every mutant read `undetected` while proving nothing (the #262 lesson).
#
# No `| grep -q` pipelines anywhere: grep -q closes the pipe on its first match,
# the writer takes SIGPIPE, and pipefail promotes the 141 — turning a caught
# regression into a reported miss (the #172 shape, generalised by #256). Every
# string match here reads a herestring or the file directly.
#
# NO INVENTORY NUMBER IS TRANSCRIBED. The assertion count is PRINTED by the run
# and guarded by a coarse vacuity floor set well below it: a floor tuned to
# today's exact total is one more number that rots, and a count nobody can
# re-derive is what a future editor trusts instead of re-measuring (#268). The
# mutation battery lives in the PR that added this gate (issue #282).
#
# One tracked file. No gh, no network, no repo mutation.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-drain-terminal-states.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-drain-terminal-states: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/dispatch-ready/SKILL.md"

fails=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1"; }
bad() { asserts=$((asserts + 1)); echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

# assert_in <haystack> <ERE> <label>   — herestring, never a pipeline
assert_in() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_not_in <haystack> <ERE> <label>
assert_not_in() {
    if grep -qE -- "$2" <<<"$1"; then bad "$3"; else ok "$3"; fi
}
# assert_has <haystack> <FIXED string> <label> — for a literal carrying regex
# metacharacters. The COMPLETE veto ends in `(in-flight until actually MERGED,
# per §3)`, whose parentheses are an ERE group: matched as a pattern it
# silently tests something else entirely.
assert_has() {
    if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_line <ERE> <label> — line-scoped, against the tracked file
assert_line() {
    if grep -qE -- "$1" "$SKILL"; then ok "$2"; else bad "$2"; fi
}
# assert_eq <got> <want> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 — got [$1]"; fi
}

echo "dispatch-ready section 7 terminal states (issue #282)"

if [ -r "$SKILL" ]; then
    ok "read $SKILL"
else
    bad "missing file: $SKILL"
    echo "test-drain-terminal-states: FAILED" >&2
    exit 1
fi

# raw_region <start prefix> <stop prefix> — from the first line STARTING WITH
# start (inclusive) to the line before the next line starting with stop; an
# empty stop means "the next blank line". The start line is consumed with
# `next`, so a start that also matches its own stop — every heading region here
# does — cannot terminate itself on line one.
#
# LITERAL PREFIXES, NEVER REGEXES, and that is not a style choice: awk expands
# backslash escapes inside a `-v` assignment, so `\*\*Self-resolving` arrives as
# `**Self-resolving` and the leading `*` is a quantifier with nothing to repeat.
# Measured — both carve-out windows came back EMPTY, which their non-empty
# guards caught. A pattern that silently matched something else would not have
# been caught, which is why the anchors are index() comparisons now.
#
# `### ` as a stop does not match a `#### ` heading (character 4 differs), which
# is what lets the STALLED window span its own `####` subsection while still
# stopping at `### Stop path`; `## ` likewise matches only level-2 headings.
raw_region() {
    awk -v s="$1" -v stop="$2" '
        !f && index($0, s) == 1 { f = 1; print; next }
        f && stop == "" && $0 == "" { exit }
        f && stop != "" && index($0, stop) == 1 { exit }
        f { print }' "$SKILL"
}
# flat <text> — join wrapped lines, strip blockquote markers, squeeze runs, trim.
# `[[:space:]]`, never `[ \t]`: BSD sed reads the latter as a literal-t class
# and eats every t. Ends in `sed`/`tr`, which drain their input rather than
# closing early.
flat() {
    sed -E 's/^[[:space:]]*(> ?)+//' <<<"$1" | tr '\n' ' ' | tr -s ' ' \
        | sed -E 's/^ +//; s/ +$//'
}

# --- windows, each proved non-empty AND bounded ------------------------------
# A window that silently over-runs is the failure mode CLAUDE.md records twice:
# an assertion labelled for one rule, answered by the text of another. So each
# window is asserted to STOP where it claims to, by refusing a marker that
# belongs to the text after it.

sec7="$(raw_region '## 7. Terminal states' '## Guardrails')"
complete_raw="$(raw_region '### DRAIN COMPLETE' '### ')"
stalled_raw="$(raw_region '### DRAIN STALLED' '### ')"
gate_raw="$(raw_region '### DRAIN STALLED' '#### ')"
disc_raw="$(raw_region '#### The discriminator' 'Two carve-outs keep the state precise:')"
opening_raw="$(raw_region 'In-flight zero AND dispatched zero' '')"
record_raw="$(raw_region '**Confirm across two consecutive ticks' '```')"
announce_raw="$(raw_region 'DRAIN STALLED — nothing dispatchable' '```')"
rails_raw="$(raw_region 'Safety rails:' '## ')"
carvelist_raw="$(raw_region 'Two carve-outs keep the state precise:' '**Both carve-outs')"
carve1_raw="$(raw_region '- **Self-resolving holds' '- **A foreign claim')"
carve2_raw="$(raw_region '- **A foreign claim' '')"

for w in sec7 complete_raw stalled_raw gate_raw disc_raw opening_raw record_raw \
         announce_raw rails_raw carvelist_raw carve1_raw carve2_raw; do
    if [ -n "${!w}" ]; then
        ok "window $w resolved"
    else
        bad "window $w is empty — every assertion scoped to it would pass vacuously"
    fi
done
[ "$fails" -eq 0 ] || { echo "test-drain-terminal-states: FAILED ($fails)" >&2; exit 1; }

sec7_flat="$(flat "$sec7")"
complete_flat="$(flat "$complete_raw")"
stalled_flat="$(flat "$stalled_raw")"
gate_flat="$(flat "$gate_raw")"
disc_flat="$(flat "$disc_raw")"
opening_flat="$(flat "$opening_raw")"
record_flat="$(flat "$record_raw")"
announce_flat="$(flat "$announce_raw")"
rails_flat="$(flat "$rails_raw")"

assert_not_in "$complete_flat" 'In-flight zero AND dispatched zero' \
    "COMPLETE window stops before the STALLED gate"
assert_not_in "$gate_flat" 'May this loop advance it' \
    "STALLED gate window stops before the discriminator table"
assert_not_in "$disc_flat" 'Self-resolving holds' \
    "discriminator window stops before the carve-outs"
assert_not_in "$stalled_flat" 'Stop the loop yourself' \
    "STALLED window stops before the stop path"
assert_not_in "$opening_flat" 'The third conjunct' \
    "STALLED opening window is one paragraph, not the rationale below it"
assert_not_in "$record_flat" 'DRAIN STALLED —' \
    "stall-record window stops before the announcement block"
assert_not_in "$rails_flat" 'Ready only' \
    "safety-rails window stops before the Guardrails list"

# --- 1. the third conjunct ---------------------------------------------------
echo "-- 1: the STALLED gate is 'nothing to advance', not 'Ready non-empty'"

assert_in "$opening_flat" 'In-flight zero AND dispatched zero this tick AND' \
    "STALLED keeps its first two conjuncts"
assert_in "$opening_flat" 'nothing this loop is permitted to advance' \
    "STALLED's third conjunct is 'nothing this loop is permitted to advance'"
assert_not_in "$opening_flat" 'Ready non-empty' \
    "STALLED's gate no longer requires Ready non-empty"
assert_in "$opening_flat" 'every open PR held by the discriminator' \
    "STALLED's held set includes open PRs, not Ready items alone"
assert_in "$opening_flat" 'every Ready item held by a §4 filter' \
    "STALLED's held set still includes held Ready items"

# The uncovered state, and the rejected fix. Both are rationale a "this reads
# like history" sweep deletes — and deleting them is what lets the conjunct be
# re-derived as the obvious one-word simplification.
assert_in "$gate_flat" 'covered by NEITHER terminal state' \
    "the gate names the state that neither terminal state covered"
assert_in "$gate_flat" 'COMPLETE is vetoed by the open PR, and STALLED could not fire on an empty queue' \
    "the gate names both halves of why it was uncovered"
assert_in "$gate_flat" 'Deleting that conjunct outright would have been the wrong fix' \
    "the gate pins the rejected fix — dropping the conjunct outright"
assert_in "$gate_flat" 'an open PR is not automatically a human gate' \
    "the gate states why dropping it outright is wrong"
assert_in "$gate_flat" 'strips .ready. and .in-progress. together' \
    "the gate records that blocking an issue is what hid the state"

# --- 2. the discriminator, every row accounted for ---------------------------
echo "-- 2: every discriminator row classifies, and its answer agrees with it"

assert_line '^\| Open PR this tick \| May this loop advance it\? \| Effect \|$' \
    "the discriminator table carries its header row"

rows="$(awk '
    /^#### The discriminator/ { f = 1; next }
    f && /^Two carve-outs/ { exit }
    f && /^\|/ && $0 !~ /^\| *-+ *\|/ && $0 !~ /^\| Open PR this tick \|/ { print }' "$SKILL")"

n_rows=0; n_held=0; n_alive=0; n_unclassified=0; n_contradictory=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    n_rows=$((n_rows + 1))
    answer="$(cut -d'|' -f3 <<<"$row")"
    effect="$(cut -d'|' -f4 <<<"$row")"
    held=0; alive=0
    grep -qF -- 'held: joins the held set' <<<"$effect" && held=1
    grep -qF -- 'keeps the loop alive'     <<<"$effect" && alive=1
    if [ "$held" -eq 1 ] && [ "$alive" -eq 0 ]; then
        n_held=$((n_held + 1))
        grep -qF -- '**No**' <<<"$answer" || n_contradictory=$((n_contradictory + 1))
    elif [ "$alive" -eq 1 ] && [ "$held" -eq 0 ]; then
        n_alive=$((n_alive + 1))
        grep -qF -- '**Yes**' <<<"$answer" || n_contradictory=$((n_contradictory + 1))
    else
        n_unclassified=$((n_unclassified + 1))
    fi
done <<<"$rows"

assert_eq "$n_unclassified" 0 \
    "every discriminator row classifies as held or alive ($n_rows rows read)"
assert_eq "$n_contradictory" 0 \
    "every row's answer cell agrees with its effect cell"
assert_eq "$((n_held + n_alive))" "$n_rows" \
    "held + alive accounts for every row (held $n_held, alive $n_alive)"
if [ "$n_held" -ge 2 ] && [ "$n_alive" -ge 2 ]; then
    ok "both sides of the discriminator are populated (held $n_held, alive $n_alive)"
else
    bad "the discriminator has collapsed to one side (held $n_held, alive $n_alive)"
fi

# The four rows individually. Accounting alone is satisfied by a table that
# swapped which condition carries which effect.
assert_line '^\| Its issue carries `blocked` \| \*\*No\*\*.*held: joins the held set \|$' \
    "a blocked issue's open PR is HELD (acceptance 1)"
assert_line '^\| It carries an unresolved \*\*Blocking\*\* review finding whose ONE §2 redispatch is spent \| \*\*No\*\*.*held: joins the held set \|$' \
    "an unresolved Blocking finding with its redispatch spent is HELD"
assert_line '^\| Checks still running \| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a PR whose checks are still running keeps the loop alive (acceptance 2)"
assert_line '^\| Checks red and its issue is not `blocked` \| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a red PR whose issue is not blocked keeps the loop alive (acceptance 3)"

# The hinge, and the two rules that keep an unreadable gate from reading as one.
assert_in "$disc_flat" 'redispatch budget is the hinge on both failure rows' \
    "the discriminator names the redispatch budget as the hinge"
assert_in "$disc_flat" 'grants exactly ONE redispatch per issue' \
    "the discriminator states the budget is exactly one redispatch"
assert_in "$disc_flat" 'a state it can still act on is not a stall' \
    "the discriminator states an actionable state is not a stall"
assert_in "$disc_flat" 'the label is a write this loop performs, the finding is a fact it reads' \
    "the discriminator states why the finding row is not redundant beside the label"
assert_in "$disc_flat" 'Read the review outcome from the PR body' \
    "the discriminator reads the review outcome from the PR body, as section 2 does"
assert_in "$disc_flat" 'A gate that could not be read is not a hold' \
    "an unreadable gate is an unverified tick, not a hold"
assert_in "$disc_flat" 'write no stall record' \
    "an unverified tick writes no stall record"

# --- 3. the held set must be non-empty ---------------------------------------
echo "-- 3: 'nothing to advance' cannot be satisfied vacuously"

assert_in "$gate_flat" 'The held set must be non-empty' \
    "STALLED requires a non-empty held set"
assert_in "$gate_flat" 'Nothing held, nothing in flight and no open PR is COMPLETE' \
    "an empty held set with nothing in flight is COMPLETE, not STALLED"
assert_in "$gate_flat" 'which fires first' \
    "COMPLETE fires first on that state"
assert_in "$gate_flat" 'must never announce STALLED' \
    "a vacuously satisfied conjunct must never announce STALLED"

# --- 4. both carve-outs, unchanged -------------------------------------------
echo "-- 4: both carve-outs survive byte-identical to the canonical text"

# Canonical literals, held HERE rather than compared between copies: comparing
# the file to itself bounds nothing, and a keyword check ("collision", "foreign
# claim") is satisfied by a bullet that reversed its own rule. #282 requires
# these two unchanged, so byte identity is the bound. A legitimate reword must
# be made in both places at once and fails loudly until it is.
CARVE1_CANON='- **Self-resolving holds can never trip it.** Collision holds, migration-slot holds, and deps on in-flight issues all require in-flight > 0 — the in-flight = 0 conjunct excludes them by construction.'
CARVE2_CANON='- **A foreign claim is not a human gate.** An item skipped by the Claimed filter is another session'\''s in-flight (`mine: false`) and resolves when that session merges, no human needed. A tick whose holds include an active foreign claim is idle, not stalled — keep looping.'

assert_eq "$(flat "$carve1_raw")" "$CARVE1_CANON" \
    "carve-out 1 (self-resolving holds) is unchanged"
assert_eq "$(flat "$carve2_raw")" "$CARVE2_CANON" \
    "carve-out 2 (a foreign claim is not a human gate) is unchanged"

n_carve="$(grep -c '^- \*\*' <<<"$carvelist_raw")"
assert_eq "$n_carve" 2 \
    "the carve-out list holds exactly two bullets — a third would weaken them unseen"
assert_in "$(flat "$carvelist_raw")" 'Two carve-outs keep the state precise' \
    "the carve-out list still introduces itself as two"

assert_in "$stalled_flat" 'Both carve-outs survive the new conjunct unchanged' \
    "the fix states both carve-outs survive it"
assert_in "$stalled_flat" 'whether it presents as an issue row or as a PR row' \
    "the foreign-claim carve-out is stated to cover PR rows too"

# --- 5. COMPLETE is unchanged, veto included ---------------------------------
echo "-- 5: COMPLETE keeps its condition, its announcement and its open-PR veto"

assert_line '^Ready empty AND in-flight zero → announce loudly and take the stop path below immediately' \
    "COMPLETE's condition line is unchanged"
assert_line '^DRAIN COMPLETE — Ready is empty and nothing is in flight\.$' \
    "COMPLETE's verbatim announcement is unchanged"
assert_has "$rails_flat" \
    'anything still claimed or an open PR (in-flight until actually MERGED, per §3) means the drain is not complete.' \
    "the safety rail still vetoes COMPLETE on an open PR"
assert_in "$complete_flat" 'COMPLETE is unchanged, veto included' \
    "COMPLETE says so where a reader of the fix will look"
assert_in "$complete_flat" 'it now joins STALLED.s held set' \
    "an unadvanceable PR is routed into STALLED's held set rather than nowhere"

# The rails' STALLED half gained the two conditions the discriminator produces.
assert_in "$rails_flat" 'an open PR this loop may still advance' \
    "the rails keep the loop alive on an advanceable open PR"
assert_in "$rails_flat" 'an empty held set' \
    "the rails keep the loop alive on an empty held set"
assert_in "$rails_flat" 'any in-flight work \(mine or foreign\)' \
    "the rails still keep the loop alive on foreign in-flight work"

# --- 6. the record is written from the held set ------------------------------
echo "-- 6: the two-tick clock is reachable, and still two ticks"

assert_in "$record_flat" 'Confirm across two consecutive ticks before stopping' \
    "the two-tick confirmation survives"
assert_in "$record_flat" 'held issue numbers AND held PR numbers' \
    "the stall record persists held PR numbers alongside held issue numbers"
assert_in "$record_flat" 'written from the held set, never from .ready\[\]' \
    "the record is written from the held set, not from ready[]"
assert_in "$record_flat" 'which is what makes it reachable with Ready empty' \
    "the record is stated reachable with Ready empty"
assert_in "$record_flat" 'the two-tick clock never started' \
    "the record names the pre-fix failure it fixes"
assert_line '^  `stall: suspected — nothing in flight and nothing this loop may advance; an identical hold-set next tick ends the loop`\.$' \
    "the suspected-stall line no longer claims Ready is non-empty"
assert_in "$record_flat" 'PR rows alongside issue rows, each naming the PR and the gate holding it' \
    "the confirmed announcement names each held PR and its gate"

# --- 7. one stop path, two terminal states -----------------------------------
echo "-- 7: still two terminal states, still one stop path"

assert_in "$sec7_flat" 'A drain loop ends itself in exactly two states' \
    "#282 adds coverage, not a third terminal state"
assert_line '^DRAIN STALLED — nothing dispatchable, nothing in flight, and nothing this loop may advance:$' \
    "the STALLED announcement's headline covers a PR-only held set"
assert_line '^  PR #279 \(#273\) → open, issue blocked \(3 Blocking review findings, redispatch spent\)$' \
    "the announcement carries a PR row naming the PR and its gate (acceptance 1)"
assert_not_in "$announce_flat" 'all Ready items gate on human action' \
    "the announcement no longer asserts Ready holds the held set"
assert_in "$stalled_flat" 'same stop path as DRAIN COMPLETE' \
    "STALLED still takes COMPLETE's stop path"
assert_in "$stalled_flat" 'one path, never a parallel one' \
    "there is still exactly one stop path"
assert_in "$stalled_flat" 'A held set of nothing but PRs takes that same path' \
    "a PR-only held set takes the same stop path"
assert_in "$stalled_flat" 'self-cancel below is not optional on it' \
    "the cron self-cancel is not optional on a PR-only held set (acceptance 1)"
assert_in "$stalled_flat" 'sees an open PR it may still advance' \
    "an advanceable PR resets the confirmation clock"

# --- vacuity floor -----------------------------------------------------------
# Coarse and set well below today's total on purpose: it catches a COLLAPSE — a
# whole assertion block deleted in a refactor, which otherwise drops the count
# and still prints "all green" — not a trim. A broken window already fails
# loudly above, where every window carries a non-empty guard. The total itself
# is printed, never transcribed: see the header.
ASSERT_FLOOR=45
if [ "$asserts" -lt "$ASSERT_FLOOR" ]; then
    echo "test-drain-terminal-states: only $asserts assertions ran (floor $ASSERT_FLOOR) — a window or a block is silently matching nothing" >&2
    exit 1
fi

if [ "$fails" -ne 0 ]; then
    echo "test-drain-terminal-states: FAILED ($fails of $asserts assertions)" >&2
    exit 1
fi
echo "drain terminal-state tests: all green ($asserts assertions)"
