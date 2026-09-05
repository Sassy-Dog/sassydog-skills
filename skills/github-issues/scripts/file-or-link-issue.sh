#!/usr/bin/env bash
# file-or-link-issue.sh — idempotently create-or-find a GitHub issue keyed by a
# body marker, optionally adding it to a ProjectV2 board column.
#
# The ONLY write-capable script in this skill. The calling skill applies its
# qualifying gate BEFORE calling this; this script's job is (a) idempotency —
# find the marker and return the existing issue instead of re-filing — and
# (b) the create + board-add mechanics.
#
# IDEMPOTENCY IS TWO STAGES, AND NEITHER ONE ALONE IS SUFFICIENT (issue #339).
# The search index is ASYNCHRONOUS. Measured 2026-09-04 against this repo: #337
# was filed at 21:05:37Z carrying marker `stale-issues-title-only-shipped-
# detector`; the SAME marker re-run at 21:05:44Z searched, got `[]`, and filed a
# duplicate (#338). Seven seconds. The identical search ~4 minutes later returns
# both. The marker footer was present in #337's body the whole time and the
# search expression was correct — only the freshness assumption was wrong.
#
#   Stage 1, the SEARCH (`--search '"<marker>" in:body'`). Unbounded in AGE: it
#   finds a marker on an issue filed years and ten thousand issues ago, which no
#   bounded listing can. What it is not is fresh.
#   Stage 2, the RECENT-LISTING SCAN (`gh issue list --state all --json
#   number,url,body --limit N`, NO `--search`). That is a direct object read of
#   the repo's issues rather than a query against the search index, so an issue
#   is visible the instant it exists. Bounded in COUNT, not in age: it sees the
#   N most recently created issues, which is exactly the window the index has
#   not caught up to yet.
#
# The two are COMPLEMENTARY — search covers depth, the scan covers recency — so
# deleting either one restores a real defect. A retry/backoff loop was rejected
# as the fix: it is slow on every duplicate-free call and still races.
#
# WHAT STAGE 2 CANNOT SEE, stated rather than left to be discovered: a marker
# whose issue is older than the `--recent-scan` window AND not yet indexed. That
# combination needs a repo to file more than N issues inside the index window,
# which the calling skill's burst rail (> 5 new issues per run → stop) already
# refuses. Raise `--recent-scan` if a caller can outrun it.
#
# Usage:
#   file-or-link-issue.sh \
#     --marker "sentry-source: PROJ-123" \
#     --title <T> --body-file <F> \
#     [--repo owner/name] \
#     [--labels "bug,sentry-escalation"] \
#     [--ensure-label "name:COLOR:description"]...   # create label if missing
#     [--recent-scan 100] \                          # stage-2 window, issues
#     [--project-id PVT_... --status-field-id PVTSSF_... --status-option-id <id>] \
#     [--dry-run]
#
# Env: DRY_RUN=1 equivalent to --dry-run.
#
# Exit codes:
#   0 — issue is filed (or was already filed); JSON printed to stdout.
#   1 — bad arguments / missing tooling. NEVER a transport failure: a caller may
#       treat 1 as permanent and drop the filing, so nothing that a retry could
#       fix is allowed to exit 1.
#   2 — gh call failed mid-flight. That includes a stage-2 scan that could not be
#       performed (unknown is not verified: a failed idempotency read never
#       licenses a write, because filing blind is the exact harm #339 records)
#       AND the `gh issue create` itself failing. The create's status is captured
#       explicitly rather than left to `set -e`, which used to abort the
#       assignment before this script's own diagnostic could run — measured: a
#       failed create exited 1 with empty stdout and empty stderr, reporting a
#       transient 5xx under the code reserved for "you called me wrong".
#       Retrying is always safe — that is what this script is for.
#
# Output (JSON on stdout):
#   {"action":"filed",          "number":1234, "url":"https://...", "scan_truncated":false, "search_degraded":false}
#   {"action":"already-linked", "number":1234, "url":"https://...", "via":"search"}
#   {"action":"already-linked", "number":1234, "url":"https://...", "via":"recent-scan"}
#   {"action":"filed-no-board", "number":1234, "url":"https://...", "scan_truncated":false, "search_degraded":false}   (board add failed/skipped on error)
#   {"action":"would-file",     "marker":"...", "title":"...", "labels":"...", "scan_truncated":false, "search_degraded":false}   (dry-run)
#
# `via` names WHICH stage answered. It is additive — every existing consumer
# reads `.action`/`.number` — and it exists so the stages are distinguishable:
# without it a gate cannot tell a working stage 2 from a search that happened to
# be warm, which is how this bug survived unmeasured in the first place.
#
# `search_degraded` rides the same three FILING outcomes and answers a DIFFERENT
# question from `scan_truncated`. Truncation says stage 2's window was full, so
# something recent may be unseen; degradation says stage 1 did not run at all,
# so anything OLDER than that window is unseen. A filing with
# `search_degraded:true` is idempotent only against the newest `--recent-scan`
# issues — pre-#339 semantics — and the caller is the only one who can decide
# whether that is good enough. Silence made it look verified.
#
# `scan_truncated` rides the three FILING outcomes: a stage-2 window that came
# back full is indistinguishable from one with headroom, so a marker one row
# past the edge would be invisible and this is filed anyway. Never a silent
# clean read — the shape `stale-issues.sh` already uses for its bounded pull.
#
# The marker is appended to the body as an HTML comment footer (script-owned,
# not caller-owned) so the idempotency lookups always have a stable anchor.
# BOTH stages match that DELIMITED footer, `<!-- <marker> -->`, and never the
# bare marker, through ONE predicate (`footer_pick`) with two call sites.
# Two reasons, and they are different reasons:
#   - stage 2's `contains()` is a plain substring test, so a bare match reports
#     `epic-split: #207/alpha` as already-linked against an existing
#     `epic-split: #207/alpha-two`;
#   - stage 1's GitHub phrase search matches a token SUBSEQUENCE, so the same
#     collision arrives by a different route, and it arrives on the sibling that
#     IS indexed — i.e. any sibling more than a few minutes old, the ordinary
#     case rather than the rare one.
# The footer predicate first shipped on stage 2 alone while stage 1 answered
# first on the bare marker and the docs claimed the guarantee unconditionally.
# The harm is quieter than #339's own: #339 filed a visible duplicate, this
# swallows a real epic child that is never filed, reporting `already-linked`
# with a sibling's number into a backlog `dispatch-ready` consumes. Callers
# never hand-write the footer, so the delimited form is what every issue this
# script filed actually carries.

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
recent_scan=100
dry_run="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)             REPO="$2";             shift 2 ;;
    --marker)           marker="$2";           shift 2 ;;
    --title)            title="$2";            shift 2 ;;
    --body-file)        body_file="$2";        shift 2 ;;
    --labels)           labels="$2";           shift 2 ;;
    --ensure-label)     ensure_labels+=("$2"); shift 2 ;;
    --recent-scan)      recent_scan="$2";      shift 2 ;;
    --project-id)       PROJECT_ID="$2";       shift 2 ;;
    --status-field-id)  STATUS_FIELD_ID="$2";  shift 2 ;;
    --status-option-id) STATUS_OPTION_ID="$2"; shift 2 ;;
    --dry-run)          dry_run=1;             shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not on PATH" >&2; exit 1; }
# SLUG RESOLUTION, SPLIT BY CAUSE. The permanent conditions (not a git repo, no
# remote) and the transient one (gh reached the network and it failed) BOTH make
# `gh repo view` exit 1, so they cannot be told apart from its status — and its
# prose is not something to match on. They are separable locally instead: both
# permanent cases fail in git, before any request. Checking them here first
# leaves any remaining `gh repo view` failure genuinely transport, which is what
# lets this report exit 2 without guessing.
#
# The previous form was `[[ -z "$REPO" ]] && REPO=$(gh repo view ...)`. The
# assignment is the LAST command of that && list, so errexit aborted the script
# on a transient failure — exit 1, empty stdout, empty stderr, before line 137's
# own diagnostic could print. That is the same silent-exit-1 shape this header
# documents for the create, one screen above the fix for it.
if [[ -z "$REPO" ]]; then
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "not in a git repository and --repo not given" >&2
    exit 1
  fi
  if [[ -z "$(git remote 2>/dev/null)" ]]; then
    echo "this git repository has no remotes and --repo not given" >&2
    exit 1
  fi
  repo_rc=0
  # 2>&1 so a failure carries gh's own words; on success this is just the slug.
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1) || repo_rc=$?
  if [[ "$repo_rc" -ne 0 || -z "$REPO" ]]; then
    echo "could not resolve the repo slug, so nothing about this run is verified; refusing to file. gh said: $(tr '\n' ' ' <<<"$REPO")" >&2
    exit 2
  fi
fi
[[ -z "$marker" ]] && { echo "missing --marker" >&2; exit 1; }
[[ -z "$title"  ]] && { echo "missing --title" >&2; exit 1; }
[[ -z "$body_file" ]] && { echo "missing --body-file" >&2; exit 1; }
[[ ! -f "$body_file" ]] && { echo "body file not found: $body_file" >&2; exit 1; }
[[ "$recent_scan" =~ ^[1-9][0-9]*$ ]] || { echo "--recent-scan must be a positive integer, got: $recent_scan" >&2; exit 1; }

# Both scratch files are created here under ONE trap. Splitting them re-created
# the classic bug where a second `trap ... EXIT` silently replaces the first and
# the earlier file leaks.
# Each mktemp is checked: under errexit a failing command substitution aborts
# the script with ITS status, which is 1 — the code reserved for "you called me
# wrong". A full or unwritable TMPDIR is a transport-class failure, not a
# calling error. The second one cleans the first by hand because the trap does
# not exist yet, which is the leak the note above is about.
scan_err=$(mktemp) || {
  echo "could not create a scratch file (TMPDIR full or unwritable), so nothing about this run is verified; refusing to file" >&2
  exit 2
}
body_with_marker=$(mktemp) || {
  rm -f "$scan_err"
  echo "could not create a scratch file (TMPDIR full or unwritable), so nothing about this run is verified; refusing to file" >&2
  exit 2
}
trap 'rm -f "$scan_err" "$body_with_marker"' EXIT

# THE DELIMITED-FOOTER PREDICATE, DEFINED ONCE AND USED BY BOTH STAGES. Two
# copies is exactly how the stage-1 half of this guarantee went missing: the
# footer match was written into stage 2 while stage 1 went on answering first on
# the bare marker, and the docs claimed the guarantee unconditionally. One
# definition, two call sites — a widening here reaches both, and the gate proves
# both call sites depend on it.
footer_pick='map(select((.body // "") | contains("<!-- " + $m + " -->"))) | sort_by(.number) | first // empty'

# 1. Idempotency stage 1 — the SEARCH index. Unbounded in age, NOT fresh; the
#    header records the measurement. A search failure degrades to "no hit"
#    rather than aborting, because stage 2 below is the authority that must
#    hold: this stage is an optimisation that reaches further back in time.
#
#    `--json` MUST include `body`, because the rows are FILTERED rather than
#    trusted: GitHub phrase search matches a token SUBSEQUENCE, not the literal
#    string, so `"epic-split: #207/auth" in:body` returns issues whose marker is
#    `epic-split: #207/auth-refresh`. Verified read-only on 2026-09-04 against
#    this repo — `"stale-issues-title-only" in:body` returns #339/#337/#338,
#    whose actual marker is `stale-issues-title-only-shipped-detector`, while a
#    superstring control returns `[]`. A hit that does not carry the footer
#    falls THROUGH to stage 2 rather than short-circuiting.
#
#    The limit is 30 rather than 5 for the same reason: now that rows are
#    filtered, a truncated relevance-ordered page can hide the exact-footer
#    issue behind its near-misses. Truncation here is not silent harm — it falls
#    through to stage 2 and, failing that, files a VISIBLE duplicate, which is
#    the safe direction. The swallowed-child failure is the one being designed
#    out.
search_limit=30
# The fall-through on failure is deliberate and stays: stage 2 is the authority
# for anything recent, so a degraded search must not stop a filing. What does
# NOT stay is the silence. `2>/dev/null || echo "[]"` discarded gh's status AND
# its words, so a rate-limited search — the likely one, since the Search API is
# throttled far harder than the plain listing stage 2 uses — was indistinguish-
# able from a search that legitimately found nothing, while the payload went on
# to assert `scan_truncated:false`. Idempotency then silently narrowed from
# unbounded-in-age to the newest `--recent-scan` issues, which is pre-#339
# behaviour, reported as success.
search_rc=0
existing=$(gh issue list --repo "$REPO" --state all \
  --search "\"$marker\" in:body" \
  --json number,url,body \
  --limit "$search_limit" 2>"$scan_err") || search_rc=$?
search_degraded=false
if [[ "$search_rc" -ne 0 ]]; then
  search_degraded=true
  existing="[]"
  echo "stage-1 marker search failed, so idempotency for issues older than the recent scan is UNVERIFIED; continuing to the recent scan. gh said: $(tr '\n' ' ' <"$scan_err")" >&2
fi

# Tolerant on purpose: stage 1's own `|| echo "[]"` means a degraded search
# legitimately yields an empty array, and stage 2 below is the authority. The
# FATAL type check belongs to stage 2, not here.
search_hit=$(jq -c --arg m "$marker" "$footer_pick" <<<"$existing" 2>/dev/null || true)
if [[ -n "$search_hit" ]]; then
  jq '{action:"already-linked", number:.number, url:.url, via:"search"}' <<<"$search_hit"
  exit 0
fi

# 2. Idempotency stage 2 — the RECENT-LISTING scan. No `--search`, so this is a
#    direct object read and is read-after-write consistent: an issue filed a
#    second ago is in it. `--state all` matters as much here as it does above —
#    a marker on a CLOSED issue is still filed.
#
#    A scan that could not be PERFORMED is not a scan that found nothing. Exit 2
#    instead of filing blind (see the exit-code note in the header).
scan_rc=0
recent=$(gh issue list --repo "$REPO" --state all \
  --json number,url,body \
  --limit "$recent_scan" 2>"$scan_err") || scan_rc=$?
if [[ "$scan_rc" -ne 0 ]]; then
  echo "recent-issue scan failed, so idempotency is unverified; refusing to file. gh said: $(tr '\n' ' ' <"$scan_err")" >&2
  exit 2
fi

# A gh that exits 0 having printed nothing (or HTML from a rate limiter) is a
# SUCCESSFUL call with no answer in it. `jq` reads empty input as no output and
# exits 0, so without this the run falls through and files blind — the same harm
# as a failed scan, reached by a path no exit code reports.
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$recent"; then
  echo "recent-issue scan did not return a JSON array, so idempotency is unverified; refusing to file" >&2
  exit 2
fi

# A window that came back FULL is indistinguishable from one with headroom, and
# the marker may sit one row past the edge. Never a silent clean read: the shape
# `stale-issues.sh` uses for its own bounded pull.
scan_truncated=false
[[ "$(jq 'length' <<<"$recent")" -ge "$recent_scan" ]] && scan_truncated=true

if ! recent_hit=$(jq -c --arg m "$marker" "$footer_pick" <<<"$recent"); then
  echo "recent-issue scan returned unparseable JSON, so idempotency is unverified; refusing to file" >&2
  exit 2
fi

if [[ -n "$recent_hit" ]]; then
  jq '{action:"already-linked", number:.number, url:.url, via:"recent-scan"}' <<<"$recent_hit"
  exit 0
fi

if [[ "$scan_truncated" == "true" ]]; then
  echo "recent-issue scan returned a FULL window ($recent_scan issues) with no marker hit; a match one row past the edge would be invisible. Raise --recent-scan if this repo files in bursts." >&2
fi

# 3. Dry-run short-circuit. Deliberately AFTER both stages: a preview that says
#    `would-file` for a marker already filed is a wrong preview.
if [[ "$dry_run" == "1" ]]; then
  jq -n --arg m "$marker" --arg t "$title" --arg l "$labels" --argjson tr "$scan_truncated" --argjson sd "$search_degraded" \
    '{action:"would-file", marker:$m, title:$t, labels:$l, scan_truncated:$tr, search_degraded:$sd}'
  exit 0
fi

# 4. Ensure requested labels exist (idempotent; ignore "already exists").
# ${arr[@]+...} (not [@]:-) — on bash 3.2 (macOS) the :- form expands an empty
# array to one '' element instead of zero elements.
for spec in ${ensure_labels[@]+"${ensure_labels[@]}"}; do
  [[ -z "$spec" ]] && continue
  name="${spec%%:*}"; rest="${spec#*:}"
  color="${rest%%:*}"; desc="${rest#*:}"
  gh label create "$name" --repo "$REPO" \
    --color "$color" --description "$desc" \
    >/dev/null 2>&1 || true
done

# 5. Build the body with the marker footer appended. The scratch file and its
# trap are established above, with the scan's.
cat "$body_file" > "$body_with_marker"
printf '\n\n<!-- %s -->\n' "$marker" >> "$body_with_marker"

# 6. Create the issue. Parse the URL gh prints on its last line.
#
# THE CREATE'S STATUS IS CAPTURED EXPLICITLY, NOT LEFT TO `set -e`. This was
# measured wrong: with `created_url=$(gh issue create … | tail -n1)` under
# `set -euo pipefail`, pipefail fails the pipeline on gh's status and errexit
# aborts the ASSIGNMENT — so the `exit 2` below and its diagnostic never run,
# and a transient 5xx on the write exits 1 with empty stdout and empty stderr.
# Exit 1 is this script's "you called me wrong" code, which a caller written
# against the contract treats as permanent; the most likely failure this path
# sees was reported as the one code that must never be retried, silently.
label_args=()
[[ -n "$labels" ]] && label_args=(--label "$labels")
create_rc=0
create_out=$(gh issue create \
  --repo "$REPO" \
  --title "$title" \
  --body-file "$body_with_marker" \
  ${label_args[@]+"${label_args[@]}"} 2>&1) || create_rc=$?
if [[ "$create_rc" -ne 0 ]]; then
  echo "gh issue create failed (exit $create_rc): $(tr '\n' ' ' <<<"$create_out")" >&2
  exit 2
fi

created_url=$(tail -n1 <<<"$create_out")
if [[ ! "$created_url" =~ ^https://github\.com/[^/]+/[^/]+/issues/[0-9]+$ ]]; then
  echo "gh issue create did not return a URL; got: $created_url" >&2
  exit 2
fi

created_number=$(basename "$created_url")

# 7. Optional board add (graphql is the reliable shape for the new item id).
if [[ -z "$PROJECT_ID" ]]; then
  jq -n --arg n "$created_number" --arg u "$created_url" --argjson tr "$scan_truncated" --argjson sd "$search_degraded" \
    '{action:"filed", number:($n|tonumber), url:$u, scan_truncated:$tr, search_degraded:$sd}'
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
    jq -n --arg n "$created_number" --arg u "$created_url" --argjson tr "$scan_truncated" --argjson sd "$search_degraded" \
      '{action:"filed-no-board", number:($n|tonumber), url:$u, scan_truncated:$tr, search_degraded:$sd}'
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

jq -n --arg n "$created_number" --arg u "$created_url" --argjson tr "$scan_truncated" --argjson sd "$search_degraded" \
  '{action:"filed", number:($n|tonumber), url:$u, scan_truncated:$tr, search_degraded:$sd}'
