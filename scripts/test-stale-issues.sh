#!/usr/bin/env bash
# test-stale-issues.sh — pins github-issues/scripts/stale-issues.sh: its third
# detector, `tracking-parent-complete` (issue #198), and the two arms of its
# first, `shipped-but-still-open` (issue #337).
#
# Both detectors fail the SAME silent way, which is why they share a gate: their
# wrong answer is an empty list, and an empty list is also the healthy answer.
# Nothing reddens when either goes vacuous.
#
# --- detector 1, and why it needed two arms (issue #337) ---------------------
# It originally read PR TITLES only, scanning `(#N)` parentheticals, and pulled
# `--json number,title,mergedAt`. But GitHub appends `(#N)` to the SQUASH-MERGE
# COMMIT title, not to the PR title, and the number it appends is the PR's OWN.
# Measured on this repo: 3 of the last 100 merged PR titles carried any
# parenthetical, while 35 of the last 40 PR BODIES named an issue. The detector's
# sole input was present in 3% of PRs, and it answered `[]` — which reads as
# verified, not as blind. It missed live: #316 was fixed by #328, which named
# #316 in its body with no closing keyword, so #316 stayed open AND labelled
# `ready` and the dispatcher would have redone finished work.
#
# The body arm is an ADDITION, never a replacement — all 3 of those title hits
# (#192, #165, #164) are hand-written refs and real true positives, and a body
# scan cannot see them — and three properties make the addition non-vacuous
# rather than a detector that fires on everything:
#
#   a. A body ref WITHOUT a closing keyword flags. This is the whole point.
#   b. A body ref WITH one does NOT. GitHub auto-closes on those, so flagging
#      them would bury (a) under one finding per merged PR. A row asserting only
#      that the arm fires passes just as well when it fires on everything, so
#      both directions are pinned, and each is mutation-proved below.
#   c. HTML comments are stripped before the scan. PR templates carry example
#      refs inside `<!-- -->` (this repo's own carries `Closes #123`) and authors
#      leave them in, so an unstripped body flags the template's numbers on every
#      single PR — the same "fires on everything" collapse as (b).
#
# (b) AND (c) ARE THE TRUST BOUNDARY, and each is a route back to `[]`. They are
# the only code here that reads untrusted PR text and decides to say nothing, so
# every way they can OVER-suppress gets its own fixture and its own mutant. A
# combined row would go green again the moment one form regressed:
#
#   - `Closes #N` inside a fenced code block, inside an inline code span, or
#     inside a quotation is an illustration, not GitHub closing anything. The
#     backticked form is what this repo's own docs and PR template model, so
#     without it a PR that merely DOCUMENTS the convention silences the issue.
#   - `\s` between keyword and ref spans NEWLINES, so `## Resolved` two lines
#     above a bare `#451` would read as a close. The separator is same-line.
#   - Suppression is POSITIONAL. A body-global number set let one `Closes #N`
#     silence every later mention of N in the same body.
#   - A single stray `<!--` plus the template's trailing `-->` used to delete
#     everything between them — silencing every issue a PR named AT ONCE, with
#     no visible trace, since HTML comments render as nothing. The pattern now
#     refuses to span a nested `<!--`, oversized spans are left in place, and
#     the refusal reaches the reader as both a finding field and a stderr line.
#   - A ref needs BOUNDARIES: `owner/repo#951` is not this repo's #951 and the
#     hex colour `#7A3FE4` is not issue #7.
#
# Every one of those trades the same way: an over-broad suppression is a SILENT
# FALSE NEGATIVE, while a missed one is a false positive a human dismisses.
#
# The mock serves ONLY the fields `--json` asks for, on BOTH list branches,
# because the fixture is otherwise dishonest: `body` is the sole input to
# detectors 2 and 3 as well as to the new arm, and a mock that always hands it
# back keeps every row green while production reads "" — which for detector 3
# means `parent_to_children` stays {} and #198's bug returns in silence.
#
# A FAILED pull exits 10 rather than degrading to `[]`. Three empty sections and
# exit 0 is byte-identical to a healthy repo, so an expired token would
# otherwise render as "we checked, nothing found".
#
# One property here is asserted against the SOURCE rather than the fixture, and
# has to be: adding `body` pushed the three pulls past ARG_MAX on a real repo
# (`python3: Argument list too long`, exit 126, no output at all), so they now
# reach python as file PATHS. This fixture's payload is a few kB and can never
# reproduce that, which means a later "simplify" back to `json.loads(sys.argv)`
# would keep every fixture row green while breaking every real invocation.
#
# --- detector 3 -------------------------------------------------------------
# Why this exists: an epic that splits into children can never close itself.
# GitHub's automation moves an issue only when a merged PR carries a closing
# keyword for it, and a tracking parent is definitionally the issue no PR ever
# names — so the children close one by one under their own PRs and the parent
# stays open forever. Three of eight open issues in one repo turned out to be
# finished work, found this way, and every prioritisation read off that backlog
# had been wrong. This detector is the only thing that notices, which makes each
# of its silent-wrong answers a backlog nobody can trust:
#
#   1. A false NEGATIVE (a complete parent not reported) restores the original
#      bug exactly — silence and "clean" are the same output.
#   2. A false POSITIVE from the PREFIX COLLISION is worse than silence: read
#      `Part of #283` without requiring a non-digit after the number and issue
#      #28 inherits #283's finished children, so a human is told to close live
#      work. GitHub's own text search has this hole, which is why detection is
#      a body scan and not a per-parent `--search "Part of #28"` query.
#   3. A TRUNCATED pull reports the same empty list a clean repo does. Unknown
#      has to render as unknown, or "we checked" gets asserted about a slice of
#      the repo nobody chose.
#
# Asserted here:
#   - a complete parent IS reported, with its child numbers
#   - a parent with any OPEN child is NOT (the negative case)
#   - a CLOSED parent is not re-reported (already reconciled)
#   - the prefix guard holds: open #28 does not claim #283's children — and the
#     fixture is mutation-proved live, by running a copy of the script whose
#     regex has lost the guard and requiring THAT copy to report #28
#   - a pull returning at ALL_LIMIT reports `truncated: true` plus a stderr
#     warning, rather than an empty list that reads as clean
#   - detector 1's TITLE arm still fires, including the hand-written compound
#     form `(#190) (#189)` that a body scan would not have caught
#   - detector 1's BODY arm fires on a keyword-less ref (#316) and does NOT fire
#     on a `Closes`-governed one (#500) or on one buried in an HTML comment
#     (#700) — and every one of those three is mutation-proved: neutering the
#     body regex must drop #316 while leaving the title arm's #400 alone,
#     neutering the closing-keyword regex must make #500 appear, and neutering
#     the comment strip must make #700 appear
#   - the suppression does NOT reach past GitHub's own closing semantics: a
#     keyword in a fence (#801), a code span (#803), a quotation (#805), one
#     separated by blank lines (#807), and a second mention after a real close
#     (#809) all still flag — each with a mutant that makes exactly that one
#     vanish, so the three underlying defects stay told apart
#   - a stray `<!--` cannot swallow the body: #811 and #813 survive it, and the
#     naive `<!--.*?-->` mutant must swallow them both
#   - an oversized comment is REFUSED rather than stripped, #815 stays visible,
#     and the refusal is on the finding AND on stderr
#   - a body ref carries boundaries: `owner/repo#951` and `#7A3FE4` claim
#     neither #951 nor #7, and the unbounded mutant must claim both
#   - dropping `body` from EITHER `--json` pull reddens — the merged-PR one
#     drops #316, the all-state one drops detector 3's #283
#   - a FAILED pull exits 10 with gh's own reason, printing no sections at all
#   - every finding names the arm that matched (`matched_via`)
#   - the pulls reach python as file paths, never as argv payloads, and the
#     all-state pull passes its own `--limit` (both source-level — see the
#     ARG_MAX note above; the fixture is far too small to show either)
#   - detector 2 still works
#   - the whole run is READ-ONLY: the mock records any non-read call, and the
#     record must be empty
#
# The mock replaces `gh` only, and serves recorded JSON: no repo, no network.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-stale-issues.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-stale-issues: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPT="skills/github-issues/scripts/stale-issues.sh"

if ! command -v python3 >/dev/null 2>&1; then
    echo "test-stale-issues: SKIP (python3 not installed — CI still enforces)" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "stale-issues tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
# Serves the three recorded pulls the script makes and records EVERYTHING else
# in $MOCK_WRITES — an unexpected call is both recorded and fatal, so a future
# edit that reaches for a mutation cannot pass by simply being unmocked.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

cmd="${1:-}"; sub="${2:-}"
shift 2 2>/dev/null || true

# MOCK_FAIL="<cmd> <sub>" makes that one pull fail the way an expired token or
# a rate limit does: non-zero, with a reason on stderr.
if [ -n "${MOCK_FAIL:-}" ] && [ "$cmd $sub" = "$MOCK_FAIL" ]; then
    echo "simulated failure: HTTP 401 Bad credentials" >&2
    exit 1
fi

# serve <fixture-file> <fields-csv> <limit>
#
# Projects to the requested --json fields and truncates to --limit, exactly as
# gh does. BOTH list branches go through this, and that is the point: a mock
# that hands back a field the caller never asked for keeps a gate green while
# production reads nothing. `body` is the sole input to detectors 2 AND 3, so
# an unprojected `issue list` leaves the #198 tracking-parent detector — the
# whole reason this gate exists — completely unpinned.
serve() {
    python3 - "$1" "$2" "$3" <<'PYPROJECT'
import json, sys
rows = json.load(open(sys.argv[1]))
want = [f for f in sys.argv[2].split(",") if f]
limit = int(sys.argv[3])
rows = [{k: v for k, v in r.items() if k in want} for r in rows]
print(json.dumps(rows[:limit]))
PYPROJECT
}

case "$cmd $sub" in
    "issue list")
        state=""; fields=""; limit=30      # gh's own default page size
        repo=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --repo)  repo="${2:-}";  shift 2 ;;
                --state) state="${2:-}"; shift 2 ;;
                --json)  fields="${2:-}"; shift 2 ;;
                --limit) limit="${2:-}"; shift 2 ;;
                *)       shift ;;
            esac
        done
        # `--repo` was parsed by nobody, so dropping it from a pull stayed green
        # while production would read whatever repo the cwd happened to be.
        if [ "$repo" != "$MOCK_REPO" ]; then
            echo "mock gh: issue list aimed at '$repo', expected '$MOCK_REPO'" >&2; exit 1
        fi
        case "$state" in
            open) serve "$MOCK_OPEN_ISSUES" "$fields" "$limit" ;;
            all)  serve "$MOCK_ALL_ISSUES" "$fields" "$limit" ;;
            *)    echo "mock gh: unhandled issue list --state '$state'" >&2; exit 1 ;;
        esac ;;
    "pr list")
        # `--state` is parsed AND dispatched on, exactly as the issue-list arm
        # above does. It used to fall to the `*) shift` catch-all and be served
        # regardless, so deleting `--state merged` from the script left all 46
        # rows green — while `gh pr list` with no --state returns OPEN PRs, and
        # with this detector's broad body arm nearly every open PR would produce
        # a shipped-but-still-open finding. The gate's own header measures 35 of
        # the last 40 PR bodies naming an issue.
        state=""; fields=""; limit=30; repo=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --repo)  repo="${2:-}";  shift 2 ;;
                --state) state="${2:-}"; shift 2 ;;
                --json)  fields="${2:-}"; shift 2 ;;
                --limit) limit="${2:-}"; shift 2 ;;
                *)       shift ;;
            esac
        done
        if [ "$repo" != "$MOCK_REPO" ]; then
            echo "mock gh: pr list aimed at '$repo', expected '$MOCK_REPO'" >&2; exit 1
        fi
        case "$state" in
            merged) serve "$MOCK_PRS" "$fields" "$limit" ;;
            *)      echo "mock gh: unhandled pr list --state '$state'" >&2; exit 1 ;;
        esac ;;
    "repo view")
        if [ "${MOCK_FAIL_REPO_VIEW:-0}" = "1" ]; then
            echo "gh: Bad credentials (HTTP 401)" >&2
            exit 1
        fi
        printf '%s\n' "$MOCK_REPO" ;;
    *)
        echo "gh $cmd $sub $*" >>"$MOCK_WRITES"
        echo "mock gh: refusing unexpected call: gh $cmd $sub $*" >&2
        exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

export MOCK_REPO="mock-org/mock-repo"
export MOCK_WRITES="$WORK/writes.log"
export MOCK_OPEN_ISSUES="$WORK/open-issues.json"
export MOCK_ALL_ISSUES="$WORK/all-issues.json"
export MOCK_PRS="$WORK/prs.json"
: >"$MOCK_WRITES"

# --- the fixture -------------------------------------------------------------
# Detector 3 (issue #198):
# #283  OPEN    complete parent: children #286, #287, both closed
# #341  OPEN    incomplete parent: #345 closed, #346 still OPEN
# #125  CLOSED  parent already reconciled: child #126 closed
# #28   OPEN    the prefix decoy — no children of its own. A parser that reads
#               `Part of #283` as "#28, then some digits" hands it #283's two
#               closed children and reports it complete.
#
# Detector 1 (issue #337) — one issue per arm and per exclusion, so a row that
# reddens names the exact behaviour that broke:
# #400  OPEN    title arm, simple: shipped under a PR titled "(#400)"
# #189  OPEN    title arm, compound: PR #193's title carries "(#190) (#189)".
# #190  OPEN      A body scan would never see these two — the title arm is an
#                 independent true positive and stays.
# #316  OPEN    BODY arm: PR #328's title carries no ref at all (it is the real
#               shape — GitHub puts "(#328)" on the squash COMMIT), and its body
#               says "See #316" with no closing keyword. This is the live miss.
# #500  OPEN    body ref WITH `Closes #500` — must NOT flag. GitHub auto-closes
#               on the keyword, so a still-open copy is a cross-repo ref or an
#               anomaly, and flagging it would bury the real findings under one
#               per merged PR.
# #600  OPEN    named by BOTH arms in PR #601 — pins the merge, `matched_via`
#               "title+body" rather than two entries or a lost arm.
# #700  OPEN    named ONLY inside PR #701's leftover template HTML comment —
#               boilerplate, not a reference, and must NOT flag.
#
# Every detector-1 issue is given a body over the 80-char stub floor so the
# stub-body expectation stays exactly [28, 341] and the two detectors' rows
# cannot mask each other.
#
# The two parents are deliberately NOT 2-digit-prefix siblings of each other
# (#283 and #341, not #283 and #284): under the truncating mutant below, #341's
# children would otherwise also land on #28, and its still-open #346 would mask
# the very false positive the decoy exists to expose.
cat >"$MOCK_ALL_ISSUES" <<'JSON'
[
  {"number": 28,  "state": "OPEN",   "title": "Standalone issue",
   "body": "A short standalone issue with no children at all."},
  {"number": 125, "state": "CLOSED", "title": "Epic: closed already",
   "body": "Tracking issue, closed by hand once the last of its work landed."},
  {"number": 126, "state": "CLOSED", "title": "Child of the closed epic",
   "body": "Do the thing.\n\nPart of #125"},
  {"number": 283, "state": "OPEN",   "title": "Epic: token minting",
   "body": "Tracking issue for the token-minting work. It tracks the split rather than dispatching any of it."},
  {"number": 286, "state": "CLOSED", "title": "Extract the token-minting helper",
   "body": "Extract it.\n\nPart of #283"},
  {"number": 287, "state": "CLOSED", "title": "Route the sync workflows through it",
   "body": "Route them.\n\nPart of #283"},
  {"number": 341, "state": "OPEN",   "title": "Epic: lockfile sync",
   "body": "Tracking issue for the lockfile-sync work."},
  {"number": 345, "state": "CLOSED", "title": "Sync bun.lock",
   "body": "Sync it.\n\nPart of #341"},
  {"number": 346, "state": "OPEN",   "title": "Sync the pod lockfile",
   "body": "Sync it too.\n\nPart of #341"},
  {"number": 400, "state": "OPEN",   "title": "Ordinary open issue",
   "body": "An ordinary issue with a body comfortably longer than the eighty-character stub floor."},
  {"number": 189, "state": "OPEN",   "title": "Compound-ref sibling A",
   "body": "One half of a hand-written compound title parenthetical, with a body well past the eighty-character stub floor."},
  {"number": 190, "state": "OPEN",   "title": "Compound-ref sibling B",
   "body": "The other half of that compound title parenthetical, likewise past the eighty-character stub floor."},
  {"number": 316, "state": "OPEN",   "title": "setup-deps mints app tokens with the deprecated app-id",
   "body": "The workflow templates mint an app token with the deprecated app-id input, and the docs still describe it that way."},
  {"number": 500, "state": "OPEN",   "title": "Named under a closing keyword",
   "body": "A merged PR body names this issue under a Closes keyword, so GitHub already handled it and a still-open copy is an anomaly."},
  {"number": 600, "state": "OPEN",   "title": "Named by both arms of detector 1",
   "body": "Named in a merged PR title parenthetical and again in that same PR body, so both arms of detector one see it."},
  {"number": 700, "state": "OPEN",   "title": "Named only inside template boilerplate",
   "body": "Named only inside an HTML comment carried over from the PR template, which is boilerplate rather than any author reference."},
  {"number": 801, "state": "OPEN",   "title": "Keyword inside a fenced code block",
   "body": "A merged PR shows a Closes line for this issue inside a fenced code block, which is an illustration and not GitHub closing anything."},
  {"number": 803, "state": "OPEN",   "title": "Keyword inside an inline code span",
   "body": "A merged PR writes the convention for this issue in backticks, which is the form this repo's own docs and PR template both model."},
  {"number": 805, "state": "OPEN",   "title": "Keyword inside a quotation",
   "body": "A merged PR quotes somebody else's old body carrying a Fixes line for this issue, which is reporting text rather than closing it."},
  {"number": 807, "state": "OPEN",   "title": "Keyword separated from the ref by blank lines",
   "body": "A merged PR carries a Resolved heading two lines above this bare reference, which GitHub does not read as a closing keyword at all."},
  {"number": 809, "state": "OPEN",   "title": "Named again after a genuine closing keyword",
   "body": "A merged PR closes this issue on one line and then mentions the same number again later, which a body-global number set would swallow."},
  {"number": 811, "state": "OPEN",   "title": "First of two swallowed by a stray comment opener",
   "body": "A merged PR names this issue after a stray HTML comment opener whose closer is the PR template's, which used to delete the text between."},
  {"number": 813, "state": "OPEN",   "title": "Second of two swallowed by a stray comment opener",
   "body": "Named in the same swallowed span as its sibling, so the failure silences every issue a PR named at once rather than only one of them."},
  {"number": 817, "state": "OPEN",   "title": "Keyword inside a DOUBLE-backtick code span",
   "body": "A merged PR writes the convention for this issue in double backticks — the form the detector's own docstring used, and the one a span regex mis-pairs as an empty span."},
  {"number": 815, "state": "OPEN",   "title": "Named inside an oversized HTML comment",
   "body": "Named inside an HTML comment past the strip's span cap, so the strip is refused and the reference stays visible with the refusal marked."},
  {"number": 7,   "state": "OPEN",   "title": "The hex-colour decoy",
   "body": "A merged PR body contains the hex colour 7A3FE4, which an unbounded ref regex reads as a reference to this issue number seven."},
  {"number": 951, "state": "OPEN",   "title": "The cross-repo decoy",
   "body": "A merged PR body names another repository's issue with an owner/repo prefix, which an unbounded ref regex attributes to this repo."}
]
JSON

cat >"$MOCK_OPEN_ISSUES" <<'JSON'
[
  {"number": 28,  "title": "Standalone issue",
   "body": "A short standalone issue with no children at all.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 283, "title": "Epic: token minting",
   "body": "Tracking issue for the token-minting work. It tracks the split rather than dispatching any of it.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 341, "title": "Epic: lockfile sync",
   "body": "Tracking issue for the lockfile-sync work.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 400, "title": "Ordinary open issue",
   "body": "An ordinary issue with a body comfortably longer than the eighty-character stub floor.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 189, "title": "Compound-ref sibling A",
   "body": "One half of a hand-written compound title parenthetical, with a body well past the eighty-character stub floor.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 190, "title": "Compound-ref sibling B",
   "body": "The other half of that compound title parenthetical, likewise past the eighty-character stub floor.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 316, "title": "setup-deps mints app tokens with the deprecated app-id",
   "body": "The workflow templates mint an app token with the deprecated app-id input, and the docs still describe it that way.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 500, "title": "Named under a closing keyword",
   "body": "A merged PR body names this issue under a Closes keyword, so GitHub already handled it and a still-open copy is an anomaly.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 600, "title": "Named by both arms of detector 1",
   "body": "Named in a merged PR title parenthetical and again in that same PR body, so both arms of detector one see it.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 700, "title": "Named only inside template boilerplate",
   "body": "Named only inside an HTML comment carried over from the PR template, which is boilerplate rather than any author reference.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 817, "title": "Keyword inside a DOUBLE-backtick code span",
   "state": "OPEN", "body": "A merged PR writes the convention for this issue in double backticks, which is the form the detector's own docstring used and the one a span regex mis-pairs as an empty span."},
  {"number": 801, "title": "Keyword inside a fenced code block",
   "body": "A merged PR shows a Closes line for this issue inside a fenced code block, which is an illustration and not GitHub closing anything.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 803, "title": "Keyword inside an inline code span",
   "body": "A merged PR writes the convention for this issue in backticks, which is the form this repo's own docs and PR template both model.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 805, "title": "Keyword inside a quotation",
   "body": "A merged PR quotes somebody else's old body carrying a Fixes line for this issue, which is reporting text rather than closing it.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 807, "title": "Keyword separated from the ref by blank lines",
   "body": "A merged PR carries a Resolved heading two lines above this bare reference, which GitHub does not read as a closing keyword at all.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 809, "title": "Named again after a genuine closing keyword",
   "body": "A merged PR closes this issue on one line and then mentions the same number again later, which a body-global number set would swallow.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 811, "title": "First of two swallowed by a stray comment opener",
   "body": "A merged PR names this issue after a stray HTML comment opener whose closer is the PR template's, which used to delete the text between.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 813, "title": "Second of two swallowed by a stray comment opener",
   "body": "Named in the same swallowed span as its sibling, so the failure silences every issue a PR named at once rather than only one of them.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 815, "title": "Named inside an oversized HTML comment",
   "body": "Named inside an HTML comment past the strip's span cap, so the strip is refused and the reference stays visible with the refusal marked.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 7,   "title": "The hex-colour decoy",
   "body": "A merged PR body contains the hex colour 7A3FE4, which an unbounded ref regex reads as a reference to this issue number seven.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"},
  {"number": 951, "title": "The cross-repo decoy",
   "body": "A merged PR body names another repository's issue with an owner/repo prefix, which an unbounded ref regex attributes to this repo.",
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"}
]
JSON

# The merged PRs. #328's title is the REAL shape of the bug: a conventional
# commit whose only parentheses hold a scope, never an issue ref — GitHub puts
# "(#328)" on the squash commit, which this pull never sees.
cat >"$MOCK_PRS" <<'JSON'
[
  {"number": 401, "title": "fix: the ordinary thing (#400)",
   "body": "Straightforward fix. This body names no issue at all.",
   "mergedAt": "2026-08-10T00:00:00Z"},
  {"number": 193, "title": "docs: reconcile both homes (#190) (#189)",
   "body": "Hand-written compound parenthetical in the title; the body names nothing.",
   "mergedAt": "2026-08-12T00:00:00Z"},
  {"number": 328, "title": "fix(setup-deps): mint app tokens with client-id, not the deprecated app-id",
   "body": "The templates already said client-id; this repairs the docs that still said app-id.\n\nSee #316 for the original report.",
   "mergedAt": "2026-09-04T00:00:00Z"},
  {"number": 501, "title": "feat: land the thing",
   "body": "Adds the thing.\n\nCloses #500\n",
   "mergedAt": "2026-08-14T00:00:00Z"},
  {"number": 601, "title": "fix: both arms at once (#600)",
   "body": "Follow-up to the work tracked in #600.",
   "mergedAt": "2026-08-16T00:00:00Z"},
  {"number": 701, "title": "chore: template boilerplate left in the body",
   "body": "Real work; this body names no issue of its own.\n\n<!--\nClosing an issue needs a literal `Closes #123` on its own line, one per issue.\nSee #700 for the convention.\n-->\n",
   "mergedAt": "2026-08-18T00:00:00Z"},
  {"number": 900, "title": "docs: every keyword form that must NOT suppress",
   "body": "Roll-up of the shapes GitHub does not honour as closing refs.\n\n```text\nCloses #801\n```\n\nOur docs write the convention as `Closes #803`, in backticks.\n\nAnd sometimes as ``Closes #817``, in DOUBLE backticks — the form a span regex mis-pairs.\n\n> The old body said: Fixes #805\n\n## Resolved\n\n#807\n\nCloses #809 — and #809 turns up again later in this very sentence.\n",
   "mergedAt": "2026-08-22T00:00:00Z"},
  {"number": 910, "title": "fix: a stray comment opener above the template block",
   "body": "Real work.\n\n<!-- stray opener, left behind by an edit and never closed\n\nThis lands the behaviour for #811 and #813.\n\n<!--\nClosing an issue needs a literal `Closes #123` on its own line, one per issue.\n-->\n",
   "mergedAt": "2026-08-24T00:00:00Z"},
  {"number": 930, "title": "chore: strings that only LOOK like refs to this repo",
   "body": "Ports the change that landed as Sassy-Dog/velovate#951 over there.\n\nThe badge colour is #7A3FE4, which is deliberately NOT a canonical taxonomy colour — test-label-taxonomy.sh fails on any of those found outside their home (issue #167).\n",
   "mergedAt": "2026-08-28T00:00:00Z"}
]
JSON

# The oversized-comment PR is GENERATED rather than typed: its whole point is a
# comment past COMMENT_MAX_SPAN (2000 chars), which does not belong inline in a
# fixture a human has to read.
python3 - "$MOCK_PRS" <<'PYFIXTURE'
import json, sys
path = sys.argv[1]
prs = json.load(open(path))
filler = "padding that pushes this comment past the strip's span cap. " * 40
prs.append({
    "number": 920,
    "title": "chore: one enormous HTML comment in the body",
    "body": "Real work.\n\n<!--\n" + filler + "\nSee #815 for the convention.\n-->\n",
    "mergedAt": "2026-08-26T00:00:00Z",
})
json.dump(prs, open(path, "w"), indent=2)
PYFIXTURE

# Derived rather than hard-coded: the truncation rows below need a limit that
# lands exactly ON the fixture's size, and a hard-coded one silently stops
# testing truncation the moment somebody adds a fixture issue.
ALL_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$MOCK_ALL_ISSUES")

# --- helpers -----------------------------------------------------------------
# Both read the script's own output format: `=== <section> ===` headers, each
# followed by one JSON document.
section() {  # section <name> <output-file>
    python3 - "$1" "$2" <<'PY'
import sys
name, path = sys.argv[1], sys.argv[2]
want, grab, out = "=== %s ===" % name, False, []
with open(path) as fh:
    for line in fh:
        if line.startswith("=== ") and line.rstrip().endswith(" ==="):
            grab = line.strip() == want
            continue
        if grab:
            out.append(line)
sys.stdout.write("".join(out))
PY
}

# q evaluates a python expression over the parsed JSON on stdin. `eval` is safe
# here: every expression is a literal written in this file, never input — the
# JSON goes through json.load, not through eval.
q() {  # q <python-expression-over-d>  < json
    python3 -c 'import json,sys; d = json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"
}

has_parent() {  # has_parent <issue-number> <tracking-parent-complete json>
    [ "$(q "$1 in [p['issue'] for p in d['parents']]" <"$2")" = "True" ]
}

has_issue() {  # has_issue <issue-number> <shipped-but-still-open json>
    [ "$(q "$1 in [i['issue'] for i in d]" <"$2")" = "True" ]
}

run_stale() {  # run_stale <stdout> <stderr> [VAR=value ...]
    local out="$1" err="$2"; shift 2
    env PATH="$WORK/bin:$PATH" REPO="$MOCK_REPO" "$@" bash "$SCRIPT" >"$out" 2>"$err"
}

# mutate_run <sed-program> <label> — run a copy of the script with ONE property
# removed, leaving its shipped-but-still-open section in $WORK/<label>.json.
# A mutation that changes nothing means its target was renamed or reshaped, so
# the proof resting on it has silently gone vacuous: that is itself a failure,
# never a skip.
mutate_run() {
    local prog="$1" label="$2"
    sed "$prog" "$SCRIPT" >"$WORK/$label.sh"
    if cmp -s "$SCRIPT" "$WORK/$label.sh"; then
        bad "mutation '$label' changed nothing — its target was renamed or reshaped; re-point this proof"
        return 1
    fi
    # THE MUTANT MUST RUN. Its status and output were discarded, so a mutation
    # that left invalid Python satisfied every purely-negative assertion — a row
    # asserting only `! has_issue 811 && ! has_issue 813` passes just as well
    # when the program crashed and printed nothing. Swept across all ten rows
    # with a universally-crashing mutant, nine reddened and one stayed green.
    # `cmp -s` above catches a RENAMED target; this catches a reshaped one.
    local mrc=0
    env PATH="$WORK/bin:$PATH" REPO="$MOCK_REPO" bash "$WORK/$label.sh" \
        >"$WORK/$label.out" 2>"$WORK/$label.err" || mrc=$?
    if [ "$mrc" -ne 0 ]; then
        bad "mutation '$label' did not complete (exit $mrc) — a crashed mutant satisfies a negative assertion without proving anything: $(head -c 160 "$WORK/$label.err")"
        return 1
    fi
    if [ ! -s "$WORK/$label.out" ]; then
        bad "mutation '$label' produced no output — its verdict would come from absence, not from the decision under test"
        return 1
    fi
    section shipped-but-still-open "$WORK/$label.out" >"$WORK/$label.json"
    section tracking-parent-complete "$WORK/$label.out" >"$WORK/$label.tpc.json"
}

# --- 1. the happy path -------------------------------------------------------
rc=0
run_stale "$WORK/run1.out" "$WORK/run1.err" || rc=$?
if [ "$rc" -eq 0 ]; then
    ok "a normal run exits 0"
else
    bad "a normal run exited $rc: $(cat "$WORK/run1.err")"
fi

section tracking-parent-complete "$WORK/run1.out" >"$WORK/tpc1.json"
parents=$(q '[p["issue"] for p in d["parents"]]' <"$WORK/tpc1.json")

if [ "$parents" = "[283]" ]; then
    ok "the complete parent #283 is the only hit (got $parents)"
else
    bad "expected exactly [283], got $parents"
fi

if [ "$(q 'd["parents"][0]["children"] if d["parents"] else None' <"$WORK/tpc1.json")" = "[286, 287]" ] \
   && [ "$(q 'd["parents"][0]["child_count"] if d["parents"] else None' <"$WORK/tpc1.json")" = "2" ]; then
    ok "the hit names its closed children (#286 #287) and their count"
else
    bad "the hit did not list its children correctly"
fi

# The negative cases, stated one at a time: a detector that reported everything
# would sail through an "is #283 present" check on its own.
if has_parent 341 "$WORK/tpc1.json"; then
    bad "#341 reported despite its open child #346 — the negative case failed"
else
    ok "#341 (one child still OPEN) is NOT reported"
fi

if has_parent 125 "$WORK/tpc1.json"; then
    bad "#125 reported although the parent is itself CLOSED"
else
    ok "#125 (parent already closed) is NOT reported"
fi

if has_parent 28 "$WORK/tpc1.json"; then
    bad "#28 claimed #283's children — the prefix guard failed"
else
    ok "prefix guard: #28 does not claim a child of #283"
fi

# --- 2. the prefix fixture is live (mutation proof) --------------------------
# A guard nothing can trip is not a guard. Strip the "next character is not a
# digit" requirement from the regex — the exact property the acceptance
# criterion names — and this same fixture must now hand #28 the finished
# children of #283. If the mutant comes back clean, the decoy has stopped
# exercising anything and the assertion above is decoration.
sed '/^PART_OF_RE = /{ s/(?!\[0-9\])//; s/(\\d+)/(\\d\\d)/; }' "$SCRIPT" >"$WORK/mutant.sh"
if cmp -s "$SCRIPT" "$WORK/mutant.sh"; then
    bad "the mutation changed nothing — PART_OF_RE was renamed or reshaped; re-point this proof"
else
    env PATH="$WORK/bin:$PATH" REPO="$MOCK_REPO" bash "$WORK/mutant.sh" \
        >"$WORK/mutant.out" 2>/dev/null
    section tracking-parent-complete "$WORK/mutant.out" >"$WORK/tpc-mutant.json"
    if has_parent 28 "$WORK/tpc-mutant.json"; then
        ok "the unguarded regex DOES report #28 on this fixture — the decoy is live"
    else
        bad "the unguarded regex reported $(q '[p["issue"] for p in d["parents"]]' <"$WORK/tpc-mutant.json") — the fixture no longer exercises the prefix collision"
    fi
fi

# --- 3. truncation is reported, not swallowed --------------------------------
if [ "$(q 'd["truncated"]' <"$WORK/tpc1.json")" = "False" ] \
   && [ "$(q 'd["limit"]' <"$WORK/tpc1.json")" = "500" ] \
   && [ "$(q 'd["scanned"]' <"$WORK/tpc1.json")" = "$ALL_COUNT" ]; then
    ok "an under-ceiling pull reports truncated=false at the default limit of 500"
else
    bad "the under-ceiling pull mis-reported: $(cat "$WORK/tpc1.json")"
fi

# ALL_LIMIT set to the fixture's own size is a pull that came back exactly AT
# the ceiling — indistinguishable, from inside, from a repo holding more.
rc=0
run_stale "$WORK/run2.out" "$WORK/run2.err" ALL_LIMIT="$ALL_COUNT" || rc=$?
section tracking-parent-complete "$WORK/run2.out" >"$WORK/tpc2.json"
if [ "$rc" -eq 0 ] \
   && [ "$(q 'd["truncated"]' <"$WORK/tpc2.json")" = "True" ] \
   && [ "$(q 'd["limit"]' <"$WORK/tpc2.json")" = "$ALL_COUNT" ]; then
    ok "a pull returning AT the ceiling reports truncated=true"
else
    bad "a pull at the ceiling did not report truncated=true: $(cat "$WORK/tpc2.json")"
fi

if grep -q 'TRUNCATED' "$WORK/run2.err"; then
    ok "truncation is also announced on stderr (an empty list never reads as clean)"
else
    bad "no stderr warning for a truncated pull: $(cat "$WORK/run2.err")"
fi

# --- 4. detector 1: both arms, both directions (issue #337) ------------------
section shipped-but-still-open "$WORK/run1.out" >"$WORK/shipped.json"

# The whole set at once, so an arm that starts over-firing shows up here rather
# than passing every single-issue check below.
expected_hits="[400, 189, 190, 316, 600, 817, 801, 803, 805, 807, 809, 811, 813, 815]"
if [ "$(q '[i["issue"] for i in d]' <"$WORK/shipped.json")" = "$expected_hits" ]; then
    ok "detector 1 reports exactly the expected hit set, and nothing else"
else
    bad "detector 1's hit set is wrong: $(q '[i["issue"] for i in d]' <"$WORK/shipped.json")"
fi

# --- 4a. the TITLE arm survives the addition ---------------------------------
if has_issue 400 "$WORK/shipped.json"; then
    ok "title arm: a simple '(#400)' parenthetical still matches"
else
    bad "title arm regressed on the simple form: $(cat "$WORK/shipped.json")"
fi

if has_issue 189 "$WORK/shipped.json" && has_issue 190 "$WORK/shipped.json"; then
    ok "title arm: the compound '(#190) (#189)' still yields BOTH — a body scan would miss these"
else
    bad "title arm regressed on the compound form: $(cat "$WORK/shipped.json")"
fi

# --- 4b. the BODY arm fires ---------------------------------------------------
# #328's title carries no ref; only its body says "See #316". Before #337 this
# returned [] and read as verified.
if has_issue 316 "$WORK/shipped.json"; then
    ok "body arm: #316 is flagged from PR #328's body ref with no closing keyword"
else
    bad "body arm did not flag #316 — the live miss of #337 is back: $(cat "$WORK/shipped.json")"
fi

# --- 4c. the BODY arm discriminates ------------------------------------------
# Without these two, "it fires" is satisfied just as well by firing on
# everything, and every merged PR would produce a finding.
if has_issue 500 "$WORK/shipped.json"; then
    bad "#500 flagged although PR #501's body carries 'Closes #500' — GitHub already closes those"
else
    ok "a body ref UNDER a closing keyword (#500) is NOT a finding"
fi

if has_issue 700 "$WORK/shipped.json"; then
    bad "#700 flagged from inside a leftover template HTML comment — that fires on every PR"
else
    ok "a body ref inside an HTML comment (#700) is NOT a finding"
fi

# --- 4d. findings name the arm that matched ----------------------------------
via=$(q '" ".join("%d:%s" % (i["issue"], "/".join(p["matched_via"] for p in i["merged_prs"])) for i in d)' <"$WORK/shipped.json")
expected_via="400:title 189:title 190:title 316:body 600:title+body"
expected_via="$expected_via 817:body 801:body 803:body 805:body 807:body 809:body"
expected_via="$expected_via 811:body 813:body 815:body"
if [ "$via" = "$expected_via" ]; then
    ok "every finding names its arm, and a both-arms hit merges to one 'title+body' entry"
else
    bad "matched_via is wrong: got '$via'"
fi

# --- 4g. the suppression is NARROW: only GitHub's own closing semantics -------
# The keyword exclusion is the one thing that can turn a finding back into
# silence, so every form GitHub does NOT honour as a close must still flag.
# Each is a distinct over-suppression bug, so each gets its own row: a single
# combined check would go green again the moment one form regressed.
for probe in \
    "801|a Closes line inside a FENCED CODE BLOCK" \
    "803|a backticked \`Closes #N\` in prose — the form this repo's own docs model" \
    "817|a DOUBLE-backticked \`\`Closes #N\`\` span — mis-paired as empty by a regex, masked by the scanner" \
    "805|a Fixes line inside a QUOTATION of somebody else's text" \
    "807|a keyword separated from the ref by BLANK LINES (\\s must not span newlines)" \
    "809|a SECOND mention after a genuine close — suppression is positional, not body-global"
do
    n="${probe%%|*}"; what="${probe#*|}"
    if has_issue "$n" "$WORK/shipped.json"; then
        ok "still flags #$n: $what does not suppress"
    else
        bad "#$n was SUPPRESSED by $what — that is a silent false negative"
    fi
done

# --- 4h. a stray comment opener cannot swallow the body ----------------------
# `<!--` anywhere plus the template's trailing `-->` used to delete everything
# between them, silencing every issue the PR named at once and leaving no trace,
# since an HTML comment renders as nothing.
if has_issue 811 "$WORK/shipped.json" && has_issue 813 "$WORK/shipped.json"; then
    ok "a stray '<!--' above the template block does NOT swallow #811 and #813"
else
    bad "the stray comment opener swallowed the body — #811/#813 lost: $(cat "$WORK/shipped.json")"
fi

# --- 4i. an oversized comment is REFUSED, and the refusal is visible ---------
# Refusing silently would be the same false clean by a longer route, so the
# finding carries the marker and stderr carries the warning.
if has_issue 815 "$WORK/shipped.json"; then
    ok "a comment past the span cap is left in place, so #815 stays visible"
else
    bad "#815 was stripped away by an over-long comment: $(cat "$WORK/shipped.json")"
fi

if [ "$(q '[i["issue"] for i in d if any(p.get("comment_strip_refused") for p in i["merged_prs"])]' <"$WORK/shipped.json")" = "[815]" ]; then
    ok "the finding carries 'comment_strip_refused' — the refusal is on the record"
else
    bad "no finding marks the refused comment strip: $(cat "$WORK/shipped.json")"
fi

if grep -q 'refused to strip an HTML comment' "$WORK/run1.err"; then
    ok "the refusal is also announced on stderr, naming the PR"
else
    bad "no stderr warning for the refused comment strip: $(cat "$WORK/run1.err")"
fi

# --- 4e. all three body-arm properties are mutation-proved -------------------
# Each mutant removes exactly one property and the fixture must react. A row
# that only asserts the current behaviour cannot tell a live check from a
# decorative one.

# (i) neuter the body ref regex: #316 must vanish, and the title arm's #400 must
#     NOT — otherwise the mutation is proving the wrong thing.
if mutate_run '/^BODY_REF_RE = /s/#(/#(?!)(/' body-arm-off; then
    if ! has_issue 316 "$WORK/body-arm-off.json" && has_issue 400 "$WORK/body-arm-off.json"; then
        ok "reverting the body scan DROPS #316 while the title arm keeps #400 — the arm is live"
    else
        bad "the neutered body regex still reported $(q '[i["issue"] for i in d]' <"$WORK/body-arm-off.json") — this row proves nothing"
    fi
fi

# (ii) drop `body` from the merged-PR pull. The mock serves only the requested
#      fields, so this is the real production failure — the arm's input, gone —
#      rather than a rewrite of its logic.
if mutate_run 's/--json number,title,body,mergedAt/--json number,title,mergedAt/' no-body-field; then
    if ! has_issue 316 "$WORK/no-body-field.json" && has_issue 400 "$WORK/no-body-field.json"; then
        ok "dropping 'body' from the --json pull DROPS #316 — the field list cannot rot unnoticed"
    else
        bad "the pull without 'body' still reported $(q '[i["issue"] for i in d]' <"$WORK/no-body-field.json") — the mock is handing back a field gh would not have returned"
    fi
fi

# (iii) neuter the closing-keyword suppression: #500 must now appear. If it does
#       not, the suppression was never what kept it out and 4c is decoration.
if mutate_run 's/(?:close/(?!)(?:close/' keyword-off; then
    if has_issue 500 "$WORK/keyword-off.json"; then
        ok "without the closing-keyword suppression #500 DOES flag — the discrimination is live"
    else
        bad "#500 stayed unflagged with the keyword suppression removed — 4c is not testing the suppression"
    fi
fi

# (iv) neuter the HTML-comment strip: #700 must now appear.
if mutate_run '/^HTML_COMMENT_RE = /s/<!--/<!--NEVERMATCHES/' comment-strip-off; then
    if has_issue 700 "$WORK/comment-strip-off.json"; then
        ok "without the HTML-comment strip #700 DOES flag — the strip is live"
    else
        bad "#700 stayed unflagged with the comment strip removed — 4c is not testing the strip"
    fi
fi

# (v) drop the nested-opener guard, restoring the naive `<!--.*?-->`: the stray
#     opener must once again swallow #811 and #813. Without this the fixture in
#     4h proves nothing — a body with no stray opener passes it just as well.
if mutate_run '/^HTML_COMMENT_RE = /s/(?:(?!<!--)\.)/./' swallow-guard-off; then
    if ! has_issue 811 "$WORK/swallow-guard-off.json" \
       && ! has_issue 813 "$WORK/swallow-guard-off.json"; then
        ok "the naive '<!--.*?-->' DOES swallow #811 and #813 — 4h's fixture is live"
    else
        bad "the naive comment regex did not swallow the body — 4h has stopped exercising the stray opener"
    fi
fi

# (vi) make the keyword scan read the RAW body again — no code/quote masking.
#      Every form in 4g that lives in code or a quotation must vanish. #807 and
#      #809 survive it, because those two are the separator and positional bugs
#      rather than the masking one, and a mutation that killed all five at once
#      would not tell the three defects apart.
if mutate_run 's/^    keyword_text = mask(mask_code(body).*/    keyword_text = body/' mask-off; then
    if ! has_issue 801 "$WORK/mask-off.json" \
       && ! has_issue 803 "$WORK/mask-off.json" \
       && ! has_issue 805 "$WORK/mask-off.json" \
       && has_issue 807 "$WORK/mask-off.json" \
       && has_issue 809 "$WORK/mask-off.json"; then
        ok "unmasked prose DOES suppress #801/#803/#805 and leaves #807/#809 — the masking is live and targeted"
    else
        bad "the unmasked keyword scan reported $(q '[i["issue"] for i in d]' <"$WORK/mask-off.json") — 4g's code/quote rows prove nothing"
    fi
fi

# (vi-b) restore the SPAN REGEX that paired a double backtick as an empty span.
#        `mask_code_spans` replaced `re.compile(r'`[^`\n]*`')`, which matched
#        the leading `` of ``like this`` as a zero-length span and left the
#        content unmasked — so a `<!--` inside one reached the comment probe and
#        swallowed the whole body. #817 carries the double-backtick form; #801's
#        single-backtick form must be unaffected, which is what separates this
#        mutant from (vi).
if mutate_run 's|^    return mask_code_spans(mask_fences(text))|    return re.sub(r"`[^`\\n]*`", lambda m: blank(m.group(0)), mask_fences(text))|' span-regex; then
    if ! has_issue 817 "$WORK/span-regex.json" && has_issue 801 "$WORK/span-regex.json"; then
        ok "the old span regex mis-pairs a DOUBLE backtick, so #817's keyword goes UNMASKED and wrongly suppresses — while #801's fence still masks, isolating the span scanner"
    else
        bad "restoring the span regex reported $(q '[i[\"issue\"] for i in d]' <"$WORK/span-regex.json") — the double-backtick row proves nothing"
    fi
fi

# (vii) restore the `\s` separator, which spans newlines: #807 must vanish while
#       the code/quote form stays, isolating the separator from the masking.
#       The separator is replaced by whole line, never by matching `[ \t]` —
#       GNU sed reads `\t` in a BRE as a tab and BSD sed as a literal `t`, so a
#       pattern containing it would mutate on one runner and no-op on the other.
if mutate_run '/^KEYWORD_SEP = /s/.*/KEYWORD_SEP = r"[:\\s]*"/' separator-off; then
    if ! has_issue 807 "$WORK/separator-off.json" && has_issue 801 "$WORK/separator-off.json"; then
        ok "a newline-spanning separator DOES suppress #807 — the same-line rule is live"
    else
        bad "the newline-spanning separator reported $(q '[i["issue"] for i in d]' <"$WORK/separator-off.json") — 4g's blank-line row proves nothing"
    fi
fi

# (viii) go back to a body-global number SET rather than the governed offsets:
#        #809's second mention must vanish while the masked forms stay put.
if mutate_run 's/{m\.start(1) for m in CLOSING_KEYWORD_RE/{m.group(1) for m in CLOSING_KEYWORD_RE/; s/if m\.start(1) in governed:/if m.group(1) in governed:/' positional-off; then
    if ! has_issue 809 "$WORK/positional-off.json" && has_issue 801 "$WORK/positional-off.json"; then
        ok "a body-global number set DOES swallow #809's second mention — positional suppression is live"
    else
        bad "the body-global mutant reported $(q '[i["issue"] for i in d]' <"$WORK/positional-off.json") — 4g's #809 row proves nothing"
    fi
fi

# --- 4l. a body ref needs boundaries -----------------------------------------
# `#(\d+)` with nothing either side reads `owner/repo#951` as THIS repo's #951
# and the hex colour `#7A3FE4` as issue #7. Both decoys sit in PR #930's body.
if has_issue 123 "$WORK/shipped.json" || has_issue 7 "$WORK/shipped.json"; then
    bad "a cross-repo ref or a hex colour was read as this repo's issue: $(q '[i["issue"] for i in d]' <"$WORK/shipped.json")"
else
    ok "'Sassy-Dog/velovate#951' and '#7A3FE4' are NOT read as refs to #951 and #7"
fi

if mutate_run '/^BODY_REF_RE = /s/.*/BODY_REF_RE = re.compile(r"#(\\d+)")/' unbounded-refs; then
    if has_issue 951 "$WORK/unbounded-refs.json" && has_issue 7 "$WORK/unbounded-refs.json"; then
        ok "the unbounded regex DOES claim #951 and #7 — the boundaries are live"
    else
        bad "the unbounded regex claimed neither decoy — 4l's fixture exercises nothing"
    fi
fi

# --- 4j. detector 3's `body` dependency is pinned too -------------------------
# `body` is the sole input to detectors 2 AND 3, not just to the new body arm.
# Now that the mock projects `issue list` as well, losing it from the all-state
# pull reddens here — before that projection existed this mutation left every
# row green while `PART_OF_RE` scanned "" in production, `parent_to_children`
# stayed {} and tracking-parent-complete returned [] forever: exactly the #198
# bug this whole gate was written to prevent.
if mutate_run 's/--json number,title,state,body/--json number,title,state/' no-all-body; then
    if [ "$(q '[p["issue"] for p in d["parents"]]' <"$WORK/no-all-body.tpc.json")" = "[]" ]; then
        ok "dropping 'body' from the all-state pull DROPS #283 — detector 3's input is pinned"
    else
        bad "detector 3 still reported $(q '[p["issue"] for p in d["parents"]]' <"$WORK/no-all-body.tpc.json") without 'body' — the mock is serving a field gh would not have returned"
    fi
fi

# The open pull's `body` needs no separate mutation: strip it and every issue
# reads as a zero-length body, so 4f's stub-body row fails on its own.

# --- 4k. a FAILED pull is never a clean answer -------------------------------
# Three empty sections and exit 0 is byte-identical to a healthy repo, so an
# expired token or a rate limit must not be able to render as "nothing found".
rc=0
run_stale "$WORK/run3.out" "$WORK/run3.err" MOCK_FAIL="pr list" || rc=$?
if [ "$rc" -eq 10 ]; then
    ok "a failed pull exits 10 (UNKNOWN), not 0"
else
    bad "a failed pull exited $rc — a degraded run is reading as clean"
fi

if [ ! -s "$WORK/run3.out" ] && grep -q 'UNKNOWN, not clean' "$WORK/run3.err"; then
    ok "it prints no sections at all, and says on stderr that the run is UNKNOWN"
else
    bad "a failed pull still printed sections or gave no reason: $(cat "$WORK/run3.err")"
fi

if grep -q 'Bad credentials' "$WORK/run3.err"; then
    ok "gh's own reason is relayed, so the reader is not sent back to guessing"
else
    bad "gh's stderr was swallowed: $(cat "$WORK/run3.err")"
fi

# --- 4f. detector 2 still works ----------------------------------------------
section stub-body "$WORK/run1.out" >"$WORK/stub.json"
if [ "$(q '[i["issue"] for i in d]' <"$WORK/stub.json")" = "[28, 341]" ]; then
    ok "detector 2 (stub-body) still flags the short bodies"
else
    bad "detector 2 regressed: $(cat "$WORK/stub.json")"
fi

# --- 4l. the exit-code contract itself ---------------------------------------
# EVERY other row presets REPO, so the resolution path this gate's script
# rewrote never executed here: reverting it to the pre-change one-liner kept the
# whole gate green while that copy exited 1 (not a repo) and 127 (gh missing),
# both silently — the exact measurements the script's own header records as the
# bug. These three rows are the only thing that runs it, and (c) proves the
# mock's `repo view` arm is reachable rather than dead code.
ec_out="$WORK/ec.out"; ec_err="$WORK/ec.err"

# (a) gh missing entirely. The condition is CONSTRUCTED rather than borrowed
#     from the host's PATH layout: a directory of symlinks to the tools this
#     script needs, with no gh in it. Keying on `/usr/bin:/bin` was
#     host-dependent and went red on the CI runner, where gh ships in /usr/bin
#     — a legitimately different layout must not fail the build.
NOGH="$WORK/nogh"
mkdir -p "$NOGH"
nogh_missing=""
for t in bash sh python3 mktemp sed tr grep cat wc head sort awk date rm env; do
    p="$(command -v "$t" 2>/dev/null)" || { nogh_missing="$nogh_missing $t"; continue; }
    ln -sf "$p" "$NOGH/$t"
done
if [ -n "$nogh_missing" ]; then
    bad "cannot build a gh-free PATH: missing$nogh_missing — the gh-missing row did not run, which is a gap, not a pass"
elif PATH="$NOGH" command -v gh >/dev/null 2>&1; then
    bad "the constructed gh-free PATH still resolves gh — the gh-missing row would prove nothing"
else
    ec_rc=0
    env -u REPO PATH="$NOGH" bash "$SCRIPT" >"$ec_out" 2>"$ec_err" || ec_rc=$?
    if [ "$ec_rc" = "10" ] && grep -q 'gh not installed' "$ec_err"; then
        ok "gh missing exits 10 and names the cause"
    else
        bad "gh missing exited $ec_rc (want 10): $(head -c 140 "$ec_err")"
    fi
fi

# (b) REPO unset and `gh repo view` fails — the transport case.
ec_rc=0
env -u REPO PATH="$WORK/bin:$PATH" MOCK_FAIL_REPO_VIEW=1 bash "$SCRIPT" >"$ec_out" 2>"$ec_err" || ec_rc=$?
if [ "$ec_rc" = "10" ] && grep -q 'could not resolve the repo' "$ec_err"; then
    ok "a failed repo resolution exits 10 and relays gh's own words"
else
    bad "a failed repo resolution exited $ec_rc (want 10): $(head -c 140 "$ec_err")"
fi

# (c) REPO unset and `gh repo view` WORKS. Without this, (a) and (b) could both
#     pass on a script that never resolves a repo at all.
ec_rc=0
env -u REPO PATH="$WORK/bin:$PATH" bash "$SCRIPT" >"$ec_out" 2>"$ec_err" || ec_rc=$?
if [ "$ec_rc" = "0" ]; then
    ok "…and with REPO unset but resolvable, the run completes normally"
else
    bad "REPO unset with a working repo view exited $ec_rc (want 0): $(head -c 200 "$ec_err")"
fi

# --- 5. read-only ------------------------------------------------------------
# The detector's whole contract is that a human closes. Nothing here may write.
if [ ! -s "$MOCK_WRITES" ]; then
    ok "the full run issued ZERO non-read gh calls — nothing closes, comments, or edits"
else
    bad "the run issued write calls: $(tr '\n' '; ' <"$MOCK_WRITES")"
fi

# --- 6. the pulls reach python as PATHS, not as argv payloads ----------------
# Adding `body` to the merged-PR pull (issue #337) pushed the three documents
# past ARG_MAX on a real repo: `python3: Argument list too long`, exit 126, the
# detector's entire output gone — and the all-state pull was already close at
# ALL_LIMIT=500. THIS FIXTURE, AS SIZED, does not reproduce it — its payload is
# a few kB, so every row above stays green on a script that is broken on every
# repo it is actually pointed at. The earlier wording said the fixture CANNOT
# reproduce it; that is false. 20 PRs carrying 60000-char bodies trip the
# pre-fix script to exit 126, on macOS and on Linux's 128 KB per-argument cap.
# A behavioural row is the stronger pin and is deliberately NOT taken here: it
# would add ~1.2 MB of fixture, and its build cost, to a gate on preflight's
# critical path. That is a decision, recorded — not a limit of the fixture.
# ONE pattern, used by both the check and its own liveness proof. Re-typing it
# as a second literal would let a neutered pattern here keep every row green,
# INCLUDING the row claiming the guard is live.
ARGV_SHAPE_RE='json.loads(sys.argv\['

if grep -q "$ARGV_SHAPE_RE" "$SCRIPT"; then
    bad "a pull is parsed straight off argv — that is the ARG_MAX regression of #337"
else
    ok "no pull is parsed from argv"
fi

if grep -q 'with open(sys.argv\[' "$SCRIPT"; then
    ok "the pulls reach python as file paths (ARG_MAX-safe)"
else
    bad "the pulls no longer reach python as file paths — re-point this proof at the current source"
fi

# The guard's own liveness: a grep that can never match is not a guard.
printf 'issues = json.loads(sys.argv[1])\n' >"$WORK/argv-shape.txt"
if grep -q "$ARGV_SHAPE_RE" "$WORK/argv-shape.txt"; then
    ok "the argv-shape guard DOES recognise the banned form"
else
    bad "the argv-shape guard cannot match the form it bans — the row above is decoration"
fi

# --- 7. the all-state pull passes its own --limit ----------------------------
# Also source-level, and for the same reason as section 6: this fixture holds
# fewer issues than gh's default page of 30, so dropping `--limit "$ALL_LIMIT"`
# changes nothing here while production silently pages at 30 against an
# ALL_LIMIT of 500 — `truncated` then computes false forever and detector 3's
# "unknown is not clean" guarantee is gone with it.
# ANCHORED TO THE ALL-STATE PULL'S OWN COMMAND. A bare `--limit "$ALL_LIMIT"`
# grep is satisfiable while the property is false: moving the flag onto the
# OPEN-issues pull kept this row green, message and all. The fixture cannot
# see it either, so this grep is the only protection detector 3's truncation
# guarantee has.
ALL_PULL_RE='issue list --repo "\$REPO" --state all --limit "\$ALL_LIMIT"'
# Comment lines are stripped first: a `# was: issue list --repo ... --limit
# "$ALL_LIMIT"` note left behind by whoever removed the flag satisfies a raw
# grep, which is the same free-floating weakness this row was written to end.
SCRIPT_LIVE="$WORK/script-live.sh"
sed 's/^[[:space:]]*#.*$//' "$SCRIPT" >"$SCRIPT_LIVE"
if grep -q -- "$ALL_PULL_RE" "$SCRIPT_LIVE"; then
    ok "the all-state pull itself carries --limit \"\$ALL_LIMIT\", so truncated= means something"
else
    bad "the all-state pull no longer carries --limit \"\$ALL_LIMIT\" on its own command — truncated= is now unfalsifiable"
fi
# LIVENESS: the pattern must not match a pull that lacks the flag, or the row
# above proves nothing. Same shape as the ARGV guard's own proof below.
if grep -q -- "$ALL_PULL_RE" <<<'issue list --repo "$REPO" --state all'; then
    bad "the all-state pull shape guard matches a command WITHOUT the flag — the row above is vacuous"
else
    ok "…and that shape guard does not match an all-state pull missing the flag"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "stale-issues tests: all pass" >&2
    exit 0
fi
echo "stale-issues tests: FAILURES above" >&2
exit 1
