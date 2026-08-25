#!/usr/bin/env bash
# test-sentry-verification.sh — pins setup-config's Sentry project VERIFICATION
# decision and the `sentry: none` contract exception (issue #213).
#
# Why a source-level guard and not a render test. Nothing here is executed by a
# script: `setup-config` is a generator whose Sentry rule is prose an agent
# follows, so the artifact under test is the instruction itself — the same shape
# as test-visibility-preconditions.sh (setup-deps' two preconditions) and
# test-label-migrate.sh (align-labels.sh's single-call-site invariant).
#
# The bug it guards. A Sentry project slug and a GitHub repo can share a name and
# belong to DIFFERENT codebases — a marketing-site repo `<product>-web` beside a
# Sentry project `<product>-web` fed by a member-app frontend living elsewhere.
# The old rule ("list projects for the org to propose {{SENTRY_PROJECTS}}") made
# name similarity the only evidence, which is also the evidence an agent reaches
# for first. Every consequence is invisible after the fact: the wrong repo claims
# another codebase's P0s, two repos double-report the same issues, `take-it` is
# dispatched at a repo holding no such route — and BOTH plates still render
# complete, so nothing signals the error.
#
# Three decisions are pinned, and the last two are the fragile ones:
#
#   A. Verification is by CULPRIT, not by name, and a failed verification writes
#      `sentry: none` rather than a guessed block.
#   B. `sentry: none` is the config contract's FIRST documented exception to
#      "presence is the toggle". That exception is exactly the kind of prose a
#      later "align with the governing principle" sweep deletes as an
#      inconsistency — it reads like drift and is in fact the decision.
#   C. The `none` form now spans FOUR keys and is deliberately ASYMMETRIC across
#      them (issue #261): `sentry: none` keeps its blind-spot row, while
#      `testflight: none`, `posthog: none` and `mobile: none` render one `(n/a)`
#      token on the clean line and no row at all.
#
# Why C needs a gate rather than a paragraph. A four-key form where one key
# behaves differently reads as a plain inconsistency, so it is precisely what a
# tidying sweep "fixes" — in either direction, and both directions are silent.
# Collapsing `sentry: none` onto the clean line restores the gap #213 opened the
# form to close: a repo with no error monitoring stops being told so. Promoting
# the other three back into rows restores #261: an infra repo with no app carried
# three permanently unclearable rows on every plate, two of them in the loudest
# position the section has, which is how a reader learns to skim the heading that
# a genuinely dark Sentry lives under.
#
# The four-key table is checked by COUNTING its rows, not by looking up the four
# names — a lookup passes just as happily on a table that grew a fifth key or
# lost one, and "how many keys behave which way" is the whole decision.
#
# Four ways this gate was MEASURED reporting a clean tree on a source stating the
# inverse. Every one is a scoping error, and every fix is the same shape:
#
#   * §3A's `sentry:` rule was covered by nothing, because the per-key loop runs
#     over the three clean-line keys only. Rewriting §3A to put `sentry: none` on
#     the clean line left this gate GREEN — the headline decision unpinned in the
#     one section the loop calls authoritative. It now has its own block with the
#     expectations INVERTED, and the loop must never be widened to swallow it.
#   * The per-key windows read the whole flattened file, so they landed on §6's
#     prose and a reverted §3 probe rule read as covered. Windows are scoped to
#     §3.
#   * `update-mode.md`'s rule was checked file-wide for 'stop and surface', which
#     step 1's unrelated rename-collision rule already satisfies. Inverting the
#     rule to "always silently rewrite a `none`" left it printing ok. Windowed.
#   * §2c's per-key check was a bare `grep -q "$key"`, which its own rationale
#     sentence satisfies ("an absent mobile app is a product fact"). It now
#     requires the literal `<key>: none` the question actually writes.
#
# HOW THIS GATE WAS MEASURED, and the methodology lesson, which is the part worth
# keeping. Three review rounds each found assertions here passing on sources that
# state the inverse, and the reason the author's own mutation set kept reporting
# "all detected" is that every mutation was written by deleting the exact literal
# its assertion greps for. Such a set is tautologically caught: it proves `grep`
# works, not that the assertion pins a decision. A mutation must invert the
# MEANING and be worded the way a tidying editor would word it — different verb,
# different emphasis, different sentence shape. Re-measured that way, four
# assertions that had "passed" 50 literal mutations were undetected.
#
# What the three rounds found, all of it the same family:
#
#   * NEGATION-BLINDNESS. `grep -qi 'blind-spot row'` matches inside "**no**
#     blind-spot row"; the fix for that matched inside "never given a blind-spot
#     row", "is exempt from", and "aligned with the other three". Enumerating
#     negations is unwinnable, which is why the two outcomes now have MUTUALLY
#     EXCLUSIVE vocabularies and each rule must speak exactly one.
#   * WINDOW SIZING, wrong in both directions: 460 bytes read half of a ~930-byte
#     rule and a must-not-exist slipped past; 400 bytes let one key's assertions
#     be satisfied by the next key's rule, ~158 bytes away. Hence `window_between`
#     and the structural `No key at all` bound.
#   * A WINDOW THAT IS RIGHT FOR ONE CHECK IS WRONG FOR ANOTHER. The `none`
#     clause is the right scope for "does it keep its row"; it is the wrong scope
#     for "does this rule ever mention the clean line", because a contradictory
#     clause appended to the rule's absent-key half lands outside it. Both scopes
#     are asserted.
#   * TALLYING IS NOT CLASSIFYING. Counting two patterns left a fifth key whose
#     behaviour column matched neither invisible — and the row filter keyed on a
#     backtick, so a row a human hand-adds without code formatting was invisible
#     too. Every row must be ACCOUNTED FOR.
#   * PREFIX ANCHORS. `grep -qi 'cannot re-derive is the'` is satisfied by
#     "…is the **surface**", the exact inversion of "…is the **confirmation**".
#   * A MENTION IS NOT A COMMITMENT. `grep -qi 'migrate mode'` was satisfied by a
#     sentence *demoting* migrate mode, so the check now requires the list entry.
#   * EMPHASIS. `The exception is scoped to **`sentry:`** alone.` slipped past a
#     check on the plain flatten, so must-not-exist checks also run against an
#     emphasis-stripped copy.
#
# Two more traps worth naming. The example-block must-not-exist check reads a
# FLATTENED copy: markdownlint's MD013 is off here, so a hard-wrapped row is
# invisible to a line-scoped grep — measured both ways. And a `\`` inside a
# double-quoted `ok`/`bad` message is COMMAND SUBSTITUTION, not a literal: three
# messages in this file ran `sentry: none` as a command before they were escaped.
#
# The prior-claim sibling scan is pinned as SECONDARY on purpose: promoting it to
# the guard would re-open the hole in every cloud session, which has no sibling
# checkouts on disk and so finds nothing while reporting nothing.
#
# Must-not-exist assertions run against a WHITESPACE-FLATTENED copy of the file.
# This repo hard-wraps prose, so forbidden wording routinely straddles two lines
# and a line-scoped grep reports a FALSE PASS. (Must-exist checks may stay
# line-scoped: a wrap there fails loudly, which is safe.)
#
# No `| grep -q` pipeline here takes a command as its writer: every one is fed by
# a single-argument `printf`, the shape scripts/test-pipefail-grep.sh permits.
# MEASURED, because an earlier version of this file asserted a size limit that
# does not exist: `printf '%s' "$one_unterminated_line" | grep -q` returns 0 at
# 64KB, 256KB, 1MB and 4MB on both bash 3.2.57 and 5.3.15, because `grep -q`
# cannot exit early on a line whose terminator it has not seen — and `tr '\n' ' '`
# makes every haystack here exactly one unterminated line. A COMMAND writer
# emitting many lines returns 141 at 64KB, which is the shape #256's syntactic
# rule targets and the reason that rule cannot be replaced by a size check.
#
# No gh, no network, no repo mutation — it reads eight tracked files.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-sentry-verification.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-sentry-verification: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

DETECTION="skills/setup-config/references/detection.md"
CONTRACT="skills/setup-config/references/config-contract.md"
SKILL="skills/setup-config/SKILL.md"
TEMPLATE="skills/setup-config/references/templates/survey-work.config.md"
INTERVIEW="skills/setup-config/references/interview.md"
UPDATE="skills/setup-config/references/update-mode.md"
MIGRATE="skills/setup-config/references/migrate-mode.md"
PLATE="skills/survey-work/SKILL.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "Sentry verification + the four-key \`none\` form (issues #213, #261)"

for f in "$DETECTION" "$CONTRACT" "$SKILL" "$TEMPLATE" "$INTERVIEW" "$UPDATE" "$MIGRATE" "$PLATE"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-sentry-verification: FAILED" >&2; exit 1; }

# Re-join each hand-check bullet into ONE record, so "same bullet" is the unit of
# every check below. Flattening the whole section instead would let 'culprit' in
# one bullet satisfy a claim about another.
handchecks="$(awk '/^## Hand checks the script/{f=1; next} /^## /{f=0} f' "$DETECTION")"
[ -n "$handchecks" ] || bad "cannot locate detection.md's '## Hand checks' section"
bullets="$(printf '%s\n' "$handchecks" |
    awk '/^- /{if (b != "") print b; b=$0; next} {b = b " " $0} END{if (b != "") print b}')"
# `tr -s ' '` because the join preserves each continuation line's indentation,
# so a phrase that wrapped mid-sentence carries a run of spaces inside it.
culprit_bullet="$(printf '%s\n' "$bullets" | grep -i 'Sentry project' | tr -s ' ')"
claim_bullet="$(printf '%s\n' "$bullets" | grep -i 'prior-claim' | tr -s ' ')"

# --- A. Verification is by culprit, against THIS repo -------------------------

if [ -n "$culprit_bullet" ]; then
    ok "detection.md carries a Sentry project hand-check"
else
    bad "detection.md has no Sentry project hand-check bullet"
fi

if printf '%s' "$culprit_bullet" | grep -qi 'culprit'; then
    ok "the Sentry hand-check verifies by culprit"
else
    bad "the Sentry hand-check does not mention culprit — name match is back"
fi

# The culprit has to be resolved against the repo being configured. A rule that
# samples culprits and never checks them against this tree proves nothing.
if printf '%s' "$culprit_bullet" | grep -qiE 'resolve in the repo being configured|resolve in this repo'; then
    ok "culprits must resolve in the repo being configured"
else
    bad "the hand-check never requires culprits to resolve in THIS repo"
fi

if printf '%s' "$culprit_bullet" | grep -qi 'name similarity is not evidence'; then
    ok "the rule states name similarity is not evidence"
else
    bad "the rule no longer states that name similarity is not evidence"
fi

if printf '%s' "$culprit_bullet" | grep -qiE 'regardless of what it is called|regardless of (its|the) name'; then
    ok "a non-matching project is wrong regardless of its name"
else
    bad "the rule lost the 'wrong project regardless of its name' clause"
fi

# Mutation proof: the pre-#213 rule, flattened so a re-wrap cannot hide it.
detection_flat="$(tr '\n' ' ' < "$DETECTION" | tr -s ' ')"
if printf '%s' "$detection_flat" | grep -qi 'list projects for the org to propose'; then
    bad "detection.md reverted to the name-match rule (list projects to propose)"
else
    ok "detection.md carries no name-match propose rule"
fi

# --- B. A failed verification writes `sentry: none` ---------------------------

if printf '%s' "$culprit_bullet" | grep -q 'sentry: none'; then
    ok "failed verification is routed to \`sentry: none\`"
else
    bad "the hand-check never names \`sentry: none\` as the failure outcome"
fi

if printf '%s' "$culprit_bullet" | grep -qiE 'never a guessed block|not a guessed block'; then
    ok "the hand-check forbids a guessed block"
else
    bad "the hand-check no longer forbids writing a guessed block"
fi

# --- C. The prior-claim scan is secondary and non-blocking -------------------

if [ -n "$claim_bullet" ]; then
    ok "detection.md carries the prior-claim sibling scan"
else
    bad "detection.md has no prior-claim sibling scan"
fi

if printf '%s' "$claim_bullet" | grep -qi 'secondary'; then
    ok "the prior-claim scan is marked secondary"
else
    bad "the prior-claim scan is no longer marked secondary"
fi

if printf '%s' "$claim_bullet" | grep -qiE 'never block|never blocks|non-blocking|never fatal'; then
    ok "the prior-claim scan is non-blocking"
else
    bad "the prior-claim scan no longer states that a miss does not block"
fi

# The REASON is the part a later edit trims as redundant, and losing it is what
# lets someone promote the scan to the guard: it finds nothing in a cloud session
# and says nothing about having found nothing.
if printf '%s' "$claim_bullet" | grep -qi 'cloud session' &&
   printf '%s' "$claim_bullet" | grep -qi 'sibling'; then
    ok "the scan's secondary status carries its reason (no siblings in a cloud session)"
else
    bad "the prior-claim scan states no reason for being secondary"
fi

if printf '%s' "$detection_flat" | grep -qi 'never be the only guard'; then
    ok "the scan is explicitly never the only guard"
else
    bad "detection.md lost the 'never the only guard' rule"
fi

if printf '%s' "$claim_bullet" | grep -qi 'already owned' &&
   printf '%s' "$claim_bullet" | grep -qi 'confirm'; then
    ok "a prior claim defaults to already-owned and needs explicit confirmation"
else
    bad "a prior claim no longer defaults to owned / requires confirmation"
fi

# --- D. The contract exception ------------------------------------------------

presence_section="$(awk '/^## Governing principle: presence is the toggle/{f=1; next} /^## /{f=0} f' "$CONTRACT")"
[ -n "$presence_section" ] || bad "cannot locate the presence-is-the-toggle section"

exception_section="$(printf '%s\n' "$presence_section" |
    awk '/^### The one exception/{f=1; next} /^#{2,3} /{f=0} f')"

if [ -n "$exception_section" ]; then
    ok "config-contract.md documents the \`sentry: none\` exception"
else
    bad "the \`sentry: none\` exception is gone from config-contract.md"
fi

# It must read AS an exception. Slipped in as though the principle never existed,
# it is indistinguishable from drift and gets 'corrected' away.
if printf '%s' "$exception_section" | grep -qiE 'first documented exception|one documented exception|first exception'; then
    ok "the exception is marked as an exception to the principle"
else
    bad "the exception no longer identifies itself as the first exception"
fi

# ...with its reason attached, which is what makes it survive a consistency sweep.
if printf '%s' "$exception_section" | grep -qi 'verified by culprit'; then
    ok "the exception carries its reason (culprit verification can fail)"
else
    bad "the exception no longer explains why it exists"
fi

# The three states must stay distinct. Collapsing 'confirmed absent' into
# 'never configured' is the whole thing this form buys.
row_verified=0 row_none=0 row_absent=0
while IFS= read -r row; do
    case "$row" in
        *'block with'*) printf '%s' "$row" | grep -qi 'surface runs' && row_verified=1 ;;
        *'sentry: none'*) printf '%s' "$row" | grep -qi 'blind spot' && row_none=1 ;;
        *'key absent'*) printf '%s' "$row" | grep -qi 'blind spot' && row_absent=1 ;;
    esac
done < <(printf '%s\n' "$exception_section" | grep '^|')
if [ "$row_verified" = 1 ] && [ "$row_none" = 1 ] && [ "$row_absent" = 1 ]; then
    ok "the three-state table distinguishes verified / confirmed-absent / unknown"
else
    bad "the three-state table is incomplete (verified=$row_verified none=$row_none absent=$row_absent)"
fi

# The bare claim a reader meets first must point at the exception, or the section
# contradicts itself for anyone who stops reading at the paragraph.
contract_flat="$(tr '\n' ' ' < "$CONTRACT" | tr -s ' ')"
if printf '%s' "$contract_flat" | grep -qiE 'exception to this principle is `sentry: none`'; then
    ok "the 'no \`sentry: false\`' paragraph points forward to the exception"
else
    bad "the 'no \`sentry: false\`' claim stands bare, with no pointer to \`sentry: none\`"
fi

# --- E. The rendered template's header comment --------------------------------

template_header="$(awk '/^<!--/{f=1} f{print} /-->/{if (f) exit}' "$TEMPLATE")"
header_flat="$(printf '%s' "$template_header" | tr '\n' ' ' | tr -s ' ')"

if printf '%s' "$header_flat" | grep -q 'sentry: none'; then
    ok "the template header names the \`sentry: none\` form"
else
    bad "the template header asserts presence-is-the-toggle without naming \`sentry: none\`"
fi

# Mutation proof: the pre-#213 sentence, which asserted the bare rule.
if printf '%s' "$header_flat" | grep -qi 'toggle; there is no `sentry: false`'; then
    bad "the template header reverted to the bare 'there is no \`sentry: false\`' claim"
else
    ok "the template header carries no bare no-false assertion"
fi

# --- F. SKILL.md agrees with the rule ----------------------------------------

skill_flat="$(tr '\n' ' ' < "$SKILL" | tr -s ' ')"
if printf '%s' "$skill_flat" | grep -qi 'Sentry slugs via MCP'; then
    bad "setup-config/SKILL.md still summarises the check as 'Sentry slugs via MCP'"
else
    ok "setup-config/SKILL.md carries no 'Sentry slugs via MCP' summary"
fi

if printf '%s' "$skill_flat" | grep -qi 'culprit' &&
   printf '%s' "$skill_flat" | grep -q 'sentry: none'; then
    ok "setup-config/SKILL.md names both the culprit check and \`sentry: none\`"
else
    bad "setup-config/SKILL.md does not agree with the culprit rule"
fi

if printf '%s' "$skill_flat" | grep -qi 'name similarity is not evidence'; then
    ok "setup-config/SKILL.md repeats that name similarity is not evidence"
else
    bad "setup-config/SKILL.md dropped the name-similarity warning"
fi

# --- G. The interview's confirm-on-prior-claim prompt -------------------------

q2b="$(awk '/^### 2b\./{f=1; next} /^### /{f=0} f' "$INTERVIEW")"
q2b_flat="$(printf '%s' "$q2b" | tr '\n' ' ' | tr -s ' ')"

if [ -n "$q2b" ]; then
    ok "interview.md carries the prior-claim question"
else
    bad "interview.md has no prior-claim question"
fi

if printf '%s' "$q2b_flat" | grep -qi 'already owned' &&
   printf '%s' "$q2b_flat" | grep -qi 'confirm'; then
    ok "the prompt defaults to already-owned and requires explicit confirmation"
else
    bad "the prompt no longer defaults to owned / requires confirmation"
fi

# The question must not become "which project is this repo's?" — that is the name
# match wearing a question mark.
if printf '%s' "$q2b_flat" | grep -qi 'never ask'; then
    ok "the interview forbids asking the user to pick a project by name"
else
    bad "the interview lost its 'never ask which project' instruction"
fi

# --- H. survey-work renders confirmed-absent distinctly -----------------------

plate_blind="$(awk '/^## ⚠️ Blind spots/{f=1; next} /^## /{f=0} f' "$PLATE")"
none_row="$(printf '%s\n' "$plate_blind" | grep 'sentry: none')"
absent_row="$(printf '%s\n' "$plate_blind" | grep 'no `sentry:` block')"

if [ -n "$none_row" ]; then
    ok "survey-work renders a \`sentry: none\` blind-spot row"
else
    bad "survey-work has no \`sentry: none\` blind-spot row"
fi

if [ -n "$none_row" ] && [ -n "$absent_row" ] && [ "$none_row" != "$absent_row" ]; then
    ok "the confirmed-absent row is separate from the unconfigured row"
else
    bad "the confirmed-absent and unconfigured rows are not distinct"
fi

# Distinct in WORDING, not just in the key it quotes: a confirmed-absent surface
# was not 'NOT checked', and saying so is the collapse this row exists to stop.
if printf '%s' "$none_row" | grep -qi 'confirmed' &&
   ! printf '%s' "$none_row" | grep -q 'NOT checked'; then
    ok "the confirmed-absent row reads as confirmed, not as unchecked"
else
    bad "the \`sentry: none\` row is worded as an unchecked surface"
fi

# ...and confirmed of the RIGHT thing. `sentry: none` covers a genuine absence
# AND a culprit check that could not run, so the row may claim no *verified*
# project and must not claim the repo has none — a distinction nothing downstream
# can recover once the row has asserted it.
if printf '%s' "$none_row" | grep -qi 'verified'; then
    ok "the \`sentry: none\` row claims no VERIFIED project, not an absent one"
else
    bad "the \`sentry: none\` row no longer scopes its claim to verification"
fi

if printf '%s' "$none_row" | grep -qiE '(repo|this repo) has no error monitoring'; then
    bad "the \`sentry: none\` row over-claims: it covers a check that could not run too"
else
    ok "the \`sentry: none\` row makes no bare no-error-monitoring claim"
fi

# The same over-claim in detection.md, which is where the value is written.
if printf '%s' "$detection_flat" | grep -qi 'must never be glossed as'; then
    ok "detection.md forbids glossing \`sentry: none\` as a plain absence"
else
    bad "detection.md no longer distinguishes an absence from a check that could not run"
fi

# --- I. `none` is ASYMMETRIC across the four keys (issue #261) -----------------
#
# `sentry: none` keeps its blind-spot row; `testflight: none`, `posthog: none`
# and `mobile: none` render one `(n/a)` token on the clean line and no row. Both
# halves are load-bearing and a sweep can break either one silently, so both are
# asserted — never "the three behave alike" on its own, which a table that also
# moved `sentry` onto the clean line would satisfy.
#
# HOW THE ASYMMETRY IS TESTED, and why it is not a negation check. Three separate
# attempts at "assert the phrase, then veto the word `no`" were each defeated by a
# rewording: `**no** blind-spot row`, then `never`, `does not`, `no such`, and
# `aligned with the other three`. Enumerating negations is unwinnable. So the two
# outcomes are given MUTUALLY EXCLUSIVE vocabularies instead, and every rule is
# required to speak exactly one of them: a rule that routes a key to the clean
# line cannot avoid naming the clean line, and a rule that keeps a row cannot
# avoid the affirmative "gets/keeps a blind-spot row". Rewording inside one
# vocabulary is free; crossing into the other is what fails.
CLEAN_VOCAB='\(n/a\)|clean line|Clean today'
BLIND_AFFIRM='(gets|keeps|renders|carries|receives|earns)( its own)?( a| one)? ?blind-spot row'

echo "-- the four-key \`none\` form, and its deliberate asymmetry (#261)"

# Window of flattened text starting at a literal marker, empty when the marker is
# absent. Pure parameter expansion — no awk, no regex — because the markers carry
# backticks and colons, the haystacks are single ~40KB lines, and `#*` takes the
# SHORTEST match, i.e. the FIRST occurrence. Verified under bash 3.2 (macOS
# /bin/bash) as well as 5.x, so no awk-dialect or long-line buffer question
# arises between a local run and CI's.
window_after() {
    local hay="$1" mark="$2" n="$3" rest
    rest="${hay#*"$mark"}"
    [ "$rest" = "$hay" ] && return 0
    printf '%s' "$mark${rest:0:n}"
}

# Same, but ALSO cut at the first of any number of stop markers. A constant
# length is wrong in both directions, and both were measured on this file: too
# short turns a must-not-exist into a false pass (§3A's Sentry rule is ~930B and
# a 460B window read half of it, so appending a clean-line clause passed), too
# long lets one key's assertions be satisfied by the NEXT key's rule — or, for
# the last key in a section, by whatever section follows it. Every §3 window
# therefore stops at `No key at all`, the phrase each of the four rules uses to
# hand over to its own absent-key case: that bounds the window to the `none`
# clause itself rather than to a byte count, and it is what keeps the adjacent
# `… **and a blind-spot row in §6**` (a statement about the ABSENT key) out of
# the `none` rule's window. `%%` cuts at the FIRST occurrence of the stop.
window_between() {
    local hay="$1" mark="$2" n="$3" rest cut stop
    shift 3
    rest="${hay#*"$mark"}"
    [ "$rest" = "$hay" ] && return 0
    cut="${rest:0:n}"
    for stop in "$@"; do
        [ -n "$stop" ] || continue
        case "$cut" in *"$stop"*) cut="${cut%%"$stop"*}" ;; esac
    done
    printf '%s' "$mark$cut"
}

# Data rows of a markdown table: leading `|`, minus the header and the `---`
# separator. Deliberately NOT keyed on a backtick — a row a human hand-adds
# without code formatting is exactly the fifth key this must catch, and an
# earlier `awk '/^| `/'` filter counted a five-row table as four.
table_rows() {
    printf '%s\n' "$1" | awk '
        /^\|/ {
            if ($0 ~ /^\|[ :|-]*$/) next
            if ($0 ~ /\|[ ]*Config[ ]*\|/) next
            print
        }'
}
cell() { printf '%s' "$1" | awk -F'|' -v n="$2" '{gsub(/^[ `*]+|[ `*]+$/, "", $n); print $n}'; }

# --- I1. The four-key table -----------------------------------------------------

asym_section="$(printf '%s\n' "$exception_section" | awk '/^#### The four keys/{f=1; next} /^#/{f=0} f')"

if [ -n "$asym_section" ]; then
    ok "config-contract.md carries the four-key asymmetry subsection"
else
    bad "the four-key \`none\` asymmetry subsection is gone from config-contract.md"
fi

# Every row is CLASSIFIED and the classification must be exhaustive. Tallying two
# patterns is not enough: a fifth key whose behaviour column matches neither is
# invisible to a tally, which falsified this gate's own claim that counting
# catches a grown table.
asym_keys="" n_rows=0 n_blind=0 n_clean=0 n_other=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    n_rows=$((n_rows + 1))
    k="$(cell "$row" 2)"
    b="$(cell "$row" 4)"
    asym_keys="${asym_keys}[$k]"
    # A table cell has no verb, so its affirmative marker is `kept`. A negated
    # cell ("**no** blind-spot row (aligned with the other three)") lacks it.
    if printf '%s' "$b" | grep -qi 'blind-spot row' &&
       printf '%s' "$b" | grep -qi 'kept' &&
       ! printf '%s' "$b" | grep -qiE "$CLEAN_VOCAB"; then
        n_blind=$((n_blind + 1))
        blind_key="$k"
    elif printf '%s' "$b" | grep -qiE "$CLEAN_VOCAB" &&
         ! printf '%s' "$b" | grep -qi 'blind-spot row'; then
        n_clean=$((n_clean + 1))
    else
        n_other=$((n_other + 1))
        other_desc="${other_desc:-}[$k -> $b]"
    fi
done <<EOF
$(table_rows "$asym_section")
EOF

if [ "$n_rows" = 4 ]; then
    ok "the four-key table has exactly four rows"
else
    bad "the four-key table has $n_rows rows, not four — a key was added or lost"
fi

if [ "$n_other" = 0 ]; then
    ok "every row speaks exactly one of the two outcome vocabularies"
else
    bad "$n_other row(s) match neither outcome cleanly: ${other_desc:-}"
fi

if [ "$n_blind" = 1 ] && [ "${blind_key:-}" = "sentry: none" ]; then
    ok "exactly one key keeps a blind-spot row, and it is \`sentry: none\`"
else
    bad "the blind-spot row is not \`sentry: none\` alone (n=$n_blind, key=${blind_key:-none})"
fi

if [ "$n_clean" = 3 ]; then
    ok "exactly three keys render on the clean line"
else
    bad "$n_clean keys render on the clean line, not three"
fi

for k in 'sentry: none' 'testflight: none' 'posthog: none' 'mobile: none'; do
    case "$asym_keys" in
        *"[$k]"*) ok "the table still carries \`$k\`" ;;
        *) bad "the table no longer carries \`$k\`" ;;
    esac
done

# --- I2. The three-state table (#213), cut by its OWN bounds -------------------
#
# The four-key table now nests inside `exception_section`, so the #213 loop above
# sees two tables and only the accidental "blind spot"/"blind-spot" spelling
# difference keeps them apart. This slices the #213 table alone and requires it
# to hold exactly its three states.
three_state="$(printf '%s\n' "$exception_section" | awk '/^Three states, all distinct:/{f=1; next} /^####/{f=0} f')"
ts_rows="$(table_rows "$three_state" | awk 'END{print NR}')"
if [ "$ts_rows" = 3 ]; then
    ok "the three-state table holds exactly three states"
else
    bad "the three-state table holds $ts_rows rows, not three"
fi

# ...and its `sentry: none` MEANING cell must not make the over-claim. The row
# loop in section D reads only the key and behaviour columns, so before this the
# defining site could revert to "this repo has no error monitoring" untouched.
ts_meaning=""
while IFS= read -r row; do
    [ -n "$row" ] || continue
    [ "$(cell "$row" 2)" = "sentry: none" ] && ts_meaning="$(cell "$row" 3)"
done <<EOF
$(table_rows "$three_state")
EOF
if printf '%s' "$ts_meaning" | grep -qi 'verified'; then
    ok "the three-state table scopes \`sentry: none\` to verification"
else
    bad "the three-state table's \`sentry: none\` meaning is not scoped to verification (got: ${ts_meaning:-<none>})"
fi

# --- I3. The contract's rationales and exclusions ------------------------------

if printf '%s' "$contract_flat" |
   grep -qi 'error monitoring is a gap somebody could close; an absent mobile app is a product fact'; then
    ok "the contract keeps the gap-versus-product-fact rationale"
else
    bad "the contract lost the rationale for the asymmetry (gap vs product fact)"
fi

if printf '%s' "$contract_flat" | grep -qi 'Do not "align the .none. forms'; then
    ok "the contract warns against aligning the \`none\` forms"
else
    bad "the contract no longer warns a sweep off aligning the \`none\` forms"
fi

if printf '%s' "$contract_flat" | grep -qiE 'A second reason, and it applies to .sentry:. alone'; then
    ok "the contract carries the second reason (\`sentry: none\` means two things)"
else
    bad "the contract lost the two-outcomes reason for keeping sentry's row"
fi

if printf '%s' "$contract_flat" | grep -qi 'unfinished verification wearing the same value'; then
    ok "the contract names the unverifiable outcome as not a confirmed absence"
else
    bad "the contract no longer distinguishes confirmed-absent from could-not-verify"
fi

if printf '%s' "$contract_flat" | grep -qi 'Why this section is still headed'; then
    ok "the contract records why the heading still names \`sentry: none\` alone"
else
    bad "the contract no longer explains its heading/body mismatch"
fi

if printf '%s' "$contract_flat" | grep -qi '.posthog: false. is not one of the forms'; then
    ok "the contract rules \`posthog: false\` out as a config form"
else
    bad "the contract no longer rules out \`posthog: false\`"
fi

for excl in '`board:` is excluded' '`stacked_prs:` is excluded' \
            '`review_agent:` and `review_site:` are excluded' \
            'None of them render a blind-spot row' \
            '`ci_workflow:` is excluded'; do
    if printf '%s' "$contract_flat" | grep -qiF "$excl"; then
        ok "exclusion stated: $excl"
    else
        bad "the contract lost an exclusion: $excl"
    fi
done

if printf '%s' "$contract_flat" | grep -qi 'boardless form'; then
    ok "the \`board:\` exclusion carries its reason (§3B's boardless form)"
else
    bad "the \`board:\` exclusion lost its reason"
fi

# The four-key claim, at the three sites that state it in prose rather than in the
# table. Each could be reverted to one key while the table still claims four.
if printf '%s' "$contract_flat" | grep -qiE 'scoped to the four keys whose absence'; then
    ok "the contract's scope sentence still names four keys"
else
    bad "the contract's scope sentence no longer names four keys"
fi

if printf '%s' "$contract_flat" | grep -qiE 'Four of these keys .{0,80}additionally accept the scalar'; then
    ok "the shared-blocks note still names four keys accepting \`none\`"
else
    bad "the shared-blocks note no longer names the four keys accepting \`none\`"
fi

# Mutation proofs: the pre-#261 sentences. Run against an EMPHASIS-STRIPPED
# flatten as well as the plain one — this repo bolds contract claims constantly,
# and `The exception is scoped to **\`sentry:\`** alone.` slipped past a check on
# the plain flatten alone.
contract_bare="$(printf '%s' "$contract_flat" | tr -d '*_')"
if printf '%s' "$contract_bare" | grep -qi 'The exception is scoped to .sentry:. alone'; then
    bad "the contract reverted to scoping the exception to \`sentry:\` alone"
else
    ok "the contract no longer scopes the exception to \`sentry:\` alone"
fi

if printf '%s' "$contract_bare" | grep -qi 'No other key has a .none. form'; then
    bad "the contract still claims no other key has a \`none\` form"
else
    ok "the contract carries no 'no other key has a \`none\` form' claim"
fi

# The banned gloss, everywhere it can be written — not just in the plate's row.
# Measured: the contract's own YAML sample and the rendered template both carried
# `# or \`sentry: none\` — confirmed: no error monitoring`, the exact wording
# detection.md forbids, in the same diff that added the ban.
template_bare="$(tr '\n' ' ' < "$TEMPLATE" | tr -s ' ' | tr -d '*_')"
# The banned LABEL forms only. The contract legitimately *enumerates* the two
# meanings ("means two: this repo has no error monitoring, or the culprit check
# could not run"), which is the explanation rather than the gloss. A function
# rather than a loop over "$name:$hay" pairs: the `${pair#*:}` split put a `#`
# inside the pipeline, and scripts/test-pipefail-grep.sh — deliberately syntactic
# — read the writer stage as a bare quote and flagged it.
GLOSS='confirmed: no error monitoring|confirmed( at setup)?( that)? this repo has no error monitoring'
check_gloss() {
    local where="$1" hay="$2"
    if printf '%s' "$hay" | grep -qiE "$GLOSS"; then
        bad "$where glosses \`sentry: none\` as a plain absence — detection.md forbids exactly this"
    else
        ok "$where makes no bare no-error-monitoring claim"
    fi
}
check_gloss "config-contract.md" "$contract_bare"
check_gloss "the rendered template" "$template_bare"

# --- I4. survey-work's §3 pull rules ------------------------------------------

plate_flat="$(tr '\n' ' ' < "$PLATE" | tr -s ' ')"

# Scoped to the PULL section (§3), where each surface's probe rule lives — not to
# the whole file. A whole-file window lands on §6's prose instead, so a probe rule
# that lost its `none` clause reads as covered while §3 still routes a confirmed
# absence to "no block -> blind-spot row". Measured: that mutation came back
# UNDETECTED against the unscoped window.
plate_pulls="$(awk '/^## 3\. /{f=1; next} /^## 4\./{f=0} f' "$PLATE" | tr '\n' ' ' | tr -s ' ')"
if [ -n "$plate_pulls" ]; then
    ok "located survey-work's §3 surface pulls"
else
    bad "cannot locate survey-work's '## 3.' surface-pull section"
fi

K_SENTRY='`sentry: none`' K_TF='`testflight: none`'
K_PH='`posthog: none`' K_MO='`mobile: none`'
# Every rule hands over to its absent-key case with this phrase, so it is the
# structural end of the `none` clause — a better bound than any byte count, and
# the thing that keeps the absent-key case's own "and a blind-spot row in §6"
# out of the `none` rule's window.
K_END='No key at all'

for key in testflight posthog mobile; do
    case "$key" in
        testflight) s1="$K_SENTRY" s2="$K_PH"  s3="$K_MO" ;;
        posthog)    s1="$K_SENTRY" s2="$K_TF"  s3="$K_MO" ;;
        mobile)     s1="$K_SENTRY" s2="$K_TF"  s3="$K_PH" ;;
    esac
    win="$(window_between "$plate_pulls" "\`$key: none\`" 1200 "$K_END" "$s1" "$s2" "$s3")"
    if [ -z "$win" ]; then
        bad "survey-work's §3 pull rule states nothing for \`$key: none\`"
        continue
    fi
    if printf '%s' "$win" | grep -qiE "$CLEAN_VOCAB"; then
        ok "\`$key: none\` routes to the clean line"
    else
        bad "\`$key: none\` no longer routes to the clean line"
    fi
    if printf '%s' "$win" | grep -qi '(n/a)'; then
        ok "\`$key: none\` carries the \`(n/a)\` marker"
    else
        bad "\`$key: none\` lost the \`(n/a)\` marker that distinguishes it from empty"
    fi
    if printf '%s' "$win" | grep -qiE "$BLIND_AFFIRM"; then
        bad "\`$key: none\` claims a blind-spot row — that is \`sentry: none\`'s behaviour"
    else
        ok "\`$key: none\` claims no blind-spot row"
    fi
    # The collapse this whole form exists to prevent, in the other direction: a
    # confirmed absence described as something the plate failed to look at.
    if printf '%s' "$win" | grep -qi 'not checked'; then
        bad "\`$key: none\` is worded as an unchecked surface"
    else
        ok "\`$key: none\` is not worded as an unchecked surface"
    fi
done

# §3A's Sentry rule is the INVERSE of those three, and the loop above must never
# be widened to cover it. Measured: with `sentry` outside the loop, rewriting §3A
# to render `sentry: none` on the clean line left this gate GREEN — the headline
# decision unpinned in the very section the loop declares authoritative. The two
# vetoes below are the exclusive-vocabulary test, not a negation check; the
# affirmative pattern is what a table cell's `kept` is for prose.
sentry_win="$(window_between "$plate_pulls" "$K_SENTRY" 1600 "$K_END" "$K_TF" "$K_PH" "$K_MO")"
if [ -z "$sentry_win" ]; then
    bad "survey-work's §3 pull rule states nothing for \`sentry: none\` — it reads as unconfigured"
else
    ok "survey-work's §3 pull rule states the \`sentry: none\` case"
    if printf '%s' "$sentry_win" | grep -qiE "$BLIND_AFFIRM"; then
        ok "\`sentry: none\` affirmatively keeps its blind-spot row in §3"
    else
        bad "\`sentry: none\` no longer affirmatively keeps a blind-spot row in §3"
    fi
    if printf '%s' "$sentry_win" | grep -qiE "$CLEAN_VOCAB"; then
        bad "\`sentry: none\` was moved onto the clean line — it speaks the clean-line vocabulary"
    else
        ok "\`sentry: none\` speaks none of the clean-line vocabulary"
    fi
    # Anchored to the phrase, not to the bare word `confirmed`, which the
    # neighbouring "§6's *Confirmed N/A* rule" reference supplies for free.
    if printf '%s' "$sentry_win" | grep -qi 'worded as confirmed'; then
        ok "\`sentry: none\` is worded as confirmed in §3, not as unconfigured"
    else
        bad "\`sentry: none\` is no longer explicitly worded as confirmed in §3"
    fi
fi

# The veto again, over the WHOLE Sentry rule rather than the `none` clause. The
# `none` window stops at `No key at all`, which is correct for the affirmative
# checks — but it means a contradictory clean-line instruction appended to the
# rule's *absent-key* half sits outside it, and §3A would then say both things.
# Measured: that mutation was undetected against the windowed veto alone. Sentry
# never reaches the clean line in EITHER state, so the whole rule may not speak
# that vocabulary.
sentry_rule="$(window_between "$plate_pulls" '**Sentry** —' 2200 '**GitHub bugs**')"
if [ -z "$sentry_rule" ]; then
    bad "cannot locate survey-work's §3A Sentry rule"
else
    ok "located survey-work's §3A Sentry rule"
    if printf '%s' "$sentry_rule" | grep -qiE "$CLEAN_VOCAB"; then
        bad "§3A's Sentry rule speaks the clean-line vocabulary somewhere — Sentry never goes there"
    else
        ok "§3A's Sentry rule never routes Sentry to the clean line, in either state"
    fi
fi

# --- I5. survey-work's §6 render rules ----------------------------------------

if printf '%s' "$plate_flat" | grep -qiE 'Four of those keys also accept the scalar .none.'; then
    ok "survey-work §1 states the four-key form itself"
else
    bad "survey-work §1 no longer states which keys accept \`none\`"
fi

if printf '%s' "$plate_flat" | grep -qiE 'Confirmed N/A is a[n]? (THIRD|3rd) state'; then
    ok "survey-work §6 names confirmed-N/A as a third state, distinct from empty"
else
    bad "survey-work §6 no longer distinguishes confirmed-N/A from checked-and-empty"
fi

# The RENDER RULE itself, which an agent follows — not merely the sentence that
# announces it. Measured: rewriting this to "get a blind-spot row like any other
# dark surface" left every other §6 assertion satisfied.
na_rule="$(window_between "$plate_flat" 'Confirmed N/A is a THIRD state' 1400 'Skip empty P-buckets')"
if [ -z "$na_rule" ]; then
    bad "cannot locate §6's Confirmed-N/A rule body"
else
    if printf '%s' "$na_rule" | grep -qiE "$CLEAN_VOCAB"; then
        ok "§6's Confirmed-N/A rule routes the three keys to the clean line"
    else
        bad "§6's Confirmed-N/A rule no longer routes the three keys to the clean line"
    fi
    if printf '%s' "$na_rule" | grep -qiE "$BLIND_AFFIRM"; then
        bad "§6's Confirmed-N/A rule now gives the three keys a blind-spot row"
    else
        ok "§6's Confirmed-N/A rule gives the three keys no blind-spot row"
    fi
    for k in testflight posthog mobile; do
        if printf '%s' "$na_rule" | grep -qF "\`$k: none\`"; then
            ok "§6's Confirmed-N/A rule names \`$k: none\`"
        else
            bad "§6's Confirmed-N/A rule no longer names \`$k: none\`"
        fi
    done
fi

# The `✓ Clean today:` template line is the literal block a plate is copied from.
if printf '%s' "$plate_flat" | grep -qi 'Clean today: <checked-and-empty surface>'; then
    ok "§6's output template shows the confirmed-absent token on the clean line"
else
    bad "§6's output template no longer shows a confirmed-absent token"
fi

if printf '%s' "$plate_flat" | grep -qiE '[*]{0,2}no[*]{0,2} .skipped [^ ]* token on the sources line'; then
    ok "a confirmed-absent surface takes no \`skipped —\` token on the sources line"
else
    bad "survey-work does not exempt a confirmed-absent surface from the sources-line token"
fi

if printf '%s' "$plate_flat" | grep -qiE 'Never widen it into a claim that the repo has no Sentry'; then
    ok "survey-work forbids widening the row into a no-Sentry claim"
else
    bad "survey-work lost the ban on widening \`sentry: none\` into a no-Sentry claim"
fi

plate_rules="$(awk '/^### Blind spots/{f=1; next} /^#{1,3} /{f=0} f' "$PLATE" | tr '\n' ' ' | tr -s ' ')"
if [ -n "$plate_rules" ]; then
    ok "located survey-work's Blind spots rules"
else
    bad "cannot locate survey-work's '### Blind spots' subsection"
fi

if printf '%s' "$plate_rules" | grep -qi 'A confirmed absence is not a dark surface' &&
   printf '%s' "$plate_rules" | grep -qi 'no row at all'; then
    ok "the Blind spots rules exclude a confirmed absence from the section"
else
    bad "the Blind spots rules no longer exclude a confirmed absence"
fi

if printf '%s' "$plate_rules" | grep -q 'sentry: none' &&
   printf '%s' "$plate_rules" | grep -qi 'produces a row'; then
    ok "the Blind spots rules keep \`sentry: none\` as the one exception"
else
    bad "the Blind spots rules dropped \`sentry: none\`'s surviving row"
fi

# The example block is what an agent copies. FLATTENED, per this script's own rule
# at the top: MD013 is off here, so a hard-wrapped row is invisible to a
# line-scoped grep and reports a FALSE PASS. Measured both ways.
plate_blind_flat="$(printf '%s\n' "$plate_blind" | tr '\n' ' ' | tr -s ' ')"
for key in testflight posthog mobile; do
    if printf '%s' "$plate_blind_flat" | grep -qi "$key: none"; then
        bad "survey-work's blind-spot example still renders a \`$key: none\` row"
    else
        ok "survey-work's blind-spot example renders no \`$key: none\` row"
    fi
done

# --- I6. The three `none` values are ASKED, never defaulted -------------------

q2c="$(awk '/^### 2c\./{f=1; next} /^### /{f=0} f' "$INTERVIEW" | tr '\n' ' ' | tr -s ' ')"

if [ -n "$q2c" ]; then
    ok "interview.md carries the confirmed-absent question (§2c)"
else
    bad "interview.md has no confirmed-absent question — the three keys cannot be set"
fi

for key in testflight posthog mobile; do
    if printf '%s' "$q2c" | grep -qF "\`$key: none\`"; then
        ok "§2c names the \`$key: none\` value it writes"
    else
        bad "§2c never names \`$key: none\` — the key it covers is unstated"
    fi
done

# The TRIGGER. "Keys detection could not establish" silently excluded `posthog`,
# whose detector always answers true/false — so the key that motivated the form
# was unreachable on the very path that writes it.
if printf '%s' "$q2c" | grep -qi 'would otherwise leave'; then
    ok "§2c triggers on a key being left absent, not on detection failing"
else
    bad "§2c's trigger is not the absent-key one — \`posthog\` may be unreachable again"
fi

if printf '%s' "$q2c" | grep -qi 'always answers'; then
    ok "§2c names why \`posthog\` needs the absent-key trigger"
else
    bad "§2c no longer explains why a detection-based trigger excluded \`posthog\`"
fi

# All THREE generator modes must reach it. Migrate mode is the one most likely to
# need it — a legacy render can never supply a `none` — and it was unreachable.
# Emphasis-stripped: the modes are named as **create** mode / **update** mode,
# so a plain-substring check for "create mode" misses them.
q2c_bare="$(printf '%s' "$q2c" | tr -d '*_')"
for mode in create update migrate; do
    # The LIST ENTRY, not a mention. A bare `grep "migrate mode"` is satisfied by
    # a sentence that demotes the mode ("Migrate mode inherits whatever the
    # legacy render supplied"), which is the inversion this must catch.
    if printf '%s' "$q2c_bare" | grep -qi "In $mode mode:"; then
        ok "§2c commits to asking in $mode mode"
    else
        bad "§2c does not commit to asking in $mode mode — that path leaves the keys absent"
    fi
done

if printf '%s' "$q2c" | grep -qi 'never default'; then
    ok "§2c forbids defaulting a \`none\`"
else
    bad "§2c no longer forbids defaulting a \`none\`"
fi

if printf '%s' "$q2c" | grep -qi 'Do not offer the same question for .sentry:.'; then
    ok "§2c keeps \`sentry:\` out of the confirmed-absent question"
else
    bad "§2c no longer excludes \`sentry:\` from the confirmed-absent question"
fi

# A legacy `posthog: false` is neither absent nor a legal form, so an
# absent-only trigger drops it silently and the row survives.
# Three parts, because the trigger sentence and its explanation can be made to
# contradict each other: the rule itself, the explicit rejection of absent-only,
# and the value it exists for. Measured: narrowing only the explanation to "an
# absent key is the only case" left a two-part check green.
if printf '%s' "$q2c" | grep -qi 'leave carrying a value the contract no longer defines' &&
   printf '%s' "$q2c" | grep -qi 'not "absent" alone' &&
   printf '%s' "$q2c" | grep -qi 'posthog: false'; then
    ok "§2c's trigger covers a legacy \`posthog: false\`, not only an absent key"
else
    bad "§2c's trigger is absent-only — a legacy \`posthog: false\` is dropped and the row survives"
fi

# --- I7. A refresh carries a `none` forward, never re-asking ------------------

update_flat="$(tr '\n' ' ' < "$UPDATE" | tr -s ' ')"

carry_win="$(window_between "$update_flat" '**A `none` is an answer already given' 900 '**Do not read that')"
if [ -z "$carry_win" ]; then
    bad "update mode has no carry-a-\`none\`-forward rule"
else
    ok "update mode carries the carry-a-\`none\`-forward rule"
    if printf '%s' "$carry_win" | grep -qi 'never re-ask'; then
        ok "the rule forbids re-asking an existing \`none\`"
    else
        bad "the rule no longer forbids re-asking an existing \`none\`"
    fi
    # Anchored to the phrase. A bare `grep -qi confirmation` is satisfied by the
    # window's own opening sentence, which made this assertion unfailable.
    if printf '%s' "$carry_win" | grep -qiE 'cannot re-derive is the .{0,4}confirmation'; then
        ok "the rule names the CONFIRMATION as the thing that cannot be re-derived"
    else
        bad "the rule no longer says it is the confirmation that cannot be re-derived"
    fi
    # `sentry: none` must NOT be in this carve-out: detection.md writes it when
    # there is no MCP server or no issues to sample, both transient session
    # conditions, so freezing it would let one unlucky run permanently retire the
    # highest-signal surface with no recovery path.
    if printf '%s' "$carry_win" | grep -qi 're-derived on every refresh'; then
        ok "\`sentry: none\` is re-derived on a refresh, not frozen"
    else
        bad "\`sentry: none\` is frozen by the carve-out — one bad session retires Sentry forever"
    fi
fi

pos_win="$(window_between "$update_flat" '**Positive evidence against a `none`' 700 '**An ABSENT one')"
if [ -z "$pos_win" ]; then
    bad "update mode has no rule for positive evidence against a \`none\`"
else
    ok "update mode carries the positive-evidence rule"
    if printf '%s' "$pos_win" | grep -qi 'stop and surface'; then
        ok "positive evidence against a \`none\` is a stop-and-surface"
    else
        bad "positive evidence against a \`none\` is no longer a stop-and-surface"
    fi
    if printf '%s' "$pos_win" | grep -qiE '[Nn]ever silently rewrite'; then
        ok "a contradicted \`none\` is never silently rewritten"
    else
        bad "update mode lost the never-silently-rewrite rule"
    fi
fi

absent_win="$(window_between "$update_flat" '**An ABSENT one of these keys' 1200 '**Migrate mode inherits')"
if [ -z "$absent_win" ]; then
    bad "update mode has no path to WRITE a \`none\` — the rollout is a no-op"
else
    ok "update mode has a path to write a \`none\` for an absent key"
    if printf '%s' "$absent_win" | grep -q '§2c'; then
        ok "an absent key routes to interview §2c"
    else
        bad "the absent-key path names no question to ask"
    fi
    if printf '%s' "$absent_win" | grep -qi 'Do not gate that on the tree being quiet'; then
        ok "the absent-key path is not gated on a quiet tree"
    else
        bad "the absent-key path is gated on a quiet tree — a dismissed hit is skipped"
    fi
    if printf '%s' "$absent_win" | grep -qi 'posthog: false'; then
        ok "the absent-key path also covers a legacy \`posthog: false\`"
    else
        bad "the absent-key path ignores a legacy \`posthog: false\`"
    fi
    if printf '%s' "$absent_win" | grep -qi 'Not sure'; then
        ok "the absent-key path keeps an answer that leaves the key absent"
    else
        bad "the absent-key path no longer offers an answer that leaves the key absent"
    fi
fi

# Mutation proof: the claim this rule shipped with and which is FALSE —
# `detect-capabilities.sh` derives `posthog` outright, and detection proposes all
# three. An agent that believes it never runs the tree check the rule depends on.
if printf '%s' "$update_flat" | tr -d '*_' | grep -qi 'None of the four is re-derivable'; then
    bad "update mode reasserts that none of the four is re-derivable (posthog is)"
else
    ok "update mode makes no blanket not-re-derivable claim"
fi

# Migrate mode reaches the same absent-key state, and its own doc is a different
# file. A note here is not enough on its own, so both are required.
if printf '%s' "$update_flat" | grep -qi 'Migrate mode inherits'; then
    ok "update-mode.md hands the rule to migrate mode"
else
    bad "update-mode.md says nothing about migrate mode, which needs this most"
fi

migrate_flat="$(tr '\n' ' ' < "$MIGRATE" | tr -s ' ')"
if printf '%s' "$migrate_flat" | grep -qi 'ask §2c for the three confirmed-absent keys' &&
   printf '%s' "$migrate_flat" | grep -qi 'extraction can never produce one'; then
    ok "migrate-mode.md has its own step asking §2c for the three keys"
else
    bad "migrate-mode.md has no §2c step — every migrated repo keeps the rows"
fi

# --- I8. setup-config/SKILL.md carries the three rules too --------------------
#
# SKILL.md is loaded on EVERY invocation while `references/` are read on demand,
# and CLAUDE.md's "SKILL.md stays thin" rule is an active reason a later sweep
# deletes these. Measured: inverting all three left this gate green, because §F
# above greps `skill_flat` only for #213's strings.

nodefault_win="$(window_between "$skill_flat" '**Never default a confirmed-absent `none`.**' 700 '## Phase 3')"
if [ -z "$nodefault_win" ]; then
    bad "setup-config/SKILL.md has no never-default-a-\`none\` rule"
else
    ok "setup-config/SKILL.md forbids defaulting a \`none\`"
    if printf '%s' "$nodefault_win" | grep -q '§2c'; then
        ok "Phase 2 routes the three keys to interview §2c"
    else
        bad "Phase 2 no longer names §2c as the only writer of the three keys"
    fi
    if printf '%s' "$nodefault_win" | grep -qi 'quiet tree'; then
        ok "Phase 2 names the trap (a quiet tree is not a confirmation)"
    else
        bad "Phase 2 no longer explains why detection alone cannot write a \`none\`"
    fi
fi

phase4_win="$(window_between "$skill_flat" '**The three `none` answers are carried forward' 900 'Apply per file')"
if [ -z "$phase4_win" ]; then
    bad "setup-config/SKILL.md Phase 4 states nothing about the \`none\` answers"
else
    ok "setup-config/SKILL.md Phase 4 covers the \`none\` answers"
    if printf '%s' "$phase4_win" | grep -qi 'not re-asked'; then
        ok "Phase 4 carries an existing \`none\` forward"
    else
        bad "Phase 4 no longer carries an existing \`none\` forward"
    fi
    if printf '%s' "$phase4_win" | grep -q '§2c'; then
        ok "Phase 4 asks §2c where one of the three keys is missing entirely"
    else
        bad "Phase 4 has no path to write a \`none\` for a missing key"
    fi
    if printf '%s' "$phase4_win" | grep -qi 'sentry' &&
       printf '%s' "$phase4_win" | grep -qi 're-derived'; then
        ok "Phase 4 keeps \`sentry: none\` out of the carve-out"
    else
        bad "Phase 4 does not exclude \`sentry: none\` from the carry-forward carve-out"
    fi
fi

nevercopy="$(printf '%s' "$skill_flat" |
    grep -oE 'Never copy a fact forward without re-verifying it against live state[^.]*\.')"
if [ -z "$nevercopy" ]; then
    bad "cannot locate setup-config's never-copy-a-fact-forward guardrail"
else
    ok "located the never-copy-a-fact-forward guardrail"
    if printf '%s' "$nevercopy" | grep -q '`none`'; then
        ok "the never-copy guardrail names the \`none\` answers as an exception"
    else
        bad "the never-copy guardrail no longer excepts the \`none\` answers"
    fi
fi

# --- I9. The rendered template names the form and its asymmetry --------------

if printf '%s' "$header_flat" | grep -qi 'FOUR keys carry it'; then
    ok "the template header names all four keys carrying the \`none\` form"
else
    bad "the template header no longer names the four-key \`none\` form"
fi

if printf '%s' "$header_flat" | grep -qi 'only .sentry: none. still renders a blind-spot'; then
    ok "the template header states the asymmetry"
else
    bad "the template header no longer states which key keeps its blind-spot row"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-sentry-verification: FAILED ($fails)" >&2
    exit 1
fi
echo "Sentry verification tests: all green"
