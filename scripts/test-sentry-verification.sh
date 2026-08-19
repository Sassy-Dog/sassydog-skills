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
# Two decisions are pinned, and the second is the fragile one:
#
#   A. Verification is by CULPRIT, not by name, and a failed verification writes
#      `sentry: none` rather than a guessed block.
#   B. `sentry: none` is the config contract's FIRST documented exception to
#      "presence is the toggle". That exception is exactly the kind of prose a
#      later "align with the governing principle" sweep deletes as an
#      inconsistency — it reads like drift and is in fact the decision.
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
# No gh, no network, no repo mutation — it reads six tracked files.
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
PLATE="skills/survey-work/SKILL.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "Sentry project verification + \`sentry: none\` contract (issue #213)"

for f in "$DETECTION" "$CONTRACT" "$SKILL" "$TEMPLATE" "$INTERVIEW" "$PLATE"; do
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

if [ "$fails" -ne 0 ]; then
    echo "test-sentry-verification: FAILED ($fails)" >&2
    exit 1
fi
echo "Sentry verification tests: all green"
