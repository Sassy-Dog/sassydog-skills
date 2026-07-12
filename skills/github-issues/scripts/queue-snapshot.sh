#!/usr/bin/env bash
# queue-snapshot.sh — one-call read of the boardless fill/drain work queue.
#
# Replaces drain-it's per-tick pair of ad-hoc `gh issue list` reads AND puts the
# parsing of the two machine-readable body contracts in one place:
#   - `touches:` line   → the collision-avoidance file/dir set (issue #38)
#   - `Depends on #N`   → literal dependency lines
#
# Buckets:
#   ready     open + `ready` label, ordered number-ascending (oldest first)
#   in_flight open + `in-progress` label; assignee filter is reported, not
#             silently applied — each item carries its assignees and a `mine`
#             flag (true when @me is among them) so a drain tick can count its
#             own claims while still seeing other loops' claims
#   blocked   open + `blocked` label (numbers only)
#
# Judgment stays in the calling skill: touches-set intersection, priority
# ordering beyond issue number, and the smell test are prose contracts — this
# script only reads and parses.
#
# Usage: queue-snapshot.sh [--repo owner/name] [--limit 200]
# Env:   REPO=owner/name (fallback when --repo absent; else inferred from cwd)
#
# Output: single JSON object on stdout:
#   {"repo":"...","me":"login-or-null",
#    "ready":[{number,title,labels,assignees,touches,depends_on,unannotated}...],
#    "in_flight":[{number,title,labels,assignees,mine,touches}...],
#    "blocked":[N...]}
#
# Exit codes: 0 ok; 10 skipped (gh/python3 missing or no repo); 64 usage.
# Read-only.
set -euo pipefail

REPO="${REPO:-}"
LIMIT=200

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  REPO="$2";  shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "usage: queue-snapshot.sh [--repo owner/name] [--limit N]" >&2; exit 64 ;;
    esac
done
case "$LIMIT" in ''|*[!0-9]*) echo "queue-snapshot: --limit must be a number" >&2; exit 64 ;; esac

command -v gh >/dev/null 2>&1 || { echo "skipped: gh not installed" >&2; exit 10; }
command -v python3 >/dev/null 2>&1 || { echo "skipped: python3 not installed" >&2; exit 10; }
[[ -z "$REPO" ]] && REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
[[ -z "$REPO" ]] && { echo "skipped: not in a GitHub repo and REPO not set" >&2; exit 10; }

ME=$(gh api user --jq .login 2>/dev/null || true)

# gh label filters AND together, so each bucket is its own list call.
FIELDS="number,title,labels,assignees,body"
READY_JSON=$(gh issue list --repo "$REPO" --state open --label ready \
    --limit "$LIMIT" --json "$FIELDS" 2>/dev/null || echo "[]")
INPROG_JSON=$(gh issue list --repo "$REPO" --state open --label in-progress \
    --limit "$LIMIT" --json "$FIELDS" 2>/dev/null || echo "[]")
BLOCKED_JSON=$(gh issue list --repo "$REPO" --state open --label blocked \
    --limit "$LIMIT" --json number 2>/dev/null || echo "[]")

python3 - "$REPO" "$ME" "$READY_JSON" "$INPROG_JSON" "$BLOCKED_JSON" <<'PY'
import json, re, sys

repo, me = sys.argv[1], sys.argv[2] or None
ready_raw = json.loads(sys.argv[3])
inprog_raw = json.loads(sys.argv[4])
blocked_raw = json.loads(sys.argv[5])

# `touches:` line — first matching line wins; entries split on commas and/or
# whitespace. Backticks tolerated (`touches: `a/b`, `c/d``).
touches_re = re.compile(r'^\s*touches:\s*(.+)$', re.IGNORECASE)
# `Depends on #N` lines — every #N on a line that starts with "Depends on"
# (compound "Depends on #12 and #13" yields both).
depends_re = re.compile(r'^\s*depends\s+on\b(.*)$', re.IGNORECASE)
ref_re = re.compile(r'#(\d+)')

def parse_body(body):
    touches, depends = [], []
    for line in (body or "").splitlines():
        m = touches_re.match(line)
        if m and not touches:
            raw = m.group(1).replace('`', ' ')
            touches = [t for t in re.split(r'[,\s]+', raw.strip()) if t]
            continue
        m = depends_re.match(line)
        if m:
            depends += [int(x) for x in ref_re.findall(m.group(1))]
    return touches, sorted(set(depends))

def slim(issue, with_deps):
    touches, depends = parse_body(issue.get("body"))
    out = {
        "number": issue["number"],
        "title": issue.get("title", ""),
        "labels": sorted(l["name"] for l in issue.get("labels", [])),
        "assignees": sorted(a["login"] for a in issue.get("assignees", [])),
        "touches": touches,
    }
    if with_deps:
        out["depends_on"] = depends
        out["unannotated"] = not touches
    return out

ready = sorted((slim(i, True) for i in ready_raw), key=lambda x: x["number"])
in_flight = []
for i in sorted(inprog_raw, key=lambda x: x["number"]):
    item = slim(i, False)
    item["mine"] = bool(me) and me in item["assignees"]
    in_flight.append(item)

print(json.dumps({
    "repo": repo,
    "me": me,
    "ready": ready,
    "in_flight": in_flight,
    "blocked": sorted(i["number"] for i in blocked_raw),
}, indent=2))
PY
