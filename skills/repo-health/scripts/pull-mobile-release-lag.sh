#!/usr/bin/env bash
# pull-mobile-release-lag.sh — surface "TestFlight is behind main".
#
# Finds the most recent release-workflow run whose iOS leg succeeded, then
# counts how many mobile-path commits have landed on the default branch since —
# and reports whether the latest release run's iOS leg is currently stuck.
# Catches ANY cause (EAS build failure, ASC train trap, signing, cancelled
# queue) regardless of the failure mechanism.
#
# Env:
#   REPO                owner/name (default: inferred from cwd via gh)
#   WORKFLOW            release workflow file (default: mobile-release.yml)
#   MOBILE_PATH_PREFIX  path that counts as "mobile commits" (default: apps/mobile/)
#   IOS_JOB_PATTERN     job-name regex for the iOS leg (default: iOS)
#   DEFAULT_BRANCH      branch to count commits on (default: main)
#   SCAN                recent release runs to scan for a green iOS leg (default: 25)
#
# Read-only. Emits a single JSON object on stdout.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: most `gh`/`git` sub-steps are
# allowed to come back empty (no green iOS build in range, no release runs yet)
# and we still want to emit a valid JSON object. Don't "fix" this to `-eo`.
set -uo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
[[ -z "$REPO" ]] && { echo 'skipped: not in a GitHub repo and REPO not set' >&2; exit 10; }
WORKFLOW="${WORKFLOW:-mobile-release.yml}"
MOBILE_PATH_PREFIX="${MOBILE_PATH_PREFIX:-apps/mobile/}"
IOS_JOB_PATTERN="${IOS_JOB_PATTERN:-iOS}"
BRANCH="${DEFAULT_BRANCH:-main}"
SCAN="${SCAN:-25}"

git fetch origin "$BRANCH" -q 2>/dev/null || true

# Walk recent release runs newest→oldest; stop at the first with a green iOS leg.
last_success_at=""; last_success_run=""; last_success_sha=""
mapfile -t rows < <(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit "$SCAN" \
  --json databaseId,createdAt,headSha -q '.[] | "\(.databaseId)\t\(.createdAt)\t\(.headSha)"' 2>/dev/null)

for row in "${rows[@]}"; do
  rid="${row%%$'\t'*}"; rest="${row#*$'\t'}"
  created="${rest%%$'\t'*}"; sha="${rest#*$'\t'}"
  concl=$(gh run view "$rid" --repo "$REPO" --json jobs \
    -q ".jobs[] | select(.name|test(\"$IOS_JOB_PATTERN\")) | .conclusion" 2>/dev/null | head -1)
  if [[ "$concl" == "success" ]]; then
    last_success_run="$rid"; last_success_at="$created"; last_success_sha="$sha"
    break
  fi
done

# Latest release run's iOS leg status (catches a currently-stuck build).
latest_rid=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 \
  -q '.[0].databaseId' --json databaseId 2>/dev/null)
latest_ios=""
if [[ -n "$latest_rid" ]]; then
  latest_ios=$(gh run view "$latest_rid" --repo "$REPO" --json jobs \
    -q ".jobs[] | select(.name|test(\"$IOS_JOB_PATTERN\")) | \"\(.status)/\(.conclusion // \"running\")\"" 2>/dev/null | head -1)
fi

# Mobile commits on the default branch since the last successful iOS build.
since="${last_success_at:-$(git log -1 --format=%cI "origin/$BRANCH" 2>/dev/null)}"
mobile_commits=$(git log "origin/$BRANCH" --since="$since" --oneline -- "$MOBILE_PATH_PREFIX" 2>/dev/null | wc -l | tr -d ' ')
days_since="null"
if [[ -n "$last_success_at" ]]; then
  epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_success_at%%.*}Z" +%s 2>/dev/null \
          || date -d "$last_success_at" +%s 2>/dev/null || echo 0)
  (( epoch > 0 )) && days_since=$(( ( $(date +%s) - epoch ) / 86400 ))
fi

jq -n \
  --arg lsa "$last_success_at" --arg lsr "$last_success_run" --arg lss "$last_success_sha" \
  --arg ds "$days_since" --arg mc "$mobile_commits" --arg li "$latest_ios" \
  '{
     last_ios_success_at:  ($lsa | select(. != "") // null),
     last_ios_success_run: ($lsr | select(. != "") // null),
     last_ios_success_sha: ($lss | select(. != "") // null),
     days_since_ios_success: ($ds | if . == "null" then null else tonumber end),
     mobile_commits_since: ($mc | tonumber),
     latest_release_ios_leg: ($li | select(. != "") // null)
   }'
