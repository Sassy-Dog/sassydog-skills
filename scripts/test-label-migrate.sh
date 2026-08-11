#!/usr/bin/env bash
# test-label-migrate.sh — proves align-labels.sh's migrate mode cannot delete a
# label whose relabel has not been verified (issue #163).
#
# Why this exists: #159 has to move 703 issue-label pairs across 14 repos, and
# the rule that makes that survivable — RELABEL FIRST, DELETE SECOND, because
# deleting a label strips it from every issue carrying it unrecoverably — lived
# only in an issue body. Prose enforces nothing. The gate is now control flow,
# and this file is the proof that it is: it does not read the comments, it runs
# the script against a MOCK `gh` that records every mutating call, and it
# MUTATES the gate to confirm the withheld delete was withheld BY the gate and
# not by luck.
#
# Properties asserted:
#
#   1. Structural, at the source level: `gh label delete` has exactly one call
#      site in align-labels.sh, it is inside migrate_delete_gate(), and the
#      re-query precedes it inside that same function body. No amount of
#      resequencing elsewhere can reach a delete without going through it.
#   2. The plan is refused before any network call: a mapping touching a
#      reserved dev-workflow label, a duplicate source, a chained mapping,
#      old == new, or a malformed line each exit 64 with ZERO gh invocations.
#   3. --dry-run previews every relabel and delete and writes nothing, exit 0.
#   4. A clean mapping relabels then deletes, and issues already carrying the
#      target are not touched.
#   5. Idempotency: the second run over a migrated repo issues zero writes.
#   6. A DELIBERATELY PARTIAL relabel holds the delete back, per mapping — the
#      other mapping in the same run still completes — and says so; and the
#      same scenario against a gate-neutered mutant DOES delete, which is what
#      makes assertion 6 evidence rather than a coincidence.
#   7. Every other "not verified" path also withholds: a missing target label,
#      an issue read that hit the --limit ceiling (a truncated read undercounts,
#      which is precisely what would look like success), and a delete call that
#      fails after verification.
#
# The mock replaces `gh` only; `jq` is real and is fed real JSON, so the --json
# and jq expressions in the script under test are genuinely exercised.
#
# Wired into scripts/preflight.sh. The MIGRATE MODE ITSELF IS NEVER WIRED INTO
# CI — it mutates other repos' issues. Only this mock-backed test is a gate.
#
# Run directly:  bash scripts/test-label-migrate.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-label-migrate: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

ALIGN="scripts/align-labels.sh"
CLAIM="skills/github-issues/scripts/issue-claim.sh"
RETRY="skills/pr-shepherd/scripts/gh-retry.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "test-label-migrate: SKIP (jq not installed — CI still enforces)" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "label-migrate tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# Mock gh with two stores — labels in $MOCK_DB (name<TAB>color<TAB>description)
# and issues in $MOCK_ISSUES (number<TAB>comma-separated label names) — plus an
# append-only record of every MUTATING call in $MOCK_WRITES. When $MOCK_CALLS is
# set, EVERY invocation is recorded there, which is how "refused before any
# network call" is asserted rather than assumed.
#
# Fault injection: MOCK_FAIL_ISSUE=<n> fails that issue's edit (the deliberately
# partial relabel), MOCK_FAIL_DELETE=1 fails every label delete.
set -uo pipefail

[ -n "${MOCK_CALLS:-}" ] && echo "gh $*" >>"$MOCK_CALLS"

cmd="$1"; shift
case "$cmd" in
    repo)
        echo "$MOCK_REPO" ;;
    label)
        sub="$1"; shift
        case "$sub" in
            list)
                limit=300
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --limit) limit="$2"; shift 2 ;;
                        *)       shift ;;
                    esac
                done
                head -n "$limit" "$MOCK_DB" | jq -R -s '
                    split("\n") | map(select(length > 0)) | map(split("\t"))
                    | map({name: .[0], color: (.[1] // ""), description: (.[2] // "")})' ;;
            delete)
                name="$1"; shift
                if [ "${MOCK_FAIL_DELETE:-0}" = "1" ]; then
                    echo "HTTP 403: Resource not accessible by integration" >&2
                    exit 1
                fi
                awk -F'\t' -v n="$name" '$1 != n' "$MOCK_DB" >"$MOCK_DB.new"
                mv "$MOCK_DB.new" "$MOCK_DB"
                # A real delete strips the label from every issue carrying it.
                awk -F'\t' -v OFS='\t' -v n="$name" '{
                    cnt = split($2, a, ","); out = ""
                    for (i = 1; i <= cnt; i++)
                        if (a[i] != n && a[i] != "")
                            out = (out == "" ? a[i] : out "," a[i])
                    $2 = out; print
                }' "$MOCK_ISSUES" >"$MOCK_ISSUES.new"
                mv "$MOCK_ISSUES.new" "$MOCK_ISSUES"
                echo "label delete $name" >>"$MOCK_WRITES" ;;
            *)
                echo "mock gh: unhandled label subcommand: $sub" >&2; exit 1 ;;
        esac ;;
    issue)
        sub="$1"; shift
        case "$sub" in
            list)
                # MOCK_LIST_FAIL_FROM=<n> fails the nth and every later issue
                # list, which is how the GATE's own re-query is made to fail
                # while the pass's first read succeeded.
                if [ -n "${MOCK_LIST_FAIL_FROM:-}" ]; then
                    c=0
                    [ -f "$MOCK_LIST_COUNT" ] && c=$(cat "$MOCK_LIST_COUNT")
                    c=$((c + 1)); echo "$c" >"$MOCK_LIST_COUNT"
                    if [ "$c" -ge "$MOCK_LIST_FAIL_FROM" ]; then
                        echo "gh: API rate limit exceeded" >&2
                        exit 1
                    fi
                fi
                want=""; limit=1000
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --label) want="$2"; shift 2 ;;
                        --limit) limit="$2"; shift 2 ;;
                        *)       shift ;;
                    esac
                done
                awk -F'\t' -v want="$want" -v lim="$limit" '
                    n >= lim { exit }
                    { cnt = split($2, a, ",")
                      for (i = 1; i <= cnt; i++)
                          if (a[i] == want) { print; n++; next } }
                ' "$MOCK_ISSUES" | jq -R -s '
                    split("\n") | map(select(length > 0)) | map(split("\t"))
                    | map({number: (.[0] | tonumber),
                           labels: ((.[1] // "") | split(",")
                                    | map(select(length > 0)) | map({name: .}))})' ;;
            edit)
                num="$1"; shift
                add=""
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --add-label) add="$2"; shift 2 ;;
                        *)           shift ;;
                    esac
                done
                if [ "${MOCK_FAIL_ISSUE:-}" = "$num" ]; then
                    echo "HTTP 422: Validation Failed (mock: issue $num is unwritable)" >&2
                    exit 1
                fi
                awk -F'\t' -v OFS='\t' -v n="$num" -v l="$add" \
                    '$1 == n { $2 = ($2 == "" ? l : $2 "," l) } { print }' \
                    "$MOCK_ISSUES" >"$MOCK_ISSUES.new"
                mv "$MOCK_ISSUES.new" "$MOCK_ISSUES"
                echo "issue edit $num add $add" >>"$MOCK_WRITES" ;;
            *)
                echo "mock gh: unhandled issue subcommand: $sub" >&2; exit 1 ;;
        esac ;;
    *)
        echo "mock gh: unhandled command: $cmd" >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

export MOCK_REPO="mock-org/mock-repo"
export MOCK_DB="$WORK/labels.tsv"
export MOCK_ISSUES="$WORK/issues.tsv"
export MOCK_WRITES="$WORK/writes.log"
export MOCK_LIST_COUNT="$WORK/list-count"

# Seed: a mid-migration repo. Two one-off labels to fold away, their canonical
# targets already present, one label whose target is NOT present, a reserved
# dev-workflow label and a Dependabot label that must both be left alone.
# Issue 2 already carries the target — the relabel must skip it, which is what
# makes the pass idempotent.
seed() {
    : >"$MOCK_WRITES"
    echo 0 >"$MOCK_LIST_COUNT"
    cat >"$MOCK_DB" <<'EOF'
priority:p1	b60205	Priority one
developer-experience	bfdadc	DX
chore	c5def5	Chore
sev:critical	b60205	Critical severity
dx	bfdadc	Developer experience
ready	38fa99	Dispatchable
javascript	168700	Pull requests that update javascript code
EOF
    cat >"$MOCK_ISSUES" <<'EOF'
1	priority:p1
2	priority:p1,sev:critical
3	priority:p1
4	developer-experience
5	javascript
6	chore
EOF
}

PLAN="$WORK/plan.txt"
cat >"$PLAN" <<'EOF'
# the org label migration plan — one file drives every repo
mock-org/mock-repo|priority:p1|sev:critical
mock-org/mock-repo | developer-experience | dx
other-org/other-repo|P1-high|sev:high
EOF

run_migrate() {  # extra args...
    PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" --migrate "$PLAN" "$@"
}
n_writes() { [ -s "$MOCK_WRITES" ] && wc -l <"$MOCK_WRITES" | tr -d ' ' || echo 0; }
wrote() { grep -Fq "$1" "$MOCK_WRITES" 2>/dev/null; }
has_label() { awk -F'\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$MOCK_DB"; }
issue_labels() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$MOCK_ISSUES"; }
action_of() { jq -r --arg o "$1" 'select(.old == $o) | .action' <"$2"; }
relabeled_of() { jq -r --arg o "$1" 'select(.old == $o) | .relabeled' <"$2"; }

# --- 1. the structural invariant, read off the source ------------------------
# Not "the delete happens later in the script" — later is what a stray `|| true`
# or a reordering undoes. Exactly one call site, inside the gate, downstream of
# the re-query in that same function body.
read -r n_total n_within n_ordered <<<"$(awk '
    /^migrate_delete_gate\(\) \{/ { inside = 1; next }
    inside && /^\}/               { inside = 0; next }
    /^[[:space:]]*#/              { next }
    /label delete/                { total++; if (inside) { within++; if (requeried) ordered++ } }
    inside && /migrate_unmigrated_issues/ { requeried = 1 }
    END { printf "%d %d %d\n", total + 0, within + 0, ordered + 0 }
' "$ALIGN")"
if [ "$n_total" = "1" ] && [ "$n_within" = "1" ] && [ "$n_ordered" = "1" ]; then
    ok "'label delete' has exactly ONE call site, inside migrate_delete_gate, after the re-query"
else
    bad "delete call sites: $n_total total, $n_within inside the gate, $n_ordered after the re-query (want 1/1/1)"
fi

# --- 2. the plan is refused before any network call --------------------------
refuses_offline() {  # $1=label for the assertion, $2=plan body
    local desc="$1" body="$2" rc=0 calls="$WORK/calls.log"
    : >"$calls"
    printf '%s\n' "$body" >"$WORK/bad-plan.txt"
    MOCK_CALLS="$calls" PATH="$WORK/bin:$PATH" \
        bash "$ALIGN" --repo "$MOCK_REPO" --migrate "$WORK/bad-plan.txt" \
        >/dev/null 2>"$WORK/bad-plan.err" || rc=$?
    if [ "$rc" -eq 64 ] && [ ! -s "$calls" ]; then
        ok "refused before any network call (exit 64, 0 gh invocations): $desc"
    else
        bad "$desc — exit $rc, $(wc -l <"$calls" | tr -d ' ') gh invocation(s)"
    fi
}

refuses_offline "reserved label as the SOURCE (ready)" \
    "mock-org/mock-repo|ready|sev:low"
refuses_offline "reserved label as the TARGET (in-progress)" \
    "mock-org/mock-repo|priority:p1|in-progress"
refuses_offline "reserved label as the target in ANOTHER repo's line" \
    "mock-org/mock-repo|priority:p1|sev:critical
other-org/other-repo|blocked|sev:high"
refuses_offline "malformed line (two fields)" \
    "mock-org/mock-repo|priority:p1"
refuses_offline "old == new" \
    "mock-org/mock-repo|dx|DX"
refuses_offline "one source mapped twice" \
    "mock-org/mock-repo|priority:p1|sev:critical
mock-org/mock-repo|priority:p1|sev:high"
refuses_offline "chained mapping (a -> b alongside b -> c)" \
    "mock-org/mock-repo|infrastructure|infra
mock-org/mock-repo|infra|platform"

rc=0
PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" --migrate "$PLAN" --check \
    >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 64 ]; then
    ok "--migrate combined with --check is a usage error (exit 64)"
else
    bad "--migrate --check did not exit 64 (got $rc)"
fi

# --- 3. --dry-run: full preview, zero writes ---------------------------------
seed
rc=0
run_migrate --dry-run >"$WORK/dry.json" 2>"$WORK/dry.err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(n_writes)" = "0" ] && has_label "priority:p1"; then
    ok "--dry-run exits 0 and writes nothing"
else
    bad "--dry-run exit $rc with $(n_writes) write(s)"
fi
if [ "$(action_of 'priority:p1' "$WORK/dry.json")" = "would-migrate" ] \
   && [ "$(relabeled_of 'priority:p1' "$WORK/dry.json")" = "2" ] \
   && [ "$(relabeled_of 'developer-experience' "$WORK/dry.json")" = "1" ]; then
    ok "--dry-run previews 2 + 1 relabels (issue 2 already carries the target, so it is not counted)"
else
    bad "--dry-run preview counts wrong: $(cat "$WORK/dry.json")"
fi
if jq -e -r 'select(.old == "priority:p1") | .detail' <"$WORK/dry.json" \
     | grep -q '#1, #3' \
   && jq -e -r 'select(.old == "priority:p1") | .detail' <"$WORK/dry.json" \
     | grep -q "delete 'priority:p1' ONLY if 0 still carry it"; then
    ok "--dry-run names the issues it would relabel AND the delete it would then gate"
else
    bad "--dry-run detail did not preview both the relabel and the delete"
fi

# --- 4. a clean mapping relabels, verifies, then deletes ---------------------
seed
rc=0
run_migrate >"$WORK/apply.json" 2>"$WORK/apply.err" || rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(action_of 'priority:p1' "$WORK/apply.json")" = "migrated" ] \
   && [ "$(action_of 'developer-experience' "$WORK/apply.json")" = "migrated" ]; then
    ok "both clean mappings report 'migrated' (exit 0)"
else
    bad "clean apply exit $rc: $(cat "$WORK/apply.json")"
fi
if ! has_label "priority:p1" && ! has_label "developer-experience" \
   && has_label "sev:critical" && has_label "ready" && has_label "javascript"; then
    ok "the old labels are gone; the canonical, reserved and Dependabot labels are untouched"
else
    bad "wrong labels survived: $(cut -f1 <"$MOCK_DB" | tr '\n' ' ')"
fi
if [ "$(issue_labels 1)" = "sev:critical" ] && [ "$(issue_labels 3)" = "sev:critical" ] \
   && [ "$(issue_labels 4)" = "dx" ] && [ "$(issue_labels 2)" = "sev:critical" ]; then
    ok "every issue carries the new label; none lost signal in the delete"
else
    bad "issue labels wrong: 1=$(issue_labels 1) 2=$(issue_labels 2) 3=$(issue_labels 3) 4=$(issue_labels 4)"
fi
if [ "$(n_writes)" = "5" ] && ! wrote "issue edit 2 "; then
    ok "exactly 5 writes (3 relabels + 2 deletes); issue 2 already had the target and was skipped"
else
    bad "expected 5 writes and no touch of issue 2, got $(n_writes): $(tr '\n' '; ' <"$MOCK_WRITES")"
fi

# --- 5. idempotency: the second run is a true no-op --------------------------
: >"$MOCK_WRITES"
rc=0
run_migrate >"$WORK/again.json" 2>/dev/null || rc=$?
if [ "$rc" -eq 0 ] && [ "$(n_writes)" = "0" ] \
   && [ "$(jq -r 'select(.action != "already-migrated") | .old' <"$WORK/again.json" | wc -l | tr -d ' ')" = "0" ]; then
    ok "re-run over the migrated repo: all already-migrated, ZERO writes, exit 0"
else
    bad "re-run was not a no-op: exit $rc, $(n_writes) write(s)"
fi

# --- 6. THE POINT: a partial relabel withholds the delete --------------------
seed
rc=0
MOCK_FAIL_ISSUE=3 run_migrate >"$WORK/partial.json" 2>"$WORK/partial.err" || rc=$?
if [ "$(action_of 'priority:p1' "$WORK/partial.json")" = "held-back" ] \
   && ! wrote "label delete priority:p1" && has_label "priority:p1"; then
    ok "relabel of issue 3 failed -> 'priority:p1' is HELD BACK and still exists"
else
    bad "a partial relabel did not withhold the delete: $(cat "$WORK/partial.json")"
fi
if grep -q "MAPPINGS HELD BACK" "$WORK/partial.err" \
   && grep -q "priority:p1 -> sev:critical" "$WORK/partial.err" \
   && jq -e -r 'select(.old == "priority:p1") | .detail' <"$WORK/partial.json" \
      | grep -q "1 issue(s) still carrying 'priority:p1'"; then
    ok "the run names the held-back mapping and the re-query count behind it"
else
    bad "the held-back mapping was not reported: $(cat "$WORK/partial.err")"
fi
if [ "$rc" -eq 4 ]; then
    ok "a held-back mapping exits 4 (gateable, and it outranks the write failure)"
else
    bad "expected exit 4 for a held-back mapping, got $rc"
fi
if [ "$(action_of 'developer-experience' "$WORK/partial.json")" = "migrated" ] \
   && ! has_label "developer-experience"; then
    ok "hold-back is PER MAPPING — the clean mapping in the same run still completed"
else
    bad "one held-back mapping blocked an unrelated clean one"
fi

# --- 6b. mutation: prove the gate is what withheld it ------------------------
# Neuter the one comparison the gate turns on and re-run the identical scenario.
# If the delete still does not fire, assertion 6 above proves nothing.
mkdir -p "$WORK/mutant/scripts" "$WORK/mutant/skills/github-issues/scripts" \
         "$WORK/mutant/skills/pr-shepherd/scripts"
cp "$CLAIM" "$WORK/mutant/skills/github-issues/scripts/issue-claim.sh"
cp "$RETRY" "$WORK/mutant/skills/pr-shepherd/scripts/gh-retry.sh"
sed 's/if \[\[ -n "\$still" \]\]; then/if false; then/' \
    "$ALIGN" >"$WORK/mutant/scripts/align-labels.sh"
if ! grep -q '^    if false; then$' "$WORK/mutant/scripts/align-labels.sh"; then
    bad "the mutation did not apply — the gate's guard was not found, so 6b proves nothing"
else
    seed
    MOCK_FAIL_ISSUE=3 PATH="$WORK/bin:$PATH" \
        bash "$WORK/mutant/scripts/align-labels.sh" --repo "$MOCK_REPO" --migrate "$PLAN" \
        >/dev/null 2>&1
    if wrote "label delete priority:p1"; then
        ok "MUTANT (gate neutered) DOES delete on the same partial relabel — the gate is load-bearing"
    else
        bad "the mutant did not delete either; assertion 6 is not evidence of a working gate"
    fi
fi

# --- 7. every other unverified path also withholds ---------------------------
# 7a. target label missing — nothing is invented and nothing is deleted.
cat >"$WORK/plan-blocked.txt" <<'EOF'
mock-org/mock-repo|chore|tech-debt
EOF
seed
rc=0
PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" --migrate "$WORK/plan-blocked.txt" \
    >"$WORK/blocked.json" 2>"$WORK/blocked.err" || rc=$?
if [ "$rc" -eq 4 ] && [ "$(action_of chore "$WORK/blocked.json")" = "blocked" ] \
   && [ "$(n_writes)" = "0" ] && has_label "chore"; then
    ok "a mapping whose TARGET is absent is blocked with zero writes (run the align pass first)"
else
    bad "missing-target mapping: exit $rc, $(n_writes) write(s), action $(action_of chore "$WORK/blocked.json")"
fi

# 7b. a truncated issue read UNDERCOUNTS, which is exactly what a delete gate
# would misread as progress. Hitting the ceiling is a failure, not a zero.
cat >"$WORK/plan-one.txt" <<'EOF'
mock-org/mock-repo|priority:p1|sev:critical
EOF
seed
rc=0
ISSUE_LIMIT=2 PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" \
    --migrate "$WORK/plan-one.txt" >"$WORK/ceiling.json" 2>"$WORK/ceiling.err" || rc=$?
if [ "$rc" -eq 4 ] && [ "$(n_writes)" = "0" ] && has_label "priority:p1" \
   && grep -q "hit the ceiling" "$WORK/ceiling.err"; then
    ok "an issue read at the --limit ceiling holds the mapping back instead of undercounting"
else
    bad "ceiling read did not hold back: exit $rc, $(n_writes) write(s)"
fi

# 7c. a delete that fails AFTER verification is reported, not swallowed.
seed
rc=0
MOCK_FAIL_DELETE=1 PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" \
    --migrate "$WORK/plan-one.txt" >"$WORK/delfail.json" 2>"$WORK/delfail.err" || rc=$?
if [ "$rc" -eq 4 ] && [ "$(action_of 'priority:p1' "$WORK/delfail.json")" = "held-back" ] \
   && has_label "priority:p1" \
   && jq -e -r 'select(.old == "priority:p1") | .detail' <"$WORK/delfail.json" \
      | grep -q "verified, but removing"; then
    ok "a delete that fails after verification is held back and reported, not swallowed"
else
    bad "a failed delete was mis-reported: exit $rc, $(cat "$WORK/delfail.json")"
fi

# 7e. the GATE's own re-query fails (the first read succeeded, so the relabel
# already ran). Unknown is not verified: the delete must not proceed on the
# strength of the relabel loop having reported success.
seed
rc=0
MOCK_LIST_FAIL_FROM=2 PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" \
    --migrate "$WORK/plan-one.txt" >"$WORK/requery.json" 2>"$WORK/requery.err" || rc=$?
if [ "$rc" -eq 4 ] && [ "$(action_of 'priority:p1' "$WORK/requery.json")" = "held-back" ] \
   && ! wrote "label delete" && has_label "priority:p1" \
   && jq -e -r 'select(.old == "priority:p1") | .detail' <"$WORK/requery.json" \
      | grep -q "re-query failed"; then
    ok "a re-query that FAILS after a fully successful relabel still withholds the delete"
else
    bad "an unverifiable re-query did not withhold: exit $rc, $(cat "$WORK/requery.json")"
fi

# 7d. one plan, many repos: a repo with no mapping is a loud no-op, not silence.
cat >"$WORK/plan-elsewhere.txt" <<'EOF'
other-org/other-repo|P1-high|sev:high
EOF
seed
rc=0
PATH="$WORK/bin:$PATH" bash "$ALIGN" --repo "$MOCK_REPO" \
    --migrate "$WORK/plan-elsewhere.txt" >/dev/null 2>"$WORK/elsewhere.err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(n_writes)" = "0" ] \
   && grep -q "other-org/other-repo" "$WORK/elsewhere.err"; then
    ok "a repo the plan does not target exits 0 having named the repos it DOES target"
else
    bad "a plan targeting no mapping here was not reported clearly (exit $rc)"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "label-migrate tests: all pass" >&2
    exit 0
fi
echo "label-migrate tests: FAILURES above" >&2
exit 1
