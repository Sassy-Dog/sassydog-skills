#!/usr/bin/env bash
# test-label-taxonomy.sh — proves the two label taxonomies stay separated and
# that a colour change in the dev-workflow one actually REACHES a repo that
# already carries the label (issue #161).
#
# Why this exists: `ensure_label` in issue-claim.sh used to be a bare
# `gh label create ... || true`. `gh label create` fails on an existing label,
# the failure was swallowed, and so a colour change reached only repos that did
# not yet have the label — every onboarded repo kept the old colour forever and
# nothing reported it. Nothing failed. Nothing warned. That is the same
# silent-no-op class as #97/#98, and a create-only path passes any test that
# only ever looks at a fresh repo. So the update path is exercised here against
# a MOCK `gh` that records every write, seeded mid-drift.
#
# Four properties are asserted:
#
#   1. Reconcile, not create: a label whose colour has drifted is corrected, a
#      missing label is created, an aligned repo takes ZERO writes, and
#      --dry-run takes zero writes in every case.
#   2. The transition path heals too — `promote` on a repo whose `ready` is
#      stale fixes the label as a side effect of the claim.
#   3. The taxonomies stay disjoint: align-labels.sh still refuses a reserved
#      label (exit 64), its cross-set colour check passes on the shipped tables,
#      FIRES on a reintroduced collision, and reports loudly (rather than
#      passing) when it cannot read the other taxonomy at all.
#   4. github-issues/SKILL.md's documented colours match the script constants —
#      the doc table and the `--ensure-label` spec are copies of values whose
#      home is issue-claim.sh, and a copy that drifts is how the wrong colour
#      gets pasted into the next call.
#
# The mock replaces `gh` only; `jq` is real, and the mock feeds it real JSON so
# the `--jq` expressions in the scripts under test are genuinely exercised.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-label-taxonomy.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-label-taxonomy: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

CLAIM="skills/github-issues/scripts/issue-claim.sh"
ALIGN="scripts/align-labels.sh"
SKILL="skills/github-issues/SKILL.md"

if ! command -v jq >/dev/null 2>&1; then
    echo "test-label-taxonomy: SKIP (jq not installed — CI still enforces)" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "label-taxonomy tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
# Mock gh: a label store in $MOCK_DB (name<TAB>color<TAB>description) and an
# append-only record of every MUTATING call in $MOCK_WRITES.
set -uo pipefail

jq_expr=""
prev=""
for a in "$@"; do
    [ "$prev" = "--jq" ] && jq_expr="$a"
    prev="$a"
done

db_has() { awk -F'\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$MOCK_DB"; }

cmd="$1"; shift
case "$cmd" in
    repo)
        echo "$MOCK_REPO" ;;
    api)
        path="$1"
        case "$path" in
            user)
                printf '{"login":"tester"}' | jq -r "${jq_expr:-.}" ;;
            repos/*/labels/*)
                name="${path##*/}"
                db_has "$name" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                color=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$MOCK_DB")
                desc=$(awk -F'\t' -v n="$name" '$1 == n { print $3 }' "$MOCK_DB")
                jq -n --arg c "$color" --arg d "$desc" \
                    '{color: $c, description: $d}' | jq -r "${jq_expr:-.}" ;;
            *)
                echo "mock gh: unhandled api path: $path" >&2; exit 1 ;;
        esac ;;
    label)
        sub="$1"; shift
        name="$1"; shift
        color=""; desc=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --color)       color="$2"; shift 2 ;;
                --description) desc="$2";  shift 2 ;;
                --name)        shift 2 ;;
                --repo)        shift 2 ;;
                *)             shift ;;
            esac
        done
        if [ "${MOCK_FAIL_LABEL:-0}" = "1" ]; then
            echo "HTTP 403: Resource not accessible by integration" >&2
            exit 1
        fi
        case "$sub" in
            create)
                if db_has "$name"; then
                    echo "HTTP 422: Validation Failed (label already exists)" >&2
                    exit 1
                fi
                printf '%s\t%s\t%s\n' "$name" "$color" "$desc" >>"$MOCK_DB"
                echo "label create $name $color" >>"$MOCK_WRITES" ;;
            edit)
                db_has "$name" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                awk -F'\t' -v OFS='\t' -v n="$name" -v c="$color" -v d="$desc" \
                    '$1 == n { $2 = c; $3 = d } { print }' "$MOCK_DB" >"$MOCK_DB.new"
                mv "$MOCK_DB.new" "$MOCK_DB"
                echo "label edit $name $color" >>"$MOCK_WRITES" ;;
            *)
                echo "mock gh: unhandled label subcommand: $sub" >&2; exit 1 ;;
        esac ;;
    issue)
        sub="$1"
        case "$sub" in
            view)    printf '{"assignees":[]}' | jq -r "${jq_expr:-.}" ;;
            edit|comment) echo "issue $*" >>"$MOCK_WRITES" ;;
            *) echo "mock gh: unhandled issue subcommand: $sub" >&2; exit 1 ;;
        esac ;;
    *)
        echo "mock gh: unhandled command: $cmd" >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

export MOCK_REPO="mock-org/mock-repo"
export MOCK_DB="$WORK/labels.tsv"
export MOCK_WRITES="$WORK/writes.log"

# Seed: `ready` and `in-progress` present at their PRE-#161 colours (the exact
# state of an onboarded repo), `blocked` and `sentry-escalation` absent, plus a
# Dependabot label that must be left alone.
seed_drifted() {
    : >"$MOCK_WRITES"
    cat >"$MOCK_DB" <<EOF
ready	0e8a16	Dispatchable: a cold worktree agent could ship this (groom-backlog promoted)
in-progress	1d76db	Claimed by a take-it/dispatch-ready loop
javascript	168700	Pull requests that update javascript code
EOF
}

run_claim() { PATH="$WORK/bin:$PATH" bash "$CLAIM" "$@" --repo "$MOCK_REPO"; }
n_writes() { [ -s "$MOCK_WRITES" ] && wc -l <"$MOCK_WRITES" | tr -d ' ' || echo 0; }
db_color() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$MOCK_DB"; }
action_of() { jq -r --arg l "$1" 'select(.label == $l) | .action' <"$2"; }

# --- 1. the update path ------------------------------------------------------
seed_drifted
rc=0
run_claim sync-labels >"$WORK/sync1.json" 2>"$WORK/sync1.err" || rc=$?
if [ "$rc" -ne 0 ]; then
    bad "sync-labels against a drifted repo exited $rc"
else
    ok "sync-labels against a drifted repo exits 0"
fi

if [ "$(action_of ready "$WORK/sync1.json")" = "update" ] \
   && [ "$(db_color ready)" = "38fa99" ]; then
    ok "stale 'ready' (0e8a16) is CORRECTED to 38fa99 — the create-only hole is closed"
else
    bad "stale 'ready' not corrected: action=$(action_of ready "$WORK/sync1.json") colour=$(db_color ready)"
fi

if [ "$(action_of in-progress "$WORK/sync1.json")" = "update" ] \
   && [ "$(db_color in-progress)" = "190132" ]; then
    ok "stale 'in-progress' (1d76db) is corrected to 190132"
else
    bad "stale 'in-progress' not corrected: colour=$(db_color in-progress)"
fi

if [ "$(action_of blocked "$WORK/sync1.json")" = "create" ] \
   && [ "$(action_of sentry-escalation "$WORK/sync1.json")" = "create" ]; then
    ok "absent labels are still created"
else
    bad "absent labels not created"
fi

if [ "$(n_writes)" = "4" ]; then
    ok "exactly 4 writes for 2 corrections + 2 creations"
else
    bad "expected 4 writes, got $(n_writes): $(tr '\n' '; ' <"$MOCK_WRITES")"
fi

if [ "$(db_color javascript)" = "168700" ]; then
    ok "Dependabot's 'javascript' label untouched"
else
    bad "'javascript' was modified"
fi

if grep -q "corrected label 'ready'" "$WORK/sync1.err"; then
    ok "the correction is announced on stderr (never a silent write)"
else
    bad "no stderr note for the corrected label"
fi

# --- 2. idempotency ----------------------------------------------------------
: >"$MOCK_WRITES"
run_claim sync-labels >"$WORK/sync2.json" 2>/dev/null
if [ "$(n_writes)" = "0" ] \
   && [ "$(jq -r 'select(.action != "ok") | .label' <"$WORK/sync2.json" | wc -l | tr -d ' ')" = "0" ]; then
    ok "re-run against the aligned repo: 4 x ok, ZERO writes"
else
    bad "re-run was not a no-op: $(n_writes) writes"
fi

# --- 3. dry-run --------------------------------------------------------------
seed_drifted
run_claim sync-labels --dry-run >"$WORK/sync3.json" 2>/dev/null
if [ "$(n_writes)" = "0" ] \
   && [ "$(action_of ready "$WORK/sync3.json")" = "would-update" ] \
   && [ "$(action_of blocked "$WORK/sync3.json")" = "would-create" ] \
   && [ "$(db_color ready)" = "0e8a16" ]; then
    ok "--dry-run previews would-update/would-create and writes nothing"
else
    bad "--dry-run wrote something or mis-reported"
fi

# --- 4. the transition path heals as a side effect ---------------------------
seed_drifted
run_claim promote 7 >/dev/null 2>&1
if [ "$(db_color ready)" = "38fa99" ] && grep -q '^label edit ready' "$MOCK_WRITES"; then
    ok "promote on a stale repo corrects 'ready' on the way through"
else
    bad "promote did not heal the stale label"
fi

# A label reconcile that FAILS must still not fail the claim (the contract is
# report-and-continue) — and must still say so on stderr.
seed_drifted
rc=0
MOCK_FAIL_LABEL=1 PATH="$WORK/bin:$PATH" bash "$CLAIM" promote 7 --repo "$MOCK_REPO" \
    >"$WORK/promote-fail.json" 2>"$WORK/promote-fail.err" || rc=$?
if [ "$rc" -eq 0 ] \
   && [ "$(jq -r '.result' <"$WORK/promote-fail.json")" = "ok" ] \
   && grep -q "label 'ready' is stale" "$WORK/promote-fail.err"; then
    ok "a failed label reconcile is reported on stderr but does not fail the claim"
else
    bad "a failed label reconcile was silent or broke the claim (exit $rc)"
fi

# --- 5. the two taxonomies stay disjoint -------------------------------------
mkdir -p "$WORK/tree/scripts" "$WORK/tree/skills/github-issues/scripts"
cp "$ALIGN" "$WORK/tree/scripts/align-labels.sh"
cp "$CLAIM" "$WORK/tree/skills/github-issues/scripts/issue-claim.sh"

sed 's/^CANONICAL_LABELS=(/CANONICAL_LABELS=(\n    "ready|38fa99|smuggled in"/' \
    "$ALIGN" >"$WORK/reserved.sh"
rc=0
bash "$WORK/reserved.sh" --collisions >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 64 ]; then
    ok "reserved-label guard still refuses 'ready' in CANONICAL_LABELS (exit 64)"
else
    bad "reserved-label guard did not fire (exit $rc)"
fi

rc=0
bash "$ALIGN" --collisions >"$WORK/collisions.err" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    ok "cross-set colour check passes on the shipped tables ($(sed -n 's/.*tightest cross-set pair: //p' "$WORK/collisions.err"))"
else
    bad "cross-set colour check failed on the shipped tables: $(cat "$WORK/collisions.err")"
fi

# Reintroduce the historical collision (ready == sev:low) in the copied tree.
sed 's/^READY_COLOR=.*/READY_COLOR="0e8a16"/' "$CLAIM" \
    >"$WORK/tree/skills/github-issues/scripts/issue-claim.sh"
rc=0
bash "$WORK/tree/scripts/align-labels.sh" --collisions >"$WORK/regress.err" 2>&1 || rc=$?
if [ "$rc" -eq 3 ] && grep -q 'dE2000 0.00 ready' "$WORK/regress.err"; then
    ok "cross-set check FIRES (exit 3) when a dev-workflow colour is moved back onto a canonical one"
else
    bad "cross-set check missed a reintroduced ΔE 0 collision (exit $rc)"
fi

# A check that cannot read the other taxonomy must say so, not pass.
mkdir -p "$WORK/orphan/scripts"
cp "$ALIGN" "$WORK/orphan/scripts/align-labels.sh"
rc=0
bash "$WORK/orphan/scripts/align-labels.sh" --collisions >"$WORK/orphan.err" 2>&1 || rc=$?
if [ "$rc" -eq 3 ] && grep -q 'COULD NOT RUN' "$WORK/orphan.err"; then
    ok "an unreadable dev-workflow taxonomy is reported, not silently passed"
else
    bad "a missing dev-workflow source did not degrade loudly (exit $rc)"
fi

# --- 6. the docs quote the constants -----------------------------------------
doc_drift=0
while IFS='|' read -r name color desc; do
    [ -z "$name" ] && continue
    if ! grep -Fq "| \`$name\` | \`$color\` | $desc |" "$SKILL"; then
        bad "SKILL.md's table row for '$name' does not match the script ($color)"
        doc_drift=1
    fi
done < <(bash "$CLAIM" taxonomy)

sentry_spec=$(bash "$CLAIM" taxonomy | grep '^sentry-escalation|')
sentry_color=$(printf '%s' "$sentry_spec" | cut -d'|' -f2)
sentry_desc=$(printf '%s' "$sentry_spec" | cut -d'|' -f3)
if ! grep -Fq -- "--ensure-label \"sentry-escalation:$sentry_color:$sentry_desc\"" "$SKILL"; then
    bad "SKILL.md's --ensure-label spec does not quote sentry-escalation's current colour"
    doc_drift=1
fi
[ "$doc_drift" -eq 0 ] && ok "SKILL.md quotes all four colours exactly as the script defines them"

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "label-taxonomy tests: all pass" >&2
    exit 0
fi
echo "label-taxonomy tests: FAILURES above" >&2
exit 1
