#!/usr/bin/env bash
# pull-secret-scanning.sh — one repo's committed-credential exposure, split by
# whether GitHub could VALIDATE the credential against its provider.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   PAGE_CAP   max 100-alert pages to read (default: 5)
#
# Output shape:
#   { "enabled": true|false|null, "open": N, "oldest_age_days": N|null,
#     "active": [ { "number", "type", "age_days", "bypassed" } ],
#     "unknown_validity": [ { "number", "type", "age_days", "bypassed" } ],
#     "inactive": N }
#
# WHY VALIDITY IS THE PRIMARY SPLIT AND AGE IS NOT: `validity: "active"` means
# GitHub checked the credential against the issuing provider and it answered.
# That is not a severity estimate, it is a live secret, and it is P0 the moment
# it appears — a two-hour-old active key is worse than a year-old unverified
# one. Ranking these by age, the way stuck work is ranked, would bury the only
# unambiguous finding this endpoint produces. Probed live on 2026-08-18:
# Sassy-Dog/velovate carried two Google API keys at validity "active".
#
# `unknown` is not "probably fine". It usually means GitHub cannot validate that
# provider's format at all, so it stays a finding and escalates once nobody has
# triaged it for a month. `inactive` is already rotated: counted, never listed.
#
# `enabled` is three-state for the same reason as the sibling pulls: a 403 that
# means "this token cannot see it" must never render as "the feature is off".
#
# Deliberately `set -uo pipefail` WITHOUT `-e`.
set -uo pipefail

PAGE_CAP="${PAGE_CAP:-5}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[ -z "$REPO" ] && { echo 'skipped: could not determine REPO (set REPO=owner/name)' >&2; exit 10; }

state_json() {
    jq -nc --argjson en "$1" \
        '{enabled: $en, open: null, oldest_age_days: null,
          active: [], unknown_validity: [], inactive: null}'
}

alerts='[]'
page=1
while [ "$page" -le "$PAGE_CAP" ]; do
    if ! resp=$(gh api "repos/${REPO}/secret-scanning/alerts?state=open&per_page=100&page=${page}" 2>&1); then
        if grep -qi 'secret scanning is disabled\|is disabled on this repository' <<<"$resp"; then
            state_json false; exit 0
        else
            state_json null; exit 0
        fi
    fi
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$resp" || { state_json null; exit 0; }
    count=$(jq 'length' <<<"$resp")
    alerts=$(jq -c --argjson a "$alerts" --argjson b "$resp" -n '$a + $b')
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
done

jq -c '
  ( map({number,
          type: .secret_type_display_name,
          validity: (.validity // "unknown"),
          bypassed: (.push_protection_bypassed // false),
          age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
  | { enabled: true,
      open: ($a | length),
      oldest_age_days: (if ($a | length) == 0 then null else ($a | map(.age_days) | max) end),
      active: ($a | map(select(.validity == "active"))
                  | map({number, type, age_days, bypassed}) | sort_by(.age_days)),
      unknown_validity: ($a | map(select(.validity == "unknown"))
                            | map({number, type, age_days, bypassed}) | sort_by(-.age_days)),
      inactive: ($a | map(select(.validity == "inactive")) | length) }
' <<<"$alerts"
