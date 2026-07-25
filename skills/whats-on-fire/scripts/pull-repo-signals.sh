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
#                  "dependabot": { "enabled": true|false|null, "open", "high_crit" } } ] }
#
# Cost is 1 + 2N calls (one roster + run-list and alert-list per repo). That is the
# deliberate trade: the org-level searches in pull-org-github.sh cannot express
# "recent workflow conclusions" or "alert severity", so those two genuinely need a
# loop. Keep RUN_LIMIT small — this is a triage sweep, not a CI analytics pass.
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

  runs=$(gh run list --repo "${ORG}/${repo}" --limit "$RUN_LIMIT" \
    --json conclusion,status,workflowName,headBranch,url,createdAt,event 2>/dev/null) || runs='[]'
  [[ -z "$runs" ]] && runs='[]'

  # Dependabot: distinguish "off" from "invisible to this token" — see header.
  dependabot='{"enabled":null,"open":null,"high_crit":null}'
  if alerts=$(gh api "repos/${ORG}/${repo}/dependabot/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$alerts"; then
      dependabot=$(jq -c '{
        enabled: true,
        open: length,
        high_crit: ([ .[] | select(.security_advisory.severity == "critical"
                                or .security_advisory.severity == "high") ] | length)
      }' <<<"$alerts")
    fi
  elif grep -q 'are disabled for this repository' <<<"$alerts"; then
    dependabot='{"enabled":false,"open":null,"high_crit":null}'
  fi

  results=$(jq -c \
    --arg repo "$repo" \
    --arg branch "$default_branch" \
    --argjson runs "$runs" \
    --argjson dependabot "$dependabot" '
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
          dependabot: $dependabot
        }
    ) ]' <<<"$results")
done

jq -n --arg org "$ORG" --argjson limit "$RUN_LIMIT" --argjson repos "$results" \
  '{ org: $org, run_limit: $limit, repos: ($repos | sort_by(-(.failures // 0))) }'
