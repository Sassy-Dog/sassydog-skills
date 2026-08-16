#!/usr/bin/env bash
# test-stale-issues.sh — pins github-issues/scripts/stale-issues.sh, and in
# particular its third detector, `tracking-parent-complete` (issue #198).
#
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
#   - detectors 1 and 2 still work (this change added a pull and a section)
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
        cat "$MOCK_PRS" ;;
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
# #283  OPEN    complete parent: children #286, #287, both closed
# #341  OPEN    incomplete parent: #345 closed, #346 still OPEN
# #125  CLOSED  parent already reconciled: child #126 closed
# #28   OPEN    the prefix decoy — no children of its own. A parser that reads
#               `Part of #283` as "#28, then some digits" hands it #283's two
#               closed children and reports it complete.
# #400  OPEN    ordinary issue, shipped under a PR titled "(#400)"
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
   "body": "An ordinary issue with a body comfortably longer than the eighty-character stub floor."}
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
   "createdAt": "2026-08-01T00:00:00Z", "updatedAt": "2026-08-01T00:00:00Z"}
]
JSON

cat >"$MOCK_PRS" <<'JSON'
[
  {"number": 401, "title": "fix: the ordinary thing (#400)", "mergedAt": "2026-08-10T00:00:00Z"}
]
JSON

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

run_stale() {  # run_stale <stdout> <stderr> [VAR=value ...]
    local out="$1" err="$2"; shift 2
    env PATH="$WORK/bin:$PATH" REPO="$MOCK_REPO" "$@" bash "$SCRIPT" >"$out" 2>"$err"
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
   && [ "$(q 'd["scanned"]' <"$WORK/tpc1.json")" = "10" ]; then
    ok "an under-ceiling pull reports truncated=false at the default limit of 500"
else
    bad "the under-ceiling pull mis-reported: $(cat "$WORK/tpc1.json")"
fi

# The fixture holds 10 issues, so ALL_LIMIT=10 is a pull that came back exactly
# AT the ceiling — indistinguishable, from inside, from a repo holding more.
rc=0
run_stale "$WORK/run2.out" "$WORK/run2.err" ALL_LIMIT=10 || rc=$?
section tracking-parent-complete "$WORK/run2.out" >"$WORK/tpc2.json"
if [ "$rc" -eq 0 ] \
   && [ "$(q 'd["truncated"]' <"$WORK/tpc2.json")" = "True" ] \
   && [ "$(q 'd["limit"]' <"$WORK/tpc2.json")" = "10" ]; then
    ok "a pull returning AT the ceiling reports truncated=true"
else
    bad "a pull at the ceiling did not report truncated=true: $(cat "$WORK/tpc2.json")"
fi

if grep -q 'TRUNCATED' "$WORK/run2.err"; then
    ok "truncation is also announced on stderr (an empty list never reads as clean)"
else
    bad "no stderr warning for a truncated pull: $(cat "$WORK/run2.err")"
fi

# --- 4. detectors 1 and 2 still work -----------------------------------------
section shipped-but-still-open "$WORK/run1.out" >"$WORK/shipped.json"
if [ "$(q '[i["issue"] for i in d]' <"$WORK/shipped.json")" = "[400]" ]; then
    ok "detector 1 (shipped-but-still-open) still matches a PR-title parenthetical"
else
    bad "detector 1 regressed: $(cat "$WORK/shipped.json")"
fi

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

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "stale-issues tests: all pass" >&2
    exit 0
fi
echo "stale-issues tests: FAILURES above" >&2
exit 1
