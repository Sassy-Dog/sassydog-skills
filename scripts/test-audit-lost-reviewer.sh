#!/usr/bin/env bash
# test-audit-lost-reviewer.sh — pins assess-it's audit-mode lost-reviewer
# backstop: the per-domain outcome ledger, the rule that a dark domain is never
# scored clean, the ledger's position BEFORE the approval prompt, and the fact
# that a dark domain is surfaced rather than turned into a veto.
#
# THE BUG. The nine `*-reviewer` agents serve TWO orchestrators, and only one of
# them scored a reviewer that came back with nothing. `agents/pr-review-
# orchestrator.md` Step 5 marks such a surface `!`, never a tick, and names it
# on every run. Audit mode had no equivalent, so a reviewer that returned
# nothing was indistinguishable from one that found nothing (issue #284).
#
# WHY AUDIT MODE IS THE WORSE PLACE FOR IT. A diff-scoped report is read
# in-session while the context is live, and a hole in it costs a re-run. Audit
# mode WRITES: its artefact is a filed Epic and its child issues, which becomes
# the durable record of what is wrong with the repo. A lost `security-reviewer`
# there yields a backlog that omits an entire domain and READS COMPLETE to
# everyone who finds it later. Nobody learns, because nothing about the artefact
# says a domain went dark.
#
# THE HARM LANDS AT THE PREVIEW, NOT AT THE REPORT, and that is what a later
# "just add the delivery rule to audit mode" sweep will get wrong. `assess-it`
# already never files silently — Phase 4 prints the full Epic + child-issue
# preview and files only on approval. The human was always the gate; they were
# simply not being told a domain went dark. So the requirement is POSITIONAL:
# the dark domains must be named IN the preview and BEFORE the approval prompt.
# A rule that lands after the ask does not prevent the bad outcome, and one that
# lands in Phase 5 documents a backlog that has already been filed.
#
# AND IT IS NOT A VETO. Filing still proceeds on approval. A rule that blocked
# filing on a dark domain would be the opposite failure — an audit that cannot
# deliver the findings it does hold because one agent timed out — and #284 rules
# it out in as many words. Both halves are pinned, because either one alone is
# wrong.
#
# THIS IS THE SIBLING OF THE DIFF-SCOPED RULE, NOT ITS SOURCE. #283 scoped the
# `!` consequence to diff-scoped mode DELIBERATELY and recorded the residue in
# `orchestration.md` rather than widening its own scope; this gate's subject is
# that residue being replaced by the real rule rather than left beside one.
# `agents/pr-review-orchestrator.md` is read for exactly ONE fact — that its own
# bullet survives — and nothing else about that file is pinned here.
# test-review-gate-decisions.sh owns it.
#
# HOW THIS GATE IS BOUND, AND WHY IT IS BOUND THE WAY test-drain-terminal-
# states.sh IS. That gate is the freshest precedent in this repo and it was
# defeated three times before it held: presence-only assertions lost to
# KEEP-THE-SENTENCE-AND-QUALIFY-IT; whole-paragraph equality lost to INSERTING A
# SIBLING PARAGRAPH beside a pinned one; a hand-picked SUBSET of paragraphs lost
# five review rounds running, each finding another unpinned paragraph that could
# invert a pinned one. THE SUBSET WAS THE DEFECT, NOT THE CHOICE OF SUBSET. So:
#
#   LAYER 1, CANON. Every blank-line block of every pinned window is compared
#   for equality after flattening — prose, list blocks and table blocks alike,
#   so a bullet body and a table cell are as pinned as a paragraph — plus every
#   FENCED block, with `#N` normalised so renumbering a worked example cannot
#   redden the gate. The fences are not inert here either: Phase 4's ```text
#   fence IS the coverage block the run prints, and a parenthetical added inside
#   it ("omit this block when every domain returned") would restore #284 in full
#   while every prose assertion stayed green.
#   LAYER 2, INVENTORY. The ordered lists of block openers, bullets, ordered-list
#   items, table rows and headings — for BOTH FILES WHOLE, not merely for the
#   pinned windows. Bounds INSERTION, DELETION and REORDERING, including the
#   four shapes that defeated the precedent's first inventory: a nested bullet,
#   an appended table row, a paragraph glued to a closing fence and a line glued
#   under a heading. Whole-file rather than per-section because these two files
#   are small and are entirely about this one flow: `## Core Principle`,
#   `## Workflow` and `## Reference Files` can each contradict Phase 4 from
#   outside it, which is the Guardrails hazard the precedent records. The
#   ORDERED-LIST inventory is the one that carries #284's own decision, Phase 4
#   being an ordered list whose ITEM ORDER is the fix.
#   LAYER 3, CONSUMPTION. Every canon key is consumed by exactly one assertion,
#   and every window's block and fence counts must equal its canon entry counts
#   — so deleting an assertion cannot pass by deleting its canon entry with it.
#
# THE COST IS STATED, in the precedent's idiom: this pins WORDING and STRUCTURE
# across two whole files, so a legitimate reword or a new bullet in either must
# be made in two places at once and reddens CI until it is. That is a loud false
# red, which this repo prefers to a gate reporting clean on an inverted source.
# `canon_table` is the one place to edit. "BYTE-IDENTICAL" WOULD OVERSTATE IT:
# the comparison runs after flattening, so it is identity up to whitespace — a
# re-wrap passes, a reword does not — and the inventories keep each opener's
# first words only.
#
# THERE IS DELIBERATELY NO PROSE VETO HERE, and that asymmetry with the sibling
# gates is what a later sweep will try to close. Two veto editions were built
# for test-review-gate-decisions.sh and BOTH reported clean on inverted sources:
# a polarity classifier that was inert by construction in the very windows it
# guarded, and a six-verb affirmative that reddened six correct edits while
# missing two natural rewords. A veto that works needs a forward segmentation
# pass, which is a different change. Canon plus inventory already answers the
# question a veto would ask — any rewrite changes a block, any addition changes
# an opener list — so a veto here would add risk and no coverage. The only
# must-not-exist checks are for the #283 residue note's own literals, which is a
# LITERAL DELETION being verified rather than a polarity judgement, and they run
# against flattened AND emphasis-stripped copies because this repo hard-wraps
# and `**Known gap**` is the same instruction as `Known gap`.
#
# THE PREMISE IS ASSERTED, NOT ASSUMED. The ledger says "every domain in the
# table above", so it is complete only if that table is the reviewers this
# plugin actually ships. If the map drifted from `agents/*-reviewer.md` the
# ledger would range over a stale set, and every prose assertion here would stay
# green while a whole domain had no row to be dark in. The map's rows are
# therefore compared to the shipped agent files as an EQUALITY, which is its own
# vacuity floor — a membership test cannot tell "nothing to report" from
# "nothing measured" — over a count floor beneath it. The map itself is NOT
# canon-pinned: it changes whenever a reviewer is added, the premise equality
# already reddens then, and pinning it twice would redden twice for one edit.
#
# THE VACUITY FLOOR IS A SECTION REGISTRY WITH PER-SECTION MINIMUMS, and it
# VALIDATES ITS OWN INPUTS BEFORE ANY ARITHMETIC TOUCHES THEM. A bare number was
# measured not binding three separate ways in the precedent. Worse, `set -u`
# inside `$(( ))` does not behave the same on bash 5 and on /bin/bash 3.2 — the
# shell CLAUDE.md tells developers to run preflight on — where a deleted digit
# aborts the summing loop and drops every later summand, and an unset floor
# exits 0 having run ZERO assertions, which a preflight-shaped wrapper reports
# as PASS. Every token is validated explicitly for that reason. The registry
# block's own minimum is held APART from the SECTIONS array, so deleting the
# block cannot also shrink the floor by exactly what the deletion removed.
#
# NO `| grep -q` PIPELINE ANYWHERE: grep -q closes the pipe on its first match,
# the writer takes SIGPIPE, and pipefail promotes the 141 — turning a caught
# regression into a reported miss (the #172 shape, generalised by #256). Every
# string match here reads a herestring or a file directly.
#
# NO INVENTORY NUMBER IS TRANSCRIBED. The assertion count is PRINTED by the run;
# the section inventory is enumerated beside its own counts, which is the form
# CLAUDE.md sanctions for a count. The mutation battery lives in the PR that
# added this gate (issue #284).
#
# KNOWN LIMITS, stated rather than patched.
#   (1) `agents/pr-review-orchestrator.md` is read for ONE fact. Everything else
#       about that file is #280's gate's subject, and duplicating it here would
#       make one edit redden two gates with two different explanations.
#   (2) `references/github-issue-ops.md` and `assessment-rubric.md` are unread.
#       A rule hoisted into either could contradict Phase 4 unseen — the same
#       shape the precedent records for its own §5 and §1.
#   (3) The canon values are regenerated by hand when these sections legitimately
#       change, and a regeneration that is not read is a rubber stamp. That is
#       the cost of pinning sections whole, and it is why a failure names the
#       block key and the first characters of what it found.
#   (4) A gate cannot verify its own guard from inside that guard. The derived
#       floor is the backstop under the registry block; there is no layer
#       beneath the floor.
#   (5) Markdownlint stays load-bearing for a malformed table (MD055/MD056),
#       which this gate reads as content rather than as structure.
#
# Three tracked files read, one of them for a single fact, plus a listing of
# `agents/`. No gh, no network, no repo mutation.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-audit-lost-reviewer.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-audit-lost-reviewer: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/assess-it/SKILL.md"
ORCH="skills/assess-it/orchestration.md"
PRORCH="agents/pr-review-orchestrator.md"
OPENER_WORDS=6
NEVER=$'\001NEVER-MATCHES'

fails=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1"; }
bad() { asserts=$((asserts + 1)); echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

# --- the section registry ----------------------------------------------------
# `name:minimum`. Members enumerated beside their counts, which is the form
# CLAUDE.md sanctions; ASSERT_FLOOR is their SUM, derived below rather than
# transcribed. A section that never runs, or that runs fewer assertions than it
# declares, FAILS — which a bare numeric floor cannot do.
SECTIONS=(windows:17 canon:41 inventory:9 residue:5 sibling:2 premise:3)
# Held OUTSIDE the array on purpose: while the registry block's own minimum was
# a summand, deleting the block AND its entry shrank the floor by exactly what
# the deletion removed, so two edits retired layer 3 at exit 0.
REGISTRY_MIN=2
# EVERY token is validated before arithmetic touches it. On /bin/bash 3.2,
# deleting one digit (`canon:41` -> `canon:`) aborts the `for` inside `$(( ))`,
# silently drops every later summand and still exits 0; deleting REGISTRY_MIN is
# worse — exit 0 with ZERO assertions run. This is the last layer, so it
# validates rather than assumes.
SECTION_MIN_TOTAL=0
for _s in "${SECTIONS[@]}"; do
    case "$_s" in
        *:*) ;;
        *) echo "test-audit-lost-reviewer: SECTIONS member '$_s' has no ':' minimum" >&2; exit 1 ;;
    esac
    _min="${_s##*:}"
    case "$_min" in
        ''|*[!0-9]*) echo "test-audit-lost-reviewer: SECTIONS member '$_s' has a non-numeric minimum" >&2; exit 1 ;;
    esac
    SECTION_MIN_TOTAL=$((SECTION_MIN_TOTAL + _min))
done
case "${REGISTRY_MIN:-}" in
    ''|*[!0-9]*) echo "test-audit-lost-reviewer: REGISTRY_MIN must be a number" >&2; exit 1 ;;
esac
ASSERT_FLOOR=$((SECTION_MIN_TOTAL + REGISTRY_MIN))

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
    # `registry` is legal without being a SECTIONS member: its minimum is held
    # in REGISTRY_MIN so that deleting the block cannot also shrink the floor.
    case " ${SECTIONS[*]} " in
        *" $1:"*) ;;
        *) [ "$1" = "registry" ] || bad "section '$1' is not in the declared SECTIONS inventory" ;;
    esac
    cur_sec="$1"
    sec_start=$asserts
    echo "-- $1: $2"
}
note_consumed() { consumed="$consumed $1 "; }

# --- assertion helpers -------------------------------------------------------
# assert_has <haystack> <FIXED string> <label> — for a literal carrying regex
# metacharacters.
assert_has() {
    if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_absent <haystack> <ERE> <label> — MUST-NOT-EXIST, tested against the
# text AND an emphasis-stripped copy, and FAILING CLOSED on a malformed pattern:
# grep exits 2 on an invalid ERE and an `if grep … || grep …` reads that as
# "not found", which is a veto failing open — the one direction a veto must
# never fail.
assert_absent() {
    local rc_plain rc_stripped
    grep -qE -- "$2" <<<"$1"; rc_plain=$?
    grep -qE -- "$2" <<<"$(emph_strip "$1")"; rc_stripped=$?
    if [ "$rc_plain" -ge 2 ] || [ "$rc_stripped" -ge 2 ]; then
        bad "$3 — the pattern is not a valid ERE, so this check measured nothing"
    elif [ "$rc_plain" -eq 0 ] || [ "$rc_stripped" -eq 0 ]; then
        bad "$3"
    else
        ok "$3"
    fi
}
# assert_eq <got> <want> <label> — the got/want tails are truncated, because a
# canon block is a paragraph and an untruncated mismatch buries the key.
assert_eq() {
    if [ "$1" = "$2" ]; then
        ok "$3"
    else
        bad "$3
        got : ${1:0:140}
        want: ${2:0:140}"
    fi
}
assert_nonempty() {
    if [ -n "$1" ]; then ok "$2"; else bad "$2 — empty"; fi
}

# --- extractors --------------------------------------------------------------
# raw_region <file> <start prefix> <stop prefix> — from the first line STARTING
# WITH start (inclusive) to the line before the next line starting with stop; an
# empty stop means "the next blank line". The start line is consumed with
# `next`, so a start that also matches its own stop cannot terminate itself on
# line one.
#
# LITERAL PREFIXES, NEVER REGEXES: awk expands backslash escapes inside a `-v`
# assignment, so a pattern arrives mangled and can silently match something
# else. The anchors are index() comparisons for that reason.
raw_region() {
    awk -v s="$2" -v stop="$3" '
        !f && index($0, s) == 1 { f = 1; print; next }
        f && stop == "" && $0 == "" { exit }
        f && stop != "" && index($0, stop) == 1 { exit }
        f { print }' "$1"
}
# region_stop_line <file> <start prefix> <stop prefix> — the first line AFTER the
# region. A window that runs silently to EOF prints nothing here, which is how
# "stops where it claims to" is measured rather than assumed.
region_stop_line() {
    awk -v s="$2" -v stop="$3" '
        !f && index($0, s) == 1 { f = 1; next }
        f && stop == "" && $0 == "" { print "<blank>"; exit }
        f && stop != "" && index($0, stop) == 1 { print; exit }' "$1"
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
# block opener, joined by ` ~ `. Fenced blocks collapse to their fences. WORDS,
# not characters: awk under LC_ALL=C counts BYTES and an em dash is multi-byte.
# BOTH fence delimiters are emitted, because text appended to a CLOSING fence
# was invisible to the precedent's first inventory. A HEADING closes the block
# it opens, so the next line starts a new one — the identical root cause,
# measured there as a line glued under a heading escaping all four inventories.
openers() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                printf "%s%s", (c++ ? " ~ " : ""), s }
        BEGIN { prev = 1 }
        /^[ \t]*```/ { emit()
                       if (!fence) { fence = 1; prev = 0 } else { fence = 0; prev = 1 }
                       next }
        fence { next }
        $0 == "" { prev = 1; next }
        { if (prev) emit()
          prev = ($0 ~ /^#+ /) }' <<<"$1"
}
# bullet_openers <text> — same idea for bullets at any indent, which an opener
# list cannot see: bullets in one list are adjacent, so an inserted one adds no
# block. The INDENT is part of the key, so a nested bullet is visible too.
bullet_openers() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s, ind) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                ind = match($0, /[^ \t]/) - 1
                                printf "%s%d:%s", (c++ ? " ~ " : ""), ind, s }
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^[ \t]*[-*+] / { emit() }' <<<"$1"
}
# ordered_openers <text> — the same for ordered-list items. Phase 4 IS an
# ordered list and its item ORDER is the decision this gate exists for: the
# ledger before the approval ask, never after it.
ordered_openers() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s, ind) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                ind = match($0, /[^ \t]/) - 1
                                printf "%s%d:%s", (c++ ? " ~ " : ""), ind, s }
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^[ \t]*[0-9]+\. / { emit() }' <<<"$1"
}
# table_rows <text> — every table row in the window. Anchored `^[[:space:]]*\|`,
# because a row indented by ONE SPACE renders identically, passes markdownlint,
# and was measured slipping past a `^\|` filter.
#
# THE PATTERN IS INLINE, NEVER PASSED THROUGH `-v`: awk expands escapes in a
# `-v` assignment, so `\|` arrives as a bare `|` and the ERE becomes an
# alternation with an empty branch that matches every line.
table_rows() {
    awk -v n="$OPENER_WORDS" '
        function emit(  i, s, ind) { s = ""
                                for (i = 1; i <= n && i <= NF; i++) s = s (i > 1 ? " " : "") $i
                                ind = match($0, /[^ \t]/) - 1
                                printf "%s%d:%s", (c++ ? " ~ " : ""), ind, s }
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^[ \t]*\|/ { emit() }' <<<"$1"
}
# heading_list <text> — every heading line. `^#+ ` and not `^#`: a wrapped line
# beginning `#284 changed …` is not a heading. Fence-aware, or the first `#`
# comment inside a ```bash block reads as one.
heading_list() {
    awk '
        /^[ \t]*```/ { fence = !fence; next }
        !fence && /^#+ / { printf "%s%s", (c++ ? " ~ " : ""), $0 }' <<<"$1"
}
# section_blocks <text> — one flattened block per line, fences EXCLUDED.
section_blocks() {
    awk '
        function flush(  t) { if (n) { t = buf
                                       gsub(/[ \t]+/, " ", t); sub(/^ +/, "", t); sub(/ +$/, "", t)
                                       print t; buf = ""; n = 0 } }
        /^[ \t]*```/ { flush(); fence = !fence; next }
        fence { next }
        $0 == "" { flush(); next }
        { line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line)
          buf = (n ? buf " " line : line); n = 1 }
        END { flush() }' <<<"$1"
}
# section_fences <text> — one flattened FENCE BODY per line, with issue and PR
# numbers normalised to `#N`. The fences are not inert worked examples here:
# Phase 4's ```text fence is the coverage block the run prints, so excluding it
# would leave the one artefact #284 is about writable.
section_fences() {
    awk '
        function flush(  t) { if (n) { t = buf
                                       gsub(/[ \t]+/, " ", t); sub(/^ +/, "", t); sub(/ +$/, "", t)
                                       gsub(/#[0-9]+/, "#N", t)
                                       print t; buf = ""; n = 0 } }
        /^[ \t]*```/ { if (fence) flush(); fence = !fence; next }
        !fence { next }
        { line = $0; gsub(/^[ \t]+|[ \t]+$/, "", line)
          buf = (n ? buf " " line : line); n = 1 }
        END { flush() }' <<<"$1"
}
# reviewer_rows <text> — the `sassy-dog:<name>-reviewer` in each map row's FIRST
# cell, sorted. First cell only, so a reviewer merely mentioned in a
# "Dispatch when" cell cannot forge a row.
reviewer_rows() {
    awk -F'|' '
        /^[ \t]*\|/ {
            cell = $2
            if (match(cell, /sassy-dog:[a-z0-9-]+-reviewer/))
                print substr(cell, RSTART + 10, RLENGTH - 10)
        }' <<<"$1" | sort
}
# --- end extractors ----------------------------------------------------------

# --- the canon ---------------------------------------------------------------
# The decision surface AND the structure, held HERE rather than derived from the
# files under test. A quoted heredoc, so nothing expands and no quote needs
# escaping; key and value are TAB-separated. This is the ONE place to edit when
# these sections legitimately change — see the cost note in the header.
canon_table() {
    cat <<'CANON'
orch_outcomes#b1	## Dispatch outcomes (Phase 1)
orch_outcomes#b2	Every domain in the table above gets an **outcome**, recorded as the fan-out returns. Together they are the run's **ledger**: built in Phase 1, carried through Phases 2 and 3 unchanged, and printed in Phase 4's preview before the approval prompt.
orch_outcomes#b3	Three outcomes belong to the fan-out itself:
orch_outcomes#b4	| Outcome | What it means | Reviewed | |---|---|---| | `returned` | The agent came back with a finding list in the schema below — empty or not | yes | | `no report` | The dispatch succeeded and came back with nothing usable: no final text, prose where a finding list belongs, or output you cannot parse | **no** | | `could not dispatch` | The Agent call errored, timed out, or the agent could not be resolved | **no** |
orch_outcomes#b5	A fourth records a decision taken *before* the fan-out: `not dispatched`, for a domain the Phase-0 stack detection found no signal for. Record it with the reason that skipped it.
orch_outcomes#b6	**A domain whose outcome is not `returned` is DARK, and a dark domain is never scored as clean and never reported as "no findings".** Those are the two claims this audit is not entitled to make about a domain nobody reviewed. Name it, name its outcome, and say that this run does not cover it. Keep `not dispatched` visibly apart from the two dark outcomes: a domain skipped for cause and a domain that went dark are indistinguishable once both are merely missing from the Epic, and only one of them is a decision somebody made.
orch_outcomes#b7	**This is the sibling of the diff-scoped rule, not a copy of it and not derived from it.** `agents/pr-review-orchestrator.md`, Step 5, scores a lost reviewer's surface `!` in a report a human reads while the context is still live; a hole there costs a re-run. This path **writes**. Its artefact is a filed Epic and its child issues, which becomes the durable record of what is wrong with the repo — so a lost `security-reviewer` here yields a backlog that omits an entire domain and **reads complete** to everyone who finds it later. Same question, different consequence: neither rule is evidence about the other, and changing one does not license changing the other ([#280](https://github.com/Sassy-Dog/sassydog-skills/issues/280), [#284](https://github.com/Sassy-Dog/sassydog-skills/issues/284)).
orch_outcomes#b8	**A dark domain is surfaced, not a veto.** It never stops the run and never blocks filing: findings that did come back are still verified, grouped, previewed and — on approval — filed. The human was always the gate here; what was missing is that they were not told a domain went dark. Re-dispatching a dark domain is allowed, and the ledger records the outcome of the last attempt — a domain that comes back on a retry is `returned`.
orch_schema#b1	## Finding output schema
orch_schema#b2	Each agent returns a list of findings. Each finding:
orch_schema#b3	Agents that find nothing in their domain return an empty list — that is a valid, useful result, **and it is a result only once you have received it**. An empty list that arrived is a clean domain; an empty list that never arrived is a dark one. The ledger above is the only thing that tells them apart, which is why it is recorded rather than inferred from what the Epic ended up containing.
orch_schema#f1	- title: imperative, PR-sized ("Pin GitHub Actions to commit SHAs") area: one of the 15 rubric areas severity: critical | high | medium | low likelihood: high | medium | low evidence: one or more "path/to/file.ext:LINE" with a 1-line quote/why why_it_matters: concrete consequence in THIS repo (not generic) proposed_fix: what a PR would do acceptance: how we'd know it's fixed pr_size: xs | s | m | l (l = consider splitting) labels: suggested labels from the taxonomy confidence: 0.0–1.0 (agent's own confidence the finding is real)
skill_principle#b1	**Default = preview, not file.** Filing issues is outward-facing and hard to undo. Always present the proposed Epic + child issues for approval and file only after the user confirms. Never create issues silently.
skill_phase1#b1	### Phase 1 — Fan out (parallel review agents)
skill_phase1#b2	Dispatch the relevant `sassy-dog:*-reviewer` agents **in a single message with multiple Agent tool calls** so they run concurrently. Skip domains with no signal (no IaC → skip `infra-platform-reviewer`). Give each agent the repo path, the detected stack, and its scope. Each returns findings in the shared schema with mandatory `file:line` evidence.
skill_phase1#b3	**Record an outcome for every domain as the fan-out returns** — `returned`, `no report`, or `could not dispatch` — plus `not dispatched`, with its reason, for a domain step 2 above skipped. That ledger is Phase 4's input: a domain whose outcome is not `returned` is **dark**, and a dark domain is never scored as clean and never reported as "no findings". A reviewer that came back with nothing looks exactly like one that found nothing, and writing down which happened is the only thing that separates them. Carry the ledger through Phases 2 and 3 unchanged — nothing there adds a domain or clears one.
skill_phase1#b4	See **`orchestration.md`** for the agent→domain map, the four outcomes and what each one means, and the finding schema.
skill_phase4#b1	### Phase 4 — Preview, then file
skill_phase4#b2	1. **Print the full preview**: the Epic (exec summary + scores) and every child issue (title, body, labels, and its dedupe decision). 2. **Print the Phase-1 ledger in that preview, before you ask for approval.** Every domain, with its outcome, rendered so a reader sees the coverage without opening anything:
skill_phase4#b3	Print this block on **every** run, the all-clear included. A coverage line that shows up only when something went wrong teaches the reader that its absence means nothing, which is the habit that made a dark domain invisible in the first place (issue [#284](https://github.com/Sassy-Dog/sassydog-skills/issues/284)). 3. Now ask the user to approve, edit, or cancel. **File nothing yet.** A dark domain is surfaced, not a veto: it does not stop the run and does not block filing, and on approval everything that did come back is filed as normal. 4. On approval, **align the target repo's labels first** — the engineering-dimension + severity taxonomy is owned by one script in this plugin, and this skill invokes it rather than carrying a copy (issue #167). The path below is resolved when this skill loads; pass it on as `ALIGN=<that path>` to anything that needs it, because `references/*.md` are read raw and never get the substitution:
skill_phase4#b4	5. Then follow **`references/github-issue-ops.md`**: re-check dedupe per issue right before creation (comment on a match instead of duplicating), create child issues, create the Epic, then attach each child as a **native sub-issue** (`gh api`), with a task-list fallback.
skill_phase4#f1	Domain coverage — 9 dispatched, 7 returned, 2 dark returned: architecture, code-quality, testing, dx-docs, observability-ops, cicd-release, deps no report: infra-platform — came back with prose, not a finding list could not dispatch: security — Agent call errored (agent not resolved) not dispatched: (none) 2 domains are DARK. This audit does not cover them, and nothing above is evidence that they are clean.
skill_phase4#f2	bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo "$REPO" --dry-run # preview drift, writes nothing bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo "$REPO" # create missing + correct drifted
skill_phase5#b1	### Phase 5 — Report
skill_phase5#b2	Print the Epic URL, the child issue list, the executive summary, and the same coverage block Phase 4 previewed — the filed backlog is the durable artefact, so the record of what this audit did not cover travels with it.
skill_redflags#b1	## Red Flags — STOP
skill_redflags#b2	- About to file an issue with no `file:line` evidence → drop it or downgrade to the Epic's "watch list". - About to create issues without showing the preview first → STOP, preview and get approval. - A finding that's "best practice" with no concrete harm in *this* repo → that's cargo-cult; drop it. - Skipped the dedupe index fetch → you will create duplicates. Fetch it in Phase 0. - About to call a domain clean, or write "no findings" for it, when its reviewer did not come back → STOP. That is the one claim this audit cannot make. Report it dark, with its outcome, and file the rest. - About to show the preview with a domain missing from the coverage block → STOP. A domain absent from the ledger is a domain the reader cannot tell apart from a clean one, and this preview is the last moment before the backlog becomes the record. - About to type a `gh label create` with a colour in it → STOP. Run `align-labels.sh` (Phase 4). A hardcoded hex here is a second copy of the taxonomy, and the last one silently painted stale colours into every repo this skill audited.
inv#orch_headings	# Orchestration ~ ## Agent → domain map ~ ## Dispatch outcomes (Phase 1) ~ ## Finding output schema ~ ## Adversarial review (Phase 2) ~ ## Grouping into PR-sized issues (Phase 3)
inv#orch_openers	# Orchestration ~ How the main agent dispatches review ~ ## Agent → domain map ~ Dispatch only the agents with signal ~ | Agent (`subagent_type`) | Owns rubric ~ **Dispatch rule:** issue all selected agents ~ ## Dispatch outcomes (Phase 1) ~ Every domain in the table above ~ Three outcomes belong to the fan-out ~ | Outcome | What it means ~ A fourth records a decision taken ~ **A domain whose outcome is not ~ **This is the sibling of the ~ **A dark domain is surfaced, not ~ ## Finding output schema ~ Each agent returns a list of ~ ``` ~ ``` ~ Agents that find nothing in their ~ ## Adversarial review (Phase 2) ~ For each finding, in order of ~ 1. **Verify evidence** — open the ~ Survivors carry a final `confidence`. Drop ~ ## Grouping into PR-sized issues (Phase ~ - Cluster survivors that a single ~ Then proceed to `references/github-issue-ops.md` for filing.
inv#orch_bullets	0:- Cluster survivors that a single ~ 0:- A single `l`/`xl` finding may ~ 0:- Keep clusters cohesive: don't bundle ~ 0:- Order issues by ROI (severity
inv#orch_rows	0:| Agent (`subagent_type`) | Owns rubric ~ 0:|---|---|---| ~ 0:| `sassy-dog:architecture-reviewer` | 2 structure, 3 ~ 0:| `sassy-dog:code-quality-reviewer` | 4 code quality, ~ 0:| `sassy-dog:security-reviewer` | 5 security (app ~ 0:| `sassy-dog:testing-reviewer` | 7 testing | ~ 0:| `sassy-dog:cicd-release-reviewer` | 8 CI/CD & ~ 0:| `sassy-dog:infra-platform-reviewer` | 9 infrastructure & ~ 0:| `sassy-dog:observability-ops-reviewer` | 10 observability & ~ 0:| `sassy-dog:dx-docs-reviewer` | 6 DX, 11 ~ 0:| `sassy-dog:dependency-supply-chain-reviewer` | 5 supply-chain slice, ~ 0:| Outcome | What it means ~ 0:|---|---|---| ~ 0:| `returned` | The agent came ~ 0:| `no report` | The dispatch ~ 0:| `could not dispatch` | The
inv#skill_headings	# Assess-It ~ ## Core Principle ~ ## Workflow ~ ### Phase 0 — Scope & detect (you, the main agent) ~ ### Phase 1 — Fan out (parallel review agents) ~ ### Phase 2 — Adversarial review (you) ~ ### Phase 3 — Group into PR-sized work items ~ ### Phase 4 — Preview, then file ~ ### Phase 5 — Report ~ ## Reference Files ~ ## Red Flags — STOP
inv#skill_openers	--- ~ # Assess-It ~ Turn a whole repository into a ~ **Repo-agnostic.** Works on any GitHub repo. ~ **Default = preview, not file.** Filing ~ ## Core Principle ~ A finding only earns an issue ~ ## Workflow ~ Follow the five phases. Full dispatch ~ ### Phase 0 — Scope & ~ 1. Resolve the target repo (cwd ~ ### Phase 1 — Fan out ~ Dispatch the relevant `sassy-dog:*-reviewer` agents **in ~ **Record an outcome for every domain ~ See **`orchestration.md`** for the agent→domain map, ~ ### Phase 2 — Adversarial review ~ For every finding: open the cited ~ ### Phase 3 — Group into ~ Cluster surviving findings so each cluster ~ ### Phase 4 — Preview, then ~ 1. **Print the full preview**: the ~ ```text ~ ``` ~ Print this block on **every** run, ~ ```bash ~ ``` ~ 5. Then follow **`references/github-issue-ops.md`**: re-check dedupe ~ ### Phase 5 — Report ~ Print the Epic URL, the child ~ ## Reference Files ~ - **`assessment-rubric.md`** — the 15 assessment ~ ## Red Flags — STOP ~ - About to file an issue
inv#skill_bullets	0:- **`assessment-rubric.md`** — the 15 assessment ~ 0:- **`orchestration.md`** — agent→domain map, per-agent ~ 0:- **`references/github-issue-ops.md`** — label *routing* (which ~ 0:- About to file an issue ~ 0:- About to create issues without ~ 0:- A finding that's "best practice" ~ 0:- Skipped the dedupe index fetch ~ 0:- About to call a domain ~ 0:- About to show the preview ~ 0:- About to type a `gh
inv#skill_ordered	0:1. Resolve the target repo (cwd ~ 0:2. Detect stack(s) by globbing manifests: ~ 0:3. **Build the dedupe index** (used ~ 0:1. **Print the full preview**: the ~ 0:2. **Print the Phase-1 ledger in ~ 0:3. Now ask the user to ~ 0:4. On approval, **align the target ~ 0:5. Then follow **`references/github-issue-ops.md`**: re-check dedupe
inv#skill_rows	
CANON
}

CANON_KEYS=()
CANON_VALS=()
while IFS=$'\t' read -r _ck _cv; do
    [ -z "$_ck" ] && continue
    CANON_KEYS+=("$_ck")
    CANON_VALS+=("$_cv")
done < <(canon_table)

canon_get() {
    local i
    for ((i = 0; i < ${#CANON_KEYS[@]}; i++)); do
        if [ "${CANON_KEYS[$i]}" = "$1" ]; then printf '%s' "${CANON_VALS[$i]}"; return 0; fi
    done
    return 1
}
canon_count_prefix() {
    local i c=0
    for ((i = 0; i < ${#CANON_KEYS[@]}; i++)); do
        case "${CANON_KEYS[$i]}" in "$1"*) c=$((c + 1)) ;; esac
    done
    printf '%s' "$c"
}

# --- the pinned windows ------------------------------------------------------
# `name|file|start prefix|stop prefix`. `|` is safe as the delimiter: no anchor
# here contains one. A stop of NEVER means "runs to EOF" and is asserted as
# such; an empty stop means "the next blank line".
#
# The agent -> domain map is deliberately NOT here. It changes whenever a
# reviewer ships, the premise section's equality already reddens then, and
# pinning it twice would redden twice for one edit.
WINDOW_DEFS=(
"orch_outcomes|$ORCH|## Dispatch outcomes (Phase 1)|## Finding output schema"
"orch_schema|$ORCH|## Finding output schema|## Adversarial review (Phase 2)"
"skill_principle|$SKILL|**Default = preview, not file.**|"
"skill_phase1|$SKILL|### Phase 1 — Fan out|### Phase 2 — Adversarial review"
"skill_phase4|$SKILL|### Phase 4 — Preview, then file|### Phase 5 — Report"
"skill_phase5|$SKILL|### Phase 5 — Report|## Reference Files"
"skill_redflags|$SKILL|## Red Flags — STOP|$NEVER"
)

echo "assess-it audit-mode lost-reviewer backstop (issue #284)"

section windows "every window resolves, and stops where it claims to"

for f in "$SKILL" "$ORCH" "$PRORCH"; do
    if [ -r "$f" ]; then ok "read $f"; else bad "missing file: $f"; fi
done
[ "$fails" -eq 0 ] || { echo "test-audit-lost-reviewer: FAILED ($fails)" >&2; exit 1; }

WIN_NAMES=()
WIN_TEXT=()
for _def in "${WINDOW_DEFS[@]}"; do
    _wname="${_def%%|*}"; _rest="${_def#*|}"
    _wfile="${_rest%%|*}"; _rest="${_rest#*|}"
    _wstart="${_rest%%|*}"; _wstop="${_rest#*|}"
    _wtext="$(raw_region "$_wfile" "$_wstart" "$_wstop")"
    assert_nonempty "$_wtext" "window $_wname resolves"
    if [ "$_wstop" = "$NEVER" ]; then
        _wlast="$(printf '%s\n' "$_wtext" | tail -n 1)"
        _flast="$(tail -n 1 "$_wfile")"
        assert_eq "$_wlast" "$_flast" "window $_wname runs to EOF as declared"
    else
        _sline="$(region_stop_line "$_wfile" "$_wstart" "$_wstop")"
        if [ -z "$_sline" ]; then
            bad "window $_wname does not stop where it claims — the stop marker never appears after it"
        elif [ -z "$_wstop" ]; then
            assert_eq "$_sline" "<blank>" "window $_wname stops at the next blank line"
        else
            case "$_sline" in
                "$_wstop"*) ok "window $_wname stops at '$_wstop'" ;;
                *) bad "window $_wname stops at an unexpected line: ${_sline:0:80}" ;;
            esac
        fi
    fi
    WIN_NAMES+=("$_wname")
    WIN_TEXT+=("$_wtext")
done

section canon "every block and every fence of every pinned window, by equality after flattening"

for ((_wi = 0; _wi < ${#WIN_NAMES[@]}; _wi++)); do
    _wname="${WIN_NAMES[$_wi]}"
    _wtext="${WIN_TEXT[$_wi]}"

    _nb=0
    while IFS= read -r _bline; do
        _nb=$((_nb + 1))
        _key="${_wname}#b${_nb}"
        _want="$(canon_get "$_key")" || _want=""
        assert_eq "$_bline" "$_want" "canon $_key"
        note_consumed "$_key"
    done < <(section_blocks "$_wtext")
    assert_eq "$_nb" "$(canon_count_prefix "${_wname}#b")" "canon $_wname block count"

    _nf=0
    while IFS= read -r _fline; do
        _nf=$((_nf + 1))
        _key="${_wname}#f${_nf}"
        _want="$(canon_get "$_key")" || _want=""
        assert_eq "$_fline" "$_want" "canon $_key"
        note_consumed "$_key"
    done < <(section_fences "$_wtext")
    assert_eq "$_nf" "$(canon_count_prefix "${_wname}#f")" "canon $_wname fence count"
done

section inventory "openers, bullets, ordered items, table rows and headings — both files whole"

_orch_all="$(cat "$ORCH")"
_skill_all="$(cat "$SKILL")"

for _inv in \
    "inv#orch_headings|$(heading_list "$_orch_all")" \
    "inv#orch_openers|$(openers "$_orch_all")" \
    "inv#orch_bullets|$(bullet_openers "$_orch_all")" \
    "inv#orch_rows|$(table_rows "$_orch_all")" \
    "inv#skill_headings|$(heading_list "$_skill_all")" \
    "inv#skill_openers|$(openers "$_skill_all")" \
    "inv#skill_bullets|$(bullet_openers "$_skill_all")" \
    "inv#skill_ordered|$(ordered_openers "$_skill_all")" \
    "inv#skill_rows|$(table_rows "$_skill_all")" ; do
    _ikey="${_inv%%|*}"
    _igot="${_inv#*|}"
    _iwant="$(canon_get "$_ikey")" || _iwant=""
    assert_eq "$_igot" "$_iwant" "inventory ${_ikey#inv#}"
    note_consumed "$_ikey"
done

section residue "the #283 residue note is REPLACED by the rule, not left beside it"

_orch_flat="$(flat "$_orch_all")"
assert_absent "$_orch_flat" "Known gap" "residue: the 'Known gap' callout is gone"
assert_absent "$_orch_flat" "lost-agent scoring" "residue: 'lost-agent scoring' is gone"
assert_absent "$_orch_flat" "unfixed, not overlooked" "residue: 'unfixed, not overlooked' is gone"
assert_absent "$_orch_flat" "Recorded here so the absence" "residue: the 'recorded here' hedge is gone"
assert_absent "$_orch_flat" "deliberately kept out of the prose-gate work" "residue: the deferral clause is gone"

section sibling "the diff-scoped rule survives untouched — this file is read for one fact"

_pr_flat="$(flat "$(cat "$PRORCH")")"
assert_has "$_pr_flat" "A reviewer that did not come back is not a clean surface." \
    "sibling: pr-review-orchestrator still scores a lost reviewer"
assert_has "$_pr_flat" "its surface is \`!\`, never" \
    "sibling: the \`!\` consequence survives in the diff-scoped orchestrator"

section premise "the ledger ranges over the reviewers this plugin actually ships"

_map_text="$(raw_region "$ORCH" "## Agent → domain map" "## Dispatch outcomes (Phase 1)")"
assert_nonempty "$_map_text" "premise: the agent → domain map window resolves"
_mapped="$(reviewer_rows "$_map_text")"
_shipped="$(for _f in agents/*-reviewer.md; do _b="${_f##*/}"; printf '%s\n' "${_b%.md}"; done | sort)"
assert_eq "$_mapped" "$_shipped" "premise: the map's rows are exactly the shipped *-reviewer agents"
_nmapped=0
if [ -n "$_mapped" ]; then _nmapped="$(printf '%s\n' "$_mapped" | wc -l | tr -d ' ')"; fi
if [ "$_nmapped" -ge 9 ]; then
    ok "premise: the map carries at least the nine reviewers ($_nmapped)"
else
    bad "premise: the map carries only $_nmapped reviewers — the equality above may be vacuous"
fi

section registry "the floor binds: the canon is non-empty and every key was consumed"

if [ "${#CANON_KEYS[@]}" -gt 0 ]; then
    ok "the canon table is non-empty (${#CANON_KEYS[@]} entries)"
else
    bad "the canon table is empty — every equality above compared nothing to nothing"
fi
_unconsumed=""
for ((_i = 0; _i < ${#CANON_KEYS[@]}; _i++)); do
    case "$consumed" in
        *" ${CANON_KEYS[$_i]} "*) ;;
        *) _unconsumed="$_unconsumed ${CANON_KEYS[$_i]}" ;;
    esac
done
assert_eq "$_unconsumed" "" "every canon key is consumed by an assertion"

_close_section

echo
echo "assertions: $asserts (floor $ASSERT_FLOOR)"
if [ "$asserts" -lt "$ASSERT_FLOOR" ]; then
    echo "test-audit-lost-reviewer: only $asserts assertions ran, floor is $ASSERT_FLOOR" >&2
    fails=$((fails + 1))
fi
for _s in "${SECTIONS[@]}"; do
    _name="${_s%%:*}"; _min="${_s##*:}"
    _got=""
    for ((_i = 0; _i < ${#ran_names[@]}; _i++)); do
        [ "${ran_names[$_i]}" = "$_name" ] && _got="${ran_counts[$_i]}"
    done
    if [ -z "$_got" ]; then
        echo "test-audit-lost-reviewer: section '$_name' never ran" >&2
        fails=$((fails + 1))
    elif [ "$_got" -lt "$_min" ]; then
        echo "test-audit-lost-reviewer: section '$_name' ran $_got assertions, minimum $_min" >&2
        fails=$((fails + 1))
    fi
done
_got=""
for ((_i = 0; _i < ${#ran_names[@]}; _i++)); do
    [ "${ran_names[$_i]}" = "registry" ] && _got="${ran_counts[$_i]}"
done
if [ -z "$_got" ] || [ "$_got" -lt "$REGISTRY_MIN" ]; then
    echo "test-audit-lost-reviewer: the registry section did not reach REGISTRY_MIN=$REGISTRY_MIN" >&2
    fails=$((fails + 1))
fi

if [ "$fails" -eq 0 ]; then
    echo "test-audit-lost-reviewer: all green ($asserts assertions)"
    exit 0
fi
echo "test-audit-lost-reviewer: FAILED ($fails)" >&2
exit 1
