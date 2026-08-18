#!/usr/bin/env bash
# pull-code-scanning.sh — one repo's FIRST-PARTY code-scanning exposure, split
# into what was just shipped and what is settled debt.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   PAGE_CAP   max 100-alert pages to read (default: 5 = 500 alerts)
#   BOUNDARY   new-vs-inherited split in days (default: 14)
#
# Output shape:
#   { "enabled": true|false|null, "analyzed": true|false|null,
#     "truncated": false, "open": N, "default_branch": "main",
#     "tools": ["CodeQL"],
#     "new": [ { "rule", "severity", "count", "oldest_age_days",
#                "alerts": [N], "autofix": "ready"|"none"|"unsupported"|null } ],
#     "inherited": { "count", "rules", "oldest_age_days",
#                    "by_severity": {"critical","high","medium","low"} } }
#
# WHY `analyzed` IS A SEPARATE FIELD: the alerts endpoint answers 404 for BOTH
# "Advanced Security is off" and "on, but no analysis has ever run". Both yield
# open:0, and they are opposite findings — one is a config gap, the other is a
# clean repo. Collapsing them reports a never-scanned repo as clean, which is
# strictly worse than reporting nothing. `enabled` keeps the same three-state
# contract as pull-dependency-exposure.sh: 403-for-scope stays null, never false.
#
# WHY PAGINATION IS NOT OPTIONAL: on 2026-08-18 a single per_page=100 read of
# Sassy-Dog/velovate returned exactly 100 alerts. The true count was 102. A
# capped number is indistinguishable from a measured one, so the cap is reported
# as `truncated: true` and the count is a floor.
#
# WHY THE REF FILTER: most_recent_instance.ref can name a PR merge ref. An alert
# that exists only on someone's branch is not this repo's debt and may never
# merge. The default branch is resolved, never assumed to be "main".
#
# WHY RULE-CLUSTERED: velovate carries 74 medium alerts. Rendered as 74 rows
# that is a wall nobody triages — the same failure that made a bare Dependabot
# count useless (see pull-dependency-exposure.sh). Rendered as "11 rules, oldest
# 214d" it is one honest line, and the handful shipped this week get attention.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: a repo with scanning disabled
# must still emit a valid JSON object rather than voiding the caller's scan.
set -uo pipefail

PAGE_CAP="${PAGE_CAP:-5}"
BOUNDARY="${BOUNDARY:-14}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[ -z "$REPO" ] && { echo 'skipped: could not determine REPO (set REPO=owner/name)' >&2; exit 10; }

# No default branch means no safe ref filter. Guessing "main" would silently
# count another branch's alerts as this repo's debt, so this degrades instead.
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
[ -z "$DEFAULT_BRANCH" ] && { echo "skipped: could not resolve default branch for ${REPO}" >&2; exit 10; }

state_json() {
    jq -nc --arg db "$DEFAULT_BRANCH" \
        --argjson en "$1" --argjson an "$2" \
        '{enabled: $en, analyzed: $an, truncated: false, open: null,
          default_branch: $db, tools: [],
          new: [],
          inherited: {count: null, rules: null, oldest_age_days: null,
                      by_severity: {critical: null, high: null, medium: null, low: null}}}'
}

alerts='[]'
truncated=false
page=1
while [ "$page" -le "$PAGE_CAP" ]; do
    if ! resp=$(gh api "repos/${REPO}/code-scanning/alerts?state=open&per_page=100&page=${page}" 2>&1); then
        if grep -qi 'advanced security must be enabled\|code scanning is not enabled' <<<"$resp"; then
            state_json false false; exit 0
        elif grep -qi 'no analysis found' <<<"$resp"; then
            state_json true false; exit 0
        else
            # Could not read: token scope, not a verdict. Stay null.
            state_json null null; exit 0
        fi
    fi
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$resp" || { state_json null null; exit 0; }
    count=$(jq 'length' <<<"$resp")
    alerts=$(jq -c --argjson a "$alerts" --argjson b "$resp" -n '$a + $b')
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
    [ "$page" -gt "$PAGE_CAP" ] && truncated=true
done

base=$(jq -c --arg ref "refs/heads/${DEFAULT_BRANCH}" --arg db "$DEFAULT_BRANCH" \
             --argjson boundary "$BOUNDARY" --argjson trunc "$truncated" '
  ( map(select(.most_recent_instance.ref == $ref))
    | map({rule: .rule.id,
           severity: (.rule.security_severity_level // "none"),
           tool: .tool.name,
           number: .number,
           age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
  | ($a | map(select(.age_days <= $boundary))) as $fresh
  | ($a | map(select(.age_days >  $boundary))) as $old
  | {critical: 4, high: 3, medium: 2, low: 1, none: 0} as $rank
  | { enabled: true, analyzed: true, truncated: $trunc,
      open: ($a | length),
      default_branch: $db,
      tools: ($a | map(.tool) | unique),
      new: ( $fresh | group_by(.rule) | map({
               rule: .[0].rule,
               severity: (max_by($rank[.severity]) | .severity),
               count: length,
               oldest_age_days: (map(.age_days) | max),
               alerts: (map(.number) | sort),
               autofix: null })
             | sort_by(-($rank[.severity])) ),
      inherited: {
        count: ($old | length),
        rules: ($old | map(.rule) | unique | length),
        oldest_age_days: (if ($old | length) == 0 then null else ($old | map(.age_days) | max) end),
        by_severity: {
          critical: ($old | map(select(.severity == "critical")) | length),
          high:     ($old | map(select(.severity == "high"))     | length),
          medium:   ($old | map(select(.severity == "medium"))   | length),
          low:      ($old | map(select(.severity == "low"))      | length) } } }
' <<<"$alerts")

# Autofix is probed ONLY for rules already ranked P0/P1 by severity. It can
# therefore only ever upgrade a P1 to P0; a medium rule is never probed and
# stays null. Probing all of velovate's 102 alerts would cost 102 calls to
# change nothing about how the mediums rank.
probe_rules=$(jq -r '.new[] | select(.severity == "critical" or .severity == "high") | "\(.rule)\t\(.alerts[0])"' <<<"$base")
while IFS=$'\t' read -r rule alert_no; do
    [ -z "$rule" ] && continue
    if fix=$(gh api "repos/${REPO}/code-scanning/alerts/${alert_no}/autofix" 2>&1); then
        status=$(jq -r '.status // "none"' <<<"$fix" 2>/dev/null)
        case "$status" in
            success) verdict="ready" ;;
            *)       verdict="none" ;;
        esac
    elif grep -qi 'not supported\|unprocessable' <<<"$fix"; then
        verdict="unsupported"
    else
        verdict="none"
    fi
    base=$(jq -c --arg r "$rule" --arg v "$verdict" \
        '.new = (.new | map(if .rule == $r then .autofix = $v else . end))' <<<"$base")
done <<<"$probe_rules"

jq -c '.' <<<"$base"
