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
# The mock also serves ONLY the fields `--json` asks for, because the fixture is
# otherwise dishonest: drop `body` from the script's pull and a mock that always
# hands back bodies keeps this gate green while production loses the arm.
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
#   - dropping `body` from the merged-PR `--json` pull drops #316 — the mock
#     projects the requested fields, so the field list cannot rot unnoticed
#   - every finding names the arm that matched (`matched_via`)
#   - the pulls reach python as file paths, never as argv payloads (source-level
#     — see the ARG_MAX note above; the fixture is far too small to show it)
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

case "$cmd $sub" in
    "issue list")
        state=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --state) state="${2:-}"; shift 2 ;;
                *)       shift ;;
            esac
        done
        case "$state" in
            open) cat "$MOCK_OPEN_ISSUES" ;;
            all)  cat "$MOCK_ALL_ISSUES" ;;
            *)    echo "mock gh: unhandled issue list --state '$state'" >&2; exit 1 ;;
        esac ;;
    "pr list")
        # Serve ONLY the fields --json asked for, exactly as gh does. This is
        # what keeps the fixture honest about detector 1's body arm: a mock that
        # always hands back `body` would keep the body rows green even after the
        # script stopped asking for it, and the real pull would return nothing
        # for the arm to read. The issue-list branch has no such field to lose,
        # so it does not need the same treatment.
        fields=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --json) fields="${2:-}"; shift 2 ;;
                *)      shift ;;
            esac
        done
        python3 - "$MOCK_PRS" "$fields" <<'PYPROJECT'
import json, sys
prs = json.load(open(sys.argv[1]))
want = [f for f in sys.argv[2].split(",") if f]
print(json.dumps([{k: v for k, v in pr.items() if k in want} for pr in prs]))
PYPROJECT
        ;;
    "repo view")
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
   "body": "Named only inside an HTML comment carried over from the PR template, which is boilerplate rather than any author reference."}
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
   "mergedAt": "2026-08-18T00:00:00Z"}
]
JSON

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
    env PATH="$WORK/bin:$PATH" REPO="$MOCK_REPO" bash "$WORK/$label.sh" \
        >"$WORK/$label.out" 2>/dev/null
    section shipped-but-still-open "$WORK/$label.out" >"$WORK/$label.json"
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
if [ "$(q '[i["issue"] for i in d]' <"$WORK/shipped.json")" = "[400, 189, 190, 316, 600]" ]; then
    ok "detector 1 reports exactly the five expected issues, and nothing else"
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
if [ "$via" = "400:title 189:title 190:title 316:body 600:title+body" ]; then
    ok "every finding names its arm, and a both-arms hit merges to one 'title+body' entry"
else
    bad "matched_via is wrong: got '$via'"
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

# --- 4f. detector 2 still works ----------------------------------------------
section stub-body "$WORK/run1.out" >"$WORK/stub.json"
if [ "$(q '[i["issue"] for i in d]' <"$WORK/stub.json")" = "[28, 341]" ]; then
    ok "detector 2 (stub-body) still flags the short bodies"
else
    bad "detector 2 regressed: $(cat "$WORK/stub.json")"
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
# ALL_LIMIT=500. THIS FIXTURE CANNOT REPRODUCE IT: its payload is a few kB, so
# every row above stays green on a script that is broken on every repo it is
# actually pointed at. Hence a source-level assertion.
if grep -q 'json.loads(sys.argv\[' "$SCRIPT"; then
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
if grep -q 'json.loads(sys.argv\[' "$WORK/argv-shape.txt"; then
    ok "the argv-shape guard DOES recognise the banned form"
else
    bad "the argv-shape guard cannot match the form it bans — the row above is decoration"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "stale-issues tests: all pass" >&2
    exit 0
fi
echo "stale-issues tests: FAILURES above" >&2
exit 1
