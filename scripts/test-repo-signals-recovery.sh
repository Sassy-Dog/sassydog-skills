#!/usr/bin/env bash
# test-repo-signals-recovery.sh — pins how pull-repo-signals.sh answers
# `default_branch_ci`, and what a SURVIVING null is allowed to mean (issue #367).
#
# THE FAILURE. The puller took ONE unfiltered sample of the newest RUN_LIMIT
# workflow runs across ALL branches and derived a per-branch, per-event verdict
# from whatever happened to be in it. When that page held no push-class run on
# the default branch the verdict was null, and the cross-product sweep had
# nothing to rank. Measured against the live org on 2026-09-06, 5 of 15 repos
# returned null; re-measured on 2026-09-07 with the sweep's own baseline, 5 of
# 15 again. Every one of them had a perfectly good verdict available.
#
# It is silent in the way that matters most: null is well-formed JSON carrying
# no outcome, so a reader with no rule for it treats the repo as fine. That is
# precisely the read `scoring.md` refuses, and it is why this gate exists at all
# rather than a note in a doc.
#
# THE RECOVERY, and the half a later simplification will take out. When the
# first derivation yields null the puller issues ONE narrow re-query,
# `--branch <default_branch> --event push --limit 1`. Three things about that
# shape are settled and each reads like it could be relaxed:
#
#   1. `--event` is the load-bearing half and a larger RUN_LIMIT is NOT a
#      substitute. velovate had ZERO push-on-main runs in its newest 100 across
#      all branches — its most recent sat weeks back behind a wall of
#      `schedule` and `pull_request` runs — so no page size reaches it. Row
#      `recovery-query-shape` and the `noevent` mutant are what hold this: the
#      mock answers a branch-only query with the `schedule` run that actually
#      crowds a default branch, so dropping `--event` leaves the verdict null
#      exactly as it does live.
#   2. `push` alone, never `push,merge_group`. A merge_group run's head branch
#      is `gh-readonly-queue/<branch>/pr-<N>`, so it can never satisfy
#      `--branch <default_branch>`; adding it widens the query and recovers
#      nothing. Row `merge-group-cannot-satisfy-branch` proves the premise
#      against the derivation itself rather than restating it.
#   3. The recovery fires ONLY on a null first derivation. It is a per-repo
#      extra call, so an unconditional one taxes every healthy repo in the org
#      for nothing — `no-redundant-call` counts the calls rather than trusting
#      the condition to read correctly.
#
#   sassydog-routines#46 shipped this recovery as `{branch, status}` and it
#   recovered one repo of the two sampled; #47 added the event filter. The
#   intermediate mistake is exactly what point 1 refuses to let back in.
#
# ONE DEFINITION OF THE VERDICT. The rule lives in derive_default_branch_ci()
# and is applied to both queries. A second copy would drift silently, because
# nothing downstream can tell which query answered — section 3 asserts the code
# form of the push-class filter appears EXACTLY ONCE in the script, the same
# uniqueness shape test-scanning-states.sh uses for its P0 row and for the same
# reason: a presence check cannot catch a duplicate.
#
# THE STILL-NULL PATH IS THE POINT OF THE GATE. A recovery that works is easy
# to see; a null that survives it is not, and it is what the unknown state in
# `scoring.md` is built on. There are TWO of them and they demand different
# sentences from a report, so `default_branch_runs_seen` splits them:
# `still-null-empty` (0 — no such run was there to read) and
# `still-null-inflight` (non-zero — they are all still in flight). Collapsed
# into one bare null they read identically, and identical to green.
#
# A FAILED RECOVERY IS NOT AN ANSWER. `gh` degrades to `[]` here, and adopting
# that would report `runs_seen: 0` — "no such run exists" — for runs the sample
# watched go by. The first probe therefore stands; row
# `failed-recovery-keeps-probe` and the `overwriteonempty` mutant hold it.
#
# MUTATION PROOF. The matrix is a function of the script path, so it is re-run
# against seven mutated copies and the reach is DERIVED from the verdicts rather
# than asserted in prose: the recovery disabled, the recovery made
# unconditional, `--event push` dropped, `--event` widened to merge_group, the
# emitted runs_seen key removed, the branch check dropped from the shared
# derivation, and the empty-recovery guard removed. Every mutant must redden at
# least one row, and the rows no mutant reaches must equal the declared set —
# which holds exactly the one fixture-adequacy precondition, since a
# precondition is by construction not sensitive to the recovering code.
#
# Mock gh only: no repo, no network, no live org. jq is real and is fed real
# JSON, so the derivation under test is the shipped one.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-repo-signals-recovery.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-repo-signals-recovery: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPT="$REPO_ROOT/skills/whats-on-fire/scripts/pull-repo-signals.sh"
CLOUD="$REPO_ROOT/skills/whats-on-fire/references/cloud-fallback.md"
SCORING="$REPO_ROOT/skills/whats-on-fire/references/scoring.md"
for f in "$SCRIPT" "$CLOUD" "$SCORING"; do
    [ -f "$f" ] || { echo "test-repo-signals-recovery: $f not found" >&2; exit 1; }
done

WORK="$(mktemp -d)" || { echo "test-repo-signals-recovery: mktemp -d failed" >&2; exit 1; }
# Fail closed rather than continuing with an empty WORK: set -u does not fire on
# empty-but-set, and every path below would then resolve against /.
case "$WORK" in
    /*) : ;;
    *) echo "test-repo-signals-recovery: mktemp -d gave no absolute path ('$WORK')" >&2; exit 1 ;;
esac
[ -d "$WORK" ] || { echo "test-repo-signals-recovery: '$WORK' is not a directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

CALL_LOG="$WORK/calls.log"

fail=0
ok()  { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "repo-signals recovery tests (work: $WORK)" >&2

# --- the mock gh --------------------------------------------------------------
# Behaviour is driven by MOCK_MODE. Every invocation is appended to CALL_LOG,
# because the flags the recovery fires with ARE the finding — a gate that only
# read the emitted verdict would stay green against a query that recovered by
# luck (a mock generous enough to answer any shape).
#
# The two `run list` calls are told apart by --branch: the unfiltered sample
# carries none, the recovery carries one. A branch-only recovery (the #46 shape)
# is answered with the `schedule` run that actually crowds a default branch, so
# an --event-less query reproduces the live null instead of being waved through.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

printf '%s\n' "$*" >>"$CALL_LOG"

CROWDING='[{"conclusion":"failure","status":"completed","workflowName":"Nightly","headBranch":"main","url":"c1","createdAt":"2026-09-07T07:00:00Z","event":"schedule"}]'
MAIN_PUSH_GREEN='[{"conclusion":"success","status":"completed","workflowName":"CI","headBranch":"main","url":"r1","createdAt":"2026-09-07T06:00:00Z","event":"push"}]'
MAIN_PUSH_INFLIGHT='[{"conclusion":null,"status":"in_progress","workflowName":"CI","headBranch":"main","url":"r1","createdAt":"2026-09-07T06:00:00Z","event":"push"}]'

SAMPLE_CLEAN='[{"conclusion":"failure","status":"completed","workflowName":"CI","headBranch":"feature/x","url":"u1","createdAt":"2026-09-07T10:00:00Z","event":"push"},
 {"conclusion":"success","status":"completed","workflowName":"CI","headBranch":"main","url":"u2","createdAt":"2026-09-07T09:00:00Z","event":"push"},
 {"conclusion":"failure","status":"completed","workflowName":"Nightly","headBranch":"main","url":"u3","createdAt":"2026-09-07T08:00:00Z","event":"schedule"}]'

SAMPLE_CROWDED='[{"conclusion":"failure","status":"completed","workflowName":"Nightly","headBranch":"main","url":"u1","createdAt":"2026-09-07T10:00:00Z","event":"schedule"},
 {"conclusion":"success","status":"completed","workflowName":"CI","headBranch":"feature/y","url":"u2","createdAt":"2026-09-07T09:00:00Z","event":"pull_request"},
 {"conclusion":"success","status":"completed","workflowName":"Nightly","headBranch":"main","url":"u3","createdAt":"2026-09-07T08:00:00Z","event":"schedule"}]'

SAMPLE_MERGE_GROUP='[{"conclusion":"success","status":"completed","workflowName":"CI","headBranch":"gh-readonly-queue/main/pr-7","url":"u1","createdAt":"2026-09-07T10:00:00Z","event":"merge_group"}]'

SAMPLE_INFLIGHT_PUSH='[{"conclusion":null,"status":"in_progress","workflowName":"CI","headBranch":"main","url":"u1","createdAt":"2026-09-07T10:00:00Z","event":"push"},
 {"conclusion":"success","status":"completed","workflowName":"Nightly","headBranch":"main","url":"u2","createdAt":"2026-09-07T09:00:00Z","event":"schedule"}]'

cmd="${1:-}"; shift

case "$cmd" in
  auth) exit 0 ;;
  repo)
    printf '%s\n' '[{"name":"mock-repo","isArchived":false,"defaultBranchRef":{"name":"main"}}]'
    exit 0 ;;
  api)
    path="${1:-}"
    case "$path" in
      */dependabot/alerts*)
        echo '{"message":"Dependabot alerts are disabled for this repository."}' >&2; exit 1 ;;
      */code-scanning/alerts*)
        echo '{"message":"Advanced Security must be enabled for this repository to use code scanning."}' >&2; exit 1 ;;
      */secret-scanning/alerts*)
        echo '{"message":"Secret scanning is disabled on this repository."}' >&2; exit 1 ;;
      *) echo "mock gh: unhandled api path: $path" >&2; exit 1 ;;
    esac ;;
  run) : ;;
  *) echo "mock gh: unhandled command: $cmd" >&2; exit 1 ;;
esac

[ "${1:-}" = "list" ] || { echo "mock gh: unhandled run subcommand: ${1:-}" >&2; exit 1; }
shift

branch=""; event=""; prev=""
for a in "$@"; do
    case "$prev" in
        --branch|-b) branch="$a" ;;
        --event|-e)  event="$a" ;;
    esac
    prev="$a"
done

if [ -z "$branch" ]; then
    # The unfiltered sample.
    case "$MOCK_MODE" in
      clean)          printf '%s\n' "$SAMPLE_CLEAN" ;;
      recoverable|empty|inflight)
                      printf '%s\n' "$SAMPLE_CROWDED" ;;
      mergegroup)     printf '%s\n' "$SAMPLE_MERGE_GROUP" ;;
      recoveryfails)  printf '%s\n' "$SAMPLE_INFLIGHT_PUSH" ;;
      *) echo "mock gh: unknown MOCK_MODE: $MOCK_MODE" >&2; exit 1 ;;
    esac
    exit 0
fi

# The recovery. Without a push event filter this is the #46 shape, and what it
# gets back is what a default branch is actually crowded with.
case "$event" in
    *push*) : ;;
    *) printf '%s\n' "$CROWDING"; exit 0 ;;
esac

case "$MOCK_MODE" in
  # clean must never reach here; answering generously keeps the call-count row
  # the only one that reddens, so the finding is not smeared across the matrix.
  clean|recoverable) printf '%s\n' "$MAIN_PUSH_GREEN" ;;
  empty|mergegroup)  printf '%s\n' '[]' ;;
  inflight)          printf '%s\n' "$MAIN_PUSH_INFLIGHT" ;;
  recoveryfails)     echo '{"message":"HTTP 503"}' >&2; exit 1 ;;
  *) echo "mock gh: unknown MOCK_MODE: $MOCK_MODE" >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

# --- helpers ------------------------------------------------------------------
OUT=""
LOG=""

run_case() {  # 1: script path  2: MOCK_MODE  -> sets OUT (the repo object) and LOG
    : >"$CALL_LOG"
    OUT="$(MOCK_MODE="$2" CALL_LOG="$CALL_LOG" PATH="$WORK/bin:$PATH" ORG="mock-org" \
        bash "$1" 2>/dev/null | jq -c '.repos[0]' 2>/dev/null)"
    LOG="$(cat "$CALL_LOG" 2>/dev/null)"
}

# `printf` is the writer into every grep below: the value is already a shell
# variable, so it is bounded and fully written (test-pipefail-grep.sh).
field() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }
is()    { [ "$(field "$1")" = "$2" ]; }
has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if has "$1" "$2"; then return 1; fi; return 0; }
verdict() { if "$@"; then echo pass; else echo fail; fi; }

runlist_calls() { printf '%s\n' "$LOG" | grep -c '^run list'; }
recovery_call() { printf '%s\n' "$LOG" | awk '/^run list/ && /--branch/ { line = $0 } END { print line }'; }

# --- the matrix ---------------------------------------------------------------
# Emits one `<row-id><TAB>pass|fail` line per row. A function of the script path
# so the mutants below are scored by exactly this code.
matrix() {
    local s="$1"
    local rec

    run_case "$s" clean
    # The newest push in this sample is a FAILING one on a feature branch, so a
    # derivation that forgets the branch check reports the wrong verdict rather
    # than the same one.
    printf 'sample-verdict\t%s\n'    "$(verdict is '.default_branch_ci' success)"
    printf 'sample-runs-seen\t%s\n'  "$(verdict is '.default_branch_runs_seen' 1)"
    # Counted, not inferred from the condition reading correctly.
    printf 'no-redundant-call\t%s\n' "$(verdict test "$(runlist_calls)" = 1)"

    run_case "$s" recoverable
    # Fixture adequacy: the null below must come from the FILTER, not from an
    # empty page — otherwise every recovery row is trivially satisfiable.
    printf 'sample-adequate\t%s\n'     "$(verdict is '.runs_sampled' 3)"
    printf 'recovered-verdict\t%s\n'   "$(verdict is '.default_branch_ci' success)"
    printf 'recovered-runs-seen\t%s\n' "$(verdict is '.default_branch_runs_seen' 1)"
    rec="$(recovery_call)"
    if has "$rec" '--branch main' && has "$rec" '--event push' && has "$rec" '--limit 1'; then
        printf 'recovery-query-shape\tpass\n'
    else
        printf 'recovery-query-shape\tfail\n'
    fi
    # merge_group can never satisfy the branch filter, so it must not appear in
    # ANY call this repo made — widening the event list only costs API surface.
    printf 'recovery-never-merge-group\t%s\n' "$(verdict hasnt "$LOG" 'merge_group')"

    run_case "$s" empty
    if is '.default_branch_ci' null && is '.default_branch_runs_seen' 0; then
        printf 'still-null-empty\tpass\n'
    else
        printf 'still-null-empty\tfail\n'
    fi

    run_case "$s" inflight
    if is '.default_branch_ci' null && is '.default_branch_runs_seen' 1; then
        printf 'still-null-inflight\tpass\n'
    else
        printf 'still-null-inflight\tfail\n'
    fi

    run_case "$s" mergegroup
    if is '.default_branch_ci' null && is '.default_branch_runs_seen' 0; then
        printf 'merge-group-cannot-satisfy-branch\tpass\n'
    else
        printf 'merge-group-cannot-satisfy-branch\tfail\n'
    fi

    run_case "$s" recoveryfails
    if is '.default_branch_ci' null && is '.default_branch_runs_seen' 1; then
        printf 'failed-recovery-keeps-probe\tpass\n'
    else
        printf 'failed-recovery-keeps-probe\tfail\n'
    fi
}

# --- 1. behaviour -------------------------------------------------------------
echo "1. behaviour (skills/whats-on-fire/scripts/pull-repo-signals.sh)" >&2
BASELINE="$(matrix "$SCRIPT")"
while IFS="$(printf '\t')" read -r row res; do
    [ -z "$row" ] && continue
    if [ "$res" = "pass" ]; then ok "$row"; else bad "$row"; fi
done <<EOF
$BASELINE
EOF

# --- 2. mutation proof --------------------------------------------------------
echo "2. mutation proof" >&2

GATE_LINE='if [[ "$(jq -r '"'"'.ci'"'"' <<<"$db_ci")" == "null" ]]; then'
EVENT_LINE='--event push --limit 1'
KEY_LINE='default_branch_runs_seen: $db_ci.runs_seen,'
BRANCH_LINE='map(select(.headBranch == $branch'
EMPTY_GUARD_LINE='if [[ -n "$recovery" && "$recovery" != "[]" ]]; then'

mutate() {  # 1: out path  2: match substring  3: replacement line
    awk -v m="$2" -v r="$3" 'index($0, m) { print r; next } { print }' "$SCRIPT" >"$1"
}

# norecover: the pre-fix behaviour — whatever the unfiltered sample happened to hold.
mutate "$WORK/m-norecover.sh"        "$GATE_LINE"        '  if false; then'
# alwaysrecover: an extra call for every repo in the org, healthy ones included.
mutate "$WORK/m-alwaysrecover.sh"    "$GATE_LINE"        '  if true; then'
# noevent: the sassydog-routines#46 shape — branch filter only.
mutate "$WORK/m-noevent.sh"          "$EVENT_LINE"       '      --limit 1 \'
# mergegroupevent: widening the event list, which recovers nothing.
mutate "$WORK/m-mergegroupevent.sh"  "$EVENT_LINE"       '      --event push,merge_group --limit 1 \'
# norunsseen: the verdict without the key that makes a surviving null readable.
mutate "$WORK/m-norunsseen.sh"       "$KEY_LINE"         ''
# ignorebranch: the shared derivation stops caring which branch ran.
mutate "$WORK/m-ignorebranch.sh"     "$BRANCH_LINE"      '    map(select(true'
# overwriteonempty: a failed recovery overwrites a probe that saw runs.
mutate "$WORK/m-overwriteonempty.sh" "$EMPTY_GUARD_LINE" '    if true; then'

# Anchor adequacy first: a drifted anchor makes its mutant a silent no-op, which
# reads as "the matrix does not reach it" rather than as a stale gate.
for a in "$GATE_LINE" "$EVENT_LINE" "$KEY_LINE" "$BRANCH_LINE" "$EMPTY_GUARD_LINE"; do
    if ! grep -qF -- "$a" "$SCRIPT"; then
        bad "mutation anchor no longer present in the script: $a"
    fi
done

reached=""
for m in norecover alwaysrecover noevent mergegroupevent norunsseen ignorebranch overwriteonempty; do
    mfile="$WORK/m-$m.sh"
    if diff -q "$mfile" "$SCRIPT" >/dev/null 2>&1; then
        bad "mutant '$m' is byte-identical to the script — its anchor no longer matches"
        continue
    fi
    got="$(matrix "$mfile")"
    reddened="$(printf '%s\n' "$got" | awk -F'\t' '$2 == "fail" { print $1 }' | tr '\n' ' ')"
    if [ -z "$reddened" ]; then
        bad "mutant '$m' reddened NOTHING — the matrix does not reach it"
    else
        ok "mutant '$m' reddened: ${reddened% }"
        reached="$reached $reddened"
    fi
done

# The rows no mutant reaches must be exactly the declared fixture-adequacy
# precondition. A precondition asserts the fixture can show the bug at all, so
# by construction the recovering code cannot change its verdict.
DECLARED_UNREACHED="sample-adequate"
all_rows="$(printf '%s\n' "$BASELINE" | awk -F'\t' '{ print $1 }' | sort)"
# shellcheck disable=SC2086  # deliberate word splitting: the accumulator is a space-separated list
reached_sorted="$(printf '%s\n' $reached | sort -u | grep -v '^$')"
unreached="$(comm -23 <(printf '%s\n' "$all_rows") <(printf '%s\n' "$reached_sorted") | tr '\n' ' ')"
# shellcheck disable=SC2086  # same
declared_sorted="$(printf '%s\n' $DECLARED_UNREACHED | sort | tr '\n' ' ')"
if [ "${unreached% }" = "${declared_sorted% }" ]; then
    ok "rows no mutant reaches == declared preconditions (${declared_sorted% })"
else
    bad "unreached rows '${unreached% }' != declared '${declared_sorted% }'"
fi

# --- 3. source and docs -------------------------------------------------------
echo "3. source and docs" >&2

# ONE definition of the verdict. Uniqueness, not presence: a presence check
# cannot see a second, contradictory copy re-inlined into the assembly jq, and
# nothing downstream can tell which query answered.
defs="$(grep -cF '.event == "push" or .event == "merge_group"' "$SCRIPT")"
if [ "$defs" = "1" ]; then
    ok "the push-class rule is written exactly once in the script"
else
    bad "expected exactly one push-class filter in the puller, found $defs"
fi

if grep -qF -- '"default_branch_runs_seen"' "$SCRIPT"; then
    ok "the output-shape comment names the new key"
else
    bad "the script header output shape does not list default_branch_runs_seen"
fi

if grep -qF -- 'ONE extra per repo whose unfiltered sample holds no' "$SCRIPT"; then
    ok "the header cost accounting includes the conditional recovery call"
else
    bad "the header still prices the sweep without the recovery call"
fi

if grep -qF -- 'IS RECOVERED' "$SCRIPT" \
   && grep -qF -- 'push-on-main runs in its newest 100' "$SCRIPT"; then
    ok "the header records the recovery and why a larger RUN_LIMIT is not a substitute"
else
    bad "the header lost the recovery rationale — the next reader raises RUN_LIMIT instead"
fi

# The two reference docs a report is written from. Both describe this script's
# emitted fields, so a new key that only exists in the script is a key no report
# knows how to render.
if grep -qF -- 'default_branch_runs_seen' "$CLOUD"; then
    ok "cloud-fallback.md's field map carries the key"
else
    bad "cloud-fallback.md's pull-repo-signals field map does not mention default_branch_runs_seen"
fi

if grep -qF -- 'default_branch_runs_seen' "$SCORING"; then
    ok "scoring.md's unknown state tells the two nulls apart by the key"
else
    bad "scoring.md still describes a single undifferentiated null"
fi

if [ "$fail" -ne 0 ]; then
    echo "test-repo-signals-recovery: FAILED" >&2
    exit 1
fi
echo "Repo-signals recovery tests: all green"
