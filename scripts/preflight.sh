#!/usr/bin/env bash
# preflight.sh — this repo's CI gates, runnable locally. CI's `ci` job calls
# THIS script for every gate except actionlint, which CI runs as a separate step
# from a pinned native binary (ci.yml explains why it is not the dockerized
# action); this script runs actionlint too when a local binary or docker is
# available, and reports a skip when neither is.
#
# Guard regexes live here and only here. Tool VERSIONS do not: markdownlint-cli2
# is pinned below, but shellcheck is whatever is on PATH locally versus an exact
# pin in ci.yml. That gap is real and documented in CONTRIBUTING.md — a local
# pass on a different shellcheck is not proof of a green build.
#
# Run it before every PR; `--fix` lets markdownlint auto-fix first.
#
# Usage: bash scripts/preflight.sh [--fix]
#
# Gates, in CI order:
#   1. shellcheck -S warning over every tracked *.sh
#   2. frontmatter sanity (scripts/check-frontmatter.sh) — two layers. LOADER
#      requirements on every tracked skill/agent file: opening `---` on line 1,
#      `name`/`description` present, `name` matching the directory (skills) or
#      filename (agents). AGENT SKILLS SPEC constraints on `SKILL.md` ONLY
#      (issue #118): `description` <= 1024 characters, `name` <= 64 characters
#      with charset and hyphen rules, and a strict frontmatter key allowlist
#      (name, description, license, compatibility, allowed-tools, metadata)
#      whose unknown keys HARD-fail, matching what `gh skill publish` rejects.
#      `agents/*.md` are deliberately exempt from the spec layer — an agent is
#      not a skill and legitimately carries `color:`.
#   3. no bare positional tokens in Skill-args substitution surfaces (issue #39)
#   4. no legacy name residue outside the per-name sanctioned back-compat
#      files, in three groups (all enforced under this one gate): the renamed
#      generator family — 'create-dev-workflows', 'refresh-sassydog-',
#      'refresh-skills', 'refresh-hooks', 'refresh-deps' (issue #120); the
#      plugin and marketplace renames — 'ai-agent-skills', 'sassy-dog-skills'
#      (issue #71); and the workflow-skill naming sweep — 'plate-it',
#      'groom-it', 'drain-it', 'clean-it'
#   5. plugin manifests are valid JSON, the plugin version is CalVer
#      (YYYY.M.P — the one-way ratchet, docs/VERSIONING.md), and any
#      marketplace.json plugins[].version equals it (issue #31)
#   6. versioning tests (scripts/test-versioning.sh)
#   7. ownership-matcher tests (scripts/test-ownership-matchers.sh) — the
#      setup-hooks / setup-deps `generated-by:` matchers, extracted from the
#      shipped SKILL.md files and run against real pre-rename consumer
#      artifacts committed under scripts/fixtures/legacy-markers/ (issue #133)
#   8. label-taxonomy tests (scripts/test-label-taxonomy.sh) — the two label
#      taxonomies stay disjoint AND perceptually separated (cross-set CIEDE2000
#      check), issue-claim.sh's label reconcile still CORRECTS a drifted label
#      instead of silently skipping it (issue #161), and there is no THIRD copy
#      of either table: every colour from both emitters is searched for across
#      the tracked tree and any hit outside its own home fails (issue #167 —
#      the cross-set check scores two taxonomies, so a copy anywhere else is
#      invisible to it). Definitions and a mock gh only: no repo, no network.
#   9. label-migrate tests (scripts/test-label-migrate.sh) — align-labels.sh's
#      relabel-then-delete migrate mode cannot delete a label whose relabel has
#      not been verified by re-query (issue #163). Mock gh only; the MODE
#      itself is never run in CI, because it mutates other repos' issues.
#  10. dependabot-render tests (scripts/test-dependabot-render.sh) — setup-deps
#      renders one lane per (ecosystem, DIRECTORY) and every lane is backed by a
#      manifest in the directory it names, against three recorded consumer
#      layouts; the collapsed-to-"/" v2 shape must be REJECTED (issue #169).
#      Recorded file lists only: no repo, no network.
#  11. detect-hook-stack tests (scripts/test-detect-hook-stack.sh) —
#      setup-hooks' has_tracked probe still answers correctly when the match
#      list is LARGE. Under pipefail a `| head -1 | grep -q .` returns the
#      writer's SIGPIPE 141 once the output outruns the ~64KB pipe buffer, so a
#      MATCH read as a miss and the render silently dropped that tool's route
#      (issue #172). Needs a 20k-path fixture, because a small one passes
#      either way; the gate fails loudly if that fixture ever stops tripping
#      the pre-fix shape. Index-only temp repos: no real repo, no network.
#  12. visibility precondition tests (scripts/test-visibility-preconditions.sh)
#      — setup-deps' App-token renders have TWO preconditions, not one: a merge
#      gate AND a non-public repo. Its org secrets are `private`-visibility,
#      which excludes public repos in both the Actions and Dependabot stores, so
#      a render into one produces a workflow whose `secrets.*` are empty and
#      which fails weeks later on that repo's next Dependabot PR, as an auth
#      error that looks unrelated (issue #178). The precondition belongs to the
#      CREDENTIAL, not to one workflow: three templates mint it, #178 gated only
#      auto-merge, and the two it missed are the two that check out PR head
#      (issue #186) — hence the rename from test-auto-merge-visibility.sh. The
#      decision is SKILL.md prose, not script, so this pins the instruction —
#      same shape as the label-migrate single-call-site guard. Must-not-exist
#      assertions run against a whitespace-flattened copy, because this repo
#      hard-wraps prose and a line-scoped grep for forbidden wording turns a
#      wrap into a false PASS. Reads two tracked files: no gh, no network.
#  13. verify-issue-refs tests (scripts/test-verify-issue-refs.sh) — the
#      grooming-drift checker. Two of its failure modes are SILENT and neither
#      changes an exit code: `\b` in a git -E harvest pattern matches nothing,
#      which empties the near-match pool so every unresolved reference tiers as
#      `likely-new` and the checker quietly stops finding drift; and a
#      suggestion ranked on raw edit distance answers the shortest neighbour
#      (`open`) instead of the actual rename (`open_in`), which is worse than
#      no suggestion because it is the line a reader acts on without
#      re-checking. Also pins the NEGATIVE cases — a clean body and a
#      new-subtree body must stay quiet — since a checker that fires on
#      everything is muted within a day and then gates nothing at all.
#      Fixture tree is synthetic and built in a tmpdir: no gh, no network.
#  14. stale-issues tests (scripts/test-stale-issues.sh) — the
#      tracking-parent-complete detector (issue #198). An epic that splits into
#      children can never close itself: GitHub moves an issue only on a merged
#      PR's closing keyword, and a tracking parent is the issue no PR ever
#      names. All three of this detector's wrong answers are silent — a missed
#      parent is indistinguishable from a clean repo, a PREFIX COLLISION
#      (#28 claiming #283's children) tells a human to close live work, and a
#      TRUNCATED pull returns the same empty list a clean one does. The prefix
#      fixture is mutation-proved: a copy of the script whose regex has lost
#      its non-digit guard MUST report #28, or the decoy has gone vacuous.
#      Mock gh serving recorded JSON: no repo, no network, and the run is
#      asserted to issue zero non-read calls.
#  15. markdownlint (pinned markdownlint-cli2 version)
#  16. actionlint — best-effort locally (binary, else docker); SKIPPED in CI
#      (CI=true) because the workflow runs it as its own step
#
# All gates run even after a failure (accumulate-and-report, same pattern as
# check-frontmatter.sh). Exit 0 = all pass, 1 = any fail. Tools that are not
# installed locally SKIP with a note — CI still enforces them.
set -uo pipefail

MARKDOWNLINT_PKG="markdownlint-cli2@0.18.1"
ACTIONLINT_IMAGE="rhysd/actionlint:1.7.7"

FIX=0
case "${1:-}" in
    --fix) FIX=1 ;;
    "") ;;
    *) echo "usage: bash scripts/preflight.sh [--fix]" >&2; exit 64 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && { echo "preflight: not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

fail=0
pass() { echo "PASS  $1" >&2; }
failed() { echo "FAIL  $1" >&2; fail=1; }
skip() { echo "SKIP  $1" >&2; }

# --- 1. shellcheck ----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    sh_files=$(git ls-files '*.sh')
    if [ -z "$sh_files" ]; then
        pass "shellcheck (no *.sh files)"
    elif echo "$sh_files" | xargs shellcheck -S warning; then
        pass "shellcheck -S warning"
    else
        failed "shellcheck -S warning"
    fi
else
    skip "shellcheck (not installed — CI still enforces)"
fi

# --- 2. frontmatter ---------------------------------------------------------
if bash scripts/check-frontmatter.sh; then
    pass "frontmatter sanity"
else
    failed "frontmatter sanity"
fi

# --- 3. no bare positional tokens in Skill-args substitution surfaces -------
# SKILL.md bodies (and the config templates that render into consumer repos)
# get $1-$9/$ARGUMENTS substituted when the skill is invoked with args — a
# literal $1 in a snippet is corrupted at render time. references/ docs and
# scripts/ (including this one) are not substituted.
#
# The template pathspec is asserted non-empty FIRST. A pathspec that matches
# nothing makes `git ls-files` emit no paths, so the guard would still pass
# while silently covering nothing — which is exactly what a rename of the
# generator directory used to cause. Fail loudly instead.
POSITIONAL_TEMPLATE_GLOB='skills/setup-config/references/templates/*'
if [ -z "$(git ls-files "$POSITIONAL_TEMPLATE_GLOB")" ]; then
    failed "positional-token guard — template pathspec '$POSITIONAL_TEMPLATE_GLOB' matched no tracked files (renamed or moved? the guard would silently cover nothing)"
else
    # shellcheck disable=SC2016  # the regex is a literal, not a missed expansion
    if git ls-files 'skills/*/SKILL.md' '.claude/skills/*/SKILL.md' "$POSITIONAL_TEMPLATE_GLOB" \
        | xargs grep -nE '\$([0-9]|@|\*)'; then
        failed "positional-token guard — use cut -f1/%(format) idioms or move the snippet to references/ or scripts/ (issue #39)"
    else
        pass "positional-token guard"
    fi
fi

# --- 4. no legacy skill-name residue -----------------------------------------
# The whole generator family was renamed to setup-* in issue #120:
#   create-dev-workflows -> refresh-sassydog-skills (0.9.0)
#   refresh-sassydog-skills -> refresh-skills (2026.7.22)
#   refresh-skills -> setup-config (issue #121)
#   refresh-hooks -> setup-hooks (issue #122)
#   refresh-deps  -> setup-deps  (issue #123)
# Every superseded name may appear only in the sanctioned backward-compat
# mentions — the ownership matchers still have to RECOGNISE artifacts produced
# under the older names, and those markers are committed inside every consumer
# repo. Anything else is a stale reference that would confuse a render or send
# a reader to a dead path.
#
# Exclusions are PER NAME, not one shared union: a name is sanctioned in
# exactly the files that must still spell it out. A union list would let a
# stale `refresh-deps` hide in a file sanctioned only for `refresh-skills`,
# which is the residue this guard exists to catch.
legacy_residue=0
for legacy in 'create-dev-workflows' 'refresh-sassydog-' 'refresh-skills' 'refresh-hooks' 'refresh-deps'; do
    case "$legacy" in
        refresh-skills)
            # setup-config's marker recognizer, the adopt/update walkthrough
            # that names the superseded producer, and CLAUDE.md's statement of
            # the same recognition rule.
            allow=(
                ':!skills/setup-config/SKILL.md'
                ':!skills/setup-config/references/update-mode.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
            ) ;;
        refresh-hooks)
            # setup-hooks' generated-by ownership matcher + CLAUDE.md's
            # statement of it, plus the committed consumer artifacts that
            # PROVE the matcher still accepts this producer name (issue #133 —
            # the fixtures are verbatim upstream bytes; sanitising the name out
            # of them would defeat their entire purpose).
            allow=(
                ':!skills/setup-hooks/SKILL.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
        refresh-deps)
            # setup-deps' generated-by ownership matcher + the committed
            # consumer artifacts proving the matcher accepts it (issue #133).
            allow=(
                ':!skills/setup-deps/SKILL.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
        *)
            # 'refresh-sassydog-' also appears verbatim inside the committed
            # consumer hook fixtures (issue #133).
            allow=(
                ':!skills/setup-config/references/update-mode.md'
                ':!skills/setup-config/references/migrate-mode.md'
                ':!skills/setup-config/SKILL.md'
                ':!skills/setup-deps/SKILL.md'
                ':!skills/setup-hooks/SKILL.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
    esac
    if git grep -l "$legacy" -- "${allow[@]}"; then
        failed "legacy-name guard — '$legacy' outside the sanctioned back-compat files"
        legacy_residue=1
    fi
done

# The plugin itself renamed too: ai-agent-skills -> sassy-dog, the marketplace
# sassy-dog-skills -> sassydog-skills (issue #71), and the GitHub repo
# ai-agent-skills -> sassydog-skills (issue #72). The old plugin name may
# appear ONLY where it is still load-bearing:
#   - README.md — the one historical line recording the #71 rename
#   - CLAUDE.md — the marker-recognition rule: recognizers must accept
#     pre-rename 'generated-by: ai-agent-skills:*' markers
#   - skills/setup-deps/SKILL.md, skills/setup-hooks/SKILL.md — those
#     generated-by recognizers themselves. Their markers are committed inside
#     every consumer repo, so each must also keep naming its own superseded
#     producers (setup-hooks accepts refresh-hooks and refresh-sassydog-hooks,
#     see issue #122; setup-deps accepts refresh-deps and refresh-sassydog-deps,
#     see issue #123) — a narrower matcher would silently treat a pre-rename
#     consumer file as hand-written.
#   - scripts/fixtures/legacy-markers/ — real consumer artifacts still stamped
#     with the pre-rename namespace, committed verbatim so the matchers are
#     proven against a genuine older-plugin file rather than a synthetic
#     pattern we wrote ourselves (issue #133)
#   - this script (the guard itself)
if git grep -l 'ai-agent-skills' -- \
    ':!README.md' \
    ':!CLAUDE.md' \
    ':!skills/setup-deps/SKILL.md' \
    ':!skills/setup-hooks/SKILL.md' \
    ':!scripts/preflight.sh' \
    ':!scripts/fixtures/legacy-markers/'; then
    failed "legacy-name guard — 'ai-agent-skills' outside the sanctioned files (plugin renamed to sassy-dog, issue #71)"
    legacy_residue=1
fi

# The old marketplace name may appear only in the one-time re-add
# instructions (which must name it to remove it) and this script.
if git grep -l 'sassy-dog-skills' -- \
    ':!README.md' \
    ':!scripts/preflight.sh'; then
    failed "legacy-name guard — 'sassy-dog-skills' outside the sanctioned files (marketplace renamed to sassydog-skills, issue #71)"
    legacy_residue=1
fi

# Four workflow skills lost the -it suffix in the collection-scope naming
# sweep: plate-it -> survey-work, groom-it -> groom-backlog (nee fill-it),
# drain-it -> dispatch-ready, clean-it -> tidy-repo. Each legacy name may
# appear ONLY where it is still load-bearing:
#   - the renamed skill's own SKILL.md — legacy trigger phrases, the
#     "Formerly" note, and the stranded-pre-rename-config detection
#   - skills/setup-config/SKILL.md + references/{migrate,update}-mode.md —
#     the rename map and legacy-artifact recognition (generated dirs and
#     pre-rename config filenames keep their old names in consumer repos)
#   - skills/whats-on-fire/SKILL.md — the blind-spot probe distinguishes a
#     legacy-named survey-work config from a missing one
#   - README.md — the "(formerly ...)" annotations
#   - this script (the guard itself)
for legacy in 'plate-it' 'groom-it' 'drain-it' 'clean-it'; do
    if git grep -l "$legacy" -- \
        ':!skills/survey-work/SKILL.md' \
        ':!skills/groom-backlog/SKILL.md' \
        ':!skills/dispatch-ready/SKILL.md' \
        ':!skills/tidy-repo/SKILL.md' \
        ':!skills/setup-config/SKILL.md' \
        ':!skills/setup-config/references/migrate-mode.md' \
        ':!skills/setup-config/references/update-mode.md' \
        ':!skills/whats-on-fire/SKILL.md' \
        ':!README.md' \
        ':!scripts/preflight.sh'; then
        failed "legacy-name guard — '$legacy' outside the sanctioned back-compat files (naming sweep: collection-scoped skills lost -it)"
        legacy_residue=1
    fi
done

[ "$legacy_residue" -eq 0 ] && pass "legacy-name guard"

# --- 5. plugin manifests -----------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    if jq -e . .claude-plugin/plugin.json .claude-plugin/marketplace.json >/dev/null; then
        pass "plugin manifests valid JSON"

        # Version-of-record guard (issue #31; docs/VERSIONING.md; org
        # Versioning spec §7 committed-manifest row). CalVer adoption is a
        # ONE-WAY RATCHET: a hand-rolled 0.x/1.x here reads as a permanent
        # downgrade to version-ordering consumers. Stamp via
        # scripts/stamp-version.sh, never by hand.
        plugin_version=$(jq -r '.version // empty' .claude-plugin/plugin.json)
        if echo "$plugin_version" | grep -qE '^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$'; then
            pass "plugin version is CalVer ($plugin_version)"
        else
            failed "plugin version '$plugin_version' is not CalVer (YYYY.M.P) — stamp via scripts/stamp-version.sh (docs/VERSIONING.md)"
        fi

        # One repo-wide CalVer: any plugins[].version in marketplace.json
        # must equal the version-of-record (per-plugin drift forbidden).
        if jq -e --arg v "$plugin_version" \
            '[.plugins[]? | select(has("version")) | .version == $v] | all' \
            .claude-plugin/marketplace.json >/dev/null; then
            pass "marketplace plugins[].version matches version-of-record"
        else
            failed "marketplace.json plugins[].version differs from plugin.json — one repo-wide CalVer; stamp via scripts/stamp-version.sh"
        fi
    else
        failed "plugin manifests valid JSON"
    fi
else
    skip "plugin manifests (jq not installed — CI still enforces)"
fi

# --- 6. versioning tests -------------------------------------------------------
if bash scripts/test-versioning.sh; then
    pass "versioning tests (scripts/test-versioning.sh)"
else
    failed "versioning tests (scripts/test-versioning.sh)"
fi

# --- 7. ownership-matcher tests -----------------------------------------------
if bash scripts/test-ownership-matchers.sh; then
    pass "ownership-matcher tests (scripts/test-ownership-matchers.sh)"
else
    failed "ownership-matcher tests (scripts/test-ownership-matchers.sh)"
fi

# --- 8. label-taxonomy tests ---------------------------------------------------
# Definitions + a mock gh. #158 deliberately kept align-labels.sh out of CI
# because it MUTATES other repos — this gate runs neither applying mode, only
# the cross-set colour check (`--collisions`, which needs no repo and no
# network) and issue-claim.sh's reconcile logic against a recorded mock.
if bash scripts/test-label-taxonomy.sh; then
    pass "label-taxonomy tests (scripts/test-label-taxonomy.sh)"
else
    failed "label-taxonomy tests (scripts/test-label-taxonomy.sh)"
fi

# --- 9. label-migrate tests ----------------------------------------------------
# Same rule as gate 8, one notch more dangerous: align-labels.sh's migrate mode
# DELETES labels in other repos, and a delete strips the label from every issue
# carrying it unrecoverably. So CI runs the mode's PROOF, never the mode — a
# mock gh that records writes, plus a source-level invariant (one delete call
# site, inside the gate, downstream of the re-query) and a mutation that
# neuters the gate to show the withheld delete was withheld BY it (issue #163).
if bash scripts/test-label-migrate.sh; then
    pass "label-migrate tests (scripts/test-label-migrate.sh)"
else
    failed "label-migrate tests (scripts/test-label-migrate.sh)"
fi

# --- 10. dependabot-render tests -----------------------------------------------
# setup-deps stopped being valid-by-construction when its template gained a
# per-(ecosystem, directory) repeat (issue #169), so the render is checked
# dynamically instead — here against recorded consumer file lists, and at run
# time by validate-dependabot.sh against the repo being written into. The gate
# also asserts the OLD shape fails: a validator that accepts every lane
# collapsed onto "/" proves nothing.
if bash scripts/test-dependabot-render.sh; then
    pass "dependabot-render tests (scripts/test-dependabot-render.sh)"
else
    failed "dependabot-render tests (scripts/test-dependabot-render.sh)"
fi

# --- 11. detect-hook-stack tests -----------------------------------------------
# The bug this pins (issue #172) is size-dependent: `has_tracked` returned the
# writer's SIGPIPE 141 rather than "match" once the match list overran the pipe
# buffer, so the five affected detections under-reported on exactly the largest
# repos and the render dropped a route with nothing in the output to say so. A
# small fixture proves nothing here, so the test builds a 20k-path index-only
# repo and asserts BOTH that the pre-fix shape still fails on it (else the test
# has gone vacuous) and that the shipped probe does not.
if bash scripts/test-detect-hook-stack.sh; then
    pass "detect-hook-stack tests (scripts/test-detect-hook-stack.sh)"
else
    failed "detect-hook-stack tests (scripts/test-detect-hook-stack.sh)"
fi

# --- 12. visibility preconditions -------------------------------------------
# sassydog-skills went public on 2026-08-12 and its auto-merge workflow was
# deleted rather than re-credentialed (#177). Without this gate the next
# setup-deps run would put it straight back: a merge gate is present, and the
# gate was the only precondition the skill checked. The failure it reintroduces
# is invisible at render time and surfaces elsewhere, later, looking unrelated.
# #186 widened this from the auto-merge workflow to every template that mints
# the App token, after the same failure was found open through two other doors.
if bash scripts/test-visibility-preconditions.sh; then
    pass "visibility precondition tests (scripts/test-visibility-preconditions.sh)"
else
    failed "visibility precondition tests (scripts/test-visibility-preconditions.sh)"
fi

# --- 13. verify-issue-refs tests ---------------------------------------------
if bash scripts/test-verify-issue-refs.sh; then
    pass "verify-issue-refs tests (scripts/test-verify-issue-refs.sh)"
else
    failed "verify-issue-refs tests (scripts/test-verify-issue-refs.sh)"
fi

# --- 14. stale-issues tests ---------------------------------------------------
# The tracking-parent-complete detector is the only thing that notices a
# finished epic, so every way it can be wrong is silent: a miss looks like a
# clean repo, a prefix collision points a human at live work, and a truncated
# pull returns the empty list a clean pull returns. The prefix fixture is
# mutation-proved live rather than trusted. Mock gh only: no repo, no network.
if bash scripts/test-stale-issues.sh; then
    pass "stale-issues tests (scripts/test-stale-issues.sh)"
else
    failed "stale-issues tests (scripts/test-stale-issues.sh)"
fi

# --- 15. markdownlint --------------------------------------------------------
if command -v npx >/dev/null 2>&1; then
    if [ "$FIX" = "1" ]; then
        npx -y "$MARKDOWNLINT_PKG" --fix "**/*.md" >/dev/null 2>&1 || true
    fi
    if md_out=$(npx -y "$MARKDOWNLINT_PKG" "**/*.md" 2>&1); then
        pass "markdownlint ($MARKDOWNLINT_PKG)"
    else
        echo "$md_out" | grep -v '^npm' | tail -30 >&2
        failed "markdownlint ($MARKDOWNLINT_PKG)"
    fi
else
    skip "markdownlint (npx not installed — CI still enforces)"
fi

# --- 16. actionlint (best-effort locally; CI runs its own dockerized step) ---
if [ "${CI:-}" = "true" ]; then
    skip "actionlint (separate CI step)"
elif command -v actionlint >/dev/null 2>&1; then
    if actionlint -color; then pass "actionlint"; else failed "actionlint"; fi
elif docker info >/dev/null 2>&1; then
    if docker run --rm -v "$PWD:/repo" --workdir /repo "$ACTIONLINT_IMAGE" -color; then
        pass "actionlint (docker)"
    else
        failed "actionlint (docker)"
    fi
else
    skip "actionlint (no binary or docker — CI still enforces)"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "preflight: all gates green" >&2
    exit 0
else
    echo "preflight: FAILURES above" >&2
    exit 1
fi
