#!/usr/bin/env bash
# test-sentry-counts.sh — pins sentry-triage's lifetime-count confirmation and
# the discovery/scoring split it rests on (issue #218).
#
# Why a source-level guard and not a render test. Nothing here executes: the
# gate is prose an agent follows, so the artifact under test is the instruction
# — the same shape as test-visibility-preconditions.sh (setup-deps' two
# preconditions), test-sentry-verification.sh (setup-config's culprit rule) and
# test-label-migrate.sh (align-labels.sh's single-call-site invariant).
#
# The bug it guards. `count`/`userCount` (REST) and Events/Users (MCP
# `search_issues`) carry identical labels and different meanings: REST is
# lifetime, the MCP rescales to its `period` argument, and neither marks which
# it returned. Measured on velovate 2026-08-20, `VELOVATE-WORKERS-2` came back
# 1 event / 1 user against a true 30 / 3 — a 30x undercount — and the 30d pull
# also returned 1 event, so widening the window is not a workaround.
#
# What makes it invisible: the REST-based daily-fire-watch routine ranked that
# issue a P0 the same morning the MCP-based interactive run declared the Sentry
# surface clean. The edition under daily human review is the one that CANNOT
# reproduce the defect, so nothing about the wrong answer ever looked wrong.
#
# Six decisions are pinned, and 3 and 4 are the fragile ones:
#
#   1. Issue search is DISCOVERY; its counts never reach a gate or a plate.
#   2. Confirmation is a numbered step that PRECEDES the gate step — ordering,
#      not convention, which is what "cannot score on unconfirmed counts" means
#      in a repo whose gates are prose.
#   3. A windowed count may never select which issues get confirmed. This reads
#      exactly like a missing optimization ("only confirm the ones near the
#      threshold"), and adding it back re-creates the bug one step earlier,
#      because the windowed number is the thing that under-reports.
#   4. `skip-unconfirmed` cannot qualify AND is always reported. Drop either
#      half and an unverifiable count fails silently in one direction or the
#      other — escalated as measured, or dropped as clean.
#   5. The report renders count PROVENANCE, so a windowed figure cannot be
#      quoted onward into a plate as though it had been verified.
#   6. The transport table keeps BOTH rows. Losing the REST row turns this into
#      "the MCP is broken, prefer REST" — the wrong lesson, and one that leaves
#      the REST path ungated for the next transport that changes semantics.
#
# Must-not-exist assertions run against a WHITESPACE-FLATTENED copy. This repo
# hard-wraps prose, so forbidden wording routinely straddles two lines and a
# line-scoped grep reports a FALSE PASS. (Must-exist checks may stay
# line-scoped: a wrap there fails loudly, which is safe.)
#
# No gh, no network, no Sentry call — it reads four tracked files.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-sentry-counts.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-sentry-counts: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/sentry-triage/SKILL.md"
GATE="skills/sentry-triage/references/qualifying-gate.md"
FALLBACK="skills/sentry-triage/references/api-fallback.md"
SYNTAX="skills/sentry-triage/references/query-syntax.md"
PLATE="skills/survey-work/SKILL.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "Sentry lifetime-count confirmation (issue #218)"

for f in "$SKILL" "$GATE" "$FALLBACK" "$SYNTAX" "$PLATE"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-sentry-counts: FAILED" >&2; exit 1; }

flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
skill_flat="$(flat "$SKILL")"
gate_flat="$(flat "$GATE")"
fallback_flat="$(flat "$FALLBACK")"
syntax_flat="$(flat "$SYNTAX")"
plate_flat="$(flat "$PLATE")"

# --- 1. Search is discovery, not scoring -------------------------------------

if printf '%s' "$skill_flat" | grep -qiE 'DISCOVERY tool, never a SCORING tool'; then
    ok "SKILL.md separates discovery from scoring"
else
    bad "SKILL.md lost the discovery-vs-scoring split"
fi

if printf '%s' "$skill_flat" | grep -qiE 'must never reach a gate|never reach a gate'; then
    ok "search counts are barred from the gate"
else
    bad "SKILL.md no longer bars search counts from the gate"
fi

# The measurement is what stops this being re-litigated as over-caution.
if printf '%s' "$skill_flat" | grep -q '30×' || printf '%s' "$skill_flat" | grep -qi '30x undercount'; then
    ok "SKILL.md carries the measured undercount"
else
    bad "SKILL.md dropped the measured evidence for the rule"
fi

# Widening the window is the first fix anyone reaches for, and it does not work.
if printf '%s' "$skill_flat" | grep -qi 'not a workaround'; then
    ok "SKILL.md records that a wider period is not a workaround"
else
    bad "SKILL.md no longer rules out widening \`period\`"
fi

# --- 2. Confirmation is a step, and it precedes the gate ---------------------

confirm_line="$(grep -n '^### .*Confirm counts' "$SKILL" | head -1 | cut -d: -f1)"
gate_line="$(grep -n '^### .*Gate' "$SKILL" | head -1 | cut -d: -f1)"
pull_line="$(grep -n '^### .*Pull' "$SKILL" | head -1 | cut -d: -f1)"

if [ -n "$confirm_line" ]; then
    ok "SKILL.md has a dedicated count-confirmation step"
else
    bad "SKILL.md has no count-confirmation step — confirmation is back to convention"
fi

if [ -n "$confirm_line" ] && [ -n "$gate_line" ] && [ -n "$pull_line" ] &&
   [ "$pull_line" -lt "$confirm_line" ] && [ "$confirm_line" -lt "$gate_line" ]; then
    ok "the workflow orders pull -> confirm -> gate"
else
    bad "confirmation no longer sits between the pull and the gate (pull=$pull_line confirm=$confirm_line gate=$gate_line)"
fi

if printf '%s' "$gate_flat" | grep -qiE '^| *0\. \*\*Counts confirmed as lifetime' ||
   printf '%s' "$gate_flat" | grep -qi 'Counts confirmed as lifetime'; then
    ok "the gate carries a numbered lifetime-counts rule"
else
    bad "the gate has no lifetime-counts rule"
fi

# Rule 0 has to be evaluated before the rule that reads the number.
rule0_line="$(grep -n '^0\. ' "$GATE" | head -1 | cut -d: -f1)"
rule3_line="$(grep -n '^3\. ' "$GATE" | head -1 | cut -d: -f1)"
if [ -n "$rule0_line" ] && [ -n "$rule3_line" ] && [ "$rule0_line" -lt "$rule3_line" ]; then
    ok "rule 0 precedes the severity-threshold rule"
else
    bad "rule 0 does not precede rule 3 (rule0=$rule0_line rule3=$rule3_line)"
fi

if printf '%s' "$gate_flat" | grep -qi 'Evaluation order is part of the gate'; then
    ok "evaluation order is stated as part of the gate"
else
    bad "the gate no longer states that evaluation order is part of it"
fi

# --- 3. A windowed count may never select what gets confirmed ---------------
#
# The single most deletable rule here: it reads as a missing optimization.

if printf '%s' "$skill_flat" | grep -qi 'Never use a windowed count to decide which issues are worth confirming'; then
    ok "SKILL.md forbids selecting confirmations by windowed count"
else
    bad "SKILL.md lost the ban on pre-filtering by windowed count"
fi

# Without the reason, the ban reads as arbitrary and gets optimized away.
if printf '%s' "$skill_flat" | grep -qiE 're-?creates? the bug one step earlier'; then
    ok "the ban carries its reason (the pre-filter re-creates the bug)"
else
    bad "the ban on pre-filtering no longer says why"
fi

if printf '%s' "$gate_flat" | grep -qiE 're-?creates? the bug one step earlier'; then
    ok "the gate repeats the pre-filter reasoning"
else
    bad "the gate dropped the pre-filter reasoning"
fi

# The narrowing must be done by the rules that read no count at all.
if printf '%s' "$gate_flat" | grep -qi 'count-independent rules'; then
    ok "the gate names the count-independent rules as the narrowing step"
else
    bad "the gate no longer names which rules do the narrowing"
fi

# --- 4. skip-unconfirmed: cannot qualify, and is always reported -------------

if printf '%s' "$gate_flat" | grep -q 'skip-unconfirmed'; then
    ok "the gate defines \`skip-unconfirmed\`"
else
    bad "the gate has no \`skip-unconfirmed\` tag"
fi

# Both halves. Either one alone is a silent failure in one direction.
if printf '%s' "$gate_flat" | grep -qiE 'cannot qualify|can never qualify'; then
    ok "an unconfirmed count can never qualify"
else
    bad "unconfirmed counts are no longer barred from qualifying"
fi

if printf '%s' "$gate_flat" | grep -qiE 'reported, never dropped'; then
    ok "\`skip-unconfirmed\` is reported, never dropped"
else
    bad "\`skip-unconfirmed\` may now be dropped silently"
fi

if printf '%s' "$skill_flat" | grep -qi 'reported, never dropped'; then
    ok "SKILL.md repeats the report-never-drop rule"
else
    bad "SKILL.md dropped the report-never-drop rule"
fi

# It must appear in the tag list the report groups by, or it exists on paper only.
if printf '%s' "$skill_flat" | grep -q 'skip-unconfirmed' &&
   printf '%s' "$gate_flat" | grep -qi 'tagged in working data.*skip-unconfirmed'; then
    ok "\`skip-unconfirmed\` is in the reported skip-tag list"
else
    bad "\`skip-unconfirmed\` is missing from the reported skip-tag list"
fi

# Fail-open is the tempting compromise and it reinstates the undercount.
if printf '%s' "$gate_flat" | grep -qi 'Failing open'; then
    ok "the gate explicitly rejects failing open"
else
    bad "the gate no longer rejects failing open on unconfirmed counts"
fi

# --- 4b. firstSeen is rescaled too ------------------------------------------
#
# Found by exercising the fix rather than by reading #218, which recorded the
# counts only. It is the more believable corruption: a 57-day-old fault
# presented as 2 days old points triage straight at the latest deploy.

for f in "$SKILL" "$GATE" "$SYNTAX"; do
    if grep -q 'firstSeen' "$f"; then
        ok "$(basename "$f") covers the rescaled \`firstSeen\`"
    else
        bad "$(basename "$f") no longer covers the rescaled \`firstSeen\`"
    fi
done

if printf '%s' "$gate_flat" | grep -qi 'rescales identically'; then
    ok "rule 0 confirms \`firstSeen\` from the same fetch as the counts"
else
    bad "rule 0 no longer pulls \`firstSeen\` from the confirming fetch"
fi

# The query TERM was never shown to be broken; conflating the two would be a
# false claim in a reference doc, so the distinction is pinned.
if printf '%s' "$syntax_flat" | grep -qi 'only the second is known bad'; then
    ok "query-syntax separates the \`firstSeen:\` query term from the returned field"
else
    bad "query-syntax no longer separates the query term from the returned field"
fi

# --- 5. The report renders count provenance ----------------------------------

if printf '%s' "$skill_flat" | grep -qi 'renders its provenance'; then
    ok "the report renders count provenance"
else
    bad "the report no longer distinguishes confirmed from unconfirmed counts"
fi

if printf '%s' "$skill_flat" | grep -qi 'windowed, unconfirmed'; then
    ok "the provenance rule shows the unconfirmed rendering"
else
    bad "the provenance rule gives no unconfirmed form to render"
fi

# The hard-prohibition list is where a reader who skims stops; the rule must be there.
prohibitions="$(awk '/^## Hard prohibitions/{f=1; next} /^## /{f=0} f' "$SKILL")"
prohibitions_flat="$(printf '%s' "$prohibitions" | tr '\n' ' ' | tr -s ' ')"
if printf '%s' "$prohibitions_flat" | grep -qiE 'has not confirmed as lifetime'; then
    ok "the hard prohibitions bar scoring on unconfirmed counts"
else
    bad "the hard-prohibition list does not mention unconfirmed counts"
fi

# Dismissal is half the failure: the velovate miss was a false CLEAN, not a false file.
if printf '%s' "$prohibitions_flat" | grep -qi 'dismiss'; then
    ok "the prohibition covers dismissal, not only escalation"
else
    bad "the prohibition covers escalation only — a false 'clean' is the bug that shipped"
fi

# --- 6. The transport table keeps both rows ----------------------------------

table_rows="$(awk '/^## Count semantics differ by transport/{f=1; next} /^## /{f=0} f' "$FALLBACK" | grep '^|')"

if [ -n "$table_rows" ]; then
    ok "api-fallback.md carries the count-semantics table"
else
    bad "api-fallback.md has no count-semantics table"
fi

rest_row="$(printf '%s\n' "$table_rows" | grep -i 'REST')"
mcp_row="$(printf '%s\n' "$table_rows" | grep -i 'search_issues')"

if [ -n "$rest_row" ] && printf '%s' "$rest_row" | grep -qi 'lifetime'; then
    ok "the REST row states its counts are lifetime"
else
    bad "the REST row is missing or no longer states lifetime"
fi

if [ -n "$mcp_row" ] && printf '%s' "$mcp_row" | grep -qi 'windowed'; then
    ok "the MCP row states its counts are windowed"
else
    bad "the MCP row is missing or no longer states windowed"
fi

# REST being accidentally right must not become "prefer REST, skip confirmation".
if printf '%s' "$fallback_flat" | grep -qiE 'not a reason to prefer it or to skip confirmation'; then
    ok "REST's correctness is explicitly not an exemption from confirmation"
else
    bad "nothing stops REST being read as exempt from confirmation"
fi

# --- 7. Consumers agree ------------------------------------------------------

# Mutation proof: the pre-#218 bare claim, which sent search counts straight to
# the gate. Flattened, because it sat on one line and the fix wraps.
if printf '%s' "$syntax_flat" | grep -qi 'Both feed the qualifying gate'; then
    bad "query-syntax.md reverted to 'both feed the qualifying gate'"
else
    ok "query-syntax.md carries no direct-to-gate claim"
fi

if printf '%s' "$syntax_flat" | grep -qi 'Neither goes to the gate as returned'; then
    ok "query-syntax.md routes counts through rule 0"
else
    bad "query-syntax.md no longer routes counts through rule 0"
fi

if printf '%s' "$plate_flat" | grep -qi 'mean \*\*lifetime\*\* totals'; then
    ok "survey-work states the impact formula takes lifetime totals"
else
    bad "survey-work no longer states that the formula takes lifetime totals"
fi

if printf '%s' "$plate_flat" | grep -qi 'skip-unconfirmed'; then
    ok "survey-work refuses to quote an unconfirmed figure"
else
    bad "survey-work may quote a \`skip-unconfirmed\` figure as measured"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-sentry-counts: FAILED ($fails)" >&2
    exit 1
fi
echo "Sentry count-confirmation tests: all green"
