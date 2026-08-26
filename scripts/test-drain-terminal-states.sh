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
# WORSE THAN THE BUG. §2's only PR discovery was "open PRs from those branches" —
# the branches of IN-FLIGHT issues — and `block` strips `in-progress`, so in
# #282's own state the tick enumerated zero PRs. A held set that is empty
# because nothing was looked at is indistinguishable from one that is empty
# because nothing is held: STALLED is then forbidden by the non-empty rule while
# COMPLETE is admitted, and the loop announces DRAIN COMPLETE and self-cancels
# with a human-gated PR still open. The forever-tick at least never claimed to
# be finished.
#
# THE SET HAS TO BE ONE SET, and that is the second thing a reader will try to
# simplify apart. COMPLETE's veto and §7's held set must range over the SAME
# PRs: any PR that can veto COMPLETE but can never enter the held set gives
# Ready-empty + in-flight-zero + held-empty, which is #282 one shape over — and
# an unqualified "any open PR vetoes COMPLETE" produces exactly that the moment
# a Dependabot PR, a hand-opened PR or another session's PR is sitting there.
# BOTH HALVES ALSO HAVE TO SPAN BOTH PATHS: the blocked set is `blocked[]` only
# on the boardless path, and a bullet written for one path is invisible on the
# other, which is how a board repo would have kept the bug with every assertion
# here green.
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
# that can never happen. Rows 2 to 5 cannot fire at the moment STALLED is
# decided — in-flight zero empties the branch half of the union, so row 1
# matches first — and §7 states that rather than leaving it to be re-derived;
# the gate pins the statement, because a reader who works it out will otherwise
# either trust the rows as live or delete them as dead.
#
# HOW THIS GATE IS BOUND, AND WHY IT IS BOUND IN THREE LAYERS. Its first edition
# asserted presence only, and a review measured meaning-inverting rewrites
# passing it at exit 0 — writing the bug back as `Ready **non-empty**`, which a
# plain flatten cannot see; appending a table row licensing a merge past a
# `blocked` issue; inverting the safety rails; and deleting assertion blocks
# under a floor that did not bind. Every one KEPT the sentence an assertion
# greps for and QUALIFIED it. The second edition pinned whole paragraphs by
# equality against canonical literals — and a second review defeated THAT by
# INSERTING A SIBLING PARAGRAPH beside a pinned one, writing #282's bug back
# four lines under the canon forbidding it. Equality bounds the paragraph it
# holds and says nothing about the one next to it. So:
#
#   LAYER 1, CANON. Each decision paragraph is compared for equality after
#   flattening against text held in `canon_table`. Bounds REWORDING.
#   LAYER 2, INVENTORY. The ordered list of paragraph openers, bullet openers,
#   table rows and headings in §7, and of bullet openers in §2, is itself
#   canonical. Bounds INSERTION, DELETION and REORDERING. Its first edition
#   claimed to bound "a new paragraph anywhere in §7, whatever it says" and did
#   not: a review measured three shapes writing #282's bug back at exit 0 — a
#   TWO-SPACE NESTED bullet (the matcher was `^- `), a row appended to §7's
#   STOP-PATH table (only the discriminator's rows were anchored), and a
#   paragraph GLUED TO A CLOSING FENCE with no blank line (a fence set
#   `prev = 0`, so the next line opened no block). All three are covered now —
#   list markers match at any indent WITH the indent in the key, every table in
#   the window is inventoried, and a closing fence opens a block — which is why
#   the claim below is worded as what it was measured to do rather than as what
#   it was meant to do.
#   LAYER 3, CONSUMPTION. Every key in `canon_table` must be consumed by exactly
#   one assertion. Deleting an assertion block therefore fails even if its
#   section registration goes with it, because its canon entries go unconsumed.
#
#   THE COST IS STATED, in the idiom test-review-gate-decisions.sh uses for its
#   own canonical literal: this pins WORDING and STRUCTURE, so a legitimate
#   reword or a new paragraph in §7 must be made in two places at once and
#   reddens CI until it is. That is a loud false red, which this repo prefers to
#   a gate that reports clean on an inverted source. `canon_table` is the one
#   place to edit, and re-deriving its inventory entries is mechanical.
#
#   "BYTE-IDENTICAL" WOULD OVERSTATE IT. The comparison runs after `flat()`, so
#   it is identity up to whitespace: a re-wrap passes, a reword does not. The
#   inventory keeps each opener's first words only, so it is identity up to
#   those. Both claims are stated that way here, in preflight's gate list and in
#   CLAUDE.md, because the weaker true claim is worth more than the stronger
#   false one.
#
#   KNOWN LIMITS, stated rather than patched.
#   (1) A paragraph that no canon key holds is bound only by its first six words
#       and by whatever presence assertion happens to mention it — so an
#       APPENDED SENTENCE is enough, not merely a reword. That is why the canon
#       now holds the BRANCH BULLETS an agent executes (the two stall-record
#       branches, the two cron self-cancel branches) and not only the rationale
#       paragraphs: a review measured "→ announce STALLED and take the stop path
#       immediately" replacing the no-record branch, deleting the two-tick clock
#       while canon `confirm` still pinned the paragraph that mandates it.
#   (2) Deleting a section, its registry entry AND its canon entries together is
#       three coordinated edits in three places, and nothing here catches that —
#       only the deliberateness of it.
#   (3) The inventory keys are regenerated by hand when §7 legitimately grows,
#       and a regeneration that is not read is a rubber stamp.
#   (4) This block's own assertions sit under the derived floor (`registry` is a
#       declared member), so deleting the registry drops the run below it — but
#       a gate cannot verify its own guard from inside that guard. The floor is
#       the backstop; there is no layer beneath it.
#
# MUST-NOT-EXIST CHECKS RUN AGAINST TWO COPIES, flattened and emphasis-stripped.
# This repo hard-wraps, so a forbidden phrase routinely straddles a line break
# and a line-scoped grep reads it as absent — a FALSE PASS. Emphasis is the same
# defect one layer in: `Ready **non-empty**` is the same instruction as `Ready
# non-empty` and was measured passing the plain-flatten veto. CLAUDE.md records
# this repo paying for exactly that once already, on `**`sentry:`**`.
#
# STRUCTURAL ASSERTIONS ARE WINDOW-SCOPED, NEVER FILE-WIDE. An earlier edition
# grepped the whole tracked file for COMPLETE's condition line, so the condition
# could be CANCELLED by a clause added inside COMPLETE's own section while the
# assertion stayed green. Every line-scoped check now runs against an already
# resolved window; every window is proved non-empty AND proved to stop where it
# claims to, including `sec7`, whose stop is a heading somebody may rename.
# TABLE-ROW PATTERNS ARE ANCHORED `^[[:space:]]*\|`, because a row indented by
# ONE SPACE renders identically, passes markdownlint, and was measured slipping
# past a `^\|` filter while licensing a merge past a `blocked` issue.
#
# EXAMPLE IDENTIFIERS ARE MATCHED BY SHAPE, not by literal. `PR #279 (#273)` is
# a worked example; renumbering it changes no decision, and a gate that reddens
# on it teaches the next author that this gate cries wolf. The exact-literal
# treatment is reserved for `canon_table`.
#
# THE VACUITY FLOOR IS A SECTION REGISTRY WITH PER-SECTION MINIMUMS. A bare
# number was measured not binding twice over: deleting five assertion blocks
# left 46 of the 80 assertions then running, under a floor of 45, and deleting
# 14 assertions from the largest section left the total higher still — both
# runs printed "all green". A THIRD measurement is why the prologue and this
# file's own registry block are declared members rather than preamble: their
# assertions used to run with `cur_sec` empty, so no minimum covered them, and
# deleting the entire window-STOP block — the one added after a review made
# `sec7` run silently to EOF — left the gate at exit 0.
# `SECTIONS` declares each section beside the count it must reach, which is the
# form CLAUDE.md sanctions for a count (members enumerated beside it), and
# `ASSERT_FLOOR` is DERIVED as their sum rather than transcribed. An earlier
# edition also compared the declared count to this file's own `section` call
# sites; that was a file-to-itself comparison of the kind this header rules out
# for the canon, one `sed` updated both sides, and it is gone.
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
# nothing (the #262 lesson).
#
# No `| grep -q` pipelines anywhere: grep -q closes the pipe on its first match,
# the writer takes SIGPIPE, and pipefail promotes the 141 — turning a caught
# regression into a reported miss (the #172 shape, generalised by #256). Every
# string match here reads a herestring or a file directly.
#
# NO INVENTORY NUMBER IS TRANSCRIBED. The assertion count is PRINTED by the run;
# the section inventory is enumerated beside its own counts, which is the form
# CLAUDE.md sanctions. The mutation battery lives in the PR that added this gate
# (issue #282).
#
# Two tracked files. No gh, no network, no repo mutation.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-drain-terminal-states.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-drain-terminal-states: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/dispatch-ready/SKILL.md"
CLAIM="skills/github-issues/scripts/issue-claim.sh"
OPENER_WORDS=6

fails=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1"; }
bad() { asserts=$((asserts + 1)); echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

# --- the section registry ----------------------------------------------------
# `name:minimum`. Members enumerated beside their counts, which is the form
# CLAUDE.md sanctions; ASSERT_FLOOR is their SUM, derived below rather than
# transcribed. A section that never runs, or that runs fewer assertions than it
# declares, FAILS — which is what a bare numeric floor could not do (measured
# twice: a whole section deleted, and 14 assertions deleted from the largest).
SECTIONS=(windows:28 conjunct:10 enumeration:10 discriminator:25 nonempty:4
          carveouts:5 complete:8 record:9 stoppath:15 premise:3 registry:12)
SECTION_MIN_TOTAL=0
for _s in "${SECTIONS[@]}"; do
    SECTION_MIN_TOTAL=$((SECTION_MIN_TOTAL + ${_s##*:}))
done
ASSERT_FLOOR=$SECTION_MIN_TOTAL

ran_names=()
ran_counts=()
cur_sec=""
sec_start=0
consumed=""

_close_section() {
    if [ -n "$cur_sec" ]; then
        ran_names+=("$cur_sec")
        ran_counts+=("$((asserts - sec_start))")
    fi
}
section() {
    _close_section
    case " ${SECTIONS[*]} " in
        *" $1:"*) ;;
        *) bad "section '$1' is not in the declared SECTIONS inventory" ;;
    esac
    cur_sec="$1"
    sec_start=$asserts
    echo "-- $1: $2"
}
note_consumed() { consumed="$consumed $1"; }

# --- assertion helpers -------------------------------------------------------
# assert_in <haystack> <ERE> <label>   — herestring, never a pipeline
assert_in() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_wline <RAW window> <ERE> <label> — line-scoped, and the window is the
# whole point: file-wide was measured letting a rule be cancelled inside its own
# section while its assertion stayed green.
assert_wline() {
    # A flattened blob has no newline in it, and handing one here turns every
    # `^…$` anchor into a pattern that can never match — a silent pass for a
    # must-exist. The contract was a comment; now it is a check.
    if [ "${1#*$'\n'}" = "$1" ]; then
        bad "$3 — assert_wline was handed a single-line blob; pass a RAW window"
        return
    fi
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

# The prologue is a REGISTRY MEMBER, not an unfloored preamble. Measured: its
# assertions ran while `cur_sec` was empty, so no per-section minimum covered
# them and deleting the whole window-stop block left the gate at exit 0 — the
# very block added after a review made `sec7` run silently to EOF.
section windows "every window resolves, and stops where it claims to"

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
raw_region() {
    awk -v s="$2" -v stop="$3" '
        !f && index($0, s) == 1 { f = 1; print; next }
        f && stop == "" && $0 == "" { exit }
        f && stop != "" && index($0, stop) == 1 { exit }
        f { print }' "$1"
}
# flat <text> — join wrapped lines, strip blockquote markers, squeeze runs, trim.
# `[[:space:]]`, never `[ \t]`: BSD sed reads the latter as a literal-t class.
flat() {
    sed -E 's/^[[:space:]]*(> ?)+//' <<<"$1" | tr '\n' ' ' | tr -s ' ' \
        | sed -E 's/^ +//; s/ +$//'
}
# emph_strip <text> — Markdown emphasis and code ticks removed, so a veto cannot
# be walked past by bolding the forbidden phrase.
emph_strip() { tr -d '*_`' <<<"$1"; }

# openers <text> — the first OPENER_WORDS words of each blank-line-delimited
# block opener, joined by ` ~ `. Fenced blocks collapse to their opening fence.
# WORDS, not characters: awk under LC_ALL=C counts BYTES while the canon was
# generated counting CHARACTERS, and `§` is two bytes — measured, the two
# disagreed on every line carrying one. Words also survive a re-wrap, which
# changes where a line ENDS, not the words it starts with.
# This is layer 2: an inserted paragraph changes the list whatever it says.
openers() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                printf "%s%s", (c++ ? " ~ " : ""), s }
        BEGIN { prev = 1 }
        /^[ \t]*```/ { if (!fence) { emit(); fence = 1; prev = 0 }
                       else { fence = 0; prev = 1 }
                       next }
        fence { next }
        $0 == "" { prev = 1; next }
        { if (prev) emit(); prev = 0 }' <<<"$1"
}
# bullet_openers <text> — same idea for top-level bullets, which an opener list
# cannot see: bullets in one list are adjacent, so an inserted one adds no block.
bullet_openers() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s, ind) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                ind = match($0, /[^ \t]/) - 1
                                printf "%s%d:%s", (c++ ? " ~ " : ""), ind, s }
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^[ \t]*[-*+] / { emit() }' <<<"$1"
}
# table_rows <text> — the same idea for table rows, in EVERY table in the
# window. The `^[[:space:]]*\|` anchoring lesson had been applied to the
# discriminator table and to nothing else, so a row appended to §7's stop-path
# table — "Announce and finish — do not cancel" — was measured invisible.
#
# THE PATTERN IS INLINE IN EACH OF THESE, NEVER PASSED THROUGH `-v`: awk expands
# escapes in a `-v` assignment, so `\|` arrives as a bare `|` and the ERE becomes
# an alternation with an empty branch. Measured — a shared helper taking the
# pattern that way emitted nothing at all, and its canon comparison failed
# loudly rather than passing, which is the only reason it was cheap. Same trap
# as raw_region's, one layer over; the duplication here is the fix.
table_rows() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s, ind) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                ind = match($0, /[^ \t]/) - 1
                                printf "%s%d:%s", (c++ ? " ~ " : ""), ind, s }
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^[ \t]*\|/ { emit() }' <<<"$1"
}
# heading_list <text> — every heading line, joined. A third terminal state added
# as a `###` subsection changes this while "exactly two states" still reads true.
# `^#+ ` and not `^#`: a wrapped line beginning `#282 changed is only where …` is
# not a heading, and an earlier canon baked exactly that in as one — caught by
# markdownlint's MD018, which is the only reason it did not become the shape the
# inventory defends.
heading_list() {
    awk '/^#+ / { printf "%s%s", (c++ ? " ~ " : ""), $0 }' <<<"$1"
}

# --- the canon ---------------------------------------------------------------
# The decision surface AND the structure, held HERE rather than derived from the
# file under test. A quoted heredoc, so nothing expands and no quote needs
# escaping; key and value are TAB-separated. This is the ONE place to edit when
# §7 legitimately changes — see the cost note in the header.
canon_table() {
    cat <<'CANON'
opening	In-flight zero AND dispatched zero this tick AND **nothing this loop is permitted to advance** — every Ready item held by a §4 filter, and every open PR held by the discriminator below. Nothing this loop controls can change GitHub state before the next tick: no PRs it may merge, no agents working, and dependency holds only resolve when a dep closes — with nothing in flight, only external or human action closes one. The loop is stalled, not idle; "Ready isn't empty" alone must never keep it alive.
third_conjunct	**The third conjunct is "nothing to advance", and it replaced "Ready non-empty"** — that difference is the whole of #282. Ready empty, in-flight zero and an open unmerged PR was covered by NEITHER terminal state: COMPLETE is vetoed by the open PR, and STALLED could not fire on an empty queue. The loop ticked forever, reporting the state accurately and doing nothing (observed 2026-08-26 on #273 / PR #279; cancelled by hand). The action that creates the state is the action that hides it — `issue-claim.sh block` strips `ready` and `in-progress` together, so recording "a human must decide this" is precisely what removes the issue from the one set the old conjunct consulted.
rejected_fix	**Deleting that conjunct outright would have been the wrong fix**, and re-deriving it that way is the tempting simplification here: an open PR is not automatically a human gate. One whose checks are still running or red can advance on its own, and firing STALLED there cancels a loop that was about to make progress.
nonempty	**The held set must be non-empty.** Nothing held, nothing in flight and no open PR is COMPLETE, which fires first and needs no confirmation tick. "Nothing to advance" satisfied vacuously — by a queue that simply finished — must never announce STALLED.
union	**"Every open PR this tick sees" is the union §2 resolves** — open PRs on in-flight branches, and open PRs on blocked issues. Both halves are load-bearing: a PR nobody enumerated cannot be held, and the second half is precisely the one #282's own state consists of. Their state comes from `sassy-dog:pr-shepherd`'s `poll-prs.sh --once <PR>…`, which returns `mergeable`, `mergeStateStatus` and the check counts in one pass; the judgement below stays here, the way §4 keeps its intersection judgement while borrowing `gh pr view`. **Both halves of that invocation are load-bearing.** Without `--once` it is watch mode, which blocks for up to an hour — the "a tick that waits is a loop that stopped" rule two sections up. Without the explicit PR numbers `--once` falls back to every open PR in the repo, which is exactly the widening the paragraph above forbids.
veto_identity	**That union is also the set COMPLETE's veto ranges over, and the identity is the invariant.** A PR that can veto COMPLETE but can never enter the held set gives Ready empty, in-flight zero and a held set that is empty — COMPLETE vetoed, STALLED forbidden, ticking forever. That is #282 exactly, one shape over, and it is what an unqualified "any open PR vetoes COMPLETE" reading produces the moment a Dependabot PR, a hand-opened PR with no issue, or another session's PR is sitting there. So the veto is scoped to this union and never to every open PR in the repo. Widen one half without the other and the forever-tick comes back; narrow one without the other and the loop self-cancels on work it is still holding.
blocked_wide	**The blocked half is deliberately REPO-WIDE, and that is a decision rather than an oversight.** `queue-snapshot.sh` returns blocked issues as bare numbers — open, `blocked`-labelled, no assignee and no labels — so a tick genuinely cannot tell an issue this loop demoted from one a human blocked by hand, and `issue-claim.sh block` leaves the assignee rather than clearing it. Rather than filter on a signal neither section can read, take them all: over-including ends the loop LOUDLY, naming the PR and the gate holding it, and a human who disagrees restarts the drain. Under-including is the failure this whole section exists to close. The exclusion that matters is untouched — a Dependabot PR, or a hand-opened PR whose issue is neither in-flight nor blocked, is in neither half of the union and vetoes nothing.
ask	Ask it of every one of them, take the **first matching row**, and carry the answer per PR into the held set:
rows_unreachable	**Rows 2 to 6 cannot fire at the moment STALLED is decided, and that is by construction rather than by accident.** STALLED's first conjunct is in-flight zero, which empties the branch half of the union — so every PR still enumerable carries `blocked`, and row 1 matches it first. The argument is exhaustive over the union, so it reaches the default row too: at that instant nothing falls through to it. This is the same shape as the self-resolving carve-out below, and it is stated for the same reason: a reader who works it out later will otherwise read the rows below row 1 as live guarantees, or delete them as dead prose. They are neither. They classify held-versus-advanceable for the two OTHER consumers of this table — §6's `holds:` line, which renders on every tick including ticks with work in flight, and the safety rails' "an open PR this loop may still advance" — and they are what stops a later widening of §2's enumeration from silently answering "alive" for a shape nobody classified. Delete them and that widening becomes a silent #282; treat them as reachable at STALLED time and the reasoning above them is wrong.
default_row	**The last row is a default, not a catch-all to delete.** §2 holds a PR for more reasons than the rows above enumerate and will not stay exhaustive, and a table that silently answers "alive" for a shape it does not know re-creates #282 one shape at a time. Held is the right default *here* because it is the answer §2 already gives: a PR this loop may not merge is a PR it cannot advance. The two defaults are not mirror images: held ends the loop and names the PR wherever it fires, alive ticks forever and reports nothing. (Which of them fires at STALLED-decision time is a separate question, answered by the paragraph above — there, row 1 has already matched.)
conflicting	**`CONFLICTING` needs its own row, above the checks rows, and the ordering is the point.** A conflicted PR stops CI firing at all, and `no checks reported` is indistinguishable from `CI hasn't started` — `sassy-dog:pr-shepherd` records exactly that. Without the row a conflicted PR matches "checks still running" and is answered with something that can never happen: §6's `holds:` line would report it as advancing on every tick, and the rails would read it as a PR this loop may still advance. It is NOT what lets a stalled queue confirm — at STALLED-decision time the paragraph below applies and row 1 has already matched — and saying so here would contradict it.
budget_hinge	**The redispatch budget is the hinge on both failure rows**, so read this before "simplifying" the rows into fewer. §2 grants exactly ONE redispatch per issue, taken on a later tick; while it is unspent this loop still has an action of its own, and a state it can still act on is not a stall. Once it is spent §2 demotes to `blocked`, which is why the label is the usual way a held PR presents — and why the review-outcome row is not redundant beside it: the label is a write this loop performs, the finding is a fact it reads, and a demotion not yet written must never read as advanceable. It is also why the red-checks row asks for the budget and not for the label alone: an unspent budget is what makes a red PR advanceable, while a spent one whose demotion has not been written yet matches no row above and falls to the default. Unknown is not clear.
unreadable	**A gate that could not be read is not a hold**, and this is not in tension with "unknown is not clear" two paragraphs up — the two answer different questions. An unknown *state that was read* (a shape no row names) is held: the loop has no action for it. State that *could not be read at all* is not a fact about the PR, it is a failed tick, and it falls under this section's opening rule: live state was not verified, so the tick proves nothing — leave the loop alone and write no stall record.
carve1	- **Self-resolving holds can never trip it.** Collision holds, migration-slot holds, and deps on in-flight issues all require in-flight > 0 — the in-flight = 0 conjunct excludes them by construction.
carve2	- **A foreign claim is not a human gate.** An item skipped by the Claimed filter is another session's in-flight (`mine: false`) and resolves when that session merges, no human needed. A tick whose holds include an active foreign claim is idle, not stalled — keep looping.
carves_survive	**Both carve-outs survive the new conjunct unchanged**, and PR rows weaken neither: a self-resolving hold still requires in-flight > 0, and another session's open PR is that session's in-flight, resolving when it merges. A foreign claim is therefore not a human gate, and the union above cannot turn one into a PR row either — a foreign in-flight issue is `mine: false` and not blocked, so neither half of the union reaches it. The safety rails carry the same rule for the tick as a whole.
confirm	**Confirm across two consecutive ticks before stopping** — a single stalled tick may be racing another session that is about to close a dependency, unblock an issue, or merge a PR. Ticks share no memory, so persist the observation next to the §5 batch manifest, in `.git/dispatch-ready-stall.json`: the held set — held issue numbers AND held PR numbers — with each one's hold root (the open `Depends on #N` it chains to, the `blocked` label, the decision gate, the Blocking finding a held PR carries).
matches_exactly	**"Matches exactly" compares the identifiers and each one's hold ROOT, never the rendered sentence.** Two honest ticks word the same hold differently, and a comparison over free text never converges; a comparison over identifiers alone confirms a stall across two genuinely different states, since a PR whose gate changed between ticks is still the same number. A record written before this section grew PR rows carries issue numbers only: it cannot match a hold-set containing a PR, so it is discarded and rewritten, which costs one extra tick and never a false confirmation.
record_src	**The record is written from the held set, never from `ready[]`**, which is what makes it reachable with Ready empty. Before #282 it was written only inside a branch that required Ready non-empty, so in the uncovered state the two-tick clock never started and there was nothing to confirm. A hold-set of nothing but PRs starts that clock exactly like any other.
bullet_norecord	- **No record, or the recorded hold-set differs from this tick's** → write this tick's hold-set and finish normally, appending to the tick report: `stall: suspected — nothing in flight and nothing this loop may advance; an identical hold-set next tick ends the loop`.
bullet_matches	- **Record matches this tick's hold-set exactly** → STALLED is confirmed. Delete the record and announce loudly, naming the reason **per held item** so the human knows exactly what unlocks the queue — PR rows alongside issue rows, each naming the PR and the gate holding it:
stoppath	Then take the **same stop path as DRAIN COMPLETE** below — one path, never a parallel one. A held set of nothing but PRs takes that same path: it is a terminal state like any other, and the cron self-cancel below is not optional on it.
clockreset	Any tick that dispatches, merges, observes in-flight work, or sees an open PR it may still advance deletes a leftover `.git/dispatch-ready-stall.json`: progress resets the confirmation clock.
bullet_onematch	- **Exactly one match** → `CronDelete <id>`, then append to the report — after COMPLETE: `Loop <id> cancelled — run groom-backlog to refill Ready and start a new drain when there's more to ship.`; after STALLED: `Loop <id> cancelled — resolve the gate(s), then restart the drain.`
bullet_ambiguous	- **Zero, multiple, or ambiguous matches** → delete NOTHING. Announce the terminal state, list the candidate ids, and tell the user to `CronDelete` the right one. Deleting the wrong job is worse than a few extra no-op ticks.
complete_cond	Ready empty AND in-flight zero AND **no open PR this loop tracks** → announce loudly and take the stop path below immediately — an empty queue needs no confirmation tick:
complete_note	**COMPLETE is unchanged, veto included** — the third conjunct above IS the veto, stated where the instruction is rather than three paragraphs below it. An open PR this loop tracks still means the drain is not complete, in-flight until actually MERGED per §3, exactly as the safety rails restate it. A veto a reader reaches only after "announce loudly and take the stop path immediately" is the corrective §2 warns about: one that never runs. In #282's own state both of the old conjuncts were true, so the rule as written told the loop to self-cancel. What #282 changed is only where that veto leads. A PR this loop may not advance used to veto COMPLETE and reach no other state either; it now joins STALLED's held set, and the veto ranges over exactly the set that held set is drawn from.
rails	Safety rails: self-cancel ONLY on a terminal state confirmed above. For COMPLETE, anything still claimed or an open PR this loop tracks — the union §7's discriminator ranges over, in-flight until actually MERGED per §3 — means the drain is not complete; the veto and the held set must range over the same set, or the state they disagree about ticks forever. For STALLED, any dispatch, any in-flight work (mine or foreign), an open PR this loop may still advance, an empty held set, or a hold-set that changed since the recorded tick means the loop may still make progress — stay alive. An API-failure tick never self-cancels and never counts toward stall confirmation. Ticks that fire between confirmation and cancellation are no-ops, not errors: each re-runs this section and retries.
blocked_prs	- **Open PRs on blocked issues** → resolve these too, and hand them to nobody. **With `board:`** the blocked set is the board's cards carrying the `blocked` label; **without a board** it is `blocked[]` from the snapshot above. Both paths, like every other rule in this section and in §4 — a bullet written for one path only is invisible on the other, and the half it omits is the half that goes dark. `issue-claim.sh block` strips `in-progress`, so a blocked issue is not in-flight and the branch query above cannot see its PR at all; `gh issue view <N> --repo "$REPO" --json closedByPullRequestsReferences` names it (an OPEN entry only), the same lookup §4 already sanctions. **Known limit — and it bites hardest exactly here:** that field sees only PRs carrying a closing keyword, and this population (a redispatch PR, one opened by hand) is the likeliest to lack one, so fall back to the `*/issue-N-*` branch and never read an empty result as "no PR" — an unenumerated PR is silent and terminal. **Bounded** like §4's sibling lookup, and stated honestly: up to TWO calls per blocked issue per tick where the branch fallback is needed, and the snapshot's `--limit` bounds only the boardless path — the board path is bounded by the board's own blocked column; if that cost ever bites under `/loop`, it degrades into "live state could not be verified", which is this fix's own failure mode wearing the bug's face. This loop may not advance these PRs, so they are never handed to `sassy-dog:pr-shepherd` — they are read so **§7 can see them**. A human-gated PR that nobody enumerated is not a smaller version of the §7 gap, it is a worse one: it leaves §7's held set empty, and an empty held set admits DRAIN COMPLETE, so the loop self-cancels with the PR still open (#282).
row1	| Its issue carries `blocked` | **No** — §2 already routed it to a human | held: joins the held set |
row2	| `CONFLICTING` | **No** — §2 never auto-rebases; a human resolves the conflict | held: joins the held set |
row3	| Held by a §2 review outcome — a Blocking finding, a `NO REPORT`, or a held `SKIPPED` — with its ONE §2 redispatch spent | **No** — never merged past, and nothing left to redispatch | held: joins the held set |
row4	| Checks still running, and not `CONFLICTING` | **Yes** — a later tick merges it once it goes green | keeps the loop alive |
row5	| Checks red, its issue not `blocked`, and its ONE §2 redispatch unspent | **Yes** — that redispatch is still available | keeps the loop alive |
row6	| Anything else this loop is not permitted to merge this tick | **No** — held is the default | held: joins the held set |
sec7_openers	## 7. Terminal states — drain ~ A drain loop ends itself in ~ ### DRAIN COMPLETE ~ Ready empty AND in-flight zero AND ~ ```text ~ **COMPLETE is unchanged, veto included** — ~ ### DRAIN STALLED ~ In-flight zero AND dispatched zero this ~ **The third conjunct is "nothing to ~ **Deleting that conjunct outright would have ~ **The held set must be non-empty.** ~ #### The discriminator — may this ~ **"Every open PR this tick sees" ~ **That union is also the set ~ **The blocked half is deliberately REPO-WIDE, ~ Ask it of every one of ~ | Open PR this tick | ~ **Rows 2 to 6 cannot fire ~ **The last row is a default, ~ **`CONFLICTING` needs its own row, above ~ **The redispatch budget is the hinge ~ **Read the review outcome from the ~ **A gate that could not be ~ Two carve-outs keep the state precise: ~ - **Self-resolving holds can never trip ~ **Both carve-outs survive the new conjunct ~ **Confirm across two consecutive ticks before ~ **"Matches exactly" compares the identifiers and ~ **The record is written from the ~ - **No record, or the recorded ~ ```text ~ Then take the **same stop path ~ Any tick that dispatches, merges, observes ~ ### Stop path — both terminal ~ Stop the loop yourself, according to ~ | Mode | Recognize it by ~ **Cron self-cancel.** Find the loop's job ~ - **Exactly one match** → `CronDelete ~ Safety rails: self-cancel ONLY on a
sec7_bullets	0:- **Self-resolving holds can never trip ~ 0:- **A foreign claim is not ~ 0:- **No record, or the recorded ~ 0:- **Record matches this tick's hold-set ~ 0:- **Exactly one match** → `CronDelete ~ 0:- **Zero, multiple, or ambiguous matches**
sec7_tablerows	0:| Open PR this tick | ~ 0:| --- | --- | --- ~ 0:| Its issue carries `blocked` | ~ 0:| `CONFLICTING` | **No** — §2 ~ 0:| Held by a §2 review ~ 0:| Checks still running, and not ~ 0:| Checks red, its issue not ~ 0:| Anything else this loop is ~ 0:| Mode | Recognize it by ~ 0:| --- | --- | --- ~ 0:| **Self-paced loop** (ScheduleWakeup) | This ~ 0:| **Cron / fixed interval** (CronCreate-backed) ~ 0:| **Manual invocation** | No loop
sec2_bullets	0:- **Open PRs from those branches** ~ 0:- **Open PRs on blocked issues** ~ 0:- **Failed or red PRs** → ~ 0:- **Open PRs not yet reviewed, ~ 0:- **A review dispatched that never ~ 0:- **PRs carrying a Blocking review ~ 0:- **`CONFLICTING` PRs** → never auto-rebase;
sec7_headings	## 7. Terminal states — drain complete, drain stalled ~ ### DRAIN COMPLETE ~ ### DRAIN STALLED ~ #### The discriminator — may this loop advance it? ~ ### Stop path — both terminal states
CANON
}
canon() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<<"$(canon_table)"; }

# assert_canon <key> <start prefix> <stop prefix> <label>
assert_canon() {
    local want got
    note_consumed "$1"
    want="$(canon "$1")"
    got="$(flat "$(raw_region "$SKILL" "$2" "$3")")"
    if [ -z "$want" ]; then bad "$4 — no canonical text under key '$1'"; return; fi
    if [ -z "$got" ]; then bad "$4 — the paragraph did not resolve; its opening has moved"; return; fi
    if [ "$got" = "$want" ]; then ok "$4"; else bad "$4 — the text has moved"; fi
}
# assert_canon_value <key> <got> <label>
assert_canon_value() {
    local want
    note_consumed "$1"
    want="$(canon "$1")"
    if [ -z "$want" ]; then bad "$3 — no canonical value under key '$1'"; return; fi
    if [ "$2" = "$want" ]; then ok "$3"; else bad "$3 — the structure has moved"; fi
}

# --- windows, each proved non-empty AND bounded ------------------------------
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
carvelist_flat="$(flat "$carvelist_raw")"

# Every window stops where it claims to. `sec7`, `announce_raw` and
# `carvelist_raw` had only a non-empty check until a review measured renaming
# `## Guardrails` making `sec7` run silently to EOF at exit 0.
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
assert_absent "$sec7_flat" 'Hard cap .max_in_flight' \
    "section 7 window stops before the Guardrails list, whatever that heading is called"
assert_absent "$announce_flat" 'same stop path as DRAIN COMPLETE' \
    "announcement window stops at the closing fence"
assert_absent "$carvelist_flat" 'Both carve-outs survive' \
    "carve-out list window stops before the paragraph after it"
assert_absent "$claim_block" 'ensure_label "\$READY_LABEL"' \
    "issue-claim.sh block window stops before the promote case"

# --- 1. the third conjunct ---------------------------------------------------
section conjunct "the STALLED gate is 'nothing to advance', not 'Ready non-empty'"

assert_canon opening 'In-flight zero AND dispatched zero' '' \
    "STALLED's gate paragraph is unchanged (the three conjuncts, and only those)"
assert_absent "$opening_flat" 'Ready non-empty' \
    "STALLED's gate no longer requires Ready non-empty, in any emphasis"
assert_absent "$opening_flat" 'Ready still' \
    "STALLED's gate has not re-acquired a Ready test under another wording"

assert_canon third_conjunct '**The third conjunct is "nothing to advance"' '' \
    "the third-conjunct paragraph is unchanged"
assert_canon rejected_fix '**Deleting that conjunct outright would have been the wrong fix**' '' \
    "the rejected-fix paragraph is unchanged"
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
section enumeration "section 2 resolves open PRs on blocked issues, on BOTH paths"

assert_canon blocked_prs '- **Open PRs on blocked issues**' '- **Failed or red PRs**' \
    "section 2's blocked-PR enumeration bullet is unchanged"
assert_canon union '**"Every open PR this tick sees" is the union' '' \
    "the discriminator defines its input as that union"
assert_canon veto_identity "**That union is also the set COMPLETE's veto" '' \
    "the veto and the held set are stated to range over the same set"
assert_canon blocked_wide '**The blocked half is deliberately REPO-WIDE' '' \
    "the blocked half is stated repo-wide, with its reason"
assert_wline "$sec2" '^- \*\*Open PRs on blocked issues\*\*' \
    "the enumeration is a top-level bullet of section 2, not a footnote elsewhere"
assert_has "$sec2_flat" 'closedByPullRequestsReferences' \
    "section 2 names the lookup that resolves a blocked issue's PR"
assert_in "$sec2_flat" 'With .board:..+ the blocked set is the board.s cards carrying the .blocked. label' \
    "the enumeration covers the board path, not the boardless one alone"
assert_in "$sec2_flat" 'without a board..+ it is .blocked\[\]. from the snapshot' \
    "the enumeration covers the boardless path too"
assert_in "$sec2_flat" 'never handed to `sassy-dog:pr-shepherd`' \
    "an enumerated blocked PR is read, never handed to the merger"
assert_in "$sec2_flat" 'admits DRAIN COMPLETE, so the loop self-cancels with the PR still open' \
    "section 2 records the false-COMPLETE harm an unenumerated PR causes"

# --- 3. the discriminator ----------------------------------------------------
section discriminator "every row is pinned, classifies, and agrees with its own answer"

assert_wline "$disc_raw" '^[[:space:]]*\| Open PR this tick \| May this loop advance it\? \| Effect \|$' \
    "the discriminator table carries its header row"
assert_canon ask 'Ask it of every one of them, take the **first matching row**' '' \
    "the first-matching-row rule is unchanged"

# Anchored `^[[:space:]]*\|`: a row indented by ONE SPACE renders identically,
# passes markdownlint, and was measured slipping past a `^\|` filter.
# From the already-resolved, already-proved-bounded window rather than from the
# whole file: re-deriving a window beside a proved one is the shape this gate
# spends its prologue refusing.
rows="$(awk '
    /^[[:space:]]*\|/ && $0 !~ /^[[:space:]]*\| *-+ *\|/ && $0 !~ /\| Open PR this tick \|/ { print }' <<<"$disc_raw")"

n_canon_rows="$(grep -c '^row[0-9]' <<<"$(canon_table)")"
n_rows=0; n_held=0; n_alive=0; n_unclassified=0; n_contradictory=0; n_moved=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    n_rows=$((n_rows + 1))
    note_consumed "row$n_rows"
    [ "$(flat "$row")" = "$(canon "row$n_rows")" ] || n_moved=$((n_moved + 1))
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

assert_wline "$disc_raw" '^[[:space:]]*\| Its issue carries `blocked` \| \*\*No\*\*.*held: joins the held set \|$' \
    "a blocked issue's open PR is HELD (acceptance 1)"
assert_wline "$disc_raw" '^[[:space:]]*\| `CONFLICTING` \| \*\*No\*\*.*held: joins the held set \|$' \
    "a CONFLICTING PR is HELD, and above the checks rows"
assert_wline "$disc_raw" '^[[:space:]]*\| Checks still running.*\| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a PR whose checks are still running keeps the loop alive (acceptance 2)"
assert_wline "$disc_raw" '^[[:space:]]*\| Checks red.*not `blocked`.*\| \*\*Yes\*\*.*keeps the loop alive \|$' \
    "a red PR whose issue is not blocked keeps the loop alive (acceptance 3)"
assert_wline "$disc_raw" '^[[:space:]]*\| Anything else this loop is not permitted to merge this tick \| \*\*No\*\*.*held: joins the held set \|$' \
    "the table ends in a default, and the default is held"

assert_canon default_row '**The last row is a default, not a catch-all' '' \
    "the default row's rationale is unchanged"
assert_canon conflicting '**`CONFLICTING` needs its own row' '' \
    "the CONFLICTING ordering rationale is unchanged"
assert_canon rows_unreachable '**Rows 2 to 6 cannot fire at the moment' '' \
    "the statement that rows 2 to 6 cannot fire at STALLED time is unchanged"
assert_canon budget_hinge '**The redispatch budget is the hinge on both failure rows**' '' \
    "the redispatch-budget paragraph is unchanged"
assert_canon unreadable '**A gate that could not be read is not a hold**' '' \
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
assert_in "$disc_flat" 'poll-prs.sh' \
    "the discriminator names where a PR's state comes from"

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
assert_in "$carvelist_flat" 'Two carve-outs keep the state precise' \
    "the carve-out list still introduces itself as two"

# --- 6. COMPLETE is unchanged, veto included ---------------------------------
section complete "COMPLETE keeps its condition, its announcement and its open-PR veto"

assert_canon complete_cond 'Ready empty AND in-flight zero AND' '' \
    "COMPLETE's condition paragraph is unchanged, in full"
assert_canon complete_note '**COMPLETE is unchanged, veto included**' '' \
    "COMPLETE's note about where the veto now leads is unchanged"
assert_canon rails 'Safety rails: self-cancel ONLY on a terminal state' '' \
    "the safety rails are unchanged, in full"
assert_wline "$complete_raw" '^DRAIN COMPLETE — Ready is empty and nothing is in flight\.$' \
    "COMPLETE's verbatim announcement is unchanged"
assert_has "$rails_flat" \
    'anything still claimed or an open PR this loop tracks' \
    "the safety rail still vetoes COMPLETE on an open PR this loop tracks"
assert_has "$rails_flat" \
    'the veto and the held set must range over the same set' \
    "the rails carry the one-set invariant"
assert_has "$rails_flat" \
    'an open PR this loop may still advance, an empty held set, or a hold-set that changed since the recorded tick means the loop may still make progress — stay alive.' \
    "the rails' STALLED clause still ENDS in stay-alive, with all three conditions inside it"
assert_in "$complete_flat" 'open PR this loop tracks still means the drain is not complete' \
    "COMPLETE's note keeps the veto, scoped to the tracked set"

# --- 7. the record is written from the held set ------------------------------
section record "the two-tick clock is reachable, and still two ticks"

assert_canon confirm '**Confirm across two consecutive ticks before stopping**' '' \
    "the two-tick confirmation paragraph is unchanged"
assert_canon matches_exactly '**"Matches exactly" compares the identifiers' '' \
    "what the hold-set comparison compares is unchanged"
assert_canon record_src '**The record is written from the held set' '' \
    "the record's source paragraph is unchanged"
assert_canon clockreset 'Any tick that dispatches, merges, observes in-flight work' '' \
    "what resets the confirmation clock is unchanged"
assert_canon bullet_norecord '- **No record, or the recorded hold-set differs' '- **Record matches' \
    "the no-record branch bullet is unchanged"
assert_canon bullet_matches "- **Record matches this tick's hold-set exactly**" '' \
    "the record-matches branch bullet is unchanged"
assert_in "$record_flat" 'held issue numbers AND held PR numbers' \
    "the stall record persists held PR numbers alongside held issue numbers"
assert_wline "$record_raw" '^  `stall: suspected — nothing in flight and nothing this loop may advance; an identical hold-set next tick ends the loop`\.$' \
    "the suspected-stall line no longer claims Ready is non-empty"
assert_in "$record_flat" 'PR rows alongside issue rows, each naming the PR and the gate holding it' \
    "the confirmed announcement names each held PR and its gate"

# --- 8. structure: two terminal states, one stop path, and the inventories ----
section stoppath "the shape of section 7 is itself canonical"

assert_canon stoppath 'Then take the **same stop path as DRAIN COMPLETE**' '' \
    "the stop-path paragraph is unchanged"
assert_canon bullet_onematch '- **Exactly one match**' '- **Zero, multiple' \
    "the one-match cron-cancel branch bullet is unchanged"
assert_canon bullet_ambiguous '- **Zero, multiple, or ambiguous matches**' '' \
    "the ambiguous-match cron-cancel branch bullet is unchanged"
assert_in "$sec7_flat" 'A drain loop ends itself in exactly two states' \
    "#282 adds coverage, not a third terminal state"

# LAYER 2. An inserted paragraph writes #282's bug back four lines under the
# canon forbidding it and every equality check still passes — measured. These
# three lists are what make insertion, deletion and reordering visible.
assert_canon_value sec7_openers "$(openers "$sec7")" \
    "section 7's paragraph inventory is unchanged — no paragraph inserted, dropped or moved"
assert_canon_value sec7_bullets "$(bullet_openers "$sec7")" \
    "section 7's bullet inventory is unchanged — bullets are adjacent, so an opener list cannot see them"
assert_canon_value sec7_tablerows "$(table_rows "$sec7")" \
    "section 7's table rows are unchanged, in EVERY table — not the discriminator's alone"
assert_canon_value sec2_bullets "$(bullet_openers "$sec2")" \
    "section 2's bullet inventory is unchanged"
assert_canon_value sec7_headings "$(heading_list "$sec7")" \
    "section 7's headings are unchanged — a third terminal state would be a new one"

# Example identifiers by SHAPE: renumbering a worked example changes no decision.
assert_wline "$announce_raw" '^DRAIN STALLED — nothing dispatchable, nothing in flight, and nothing this loop may advance:$' \
    "the STALLED announcement's headline covers a PR-only held set"
assert_wline "$announce_raw" '^  PR #[0-9]+ \(#[0-9]+\) → open, issue blocked \(.*redispatch spent\)$' \
    "the announcement carries a PR row naming the PR and its gate (acceptance 1)"
assert_absent "$announce_flat" 'all Ready items gate on human action' \
    "the announcement no longer asserts Ready holds the held set"
assert_wline "$sec6" '^holds:.*· PR #[0-9]+ \(open, #[0-9]+ blocked\)$' \
    "the tick report's holds line carries held PRs, not issues alone"
assert_in "$sec6_flat" 'carries \*\*held PRs alongside held issues\*\*' \
    "section 6 states that held PRs render on the holds line"
assert_in "$sec6_flat" 'drawn from §2.s enumeration' \
    "section 6 sources held PRs from section 2, which runs on every tick"

# --- 9. the premise -----------------------------------------------------------
section premise "block strips BOTH labels, which is what makes the whole account true"

assert_has "$claim_block" '--remove-label "$READY_LABEL"' \
    "issue-claim.sh block strips ready"
assert_has "$claim_block" '--remove-label "$INPROG_LABEL"' \
    "issue-claim.sh block strips in-progress — the half that empties in-flight"
assert_has "$claim_block" '--add-label "$BLOCKED_LABEL"' \
    "issue-claim.sh block adds blocked"

# --- the registry, the consumption check, and the floor ----------------------
# `registry` is itself a declared member, so this block's own assertions sit
# UNDER the derived floor: deleting it drops the run below `ASSERT_FLOOR` even
# though the loop that would have reported the deletion is what was deleted.
# The per-section loop skips `registry`, whose count is not closed until after
# it runs.
section registry "the canon is fully consumed and every declared section ran"

# LAYER 3. Every canonical entry must be consumed by exactly one assertion, so
# deleting an assertion block fails even if its section registration goes with
# it — its canon entries go unconsumed.
canon_keys="$(awk -F'\t' 'NF { print $1 }' <<<"$(canon_table)" | sort)"
used_all="$(tr ' ' '\n' <<<"$consumed" | sed '/^$/d' | sort)"
used_uniq="$(tr ' ' '\n' <<<"$consumed" | sed '/^$/d' | sort -u)"
assert_eq "$used_all" "$used_uniq" \
    "every canonical entry is consumed at most once"
assert_eq "$used_uniq" "$canon_keys" \
    "every canonical entry is consumed by an assertion"

for entry in "${SECTIONS[@]}"; do
    want="${entry%%:*}"
    min="${entry##*:}"
    [ "$want" = "registry" ] && continue
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
    elif [ "$count" -lt "$min" ]; then
        bad "section '$want' ran $count assertions, below its declared $min — it has been trimmed"
    else
        ok "section '$want' ran $count assertions (declared $min)"
    fi
done

_close_section
i=0
while [ "$i" -lt "${#ran_names[@]}" ]; do
    if [ "${ran_names[$i]}" = "registry" ]; then
        for entry in "${SECTIONS[@]}"; do
            [ "${entry%%:*}" = "registry" ] || continue
            if [ "${ran_counts[$i]}" -lt "${entry##*:}" ]; then
                echo "test-drain-terminal-states: the registry block ran ${ran_counts[$i]} assertions, below its declared ${entry##*:}" >&2
                fails=$((fails + 1))
            fi
        done
    fi
    i=$((i + 1))
done

# Derived from the per-section minimums above, never transcribed.
if [ "$asserts" -lt "$ASSERT_FLOOR" ]; then
    echo "test-drain-terminal-states: only $asserts assertions ran (derived floor $ASSERT_FLOOR) — a window or a block is silently matching nothing" >&2
    exit 1
fi

if [ "$fails" -ne 0 ]; then
    echo "test-drain-terminal-states: FAILED ($fails of $asserts assertions)" >&2
    exit 1
fi
echo "drain terminal-state tests: all green ($asserts assertions)"
