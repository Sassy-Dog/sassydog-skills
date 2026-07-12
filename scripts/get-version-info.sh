#!/usr/bin/env bash
# get-version-info.sh — Single Source of Truth for computing this repo's
# version (org Versioning spec v1.0, platform#397; adopted via #31).
#
# This repo is a Claude Code plugin marketplace — spec §7 "Library / plugin
# (committed manifest)" row:
#
#   - MARKETING VERSION (this script): monthly-rolling CalVer,
#       YYYY.M.<commits-this-month>     e.g. 2026.7.16
#     Non-padded month; patch = commits on the default branch since the 1st
#     of the current month (UTC), floored at 1. CalVer IS valid semver, so
#     version-ordering consumers (Claude Code's plugin update flow) keep
#     working — and 2026.M.P strictly exceeds the pre-adoption 0.x semver
#     train, so the switch needed no cutover gate (spec §6).
#
#   - BUILD NUMBER: N/A for this repo (spec §7) — no store, appcast, or
#     force-update surface consumes a monotonic integer.
#     scripts/get-build-number.sh intentionally does not exist; do not add
#     one without a declared change via platform#397.
#
#   - VERSION-OF-RECORD: the committed `version` in
#     .claude-plugin/plugin.json. This script only COMPUTES a candidate;
#     scripts/stamp-version.sh (the §4 mint analog) resolves and WRITES the
#     record at release time. Consumers read the manifest, never this script.
#
# Full history required: the patch undercounts on shallow clones (spec §2).
# Nothing in CI computes a version today (the CI gate only shape-checks the
# committed manifest); if that ever changes, the computing job needs
# `fetch-depth: 0`.
#
# Usage:
#   bash scripts/get-version-info.sh              # 2026.7.16
#   bash scripts/get-version-info.sh --version    # same (org-consistent alias)
#
# Overrides / test seams (org-canonical names, spec §3):
#   MARKETING_VERSION=2026.7.9       -> emitted verbatim (replay pin;
#                                       stamp-version.sh never auto-bumps it)
#   VERSION_DATE_OVERRIDE=YYYY-MM-DD -> pin "today" (UTC) for tests
#   VERSION_PATCH_OVERRIDE=N         -> pin the monthly patch for tests

set -euo pipefail

# Current date (UTC), honoring the VERSION_DATE_OVERRIDE test seam.
get_today() {
    if [ -n "${VERSION_DATE_OVERRIDE:-}" ]; then
        echo "$VERSION_DATE_OVERRIDE"
    else
        date -u +%Y-%m-%d
    fi
}

# Monthly patch = commits since the 1st of the current month (UTC), floored
# at 1. The floor makes count 0 and count 1 indistinguishable; the ladder in
# stamp-version.sh resolves any resulting collision against the committed
# manifest (spec §2/§4).
get_patch() {
    local patch today month_start
    if [ -n "${VERSION_PATCH_OVERRIDE:-}" ]; then
        patch="$VERSION_PATCH_OVERRIDE"
    else
        today=$(get_today)
        month_start="${today%-*}-01T00:00:00Z"
        patch=$(git rev-list --count --since="$month_start" HEAD)
    fi
    if [ "$patch" = "0" ]; then
        patch=1
    fi
    echo "$patch"
}

get_version() {
    # Full-version replay pin always wins, verbatim.
    if [ -n "${MARKETING_VERSION:-}" ]; then
        echo "$MARKETING_VERSION"
        return
    fi
    local today year month
    today=$(get_today)
    year="${today%%-*}"
    month=$((10#$(echo "$today" | cut -d- -f2)))   # strip leading zero: 07 -> 7
    echo "${year}.${month}.$(get_patch)"
}

case "${1:-}" in
    ""|--version) get_version ;;
    *)
        echo "usage: bash scripts/get-version-info.sh [--version]" >&2
        exit 64
        ;;
esac
