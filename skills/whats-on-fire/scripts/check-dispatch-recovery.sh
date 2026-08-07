#!/usr/bin/env bash
# check-dispatch-recovery.sh — has a workflow had a green `workflow_dispatch`
# run completed strictly AFTER a reference instant? Read-only. Emits a single
# JSON object on stdout.
#
# The org-wide port of Sassy-Dog/platform's jobs/src/monitors/recovery.ts
# (platform#610): the dispatch cross-reference that tells "verified fixed,
# awaiting the next scheduled check-in" apart from "still broken". This script
# answers exactly one evidence question; the DECISION rules — only `error`
# qualifies, how to pick SINCE, owning-repo resolution, when a miss is
# "not applicable" versus "unavailable" — live in
# ../references/cron-recovery.md and stay with the caller.
#
# Env:
#   ORG            GitHub org (default: Sassy-Dog)
#   REPO           repo name within ORG (required) — the monitor's OWNING repo,
#                  resolved via the product<->repo map, never assumed platform
#   WORKFLOW_FILE  derived workflow file, e.g. relay-drift-check.yml (required)
#   SINCE          ISO-8601 reference instant (required): the environment's most
#                  recent failing check-in, or the incident start only when no
#                  check-in exists. A run qualifies only if it completed
#                  STRICTLY AFTER this — comparing against the incident start
#                  when a later check-in exists once called a control "fixed"
#                  that a newer scheduled run had proven still broken.
#
# Output (exit 0):
#   { "org", "repo", "workflow", "since",
#     "outcome": "checked",              # the lookup ran; evidence follows
#     "runs_sampled": N,
#     "qualifying_run":                  # newest green dispatch after SINCE
#       { "url", "completed_at" } | null }
#   { ..., "outcome": "not_applicable" } # HTTP 404 — no such workflow in this
#                                        # repo. A DEFINITIVE answer from a
#                                        # successful request: outside platform
#                                        # the cron-<basename> convention is a
#                                        # hypothesis and a miss must stay cheap
#                                        # and silent. No downgrade, NO footer.
#
# Exit 10 + `skipped: <reason>` on stderr — the ABSENCE of an answer (401/403,
# network, 5xx, unparseable body). The caller keeps the monitor at full
# severity AND adds this repo to the report's cross-reference footer: a reader
# must be able to tell "nothing was fixed" from "we could not check whether
# anything was fixed". A failed lookup must never quietly downgrade a P0 —
# failing closed leaves things louder, never quieter.
#
# Exit 2 — usage error (missing/unparseable inputs). A caller bug, not absence
# of evidence: it must not put a repo in the footer.
set -uo pipefail

ORG="${ORG:-Sassy-Dog}"
REPO="${REPO:-}"
WORKFLOW_FILE="${WORKFLOW_FILE:-}"
SINCE="${SINCE:-}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

[[ -z "$REPO" ]] && { echo 'usage: REPO is required (repo name within ORG)' >&2; exit 2; }
[[ -z "$WORKFLOW_FILE" ]] && { echo 'usage: WORKFLOW_FILE is required (e.g. relay-drift-check.yml)' >&2; exit 2; }
[[ -z "$SINCE" ]] && { echo 'usage: SINCE is required (ISO-8601 reference instant)' >&2; exit 2; }

# Normalize fractional seconds and +00:00 offsets (Sentry emits both) before
# fromdateiso8601, which only reads the bare Zulu form.
since_epoch=$(jq -rn --arg s "$SINCE" \
  '$s | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch empty')
[[ -z "$since_epoch" ]] && { echo "usage: SINCE is not a parseable ISO-8601 instant: ${SINCE}" >&2; exit 2; }

gh auth status >/dev/null 2>&1 || { echo 'skipped: gh not authenticated (run: gh auth login)' >&2; exit 10; }

# per_page=10 is ample: the decision only ever wants the newest success after
# the reference instant, and GitHub returns runs newest-first.
resp=$(gh api "repos/${ORG}/${REPO}/actions/workflows/${WORKFLOW_FILE}/runs?event=workflow_dispatch&status=completed&per_page=10" 2>&1)
rc=$?

if [[ $rc -ne 0 ]]; then
  if grep -q 'HTTP 404' <<<"$resp"; then
    # The one failure that IS an answer: the request succeeded and the workflow
    # does not exist in this repo. Not applicable — never a footer entry.
    jq -n --arg org "$ORG" --arg repo "$REPO" --arg wf "$WORKFLOW_FILE" --arg since "$SINCE" \
      '{ org: $org, repo: $repo, workflow: $wf, since: $since, outcome: "not_applicable" }'
    exit 0
  elif grep -qE 'HTTP 40[13]' <<<"$resp"; then
    echo "skipped: no actions:read on ${ORG}/${REPO} (HTTP 401/403) — report its monitors at full severity and name it in the cross-reference footer" >&2
    exit 10
  else
    echo "skipped: dispatch lookup failed for ${ORG}/${REPO} (${WORKFLOW_FILE}) — report its monitors at full severity and name it in the cross-reference footer" >&2
    exit 10
  fi
fi

jq -e '.workflow_runs | type == "array"' >/dev/null 2>&1 <<<"$resp" || {
  echo "skipped: response for ${ORG}/${REPO} (${WORKFLOW_FILE}) is not a runs envelope — report its monitors at full severity and name it in the cross-reference footer" >&2
  exit 10
}

# An empty or all-disqualified list yields qualifying_run: null with exit 0 —
# that is EVIDENCE (nobody verified a fix), distinct from the exit-10 absence
# of evidence above. Runs missing the fields the decision reads are dropped;
# the comparison is strictly-after, matching recovery.ts (`at <= reference`
# never qualifies).
jq -c --arg org "$ORG" --arg repo "$REPO" --arg wf "$WORKFLOW_FILE" --arg since "$SINCE" \
  --argjson since_epoch "$since_epoch" '
  def ts: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch null;
  .workflow_runs as $all
  | ( $all
      | map(select(.conclusion == "success"))
      | map({ url: (.html_url // null),
              completed_at: (.updated_at // null),
              at: ((.updated_at // "") | ts) })
      | map(select(.url != null and .at != null and .at > $since_epoch))
      | sort_by(.at) | last ) as $best
  | { org: $org, repo: $repo, workflow: $wf, since: $since,
      outcome: "checked",
      runs_sampled: ($all | length),
      qualifying_run: (if $best == null then null
                       else { url: $best.url, completed_at: $best.completed_at } end) }
' <<<"$resp"
