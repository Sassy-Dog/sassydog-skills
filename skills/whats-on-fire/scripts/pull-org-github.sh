#!/usr/bin/env bash
# pull-org-github.sh — org-wide GitHub sweep for a portfolio triage pass.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   ORG           GitHub org (default: Sassy-Dog)
#   PR_LIMIT      max open PRs to pull (default: 100)
#   ISSUE_LIMIT   max open issues to pull (default: 200)
#
# Output shape:
#   { "org": "...",
#     "repos":   [ { "name", "archived", "pushed_at", "default_branch" } ],
#     "prs":     [ { "repo", "number", "title", "url", "draft", "author",
#                    "idle_days", "age_days" } ],
#     "issues":  [ { "repo", "number", "title", "url", "labels", "idle_days" } ],
#     "partial": [ "<surface that failed>", ... ] }
#
# THREE org-level API calls total, regardless of repo count — the roster, the PR
# search, and the issue search are each one request. Do not "improve" this into a
# per-repo loop; the whole point of the portfolio sweep is that it stays O(1) in
# repos while the per-repo survey-work skills stay O(deep).
#
# Archived repos are RETAINED in `repos` (flagged) but EXCLUDED from `prs` and
# `issues`. `gh search` happily returns hits from archived repos — at Sassy Dog
# that silently adds 28 dead issues from lupita/lupita-web to a 50-issue portfolio
# and badly skews any ranking. The archived-but-present fact is still a signal,
# so the caller reads it off `repos` and reports it as a blind spot instead.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: a failed PR or issue search must
# degrade to an empty list plus a `partial` entry, not kill the roster we already
# fetched. Partial output beats no output for a triage report.
set -uo pipefail

ORG="${ORG:-Sassy-Dog}"
PR_LIMIT="${PR_LIMIT:-100}"
ISSUE_LIMIT="${ISSUE_LIMIT:-200}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }
gh auth status >/dev/null 2>&1 || { echo 'skipped: gh not authenticated (run: gh auth login)' >&2; exit 10; }

# The roster is the one hard prerequisite — everything else is filtered against it.
repos=$(gh repo list "$ORG" --limit 200 \
  --json name,isArchived,pushedAt,defaultBranchRef 2>/dev/null) || {
    echo "skipped: gh repo list failed for org ${ORG} (token needs repo scope)" >&2
    exit 10
  }

partial='[]'

prs=$(gh search prs --owner "$ORG" --state open --limit "$PR_LIMIT" \
  --json repository,number,title,url,isDraft,author,createdAt,updatedAt 2>/dev/null) || {
    prs='[]'
    partial=$(jq -c '. + ["open-prs"]' <<<"$partial")
  }

issues=$(gh search issues --owner "$ORG" --state open --limit "$ISSUE_LIMIT" \
  --json repository,number,title,url,labels,createdAt,updatedAt 2>/dev/null) || {
    issues='[]'
    partial=$(jq -c '. + ["open-issues"]' <<<"$partial")
  }

jq -n \
  --arg org "$ORG" \
  --argjson repos "$repos" \
  --argjson prs "${prs:-[]}" \
  --argjson issues "${issues:-[]}" \
  --argjson partial "$partial" '
  # Whole-days idle, computed once here so every consumer ranks on the same clock.
  def days_since($ts): (($ts | fromdateiso8601) as $t | ((now - $t) / 86400) | floor);

  ($repos | map(select(.isArchived | not) | .name)) as $active
  | {
      org: $org,
      repos: ( $repos | map({
                 name,
                 archived: .isArchived,
                 pushed_at: .pushedAt,
                 default_branch: (.defaultBranchRef.name // null)
               }) | sort_by(.name) ),
      prs: ( $prs
             | map(select(.repository.name as $n | $active | index($n)))
             | map({
                 repo: .repository.name,
                 number, title, url,
                 draft: .isDraft,
                 author: (.author.login // null),
                 idle_days: days_since(.updatedAt),
                 age_days: days_since(.createdAt)
               })
             | sort_by(-.idle_days) ),
      issues: ( $issues
                | map(select(.repository.name as $n | $active | index($n)))
                | map({
                    repo: .repository.name,
                    number, title, url,
                    labels: (.labels | map(.name)),
                    idle_days: days_since(.updatedAt)
                  })
                | sort_by(.repo, .number) ),
      partial: $partial
    }'
