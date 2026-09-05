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
#   * The token has a GRAMMAR, applied after folding: `[a-z0-9]` then up to 63
#     more of `[a-z0-9._-]`. It is not a whitelist of known sites — it is
#     deliberately permissive, so that every plausible workstation name fits
#     and a token which FAILS it was never a site name at all. The parse bounds
#     this rather than leaving it to whoever reports the value: a consumer
#     echoes the token into a refusal reason (#341), issue bodies on a public
#     repo stay editable after `ready` is applied, and a boundary asserted once
#     here is worth more than the same boundary asked of every reader.
#   * TWO malformed shapes exist and both answer the SAME way — a `site:` line
#     with no token at all, and one whose token fails the grammar. Neither is a
#     declaration: the scan continues past it, and if nothing else declares one
#     the answer is null. Null and absent are the same answer — any site. That
#     direction is deliberate and is why the grammar is permissive: rejection
#     means "this was never a site", and "any site" is then the right answer.
#   * NOTHING IS RESERVED inside that grammar: `site: any` and `site: none`
#     are ordinary site names, not escapes. Do not read "absent means any
#     site" as though the word `any` were a value: it is the MISSING LINE that
#     means it.
#   * Lines inside a FENCED code block are not read as a declaration, and
#     neither is text inside an HTML comment — the site parse reads the
#     comment-stripped remainder of a line, so an unfilled issue-template
#     placeholder (`site: <!-- vdi | mac -->`) declares nothing while
#     `site: <!-- pick one --> vdi` declares `vdi`. The fenced half is not
#     hypothetical: both issues that introduced the contract, #322 and #340,
#     carry a fenced example holding a `site: vdi` line, so a fence-blind
#     parse marks the substrate issues themselves VDI-only.
#   * Neither mask may swallow text GitHub RENDERS, which is the failure
#     direction that matters: a masked declaration reads as "any site" and the
#     wrong loop claims the issue. Three CommonMark constructs are honoured for
#     that reason alone, each measured against a real body before it was
#     written:
#       - CODE SPANS are blanked before any markup is looked for. This repo's
#         issue #6 carries a backticked `<!-- generated-by: …` with no closer
#         on the line; treating it as a comment ran the state to the next
#         `-->` 15 lines later, swallowed a fence opener on the way, and masked
#         25 of 30 non-blank lines. A backticked ```-run is likewise not a
#         fence, and CommonMark's rule that a BACKTICK fence's info string may
#         not contain a backtick is applied at the opener, so neither a paired
#         nor an unpaired one can open a block that never closes.
#       - The EMPTY COMMENTS `<!-->` and `<!--->` close where they stand.
#         Searching for `-->` four characters in misses both, and an unclosed
#         comment masks the entire rest of the body.
#       - A `<!--` that starts MID-LINE is inline HTML and cannot outlive its
#         paragraph, so it is dropped at the next blank line. One that starts a
#         line keeps CommonMark's block semantics and runs to its closer.
#       - A fence OPENER's info string is not markup either: entering a
#         comment there and letting it survive the block leaks state past the
#         closer, which is the same defect as running the walk inside a fence.
#   * ACCEPTED DIVERGENCE, recorded rather than closed — THREE shapes, each
#     with a row pinning today's answer so that changing one is a decision
#     rather than a surprise:
#       - Raw-text HTML blocks (`<script>`, `<style>`) and processing
#         instructions (`<?…?>`) are NOT masked, so `<style>` + `site: nowhere`
#         + `</style>` declares `nowhere` although GitHub's sanitizer drops
#         those elements with their contents. FALSE POSITIVE. Closing it means
#         a third line-state machine beside the fence and the comment.
#       - A CODE SPAN is paired per line, so one spanning a line break does not
#         blank and text inside it declares. FALSE POSITIVE. Closing it means
#         carrying span state across lines, which the per-line index map is
#         built to avoid.
#       - An UNCLOSED mid-line `<!--` masks the rest of its paragraph, though
#         CommonMark renders it as literal text. FALSE NEGATIVE, and bounded:
#         the blank-line rule above stops it at the paragraph. Closing it needs
#         lookahead for a closer that may never arrive, i.e. a second pass.
#     None appeared in 554 sampled org bodies.
#   * KNOWN AND ACCEPTED, left to #341. A token that FAILS the grammar is
#     emitted as `null`, byte-identical to a body with no `site:` line at all,
#     so a consumer cannot tell "rejected" from "absent" — `site: vdi<U+200B>`
#     renders on GitHub as `site: vdi` and emits null. A `site_rejected:`
#     sibling would let a consumer HOLD rather than claim, but it is a schema
#     addition whose only reader is the dispatch filter, so the skill that
#     acquires the reader is the one that should decide it. #340 emits the
#     value and nothing more.
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
# `re.ASCII` beside `re.IGNORECASE`, because Unicode folding makes `ſite:`
# (U+017F), `SİTE:` and `sıte:` match a key whose VALUE grammar is ASCII-only.
# The trade is that `\s` narrows too, so a non-breaking space BEFORE the key no
# longer matches while one after the colon still parses. Scoped to this pattern:
# the older three contracts keep the parse they shipped with.
site_re = re.compile(r'^\s*site:\s*(\S.*)$', re.IGNORECASE | re.ASCII)
# The site TOKEN's grammar, applied AFTER folding. Not a whitelist: the
# boundary past which a token was never a workstation name. See the header for
# why the parse owns this rather than each consumer.
site_token_re = re.compile(r'^[a-z0-9][a-z0-9._-]{0,63}$')
# A fence DELIMITER, not a fence: openers and closers look alike, so an opener
# is remembered as (character, run length) and `closes_fence` decides pairing.
fence_re = re.compile(r'^\s*(`{3,}|~{3,})')
ref_re = re.compile(r'#(\d+)')


def blank_code_spans(text):
    """Replace paired backtick code spans with spaces, PRESERVING LENGTH.

    CommonMark pairs a run of N backticks with the next run of exactly N, and
    what lies between is literal text — so `` `<!-- x` `` opens no comment and
    ```gh pr merge``` opens no fence. An unpaired run is an ordinary character
    and is left alone, which is what keeps a real ```-fence opener visible.

    Length is preserved so the result serves as an INDEX MAP over the original
    line: markup is located here and text is cut from there, which is how a
    backticked VALUE (`site: `vdi``) still reaches the token split intact.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text[i] != '`':
            i += 1
            continue
        j = i
        while j < n and text[j] == '`':
            j += 1
        k = j
        while k < n:
            if text[k] != '`':
                k += 1
                continue
            e = k
            while e < n and text[e] == '`':
                e += 1
            if e - k == j - i:               # a closer of exactly equal length
                out[i:e] = ' ' * (e - i)
                i = e
                break
            k = e
        else:
            i = j                            # unpaired: literal backticks
    return ''.join(out)


def strip_comments(line, scan, comment):
    """Return (visible, visible_scan, comment) — the line minus comment spans.

    The site parse reads this REMAINDER rather than the raw line. Keying on
    "did the line START inside a comment" instead is a different rule, and it
    misses the shape issue templates actually use: `site: <!-- vdi | mac -->`
    starts outside the comment, so the raw line matches and the unfilled
    placeholder itself becomes the site.

    Marker positions are found in `scan` (code spans blanked) and text is cut
    from `line`; the two are the same length, so the indices agree. `comment`
    is None, `block` (the `<!--` began a line, so CommonMark block semantics
    apply and it runs to its closer) or `inline` (it began mid-line, so it
    cannot outlive its paragraph — `scan_lines` drops it at a blank line).
    """
    out, outs, i, n = [], [], 0, len(line)
    while i < n:
        if comment:
            end = scan.find('-->', i)
            if end < 0:
                break                        # comment runs past end of line
            i, comment = end + 3, None
        else:
            start = scan.find('<!--', i)
            if start < 0:
                out.append(line[i:])
                outs.append(scan[i:])
                break
            out.append(line[i:start])
            outs.append(scan[i:start])
            comment = 'inline' if line[:start].strip() else 'block'
            i = start + 4
            # CommonMark's two EMPTY comments close where they stand. Resuming
            # the search for `-->` past them misses both, and an unclosed
            # comment masks the whole rest of the body.
            if scan.startswith('>', i):
                i, comment = i + 1, None
            elif scan.startswith('->', i):
                i, comment = i + 2, None
    return ''.join(out), ''.join(outs), comment


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
    comment = None          # None, 'block' or 'inline' — see strip_comments
    for line in (body or "").splitlines():
        if fence is not None:
            # Inside a fence, comment syntax is CONTENT, so the comment walk
            # does not run here. Letting it run leaks comment state PAST the
            # block, and the first real declaration after the fence is then
            # masked — the false NEGATIVE, where "absent means any site" lets
            # the wrong loop claim a site-held issue.
            if closes_fence(line, fence):
                fence = None
            yield line, ""                   # fenced content declares nothing
            continue
        if comment == 'inline' and not line.strip():
            comment = None                   # inline HTML dies at its paragraph
        # A line that OPENS or CONTINUES a block comment is an HTML block for
        # its whole length, so no fence opens on it: `<!-- x --> ``` ` is one
        # HTML block, not a comment followed by a fence. Its visible remainder
        # still declares, because GitHub renders that text.
        html_line = comment == 'block'
        scan = blank_code_spans(line)
        if scan.lstrip().startswith('<!--'):
            html_line = True
        visible, vscan, comment = strip_comments(line, scan, comment)
        m = None if html_line else fence_re.match(vscan)
        # A BACKTICK fence's info string may not contain a backtick (CommonMark);
        # such a line is a paragraph. `visible` is checked rather than `vscan`
        # because the blanking has already erased any PAIRED run, and it is the
        # unpaired leftovers that disqualify the opener. Tilde fences are exempt,
        # as the spec has them.
        tainted_info = bool(m) and m.group(1)[0] == '`' and '`' in visible[m.end():]
        if m and not tainted_info:
            fence = (m.group(1)[0], len(m.group(1)))
            comment = None                   # an info string is not markup
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
                candidate = (m.group(1).replace('`', ' ').split() or [''])[0].lower()
                if site_token_re.fullmatch(candidate):
                    site = candidate   # both malformed shapes fall through
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
