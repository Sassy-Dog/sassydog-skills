#!/usr/bin/env bash
# file-or-link-issue.sh — idempotently create-or-find a GitHub issue keyed by a
# body marker, optionally adding it to a ProjectV2 board column.
#
# The ONLY write-capable script in this skill. The calling skill applies its
# qualifying gate BEFORE calling this; this script's job is (a) idempotency —
# search for the marker and return the existing issue instead of re-filing —
# and (b) the create + board-add mechanics.
#
# Usage:
#   file-or-link-issue.sh \
#     --marker "sentry-source: PROJ-123" \
#     --title <T> --body-file <F> \
#     [--repo owner/name] \
#     [--labels "bug,sentry-escalation"] \
#     [--ensure-label "name:COLOR:description"]...   # create label if missing
#     [--project-id PVT_... --status-field-id PVTSSF_... --status-option-id <id>] \
#     [--dry-run]
#
# Env: DRY_RUN=1 equivalent to --dry-run.
#
# Exit codes:
#   0 — issue is filed (or was already filed); JSON printed to stdout.
#   1 — bad arguments / missing tooling.
#   2 — gh call failed mid-flight.
#
# Output (JSON on stdout):
#   {"action":"filed",          "number":1234, "url":"https://..."}
#   {"action":"already-linked", "number":1234, "url":"https://..."}
#   {"action":"filed-no-board", "number":1234, "url":"https://..."}   (board add failed/skipped on error)
#   {"action":"would-file",     "marker":"...", "title":"...", "labels":"..."}   (dry-run)
#
# The marker is appended to the body as an HTML comment footer (script-owned,
# not caller-owned) so the idempotency search always has a stable anchor.

set -euo pipefail

REPO=""
PROJECT_ID=""
STATUS_FIELD_ID=""
STATUS_OPTION_ID=""
marker=""
title=""
body_file=""
labels=""
ensure_labels=()
dry_run="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)             REPO="$2";             shift 2 ;;
    --marker)           marker="$2";           shift 2 ;;
    --title)            title="$2";            shift 2 ;;
    --body-file)        body_file="$2";        shift 2 ;;
    --labels)           labels="$2";           shift 2 ;;
    --ensure-label)     ensure_labels+=("$2"); shift 2 ;;
    --project-id)       PROJECT_ID="$2";       shift 2 ;;
    --status-field-id)  STATUS_FIELD_ID="$2";  shift 2 ;;
    --status-option-id) STATUS_OPTION_ID="$2"; shift 2 ;;
    --dry-run)          dry_run=1;             shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not on PATH" >&2; exit 1; }
[[ -z "$REPO" ]] && REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[[ -z "$REPO" ]] && { echo "not in a GitHub repo and --repo not given" >&2; exit 1; }
[[ -z "$marker" ]] && { echo "missing --marker" >&2; exit 1; }
[[ -z "$title"  ]] && { echo "missing --title" >&2; exit 1; }
[[ -z "$body_file" ]] && { echo "missing --body-file" >&2; exit 1; }
[[ ! -f "$body_file" ]] && { echo "body file not found: $body_file" >&2; exit 1; }

# 1. Idempotency: GH issue search indexes body text. Marker hit = already filed.
existing=$(gh issue list --repo "$REPO" --state all \
  --search "\"$marker\" in:body" \
  --json number,url \
  --limit 5 2>/dev/null || echo "[]")

existing_count=$(echo "$existing" | jq 'length')
if [[ "$existing_count" -gt 0 ]]; then
  echo "$existing" | jq '{action:"already-linked", number:.[0].number, url:.[0].url}'
  exit 0
fi

# 2. Dry-run short-circuit.
if [[ "$dry_run" == "1" ]]; then
  jq -n --arg m "$marker" --arg t "$title" --arg l "$labels" \
    '{action:"would-file", marker:$m, title:$t, labels:$l}'
  exit 0
fi

# 3. Ensure requested labels exist (idempotent; ignore "already exists").
for spec in "${ensure_labels[@]:-}"; do
  [[ -z "$spec" ]] && continue
  name="${spec%%:*}"; rest="${spec#*:}"
  color="${rest%%:*}"; desc="${rest#*:}"
  gh label create "$name" --repo "$REPO" \
    --color "$color" --description "$desc" \
    >/dev/null 2>&1 || true
done

# 4. Build the body with the marker footer appended.
body_with_marker=$(mktemp)
trap 'rm -f "$body_with_marker"' EXIT
cat "$body_file" > "$body_with_marker"
printf '\n\n<!-- %s -->\n' "$marker" >> "$body_with_marker"

# 5. Create the issue. Parse the URL gh prints on its last line.
label_args=()
[[ -n "$labels" ]] && label_args=(--label "$labels")
created_url=$(gh issue create \
  --repo "$REPO" \
  --title "$title" \
  --body-file "$body_with_marker" \
  "${label_args[@]:-}" 2>&1 | tail -n1)

if [[ ! "$created_url" =~ ^https://github\.com/[^/]+/[^/]+/issues/[0-9]+$ ]]; then
  echo "gh issue create did not return a URL; got: $created_url" >&2
  exit 2
fi

created_number=$(basename "$created_url")

# 6. Optional board add (graphql is the reliable shape for the new item id).
if [[ -z "$PROJECT_ID" ]]; then
  jq -n --arg n "$created_number" --arg u "$created_url" \
    '{action:"filed", number:($n|tonumber), url:$u}'
  exit 0
fi

project_item_id=$(gh api graphql -f query='
  mutation($projectId: ID!, $contentId: ID!) {
    addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
      item { id }
    }
  }' \
  -f projectId="$PROJECT_ID" \
  -f contentId="$(gh issue view "$created_number" --repo "$REPO" --json id -q .id)" \
  --jq '.data.addProjectV2ItemById.item.id' 2>&1) || {
    echo "project add failed; issue $created_number filed but unboarded: $project_item_id" >&2
    jq -n --arg n "$created_number" --arg u "$created_url" \
      '{action:"filed-no-board", number:($n|tonumber), url:$u}'
    exit 0
  }

if [[ -n "$STATUS_FIELD_ID" && -n "$STATUS_OPTION_ID" ]]; then
  gh project item-edit \
    --project-id "$PROJECT_ID" \
    --id "$project_item_id" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$STATUS_OPTION_ID" >/dev/null || {
      echo "status set failed; item on board but column unset" >&2
    }
fi

jq -n --arg n "$created_number" --arg u "$created_url" \
  '{action:"filed", number:($n|tonumber), url:$u}'
