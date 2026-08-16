#!/usr/bin/env bash
# Detect issues whose state is stale relative to recent ship history.
#
# Three detectors:
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
#   3. tracking-parent-complete — an OPEN issue with >= 1 child (any issue whose
#      body carries the literal `Part of #<N>` line groom-backlog's epic split
#      writes) where EVERY child is CLOSED. Nothing upstream can catch this:
#      GitHub moves a card only when a merged PR closes the issue via a
#      keyword, and a tracking parent is definitionally the issue no PR ever
#      names, so it can never self-close. Its children close one by one under
#      their own PRs and the parent sits open forever, counted as pending work
#      by every read of the backlog (issue #198 — three of eight open issues in
#      one repo were finished work). REPORT ONLY: a human closes, never this.
#
# Env: REPO=owner/name (default: inferred from cwd via gh)
#      ALL_LIMIT=<n> (default 500) — ceiling on detector 3's all-state pull. A
#        pull that comes back AT the ceiling is reported `truncated: true`;
#        that result is UNKNOWN, not clean. Re-run with a higher ALL_LIMIT.
#
# Read-only.
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
ALL_LIMIT="${ALL_LIMIT:-500}"

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

# Detector 3 needs the CLOSED issues too — a completed epic's children are
# closed by definition — so it takes its own all-state pull rather than reusing
# the open-only one above.
ALL_ISSUES_JSON=$(gh issue list --repo "$REPO" --state all --limit "$ALL_LIMIT" \
  --json number,title,state,body 2>/dev/null || echo "[]")

python3 - "$OPEN_ISSUES_JSON" "$RECENT_MERGED_PRS_JSON" "$ALL_ISSUES_JSON" "$ALL_LIMIT" <<'PY'
import json, re, sys

issues = json.loads(sys.argv[1])
prs = json.loads(sys.argv[2])
all_issues = json.loads(sys.argv[3])
all_limit = int(sys.argv[4])

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

# --- detector 3: tracking-parent-complete ------------------------------------
# groom-backlog's epic split gives every child a literal `Part of #<parent>`
# line and gives the parent nothing, so the link is one-directional and only the
# children can be read for it. Build parent -> children from every issue in the
# repo, then report the OPEN parents whose children have ALL closed.
#
# The trailing (?![0-9]) is the PREFIX GUARD. Without a "the next character is
# not a digit" requirement, a match for parent #28 also claims every child of
# #283, and #28 gets reported complete on somebody else's finished work.
# GitHub's own text search has exactly that hole — it will not anchor `#28`
# against `#283` — which is why this is a body scan here and not a
# `--search "Part of #28"` query per candidate.
PART_OF_RE = re.compile(r'Part of #(\d+)(?![0-9])', re.IGNORECASE)

by_number = {i["number"]: i for i in all_issues}
parent_to_children = {}
for issue in all_issues:
    seen_parents = set()
    for m in PART_OF_RE.finditer(issue.get("body") or ""):
        parent_n = int(m.group(1))
        if parent_n == issue["number"] or parent_n in seen_parents:
            continue
        seen_parents.add(parent_n)
        parent_to_children.setdefault(parent_n, []).append(issue)

tracking_parent_complete = []
for parent_n, children in sorted(parent_to_children.items()):
    parent = by_number.get(parent_n)
    # An unknown parent number is a cross-repo or malformed reference, not a
    # finding. A closed parent is already reconciled.
    if parent is None or parent.get("state") != "OPEN":
        continue
    if not all(c.get("state") == "CLOSED" for c in children):
        continue
    tracking_parent_complete.append({
        "issue": parent_n,
        "title": parent.get("title", ""),
        "child_count": len(children),
        "children": sorted(c["number"] for c in children),
    })

# A pull that came back AT the ceiling saw an unknown slice of the repo, so an
# empty result means "found nothing in what I could see", not "clean". Say so
# in the payload rather than letting a consumer read silence as a pass.
truncated = len(all_issues) >= all_limit

print("=== shipped-but-still-open ===")
print(json.dumps(shipped_but_open, indent=2))
print("=== stub-body ===")
print(json.dumps(stub_body, indent=2))
print("=== tracking-parent-complete ===")
print(json.dumps({
    "truncated": truncated,
    "limit": all_limit,
    "scanned": len(all_issues),
    "parents": tracking_parent_complete,
}, indent=2))

if truncated:
    print(
        "WARNING: the all-state issue pull returned %d == ALL_LIMIT (%d), so the "
        "parent->child map is TRUNCATED. Treat tracking-parent-complete as "
        "UNKNOWN, not clean, and re-run with a higher ALL_LIMIT."
        % (len(all_issues), all_limit),
        file=sys.stderr,
    )
PY
