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
#                  "default_branch_ci",       # newest CONCLUDED push-class run on default branch
#                  "default_branch_ci_age_days",  # its age; NOT bounded by RUN_LIMIT
#                  "default_branch_ci_url",
#                  "default_branch_runs_seen",    # 0 | >0 | null — see below
#                  "scheduled_failing": [ { "workflow", "url", "created_at" } ],
#                  "last_failure": { "workflow", "branch", "event", "url", "created_at" } | null,
#                  "dependabot": { "enabled": true|false|null, "open", "high_crit",
#                                  "oldest_high_crit_age_days",
#                                  "open_fix_prs": [ { "number", "title", "state", "age_days" } ] },
#                  # NOTE: a deliberately REDUCED projection of what
#                  # pull-code-scanning.sh and pull-secret-scanning.sh emit.
#                  # The org sweep routes to a repo; it does not triage
#                  # inside one. Dropped from code_scanning: per-alert
#                  # numbers, inherited.by_severity, new[].autofix, tools,
#                  # default_branch (autofix carries a P0 rule in
#                  # repo-health/SKILL.md; the org scoring table
#                  # deliberately has no autofix->P0 rule, since routing
#                  # a repo needs no readiness verdict on its fix).
#                  # Dropped from secret_scanning: oldest_age_days,
#                  # inactive. Do not assume field parity with either
#                  # per-repo script.
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
# alerts (its fix PRs), plus ONE extra per repo whose unfiltered sample yields no
# `default_branch_ci` VERDICT (a strict superset of "held no such run" — an
# all-in-flight sample triggers the recovery too). The code- and secret-scanning
# pulls each read a single page capped at 100 alerts — there is no pagination
# loop, ever. code_scanning reports `truncated: true` when the cap was hit,
# marking `open` as a floor rather than a count; secret_scanning carries no such
# field and simply reflects whatever sits in the first 100. The two conditionals
# are priced differently and only one is free for a healthy org: the Dependabot
# call needs an actual high/critical alert, while the CI recovery fires for a
# perfectly healthy repo that is merely QUIET — five of the fifteen repos in
# issue #367's table were exactly that. Keep RUN_LIMIT small — this is a triage
# sweep, not a security analytics pass.
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
# `default_branch_ci` IS RECOVERED, never left to whatever the unfiltered sample
# happened to contain. One page of the newest runs across ALL branches is the
# wrong instrument for a per-branch, per-event question: measured against the
# live org on 2026-09-06, five repos returned null with a perfectly good verdict
# available — velovate, brewslate, tailoredtip, what2wear and td3000, tabulated
# in issue #367. Raising RUN_LIMIT does not fix it: velovate had ZERO
# push-on-main runs in its newest 100, its most recent sitting weeks back behind
# a wall of `schedule` and `pull_request` runs, so no page size reaches it.
#
# ALL THREE narrowing filters on the recovery are load-bearing, and each looks
# droppable for a different reason. `--event` is the one that does the work:
# `--branch` alone leaves the crowding intact, because what crowds a default
# branch is `schedule` runs, which a branch filter keeps. `--status completed`
# is the one a reader assumes the derivation already handles: the SAMPLE fetches
# RUN_LIMIT rows so the derivation can walk past in-flight runs to the newest
# concluded one, while this query fetches exactly ONE row and has nothing to
# walk past — without it a single in-flight run re-creates the very null this
# recovery exists to remove. `push` alone and never `merge_group`, whose head
# branch `gh-readonly-queue/<branch>/pr-<N>` can never satisfy `--branch`.
# sassydog-routines#46 shipped this with branch and status only and recovered
# one repo of the two sampled; #47 added the event filter (issue #367).
#
# THE RECOVERED VERDICT IS NOT BOUNDED BY RUN_LIMIT, so it ships its own age.
# The recovery reaches back as far as the branch's newest concluded push, which
# in #367's own table was 2026-08-09 for two of the five repos it recovered,
# measured on 2026-09-06. A month-old green rendered as "current" is a FALSE
# GREEN — quieter than the missing verdict it replaced — and a seven-week-old
# red rendered as P0 is a false alarm. `default_branch_ci_age_days` and
# `default_branch_ci_url` therefore travel with the verdict, and `scoring.md`
# bounds both directions at 14 days. Note that `last_failure` is derived from
# the SAMPLE, so a recovered failure has no `last_failure` beside it — the url
# here is the only link to it.
#
# `default_branch_runs_seen` IS THREE-STATE, for the same reason
# `dependabot.enabled` is: `0` is the positive claim "no such run exists" and
# may only come from a recovery that was actually READ. A call that failed,
# returned nothing, or came back in a shape the derivation cannot reduce is
# unknown — null — and never 0. The sample counting zero is not evidence
# either; that is the entire bug this recovery fixes, so a zero from the sample
# contributes nothing and the recovery answers alone. A non-zero count with a
# null verdict means every such run is still in flight. The count itself is
# bounded by whichever query answered (RUN_LIMIT, or 1), so only its
# zero/non-zero/unknown split is sound — never read it as a total.
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

# THE ONE DEFINITION of the default-branch CI verdict, applied to BOTH the
# unfiltered sample and the recovery query below. It is hoisted out of the
# assembly jq so the rule cannot come to mean two different things depending on
# which query answered. Emits {ci, runs_seen}.
#
# CI state on the default branch means PUSH-class runs only. A failing
# `schedule` run on main is an ops-job failure, not a broken build — it blocks
# no merges at all. Conflating them reports "main is red" for a nightly sweep
# that hiccuped, which is confident nonsense. Same trap
# repo-health/scripts/pull-ci-health.sh keys on `event` to avoid.
#
# `runs_seen` counts push-class default-branch runs REGARDLESS of status, and a
# null verdict is only readable next to it — see the three-state note in the
# header. `age_days` and `url` are projected from the SAME run the verdict came
# from, because a verdict whose age is not carried alongside it gets rendered as
# current by every consumer.
derive_default_branch_ci() {  # arg 1: runs JSON   arg 2: default branch
  jq -c --arg branch "$2" '
    map(select(.headBranch == $branch
               and (.event == "push" or .event == "merge_group"))) as $dbr
    | ( $dbr | map(select(.status == "completed")) | first ) as $v
    | { ci: ($v.conclusion // null),
        age_days: (if ($v.createdAt // null) == null then null
                   else ((now - ($v.createdAt | fromdateiso8601)) / 86400 | floor) end),
        url: ($v.url // null),
        runs_seen: ($dbr | length) }' <<<"$1"
}

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

  db_ci=$(derive_default_branch_ci "$runs" "$default_branch")

  # RECOVERY — see header for why each of the three narrowing filters is
  # load-bearing. Fires ONLY when the unfiltered sample yielded no VERDICT, and
  # it runs the SAME derivation above rather than a second copy of the rule.
  #
  # The query inherits the branch provenance the sample derivation already had —
  # a guessed `default_branch` narrows this query exactly as wrongly as it
  # filtered the sample, so this adds no exposure the verdict did not carry.
  if [[ "$(jq -r '.ci' <<<"$db_ci")" == "null" ]]; then
    # The unknown default. Every path that does not READ an answer leaves it
    # here — a failed call, an empty body, a non-array shape. `0` is a claim and
    # is only ever assigned below, from a recovery that came back empty.
    rec='{"ci":null,"age_days":null,"url":null,"runs_seen":null}'
    if recovery=$(gh run list --repo "${ORG}/${repo}" --branch "$default_branch" \
        --event push --status completed --limit 1 \
        --json conclusion,status,workflowName,headBranch,url,createdAt,event 2>/dev/null) \
       && [[ -n "$recovery" ]] \
       && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$recovery"; then
      if [[ "$(jq 'length' <<<"$recovery")" -eq 0 ]]; then
        # READ, and it says there is no concluded push-class run on this branch.
        rec='{"ci":null,"age_days":null,"url":null,"runs_seen":0}'
      else
        rec=$(derive_default_branch_ci "$recovery" "$default_branch")
        if [[ "$(jq -r '.runs_seen' <<<"$rec")" == "0" ]]; then
          # Rows came back that the derivation drops. The query asserts such
          # runs exist and we cannot reduce them, which is unknown — never the
          # positive claim that none exist.
          rec='{"ci":null,"age_days":null,"url":null,"runs_seen":null}'
        fi
      fi
    fi
    db_ci=$(jq -c -n --argjson s "$db_ci" --argjson r "$rec" '
      # The verdict, its age and its link travel together, from whichever probe
      # HAS one — only the recovery can, since this branch runs only when the
      # sample had none.
      ( if $r.ci != null then $r else $s end ) as $v
      | { ci: $v.ci, age_days: $v.age_days, url: $v.url,
          # A sample count of ZERO is not evidence that none exist — that is the
          # bug this recovery fixes — so it contributes nothing and the recovery
          # answers alone, unknown included. A sample that DID see runs still
          # bounds the count from below, so a one-row recovery cannot shrink it
          # and an unreadable one cannot erase it.
          runs_seen: (if $s.runs_seen > 0
                      then ([$s.runs_seen, ($r.runs_seen // 0)] | max)
                      else $r.runs_seen end) }')
  fi

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
    : # enabled:null here is NOT the usual token-scope signal — the roster
      # lookup for this repo's default branch failed, so the ref filter
      # above has nothing safe to compare against. secret_scanning carries
      # no ref and is unaffected, so the same repo/token can legitimately
      # show code_scanning unknown while secret_scanning resolves fine.
      # code_scanning keeps the null-state default assigned above.
  elif cs=$(gh api "repos/${ORG}/${repo}/code-scanning/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cs"; then
      code_scanning=$(jq -c --arg ref "refs/heads/${default_branch}" '
        . as $raw
        | ( map(select(.most_recent_instance.ref == $ref))
          | map({rule: .rule.id,
                 severity: (.rule.security_severity_level // "none"),
                 age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
        | ($a | map(select(.age_days > 14))) as $old
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
            inherited: { count: ($old | length),
                         rules: ($old | map(.rule) | unique | length),
                         oldest_age_days: (if ($old | length) == 0 then null
                                           else ($old | map(.age_days) | max) end) } }' <<<"$cs")
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
            active: ($a | map(select(.validity == "active"))
                        | map({number, type, age_days, bypassed}) | sort_by(-.age_days)),
            unknown_validity: ($a | map(select(.validity == "unknown"))
                                  | map({number, type, age_days, bypassed}) | sort_by(-.age_days)) }' <<<"$ss")
    fi
  elif grep -qi 'secret scanning is disabled\|is disabled on this repository' <<<"$ss"; then
    secret_scanning='{"enabled":false,"open":null,"active":[],"unknown_validity":[]}'
  fi

  results=$(jq -c \
    --arg repo "$repo" \
    --arg branch "$default_branch" \
    --argjson runs "$runs" \
    --argjson db_ci "$db_ci" \
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
          # All four come from derive_default_branch_ci() above — the one place
          # the push-class rule is written — recovered by a narrow re-query when
          # the unfiltered sample yielded no verdict.
          default_branch_ci: $db_ci.ci,
          # The age and the link are NOT optional decoration. The recovery is
          # unbounded by RUN_LIMIT, so the verdict can be weeks old; without the
          # age a consumer renders a month-old green as "clean today" and a
          # seven-week-old red as P0. `last_failure` below is derived from the
          # SAMPLE, so a recovered failure has none — this url is its only link.
          default_branch_ci_age_days: $db_ci.age_days,
          default_branch_ci_url: $db_ci.url,
          # THREE-STATE, like `dependabot.enabled`: 0 is the positive claim that
          # no such run exists and comes only from a recovery that was read;
          # non-zero with a null verdict means they are all in flight; null
          # means the recovery could not be read. Bounded by whichever query
          # answered, so read the split, never the total.
          default_branch_runs_seen: $db_ci.runs_seen,
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
