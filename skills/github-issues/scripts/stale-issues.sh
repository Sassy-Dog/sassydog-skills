#!/usr/bin/env bash
# Detect issues whose state is stale relative to recent ship history.
#
# Three detectors:
#   1. shipped-but-still-open — an open issue named by a merged PR that never
#      closed it. TWO arms, and every finding records which one fired
#      (`matched_via`: "title", "body", or "title+body"):
#        - title — a "(#N)" parenthetical in the PR title. A conventional-commit
#          title parenthetical is a hyperlink, NOT a Closes-keyword.
#        - body  — an "#N" in the PR body carrying NO closing keyword. This is
#          where the reference nearly always lives: GitHub appends "(#N)" to the
#          SQUASH-MERGE COMMIT title, not to the PR title, and the number it
#          appends is the PR's OWN (issue #337).
#      Either way the issue never auto-closed — needs manual review-and-close,
#      or a status comment if only half-shipped.
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

# Each pull lands in a FILE and python is handed the path, never the payload.
# These three documents carry every issue body, plus (since #337) every recent
# PR body, and passing that on argv blows ARG_MAX on any real repo — measured
# here as `python3: Argument list too long`, exit 126, with the detector's whole
# output gone. The all-state pull was already near the limit at ALL_LIMIT=500;
# adding PR bodies pushed it over. Keep the payload off the command line.
PULL_DIR="$(mktemp -d)"
trap 'rm -rf "$PULL_DIR"' EXIT

# pull <destination-file> <gh args...> — a failed or empty pull degrades to the
# empty array the callers below already expect, never to malformed JSON.
pull() {
  local dest="$1"; shift
  gh "$@" >"$dest" 2>/dev/null || :
  [ -s "$dest" ] || printf '[]' >"$dest"
}

pull "$PULL_DIR/open-issues.json" \
  issue list --repo "$REPO" --state open --limit 100 \
  --json number,title,body,createdAt,updatedAt

# Pull recent merged PRs (last 60 days is plenty — older sheds happen rarely).
# `body` is load-bearing rather than convenience: it is where the issue
# reference actually lives (detector 1, arm 2). Drop it from this field list and
# detector 1 silently collapses back to its near-vacuous title arm.
pull "$PULL_DIR/merged-prs.json" \
  pr list --repo "$REPO" --state merged --limit 100 \
  --search "merged:>=$(date -v-60d +%Y-%m-%d 2>/dev/null || date -d '60 days ago' +%Y-%m-%d)" \
  --json number,title,body,mergedAt

# Detector 3 needs the CLOSED issues too — a completed epic's children are
# closed by definition — so it takes its own all-state pull rather than reusing
# the open-only one above.
pull "$PULL_DIR/all-issues.json" \
  issue list --repo "$REPO" --state all --limit "$ALL_LIMIT" \
  --json number,title,state,body

python3 - "$PULL_DIR/open-issues.json" "$PULL_DIR/merged-prs.json" \
  "$PULL_DIR/all-issues.json" "$ALL_LIMIT" <<'PY'
import json, re, sys

# Paths, not payloads — see the ARG_MAX note beside the pulls.
with open(sys.argv[1]) as fh:
    issues = json.load(fh)
with open(sys.argv[2]) as fh:
    prs = json.load(fh)
with open(sys.argv[3]) as fh:
    all_issues = json.load(fh)
all_limit = int(sys.argv[4])

# --- detector 1: shipped-but-still-open --------------------------------------
# Build map: issue_number -> [matching merged PRs]. TWO arms, and each finding
# records which one fired, because the arms carry very different weight and a
# reader has to be able to tell a title hit from a body hit.
#
# ARM 1 — the TITLE parenthetical. Scan EVERY parenthetical group in each title
# and pull all `#N` refs from inside. This catches:
#   - simple   "(#419)"           -> 419
#   - compound "(#419 + #421)"    -> 419, 421         (missed by the naive regex)
#   - csv      "(#419, #421)"     -> 419, 421
#   - trailing "(#458)" PR self-ref -> 458 (harmless: GitHub numbers issues and
#                                     PRs from ONE sequence, so a PR's own
#                                     number can never also be an open issue)
# The naive `\(#(\d+)\)` regex only matches the simple form — compound refs
# slipped through it in production and left shipped issues flagged-but-open.
#
# ARM 2 — the PR BODY. The title arm ALONE is near-vacuous wherever GitHub's
# squash-merge autotitle is the convention, because GitHub appends "(#N)" to the
# MERGE COMMIT title rather than the PR title, and the number it appends is the
# PR's OWN. Measured for issue #337: of the last 100 merged PRs in this repo
# only 3 titles carried any parenthetical, while 35 of the last 40 PR BODIES
# named an issue — the detector's sole input was present in 3% of PRs. A live
# miss followed: #316 was fixed by #328, which named it in the body with no
# closing keyword; #316 stayed open AND labelled `ready`, and this detector
# reported `[]`, which reads as a verified answer rather than as a blind spot.
#
# Arm 2 is deliberately BROAD — any `#N` in the body counts, not only refs under
# a fix-shaped phrase — because the miss it exists to catch is exactly the author
# who described the work without wording it as a close. That makes a body hit a
# REVIEW PROMPT rather than a verdict: a PR citing an issue for background is
# reported too, and `matched_via` is what lets the reader weigh it. Two
# exclusions keep that breadth from collapsing into "fires on everything":
#
#   - A ref governed by a CLOSING KEYWORD is not a finding. GitHub auto-closes
#     on those, so an open issue named that way is a cross-repo ref or a genuine
#     anomaly, not the omission this detector reports.
#   - HTML COMMENTS are stripped first. PR templates carry example refs inside
#     `<!-- -->` (this repo's own template carries `Closes #123`), authors leave
#     the comment in the body, and it is boilerplate rather than anyone's
#     reference — unstripped, the same template numbers would flag on EVERY PR.
#
# The two arms keep SEPARATE ref regexes although the patterns are currently
# identical. Do not fold them into one: each arm has to be neuterable on its own
# for `scripts/test-stale-issues.sh` to mutation-prove it independently, and the
# arms are free to diverge (a title ref is already narrowed by `group_re`; a
# body ref is not).
group_re = re.compile(r'\(([^)]*)\)')
issue_in_group_re = re.compile(r'#(\d+)')
BODY_REF_RE = re.compile(r'#(\d+)')
HTML_COMMENT_RE = re.compile(r'<!--.*?-->', re.DOTALL)
# GitHub's documented closing keywords, anchored adjacent to the ref.
# Recognising one SUPPRESSES a finding, so this set stays tight: a keyword form
# it misses costs a false positive a human dismisses in a second, while one it
# invents costs the silent false negative this detector exists to end.
CLOSING_KEYWORD_RE = re.compile(
    r'\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b[:\s]*#(\d+)',
    re.IGNORECASE,
)

issue_to_prs = {}
for pr in prs:
    title = pr.get("title", "")
    body = HTML_COMMENT_RE.sub(" ", pr.get("body") or "")

    # issue number -> the arms that fired, recorded in title-then-body order.
    arms = {}
    for group in group_re.findall(title):
        for m in issue_in_group_re.finditer(group):
            arms.setdefault(int(m.group(1)), ["title"])

    closed_by_keyword = {int(m.group(1)) for m in CLOSING_KEYWORD_RE.finditer(body)}
    for m in BODY_REF_RE.finditer(body):
        n = int(m.group(1))
        if n in closed_by_keyword:
            continue
        fired = arms.setdefault(n, [])
        if "body" not in fired:
            fired.append("body")

    for n, fired in arms.items():
        issue_to_prs.setdefault(n, []).append({
            "pr_number": pr["number"],
            "pr_title": pr["title"],
            "mergedAt": pr.get("mergedAt"),
            "matched_via": "+".join(fired),
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
