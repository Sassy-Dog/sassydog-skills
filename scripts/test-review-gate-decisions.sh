#!/usr/bin/env bash
# test-review-gate-decisions.sh — pins the FIVE decisions settled about the
# review gate: three from #237 (PR #243, issue #247), and two more from #248
# (PR #250, issue #255) covering the gate's two DISPATCHING paths.
#
# All five are prose, none of them is derivable from anything a script can run,
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
#      and that a key joining that form needs the same justification: a value
#      recording that somebody went and CHECKED for a confirmed absence.
#      `review_agent`'s opt-out overrides a default instead, so that
#      justification does not apply, and `skip` is also the word the gate's own
#      output uses. The missing symmetry is exactly what a tidying sweep would
#      "fix" — and issue #261 raised that pressure rather than lowering it, by
#      growing the `none` form from one key to FOUR (`sentry`, `testflight`,
#      `posthog`, `mobile`). The contract now names `review_agent:` and
#      `review_site:` in that section's exclusion list, with the reason; this
#      gate is what keeps `skip` from being "aligned" to `none` anyway.
#
#   4. `review_site` IS CONFIGURED, NOT DERIVED — DELIBERATELY. The contract's
#      governing principle is *configure only what cannot be derived*, and repo
#      visibility IS derivable: `gh repo view --json visibility` answers it on
#      any run. So a literal reading of that principle deletes the key. Do not.
#      Deriving it live means a visibility change silently rewrites a repo's
#      review architecture — taking a repo private downgrades it from pre-PR
#      review to after-the-fact review with no config diff, no prompt, and no
#      line in any run's output. That is the #187 failure class: a visibility
#      transition silently disabling a protection the repo was relying on.
#      `setup-config` therefore seeds it ONCE from visibility at setup and
#      records the resolved value. The half that a REFRESH would undo lives in
#      a different file: Phase 4 of `setup-config/SKILL.md` carves `review_site`
#      out of update mode's "re-verify every fact against live state" rule, and
#      that carve-out is what stops the first refresh after a visibility change
#      from re-creating the silent flip. Both halves are pinned here — the
#      contract entry AND the Phase 4 exception, scoped to the phase it governs.
#
#   5. A BLOCKING FINDING BLOCKS THE MERGE, WITH EXACTLY ONE REDISPATCH.
#      `dispatch-ready` surfaces the finding named, comments it on the issue,
#      allows ONE redispatch carrying the finding as context, then demotes to
#      `blocked` on a second failure. Never merge past it; never park it back
#      in Ready, which must stay synonymous with dispatchable. The number is
#      the part that rots: on its own "one" reads as an arbitrary retry count,
#      so the rationale — it is the SAME single-redispatch budget a failed
#      check already gets — is pinned alongside it. `take-it` states the same
#      rule for its own coordinator site, and both guardrail lists repeat it,
#      because these two skills dispatch sub-agents that open PRs from a cold
#      worktree and never see an interactive session's instructions.
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
# The flatten also strips leading blockquote markers, for the reason
# test-doc-reconciliation.sh does: `take-it`'s step-6 review gate lives inside a
# `>` sub-agent prompt template, so a phrase wrapped across two quoted lines
# joins as `… fix them > and re-review …` and reads as ABSENT. Measured, not
# assumed — decision 5's "Blocking findings → fix them and re-review before you
# commit" is a miss under a marker-preserving flatten and a hit under this one.
# Stripping can only join text that was already adjacent, so it never hides a
# forbidden phrase from a must-not-exist check.
#
# No `| grep -q` pipelines anywhere: `grep -q` closes the pipe on its first match,
# the writer takes SIGPIPE, and `pipefail` promotes 141 — turning a caught
# regression into a reported miss (the #172 shape). Every string match here reads
# a file directly or a herestring. The two pipelines that do exist — `flatten`
# and the Phase 4 section slice — end in `tr`, which drains its input and never
# closes early.
#
# No gh, no network, no repo mutation — it reads six tracked files.
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
# Decisions 4 and 5 (#248/PR #250). `review_site` is live prose in four files;
# the generator owns the seeding half of decision 4, and the two dispatching
# skills own decision 5 — one for each site the key can name.
SETUP="skills/setup-config/SKILL.md"
TAKEIT="skills/take-it/SKILL.md"
DISPATCH="skills/dispatch-ready/SKILL.md"

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

echo "review-gate decisions from #237/PR #243 (issue #247) and #248/PR #250 (issue #255)"

for f in "$SKILL" "$CONTRACT" "$TEMPLATE" "$SETUP" "$TAKEIT" "$DISPATCH"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-review-gate-decisions: FAILED" >&2; exit 1; }

# Blockquote markers are stripped first — see the header note. `[[:space:]]`,
# never `[ \t]`: BSD sed reads the latter as a literal-t class and eats every t.
flatten() { sed -E 's/^[[:space:]]*(> ?)+//' "$1" | tr '\n' ' ' | tr -s ' '; }
skill_flat="$(flatten "$SKILL")"
contract_flat="$(flatten "$CONTRACT")"
template_flat="$(flatten "$TEMPLATE")"
setup_flat="$(flatten "$SETUP")"
takeit_flat="$(flatten "$TAKEIT")"
dispatch_flat="$(flatten "$DISPATCH")"

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
    # #250's key lands in the same trap: it has a default too, so listing it
    # here would turn its absence into an off switch for the dispatching paths.
    assert_not_in "$toggle_list" 'review_site' \
        "presence-is-the-toggle key list does NOT list review_site"
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
    # #250 made it TWO exceptions. Dropping the second one back out teaches the
    # example that omitting `review_site:` disables something, which it does not.
    assert_in "$omit_rule" 'review_site' \
        "omit-any-block rule names review_site as an exception too"
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
# 4. `review_site` is CONFIGURED, not derived (decision 4, #248/PR #250)
# ---------------------------------------------------------------------------
echo "-- decision 4: review_site is seeded once from visibility, then frozen"

assert_line "$CONTRACT" \
    '^#### Why this key is CONFIGURED and not DERIVED$' \
    "contract keeps the CONFIGURED-and-not-DERIVED section"
assert_in "$contract_flat" \
    'deliberate exception to \*configure only what cannot be derived\*' \
    "contract names review_site an exception to the governing principle"
# The concession is the load-bearing half. A reader who learns only that the key
# is configured, and separately that visibility is derivable, closes the gap.
assert_in "$contract_flat" \
    'Visibility \*\*is\*\* derivable — `gh repo view --json visibility`' \
    "contract concedes visibility is derivable via gh repo view"
assert_in "$contract_flat" \
    'Deriving it live means a visibility change silently rewrites the repo.s review architecture' \
    "contract states deriving it live silently rewrites the review architecture"
assert_in "$contract_flat" \
    'downgrade it from pre-PR review to after-the-fact review with nothing announcing the change' \
    "contract names the silent pre-PR to after-the-fact downgrade"
assert_in "$contract_flat" \
    'issues/187' \
    "contract cites #187 as the failure class this exception avoids"
assert_in "$contract_flat" \
    'reads visibility \*\*once\*\*, at setup, and writes the resolved value explicitly' \
    "contract states setup-config reads visibility once and records the value"
assert_in "$contract_flat" \
    'seeded from a derived fact and then frozen' \
    "contract's scalar-key bullet marks review_site seeded-then-frozen"
assert_line "$CONTRACT" \
    '^- `review_site: agent[|]coordinator` — \*\*where\*\*' \
    "contract carries review_site as a scalar key"
# Both seed rows, in both files that carry the table. A one-row table is a rule
# with no alternative, and PUBLIC -> agent is the counter-intuitive row.
for pair in "contract:$CONTRACT" "setup-config:$SETUP"; do
    assert_line "${pair#*:}" '^\| `PUBLIC` \| `agent` \|$' \
        "${pair%%:*} seed table maps PUBLIC to agent"
    assert_line "${pair#*:}" '^\| `INTERNAL` / `PRIVATE` \| `coordinator` \|$' \
        "${pair%%:*} seed table maps INTERNAL/PRIVATE to coordinator"
done

assert_line "$SETUP" \
    '^### Seed `review_site` — once, from visibility, then never again$' \
    "setup-config keeps the seed-once-then-never-again heading"
assert_in "$setup_flat" \
    'read exactly once: it seeds `review_site:`' \
    "setup-config Phase 0 reads visibility exactly once"
assert_in "$setup_flat" \
    'never re-read it on a refresh' \
    "setup-config Phase 0 forbids re-reading visibility on a refresh"
assert_in "$setup_flat" \
    'Write the resolved value, never the rule that produced it' \
    "setup-config writes the resolved value, never the rule"
assert_in "$setup_flat" \
    'A derived `review_site` means a later visibility change silently rewrites' \
    "setup-config states a derived review_site rewrites the architecture silently"
assert_in "$setup_flat" \
    'the failure class issue #187 documents' \
    "setup-config cites #187 as the failure class"

# The Phase 4 carve-out — the half of decision 4 that survives a REFRESH, and
# the half that lives in a different file from the contract entry. Scoped to the
# phase: update mode's "re-verify every fact against live state" rule and its one
# exception must sit in the same section, or the rule reads absolute where it
# runs. (awk into tr: tr drains its input, so no SIGPIPE under pipefail.)
phase4="$(awk '/^## Phase 4 /{f=1} /^## Phase 5 /{f=0} f' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
if [ -z "$phase4" ]; then
    bad "cannot locate setup-config Phase 4 (update mode)"
else
    ok "located setup-config Phase 4 (update mode)"
    assert_in "$phase4" 're-verify every fact against live state' \
        "Phase 4 still states update mode's re-verify-every-fact rule"
    # "the one fact" was dropped, deliberately: issue #261 added four more
    # non-re-derived frontmatter values (the `none` forms), and the same file's
    # guardrail list already named them beside `review_site`, so the uniqueness
    # claim was false nine lines from where it was made. The DECISION this pins
    # is that Phase 4 exempts `review_site` — not that it is the only exemption.
    assert_in "$phase4" '`review_site:` is a fact this phase must NOT re-derive' \
        "Phase 4 exempts review_site from the re-verify rule"
    assert_in "$phase4" 'stop and surface both sides' \
        "Phase 4 surfaces a visibility mismatch rather than rewriting the value"
fi

# The same carve-out in the guardrail list, where the rule is stated absolutely.
never_copy="$(grep -oE 'Never copy a fact forward without re-verifying it against live state[^.]*\.' <<<"$setup_flat")"
if [ -z "$never_copy" ]; then
    bad "cannot locate setup-config's never-copy-a-fact-forward guardrail"
else
    ok "located the never-copy-a-fact-forward guardrail"
    assert_in "$never_copy" 'review_site' \
        "the never-copy guardrail names review_site as its exception"
    assert_in "$never_copy" 'seeded once and carried forward by design' \
        "the never-copy guardrail states review_site is seeded once by design"
fi

# ---------------------------------------------------------------------------
# 5. A Blocking finding blocks the merge, with ONE redispatch (decision 5)
# ---------------------------------------------------------------------------
echo "-- decision 5: never merge past a Blocking finding; one redispatch, then blocked"

assert_in "$contract_flat" \
    'A Blocking finding is never merged past' \
    "contract states a Blocking finding is never merged past"
assert_in "$contract_flat" \
    'one redispatch carrying the finding as context' \
    "contract states one redispatch carrying the finding"
assert_in "$contract_flat" \
    'never parks it back in Ready' \
    "contract states the finding is never parked back in Ready"
# The contract points at the owner instead of restating the path — the same
# write-it-once posture it takes for `review_agent`'s resolution order.
assert_in "$contract_flat" \
    'That path lives in `dispatch-ready` §2' \
    "contract defers the path itself to dispatch-ready §2"

assert_in "$dispatch_flat" \
    '\*\*never merge past one\.\*\*' \
    "dispatch-ready never merges past a Blocking finding"
assert_in "$dispatch_flat" \
    'allow ONE redispatch carrying that finding as context on a later tick' \
    "dispatch-ready allows exactly one redispatch carrying the finding"
# The rationale for the number. Without it "one" is an arbitrary retry count,
# and an arbitrary number is the kind a later edit rounds up.
assert_in "$dispatch_flat" \
    'the same single-redispatch budget a failed check gets' \
    "dispatch-ready justifies the number as parity with a failed check"
assert_in "$dispatch_flat" \
    'A second failure demotes to `blocked` the same way' \
    "dispatch-ready demotes to blocked on a second failure"
assert_in "$dispatch_flat" \
    '\*\*Never park it back in Ready\*\*' \
    "dispatch-ready never parks a Blocking finding back in Ready"
assert_in "$dispatch_flat" \
    'max one redispatch per issue without a human' \
    "dispatch-ready guardrails cap redispatches at one without a human"
assert_in "$dispatch_flat" \
    'never park one back in Ready — one redispatch carrying the finding, then `blocked`' \
    "dispatch-ready guardrails repeat the one-redispatch-then-blocked rule"
# The reported shape. A budget nobody prints is a budget nobody can audit.
assert_line "$DISPATCH" \
    '^review: #[0-9]+ BLOCKING .*redispatch 1 of 1$' \
    "dispatch-ready tick report shows the 1-of-1 redispatch budget"
assert_in "$dispatch_flat" \
    'never drop a Blocking finding or a `review: SKIPPED` from it' \
    "dispatch-ready never drops a Blocking finding from the tick report"
# The `agent`-site case that looks dead and is not: a sub-agent that could not
# resolve a reviewer produces a PR the coordinator must still stop.
assert_in "$dispatch_flat" \
    'it still fires when a sub-agent could not resolve a reviewer at all' \
    "dispatch-ready keeps the Blocking path live on the agent site"

assert_line "$TAKEIT" \
    '^### Review gate on the coordinator site \(ONLY when `review_site: coordinator`\)$' \
    "take-it keeps its coordinator-site review section"
assert_in "$takeit_flat" \
    'hold the PR; \*\*never merge past it\*\*' \
    "take-it holds the PR and never merges past a Blocking finding"
assert_in "$takeit_flat" \
    'allow ONE redispatch carrying it as context' \
    "take-it allows exactly one redispatch carrying the finding"
assert_in "$takeit_flat" \
    'A second failure gets the `blocked` label' \
    "take-it labels blocked on a second failure"
assert_in "$takeit_flat" \
    'Never merge past a Blocking review finding\*\*, on either `review_site`' \
    "take-it guardrails apply the rule on either review_site"
# Inside the `>` sub-agent prompt, and wrapped — only visible to a flatten that
# strips blockquote markers. This is the assertion that proves the flatten.
assert_in "$takeit_flat" \
    '\*\*Blocking findings → fix them and re-review before you commit\*\*' \
    "take-it's dispatched prompt fixes Blocking findings before committing"

# ---------------------------------------------------------------------------
# 6. Must-not-exist: the pre-#243 wordings, the `none` form that never was, and
#    the two #250 decisions reverted. All flattened — see the header note on
#    false passes.
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

# Decisions 4 and 5, reverted — across all four files `review_site` lives in.
for pair in "contract:$contract_flat" "setup-config:$setup_flat" \
            "take-it:$takeit_flat" "dispatch-ready:$dispatch_flat"; do
    # Decision 4: the key re-derived from live visibility rather than seeded.
    assert_not_in "${pair#*:}" 'review_site.{0,30}is derived' \
        "${pair%%:*} does not describe review_site as derived"
    assert_not_in "${pair#*:}" 're-?read visibility (live|on every|at each|on each)' \
        "${pair%%:*} does not re-read visibility per run or per refresh"
    # Decision 5: an unqualified "merge past", a Blocking finding parked back in
    # Ready, or a redispatch budget grown past one. `[^r] ` excludes the legal
    # forms, all of which are preceded by "never"/"Never".
    assert_not_in "${pair#*:}" '[^r] merge past' \
        "${pair%%:*} carries no unqualified 'merge past'"
    assert_not_in "${pair#*:}" '[^r] park (it|one|them|the PR) back in Ready' \
        "${pair%%:*} carries no unqualified 'park … back in Ready'"
    assert_not_in "${pair#*:}" '(two|TWO|2|three) redispatches?' \
        "${pair%%:*} grants no second redispatch"
    assert_not_in "${pair#*:}" 'redispatch 2 of' \
        "${pair%%:*} reports no redispatch budget past 1"
done

# take-it's derived-never-configured list is where a "this is derivable" sweep
# would move the key. Scoped, so a mention of `review_site` elsewhere in the
# file cannot mask it.
derived_list="$(grep -oE 'Repo slug[^:.]*derived, never configured' <<<"$takeit_flat")"
if [ -z "$derived_list" ]; then
    bad "cannot locate take-it's derived-never-configured list"
else
    ok "located take-it's derived-never-configured list"
    assert_not_in "$derived_list" 'review_site' \
        "take-it's derived-never-configured list does NOT name review_site"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-review-gate-decisions: FAILED ($fails)" >&2
    exit 1
fi
echo "review-gate decision tests: all green"
