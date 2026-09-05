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
#                         token, emitted lowercased; ABSENT MEANS "any site".
#
# `site:` resolution, spelled out because a body can be ambiguous in several
# ways at once and the answer must not depend on WHICH ambiguity it carries:
#   * The FIRST `site:` line carrying a token wins — the same first-line-wins
#     rule `touches:` and `stack:` already use. Later lines are ignored.
#   * Only the first whitespace-separated token is the site: `site: vdi (corp
#     laptop)` is `vdi`. The contract is one token, so the rest is a remark.
#   * Backticks are tolerated in the value, as in `touches:`.
#   * Case is folded. A site name is a token compared for equality against a
#     per-checkout `execution_site:`, and a case difference between an issue
#     body and a config file is invisible in both places. The comparison is
#     case-insensitive on BOTH sides — folding the configured value is the
#     reading skill's half, which this script cannot do for it.
#   * A `site:` line carrying no token at all is not a declaration: the scan
#     continues past it, and if nothing else declares one the answer is null.
#     Null and absent are the same answer — any site. That valueless line is
#     the ONLY malformed shape this parser recognises.
#   * NOTHING IS RESERVED. Every other token is emitted verbatim (lowercased),
#     `site: any` and `site: none` included — to this script they are ordinary
#     site names, not escapes. Do not read "absent means any site" as though
#     the word `any` were a value: it is the MISSING LINE that means it.
#   * Lines inside a FENCED code block are not read as a declaration, and
#     neither is text inside an HTML comment — the site parse reads the
#     comment-stripped remainder of a line, so an unfilled issue-template
#     placeholder (`site: <!-- vdi | mac -->`) declares nothing while
#     `site: <!-- pick one --> vdi` declares `vdi`. The fenced half is not
#     hypothetical: both issues that introduced the contract, #322 and #340,
#     carry a fenced example holding a `site: vdi` line, so a fence-blind
#     parse marks the substrate issues themselves VDI-only.
#   * Indentation is deliberately NOT read as a code block. CommonMark makes
#     four leading spaces an indented code block; here the leading-whitespace
#     tolerance is what lets the contract sit as a continuation line under a
#     NESTED list item, which is already past four columns, and a 4-space rule
#     would take that away.
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
# A fence DELIMITER, not a fence: openers and closers look alike, so an opener
# is remembered as (character, run length) and `closes_fence` decides pairing.
fence_re = re.compile(r'^\s*(`{3,}|~{3,})')
ref_re = re.compile(r'#(\d+)')


def strip_comments(line, in_comment):
    """Return (visible, in_comment): the line with HTML-comment spans removed.

    The site parse reads this REMAINDER rather than the raw line. Keying on
    "did the line START inside a comment" instead is a different rule, and it
    misses the shape issue templates actually use: `site: <!-- vdi | mac -->`
    starts outside the comment, so the raw line matches and the unfilled
    placeholder itself becomes the site.
    """
    out, rest = [], line
    while rest:
        if in_comment:
            cut = rest.find('-->')
            if cut < 0:
                break                        # comment runs past end of line
            rest, in_comment = rest[cut + 3:], False
        else:
            cut = rest.find('<!--')
            if cut < 0:
                out.append(rest)
                break
            out.append(rest[:cut])
            rest, in_comment = rest[cut + 4:], True
    return ''.join(out), in_comment


def closes_fence(line, fence):
    """CommonMark's closer test. All three clauses earn their place.

    Same CHARACTER as the opener, or a ``` inside a ~~~ block ends it. At
    least as LONG, or a ```-fenced example quoted inside a ````-fenced block
    ends the quote early. Nothing but WHITESPACE after it, or an info string
    (```text) reads as a closer.
    """
    m = fence_re.match(line)
    if not m:
        return False
    marker = m.group(1)
    return (marker[0] == fence[0] and len(marker) >= fence[1]
            and not line[m.end():].strip())


def scan_lines(body):
    """Yield (line, visible) per body line.

    `visible` is the only text the `site:` parse may read: empty for anything
    inside a fenced code block (delimiters included), and stripped of HTML
    comments everywhere else. The older contracts read `line` instead and are
    deliberately left fence-blind — see the header.
    """
    fence = None            # (character, run length) of the open fence, or None
    in_comment = False
    for line in (body or "").splitlines():
        if fence is not None:
            # Inside a fence, comment syntax is CONTENT, so the comment walk
            # does not run here. An unclosed `<!--` in a fenced example would
            # otherwise swallow the closing delimiter and every real
            # declaration after it — the false NEGATIVE, where "absent means
            # any site" lets the wrong loop claim a site-held issue.
            if closes_fence(line, fence):
                fence = None
            yield line, ""                   # fenced content declares nothing
            continue
        visible, in_comment = strip_comments(line, in_comment)
        m = fence_re.match(visible)
        if m:
            fence = (m.group(1)[0], len(m.group(1)))
            yield line, ""                   # the delimiter declares nothing
            continue
        yield line, visible

def parse_body(body):
    touches, depends, stack, site = [], [], [], None
    for line, visible in scan_lines(body):
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
        if site is None:
            m = site_re.match(visible)
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
