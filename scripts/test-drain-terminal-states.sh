#!/usr/bin/env bash
# test-drain-terminal-states.sh — pins dispatch-ready §7's terminal-state
# coverage: the uncovered state #282 found, the enumeration the fix depends on,
# the discriminator that makes it safe, and the four things the fix must NOT
# have moved.
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
# THE ENUMERATION IS PART OF THE FIX, NOT A DETAIL OF IT, and this gate exists
# in its current shape because the first edition of the fix omitted it and was
# WORSE THAN THE BUG. §2's only PR discovery is "open PRs from those branches" —
# the branches of IN-FLIGHT issues — and `block` strips `in-progress`, so in
# #282's own state the tick enumerates zero PRs. A held set that is empty
# because nothing was looked at is indistinguishable from one that is empty
# because nothing is held: STALLED is then forbidden by the non-empty rule while
# COMPLETE is admitted, and the loop announces DRAIN COMPLETE and self-cancels
# with a human-gated PR still open. The forever-tick at least never claimed to
# be finished. So §2 must resolve open PRs for `blocked[]` too, and §7 must say
# that "every open PR this tick sees" means that union — both halves are pinned.
#
# WHY THE FIX IS A DISCRIMINATOR AND NOT A DELETED CONJUNCT. Simply dropping
# "Ready non-empty" is the obvious fix and it is wrong — it is also the shape a
# later "this conjunct does nothing" sweep re-derives, which is why the rejected
# option is pinned here as a NEGATIVE rather than merely described. An open PR
# is not automatically a human gate: one whose checks are still running or red
# can advance on its own, and firing STALLED there cancels a loop that was about
# to make progress. So the third conjunct is "nothing this loop is permitted to
# advance", and a table decides which side of that an open PR falls on.
#
# THE TABLE'S LAST ROW IS A DEFAULT AND THE GATE PINS IT AS ONE. §2 holds a PR
# for more reasons than the rows enumerate — `CONFLICTING`, a held `SKIPPED`, a
# held `NO REPORT` — and a table that silently answers "alive" for a shape it
# does not know re-creates #282 one shape at a time. `CONFLICTING` is the
# measured case: a conflicted PR stops CI firing at all and `no checks reported`
# reads exactly like `CI hasn't started`, so without its own row ABOVE the
# checks rows it matches "checks still running" and is answered with something
# that can never happen — one long-lived conflicted PR would then keep a
# genuinely stalled queue from ever confirming STALLED, which is a regression
# the pre-#282 file did not have.
#
# HOW THIS GATE IS BOUND, AND WHY IT IS BOUND THAT WAY. Its first edition
# asserted presence only, and a review measured meaning-inverting rewrites
# passing it at exit 0 — writing the bug back as `Ready **non-empty**`, which a
# plain flatten cannot see; appending a fifth table row licensing a merge past a
# `blocked` issue; inverting the safety rails; and deleting a run of assertion
# blocks under a floor that did not bind. Every one of them KEPT the
# sentence an assertion greps for and QUALIFIED it, which is exactly the edit a
# tidying sweep makes and exactly what a must-exist cannot see. So the decision
# surface is pinned by CANONICAL LITERALS held in this gate — the whole
# paragraph, compared for equality after flattening, the shape the carve-outs
# already used — never by a keyword and never by comparing the file to itself,
# which bounds divergence rather than content.
#
#   THE COST IS STATED, in the idiom test-review-gate-decisions.sh uses for its
#   own canonical literal: this pins WORDING, so a legitimate reword must be
#   made in two places at once and reddens CI until it is. That is a loud false
#   red, which this repo prefers to a gate that reports clean on an inverted
#   source. `canon_table` is the one place to edit.
#
#   "BYTE-IDENTICAL" WOULD OVERSTATE IT. The comparison runs after `flat()`, so
#   it is identity up to whitespace: a re-wrap passes, a reword does not. That
#   is deliberate — this repo hard-wraps, and a raw comparison would redden on
#   every reflow — but the claim in this header, in preflight's gate list and in
#   CLAUDE.md says "after flattening" rather than "byte-identical" because the
#   weaker true claim is worth more than the stronger false one.
#
# MUST-NOT-EXIST CHECKS RUN AGAINST TWO COPIES, flattened and emphasis-stripped.
# This repo hard-wraps, so a forbidden phrase routinely straddles a line break
# and a line-scoped grep reads it as absent — a FALSE PASS. Emphasis is the same
# defect one layer in: `Ready **non-empty**` is the same instruction as `Ready
# non-empty` and was measured passing the plain-flatten veto, with a plain-text
# control that correctly failed. CLAUDE.md records this repo paying for exactly
# that once already, on `**\`sentry:\`**`.
#
# STRUCTURAL ASSERTIONS ARE WINDOW-SCOPED, NEVER FILE-WIDE. An earlier edition
# grepped the whole tracked file for COMPLETE's condition line, so the condition
# could be CANCELLED by a clause added inside COMPLETE's own section while the
# assertion stayed green. Every line-scoped check now runs against an already
# resolved window, and every window is proved non-empty AND proved to stop where
# it claims to.
#
# THE VACUITY FLOOR IS A SECTION REGISTRY, not just a number. A bare floor was
# measured not binding: deleting sections 3-7 whole left 46 of 80 assertions and
# a floor of 45, so the run printed `all green` having dropped every "must not
# have moved" constraint. `SECTIONS` declares the inventory, each section
# registers itself against it, and a declared section that never ran — or that
# ran too few assertions to be measuring anything — FAILS. The count of declared
# sections is re-derived from this file's own `section` call sites rather than
# transcribed. The numeric floor stays underneath as a coarse backstop.
#
# THE PREMISE IS ASSERTED, NOT ASSUMED. Everything above rests on `block`
# stripping BOTH labels; if it ever stripped only `ready`, the blocked issue
# would stay in-flight, §2's branch query would find its PR, and this gate's
# whole account of the bug would be wrong while every prose assertion stayed
# green. So the `block` case in `skills/github-issues/scripts/issue-claim.sh` is
# read too — the gate's second tracked file, read for that one fact.
#
# NO `-ef` PRECONDITION, deliberately, and what follows is the reasoning
# test-review-gate-decisions.sh's section 9 paid for rather than its conclusion.
# That gate needs the precondition because its subject is its OWN source, so a
# copy measures the wrong file. This gate's subjects are other tracked files,
# resolved against `git rev-parse --show-toplevel`, so running it from a copy
# still measures them — which is what a mutation harness wants. The mirror
# hazard is real and belongs to the HARNESS: mutate the tracked file in place
# and restore it. Mutating a tmpdir copy leaves every assertion here measuring
# the unmutated tracked file and every mutant reading `undetected` while proving
# nothing (the #262 lesson). `SELF_ABS` is read only to count this file's own
# `section` call sites, which is consistent under a copy either way.
#
# No `| grep -q` pipelines anywhere: grep -q closes the pipe on its first match,
# the writer takes SIGPIPE, and pipefail promotes the 141 — turning a caught
# regression into a reported miss (the #172 shape, generalised by #256). Every
# string match here reads a herestring or a file directly.
#
# NO INVENTORY NUMBER IS TRANSCRIBED. The assertion count is PRINTED by the run;
# the section inventory is enumerated beside its own count, which is the form
# CLAUDE.md sanctions. The mutation battery lives in the PR that added this gate
# (issue #282).
#
# Two tracked files. No gh, no network, no repo mutation.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-drain-terminal-states.sh
set -uo pipefail
export LC_ALL=C

# Resolved BEFORE the `cd`, because the caller's path is relative to the
# caller's cwd — the idiom scripts/test-sentry-verification.sh uses.
SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-drain-terminal-states: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/dispatch-ready/SKILL.md"
CLAIM="skills/github-issues/scripts/issue-claim.sh"

fails=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1"; }
bad() { asserts=$((asserts + 1)); echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

# --- the section registry ----------------------------------------------------
# Declared inventory. A section that never runs, or that runs too few assertions
# to be measuring anything, fails — which is what a bare numeric floor could not
# do (measured: 34 of 80 assertions deleted, still `all green`).
SECTIONS=(conjunct enumeration discriminator nonempty carveouts complete record stoppath premise)
SECTION_FLOOR=3
ASSERT_FLOOR=80
ran_names=()
ran_counts=()
cur_sec=""
sec_start=0

_close_section() {
    if [ -n "$cur_sec" ]; then
        ran_names+=("$cur_sec")
        ran_counts+=("$((asserts - sec_start))")
    fi
}
section() {
    _close_section
    case " ${SECTIONS[*]} " in
        *" $1 "*) ;;
        *) bad "section '$1' is not in the declared SECTIONS inventory" ;;
    esac
    cur_sec="$1"
    sec_start=$asserts
    echo "-- $1: $2"
}

# --- assertion helpers -------------------------------------------------------
# assert_in <haystack> <ERE> <label>   — herestring, never a pipeline
assert_in() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_wline <RAW window> <ERE> <label> — line-scoped, and the window is the
# whole point: file-wide was measured letting a rule be cancelled inside its own
# section while its assertion stayed green.
assert_wline() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_has <haystack> <FIXED string> <label> — for a literal carrying regex
# metacharacters; `(in-flight until actually MERGED, per §3)` is an ERE group.
assert_has() {
    if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_absent <haystack> <ERE> <label> — MUST-NOT-EXIST, tested against the
# text AND an emphasis-stripped copy. See the header: `Ready **non-empty**` was
# measured slipping past the plain copy.
assert_absent() {
    if grep -qE -- "$2" <<<"$1" || grep -qE -- "$2" <<<"$(emph_strip "$1")"; then
        bad "$3"
    else
        ok "$3"
    fi
}
# assert_eq <got> <want> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 — got [$1]"; fi
}

echo "dispatch-ready section 7 terminal states (issue #282)"

for f in "$SKILL" "$CLAIM"; do
    if [ -r "$f" ]; then ok "read $f"; else bad "missing file: $f"; fi
done
[ "$fails" -eq 0 ] || { echo "test-drain-terminal-states: FAILED ($fails)" >&2; exit 1; }

# raw_region <file> <start prefix> <stop prefix> — from the first line STARTING
# WITH start (inclusive) to the line before the next line starting with stop; an
# empty stop means "the next blank line". The start line is consumed with
# `next`, so a start that also matches its own stop — every heading region here
# does — cannot terminate itself on line one.
#
# LITERAL PREFIXES, NEVER REGEXES, and that is not a style choice: awk expands
# backslash escapes inside a `-v` assignment, so `\*\*Self-resolving` arrives as
# `**Self-resolving` and the leading `*` is a quantifier with nothing to repeat.
# Measured — both carve-out windows came back EMPTY, which their non-empty
# guards caught. A pattern that silently matched something ELSE would not have
# been caught, which is why the anchors are index() comparisons.
#
# `### ` as a stop does not match a `#### ` heading (character 4 differs), which
# is what lets the STALLED window span its own `####` subsection while stopping
# at `### Stop path`; `## ` likewise matches only level-2 headings.
raw_region() {
    awk -v s="$2" -v stop="$3" '
        !f && index($0, s) == 1 { f = 1; print; next }
        f && stop == "" && $0 == "" { exit }
        f && stop != "" && index($0, stop) == 1 { exit }
        f { print }' "$1"
}
# flat <text> — join wrapped lines, strip blockquote markers, squeeze runs, trim.
# `[[:space:]]`, never `[ \t]`: BSD sed reads the latter as a literal-t class
# and eats every t. Ends in `sed`/`tr`, which drain their input.
flat() {
    sed -E 's/^[[:space:]]*(> ?)+//' <<<"$1" | tr '\n' ' ' | tr -s ' ' \
        | sed -E 's/^ +//; s/ +$//'
}
# emph_strip <text> — Markdown emphasis and code ticks removed, so a veto cannot
# be walked past by bolding the forbidden phrase.
emph_strip() { tr -d '*_`' <<<"$1"; }

# --- the canon ---------------------------------------------------------------
# The decision surface, held HERE rather than derived from the file under test.
# A quoted heredoc, so nothing expands and no quote needs escaping; key and text
# are TAB-separated. This is the ONE place to edit when a decision is legitimately
# reworded — see the cost note in the header.
canon_table() {
    cat <<'CANON'
opening	In-flight zero AND dispatched zero this tick AND **nothing this loop is permitted to advance** — every Ready item held by a §4 filter, and every open PR held by the discriminator below. Nothing this loop controls can change GitHub state before the next tick: no PRs it may merge, no agents working, and dependency holds only resolve when a dep closes — with nothing in flight, only external or human action closes one. The loop is stalled, not idle; "Ready isn't empty" alone must never keep it alive.
nonempty	**The held set must be non-empty.** Nothing held, nothing in flight and no open PR is COMPLETE, which fires first and needs no confirmation tick. "Nothing to advance" satisfied vacuously — by a queue that simply finished — must never announce STALLED.
union	**"Every open PR this tick sees" is the union §2 resolves** — open PRs on in-flight branches, and open PRs on `blocked[]` issues. Both halves are load-bearing: a PR nobody enumerated cannot be held, and the second half is precisely the one #282's own state consists of.
default_row	**The last row is a default, not a catch-all to delete.** §2 holds a PR for more reasons than the rows above enumerate and will not stay exhaustive, and a table that silently answers "alive" for a shape it does not know re-creates #282 one shape at a time. Held is the right default *here* because it is the answer §2 already gives: a PR this loop may not merge is a PR it cannot advance. The two defaults are not mirror images — this one ends the loop and names the PR, the other one ticks forever and reports nothing.
conflicting	**`CONFLICTING` needs its own row, above the checks rows, and the ordering is the point.** A conflicted PR stops CI firing at all, and `no checks reported` is indistinguishable from `CI hasn't started` — `sassy-dog:pr-shepherd` records exactly that. Without the row a conflicted PR matches "checks still running" and is answered with something that can never happen, so one long-lived conflicted PR would keep a genuinely stalled queue from ever confirming STALLED.
unreadable	**A gate that could not be read is not a hold.** A PR whose checks or review outcome would not read this tick falls under this section's opening rule: live state was not verified, so the tick proves nothing — leave the loop alone and write no stall record.
carve1	- **Self-resolving holds can never trip it.** Collision holds, migration-slot holds, and deps on in-flight issues all require in-flight > 0 — the in-flight = 0 conjunct excludes them by construction.
carve2	- **A foreign claim is not a human gate.** An item skipped by the Claimed filter is another session's in-flight (`mine: false`) and resolves when that session merges, no human needed. A tick whose holds include an active foreign claim is idle, not stalled — keep looping.
carves_survive	**Both carve-outs survive the new conjunct unchanged**, and PR rows weaken neither: a self-resolving hold still requires in-flight > 0, and another session's open PR is that session's in-flight, resolving when it merges — a foreign claim is not a human gate whether it presents as an issue row or as a PR row.
confirm	**Confirm across two consecutive ticks before stopping** — a single stalled tick may be racing another session that is about to close a dependency, unblock an issue, or merge a PR. Ticks share no memory, so persist the observation next to the §5 batch manifest, in `.git/dispatch-ready-stall.json`: the held set — held issue numbers AND held PR numbers — with each one's hold root (the open `Depends on #N` it chains to, the `blocked` label, the decision gate, the Blocking finding a held PR carries).
record_src	**The record is written from the held set, never from `ready[]`**, which is what makes it reachable with Ready empty. Before #282 it was written only inside a branch that required Ready non-empty, so in the uncovered state the two-tick clock never started and there was nothing to confirm. A hold-set of nothing but PRs starts that clock exactly like any other.
stoppath	Then take the **same stop path as DRAIN COMPLETE** below — one path, never a parallel one. A held set of nothing but PRs takes that same path: it is a terminal state like any other, and the cron self-cancel below is not optional on it.
clockreset	Any tick that dispatches, merges, observes in-flight work, or sees an open PR it may still advance deletes a leftover `.git/dispatch-ready-stall.json`: progress resets the confirmation clock.
complete_cond	Ready empty AND in-flight zero → announce loudly and take the stop path below immediately — an empty queue needs no confirmation tick:
complete_note	**COMPLETE is unchanged, veto included**: an open PR still means the drain is not complete — in-flight until actually MERGED per §3, exactly as the safety rails below state it. What #282 changed is only where that veto leads. A PR this loop may not advance used to veto COMPLETE and reach no other state either; it now joins STALLED's held set.
rails	Safety rails: self-cancel ONLY on a terminal state confirmed above. For COMPLETE, anything still claimed or an open PR (in-flight until actually MERGED, per §3) means the drain is not complete. For STALLED, any dispatch, any in-flight work (mine or foreign), an open PR this loop may still advance, an empty held set, or a hold-set that changed since the recorded tick means the loop may still make progress — stay alive. An API-failure tick never self-cancels and never counts toward stall confirmation. Ticks that fire between confirmation and cancellation are no-ops, not errors: each re-runs this section and retries.
blocked_prs	- **Open PRs on `blocked[]` issues** → resolve these too, and hand them to nobody. `issue-claim.sh block` strips `in-progress`, so a blocked issue is not in-flight and the branch query above cannot see its PR at all; `gh issue view <N> --repo "$REPO" --json closedByPullRequestsReferences` names it (an OPEN entry only), the same lookup §4 already sanctions. This loop may not advance them, so they are never handed to `sassy-dog:pr-shepherd` — they are read so **§7 can see them**. A human-gated PR that nobody enumerated is not a smaller version of the §7 gap, it is a worse one: it leaves §7's held set empty, and an empty held set admits DRAIN COMPLETE, so the loop self-cancels with the PR still open (#282).
row1	| Its issue carries `blocked` | **No** — §2 already routed it to a human | held: joins the held set |
row2	| `CONFLICTING` | **No** — §2 never auto-rebases; a human resolves the conflict | held: joins the held set |
row3	| Held by a §2 review outcome — a Blocking finding, a `NO REPORT`, or a held `SKIPPED` — with its ONE §2 redispatch spent | **No** — never merged past, and nothing left to redispatch | held: joins the held set |
row4	| Checks still running, and not `CONFLICTING` | **Yes** — a later tick merges it once it goes green | keeps the loop alive |
row5	| Checks red, its issue not `blocked`, and its ONE §2 redispatch unspent | **Yes** — that redispatch is still available | keeps the loop alive |
row6	| Anything else this loop is not permitted to merge this tick | **No** — held is the default | held: joins the held set |
CANON
}
canon() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<<"$(canon_table)"; }

# assert_canon <key> <start prefix> <stop prefix> <label>
assert_canon() {
    local want got
    want="$(canon "$1")"
    got="$(flat "$(raw_region "$SKILL" "$2" "$3")")"
    if [ -z "$want" ]; then bad "$4 — no canonical text under key '$1'"; return; fi
    if [ -z "$got" ]; then bad "$4 — the paragraph did not resolve; its opening has moved"; return; fi
    if [ "$got" = "$want" ]; then ok "$4"; else bad "$4 — the text has moved"; fi
}

# --- windows, each proved non-empty AND bounded ------------------------------
# A window that silently over-runs is the failure mode CLAUDE.md records twice:
# an assertion labelled for one rule, answered by the text of another.

sec2="$(raw_region "$SKILL" '## 2. Reconcile in-flight' '## 3. Compute capacity')"
sec6="$(raw_region "$SKILL" '## 6. Tick report' '## 7. Terminal states')"
sec7="$(raw_region "$SKILL" '## 7. Terminal states' '## Guardrails')"
complete_raw="$(raw_region "$SKILL" '### DRAIN COMPLETE' '### ')"
stalled_raw="$(raw_region "$SKILL" '### DRAIN STALLED' '### ')"
gate_raw="$(raw_region "$SKILL" '### DRAIN STALLED' '#### ')"
disc_raw="$(raw_region "$SKILL" '#### The discriminator' 'Two carve-outs keep the state precise:')"
opening_raw="$(raw_region "$SKILL" 'In-flight zero AND dispatched zero' '')"
record_raw="$(raw_region "$SKILL" '**Confirm across two consecutive ticks' '```')"
announce_raw="$(raw_region "$SKILL" 'DRAIN STALLED — nothing dispatchable' '```')"
rails_raw="$(raw_region "$SKILL" 'Safety rails:' '## ')"
carvelist_raw="$(raw_region "$SKILL" 'Two carve-outs keep the state precise:' '**Both carve-outs')"
claim_block="$(raw_region "$CLAIM" '        block)' '        promote)')"

for w in sec2 sec6 sec7 complete_raw stalled_raw gate_raw disc_raw opening_raw \
         record_raw announce_raw rails_raw carvelist_raw claim_block; do
    if [ -n "${!w}" ]; then
        ok "window $w resolved"
    else
        bad "window $w is empty — every assertion scoped to it would pass vacuously"
    fi
done
[ "$fails" -eq 0 ] || { echo "test-drain-terminal-states: FAILED ($fails)" >&2; exit 1; }

sec2_flat="$(flat "$sec2")"
sec6_flat="$(flat "$sec6")"
sec7_flat="$(flat "$sec7")"
complete_flat="$(flat "$complete_raw")"
stalled_flat="$(flat "$stalled_raw")"
gate_flat="$(flat "$gate_raw")"
disc_flat="$(flat "$disc_raw")"
opening_flat="$(flat "$opening_raw")"
record_flat="$(flat "$record_raw")"
announce_flat="$(flat "$announce_raw")"
rails_flat="$(flat "$rails_raw")"

assert_absent "$complete_flat" 'In-flight zero AND dispatched zero' \
    "COMPLETE window stops before the STALLED gate"
assert_absent "$gate_flat" 'May this loop advance it' \
    "STALLED gate window stops before the discriminator table"
assert_absent "$disc_flat" 'Self-resolving holds' \
    "discriminator window stops before the carve-outs"
assert_absent "$stalled_flat" 'Stop the loop yourself' \
    "STALLED window stops before the stop path"
assert_absent "$opening_flat" 'The third conjunct' \
    "STALLED opening window is one paragraph, not the rationale below it"
assert_absent "$record_flat" 'DRAIN STALLED —' \
    "stall-record window stops before the announcement block"
assert_absent "$rails_flat" 'Ready only' \
    "safety-rails window stops before the Guardrails list"
assert_absent "$sec2_flat" 'Capacity =' \
    "section 2 window stops before section 3"
assert_absent "$sec6_flat" 'DRAIN COMPLETE' \
    "section 6 window stops before section 7"
assert_absent "$claim_block" 'ensure_label "\$READY_LABEL"' \
    "issue-claim.sh block window stops before the promote case"

# --- 1. the third conjunct ---------------------------------------------------
section conjunct "the STALLED gate is 'nothing to advance', not 'Ready non-empty'"

# The whole opening sentence, by equality. A veto on one spelling was measured
# defeated by `Ready **non-empty**`, and a presence check on the new conjunct is
# satisfied by an opening carrying BOTH.
assert_canon opening 'In-flight zero AND dispatched zero' '' \
    "STALLED's gate paragraph is unchanged (the three conjuncts, and only those)"
assert_absent "$opening_flat" 'Ready non-empty' \
    "STALLED's gate no longer requires Ready non-empty, in any emphasis"
assert_absent "$opening_flat" 'Ready still' \
    "STALLED's gate has not re-acquired a Ready test under another wording"

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

# --- 2. the enumeration the held set depends on ------------------------------
section enumeration "section 2 resolves open PRs on blocked issues, and section 7 consumes that union"

assert_canon blocked_prs '- **Open PRs on `blocked[]` issues**' '- **Failed or red PRs**' \
    "section 2's blocked-PR enumeration bullet is unchanged"
assert_canon union '**"Every open PR this tick sees" is the union' '' \
    "the discriminator defines its input as that union"
assert_wline "$sec2" '^- \*\*Open PRs on `blocked\[\]` issues\*\*' \
    "the enumeration is a top-level bullet of section 2, not a footnote elsewhere"
assert_has "$sec2_flat" 'closedByPullRequestsReferences' \
    "section 2 names the lookup that resolves a blocked issue's PR"
assert_in "$sec2_flat" 'never handed to `sassy-dog:pr-shepherd`' \
    "an enumerated blocked PR is read, never handed to the merger"
assert_in "$sec2_flat" 'admits DRAIN COMPLETE, so the loop self-cancels with the PR still open' \
    "section 2 records the false-COMPLETE harm an unenumerated PR causes"

# --- 3. the discriminator ----------------------------------------------------
section discriminator "every row is pinned, classifies, and agrees with its own answer"

assert_wline "$disc_raw" '^\| Open PR this tick \| May this loop advance it\? \| Effect \|$' \
    "the discriminator table carries its header row"

rows="$(awk '
    /^#### The discriminator/ { f = 1; next }
    f && /^Two carve-outs/ { exit }
    f && /^\|/ && $0 !~ /^\| *-+ *\|/ && $0 !~ /^\| Open PR this tick \|/ { print }' "$SKILL")"

n_canon_rows="$(grep -c '^row[0-9]' <<<"$(canon_table)")"
n_rows=0; n_held=0; n_alive=0; n_unclassified=0; n_contradictory=0; n_moved=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    n_rows=$((n_rows + 1))
    want="$(canon "row$n_rows")"
    [ "$(flat "$row")" = "$want" ] || n_moved=$((n_moved + 1))
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

# EQUALITY against the canon, in order. Accounting alone was measured accepting
# a FIFTH row that licensed merging past a `blocked` issue: it classified
# cleanly, so nothing counted it as wrong.
assert_eq "$n_rows" "$n_canon_rows" \
    "the table holds exactly the rows the canon pins ($n_canon_rows)"
assert_eq "$n_moved" 0 \
    "every row matches its canonical text, in order"
assert_eq "$n_unclassified" 0 \
    "every row classifies as held or alive ($n_rows rows read)"
assert_eq "$n_contradictory" 0 \
    "every row's answer cell agrees with its effect cell"
assert_eq "$((n_held + n_alive))" "$n_rows" \
    "held + alive accounts for every row (held $n_held, alive $n_alive)"
if [ "$n_held" -ge 2 ] && [ "$n_alive" -ge 2 ]; then
    ok "both sides of the discriminator are populated (held $n_held, alive $n_alive)"
else
    bad "the discriminator has collapsed to one side (held $n_held, alive $n_alive)"
fi

# The rows the acceptance boxes name, asserted by shape as well as by canon: the
# canon moves with a legitimate reword, these say what the row must still MEAN.
assert_wline "$disc_raw" '^\| Its issue carries `blocked` \| \*\*No\*\*.*held: joins the held set \|$' \
    "a blocked issue's open PR is HELD (acceptance 1)"
assert_wline "$disc_raw" '^\| `CONFLICTING` \| \*\*No\*\*.*held: joins the held set \|$' \
    "a CONFLICTING PR is HELD, and above the checks rows"
assert_wline "$disc_raw" '^\| Checks still running.*\| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a PR whose checks are still running keeps the loop alive (acceptance 2)"
assert_wline "$disc_raw" '^\| Checks red.*not `blocked`.*\| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a red PR whose issue is not blocked keeps the loop alive (acceptance 3)"
assert_wline "$disc_raw" '^\| Anything else this loop is not permitted to merge this tick \| \*\*No\*\*.*held: joins the held set \|$' \
    "the table ends in a default, and the default is held"

assert_canon default_row '**The last row is a default, not a catch-all' '' \
    "the default row's rationale is unchanged"
assert_canon conflicting '**`CONFLICTING` needs its own row' '' \
    "the CONFLICTING ordering rationale is unchanged"
assert_canon unreadable '**A gate that could not be read is not a hold.**' '' \
    "an unreadable gate is an unverified tick, not a hold"

assert_in "$disc_flat" 'redispatch budget is the hinge on both failure rows' \
    "the discriminator names the redispatch budget as the hinge"
assert_in "$disc_flat" 'grants exactly ONE redispatch per issue' \
    "the discriminator states the budget is exactly one redispatch"
assert_in "$disc_flat" 'a state it can still act on is not a stall' \
    "the discriminator states an actionable state is not a stall"
assert_in "$disc_flat" 'Read the redispatch budget from the issue' \
    "the discriminator says where the budget is read from"
assert_in "$disc_flat" 'No such comment means the budget is unspent' \
    "the discriminator gives the budget's default reading"
assert_in "$disc_flat" 'Read the review outcome from the PR body' \
    "the discriminator reads the review outcome from the PR body, as section 2 does"

# --- 4. the held set must be non-empty ---------------------------------------
section nonempty "'nothing to advance' cannot be satisfied vacuously"

assert_canon nonempty '**The held set must be non-empty.**' '' \
    "the non-empty rule is unchanged"
assert_in "$gate_flat" 'The held set must be non-empty' \
    "STALLED requires a non-empty held set"
assert_in "$gate_flat" 'Nothing held, nothing in flight and no open PR is COMPLETE' \
    "an empty held set with nothing in flight is COMPLETE, not STALLED"
assert_in "$gate_flat" 'must never announce STALLED' \
    "a vacuously satisfied conjunct must never announce STALLED"

# --- 5. both carve-outs, unchanged -------------------------------------------
section carveouts "both carve-outs survive, and the list cannot grow a third"

assert_canon carve1 '- **Self-resolving holds' '- **A foreign claim' \
    "carve-out 1 (self-resolving holds) is unchanged"
assert_canon carve2 '- **A foreign claim' '' \
    "carve-out 2 (a foreign claim is not a human gate) is unchanged"
assert_canon carves_survive '**Both carve-outs survive the new conjunct unchanged**' '' \
    "the statement that both survive is unchanged"

# Counted on `^- `, not on the bold prefix: an unbolded third bullet was
# measured slipping past `^- \*\*` — and a verbatim restatement of the #282 bug
# is exactly what such a bullet would say.
n_carve="$(grep -c '^- ' <<<"$carvelist_raw")"
assert_eq "$n_carve" 2 \
    "the carve-out list holds exactly two bullets — a third would weaken them unseen"
assert_in "$(flat "$carvelist_raw")" 'Two carve-outs keep the state precise' \
    "the carve-out list still introduces itself as two"

# --- 6. COMPLETE is unchanged, veto included ---------------------------------
section complete "COMPLETE keeps its condition, its announcement and its open-PR veto"

assert_canon complete_cond 'Ready empty AND in-flight zero → announce loudly' '' \
    "COMPLETE's condition paragraph is unchanged, in full"
assert_canon complete_note '**COMPLETE is unchanged, veto included**' '' \
    "COMPLETE's note about where the veto now leads is unchanged"
assert_canon rails 'Safety rails: self-cancel ONLY on a terminal state' '' \
    "the safety rails are unchanged, in full"
assert_wline "$complete_raw" '^DRAIN COMPLETE — Ready is empty and nothing is in flight\.$' \
    "COMPLETE's verbatim announcement is unchanged"
assert_has "$rails_flat" \
    'anything still claimed or an open PR (in-flight until actually MERGED, per §3) means the drain is not complete.' \
    "the safety rail still vetoes COMPLETE on an open PR"
assert_has "$rails_flat" \
    'an open PR this loop may still advance, an empty held set, or a hold-set that changed since the recorded tick means the loop may still make progress — stay alive.' \
    "the rails' STALLED clause still ENDS in stay-alive, with all three conditions inside it"

# --- 7. the record is written from the held set ------------------------------
section record "the two-tick clock is reachable, and still two ticks"

assert_canon confirm '**Confirm across two consecutive ticks before stopping**' '' \
    "the two-tick confirmation paragraph is unchanged"
assert_canon record_src '**The record is written from the held set' '' \
    "the record's source paragraph is unchanged"
assert_canon clockreset 'Any tick that dispatches, merges, observes in-flight work' '' \
    "what resets the confirmation clock is unchanged"
assert_in "$record_flat" 'held issue numbers AND held PR numbers' \
    "the stall record persists held PR numbers alongside held issue numbers"
assert_wline "$record_raw" '^  `stall: suspected — nothing in flight and nothing this loop may advance; an identical hold-set next tick ends the loop`\.$' \
    "the suspected-stall line no longer claims Ready is non-empty"
assert_in "$record_flat" 'PR rows alongside issue rows, each naming the PR and the gate holding it' \
    "the confirmed announcement names each held PR and its gate"

# --- 8. one stop path, two terminal states -----------------------------------
section stoppath "still two terminal states, still one stop path, and the tick report shows held PRs"

assert_canon stoppath 'Then take the **same stop path as DRAIN COMPLETE**' '' \
    "the stop-path paragraph is unchanged"
assert_in "$sec7_flat" 'A drain loop ends itself in exactly two states' \
    "#282 adds coverage, not a third terminal state"
assert_wline "$announce_raw" '^DRAIN STALLED — nothing dispatchable, nothing in flight, and nothing this loop may advance:$' \
    "the STALLED announcement's headline covers a PR-only held set"
assert_wline "$announce_raw" '^  PR #279 \(#273\) → open, issue blocked \(3 Blocking review findings, redispatch spent\)$' \
    "the announcement carries a PR row naming the PR and its gate (acceptance 1)"
assert_absent "$announce_flat" 'all Ready items gate on human action' \
    "the announcement no longer asserts Ready holds the held set"
assert_wline "$sec6" '^holds:.*· PR #1699 \(open, #1698 blocked\)$' \
    "the tick report's holds line carries held PRs, not issues alone"
assert_in "$sec6_flat" 'carries \*\*held PRs alongside held issues\*\*' \
    "section 6 states that held PRs render on the holds line"

# --- 9. the premise -----------------------------------------------------------
section premise "block strips BOTH labels, which is what makes the whole account true"

assert_has "$claim_block" '--remove-label "$READY_LABEL"' \
    "issue-claim.sh block strips ready"
assert_has "$claim_block" '--remove-label "$INPROG_LABEL"' \
    "issue-claim.sh block strips in-progress — the half that empties in-flight"
assert_has "$claim_block" '--add-label "$BLOCKED_LABEL"' \
    "issue-claim.sh block adds blocked"

# --- the registry and the floor ----------------------------------------------
_close_section
cur_sec=""

n_section_calls="$(grep -c '^section ' "$SELF_ABS")"
assert_eq "$n_section_calls" "${#SECTIONS[@]}" \
    "every declared section has exactly one call site (${#SECTIONS[@]} declared)"

for want in "${SECTIONS[@]}"; do
    found=0
    count=0
    i=0
    while [ "$i" -lt "${#ran_names[@]}" ]; do
        if [ "${ran_names[$i]}" = "$want" ]; then
            found=1
            count="${ran_counts[$i]}"
        fi
        i=$((i + 1))
    done
    if [ "$found" -eq 0 ]; then
        bad "declared section '$want' never ran — its block has been deleted"
    elif [ "$count" -lt "$SECTION_FLOOR" ]; then
        bad "section '$want' ran only $count assertions (floor $SECTION_FLOOR) — it is no longer measuring anything"
    else
        ok "section '$want' ran $count assertions"
    fi
done

# A coarse backstop underneath the registry, not the primary guard — a bare
# floor was measured NOT binding (34 of 80 assertions deleted, still green),
# which is why the registry above exists.
if [ "$asserts" -lt "$ASSERT_FLOOR" ]; then
    echo "test-drain-terminal-states: only $asserts assertions ran (floor $ASSERT_FLOOR) — a window or a block is silently matching nothing" >&2
    exit 1
fi

if [ "$fails" -ne 0 ]; then
    echo "test-drain-terminal-states: FAILED ($fails of $asserts assertions)" >&2
    exit 1
fi
echo "drain terminal-state tests: all green ($asserts assertions)"
