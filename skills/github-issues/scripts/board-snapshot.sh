#!/usr/bin/env bash
# Pull a GitHub ProjectV2 board snapshot grouped by status column.
# Read-only. Emits a single JSON document so consumers can pipe to jq.
#
# Env:
#   PROJECT_NUMBER   board number (required)
#   OWNER            org/user that owns the board (required)
#   PROJECT_LIMIT    item ceiling (default 2000)
#
# Output shape:
#   { "counts": { "<status>": N, ... },
#     "truncated": bool,
#     "items":  [ { number, title, url, status, labels, updatedAt }, ... ] }
#
# NOTE: a zero-item result does NOT necessarily mean "no backlog" — some repos
# track backlog as labeled open issues and leave the board empty. The calling
# skill states which is the source of truth for its repo.
set -euo pipefail

PROJECT_NUMBER="${PROJECT_NUMBER:-}"
OWNER="${OWNER:-}"
[[ -z "$PROJECT_NUMBER" || -z "$OWNER" ]] && {
  echo "usage: PROJECT_NUMBER=<n> OWNER=<org> board-snapshot.sh" >&2
  exit 64
}

# Ceiling stays well above Done-column count so newer Backlog adds aren't
# silently truncated. gh returns items in numeric order, so a too-small --limit
# drops the newest issues off the end (a real repo hit this at exactly 200).
PROJECT_LIMIT="${PROJECT_LIMIT:-2000}"

gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
    --limit "$PROJECT_LIMIT" \
  | jq --argjson limit "$PROJECT_LIMIT" '{
      counts: (
        .items
        | group_by(.status // "Unstatused")
        | map({(.[0].status // "Unstatused"): length})
        | add
      ),
      truncated: (.items | length >= $limit),
      items: [
        .items[]
        | select(.content.type == "Issue")
        | {
            number: .content.number,
            title: .content.title,
            url: .content.url,
            status: (.status // "Unstatused"),
            labels: (.labels // []),
            updatedAt: .content.updatedAt
          }
      ]
    }'
