#!/usr/bin/env bash
# pull-repo-signals.sh — per-repo failure signals across an org: workflow health
# and Dependabot exposure. Read-only. Emits a single JSON object on stdout.
#
# Env:
#   ORG        GitHub org (default: Sassy-Dog)
#   REPOS      space-separated repo names (default: every non-archived repo in ORG)
#   RUN_LIMIT  workflow runs sampled per repo (default: 25)
#
# Output shape:
#   { "org": "...", "run_limit": N,
#     "repos": [ { "repo",
#                  "default_branch",
#                  "runs_sampled", "failures", "failure_rate",
#                  "default_branch_ci",       # latest push/merge_group run on default branch
#                  "scheduled_failing": [ { "workflow", "url", "created_at" } ],
#                  "last_failure": { "workflow", "branch", "event", "url", "created_at" } | null,
#                  "dependabot": { "enabled": true|false|null, "open", "high_crit",
#                                  "oldest_high_crit_age_days",
#                                  "open_fix_prs": [ { "number", "title", "state", "age_days" } ] },
#                  # NOTE: a deliberately REDUCED projection of what
#                  # pull-code-scanning.sh and pull-secret-scanning.sh emit.
#                  # The org sweep routes to a repo; it does not triage
#                  # inside one. Dropped from code_scanning: per-alert
#                  # numbers, inherited.by_severity. Dropped from
#                  # secret_scanning: oldest_age_days, inactive. Do not
#                  # assume field parity with either per-repo script.
#                  "code_scanning": { "enabled": true|false|null,
#                                     "analyzed": true|false|null, "truncated",
#                                     "open",
#                                     "new": [ { "rule", "severity", "count",
#                                                "oldest_age_days" } ],
#                                     "inherited": { "count", "rules",
#                                                    "oldest_age_days" } },
#                  "secret_scanning": { "enabled": true|false|null, "open",
#                                       "active": [...], "unknown_validity": [...] } } ] }
#
# Cost is 1 + 4N calls, plus ONE extra per repo with high/critical Dependabot
# alerts (its fix PRs). The code- and secret-scanning pulls each read a
# single page capped at 100 alerts — there is no pagination loop, ever.
# code_scanning reports `truncated: true` when the cap was hit, marking
# `open` as a floor rather than a count; secret_scanning carries no such
# field and simply reflects whatever sits in the first 100. A healthy org
# pays nothing for the conditional Dependabot call. Keep RUN_LIMIT small —
# this is a triage sweep, not a security analytics pass.
#
# WHY AGE AND FIX-PR STATE ARE PART OF THE CONTRACT: a bare alert count is a
# LAGGING indicator. It only falls when a fix MERGES, so it conflates "we were
# slow" with "the world just changed" — and the consumer cannot tell them apart.
# On 2026-07-25 this script reported 25 high/critical across 6 repos; every alert
# was under 48h old (a published Next.js/drizzle/sharp CVE batch) and the fix PR
# for the worst repo was already open and green. That is a healthy system, and it
# read as a fire. Meanwhile the genuinely broken cases — a green fix PR parked for
# days, or alerts with an available patch and no PR at all — were invisible,
# because both look identical to "some number of alerts". Never re-narrow this
# back to a count.
#
# `dependabot.enabled` is THREE-STATE on purpose. A 403 from the alerts endpoint
# means either "the feature is off" or "this token can't see it", and those demand
# opposite responses from a human — turn it on, versus fix your scope. Collapsing
# both to `false` would have the report confidently tell you to enable something
# that is already enabled. Unknown stays null and is reported as unknown.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: one unreachable repo must not void
# the sweep. Per-repo failures degrade to nulls and the loop continues.
set -uo pipefail

ORG="${ORG:-Sassy-Dog}"
RUN_LIMIT="${RUN_LIMIT:-25}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }
gh auth status >/dev/null 2>&1 || { echo 'skipped: gh not authenticated (run: gh auth login)' >&2; exit 10; }

roster=$(gh repo list "$ORG" --limit 200 --json name,isArchived,defaultBranchRef 2>/dev/null) || {
  echo "skipped: gh repo list failed for org ${ORG} (token needs repo scope)" >&2
  exit 10
}

if [[ -n "${REPOS:-}" ]]; then
  # shellcheck disable=SC2206  # word splitting is the intended parse for a space-separated list
  targets=( ${REPOS} )
else
  mapfile -t targets < <(jq -r '.[] | select(.isArchived | not) | .name' <<<"$roster")
fi

[[ ${#targets[@]} -eq 0 ]] && { echo "skipped: no repos to scan in org ${ORG}" >&2; exit 10; }

results='[]'

for repo in "${targets[@]}"; do
  default_branch=$(jq -r --arg r "$repo" \
    '.[] | select(.name == $r) | .defaultBranchRef.name // "main"' <<<"$roster")
  [[ -z "$default_branch" ]] && default_branch="main"

  # Track provenance: a GUESSED branch cannot support the ref filter below.
  default_branch_resolved=true
  if [ -z "$(jq -r --arg r "$repo" '.[] | select(.name == $r) | .defaultBranchRef.name // empty' <<<"$roster")" ]; then
    default_branch_resolved=false
  fi

  runs=$(gh run list --repo "${ORG}/${repo}" --limit "$RUN_LIMIT" \
    --json conclusion,status,workflowName,headBranch,url,createdAt,event 2>/dev/null) || runs='[]'
  [[ -z "$runs" ]] && runs='[]'

  # Dependabot: distinguish "off" from "invisible to this token" — see header.
  dependabot='{"enabled":null,"open":null,"high_crit":null,"oldest_high_crit_age_days":null,"open_fix_prs":null}'
  if alerts=$(gh api "repos/${ORG}/${repo}/dependabot/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$alerts"; then
      dependabot=$(jq -c '
        ([ .[] | select(.security_advisory.severity == "critical"
                     or .security_advisory.severity == "high") ]) as $hc
        | {
        enabled: true,
        open: length,
        high_crit: ($hc | length),
        # AGE IS THE POINT. A raw count cannot tell "a CVE batch published this
        # morning, fix already queued" from "a year of neglect" — they render
        # identically, and the first one reads as a fire it is not. Measured from
        # the OLDEST high/crit, so it is the true exposure window.
        oldest_high_crit_age_days:
          (if ($hc | length) == 0 then null
           else ($hc | map((now - (.created_at | fromdateiso8601)) / 86400 | floor) | max)
           end),
        # The packages actually under advisory. Remediation is judged PER PACKAGE
        # against this list — see the matching note below.
        vulnerable_packages: ($hc | map(.dependency.package.name) | unique),
        open_fix_prs: null,
        unremediated_packages: null
      }' <<<"$alerts")

      # Remediation state, but only where it can matter: a repo with no high/crit
      # alerts needs no fix PR, so it costs nothing. This keeps the sweep O(1) in
      # a healthy org and O(repos-with-exposure) in a bad one — never O(all).
      if [[ "$(jq -r '.high_crit' <<<"$dependabot")" -gt 0 ]]; then
        fix_prs=$(gh pr list --repo "${ORG}/${repo}" --state open --author 'app/dependabot' \
          --json number,title,mergeStateStatus,createdAt,headRefName --limit 20 2>/dev/null) || fix_prs='[]'
        [[ -z "$fix_prs" ]] && fix_prs='[]'
        dependabot=$(jq -c --argjson prs "$fix_prs" '
          .vulnerable_packages as $vuln
          # MATCH PER PACKAGE, NOT PER REPO. "This repo has an open Dependabot PR"
          # does NOT mean "this alert is being fixed" — brewslate and what2wear
          # both had a CLEAN actions-group PR open while their drizzle-orm
          # advisory had no PR at all. Counting any PR as remediation would have
          # marked the two genuinely-stuck repos as healthy.
          #
          # Dependabot encodes the package in the head ref
          # (dependabot/npm_and_yarn/apps/web/next-16.2.11), which is more
          # reliable than the title. Scoped names appear unscoped there
          # (@types/node -> types/node), so drop a leading "@" before matching.
          | .open_fix_prs = ( $prs
              | map({
                  number, title,
                  # CLEAN == green and mergeable. A CLEAN PR sitting for days is
                  # the worst state in this report: the fix exists, it works, and
                  # nobody is merging it. That is a process failure, not a CVE.
                  state: .mergeStateStatus,
                  age_days: ((now - (.createdAt | fromdateiso8601)) / 86400 | floor),
                  addresses: [ $vuln[] as $p
                               | select(.headRefName | ascii_downcase
                                        | contains($p | ltrimstr("@") | ascii_downcase))
                               | $p ]
                })
              | map(select(.addresses | length > 0)) )
          | .unremediated_packages =
              ( $vuln - ( .open_fix_prs | map(.addresses[]) | unique ) )
        ' <<<"$dependabot")
      fi
    fi
  elif grep -q 'are disabled for this repository' <<<"$alerts"; then
    dependabot='{"enabled":false,"open":null,"high_crit":null,"oldest_high_crit_age_days":null,"open_fix_prs":null}'
  fi

  # Code scanning. The 404 is ambiguous by design — see pull-code-scanning.sh.
  code_scanning='{"enabled":null,"analyzed":null,"truncated":false,"open":null,"new":[],"inherited":null}'
  if [ "$default_branch_resolved" != "true" ]; then
    : # Unknown branch means an unusable ref filter. Unknown is not clean;
      # code_scanning keeps the null-state default assigned above.
  elif cs=$(gh api "repos/${ORG}/${repo}/code-scanning/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cs"; then
      code_scanning=$(jq -c --arg ref "refs/heads/${default_branch}" '
        . as $raw
        | ( map(select(.most_recent_instance.ref == $ref))
          | map({rule: .rule.id,
                 severity: (.rule.security_severity_level // "none"),
                 age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
        | {critical: 4, high: 3, medium: 2, low: 1, none: 0} as $rank
        | { enabled: true, analyzed: true,
            # Measured on the RAW page, not $a (ref-filtered): a repo can
            # have 100 raw alerts with only 40 on the default branch, and
            # the 60 unseen ones (hidden by the page cap) may include more
            # default-branch alerts. A truncated computed from $a would
            # read false and assert completeness it does not have — worse
            # than no truncated flag at all.
            truncated: (($raw | length) >= 100),
            open: ($a | length),
            new: ( $a | map(select(.age_days <= 14)) | group_by(.rule)
                   | map({rule: .[0].rule,
                          severity: (max_by($rank[.severity]) | .severity),
                          count: length,
                          oldest_age_days: (map(.age_days) | max)}) ),
            inherited: { count: ($a | map(select(.age_days > 14)) | length),
                         rules: ($a | map(select(.age_days > 14)) | map(.rule) | unique | length),
                         oldest_age_days: (if ($a | length) == 0 then null
                                           else ($a | map(.age_days) | max) end) } }' <<<"$cs")
    fi
  elif grep -qi 'advanced security must be enabled\|code scanning is not enabled' <<<"$cs"; then
    code_scanning='{"enabled":false,"analyzed":false,"truncated":false,"open":null,"new":[],"inherited":null}'
  elif grep -qi 'no analysis found' <<<"$cs"; then
    code_scanning='{"enabled":true,"analyzed":false,"truncated":false,"open":null,"new":[],"inherited":null}'
  fi

  # Secret scanning. validity is the split; age never outranks a live credential.
  secret_scanning='{"enabled":null,"open":null,"active":[],"unknown_validity":[]}'
  if ss=$(gh api "repos/${ORG}/${repo}/secret-scanning/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$ss"; then
      secret_scanning=$(jq -c '
        ( map({number,
               type: .secret_type_display_name,
               validity: (.validity // "unknown"),
               bypassed: (.push_protection_bypassed // false),
               age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
        | { enabled: true, open: ($a | length),
            active: ($a | map(select(.validity == "active")) | map({number, type, age_days, bypassed})),
            unknown_validity: ($a | map(select(.validity == "unknown"))
                                  | map({number, type, age_days, bypassed})) }' <<<"$ss")
    fi
  elif grep -qi 'secret scanning is disabled\|is disabled on this repository' <<<"$ss"; then
    secret_scanning='{"enabled":false,"open":null,"active":[],"unknown_validity":[]}'
  fi

  results=$(jq -c \
    --arg repo "$repo" \
    --arg branch "$default_branch" \
    --argjson runs "$runs" \
    --argjson dependabot "$dependabot" \
    --argjson code_scanning "$code_scanning" \
    --argjson secret_scanning "$secret_scanning" '
    . + [ (
      ($runs | map(select(.status == "completed"))) as $done
      | ($done | length) as $n
      | ($done | map(select(.conclusion == "failure"))) as $failed
      | {
          repo: $repo,
          default_branch: $branch,
          runs_sampled: $n,
          failures: ($failed | length),
          failure_rate: (if $n == 0 then null
                         else (($failed | length) / $n * 100 | round) end),
          # CI state on the default branch means PUSH-class runs only. A failing
          # `schedule` run on main is an ops-job failure, not a broken build — it
          # blocks no merges at all. Conflating them reports "main is red" for a
          # nightly sweep that hiccuped, which is confident nonsense. Same trap
          # repo-health/scripts/pull-ci-health.sh keys on `event` to avoid.
          default_branch_ci:
            ( $done
              | map(select(.headBranch == $branch
                           and (.event == "push" or .event == "merge_group")))
              | first | .conclusion // null ),
          # Per scheduled workflow, is its MOST RECENT run failing? A stale failure
          # already followed by a green run is not an active fire.
          scheduled_failing:
            ( $done
              | map(select(.event == "schedule"))
              | group_by(.workflowName)
              | map(first)
              | map(select(.conclusion == "failure"))
              | map({ workflow: .workflowName, url: .url, created_at: .createdAt }) ),
          last_failure:
            ( $failed | first
              | if . == null then null
                else { workflow: .workflowName, branch: .headBranch, event: .event,
                       url: .url, created_at: .createdAt } end ),
          dependabot: $dependabot,
          code_scanning: $code_scanning,
          secret_scanning: $secret_scanning
        }
    ) ]' <<<"$results")
done

jq -n --arg org "$ORG" --argjson limit "$RUN_LIMIT" --argjson repos "$results" \
  '{ org: $org, run_limit: $limit, repos: ($repos | sort_by(-(.failures // 0))) }'
