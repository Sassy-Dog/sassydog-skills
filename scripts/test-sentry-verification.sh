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
# Four decisions are pinned, and the last three are the fragile ones:
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
#   D. The CARRY-FORWARD carve-out covers those same three and NOT `sentry:`
#      (issue #268). `setup-config` writes `sentry: none` when the culprit check
#      merely COULD NOT RUN — no MCP server, no issues to sample — so freezing it
#      lets one unlucky session permanently retire the plate's highest-signal
#      surface, the only contradicting evidence being the check the carve-out
#      just skipped. The three/four split is asserted on all four sites that
#      state it: `SKILL.md`'s Guardrails list (which CLAUDE.md names as the copy
#      to trust), `SKILL.md` Phase 4, `config-contract.md`, and `update-mode.md`.
#      #267 added `sentry:` to the guardrail list while removing it from the
#      other two, so the same file contradicted itself forty lines apart and
#      nothing here noticed.
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
# SIX ways this gate was MEASURED reporting a clean tree on a source stating the
# inverse. Every one is a scoping error, and every fix is the same shape:
#
#   * §6's Confirmed-N/A rule stated BOTH outcomes inside ONE window, so neither
#     was pinned (issue #268). Replacing "**`sentry: none` is the deliberate
#     exception and keeps its blind-spot row**" with "…is aligned with the other
#     three and takes the clean line too" left this gate GREEN — deleting
#     sentry's affirmation made the three-key row veto MORE likely to pass, not
#     less. #213's gap restored in the one section an agent follows when
#     rendering, and §3A was already carrying the identical lesson. The block is
#     now cut at the key literal, sentry's half carrying the INVERTED
#     expectations, and that half must never be folded back into the loop.
#   * The `### Blind spots` rules were checked by CO-OCCURRENCE — `sentry: none`
#     anywhere in the subsection AND `produces a row` anywhere in it — so
#     swapping which key gets the row satisfied both halves and stayed GREEN.
#     Split per key, same shape as §6.
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
# keeping. FOUR review rounds have each found assertions here passing on sources
# that state the inverse, and the reason the author's own mutation set kept
# reporting "all detected" is that every mutation was written by deleting the
# exact literal its assertion greps for. Such a set is tautologically caught: it
# proves `grep` works, not that the assertion pins a decision. A mutation must
# invert the MEANING and be worded the way a tidying editor would word it —
# different verb, different emphasis, different sentence shape.
#
# **NO INVENTORY NUMBER IS CARRIED HERE, DELIBERATELY.** This header used to
# claim a mutation count and an assertion count; both were wrong, and CLAUDE.md
# repeated one of them into the one place a future editor trusts instead of
# re-measuring (issue #268). A number nobody can re-derive from the tree is not
# worth carrying. The run prints its own assertion count, and the mutation
# batteries live in the PR that added them — re-measure rather than transcribe.
#
# The failure family is always the same:
#
#   * NEGATION-BLINDNESS, and the two failed attempts at fixing it. `grep -qi
#     'blind-spot row'` matches inside "**no** blind-spot row". Vetoing the word
#     `no` anywhere in the window was tried three times and defeated each time,
#     because it vetoed a negator that merely SHARED the window rather than one
#     GOVERNING the mention. The six-verb affirmative that replaced it enumerated
#     an OPEN class, so `plus a blind-spot row in §6` and `also produces` evaded
#     it while the correct rewords `keeps a blind-spot row` and `gets its own
#     blind-spot row` reddened the gate on prose that was RIGHT — measured, six
#     correct edits turned `main` red. Destinations are now matched
#     verb-independently and each mention is classified against its own bounded
#     left context, against a negator set whose CORE is a closed grammatical
#     class, resolved by polarity rather than by list length. See `dest_tally`.
#   * A MARKER IS NOT A DESTINATION. `\(n/a\)` sat inside the clean-line
#     vocabulary, so "they appear under Blind spots with an explicit `(n/a)`
#     marker" satisfied a clean-line assertion, and §3A's Sentry rule reddened
#     the moment it named the marker it must not use. Separate constants now.
#   * POLARITY, NOT A LONGER LIST. `is not exempt from a blind-spot row` AFFIRMS
#     the row, and `exempt`/`excluded`/`omitted` are words this file's own header
#     cites as natural here — so reading them as negations put the inverse of
#     #261 past both the `'0'` and the stricter `'-'` veto at every call site.
#     The fix is `cancelled()`: a second negator governing the first flips the
#     polarity back. Adding words to the negator list is the move that feels
#     like the fix and is not — that is what the six-verb `BLIND_AFFIRM` did.
#   * SILENCE IS NOT A NEGATION. `'0'` tested only "nothing affirmed", so a rule
#     whose negative clause drifted out of its window scored 0/0 and the veto
#     printed `ok` while measuring nothing. Rules that STATE a negative now use
#     `'-'`, which requires the negation to be present and measured.
#   * WINDOW SIZING, wrong in both directions: 460 bytes read half of a ~930-byte
#     rule and a must-not-exist slipped past; 400 bytes let one key's assertions
#     be satisfied by the next key's rule, ~158 bytes away. Hence `window_between`
#     and the structural `No key at all` bound. And a cap that binds BEFORE its
#     stop marker is the same defect wearing the other face — `carry_win`'s last
#     asserted phrase ended at byte 933 of a 937-byte window — so
#     `window_is_bounded` now asserts every such window ends where it says it
#     does.
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
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1"; }
bad() { asserts=$((asserts + 1)); echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

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
    awk '/^### The one exception/{f=1; next} /^## / || /^### /{f=0} f')"

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
# Each `- ` row re-joined into ONE record before it is matched, the same unit
# detection.md's hand-check bullets get above. A line-scoped `grep` over this
# block was a false PASS waiting to happen: MD013 is off in this repo and the
# `sentry: none` row is 261 characters, so rewrapping it across the phrase an
# assertion greps for reports the row as compliant when it no longer is.
# ...and EMPHASIS-STRIPPED, like `contract_bare` and `template_bare`. The two
# must-not-exist vetoes below are defeated by bold otherwise: `has **no** error
# monitoring` passes where the plain spelling fails. Measured both ways.
blind_rows="$(printf '%s\n' "$plate_blind" |
    awk '/^- /{if (b != "") print b; b=$0; next} {b = b " " $0} END{if (b != "") print b}' |
    tr -s ' ' | tr -d '*_')"
none_row="$(printf '%s\n' "$blind_rows" | grep 'sentry: none')"
absent_row="$(printf '%s\n' "$blind_rows" | grep 'no `sentry:` block')"

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
# HOW THE ASYMMETRY IS TESTED (issue #268 rewrote this; read before changing it).
#
# A rule is classified by the DESTINATION it sends a key to — the blind-spot row
# or the clean line — and each destination is a noun phrase naming a place. Two
# earlier designs are recorded here because both are tempting and both failed.
#
#   1. "Assert the phrase, then veto the word `no`", tried three times, defeated
#      each time by a rewording: `**no** blind-spot row`, `never`, `does not`,
#      `no such`, `aligned with the other three`. It vetoed a negator ANYWHERE in
#      the window rather than one GOVERNING the mention, so it was wrong in both
#      directions at once.
#   2. The six-verb affirmative `(gets|keeps|renders|carries|receives|earns)…`
#      that replaced it. Verbs are an OPEN class, so `plus a blind-spot row in
#      §6`, `also produces a blind-spot row`, `they get a blind-spot row` and
#      `are given a blind-spot row` all evade it — every one of them correct
#      English — while the two natural rewords `keeps a blind-spot row` and
#      `gets its own blind-spot row` reddened the gate on prose that was RIGHT.
#      A gate that fails on a correct edit teaches the next author to loosen it.
#
# So: the destination is matched verb-independently, and each occurrence is then
# classified AFFIRMED or NEGATED against its own bounded left context. Requiring
# a negator to GOVERN the mention is what the three earlier attempts lacked.
#
# BE PRECISE ABOUT WHY THIS ENUMERATION IS ALLOWED WHEN THE VERB LIST WAS NOT,
# because "the list works after all" is the reading that walks straight back into
# `BLIND_AFFIRM`. The negator set has two parts. Its CORE — no / not / never /
# neither / nor / without / nothing — is a closed GRAMMATICAL class: English does
# not coin new ones, so enumerating it terminates. The rest — exempt / excluded /
# omitted / instead / rather — are lexical, chosen because this repo's prose
# actually uses them, and that half is NOT closed. It is kept short on purpose,
# every addition has to be justified by prose in the tree, and it is never the
# thing doing the work: POLARITY is, which is what resolves `not exempt` and what
# no list of any length can do. Growing the lexical half in place of fixing
# polarity is the failure mode to refuse.
#
# `none` is deliberately NOT a negator. The literal key value sits immediately
# before its own destination in the one rule this gate exists for (``sentry: none`
# … keeps its blind-spot row``), so reading it as a negation inverts that rule.
# Contractions are left out for the same reason: `n.t` also matches `net`, and
# "the net effect is a blind-spot row" would classify as negated. This repo's
# rules are written without contractions; `does not` is covered by `not`.
#
# The marker is NOT a destination. `\(n/a\)` used to sit inside the clean-line
# vocabulary, which let "they appear under Blind spots with an explicit `(n/a)`
# marker" satisfy a clean-line assertion, and made §3A's Sentry rule redden the
# moment it mentioned the marker it must NOT use. It is its own constant now.
ROW_DEST='blind[- ]spot row'
CLEAN_DEST='clean[- ]line|clean today'
NA_MARKER='(n/a)'

# Tally the destination mentions matching ERE $2 in text $1, split into AFFIRMED
# and NEGATED. Prints "<affirmed> <negated>". Emphasis and backticks are stripped
# so `**no**` reads as `no`, and the haystack is lower-cased because awk's ERE
# has no case-insensitive flag.
#
# A negator GOVERNS a mention when it is one of the FOUR words before it, no
# clause boundary intervenes, and it is not itself the head of a prepositional
# phrase about some other noun. Every clause of that rule was forced by a
# measured counterexample, so none of it is decoration:
#
#   * FOUR, not three. `**\`sentry: none\` no longer renders a blind-spot row**`
#     puts the negator four tokens back and is the most ordinary way English
#     writes this inversion. A three-token budget read it AFFIRMED and left §6's
#     headline decision invertible green — the very defect #268 exists to close,
#     and a REGRESSION against the flat regex this function replaced.
#   * The PREPOSITION test is what four costs. `a repo with no Sentry keeps a
#     blind-spot row` also puts a negator four back, but it negates `Sentry`, not
#     the row. A negator headed by `with`/`in`/`of`/`for`/… is skipped.
#   * CLAUSE BOUNDARIES, but only strong ones. `render \`skipped — not
#     configured\` **and a blind-spot row in §6**` is the LIVE §3A absent-key
#     rule and is an affirmation; `and` ends the search so it reads that way.
#     `,` and `or` are deliberately NOT boundaries — `does not get, or need, a
#     blind-spot row` is one negation, and treating either as a boundary stops
#     the scan inside the clause it belongs to. ALL THREE scans stop at the same
#     boundary, through one shared `clause_break` (issue #270). Two of them did
#     and `cancelled` did not, which reads as deliberate to a later reader
#     and was not: `that is not so. sentry is exempt from a blind-spot row` let
#     the PREVIOUS clause's `not` cancel a real negation, so the sentence read
#     AFFIRMED and could satisfy the very `'+'` veto that exists to catch it.
#   * PARENTHETICAL INSERTIONS are skipped without being counted, reading
#     right-to-left: the token bearing the closing comma opens the skip and the
#     token bearing the opening comma closes it and is itself counted. Without
#     this, `is not, as of #261, given a blind-spot row` and `never, in ordinary
#     practice, renders a blind-spot row` both read AFFIRMED.
#   * `instead`/`rather`/`excluded`/`omitted` count as negators, because
#     `instead of a blind-spot row` and `rather than a blind-spot row` are how
#     this repo actually writes the negative half, and reading them as
#     affirmations turned correct prose RED.
#
# BOTH tallies are printed, and every caller accounts for both, because a probe
# for one of them is the "tallying is not classifying" failure this file already
# learned once on the four-key table. This is not the place to grow a parser:
# the aim is that where the rule is wrong it is wrong in the LOUD direction, and
# `assert_dest`'s `'-'` want exists so a rule that states a negative must be
# measurably negated rather than merely silent.
#
# KNOWN LIMIT, stated rather than implied, because an aim is not a guarantee and
# the previous wording read as one. The backward scan is bounded to four content
# words, so a negation whose negator sits further left than that reads AFFIRMED:
# measured, `The three keys do not, in current practice, ever actually produce a
# blind-spot row` returns 1/0. Two adverbs before the destination are enough. It
# is a QUIET miss on a `'+'` check, which is the direction that matters, and it
# is recorded here because it cannot be fixed by widening the budget — six was
# measured and it reddens the gate and four mutation batteries, since a wider
# window starts reaching negators that belong to other clauses. Fixing it
# properly means bounding by clause rather than by count, which is its own
# change with its own measurement, not a constant to nudge.
dest_tally() {
    printf '%s' "$1" | tr -d '*_`' | tr '[:upper:]' '[:lower:]' |
        awk -v dest="$2" '
        function bare(t) { gsub(/^[^a-z]+|[^a-z]+$/, "", t); return t }
        # ONE clause boundary, shared by all three scans (issue #270).
        # `governed` and `post_negated` carried this expression verbatim while
        # `cancelled` had NO boundary check at all, so a negator in a PREVIOUS
        # clause cancelled a real negation and the sentence then read AFFIRMED —
        # a must-affirm veto passing on prose that states the inverse, which is
        # the direction of issue #268, again. Measured on main: `that is not so.
        # sentry is exempt from a blind-spot row` returned 1/0.
        #
        # It takes BOTH the raw token and its bare form because `bare()` strips
        # the trailing terminator. That is what made the boundary invisible to
        # `cancelled` rather than merely unchecked: a scan holding only bare
        # words cannot see a boundary at all, so passing `b2` twice here would
        # reproduce the bug while looking like the fix.
        #
        # TWO KNOWN LIMITS, both measured rather than assumed, because one shared
        # helper invites the reading that every arm of it works.
        #
        # 1. The THREE DASH ARMS ARE DEAD, in all three scans, in every form —
        # not merely narrow. They are EQUALITY tests, so an attached dash never
        # satisfies one (`special-` is not `-`), and a standalone dash bares to
        # the empty string, which every scan skips before reaching here.
        # Measured, main and this branch alike: `nothing - sentry keeps a
        # blind-spot row` and `the key is not special- mobile is exempt from a
        # blind-spot row` both classify exactly as they would with the arms
        # absent, and neutering all three changes no assertion. Only `[;:.]$`
        # has the attached-only behaviour (`true.`, `so;`). The arms are kept
        # because reviving them changes where the two ALREADY bounded scans
        # stop, on prose this file classifies correctly today — the
        # clause-bounding rework filed as issue #271, which subsumes this
        # function.
        #
        # 2. NEW WITH THIS CHANGE, and its honest cost: the `:` arm is now live
        # inside `cancelled`, where a config-key token (`sentry:`) is far likelier
        # than a real colon clause. `cancelled` has no parenthetical skip —
        # `governed` does — so an aside carrying a key literal now ends the scan
        # early. Measured, main to here: `testflight: none is not, like sentry:
        # none, exempt from a blind-spot row` goes 1/0 to 0/1, while the same
        # sentence with a colon-free aside is unchanged, which isolates the arm.
        # That is the QUIET direction on a `-` want. It is accepted rather than
        # special-cased, because both repairs are worse: dropping `:` from the
        # shared set weakens the two scans that were already correct, in exactly
        # the direction issue #270 exists to close, and giving `cancelled` a set
        # of its own re-creates the divergence this change removes. No prose in
        # the tree hits it, and a parenthetical skip for `cancelled` belongs
        # with #271.
        #
        # NO APOSTROPHE may appear in any comment in this awk program: it is a
        # single-quoted shell word, so one closes the program and the next `{`
        # is a bash syntax error. Measured here while writing this block.
        function clause_break(t, b) {
            return (t ~ /[;:.]$/ || b == "and" || b == "but" || b == "so" ||
                    b == "then" || t == "-" || t == "\342\200\224" ||
                    t == "\342\200\223")
        }
        # Is there a SECOND negator governing the one at position `at`? Double
        # negation cancels, and the cancelling word is not always adjacent:
        # `none of them is exempt from a blind-spot row` puts it four back.
        # `none` counts here ONLY as `none of` — bare `none` is the config value
        # this whole file is about and sits beside its own destination
        # constantly.
        function cancelled(w, at,   j, b2) {
            for (j = at - 1; j >= 1 && j >= at - 4; j--) {
                b2 = bare(w[j])
                if (b2 == "") continue
                # Same clause only, and checked BEFORE the negator arms so a
                # sentence-final `not.` BOUNDS rather than cancels — the sibling
                # shape, and the reason `sentry is not. mobile is exempt from a
                # blind-spot row` is a negation. The lookback budget is untouched
                # — four POSITIONS here, four CONTENT WORDS in the two siblings,
                # which is a real difference and not a wording slip. This changes
                # where the scan STOPS, not what BOUNDS it. Bounding by clause
                # instead of by a count at all is issue #271.
                if (clause_break(w[j], b2)) return 0
                if (b2 ~ /^(no|not|never|neither|nor|without|nothing)$/) return 1
                if (b2 == "none" && j < at && bare(w[j + 1]) == "of") return 1
            }
            return 0
        }
        function governed(ctx,   nw, w, i, cnt, t, b, p, skipping, scanned) {
            nw = split(ctx, w, / +/)
            cnt = 0; skipping = 0; scanned = 0
            for (i = nw; i >= 1 && cnt < 4 && scanned < 16; i--) {
                t = w[i]
                if (t == "") continue
                scanned++
                if (t ~ /,$/) {
                    if (!skipping) { skipping = 1; continue }
                    skipping = 0
                } else if (skipping) continue
                b = bare(t)
                if (b == "") continue
                cnt++
                if (clause_break(t, b)) return 0
                if (b ~ /^(no|not|never|neither|nor|without|nothing|exempt|instead|rather|excluded|omitted)$/) {
                    p = (i > 1) ? bare(w[i - 1]) : ""
                    # A negator inside a prepositional phrase negates that
                    # phrase, not the destination: `a repo with no Sentry keeps
                    # a blind-spot row` is an affirmation.
                    #
                    # PREPOSITIONS ONLY. `has`/`have`/`having` were here once and
                    # are VERBS, and `X has no Y` is the most ordinary way English
                    # writes this negation — so `` `sentry: none` has no
                    # blind-spot row `` read as AFFIRMED and defeated every
                    # must-affirm site at once (§3A, §6 and the Blind spots
                    # bullet) — the #213 gap restored three times over through
                    # one word. It also reddened the correct three-key half the
                    # moment it said `have no` instead of `get no`. The case
                    # they appeared to protect is already carried by the real
                    # prepositions:
                    # `a repo with no Sentry keeps a blind-spot row` classifies
                    # AFFIRMED on `with` alone. Measured both ways.
                    if (p ~ /^(with|in|of|for|on|at|by|from|under|inside|despite)$/)
                        continue
                    # POLARITY FLIP. A second negator governing the first cancels
                    # it: `is not exempt from a blind-spot row` and `is never
                    # excluded from a blind-spot row` AFFIRM the row, and
                    # `exempt`/`excluded` are exactly the words this repo reaches
                    # for — its own header cites `is exempt from`. Read as
                    # negations they satisfied the plain veto AND the stricter
                    # must-be-negated one, so
                    # the inverse of #261 passed every veto meant to catch it.
                    #
                    # Deliberately a polarity rule and NOT a longer negator list
                    # or a wider budget: enumerating negations is what the
                    # six-verb `BLIND_AFFIRM` already failed at, and #268 exists
                    # because that approach does not converge.
                    if (cancelled(w, i))
                        return 0
                    return 1
                }
            }
            return 0
        }
        # English negates a noun phrase from the RIGHT too, in the passive: `the
        # blind-spot row is dropped`. A look-left-only classifier read those as
        # AFFIRMED, so `**for `sentry: none` the blind-spot row is dropped**`
        # passed every must-affirm site silently — the quiet direction, on the
        # one decision this gate exists for.
        #
        # This set is its own, and NARROWER than the left one on purpose. The
        # left-side `rather` would fire on the live Blind-spots clause
        # (`produces a row, worded as confirmed rather than unchecked`), and
        # `absent` would fire on the live §6 text `keeps its blind-spot row —
        # absent error monitoring…`, both reddening correct prose. Only
        # post-positional participles count, and the scan stops at the same
        # clause boundaries.
        function post_negated(rest,   nw, w, i, cnt, t, b) {
            nw = split(rest, w, / +/)
            cnt = 0
            for (i = 1; i <= nw && cnt < 4; i++) {
                t = w[i]
                if (t == "") continue
                b = bare(t)
                if (b == "") continue
                cnt++
                if (clause_break(t, b)) return 0
                if (b ~ /^(dropped|omitted|suppressed|excluded|removed|withheld|skipped|retired)$/)
                    return 1
            }
            return 0
        }
        {
            s = $0
            while (match(s, dest)) {
                ctx = substr(s, 1, RSTART - 1)
                rest = substr(s, RSTART + RLENGTH)
                if (governed(ctx) || post_negated(rest)) n++; else a++
                s = rest
            }
        }
        END { printf "%d %d", a + 0, n + 0 }'
}
dest_affirmed() { local t; t="$(dest_tally "$1" "$2")"; printf '%s' "${t%% *}"; }

# --- The classifier's own clause boundary (issue #270) ------------------------
#
# Every veto below that reads a DESTINATION — `assert_dest`, the sentence scans,
# and the four-key row classification, though not the plain `grep` assertions
# beside them — is only as good as this classifier, and nothing in this file
# tested the classifier itself — its behaviour was measured out of band and
# written into a comment. A comment does not redden. So the boundary #270 closed
# is pinned here, in both directions, against fixed strings that owe nothing to
# what any tracked file happens to say today.
#
# SCOPE, stated so this is not read as coverage of the whole classifier. What is
# pinned is the clause boundary and the lookback around it. Two of the rules in
# the header above remain comment-only: `governed`'s four-content-word budget
# and its PREPOSITION test each flip one of that header's own cited
# counterexamples with the gate still green. Both strings are already written down there, so pinning them
# is transcription rather than measurement, and it is not #270 work — but it is
# available, and this sentence exists so nobody concludes it was already done.
#
# Each case asserts the WHOLE `<affirmed> <negated>` tally, never one half of it.
# Probing one number is the "tallying is not classifying" failure this file
# already learned on the four-key table, and here it is worse: a case that
# stopped classifying altogether returns `0 0`, which satisfies every
# "nothing affirmed" probe while measuring nothing.
#
# The distances are load-bearing and were measured, not eyeballed, and WHICH
# CASE MEASURES WHAT has to stay straight. `cancelled` looks back four positions
# from the negator, so a case whose earlier negator sits five back reads NEGATED
# on the BROKEN classifier too and is no evidence about the BOUNDARY at all —
# the cases in the `Direction 1` block — those and no others — read AFFIRMED
# before this fix and NEGATED after it, which is what makes THOSE boundary
# evidence. The quantifier is scoped to that block deliberately, not to
# everything below: measured by running both editions over all twelve strings
# here, the `Direction 1` block is the entire set that differs between them, and
# a universal reaching further would be refuted by the cases beside it — this
# gate reporting a claim its own source contradicts, which is the failure #268
# is about, committed inside the fix for it.
#
# `... and sentry is exempt ...` is the five-back shape and is deliberately
# ABSENT: green before this fix and after it, pinning nothing.
#
# `... — sentry is exempt ...` is the same shape and is deliberately PRESENT,
# for a DIFFERENT job — and must not be read as boundary evidence, which is the
# confusion this paragraph exists to prevent. A standalone dash bares to the
# empty string, which costs a POSITION-counted window a step and a
# content-word-counted one nothing, so it pins the lookback BOUND and only that.
# It carries its own heading below for that reason, outside `Direction 1`.
#
# COVERAGE IS DERIVED BY MEASUREMENT, never asserted, and no tally of it is
# written down here — a number nobody can re-derive is what a future editor
# trusts instead of re-measuring, which is this file's own rule. Every case in
# this battery was proved load-bearing by at least one mutation of the classifier that it, and
# for most of them only it, reddens. The direction-2 and control cases are pinned
# by mutations of the LOOKBACK rather than of the boundary, which is what showed
# they are not decoration. The comma pair closed a real gap: before it existed,
# adding `,` to `clause_break` left the ENTIRE gate green, and one shared helper
# is exactly what makes that a single edit.
dest_case() {
    local label="$1" text="$2" want="$3" got
    got="$(dest_tally "$text" "$ROW_DEST")"
    if [ "$got" = "$want" ]; then ok "$label"
    else bad "$label (want '$want' affirmed/negated, got '$got')"; fi
}

echo "-- the destination classifier's clause boundary (#270)"

# The control. With no earlier negator the classifier was always right here, so
# it is what makes the `Direction 1` cases evidence of a BOUNDARY rather than of
# a classifier that has simply stopped cancelling. Scoped to that block for the
# same reason the preamble scopes its quantifier — and note the scope is
# `Direction 1`, NOT everything under this control: apart from that one block,
# no case here differs between the two editions.
dest_case "a lone negation is NEGATED" \
    'sentry: none is exempt from a blind-spot row' '0 1'

# Direction 1: a negator in a PREVIOUS clause must not cancel this one.
dest_case "a negator across a period does not cancel" \
    'that is not so. sentry is exempt from a blind-spot row' '0 1'
dest_case "a negator across a semicolon does not cancel" \
    'it is never so; posthog is exempt from a blind-spot row' '0 1'
# `not so.` and `never so;` carry a conjunction (`so`) as well as a terminator,
# so on their own they cannot say WHICH arm fired. This one bares to `special`
# and isolates the terminator.
dest_case "a negator across a period alone does not cancel" \
    'the key is not special. mobile is exempt from a blind-spot row' '0 1'
# And this one isolates the conjunction: no terminator anywhere in the window.
dest_case "a negator across a conjunction does not cancel" \
    'sentry is not, and mobile is exempt from a blind-spot row' '0 1'
# ORDER, not just presence. Here the boundary and the negator are the SAME token
# (`not.`), so a `clause_break` call moved below the negator arms — the ordinary
# "test the cheap comparisons first" tidy — cancels and inverts the sentence.
dest_case "a sentence-final negator bounds rather than cancels" \
    'sentry is not. mobile is exempt from a blind-spot row' '0 1'

# NOT boundary evidence — the lookback BOUND. Its own block, because it is the
# one case here that is not about `clause_break` at all, and leaving it under
# `Direction 1` put a counterexample inside the set that heading quantifies
# over. Measured, it reads `0 1` on main and `0 1` here: identical in both
# editions, so it says nothing whatever about the boundary. It earns its place
# from the other direction — the comment at the call site claims the
# POSITIONS-versus-CONTENT-WORDS difference is real, and until this case existed
# that claim reddened nothing. `cancelled` bounds on `j`, so a token baring to
# the empty string still costs it a step and the standalone dash here pushes
# `not` out of the window, while its siblings count content words, which would
# keep `not` in scope and cancel.
dest_case "a standalone dash costs the lookback a position" \
    'it is not true — sentry is exempt from a blind-spot row' '0 1'

# What is NOT a boundary, and this pair is here because of THIS change. The set
# used to be written out twice; one shared helper makes it a single edit, so
# "a comma ends a clause too" now silently rewrites all three scans at once.
# Measured: adding `,` to `clause_break` left the whole gate green before these
# two cases existed. Both counterexamples are the file header's own — `,` and
# `or` are deliberately not boundaries, and a parenthetical is skipped without
# being counted rather than treated as one.
dest_case "a comma is not a clause boundary" \
    'sentry: none does not get, or need, a blind-spot row' '0 1'
dest_case "a parenthetical insertion is skipped, not bounded" \
    'sentry: none is not, as of #261, given a blind-spot row' '0 1'

# Direction 2: a genuine double negation INSIDE one clause still cancels. These
# are what a boundary check bolted on carelessly breaks, and each is prose this
# repo actually writes — the file header cites `is exempt from` as its own.
dest_case "an adjacent second negator still cancels" \
    'sentry: none is not exempt from a blind-spot row' '1 0'
dest_case "a second negator four back still cancels" \
    'none of them is exempt from a blind-spot row' '1 0'
# The lexical half of the negator set, cancelled by the core half: the boundary
# check now sits above both arms, so a fix that returned early on the wrong
# token would take this one out with it.
dest_case "a never/excluded pair still cancels" \
    'sentry: none is never excluded from a blind-spot row' '1 0'

# The other pair of mutually exclusive outcomes in this file: a refresh either
# RE-DERIVES a value or CARRIES it forward. Same classifier, same reason.
#
# `carve-out` on its own is deliberately NOT a carry-forward token. It is the
# ordinary noun both rules use to talk ABOUT the carve-out — "the culprit check
# that the carve-out just excluded" is the sentence arguing sentry stays out of
# it — so a bare `carve-out` veto reddens the correct source. Only membership
# phrasings count.
REDERIVE_VOCAB='re-derived|re-derive|re-run it'
CARRY_VOCAB='carried forward|carry (it|them|these) forward|not re-asked|never re-ask|(in|into|joins) (that|the) carve-out'

# Sentences of $1 that mention the literal $2, one per line. The boundary is
# `. `, which is crude — but the alternative is a window keyed on the rule's own
# wording, and that is what reddens the gate on a correct reword. A sentence is
# the unit here because "is NOT re-derived" and "is re-derived" differ by one
# word that a file-wide `grep -qi 're-derived'` cannot see: that check is what
# stood at both sites before issue #268.
sentences_about() {
    printf '%s' "$1" | awk -v key="$2" '
        {
            n = split($0, parts, /\. /)
            for (i = 1; i <= n; i++) if (index(parts[i], key) > 0) print parts[i]
        }'
}

# At least one sentence about $2 must AFFIRM vocabulary $3.
assert_sentence_affirms() {
    local label="$1" hay="$2" key="$3" vocab="$4" hits found=0 s
    hits="$(sentences_about "$hay" "$key")"
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        [ "$(dest_affirmed "$s" "$vocab")" -gt 0 ] && found=1
    done <<EOF
$hits
EOF
    if [ "$found" = 1 ]; then ok "$label"; else bad "$label"; fi
}

# NO sentence about $2 may AFFIRM vocabulary $3.
#
# ZERO sentences is a FAILURE, not a pass. A veto over an empty set is satisfied
# by nothing at all, so a key that stopped being mentioned — a rename, a section
# lost to an extractor change — would report every rule about it as clean. Its
# sibling above fails on an empty set for free (nothing affirms), which is why
# only this one needs the guard stated.
assert_no_sentence_affirms() {
    local label="$1" hay="$2" key="$3" vocab="$4" hits offender="" seen=0 s
    hits="$(sentences_about "$hay" "$key")"
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        seen=$((seen + 1))
        [ "$(dest_affirmed "$s" "$vocab")" -gt 0 ] && offender="$s"
    done <<EOF
$hits
EOF
    if [ "$seen" -eq 0 ]; then
        bad "$label: no sentence mentions \`$key\` at all — the veto would pass vacuously"
    elif [ -z "$offender" ]; then ok "$label ($seen sentence(s) checked)"
    else bad "$label (offending sentence: ${offender:0:120})"; fi
}

# Assert a window's destination profile.
#
#   '+'  at least one AFFIRMED mention.
#   '-'  at least one NEGATED mention and no affirmed one. For a rule that
#        STATES the negative ("get **no** blind-spot row"). This is the want
#        that `'0'` alone could not express, and the gap was measurable: `'0'`
#        tests only `a -eq 0`, so a rule whose negative clause moved out of the
#        window scored 0/0 and the veto printed `ok` while measuring nothing.
#        Every `'0'` veto in this file was convertible that way by a cosmetic
#        edit that shifted a window boundary.
#   '0'  no affirmed mention, and silence is legitimate. Only for whole-rule
#        scopes where the destination may simply never come up — §6's sentry
#        half never mentions the clean line at all, and must not be forced to.
#
# An EMPTY haystack is a failure in every mode: a window whose marker stopped
# matching would otherwise report each veto over it as clean.
assert_dest() {
    local label="$1" hay="$2" dest="$3" want="$4" t a n
    if [ -z "$hay" ]; then
        bad "$label: the text under test is EMPTY — an extractor is matching nothing"
        return
    fi
    t="$(dest_tally "$hay" "$dest")"; a="${t%% *}"; n="${t##* }"
    case "$want" in
        '+') if [ "$a" -gt 0 ]; then ok "$label"
             else bad "$label (affirmed=$a negated=$n)"; fi ;;
        '-') if [ "$a" -eq 0 ] && [ "$n" -gt 0 ]; then ok "$label"
             else bad "$label (affirmed=$a negated=$n; the rule must STATE the negative, not omit it)"; fi ;;
        '0') if [ "$a" -eq 0 ]; then ok "$label"
             else bad "$label (affirmed=$a negated=$n)"; fi ;;
        *) bad "assert_dest: bad want '$want'" ;;
    esac
}

echo "-- the four-key \`none\` form, and its deliberate asymmetry (#261)"

# Window of flattened text from a literal marker, ALSO cut at the first of any
# number of stop markers. Pure parameter expansion — no awk, no regex — because
# the markers carry backticks and colons, the haystacks are single ~40KB lines,
# and `#*` takes the SHORTEST match, i.e. the FIRST occurrence. Verified under
# bash 3.2 (macOS /bin/bash) as well as 5.x, so no awk-dialect or long-line
# buffer question arises between a local run and CI's.
#
# (A stop-marker-less `window_after` used to sit here; it had no call sites and
# a nine-line rationale that read as load-bearing. Every window in this file is
# structurally bounded, which is the rule — see `window_is_bounded`.)
#
# A constant
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

# A window must end at its STOP MARKER, never at its byte cap — the cap is a
# backstop against a missing stop marker running the window to EOF, not the bound
# itself. Measured (#268): `carry_win`'s last asserted phrase ended at byte 933
# of a 937-byte window, so one sentence inserted above it would have carried the
# phrase out of scope and reddened the gate on an edit that changed nothing.
# Structural bounds are the file's own rule; this asserts the rule was kept.
window_is_bounded() {
    local label="$1" hay="$2" mark="$3" n="$4"; shift 4
    local capped uncapped
    capped="$(window_between "$hay" "$mark" "$n" "$@")"
    uncapped="$(window_between "$hay" "$mark" 999999 "$@")"
    if [ -z "$capped" ]; then
        bad "$label: window marker not found"
    elif [ "${#capped}" -lt "${#uncapped}" ]; then
        bad "$label: the $n-byte cap binds $(( ${#uncapped} - ${#capped} )) bytes before the stop marker"
    else
        ok "$label: window ends at its stop marker, not at a byte cap"
    fi
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
    # A cell is classified by which destination it AFFIRMS, exactly as a prose
    # rule is. The `kept` literal this replaced was the same closed-verb-list
    # mistake one layer down: a cell reading `blind-spot row — retained` was a
    # correct edit that reddened the gate. A negated cell ("**no** blind-spot row
    # (aligned with the other three)") affirms neither and lands in `n_other`.
    if [ "$(dest_affirmed "$b" "$ROW_DEST")" -gt 0 ] &&
       [ "$(dest_affirmed "$b" "$CLEAN_DEST")" -eq 0 ]; then
        n_blind=$((n_blind + 1))
        blind_key="$k"
    elif [ "$(dest_affirmed "$b" "$CLEAN_DEST")" -gt 0 ] &&
         [ "$(dest_affirmed "$b" "$ROW_DEST")" -eq 0 ]; then
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

# The contract must agree with `update-mode.md` about what a REFRESH does with
# each `none`. It did not: the contract said "A refresh carries all four forward
# rather than re-asking (`references/update-mode.md`)" while the cited document
# says the opposite for `sentry:` (#268). Hard-wrapped across the line break, so
# a line-scoped grep could not see it — and nothing checked it either way.
assert_sentence_affirms "the contract says \`sentry: none\` is re-derived on a refresh" \
    "$contract_flat" 'sentry: none' "$REDERIVE_VOCAB"
assert_no_sentence_affirms "the contract never carries \`sentry: none\` forward" \
    "$contract_flat" 'sentry: none' "$CARRY_VOCAB"

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
    window_is_bounded "§3's \`$key: none\` window" \
        "$plate_pulls" "\`$key: none\`" 1200 "$K_END" "$s1" "$s2" "$s3"
    win="$(window_between "$plate_pulls" "\`$key: none\`" 1200 "$K_END" "$s1" "$s2" "$s3")"
    if [ -z "$win" ]; then
        bad "survey-work's §3 pull rule states nothing for \`$key: none\`"
        continue
    fi
    assert_dest "\`$key: none\` routes to the clean line" "$win" "$CLEAN_DEST" '+'
    if printf '%s' "$win" | grep -qiF "$NA_MARKER"; then
        ok "\`$key: none\` carries the \`(n/a)\` marker"
    else
        bad "\`$key: none\` lost the \`(n/a)\` marker that distinguishes it from empty"
    fi
    assert_dest "\`$key: none\` states it takes no blind-spot row" "$win" "$ROW_DEST" '-'
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
window_is_bounded "§3's \`sentry: none\` window" \
    "$plate_pulls" "$K_SENTRY" 1600 "$K_END" "$K_TF" "$K_PH" "$K_MO"
sentry_win="$(window_between "$plate_pulls" "$K_SENTRY" 1600 "$K_END" "$K_TF" "$K_PH" "$K_MO")"
if [ -z "$sentry_win" ]; then
    bad "survey-work's §3 pull rule states nothing for \`sentry: none\` — it reads as unconfigured"
else
    ok "survey-work's §3 pull rule states the \`sentry: none\` case"
    assert_dest "\`sentry: none\` affirmatively keeps its blind-spot row in §3" \
        "$sentry_win" "$ROW_DEST" '+'
    assert_dest "\`sentry: none\` states it is not a clean-line token in §3" \
        "$sentry_win" "$CLEAN_DEST" '-'
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
window_is_bounded "§3A's whole-Sentry-rule window" \
    "$plate_pulls" '**Sentry** —' 2200 '**GitHub bugs**'
sentry_rule="$(window_between "$plate_pulls" '**Sentry** —' 2200 '**GitHub bugs**')"
if [ -z "$sentry_rule" ]; then
    bad "cannot locate survey-work's §3A Sentry rule"
else
    ok "located survey-work's §3A Sentry rule"
    assert_dest "§3A's Sentry rule states Sentry is not a clean-line token, in either state" \
        "$sentry_rule" "$CLEAN_DEST" '-'
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
#
# AND IT MUST BE CUT IN TWO. §6's Confirmed-N/A block states BOTH outcomes — the
# three keys' clean line, then sentry's surviving row — so one window over the
# whole block pins neither. Measured on `main` (issue #268): replacing
# "**`sentry: none` is the deliberate exception and keeps its blind-spot row**"
# with "**`sentry: none` is aligned with the other three and takes the clean line
# too**" left this gate GREEN. The three-key assertions were satisfied by the
# three-key half, and deleting sentry's affirmation made the row veto MORE likely
# to pass, not less. That is #213's gap restored in the one section an agent
# follows when rendering, and §3A was already carrying the same lesson two
# hundred lines up.
#
# The cut is at the KEY LITERAL, which is structural — the key name, not the
# decision — so a rewrite of the decision cannot move it. If the literal is gone
# the sentry half is empty and its must-exist assertion fails loudly.
#
# WHY THIS SPLIT IS NOT THE ONE `b_clause` USES, and why that is deliberate. This
# is a PARTITION: `na_three` is the prefix and `na_sentry` the suffix, so every
# byte of the rule lands in exactly one half and nothing is discarded. The
# `### Blind spots` bullet needed `sentences_about` instead because its old cut
# took the text up to the first `. ` and THREW THE REST AWAY, so re-punctuating
# "`sentry: none` is the exception. It produces a row…" moved the row clause into
# the discarded tail and reddened the gate on correct prose. Different failure
# modes, not one shape implemented twice — do not "align" them. A partition has
# no discarded tail to lose a clause into, and every perturbation tried against
# it fails through the empty-haystack guard rather than silently.
plate_out="$(awk '/^## 6\. Output format/{f=1; next} /^## 🔥/{f=0} f' "$PLATE" | tr '\n' ' ' | tr -s ' ')"
if [ -z "$plate_out" ]; then
    bad "cannot locate survey-work's '## 6. Output format' section"
fi
window_is_bounded "§6's Confirmed-N/A window" \
    "$plate_out" 'Confirmed N/A is a THIRD state' 1800 'Skip empty P-buckets'
na_rule="$(window_between "$plate_out" 'Confirmed N/A is a THIRD state' 1800 'Skip empty P-buckets')"
if [ -z "$na_rule" ]; then
    bad "cannot locate §6's Confirmed-N/A rule body"
else
    na_three="${na_rule%%'`sentry: none`'*}"
    na_sentry="${na_rule#"$na_three"}"

    if [ -n "$na_sentry" ]; then
        ok "§6's Confirmed-N/A rule states the \`sentry: none\` case"
    else
        bad "§6's Confirmed-N/A rule never names \`sentry: none\` — the exception is gone"
    fi

    # The three-key half.
    assert_dest "§6 routes the three keys to the clean line" "$na_three" "$CLEAN_DEST" '+'
    assert_dest "§6 states the three keys get no blind-spot row" "$na_three" "$ROW_DEST" '-'
    if printf '%s' "$na_three" | grep -qiF "$NA_MARKER"; then
        ok "§6's three-key rule carries the \`(n/a)\` marker"
    else
        bad "§6's three-key rule lost the \`(n/a)\` marker"
    fi
    for k in testflight posthog mobile; do
        if printf '%s' "$na_three" | grep -qF "\`$k: none\`"; then
            ok "§6's Confirmed-N/A rule names \`$k: none\`"
        else
            bad "§6's Confirmed-N/A rule no longer names \`$k: none\`"
        fi
    done

    # The sentry half, with the expectations INVERTED. This block must never be
    # folded back into the loop above: that is exactly the shape that let the
    # inversion through.
    assert_dest "§6's \`sentry: none\` rule affirmatively keeps its blind-spot row" \
        "$na_sentry" "$ROW_DEST" '+'
    assert_dest "§6's \`sentry: none\` rule affirms no clean-line destination" \
        "$na_sentry" "$CLEAN_DEST" '0'
    if printf '%s' "$na_sentry" | grep -qiF "$NA_MARKER"; then
        bad "§6 gives \`sentry: none\` the \`(n/a)\` marker — that is the three keys' form"
    else
        ok "§6 gives \`sentry: none\` no \`(n/a)\` marker"
    fi
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

plate_rules="$(awk '/^### Blind spots/{f=1; next} /^# / || /^## / || /^### /{f=0} f' "$PLATE" | tr '\n' ' ' | tr -s ' ')"
if [ -n "$plate_rules" ]; then
    ok "located survey-work's Blind spots rules"
else
    bad "cannot locate survey-work's '### Blind spots' subsection"
fi

if printf '%s' "$plate_rules" | grep -qi 'A confirmed absence is not a dark surface'; then
    ok "the Blind spots rules exclude a confirmed absence from the section"
else
    bad "the Blind spots rules no longer exclude a confirmed absence"
fi

# The exception bullet, split at the key literal like §6's rule — and for the
# same reason. What stood here was a CO-OCCURRENCE check: `sentry: none` anywhere
# in the subsection AND `produces a row` anywhere in it. Swapping which key gets
# the row satisfies both halves, so the swap stayed GREEN (issue #268).
#
# Inside `### Blind spots` the destination is named `row`, not `blind-spot row` —
# the section IS the blind spots — so this one check widens the destination, and
# only here.
#
# It is the ONE destination pattern that needs word boundaries, and without them
# it is a false GREEN, not merely noise: `row` is a substring of `grow`, `throw`,
# `narrow` and `borrow`, so "`sentry: none` is aligned with the other three, so
# the section does not grow" would AFFIRM a row and pass the assertion that
# exists to catch exactly that sentence. Verified with awk before and after.
# `blind[- ]spot row` and `clean[- ]line` need no such guard — neither is a
# substring of an English word — and boundaries elsewhere would break the
# inflections the other vocabularies match on (`re-derives`, `re-asking`).
ROW_DEST_LOCAL='(^|[^a-z])(blind[- ]spot )?rows?([^a-z]|$)'
window_is_bounded "the Blind spots confirmed-absence bullet window" \
    "$plate_rules" 'A confirmed absence is not a dark surface' 1600 \
    'Order by what the darkness costs'
bullet="$(window_between "$plate_rules" 'A confirmed absence is not a dark surface' 1600 \
    'Order by what the darkness costs')"
if [ -z "$bullet" ]; then
    bad "cannot locate the Blind spots confirmed-absence bullet"
else
    b_three="${bullet%%'`sentry: none`'*}"
    b_sentry="${bullet#"$b_three"}"
    # Sentry's own CLAUSE, and separately the whole remainder. A window right for
    # "does it keep its row" is wrong for "does this bullet ever send sentry to
    # the clean line": a contradictory clause appended later lands outside the
    # clause and inside the remainder. Both scopes are asserted — the lesson this
    # file already recorded for §3A.
    #
    # The clause is every SENTENCE mentioning the key, not the text up to the
    # first `. `. That cut reddened the gate on a benign re-punctuation:
    # "`sentry: none` is the exception. It produces a row, worded as confirmed"
    # moves the row clause into a sentence the cut discarded, and the run failed
    # with `affirmed=0 negated=0` on correct prose.
    b_clause="$(sentences_about "$b_sentry" 'sentry: none')"

    if [ -n "$b_sentry" ]; then
        ok "the Blind spots bullet states the \`sentry: none\` case"
    else
        bad "the Blind spots bullet no longer names \`sentry: none\`"
    fi
    for k in testflight posthog mobile; do
        if printf '%s' "$b_three" | grep -qF "\`$k: none\`"; then
            ok "the Blind spots bullet names \`$k: none\` among the excluded"
        else
            bad "the Blind spots bullet no longer excludes \`$k: none\` from the section"
        fi
    done
    assert_dest "the Blind spots bullet sends the three keys to the clean line" \
        "$b_three" "$CLEAN_DEST" '+'
    assert_dest "the Blind spots bullet states the three keys get no row" \
        "$b_three" "$ROW_DEST_LOCAL" '-'
    assert_dest "the Blind spots bullet affirmatively keeps \`sentry: none\`'s row" \
        "$b_clause" "$ROW_DEST_LOCAL" '+'
    assert_dest "\`sentry: none\`'s clause affirms no clean-line destination" \
        "$b_clause" "$CLEAN_DEST" '0'
    assert_dest "nothing after \`sentry: none\` sends it to the clean line either" \
        "$b_sentry" "$CLEAN_DEST" '0'
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

# All FOUR generator modes must reach it — `setup-config` has create, update,
# migrate and adopt, and §2c claimed "all three" while omitting adopt (#268).
# Migrate and adopt are the two most likely to need it (neither a legacy render
# nor a hand-written skill can supply a `none`) and adopt reached it via nothing.
# Emphasis-stripped: the modes are named as **create** mode / **update** mode,
# so a plain-substring check for "create mode" misses them.
q2c_bare="$(printf '%s' "$q2c" | tr -d '*_')"
# A mode's BODY, not just its heading. `In **migrate** mode: **skip it**` keeps
# the list entry and passes a presence check — the heading survives while the
# rule under it is reversed.
#
# Each clause must AFFIRM that it asks. The first cut of this vetoed a
# skip/inherit vocabulary instead, which is the closed-enumeration mistake this
# same diff removed from `BLIND_AFFIRM` one section up: measured, rewriting
# adopt's clause to "the question is deferred to the next refresh" evaded every
# term and stayed GREEN. Ways of not asking are an open class; asking is a
# single act, so the affirmative is the half worth requiring. The veto is kept
# beside it — a clause that says both is a contradiction, not a pass.
ASK_VOCAB='ask|asks|asked|asking'
SKIP_VOCAB='skip it|skipped|does not apply|not applicable|exempt|inherits whatever|leave (it|them) alone|never asked|no need to ask|deferred|postponed'
Q2C_END='It is the only way'
for mode in create update migrate adopt; do
    # The LIST ENTRY, not a mention. A bare `grep "migrate mode"` is satisfied by
    # a sentence that demotes the mode ("Migrate mode inherits whatever the
    # legacy render supplied"), which is the inversion this must catch.
    if printf '%s' "$q2c_bare" | grep -qi "In $mode mode:"; then
        ok "§2c commits to asking in $mode mode"
    else
        bad "§2c does not commit to asking in $mode mode — that path leaves the keys absent"
        continue
    fi
    # Every mode marker is passed as a stop — the window's own mark is consumed
    # before the cut, so listing it here is harmless and keeps the call uniform.
    window_is_bounded "§2c's $mode-mode clause window" \
        "$q2c_bare" "In $mode mode:" 900 "$Q2C_END" \
        "In create mode:" "In update mode:" "In migrate mode:" "In adopt mode:"
    mode_win="$(window_between "$q2c_bare" "In $mode mode:" 900 "$Q2C_END" \
        "In create mode:" "In update mode:" "In migrate mode:" "In adopt mode:")"
    assert_dest "§2c's $mode-mode clause affirmatively asks" \
        "$mode_win" "$ASK_VOCAB" '+'
    assert_dest "§2c's $mode-mode clause does not exempt the mode from asking" \
        "$mode_win" "$SKIP_VOCAB" '0'
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

window_is_bounded "update mode's carry-forward window" \
    "$update_flat" '**A `none` is an answer already given' 2400 '**Do not read that'
carry_win="$(window_between "$update_flat" '**A `none` is an answer already given' 2400 '**Do not read that')"
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
fi

# `sentry: none` must NOT be in that carve-out: detection.md writes it when there
# is no MCP server or no issues to sample, both transient session conditions, so
# freezing it would let one unlucky run permanently retire the highest-signal
# surface with no recovery path.
#
# Read from the WHOLE file by sentence, not from `carry_win`. Two defects were
# measured here (#268). The check was `carry_win | grep -qi 're-derived on every
# refresh'`, which is satisfied by "is NOT re-derived on every refresh" — the
# exact inversion it exists to catch. And the phrase sat at byte 933 of a
# 937-byte window, so one sentence inserted above it would have moved it out of
# scope and reddened the gate on an edit that changed nothing.
assert_sentence_affirms "update mode says \`sentry: none\` is re-derived, not frozen" \
    "$update_flat" 'sentry: none' "$REDERIVE_VOCAB"
assert_no_sentence_affirms "update mode never carries \`sentry: none\` forward" \
    "$update_flat" 'sentry: none' "$CARRY_VOCAB"

window_is_bounded "update mode's positive-evidence window" \
    "$update_flat" '**Positive evidence against a `none`' 900 '**An ABSENT one'
pos_win="$(window_between "$update_flat" '**Positive evidence against a `none`' 900 '**An ABSENT one')"
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

window_is_bounded "update mode's absent-key window" \
    "$update_flat" '**An ABSENT one of these keys' 2400 '**Migrate mode inherits'
absent_win="$(window_between "$update_flat" '**An ABSENT one of these keys' 2400 '**Migrate mode inherits')"
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

# ADOPT mode needs the identical step, and for a reason that is easy to miss:
# `SKILL.md` Phase 5 routes adopt through this file, but this file's Adopt mode
# step 2 says "Run create mode's detect + interview", and create mode's §2c
# trigger is CONDITIONAL ("every key with no positive evidence"). So the routing
# is real and the always-ask is not inherited — the gap migrate closed with its
# own Step 2b. Without this, `interview.md` §2c's "always" for adopt is prose no
# instruction implements, which is the shape this file exists to refuse.
adopt_sec="$(awk '/^## Adopt mode/{f=1; next} /^## /{f=0} f' "$UPDATE" | tr '\n' ' ' | tr -s ' ')"
if [ -z "$adopt_sec" ]; then
    bad "cannot locate update-mode.md's Adopt mode section"
else
    ok "located update-mode.md's Adopt mode section"
    if printf '%s' "$adopt_sec" | grep -q '§2c'; then
        ok "adopt mode names interview §2c"
    else
        bad "adopt mode names no §2c step — every adopted repo keeps the three rows"
    fi
    assert_dest "adopt mode's §2c step affirmatively asks" "$adopt_sec" "$ASK_VOCAB" '+'
    if printf '%s' "$adopt_sec" | grep -qi 'always'; then
        ok "adopt mode's §2c step is unconditional"
    else
        bad "adopt mode's §2c step is conditional — create mode's trigger does not reach it"
    fi
    # Emphasis-stripped: the source writes `**not** part of this question`, and a
    # plain-substring check for the phrase misses it — the trap already recorded
    # for §2c's mode names.
    adopt_bare="$(printf '%s' "$adopt_sec" | tr -d '*_')"
    if printf '%s' "$adopt_bare" | grep -qi 'sentry' &&
       printf '%s' "$adopt_bare" | grep -qi 'not part of this question'; then
        ok "adopt mode keeps \`sentry:\` out of the confirmed-absent question"
    else
        bad "adopt mode does not exclude \`sentry:\` from the §2c question"
    fi
fi

# --- I8. setup-config/SKILL.md carries the three rules too --------------------
#
# SKILL.md is loaded on EVERY invocation while `references/` are read on demand,
# and CLAUDE.md's "SKILL.md stays thin" rule is an active reason a later sweep
# deletes these. Measured: inverting all three left this gate green, because §F
# above greps `skill_flat` only for #213's strings.

window_is_bounded "Phase 2's never-default window" \
    "$skill_flat" '**Never default a confirmed-absent `none`.**' 900 '## Phase 3'
nodefault_win="$(window_between "$skill_flat" '**Never default a confirmed-absent `none`.**' 900 '## Phase 3')"
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

window_is_bounded "setup-config Phase 4's \`none\` window" \
    "$skill_flat" '**The three `none` answers are carried forward' 1600 'Apply per file'
phase4_win="$(window_between "$skill_flat" '**The three `none` answers are carried forward' 1600 'Apply per file')"
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
    # Per SENTENCE, not per window. What stood here was `grep -qi 'sentry'` AND
    # `grep -qi 're-derived'` over the whole window — two independent substring
    # hits that "`sentry: none` is **not** re-derived on every refresh" satisfies
    # exactly as well as the rule it inverts (#268).
    assert_sentence_affirms "Phase 4 says \`sentry: none\` is re-derived, not carried forward" \
        "$phase4_win" 'sentry: none' "$REDERIVE_VOCAB"
    # ...AND the veto. Without it Phase 4 could state decision D and its inverse
    # at once — measured: appending "In practice a refresh keeps whatever
    # `sentry: none` the previous run recorded and never re-asks it." left the
    # gate GREEN. That is #267's shape exactly, in the file CLAUDE.md names as
    # the copy to trust and the one loaded on every `setup-config` run.
    assert_no_sentence_affirms "Phase 4 never carries \`sentry: none\` forward" \
        "$phase4_win" 'sentry: none' "$CARRY_VOCAB"
fi

# The guardrail list, which CLAUDE.md names as the copy to trust. Its carve-out
# is read as a MEMBER LIST and every member is accounted for, because the check
# that stood here was `grep -q '\`none\`'` — satisfied by any mention of the word
# — and #267 had quietly added `sentry:` to the list, contradicting the same
# file two paragraphs up and `update-mode.md` outright (#268). Freezing
# `sentry: none` lets one session with no MCP server retire the plate's
# highest-signal surface permanently, since the only evidence that could
# contradict the value is the check the carve-out skips.
skill_guard="$(awk '/^## Guardrails/{f=1; next} /^## /{f=0} f' "$SKILL" | tr '\n' ' ' | tr -s ' ')"
[ -n "$skill_guard" ] || bad "cannot locate setup-config/SKILL.md's Guardrails section"
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
    carveout_list="$(printf '%s' "$nevercopy" | grep -oE '\(`[^)]*`\)' | tail -1)"
    if [ -z "$carveout_list" ]; then
        bad "the never-copy guardrail no longer enumerates which \`none\` forms it excepts"
    else
        cm_n=0 cm_sentry=0
        for cm in $(printf '%s' "$carveout_list" | tr -d '()`' | tr ',' ' '); do
            cm_n=$((cm_n + 1))
            case "$cm" in sentry*) cm_sentry=1 ;; esac
        done
        if [ "$cm_n" = 3 ]; then
            ok "the guardrail's carve-out names exactly three \`none\` forms"
        else
            bad "the guardrail's carve-out names $cm_n \`none\` forms, not three: $carveout_list"
        fi
        if [ "$cm_sentry" = 0 ]; then
            ok "the guardrail's carve-out excludes \`sentry:\`"
        else
            bad "the guardrail's carve-out includes \`sentry:\` — one bad session retires Sentry forever"
        fi
    fi
    # ...and the exclusion is stated INLINE, beside the list. A reader who stops
    # at the guardrail must not have to reach Phase 4 to learn sentry is out.
    # Both halves, for the reason given at the Phase 4 site: a must-exist alone
    # lets the same list state the rule and its inverse.
    assert_sentence_affirms "the guardrail says \`sentry: none\` is re-derived, inline" \
        "$skill_guard" 'sentry: none' "$REDERIVE_VOCAB"
    assert_no_sentence_affirms "the guardrail never carries \`sentry: none\` forward" \
        "$skill_guard" 'sentry: none' "$CARRY_VOCAB"
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

# A VACUITY FLOOR, and it is worth being exact about what it does and does not
# catch. A broken EXTRACTOR already fails loudly here: every window has a `-z`
# guard, and `assert_dest` refuses an empty haystack outright. What nothing else
# sees is a whole assertion BLOCK deleted in a refactor — the count drops and the
# run still says "all green". So the floor is coarse on purpose, set well below
# today's total: it catches a collapse, not a trim, and a floor tuned to today's
# exact number is one more inventory that rots.
#
# The count itself is PRINTED, never transcribed. That is issue #268's sixth
# acceptance item taken literally: a number nobody can re-derive from the tree is
# not worth carrying, and CLAUDE.md carried a wrong one ("39 semantic mutations,
# 0 stale and 0 undetected, 59 assertions measured load-bearing") for exactly
# that reason, in the one place a future editor trusts instead of re-measuring.
ASSERT_FLOOR=120
if [ "$asserts" -lt "$ASSERT_FLOOR" ]; then
    echo "test-sentry-verification: only $asserts assertions ran (floor $ASSERT_FLOOR) — an extractor is silently matching nothing" >&2
    exit 1
fi

if [ "$fails" -ne 0 ]; then
    echo "test-sentry-verification: FAILED ($fails of $asserts assertions)" >&2
    exit 1
fi
echo "Sentry verification tests: all green ($asserts assertions)"
