#!/usr/bin/env bash
# test-doc-reconciliation.sh — pins the doc-reconciliation step in all THREE
# shipping paths (issue #220).
#
# What this gate is NOT. It does not check whether any doc is actually stale.
# #220 rules that out explicitly and correctly: staleness is a semantic
# judgement about whether a sentence still describes the code, there is nothing
# to grep for, and a script pretending otherwise would produce exactly the
# skimmed-past output issue #199 documents for the reference checker. This gate
# gates the INSTRUCTION's presence, the same source-level shape as
# test-visibility-preconditions.sh and test-sentry-counts.sh.
#
# The bug it guards. Nothing in the shipping path asked whether a change had
# just made a doc wrong. Lint, type, test and the review agent all pass on a PR
# whose CLAUDE.md now states the opposite of what the repo does, because docs
# are an input to no other gate. One Solador PR shipped beside three doc claims
# that were already false before it started — a "not consumed" value that had
# been reaching the host cards for a while, a "hard-coded" version that was the
# git-derived CalVer, and a "no release train yet" line pointing at a closed
# issue whose release.yml ships macOS and Windows. All three were caught by a
# human noticing.
#
# Why all three skills, and why take-it/dispatch-ready are the important half:
# those dispatch SUB-AGENTS that open their own PRs from a cold worktree. They
# never see an interactive session's CLAUDE.md, so a rule that lives only in
# send-it never runs for them. #220 calls this "the half most likely to be
# missed" — so the gate treats the three as equals and fails if any one lacks
# it.
#
# Four things are pinned:
#
#   1. All three skills carry the step.
#   2. In send-it it runs BEFORE the PR body is drafted. The body is where "what
#      changed" is stated, so a doc fix belongs in the same PR, not a follow-up.
#   3. Both traps survive, with their reasons:
#        - issue state is not evidence (closed != landed, open != not landed)
#        - claims of deliberate absence rot silently
#      These are the two that produced real errors, and they are the sentences a
#      later trim reads as belt-and-braces.
#   4. The scope limiter survives ("the area you touched", not every markdown
#      file). Without it the step is unbounded, and an unbounded step is skipped.
#
# Must-not-exist assertions run on a WHITESPACE-FLATTENED copy: this repo
# hard-wraps prose, and a line-scoped grep turns a wrap into a false PASS.
#
# No gh, no network: three tracked files.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-doc-reconciliation.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-doc-reconciliation: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SEND="skills/send-it/SKILL.md"
TAKE="skills/take-it/SKILL.md"
DISPATCH="skills/dispatch-ready/SKILL.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "Doc reconciliation in the shipping path (issue #220)"

for f in "$SEND" "$TAKE" "$DISPATCH"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-doc-reconciliation: FAILED" >&2; exit 1; }

# Flatten to one line for phrase matching. Two normalisations, both load-bearing:
#
#   sed 1  strip leading blockquote markers. take-it's rule lives INSIDE a `>`
#          prompt template, so a phrase wrapping across two lines flattens to
#          "not every > markdown file" and a plain grep misses it. That is a
#          FALSE PASS on a must-not-exist check and a false FAIL here — this
#          gate hit all three of its own assertions that way before the strip
#          was added.
#   sed 2  drop list/continuation indentation left behind by the join.
#
# Same class as the wrap trap the other prose gates flatten for; blockquotes
# just make it survive the newline.
flat() {
    sed -e 's/^[[:space:]]*>[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' "$1" |
        tr '\n' ' ' | tr -s ' '
}
send_flat="$(flat "$SEND")"
take_flat="$(flat "$TAKE")"
dispatch_flat="$(flat "$DISPATCH")"

# --- 1. All three carry the step ---------------------------------------------

for pair in "send-it:$send_flat" "take-it:$take_flat" "dispatch-ready:$dispatch_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    if printf '%s' "$body" | grep -qiE 'doc-reconciliation|Reconcile the docs|Reconcile the docs against the repo|reconcile the docs against the repo'; then
        ok "$name carries a doc-reconciliation step"
    else
        bad "$name has no doc-reconciliation step"
    fi
done

# The sub-agent brief is the half that gets missed: its rule must be inside the
# prompt template the agent actually receives, not just narrated around it.
if grep -q '^> [0-9]*\. \*\*Reconcile the docs against the repo before you commit\.\*\*' "$TAKE"; then
    ok "take-it's rule is a numbered step INSIDE the sub-agent prompt"
else
    bad "take-it's doc rule is not a numbered step inside the sub-agent prompt"
fi

# --- 2. In send-it it precedes the PR body -----------------------------------

doc_line="$(grep -n 'Reconcile the docs against the repo' "$SEND" | head -1 | cut -d: -f1)"
body_line="$(grep -n '^## 5\. Template-compliant PR body' "$SEND" | head -1 | cut -d: -f1)"
if [ -n "$doc_line" ] && [ -n "$body_line" ] && [ "$doc_line" -lt "$body_line" ]; then
    ok "send-it reconciles docs before the PR body is drafted"
else
    bad "send-it's doc step no longer precedes the PR body (doc=$doc_line body=$body_line)"
fi

# ...and it says WHY, which is what stops it being moved later as a tidy-up.
if printf '%s' "$send_flat" | grep -qi 'same PR as the change that invalidated it'; then
    ok "send-it explains why the step runs before the body"
else
    bad "send-it no longer explains why the doc step must precede the body"
fi

# --- 3. Both traps survive, with reasons -------------------------------------

for pair in "send-it:$send_flat" "take-it:$take_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"

    if printf '%s' "$body" | grep -qi 'Issue state is not evidence'; then
        ok "$name keeps the issue-state trap"
    else
        bad "$name lost the issue-state trap"
    fi

    # Both halves. "Closed doesn't mean done" alone still lets someone treat an
    # OPEN issue as proof the behaviour is absent, which is the other direction.
    if printf '%s' "$body" | grep -qi 'closed issue does not prove' &&
       printf '%s' "$body" | grep -qiE 'open one does not prove'; then
        ok "$name states BOTH directions of the issue-state trap"
    else
        bad "$name states only one direction of the issue-state trap"
    fi

    if printf '%s' "$body" | grep -qiE 'absence rot silently|deliberate absence'; then
        ok "$name keeps the deliberate-absence trap"
    else
        bad "$name lost the deliberate-absence trap"
    fi

    # The reason is the deletable part, and without it the rule reads as fussy.
    if printf '%s' "$body" | grep -qi 'nothing fails when they stop being true' ||
       printf '%s' "$body" | grep -qi 'nothing fails when these stop being true'; then
        ok "$name keeps the reason absence-claims rot"
    else
        bad "$name dropped why deliberate-absence claims rot"
    fi
done

# --- 4. The scope limiter survives -------------------------------------------
#
# An unbounded "check the docs" step is one nobody runs. #220 says so directly.

for pair in "send-it:$send_flat" "take-it:$take_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    if printf '%s' "$body" | grep -qiE 'not every markdown file'; then
        ok "$name bounds the step (not every markdown file)"
    else
        bad "$name lost the scope limiter — an unbounded doc step gets skipped"
    fi
done

# --- 5. dispatch-ready names it as reuse-critical ----------------------------
#
# dispatch-ready does not restate the prompt; it reuses take-it's. So its job is
# to name the doc step among the rules the reuse must preserve, exactly as it
# already does for the shared-state isolation rules. If it does not, a future
# edit that rebuilds the prompt drops the doc step and nothing notices.
if printf '%s' "$dispatch_flat" | grep -qi 'doc-reconciliation step'; then
    ok "dispatch-ready names the doc step among the reused rules"
else
    bad "dispatch-ready does not name the doc step as reuse-critical"
fi

if printf '%s' "$dispatch_flat" | grep -qiE 'never see an interactive session|cold worktree'; then
    ok "dispatch-ready records why its sub-agents need the rule spelled out"
else
    bad "dispatch-ready lost the reason its sub-agents need the rule"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-doc-reconciliation: FAILED ($fails)" >&2
    exit 1
fi
echo "Doc reconciliation tests: all green"
