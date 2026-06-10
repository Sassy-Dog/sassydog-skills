#!/usr/bin/env bash
# Detect issues whose state is stale relative to recent ship history.
#
# Two detectors:
#   1. shipped-but-still-open — open issue has a merged PR whose title contains
#      "(#<N>)" matching it. The classic failure mode: a conventional-commit
#      title parenthetical is a hyperlink, NOT a Closes-keyword, so the issue
#      never auto-closed — needs manual review-and-close, or a status comment
#      if only half-shipped.
#   2. stub-body — open issue with a body shorter than 80 chars or that's just
#      a one-line placeholder. Almost certainly needs scoping before tackle.
#      IMPORTANT for consumers: before declaring a stub, check the issue's
#      COMMENTS (gh issue view N --comments) — some repos put scope in a
#      follow-up comment, not the OP body. This script only sees the body.
#
# Env: REPO=owner/name (default: inferred from cwd via gh)
#
# Read-only.
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"

if ! command -v gh >/dev/null 2>&1; then
  echo "skipped: gh not installed" >&2
  exit 10
fi
[[ -z "$REPO" ]] && { echo "skipped: not in a GitHub repo and REPO not set" >&2; exit 10; }

OPEN_ISSUES_JSON=$(gh issue list --repo "$REPO" --state open --limit 100 \
  --json number,title,body,createdAt,updatedAt 2>/dev/null || echo "[]")

# Pull recent merged PRs (last 60 days is plenty — older sheds happen rarely).
RECENT_MERGED_PRS_JSON=$(gh pr list --repo "$REPO" --state merged --limit 100 \
  --search "merged:>=$(date -v-60d +%Y-%m-%d 2>/dev/null || date -d '60 days ago' +%Y-%m-%d)" \
  --json number,title,mergedAt 2>/dev/null || echo "[]")

python3 - "$OPEN_ISSUES_JSON" "$RECENT_MERGED_PRS_JSON" <<'PY'
import json, re, sys

issues = json.loads(sys.argv[1])
prs = json.loads(sys.argv[2])

# Build map: issue_number -> [matching merged PRs]
#
# Scan EVERY parenthetical group in each title and pull all `#N` refs
# from inside. This catches:
#   - simple   "(#419)"           → 419
#   - compound "(#419 + #421)"    → 419, 421         (missed by the naive regex)
#   - csv      "(#419, #421)"     → 419, 421
#   - trailing "(#458)" PR self-ref → 458 (harmless: not in open-issues list)
#
# The naive `\(#(\d+)\)` regex only matches the simple form — compound refs
# slipped through it in production and left shipped issues flagged-but-open.
group_re = re.compile(r'\(([^)]*)\)')
issue_in_group_re = re.compile(r'#(\d+)')
issue_to_prs = {}
for pr in prs:
    title = pr.get("title", "")
    seen_in_this_pr = set()
    for group in group_re.findall(title):
        for m in issue_in_group_re.finditer(group):
            n = int(m.group(1))
            if n in seen_in_this_pr:
                continue
            seen_in_this_pr.add(n)
            issue_to_prs.setdefault(n, []).append({
                "pr_number": pr["number"],
                "pr_title": pr["title"],
                "mergedAt": pr.get("mergedAt"),
            })

shipped_but_open = []
stub_body = []

for issue in issues:
    n = issue["number"]
    body = (issue.get("body") or "").strip()
    title = issue.get("title", "")

    matching_prs = issue_to_prs.get(n, [])
    if matching_prs:
        shipped_but_open.append({
            "issue": n,
            "title": title,
            "merged_prs": matching_prs,
        })

    if len(body) < 80 or body.lower() in ("tbd", "todo", "..."):
        stub_body.append({
            "issue": n,
            "title": title,
            "body_length": len(body),
            "body_preview": body[:120] if body else "",
        })

print("=== shipped-but-still-open ===")
print(json.dumps(shipped_but_open, indent=2))
print("=== stub-body ===")
print(json.dumps(stub_body, indent=2))
PY
