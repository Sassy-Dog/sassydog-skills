#!/usr/bin/env bash
# pull-dependency-exposure.sh — one repo's dependency-security exposure and,
# more importantly, whether it is actually being REMEDIATED.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   PR_LIMIT   max open Dependabot PRs to inspect (default: 20)
#
# Output shape:
#   { "enabled": true|false|null,
#     "open": N, "high_crit": N,
#     "oldest_high_crit_age_days": N|null,
#     "vulnerable_packages": [ "next", ... ],
#     "open_fix_prs": [ { "number", "title", "state", "age_days", "addresses": [...] } ],
#     "unremediated_packages": [ "drizzle-orm", ... ],
#     "parked_green": [ { "number", "age_days" } ] }
#
# WHY THIS EXISTS: a prioritization pass that reads only an alert COUNT cannot
# act on it. The count is a lagging indicator — it drops only when a fix merges,
# so a same-day CVE batch with a green fix PR already queued produces the same
# number as a year of neglect. On 2026-07-25 that ambiguity cost a real cycle:
# an org sweep reported "25 high/critical across 6 repos" (all under 48h old,
# fixes already open) while the genuinely actionable item — a CLEAN, mergeable
# security PR that had been sitting in the repo — was invisible to every surface
# that looked. The signal worth ranking is remediation state, not exposure size.
#
# `enabled` is THREE-STATE on purpose. A 403 from the alerts endpoint means
# either "the feature is off" or "this token cannot see it", and those demand
# opposite responses from a human — turn it on, versus fix your scope.
# Collapsing both to `false` would confidently tell you to enable something that
# is already enabled. Unknown stays null and must be reported as unknown.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: a repo with alerts disabled, or
# an unreadable PR list, must still emit a valid JSON object rather than voiding
# the caller's whole scan.
set -uo pipefail

PR_LIMIT="${PR_LIMIT:-20}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[[ -z "$REPO" ]] && { echo 'skipped: could not determine REPO (set REPO=owner/name)' >&2; exit 10; }

empty='{"enabled":null,"open":null,"high_crit":null,"oldest_high_crit_age_days":null,
        "vulnerable_packages":[],"open_fix_prs":[],"unremediated_packages":[],"parked_green":[]}'

if ! alerts=$(gh api "repos/${REPO}/dependabot/alerts?state=open&per_page=100" 2>&1); then
  if grep -q 'are disabled for this repository' <<<"$alerts"; then
    jq -nc '{enabled:false, open:null, high_crit:null, oldest_high_crit_age_days:null,
             vulnerable_packages:[], open_fix_prs:[], unremediated_packages:[], parked_green:[]}'
  else
    # Could not read: token scope, not a verdict. Stay null.
    jq -nc "$empty"
  fi
  exit 0
fi

jq -e 'type == "array"' >/dev/null 2>&1 <<<"$alerts" || { jq -nc "$empty"; exit 0; }

base=$(jq -c '
  ([ .[] | select(.security_advisory.severity == "critical"
               or .security_advisory.severity == "high") ]) as $hc
  | {
      enabled: true,
      open: length,
      high_crit: ($hc | length),
      oldest_high_crit_age_days:
        (if ($hc | length) == 0 then null
         else ($hc | map((now - (.created_at | fromdateiso8601)) / 86400 | floor) | max) end),
      vulnerable_packages: ($hc | map(.dependency.package.name) | unique),
      open_fix_prs: [], unremediated_packages: [], parked_green: []
    }' <<<"$alerts")

# Only pay for PR state where exposure exists. A clean repo costs one call total.
if [[ "$(jq -r '.high_crit' <<<"$base")" -gt 0 ]]; then
  prs=$(gh pr list --repo "$REPO" --state open --author 'app/dependabot' \
    --json number,title,mergeStateStatus,createdAt,headRefName --limit "$PR_LIMIT" 2>/dev/null) || prs='[]'
  [[ -z "$prs" ]] && prs='[]'

  base=$(jq -c --argjson prs "$prs" '
    .vulnerable_packages as $vuln
    # MATCH PER PACKAGE, NOT PER REPO. "This repo has an open Dependabot PR" does
    # NOT mean "this alert is being fixed" — a repo can have a green actions-group
    # PR open while its drizzle-orm advisory has no PR at all. Counting any PR as
    # remediation marks genuinely-stuck repos healthy, which is worse than silence.
    #
    # Dependabot encodes the package in the head ref
    # (dependabot/npm_and_yarn/apps/web/next-16.2.11) — more reliable than the
    # title. Scoped names appear unscoped there (@types/node -> types/node), so
    # drop a leading "@" before matching.
    | .open_fix_prs = ( $prs
        | map({
            number, title,
            state: .mergeStateStatus,
            age_days: ((now - (.createdAt | fromdateiso8601)) / 86400 | floor),
            addresses: [ $vuln[] as $p
                         | select(.headRefName | ascii_downcase
                                  | contains($p | ltrimstr("@") | ascii_downcase))
                         | $p ]
          })
        | map(select(.addresses | length > 0)) )
    | .unremediated_packages = ( $vuln - ( .open_fix_prs | map(.addresses[]) | unique ) )
    # CLEAN == green and mergeable. Broken out because it is the one state that is
    # both maximally urgent and trivially closable: the fix exists, it passes, and
    # a human just has to press the button.
    | .parked_green = ( .open_fix_prs
        | map(select(.state == "CLEAN") | {number, age_days}) )
  ' <<<"$base")
fi

jq -c '.' <<<"$base"
