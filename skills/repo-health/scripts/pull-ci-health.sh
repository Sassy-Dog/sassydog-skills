#!/usr/bin/env bash
# pull-ci-health.sh — surface CI duration + flake signal for a workflow.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   WORKFLOW   workflow file name (default: ci.yml)
#   LIMIT      run sample size (default: 50)
#
# Output shape:
#   { "sample": N, "median_min": X.X, "p90_min": X.X,
#     "flake_runs": N, "flake_shas": [ "...", ... ] }
#
# median_min / p90_min are computed over COMPLETED runs (any conclusion) using
# wall-clock updatedAt-startedAt. flake = a head SHA that produced both a
# failure and a success *within the same event context* without the SHA
# changing (a re-run that went green), counted over recent PR + push runs.
#
# The "same event context" qualifier matters under a merge queue: every merged
# commit legitimately produces TWO runs on one SHA — a `merge_group` run (gates
# the merge) and a later `push`-on-main run (deploys + post-deploy smoke). Those
# run DIFFERENT jobs, so a deterministic failure in a push-only job (deploy /
# migrate / smoke-production) would otherwise look identical to a real flake.
# Keying flake detection on (headSha, event) excludes that false positive — a
# genuine flake is the same job, same context, failing then passing.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: we want to emit a valid JSON
# object (null durations, empty flake list) even when the run sample is empty
# or a sub-step yields nothing. Don't "fix" this to `-eo` — it breaks the
# zero-sample path.
set -uo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[[ -z "$REPO" ]] && { echo 'skipped: not in a GitHub repo and REPO not set' >&2; exit 10; }
WORKFLOW="${WORKFLOW:-ci.yml}"
LIMIT="${LIMIT:-50}"

runs=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit "$LIMIT" \
  --json conclusion,status,createdAt,startedAt,updatedAt,headSha,event 2>/dev/null) || {
    echo 'skipped: gh run list failed (check workflow name + PAT scope: needs actions:read)' >&2
    exit 10
  }

echo "$runs" | jq '
  # Duration over completed runs with a real start + end timestamp.
  ( [ .[]
      | select(.status == "completed" and .startedAt != null and .updatedAt != null)
      | ((.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)) / 60
      | select(. >= 0) ]
    | sort ) as $durs
  | ($durs | length) as $n
  # Flake: same (headSha, event) seen as both a failure and a success. Keying on
  # the event context too prevents the merge_group-pass / push-fail split (same
  # SHA, different jobs) from being miscounted as a flake — see header note.
  | ( [ .[] | select(.conclusion == "failure") | "\(.headSha)\t\(.event)" ] | unique ) as $failedKeys
  | ( [ .[] | select(.conclusion == "success") | "\(.headSha)\t\(.event)" ] | unique ) as $passedKeys
  | ( $failedKeys - ($failedKeys - $passedKeys) ) as $flakyKeys
  | ( [ $flakyKeys[] | split("\t")[0] ] | unique ) as $flaky
  | {
      sample: $n,
      median_min: ( if $n == 0 then null
                    else (($durs[ (($n-1)/2) | floor ]) * 10 | round / 10) end ),
      p90_min:    ( if $n == 0 then null
                    else (($durs[ (($n-1) * 0.9) | floor ]) * 10 | round / 10) end ),
      flake_runs: ($flaky | length),
      flake_shas: $flaky
    }'
