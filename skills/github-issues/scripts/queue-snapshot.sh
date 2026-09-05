#!/usr/bin/env bash
# queue-snapshot.sh — one-call read of the boardless fill/drain work queue.
#
# Replaces dispatch-ready's per-tick pair of ad-hoc `gh issue list` reads AND puts the
# parsing of the machine-readable body contracts in one place:
#   - `touches:` line   → the collision-avoidance file/dir set (issue #38)
#   - `Depends on #N`   → literal dependency lines
#   - `stack:` line     → a declared stacked-PR chain, bottom→top, carried on
#                         the BOTTOM issue and naming every member including
#                         itself. Distinct from `Depends on`: a dependency
#                         often means "later", a stack means "ship together".
#   - `site:` line      → the execution site an issue can only be worked from
#                         (issue #340, epic #322). One line, one free-form
#                         token; ABSENT MEANS "any site", and so does a
#                         malformed line. Emitted lowercased, or null.
#
# `site:` resolution, spelled out because a body can be ambiguous in several
# ways at once and the answer must not depend on WHICH ambiguity it carries:
#   * The FIRST `site:` line carrying a token wins — the same first-line-wins
#     rule `touches:` and `stack:` already use. Later lines are ignored.
#   * Only the first whitespace-separated token is the site: `site: vdi (corp
#     laptop)` is `vdi`. The contract is one token, so the rest is a remark.
#   * Backticks are tolerated in the value, as in `touches:`.
#   * Case is folded. A site name is an identifier compared for equality
#     against a per-checkout `execution_site:`, and a case difference between
#     an issue body and a config file is invisible in both places.
#   * A `site:` line carrying no token at all is not a declaration: the scan
#     continues past it, and if nothing else declares one the answer is null.
#     Null and absent are the same answer — any site.
#   * Lines inside a FENCED code block or an HTML comment are not read as a
#     declaration. This is not hypothetical: both issues that introduced the
#     contract, #322 and #340, carry a fenced example holding a `site: vdi`
#     line, so a fence-blind parse marks the substrate issues themselves
#     VDI-only. Indentation is deliberately NOT read as a code block — the
#     leading-whitespace tolerance is what lets the contract sit inside a list
#     item, and a 4-space rule would take that away.
#   * The masking above applies to `site:` ALONE. `touches:`, `stack:` and
#     `Depends on` keep the parse they shipped with: narrowing them is a
#     behaviour change for every consumer already reading them, and #340 is
#     substrate only.
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
#    "ready":[{number,title,labels,assignees,touches,stack,site,depends_on,unannotated}...],
#    "in_flight":[{number,title,labels,assignees,mine,touches,stack,site}...],
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
# `stack:` line — a declared stacked-PR chain, bottom→top. Order is MEANINGFUL
# (it is the merge order), so unlike depends_on this is never sorted or
# de-duplicated into a set. First matching line wins.
stack_re = re.compile(r'^\s*stack:\s*(.+)$', re.IGNORECASE)
# `site:` line — the execution-site contract. `(\S.*)` is what makes a valueless
# `site:` (or one followed only by whitespace) fail to match at all, so it is
# never mistaken for a declaration of the empty site.
site_re = re.compile(r'^\s*site:\s*(\S.*)$', re.IGNORECASE)
# A fence DELIMITER, not a fence: the opening and closing lines look alike, so
# the marker character is what pairs them.
fence_re = re.compile(r'^\s*(`{3,}|~{3,})')
ref_re = re.compile(r'#(\d+)')


def scan_lines(body):
    """Yield (line, masked) per body line.

    `masked` marks a line sitting inside a fenced code block or an HTML
    comment — text that LOOKS like a body contract but is an example or a
    template remark. Only the `site:` parse honours it; see the header for why
    the older contracts are deliberately left fence-blind.
    """
    fence = None            # the fence character currently open, or None
    in_comment = False
    for line in (body or "").splitlines():
        opened_in_comment = in_comment
        # Walk this line's comment markers in order, so a line that both opens
        # and closes one leaves the state where it found it.
        rest = line
        while True:
            if in_comment:
                cut = rest.find('-->')
                if cut < 0:
                    break
                rest, in_comment = rest[cut + 3:], False
            else:
                cut = rest.find('<!--')
                if cut < 0:
                    break
                rest, in_comment = rest[cut + 4:], True
        masked = opened_in_comment or fence is not None
        if not opened_in_comment:
            m = fence_re.match(line)
            if m:
                marker = m.group(1)[0]
                if fence is None:
                    fence = marker
                elif marker == fence:
                    fence = None
                masked = True   # the delimiter line is never content
        yield line, masked

def parse_body(body):
    touches, depends, stack, site = [], [], [], None
    for line, masked in scan_lines(body):
        m = touches_re.match(line)
        if m and not touches:
            raw = m.group(1).replace('`', ' ')
            touches = [t for t in re.split(r'[,\s]+', raw.strip()) if t]
            continue
        m = stack_re.match(line)
        if m and not stack:
            seen = set()
            for x in ref_re.findall(m.group(1)):
                n = int(x)
                if n not in seen:      # drop repeats, keep first-seen order
                    seen.add(n)
                    stack.append(n)
            continue
        if site is None and not masked:
            m = site_re.match(line)
            if m:
                token = m.group(1).replace('`', ' ').split()
                if token:              # a valueless line declares nothing
                    site = token[0].lower()
                continue
        m = depends_re.match(line)
        if m:
            depends += [int(x) for x in ref_re.findall(m.group(1))]
    return touches, sorted(set(depends)), stack, site

def slim(issue, with_deps):
    touches, depends, stack, site = parse_body(issue.get("body"))
    out = {
        "number": issue["number"],
        "title": issue.get("title", ""),
        "labels": sorted(l["name"] for l in issue.get("labels", [])),
        "assignees": sorted(a["login"] for a in issue.get("assignees", [])),
        "touches": touches,
        "stack": stack,
        "site": site,
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
