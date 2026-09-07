#!/usr/bin/env bash
# test-tech-debt-excludes.sh — pins how pull-tech-debt.sh consumes
# EXCLUDE_PATHSPECS (issue #365).
#
# THE FAILURE. setup-config's contract shipped `exclude_pathspecs` values
# already carrying `:(exclude)`, while pull-tech-debt.sh supplies that magic
# itself. The two halves were each internally consistent and disagreed with
# each other, so every repo configured per the contract handed git
# `:(exclude):(exclude)<path>` — a VALID pathspec whose pattern happens to
# begin with `:(exclude)`, matching nothing. git excludes nothing and exits 0.
#
# It is invisible in three separate ways, and each one dictates something about
# this gate:
#
#   1. git returns 0 or 1 for the malformed pathspec, never 128. So NO
#      assertion here may key on an exit code — an exit-code check passes
#      against the broken script and proves nothing.
#   2. pull-tech-debt.sh wraps every git grep in `2>/dev/null | head -N ||
#      true`, so even a real error is swallowed before a caller could see it.
#      Only the emitted OUTPUT SET distinguishes a working exclusion from a
#      disabled one, so that is what every row below reads.
#   3. It only ADDS results. A scan that should report 4 markers reports 5 —
#      plausible either way, and the extra one sits in a directory the reader
#      was told is excluded. Nothing is red anywhere; the plate is just wrong.
#
# THE FIX BEING PINNED, and the part that reads like an inconsistency. The
# script strips AT MOST ONE leading `:(exclude)` before re-prefixing, so both
# spellings land on the same pathspec and every config already written keeps
# working with no migration. A GREEDY strip would also "work" and is the
# tempting simplification — it is refused on purpose, and row
# `doubled-stays-broken` is what refuses it: a genuinely doubled value is a
# different config error, and silently repairing it hides a mistake this gate
# would otherwise be the only thing able to see. So the doubled input is
# asserted to STILL LEAK. That row failing is the signal that someone widened
# the strip, not that the fix regressed.
#
# CANONICAL SPELLING is bare, and `docs-normalized` pins the one doc site that
# moved (config-contract.md's survey-work example). The script's own header
# documents bare, and repo-health/SKILL.md already wrote bare, so normalizing
# on bare left two of the three sites untouched. SCAN_PATHS is deliberately out
# of scope: the `**`-needs-`:(glob)` claim in the script header did not
# reproduce when tested on 2026-09-07, so it needs verification rather than a
# fix, and nothing here touches it.
#
# FIXTURES, both of them adequacy-checked rather than assumed:
#
#   * A scratch git repo under mktemp carries the behavioural matrix — small,
#     deterministic, and immune to this checkout's own contents changing.
#     Its markers are ASSEMBLED AT RUNTIME rather than written literally, so
#     this gate does not itself show up as debt in the scan it tests.
#   * The live checkout carries the issue's own reproduction. The excluded
#     directory is DERIVED from an unfiltered scan rather than hard-coded, so
#     the row can never go vacuous and no unrelated edit that removes markers
#     from one particular directory can redden it. If the tree carries no
#     markers under `skills/` at all, `live-baseline-has-markers` fails loudly
#     rather than passing over an empty set.
#
# MUTATION PROOF. The matrix is a function of the script path, so it is re-run
# against four mutated copies and the reach is DERIVED from the verdicts rather
# than asserted in prose: no-strip (the pre-fix line), greedy-strip, a dropped
# built-in exclude, and a disabled user-exclude loop. Every mutant must redden
# at least one row, and the rows no mutant reaches must equal the declared set
# — which holds exactly the two fixture-adequacy preconditions, since a
# precondition is by construction not sensitive to the excluding code.
#
# Copies and scratch repos only: no gh, no network, no mutation of this
# checkout. A LOCAL `git init` fixture, so a machine with credentials behaves
# exactly like CI.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-tech-debt-excludes.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-tech-debt-excludes: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPT="$REPO_ROOT/skills/repo-health/scripts/pull-tech-debt.sh"
CONTRACT="$REPO_ROOT/skills/setup-config/references/config-contract.md"
[ -f "$SCRIPT" ] || { echo "test-tech-debt-excludes: $SCRIPT not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok()  { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "tech-debt exclude tests (work: $WORK)" >&2

# --- the scratch fixture ------------------------------------------------------
# Markers are assembled at runtime (see header). `git add` alone makes a file
# tracked as far as `git grep` is concerned, so no commit and no identity are
# needed. The lockfile sits one directory down because the built-in
# `:(exclude)**/*.lock` needs a literal `/` to match.
MARK="TO""DO"
FIXTURE="$WORK/fixture"
mkdir -p "$FIXTURE/src" "$FIXTURE/docs" "$FIXTURE/generated" \
         "$FIXTURE/.claude" "$FIXTURE/packages"
printf '%s: real work\n'       "$MARK" >"$FIXTURE/src/app.txt"
printf '%s: docs debt\n'       "$MARK" >"$FIXTURE/docs/notes.txt"
printf '%s: generated noise\n' "$MARK" >"$FIXTURE/generated/gen.txt"
printf '%s: agent noise\n'     "$MARK" >"$FIXTURE/.claude/agent.txt"
printf '%s: lockfile noise\n'  "$MARK" >"$FIXTURE/packages/bun.lock"
git -C "$FIXTURE" init -q >/dev/null 2>&1
git -C "$FIXTURE" add -A >/dev/null 2>&1

# --- helpers ------------------------------------------------------------------
# `printf` is the writer into every `grep -q` below: the value is already a
# shell variable, so it is bounded and fully written (test-pipefail-grep.sh).
has()   { printf '%s\n' "$1" | grep -qF -- "$2"; }
hasnt() { if has "$1" "$2"; then return 1; fi; return 0; }
same()  { [ "$1" = "$2" ]; }
verdict() { if "$@"; then echo pass; else echo fail; fi; }

run_fixture() {  # $1 = script path, $2 = EXCLUDE_PATHSPECS value
    ( cd "$FIXTURE" && SCAN_PATHS="." EXCLUDE_PATHSPECS="$2" bash "$1" 2>/dev/null )
}
run_live() {     # $1 = script path, $2 = EXCLUDE_PATHSPECS value
    ( cd "$REPO_ROOT" && SCAN_PATHS="skills" EXCLUDE_PATHSPECS="$2" bash "$1" 2>/dev/null )
}

# --- derive the live fixture's excluded directory -----------------------------
# Taken from the REAL script's unfiltered scan, never from a mutant, so every
# matrix run scores the same subject. First marker path, first two components.
live_base="$(run_live "$SCRIPT" "")"
LIVE_DIR="$(printf '%s\n' "$live_base" \
    | awk -F: '/^skills\// { print $1; exit }' \
    | awk -F/ 'NF>=2 { print $1 "/" $2 }')"
if [ -z "$LIVE_DIR" ]; then
    echo "  FAIL  no markers found anywhere under skills/ — the live reproduction cannot run" >&2
    echo "test-tech-debt-excludes: FAILED (1)" >&2
    exit 1
fi
echo "  ..    live reproduction directory: $LIVE_DIR" >&2

# --- the matrix ---------------------------------------------------------------
# Emits one `<row-id><TAB>pass|fail` line per row. A function of the script
# path so the mutants below are scored by exactly this code.
matrix() {
    local s="$1"
    local base bare pref dbl mixed lbase lbare lpref
    base="$(run_fixture  "$s" "")"
    bare="$(run_fixture  "$s" "generated")"
    pref="$(run_fixture  "$s" ":(exclude)generated")"
    dbl="$(run_fixture   "$s" ":(exclude):(exclude)generated")"
    mixed="$(run_fixture "$s" "generated :(exclude)docs")"
    lbase="$live_base"
    lbare="$(run_live "$s" "$LIVE_DIR")"
    lpref="$(run_live "$s" ":(exclude)$LIVE_DIR")"

    # Fixture adequacy: with nothing excluded the marker under generated/ must
    # be visible, or every "absent" row below is trivially satisfiable.
    printf 'baseline-leaks\t%s\n' \
        "$(verdict has "$base" 'generated/gen.txt')"
    printf 'bare-excludes\t%s\n' \
        "$(verdict hasnt "$bare" 'generated/')"
    printf 'prefixed-excludes\t%s\n' \
        "$(verdict hasnt "$pref" 'generated/')"
    printf 'spellings-identical\t%s\n' \
        "$(verdict same "$bare" "$pref")"
    # The refusal to strip greedily: a doubled value stays visibly broken.
    printf 'doubled-stays-broken\t%s\n' \
        "$(verdict has "$dbl" 'generated/gen.txt')"
    # Per-item handling: one list may mix the two spellings.
    if hasnt "$mixed" 'generated/' && hasnt "$mixed" 'docs/' && has "$mixed" 'src/app.txt'; then
        printf 'mixed-list\tpass\n'
    else
        printf 'mixed-list\tfail\n'
    fi
    # The built-in excludes are not collateral damage of the user-exclude loop.
    if hasnt "$base" '.claude/agent.txt' && hasnt "$base" 'packages/bun.lock'; then
        printf 'builtins-hold\tpass\n'
    else
        printf 'builtins-hold\tfail\n'
    fi
    # The issue's own reproduction, against this checkout.
    printf 'live-baseline-has-markers\t%s\n' \
        "$(verdict has "$lbase" "$LIVE_DIR/")"
    if hasnt "$lbare" "$LIVE_DIR/" && hasnt "$lpref" "$LIVE_DIR/" && same "$lbare" "$lpref"; then
        printf 'live-both-spellings-clean\tpass\n'
    else
        printf 'live-both-spellings-clean\tfail\n'
    fi
}

# --- 1. the real script: every row green --------------------------------------
echo "1. behaviour (scripts/../pull-tech-debt.sh)" >&2
BASELINE="$(matrix "$SCRIPT")"
while IFS="$(printf '\t')" read -r row res; do
    [ -z "$row" ] && continue
    if [ "$res" = "pass" ]; then ok "$row"; else bad "$row"; fi
done <<EOF
$BASELINE
EOF

# --- 2. mutation proof --------------------------------------------------------
# Each mutant rewrites ONE line of a copy. Reach is derived from re-running the
# same matrix, never asserted in prose.
echo "2. mutation proof" >&2

STRIP_LINE='EXCLUDES+=(":(exclude)${p#'
BUILTIN_LINE=':(exclude).claude/**'

mutate() {  # $1 = out path, $2 = match substring, $3 = replacement line
    awk -v m="$2" -v r="$3" 'index($0, m) { print r; next } { print }' "$SCRIPT" >"$1"
}

# no-strip: the pre-fix line, which double-prefixes every configured value.
mutate "$WORK/m-nostrip.sh" "$STRIP_LINE" '  EXCLUDES+=(":(exclude)$p")'
# greedy-strip: `//` removes EVERY occurrence, silently repairing a doubled value.
mutate "$WORK/m-greedy.sh" "$STRIP_LINE" '  EXCLUDES+=(":(exclude)${p//:(exclude)/}")'
# no-loop: the user-exclude loop body becomes a no-op.
mutate "$WORK/m-noloop.sh" "$STRIP_LINE" '  :'
# no-builtin: one of the always-on excludes is dropped from the array.
mutate "$WORK/m-nobuiltin.sh" "$BUILTIN_LINE" '  # built-in removed by mutant'

reached=""
for m in nostrip greedy noloop nobuiltin; do
    mfile="$WORK/m-$m.sh"
    if ! grep -qF -- "$STRIP_LINE" "$SCRIPT"; then
        bad "the strip line moved — every mutant below is a no-op; re-anchor them"
        break
    fi
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
# preconditions. A precondition asserts the fixture is capable of showing the
# bug, so by construction the excluding code cannot change its verdict.
DECLARED_UNREACHED="baseline-leaks live-baseline-has-markers"
all_rows="$(printf '%s\n' "$BASELINE" | awk -F'\t' '{ print $1 }' | sort)"
reached_sorted="$(printf '%s\n' $reached | sort -u | grep -v '^$')"
unreached="$(comm -23 <(printf '%s\n' "$all_rows") <(printf '%s\n' "$reached_sorted") | tr '\n' ' ')"
declared_sorted="$(printf '%s\n' $DECLARED_UNREACHED | sort | tr '\n' ' ')"
if [ "${unreached% }" = "${declared_sorted% }" ]; then
    ok "rows no mutant reaches == declared preconditions (${declared_sorted% })"
else
    bad "unreached rows '${unreached% }' != declared '${declared_sorted% }'"
fi

# --- 3. source and docs -------------------------------------------------------
echo "3. source and docs" >&2

header="$(sed -n '1,30p' "$SCRIPT")"
if has "$header" 'canonical spelling is BARE' && has "$header" 'ALSO accepted'; then
    ok "the script header names bare as canonical and records that both spellings are accepted"
else
    bad "the script header no longer states the two-spelling contract — a reader cannot tell which form to write"
fi
if has "$header" 'At most ONE prefix is stripped'; then
    ok "the header records that the strip is bounded, not greedy"
else
    bad "the header lost the at-most-one rule that doubled-stays-broken enforces"
fi

# The one doc site that moved. Searched tree-wide, not at a line number: the
# point is that NO tracked file teaches the prefixed spelling again. THIS FILE
# is in that corpus, so the pattern is assembled from two pieces rather than
# written out — the alternative is exempting this path, which would leave the
# gate blind to the one file most likely to grow a copy of the bad spelling.
prefixed_form='exclude_pathspecs: ":'"(exclude)"
# Point it at a known positive first: an assembled pattern that quietly stops
# matching would report a clean tree forever.
printf '%s%s\n' "$prefixed_form" 'packages/db/src/migrations"' >"$WORK/badspelling.txt"
if grep -qF -e "$prefixed_form" "$WORK/badspelling.txt"; then
    ok "the prefixed-form pattern matches a line that carries it"
else
    bad "the prefixed-form pattern matches nothing — the tree-wide scan below is vacuous"
fi
prefixed_docs="$(git -C "$REPO_ROOT" grep -lIF -e "$prefixed_form" || true)"
if [ -z "$prefixed_docs" ]; then
    ok "no tracked file writes exclude_pathspecs in the prefixed form"
else
    bad "prefixed exclude_pathspecs still taught in: $(printf '%s' "$prefixed_docs" | tr '\n' ' ')"
fi
if has "$(cat "$CONTRACT")" 'exclude_pathspecs: "packages/db/src/migrations"'; then
    ok "config-contract.md's survey-work example spells the bare form"
else
    bad "config-contract.md's survey-work exclude_pathspecs example is gone or changed shape"
fi

# SCAN_PATHS is out of scope for issue #365 and must stay that way: the
# `:(glob)` claim it would rest on did not reproduce. This row fails if a later
# change quietly rewrites SCAN_PATHS while "fixing excludes".
if grep -qF -- 'SCAN=(${SCAN_PATHS:-.})' "$SCRIPT"; then
    ok "SCAN_PATHS handling is unchanged (out of scope, deliberately)"
else
    bad "SCAN_PATHS handling changed — #365 decided that needs verification, not a fix"
fi

if [ "$fail" -ne 0 ]; then
    echo "test-tech-debt-excludes: FAILED" >&2
    exit 1
fi
echo "Tech-debt exclude tests: all green"
