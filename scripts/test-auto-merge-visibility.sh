#!/usr/bin/env bash
# test-auto-merge-visibility.sh — pins the SECOND precondition on setup-deps'
# auto-merge render: repo visibility (issue #178).
#
# Why this is a source-level guard and not a render test. The auto-merge
# workflow's render decision is not made by a script — `render-dependabot.sh`
# renders `dependabot.yml` only. The decision lives in SKILL.md prose that an
# agent follows, so the artifact under test is the instruction itself, the same
# way test-label-migrate.sh pins align-labels.sh's single-call-site invariant
# and test-detect-hook-stack.sh pins "has_tracked carries no pipeline".
#
# The bug it guards is the expensive kind: invisible at render time, surfacing
# weeks later somewhere else. The rendered workflow mints a GitHub App token
# from org secrets; org secrets at `private` visibility (= private + internal)
# exclude PUBLIC repos in BOTH the Actions and the Dependabot store. Rendered
# into a public repo, `secrets.*` resolves to the empty string and
# `create-github-app-token` fails on that repo's next Dependabot PR — as an auth
# error that looks unrelated to the generator run that caused it. sassydog-skills
# went public on 2026-08-12 and its auto-merge workflow was deleted rather than
# re-credentialed (#177); without this guard the next `setup-deps` run would put
# it straight back, because a merge gate is present and the gate was the only
# precondition the skill checked.
#
# Four properties are asserted:
#
#   1. SKILL.md probes visibility (`gh repo view … --json visibility`).
#   2. SKILL.md states the public → do-not-render rule.
#   3. The Guardrails section carries it as a standing rule, not only as prose
#      buried in the classification step — guardrails are what a hurried reader
#      checks.
#   4. dependabot.yml.template does NOT assert unconditionally that
#      dependabot-auto-merge.yml holds semver-major, because in a public repo
#      that workflow is deliberately absent and the claim would be false.
#
# No gh, no network, no repo mutation — it reads two tracked files.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-auto-merge-visibility.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-auto-merge-visibility: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SKILL="skills/setup-deps/SKILL.md"
TEMPLATE="skills/setup-deps/references/templates/dependabot.yml.template"

fails=0
ok()   { echo "  ok    $1"; }
bad()  { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "auto-merge visibility precondition (issue #178)"

for f in "$SKILL" "$TEMPLATE"; do
    [ -r "$f" ] || { bad "missing file: $f"; }
done
[ "$fails" -eq 0 ] || { echo "test-auto-merge-visibility: FAILED" >&2; exit 1; }

# 1. The probe itself. Without it the rule cannot be applied, however well the
#    prose describes it.
if grep -qE 'gh repo view.*--json visibility' "$SKILL"; then
    ok "SKILL.md probes repo visibility"
else
    bad "SKILL.md has no 'gh repo view … --json visibility' probe"
fi

# 2. The rule. Matched on the pairing of 'public' with a do-not-render
#    instruction, so a passing mention of the word 'public' elsewhere in the
#    file cannot satisfy it.
if grep -iE 'public' "$SKILL" | grep -qiE 'do not render|never render|not render'; then
    ok "SKILL.md states public -> do not render auto-merge"
else
    bad "SKILL.md does not tie 'public' to a do-not-render instruction"
fi

# 3. The standing guardrail. Scoped to the Guardrails section only — the rule
#    existing somewhere in the body is property 2's job, not this one.
guardrails="$(awk '/^## Guardrails/{f=1; next} /^## /{f=0} f' "$SKILL")"
if printf '%s' "$guardrails" | grep -qiE 'public'; then
    ok "Guardrails section carries the public-repo rule"
else
    bad "Guardrails section does not mention the public-repo rule"
fi

# 4. The template must not claim coverage it may not have. The pre-fix wording
#    was 'and dependabot-auto-merge.yml holds them anyway' — an unconditional
#    assertion that is false in exactly the repos this change is about.
if grep -qE 'holds them anyway' "$TEMPLATE"; then
    bad "template still asserts auto-merge 'holds them anyway' unconditionally"
else
    ok "template makes no unconditional auto-merge coverage claim"
fi

# ...and it must still explain the semver-major exclusion, which is the reason
# that comment block exists. Guarding only against the old sentence would let
# deleting the whole paragraph pass.
if grep -qiE 'semver-major is excluded' "$TEMPLATE"; then
    ok "template still explains the semver-major exclusion"
else
    bad "template no longer explains why semver-major is excluded"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-auto-merge-visibility: FAILED ($fails)" >&2
    exit 1
fi
echo "auto-merge visibility tests: all green"
