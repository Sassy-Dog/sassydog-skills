#!/usr/bin/env bash
# test-review-gate-decisions.sh — pins the THREE decisions #237 (PR #243)
# settled about `send-it`'s review gate (issue #247).
#
# All three are prose, none of them is derivable from anything a script can run,
# and every one of them reads to a future "align with the governing principle"
# sweep like drift that ought to be tidied away:
#
#   1. THE REVIEW GATE IS UNCONDITIONAL. `review_agent:` resolves to the shipped
#      `sassy-dog:pr-review-orchestrator` when the key is absent, so the gate has
#      an outcome on every PR and an unconfigured repo can no longer ship
#      unreviewed. #235's verbatim
#      `review: SKIPPED — no review_agent resolved (lint/type/test only)` line
#      SURVIVES the default as the backstop for *resolution* failure — the agent
#      does not exist, the plugin did not load, the dispatch errored. Deleting it
#      as unreachable re-creates the original silent-no-review bug wearing a
#      default: the run that printed nothing would be indistinguishable from the
#      run that reviewed cleanly. To a reader who sees only "there is always a
#      default", the line looks like dead code.
#
#   2. `review_agent` IS DELIBERATELY NOT PRESENCE-IS-THE-TOGGLE. The config
#      contract's governing principle is that the presence of a block enables the
#      feature; `review_agent` has a DEFAULT, so presence is not its toggle at
#      all. #243 moved it OUT of that key list on purpose and added
#      `review_surfaces` (no default) to it in the same edit. In the key list this
#      reads as a plain inconsistency, and "restoring" it would silently turn the
#      absent key back into an off switch for every consumer repo at once.
#
#   3. THE OPT-OUT IS `review_agent: skip`, NOT `none`. The contract's
#      `sentry: none` section — itself pinned by test-sentry-verification.sh —
#      states that it is the FIRST documented exception to presence-is-the-toggle
#      and that adding another `none` form needs the same justification: a value
#      recording that somebody went and CHECKED for a confirmed absence.
#      `review_agent`'s opt-out overrides a default instead, so that
#      justification does not apply, and `skip` is also the word the gate's own
#      output uses. The missing symmetry with `sentry: none` is exactly what a
#      tidying sweep would "fix".
#
# Why source-level. There is no renderer and no runtime to test: the artifact IS
# the instruction an agent follows. Same shape as test-visibility-preconditions.sh
# (the credential's two preconditions), test-sentry-verification.sh (verify-by-
# culprit and the `sentry: none` exception), test-sentry-counts.sh,
# test-security-listing.sh, test-doc-reconciliation.sh, and test-label-migrate.sh's
# single-call-site invariant.
#
# WHITESPACE FLATTENING. Every MUST-NOT-EXIST assertion runs against a flattened
# copy of its file, never against raw lines. This repo hard-wraps prose, so a
# forbidden phrase routinely straddles a line break — and for a negative check
# that miss is a FALSE PASS: the wording is present, merely wrapped. Prose
# MUST-EXIST checks run flattened too (a wrap there is a loud failure, not a
# silent one, so flattening is merely kinder); structural must-exist checks —
# table rows, the verbatim SKIPPED line, a bullet's opening — stay line-scoped
# on purpose, because their shape IS the thing under test.
#
# No `| grep -q` pipelines anywhere: `grep -q` closes the pipe on its first match,
# the writer takes SIGPIPE, and `pipefail` promotes 141 — turning a caught
# regression into a reported miss (the #172 shape). Every string match here reads
# a file directly or a herestring.
#
# No gh, no network, no repo mutation — it reads three tracked files.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-review-gate-decisions.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-review-gate-decisions: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/send-it/SKILL.md"
CONTRACT="skills/setup-config/references/config-contract.md"
# The rendered artifact. Decisions 2 and 3 are restated here because this is the
# file that actually lands in a consumer repo's .claude/sassy-dog/send-it.md, so
# a sweep that only reached the template would ship the reverted decision.
TEMPLATE="skills/setup-config/references/templates/send-it.config.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

# assert_in <haystack> <ERE> <label>      — herestring, never a pipeline
assert_in() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi
}
# assert_not_in <haystack> <ERE> <label>
assert_not_in() {
    if grep -qE -- "$2" <<<"$1"; then bad "$3"; else ok "$3"; fi
}
# assert_line <file> <ERE> <label>        — line-scoped; file input, no pipe
assert_line() {
    if grep -qE -- "$2" "$1"; then ok "$3"; else bad "$3"; fi
}

echo "review-gate decisions from #237/PR #243 (issue #247)"

for f in "$SKILL" "$CONTRACT" "$TEMPLATE"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-review-gate-decisions: FAILED" >&2; exit 1; }

flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }
skill_flat="$(flatten "$SKILL")"
contract_flat="$(flatten "$CONTRACT")"
template_flat="$(flatten "$TEMPLATE")"

# ---------------------------------------------------------------------------
# 1. The review gate is unconditional (decision 1)
# ---------------------------------------------------------------------------
echo "-- decision 1: the gate runs on every PR"

assert_in "$skill_flat" \
    'The gate always runs; config only chooses the agent' \
    "send-it states the gate always runs"
assert_in "$skill_flat" \
    'heading is deliberately not' \
    "send-it keeps the 'not if set' note on the section heading"
assert_in "$skill_flat" \
    'Absence is a default, not an off switch' \
    "send-it states absence is a default, not an off switch"
# The resolution table is what a reader consults to answer "does this run?".
assert_line "$SKILL" \
    '^\| key absent \|.*sassy-dog:pr-review-orchestrator' \
    "send-it resolution table maps an absent key to the shipped orchestrator"
# §3's presence-gated rule must keep excluding this gate. Without the exclusion,
# the "run each gate only if its block is present" rule swallows the review gate.
assert_in "$skill_flat" \
    'does .*not.* extend to the review gate' \
    "send-it §3 exempts the review gate from the presence-gated rule"
assert_in "$skill_flat" \
    'runs on every PR' \
    "send-it §3 states the review gate runs on every PR"

# The SKIPPED line and its survival rationale. This is the half of decision 1
# that a "the default made this unreachable" sweep deletes.
assert_line "$SKILL" \
    '^review: SKIPPED — no review_agent resolved \(lint/type/test only\)$' \
    "send-it still prints the verbatim SKIPPED line"
assert_in "$skill_flat" \
    'The default agent does not retire it' \
    "send-it states the default does not retire the SKIPPED line"
assert_in "$skill_flat" \
    'backstop against .*resolution.* failure' \
    "send-it keeps the SKIPPED line as a resolution-failure backstop"
assert_in "$skill_flat" \
    'The line is .*unconditional.*' \
    "send-it keeps the SKIPPED line unconditional"
# Both producers must stay named, or a deliberate opt-out and a plugin that
# failed to load render identically while meaning opposite things.
assert_in "$skill_flat" \
    'name which of the two produced it' \
    "send-it names which of the two produced the SKIPPED line"

assert_in "$contract_flat" \
    'review gate resolves an agent on .*every.* run' \
    "contract states the gate resolves an agent on every run"
assert_line "$CONTRACT" \
    '^\| key absent \| dispatches `sassy-dog:pr-review-orchestrator`' \
    "contract table maps an absent key to the shipped orchestrator"
assert_line "$CONTRACT" \
    '^\| `review_agent: skip` \|.*review: SKIPPED — no review_agent resolved' \
    "contract table keeps the SKIPPED line on the opt-out row"
assert_in "$contract_flat" \
    'No .send-it. run can therefore silently ship unreviewed' \
    "contract states no send-it run silently ships unreviewed"

# ---------------------------------------------------------------------------
# 2. `review_agent` is NOT presence-is-the-toggle (decision 2)
# ---------------------------------------------------------------------------
echo "-- decision 2: review_agent has a default, so presence is not its toggle"

assert_in "$contract_flat" \
    'This key is not governed by presence-is-the-toggle at all: it has a default' \
    "contract states review_agent is not governed by presence-is-the-toggle"
# The scalar bullet itself: `review_agent` must live in the scalars list, which
# is where #243 moved it.
assert_line "$CONTRACT" \
    '^- `review_agent: <agent>\|skip` — which agent' \
    "contract carries review_agent as a scalar key, not a presence-toggled block"
assert_in "$contract_flat" \
    'the difference is the point: one chooses .*whether.* a review happens' \
    "contract keeps the whether-vs-where contrast with review_surfaces"

# The presence-is-the-toggle key list, isolated. Scoped rather than file-wide so
# that a mention of `review_agent` anywhere else cannot satisfy or break it.
toggle_list="$(grep -oE 'The same holds for [^.]*\.' <<<"$contract_flat")"
if [ -z "$toggle_list" ]; then
    bad "cannot locate the presence-is-the-toggle key list ('The same holds for …')"
else
    ok "located the presence-is-the-toggle key list"
    assert_not_in "$toggle_list" 'review_agent' \
        "presence-is-the-toggle key list does NOT list review_agent"
    assert_in "$toggle_list" 'review_surfaces' \
        "presence-is-the-toggle key list DOES list review_surfaces"
fi

# The same decision, stated one more time where a reader looks for it: the
# worked example's closing "omit what you don't use" line must carry the
# exception, or the example itself teaches that omitting turns the gate off.
omit_rule="$(grep -oE "Omit any block the repo doesn't use[^.]*\." <<<"$contract_flat")"
if [ -z "$omit_rule" ]; then
    bad "cannot locate the 'Omit any block the repo doesn't use' rule"
else
    ok "located the omit-any-block rule"
    assert_in "$omit_rule" 'review_agent' \
        "omit-any-block rule names review_agent as an exception"
    assert_in "$omit_rule" 'selects a default' \
        "omit-any-block rule states omitting selects a default"
fi

# send-it's own frontmatter inventory. #243 pulled `review_agent` out of the
# "optional blocks" list and gave it its own sentence for exactly this reason.
supplies="$(grep -oE 'Frontmatter supplies [^.]*\.' <<<"$skill_flat")"
if [ -z "$supplies" ]; then
    bad "cannot locate send-it's 'Frontmatter supplies …' inventory"
else
    ok "located send-it's frontmatter inventory"
    assert_not_in "$supplies" 'review_agent' \
        "send-it does NOT list review_agent among the optional blocks"
fi
assert_in "$skill_flat" \
    'its absence is .*not.* an off switch' \
    "send-it states an absent review_agent is not an off switch"

# The rendered template teaches the same thing to every consumer repo.
assert_in "$template_flat" \
    'review_agent is the one key presence does NOT toggle' \
    "send-it config template states review_agent is not presence-toggled"

# ---------------------------------------------------------------------------
# 3. The opt-out is `review_agent: skip`, not `none` (decision 3)
# ---------------------------------------------------------------------------
echo "-- decision 3: the opt-out is spelled skip, not none"

assert_in "$contract_flat" \
    'The opt-out is spelled .*skip.*, not .*none' \
    "contract states the opt-out is spelled skip, not none"
# The justification, not just the verdict. Without it the rule reads as an
# arbitrary spelling choice and the missing symmetry with `sentry: none` looks
# like an oversight worth closing.
assert_in "$contract_flat" \
    'none. belongs to the presence-is-the-toggle exception above' \
    "contract explains why none belongs to the presence-toggle exception"
assert_in "$contract_flat" \
    'records a confirmed absence somebody went and checked for' \
    "contract keeps the confirmed-absence justification for none"
assert_in "$contract_flat" \
    'not a presence-toggle key at all, so its opt-out overrides a default' \
    "contract states review_agent's opt-out overrides a default"
# The referent. Decision 3 cites this section; if it disappears the citation
# dangles and the rule loses its reason. (Its own contents are pinned by
# scripts/test-sentry-verification.sh — this is a link check, not a second copy.)
assert_line "$CONTRACT" \
    '^### The one exception: `sentry: none`$' \
    "the sentry: none exception section decision 3 cites still exists"

assert_line "$SKILL" \
    '^\| `review_agent: skip` \| none — the explicit opt-out' \
    "send-it resolution table spells the opt-out skip"
assert_in "$template_flat" \
    '`review_agent: skip` is the explicit opt-out' \
    "send-it config template spells the opt-out skip"

# ---------------------------------------------------------------------------
# 4. Must-not-exist: the pre-#243 wordings, and the `none` form that never was.
#    All flattened — see the header note on false passes.
# ---------------------------------------------------------------------------
echo "-- must-not-exist: pre-#243 wordings and a review_agent: none form"

# Decision 1, reverted: the gate becomes conditional again.
assert_not_in "$skill_flat" \
    'If .review_agent:. is set' \
    "send-it carries no 'if review_agent: is set' conditional dispatch"
assert_not_in "$skill_flat" \
    'When no .review_agent:. is configured' \
    "send-it does not treat an unconfigured key as a no-agent case"
assert_not_in "$skill_flat" \
    'even once a review agent resolves by default' \
    "send-it no longer speaks of the default as a future change"
assert_not_in "$contract_flat" \
    'It is .*not yet the default' \
    "contract does not describe the orchestrator as not-yet-default"

# Decision 2, reverted: `review_agent` back in the presence-is-the-toggle list.
assert_not_in "$contract_flat" \
    '`review_agent`, and `claim_label`' \
    "contract does not list review_agent in the presence-toggle key list"
assert_not_in "$skill_flat" \
    '`codegen`, `review_agent`' \
    "send-it does not list review_agent among the optional config blocks"
assert_not_in "$contract_flat" \
    "Omit any block the repo doesn't use\." \
    "contract's omit rule is not the bare pre-#243 form"

# Decision 3, reverted: a `none` opt-out grown for symmetry with `sentry: none`.
for pair in "send-it:$skill_flat" "contract:$contract_flat" "template:$template_flat"; do
    assert_not_in "${pair#*:}" 'review_agent: none' \
        "${pair%%:*} has no review_agent: none form"
done

if [ "$fails" -ne 0 ]; then
    echo "test-review-gate-decisions: FAILED ($fails)" >&2
    exit 1
fi
echo "review-gate decision tests: all green"
