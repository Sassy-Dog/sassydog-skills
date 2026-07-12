#!/usr/bin/env bash
# preflight.sh — this repo's CI gates, runnable locally. CI's `ci` job calls
# THIS script for every gate except actionlint (which stays a separate
# dockerized CI step), so the version pins and guard regexes live in exactly
# one place. Run it before every PR; `--fix` lets markdownlint auto-fix first.
#
# Usage: bash scripts/preflight.sh [--fix]
#
# Gates, in CI order:
#   1. shellcheck -S warning over every tracked *.sh
#   2. frontmatter sanity (scripts/check-frontmatter.sh)
#   3. no bare positional tokens in Skill-args substitution surfaces (issue #39)
#   4. no legacy 'create-dev-workflows' residue outside sanctioned files
#   5. plugin manifests are valid JSON, the plugin version is CalVer
#      (YYYY.M.P — the one-way ratchet, docs/VERSIONING.md), and any
#      marketplace.json plugins[].version equals it (issue #31)
#   6. versioning tests (scripts/test-versioning.sh)
#   7. markdownlint (pinned markdownlint-cli2 version)
#   8. actionlint — best-effort locally (binary, else docker); SKIPPED in CI
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
# SKILL.md bodies (and templates that render into consumer-repo SKILL.md
# bodies) get $1-$9/$ARGUMENTS substituted when the skill is invoked with args
# — a literal $1 in a snippet is corrupted at render time. references/ docs
# and scripts/ (including this one) are not substituted.
# shellcheck disable=SC2016  # the regex is a literal, not a missed expansion
if git ls-files 'skills/*/SKILL.md' '.claude/skills/*/SKILL.md' 'skills/refresh-sassydog-skills/references/templates/*.md' \
    | xargs grep -nE '\$([0-9]|@|\*)'; then
    failed "positional-token guard — use cut -f1/%(format) idioms or move the snippet to references/ or scripts/ (issue #39)"
else
    pass "positional-token guard"
fi

# --- 4. no legacy skill-name residue -----------------------------------------
# The generator was renamed create-dev-workflows -> refresh-sassydog-skills
# (0.9.0). The legacy name may appear only in the sanctioned backward-compat
# mentions; anything else is a stale reference that would confuse renders.
if git grep -l 'create-dev-workflows' -- \
    ':!skills/refresh-sassydog-skills/references/update-mode.md' \
    ':!skills/refresh-sassydog-skills/SKILL.md' \
    ':!CLAUDE.md' \
    ':!scripts/preflight.sh'; then
    failed "legacy-name guard — 'create-dev-workflows' outside the sanctioned back-compat files"
else
    pass "legacy-name guard"
fi

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

# --- 7. markdownlint ---------------------------------------------------------
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

# --- 8. actionlint (best-effort locally; CI runs its own dockerized step) ----
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
