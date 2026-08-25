#!/usr/bin/env bash
# test-gotcha-claims.sh — a `gotcha_summary` claim about issue state may not
# reach an issue body unless it has been CONFIRMED against that issue (#249).
#
# The field is prose in a frontmatter slot, so it inherits neither protection
# the config format provides: nothing derives it, and it is not in the `##` lane
# a human curates. `Sassy-Dog/solador`'s carried "#15 is not finished — #308
# (updater) and #334 (Windows + Authenticode) remain" for nine days after all
# three closed, aimed at a cold worktree agent with no way to check it.
#
# WHY THE STALE FIXTURE IS THE POINT. A verifier that accepts everything is
# indistinguishable from one that works — every clean config passes either way,
# and the day it matters is the day it is fed something wrong. So the load-
# bearing case here is section 1: a config whose claim the mock `gh` flatly
# contradicts must exit 3, must name the contradiction, and the dropped text
# must be ABSENT from the safe block. Sections 8 and 9 mutation-prove exactly
# that, by neutering the comparison and the unresolvable branch in a copy of the
# script and requiring the stale cases to pass — a proof that the assertions
# above are not passing for some unrelated reason.
#
# THE SECOND FAILURE MODE IS DEGRADATION. `gh` missing, an undetermined repo, a
# lookup that fails: the tempting shape is a skip, and a skip on this gate is a
# silent pass on exactly the input the gate exists for. Section 6 pins it —
# no `gh` on PATH, stale fixture, still exit 3 — and section 10 pins the absence
# of any skip exit in the source, because a later "be helpful when gh is
# missing" edit re-creates the bug with no test failing.
#
# Sections 11-13 are source-level, against the three prose files that carry the
# decision: a rule nobody wrote down is one the next author re-litigates. Their
# must-not-exist checks run against a WHITESPACE-FLATTENED copy, because this
# repo hard-wraps prose and a line-scoped grep turns a wrap into a false PASS.
#
# SECTIONS 14-19: A CLAIM MUST FIRST BE A CLAIM (issue #262). Everything above
# tests the classifier, and the classifier was never what failed — the string
# handed to it was not a claim. The sentence splitter could not see backticks,
# so the `;` in `code=0; cmd || code=$?` ended a claim mid-span; the tail kept
# the `(#N)` and dropped, and the truncated HEAD cited nothing, was therefore
# classified an invariant, and was emitted inside the SAFE markers a caller
# copies verbatim into an issue body. Fail-closed on a fabricated claim is not
# fail-closed.
#
# FOUR INPUTS DEFEATED FOUR NARROWER FIXES, and all four are kept as fixtures.
# Each was found AFTER the fix that was supposed to have closed the class: a
# ``…`` span (tick-wise pairing binds the opening pair to itself); an unpaired
# run that mis-binds BEFORE the stray tick (so the quarantine cannot be
# prefix-only); an EVEN number of stray ticks (every run finds a partner and
# the binding is still wrong); and a mis-bind that exposes a real span, where
# no span body carries sentence punctuation at all. The lesson is in the
# sequence, not in any one of them: which ticks the author meant is not
# decidable from the text, so every rule about WHERE the cut lands has a next
# input.
#
# SO THE GUARD THAT BOUNDS THE FAMILY IS GROUP LINKAGE (section 17). Fragments
# of a sentence are tagged with a group, resolved individually, and COMMITTED
# TOGETHER: if any fragment drops, none of that group is certified. A mis-parse
# then costs a drop rather than a half-sentence presented as verified. Two
# guesses were tried and deleted, and the verifier's header records why so they
# are not reintroduced — backtick PARITY (blind to a cut between an even number
# of ticks, and to one in text carrying none) and a padded-span HEURISTIC
# (missed the fourth input and dropped legal Markdown).
#
# LINKAGE ALONE WAS NOT ENOUGH EITHER: deciding where a sentence STARTS is the
# same guess as deciding where to cut. A fifth input, `Deploy only to U.S. East
# until #999 …`, certified `Deploy only to U.S.` — complete, grammatical and
# meaning-INVERTED. So the default is inverted: splitting needs POSITIVE
# evidence (a terminator, and a preceding token that is not
# abbreviation-shaped). Its accepted cost is over-linking — section 18 asserts
# a neighbouring invariant being dropped for a citation that is not its own,
# deliberately, so nobody "fixes" it back. The class is BOUNDED, NOT CLOSED: a
# sentence whose referent was dropped can still survive, which needs anaphora.
#
# THE ROOT CASE HAS NO BACKTICK IN IT AT ALL (section 19). `;` matched the
# boundary regex, so a clause was an independent claim: the clause carrying the
# citation dropped and the survivors were rejoined into a confident inversion
# of the field. That shape was live on `main` and no amount of pairing work
# could ever have reached it. `e.g.`/`i.e.`/`etc.` are the same shape.
#
# MUTATION SCOPE IS DELIBERATE, AND SECTION 20 ASSERTS THE SCOPE ITSELF.
# Linkage is proved only on the two fixtures where it is the SOLE protection,
# and run-pairing only where linkage cannot save the field — a mutation aimed
# at a fixture some other rule already covers reports `undetected` and proves
# nothing, loudly. Which rule protects which fixture is therefore MEASURED into
# a matrix and compared against a declared table, so the scoping fails loudly
# when coverage moves instead of rotting into a comment that is no longer true. `apply_mutation`
# refuses the vacuity `cmp -s` allows: it exits 2 on a MISSING file, which an
# `if` reads as "differs", so a sed that matched nothing would report
# `mutation applied` and every negative assertion after it would pass against a
# file that was never run. Section 17f guards that guard, and section 14
# requires every probe string to be present in the fixture, since a probe that
# is absent from the input passes exactly like one that is satisfied.
#
# Mock `gh` only: no repo, no network, no live issue ever read.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-gotcha-claims.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-gotcha-claims: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPT="skills/github-issues/scripts/verify-gotcha-claims.sh"
GROOM="skills/groom-backlog/SKILL.md"
CONTRACT="skills/setup-config/references/config-contract.md"
TEMPLATE="skills/setup-config/references/templates/groom-backlog.config.md"

for f in "$SCRIPT" "$GROOM" "$CONTRACT" "$TEMPLATE"; do
    [ -f "$f" ] || { echo "test-gotcha-claims: $f missing" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "gotcha-claims tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
# States are fixed: #15/#308/#334 CLOSED (the real solador outcome), #77 OPEN,
# everything else genuinely unknown — `gh` exits non-zero, as it does for an
# issue in another repo or one the token cannot see.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" = "repo" ]; then
    echo "Sassy-Dog/solador"
    exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
    case "${3:-}" in
        15|308|334) echo "CLOSED"; exit 0 ;;
        77)         echo "OPEN"; exit 0 ;;
        *)          echo "gh: issue not found" >&2; exit 1 ;;
    esac
fi
echo "mock gh: unexpected call: $*" >&2
exit 1
MOCK
chmod +x "$WORK/bin/gh"

# --- a PATH with no gh on it -------------------------------------------------
# Not `PATH=/usr/bin:/bin`: GitHub-hosted runners ship `gh` in /usr/bin, so that
# spelling would quietly become "gh present, network reachable" in CI — the one
# environment this gate most needs to be honest in. Symlink in exactly the tools
# the script uses and nothing else, then assert gh really is unreachable.
NOGH_BIN="$WORK/nogh"
mkdir -p "$NOGH_BIN"
for t in bash env awk sed tr grep mktemp cat sort rm; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -s "$p" "$NOGH_BIN/$t"
done
if PATH="$NOGH_BIN" command -v gh >/dev/null 2>&1; then
    echo "test-gotcha-claims: the no-gh sandbox still resolves gh" >&2
    exit 1
fi

mkconfig() {
    # mkconfig <path> <summary text...>
    local path="$1"; shift
    {
        echo "---"
        echo "gotcha_summary: >"
        printf '  %s\n' "$*"
        echo "---"
        echo
        echo "## extra-rubric"
    } >"$path"
}

STALE="$WORK/stale.md"
mkconfig "$STALE" "Business logic lives in \`crates/\`, never in the Tauri shell. #15 is not finished — #308 (updater) and #334 (Windows + Authenticode) remain."

CLEAN="$WORK/clean.md"
mkconfig "$CLEAN" "Business logic lives in \`crates/\`, never in the Tauri shell. Renaming \`LEGACY_SERVICE\` orphans every stored credential."

CONFIRMED="$WORK/confirmed.md"
mkconfig "$CONFIRMED" "The watchOS target is still blocked on #77, so do not touch it."

UNRESOLVABLE="$WORK/unresolvable.md"
mkconfig "$UNRESOLVABLE" "Codegen output is committed. #999 remains open, so regenerate by hand."

UNVERIFIABLE="$WORK/unverifiable.md"
mkconfig "$UNVERIFIABLE" "See #77 for the migration policy."

# Single-quoted: `$?` and `$f` are fixture text, not this shell's expansions.
# All FOUR boundary characters sit inside a span here and each is followed by a
# SPACE, which is what `[.;!?] +` actually matches — `code=$?` alone does not
# fire, the `?` being followed by a backtick, so `test $? -eq 0` carries the
# real `?` case. Plus the dotted names `*.tf` and `run.sh` #262 asks for.
INLINE="$WORK/inline-code.md"
mkconfig "$INLINE" 'Exit-code capture is `code=0; cmd || code=$?` under `bash -e` (#77), so keep the guard. Helpers load with `. ./scripts/lib.sh`, never `source`. Check it with `test $? -eq 0 && echo ok` before the push. A missing file is `[ ! -f "$f" ] && exit 1`, and `terraform fmt` covers every `*.tf` via `run.sh fmt`.'

# A ``…`` delimiter is the standard Markdown way to show a literal backtick, and
# character-wise toggling pairs its two ticks WITH EACH OTHER — leaving the span
# body exposed and reproducing #262 byte-for-byte past a parity guard, because
# both fragments then carry an even tick count. Measured, not predicted.
DOUBLE="$WORK/double-tick.md"
mkconfig "$DOUBLE" 'Exit-code capture is ``code=0; cmd || code=$?`` under bash -e (#77), so keep the guard.'

# The field itself is mis-written. Two fixtures, stray tick LATE and EARLY: the
# verdict must not depend on where it sits, which is the whole point of judging
# the field rather than the fragments.
UNBALANCED="$WORK/unbalanced.md"
mkconfig "$UNBALANCED" 'Business logic lives in `crates/`, never in the Tauri shell. Exit-code capture is `code=0; cmd under bash -e.'

UNBALANCED_EARLY="$WORK/unbalanced-early.md"
mkconfig "$UNBALANCED_EARLY" 'Exit-code capture is `code=0; cmd under bash -e. Business logic lives in `crates/`, never in the Tauri shell.'

# One stray tick INVERTS the pairing: greedy left-to-right binds tick 1 to
# tick 2, so the prose between them is masked and the code after is not. The
# damage lands BEFORE the unpaired run, which is why a prefix-only quarantine is
# not enough and the whole field has to go.
INVERTED="$WORK/inverted.md"
mkconfig "$INVERTED" 'The flag is `--strict and the guard is `code=0; cmd || code=$?` in run.sh.'

# EVERY run pairs here — two stray literal ticks, an even number — so the
# unpaired-run check never fires, yet greedy binding masks the prose and exposes
# `code=0; cmd || code=$?` to the split. #262 by a third road.
AMBIGUOUS_FIELD="$WORK/ambiguous.md"
mkconfig "$AMBIGUOUS_FIELD" 'Wrap the name in ` when quoting. Exit capture is `code=0; cmd || code=$?` per #999, which remains open. Never use ` alone.'

# The legitimate CommonMark idiom for showing a literal backtick span: padded on
# both sides, but carrying no sentence boundary, so it must NOT be quarantined.
PADDED_SPAN="$WORK/padded-span.md"
mkconfig "$PADDED_SPAN" 'Write a literal tick as `` `a` `` in prose, never bare.'

# No backticks at all. `;` split this into clauses, the middle one dropped on
# its `#999`, and the safe block welded the survivors into an instruction that
# says the opposite of the field. The root cause of the whole family.
CLAUSE_WELD="$WORK/clause-weld.md"
mkconfig "$CLAUSE_WELD" 'Set FOO=1; the guard is disabled per #999, which remains open. Always export it.'

# Two stray ticks, each FLUSH against a word, so each mis-bound span is padded
# on one side only — the shape a both-ends padding test cannot see.
FLUSH_TICK="$WORK/flush-tick.md"
mkconfig "$FLUSH_TICK" 'Set `FOO=1` and note the guard`s state. Exit capture is `code=0; cmd || code=$?` per #999, which remains open. Never use it`s value.'

# The fourth input, found while proving the third fix: two flush stray ticks
# mis-bind so that a REAL span (`. ./scripts/lib.sh`) ends up exposed, and the
# `. ` inside it cuts the sentence. No span body carries sentence punctuation
# here, so every padding heuristic is blind to it by construction.
EXPOSED_SPAN="$WORK/exposed-span.md"
mkconfig "$EXPOSED_SPAN" 'Check the guard`s state before you run `. ./scripts/lib.sh` per #999, which remains open`s note. Done.'

# Correctly paired and legal: padding is REQUIRED Markdown when span content
# starts or ends with a backtick, and `;`/`.` inside a span is the everyday
# shell idiom. The deleted padded-span heuristic dropped this whole field.
LEGAL_PADDED="$WORK/legal-padded.md"
mkconfig "$LEGAL_PADDED" 'The two-step is `` ` git add .; git commit ` ``. Business logic lives in `crates/`.'

# No backticks anywhere: `e.g.` ends a fragment exactly as a full stop does.
ABBREV="$WORK/abbrev.md"
mkconfig "$ABBREV" 'Use the flag, e.g. --strict, per #999, which remains unresolved. Prefer bun.'

# A ``…`` body carrying BOTH a sentence boundary and the citation. Tick-wise
# pairing exposes the boundary; the halves land in DIFFERENT groups because the
# second starts with a capital, so linkage cannot weld them and the half with no
# citation is certified. This is the one shape where run-pairing, not linkage,
# is what stops the fabrication.
DOUBLE_CITED="$WORK/double-cited.md"
mkconfig "$DOUBLE_CITED" 'Escape it as ``run alpha. Then y per #999, which remains open`` in the doc.'

run() {
    # run <PATH-prefix|-> <args...>  -> stdout in $OUT, status in $STATUS
    local pathpfx="$1"; shift
    if [ "$pathpfx" = "-" ]; then
        OUT="$(PATH="$NOGH_BIN" bash "$SCRIPT" "$@" 2>&1)"
    else
        OUT="$(PATH="$pathpfx:$PATH" bash "$SCRIPT" "$@" 2>&1)"
    fi
    STATUS=$?
}

safe_block() {
    printf '%s\n' "$OUT" | awk '/^--- BEGIN SAFE GOTCHAS ---$/{f=1;next} /^--- END SAFE GOTCHAS ---$/{f=0} f'
}

# An odd backtick count in the block the caller copies verbatim is the visible
# signature of a claim cut mid-span — assertable without naming any one claim.
# It requires the block to be NON-EMPTY first: nothing has zero ticks, zero is
# even, and "the backticks pair" would otherwise be printed for a run that
# certified nothing at all.
safe_block_intact() {
    local block ticks
    block="$(safe_block)"
    [ -n "$block" ] || return 1
    ticks="$(printf '%s' "$block" | tr -cd '`')"
    [ $(( ${#ticks} % 2 )) -eq 0 ]
}

# --- mutation helpers --------------------------------------------------------
# `cmp -s` exits 2 on a MISSING file, which an `if` reads as "they differ" — so
# a mutation whose sed matched nothing, or wrote nowhere, reports `ok mutation
# applied` and every negative assertion after it passes against a file that was
# never run. Existence and non-emptiness are therefore checked BEFORE cmp, and
# each mutant must then prove it executed by printing a verdict line.
apply_mutation() {
    # apply_mutation <label> <mutant-path> <source> <sed-expr>...
    local label="$1" out="$2" src="$3"; shift 3
    local args=() e
    for e in "$@"; do args+=(-e "$e"); done
    sed "${args[@]}" "$src" >"$out" 2>/dev/null
    if [ ! -s "$out" ]; then bad "$label — the mutant is missing or empty"; return 1; fi
    if cmp -s "$src" "$out"; then bad "$label — the mutation changed nothing, the proof is vacuous"; return 1; fi
    ok "$label — mutation applied"
    return 0
}

run_mutant() {
    # run_mutant <label> <mutant-path> <PATH-prefix|-> <args...>  -> $OUT, $STATUS
    local label="$1" mut="$2" pathpfx="$3"; shift 3
    if [ "$pathpfx" = "-" ]; then
        OUT="$(PATH="$NOGH_BIN" bash "$mut" "$@" 2>&1)"
    else
        OUT="$(PATH="$pathpfx:$PATH" bash "$mut" "$@" 2>&1)"
    fi
    STATUS=$?
    case "$OUT" in
        *"gotcha-claims: repo="*) return 0 ;;
        *) bad "$label — the mutant printed no verdict line, so it never ran: $OUT"; return 1 ;;
    esac
}

# --- 1. the known-stale fixture ----------------------------------------------
echo "1. stale fixture: a claim the tree contradicts" >&2
run "$WORK/bin" --config "$STALE" --repo Sassy-Dog/solador
[ "$STATUS" -eq 3 ] && ok "exit 3 on a contradicted claim" || bad "expected exit 3, got $STATUS"
case "$OUT" in
    *"DROP"*"contradicted"*) ok "the contradiction is named" ;;
    *) bad "no 'DROP … contradicted' line: $OUT" ;;
esac
case "$OUT" in
    *"#15 is CLOSED"*) ok "reports the real state it read" ;;
    *) bad "the drop line does not name the real state" ;;
esac
case "$(safe_block)" in
    *"#334"*) bad "the dropped claim still reached the safe block" ;;
    *) ok "the dropped claim is absent from the safe block" ;;
esac
case "$(safe_block)" in
    *"never in the Tauri shell"*) ok "the invariant beside it survives" ;;
    *) bad "the invariant was dropped along with the rotted claim" ;;
esac

# --- 2. the clean fixture ----------------------------------------------------
echo "2. invariants-only fixture" >&2
run "$WORK/bin" --config "$CLEAN" --repo Sassy-Dog/solador
[ "$STATUS" -eq 0 ] && ok "exit 0" || bad "expected exit 0, got $STATUS ($OUT)"
case "$OUT" in
    *DROP*) bad "an invariants-only config had a claim dropped" ;;
    *) ok "nothing dropped" ;;
esac
case "$(safe_block)" in
    *"orphans every stored credential"*) ok "both invariants pass through" ;;
    *) bad "an invariant did not reach the safe block" ;;
esac

# --- 3. a confirmed state claim ----------------------------------------------
echo "3. state claim that is currently true" >&2
run "$WORK/bin" --config "$CONFIRMED" --repo Sassy-Dog/solador
[ "$STATUS" -eq 0 ] && ok "exit 0 when the asserted state matches" || bad "expected exit 0, got $STATUS ($OUT)"
case "$OUT" in
    *"KEEP  confirmed"*) ok "kept, and flagged as a claim that rots" ;;
    *) bad "a confirmed claim was not marked confirmed: $OUT" ;;
esac
case "$(safe_block)" in
    *"#77"*) ok "the confirmed claim reaches the safe block" ;;
    *) bad "a confirmed claim was withheld" ;;
esac

# --- 4. unresolvable ---------------------------------------------------------
echo "4. cited issue that cannot be resolved" >&2
run "$WORK/bin" --config "$UNRESOLVABLE" --repo Sassy-Dog/solador
[ "$STATUS" -eq 3 ] && ok "exit 3" || bad "expected exit 3, got $STATUS ($OUT)"
case "$OUT" in
    *"unresolvable"*) ok "the reason is named" ;;
    *) bad "no 'unresolvable' reason: $OUT" ;;
esac
case "$(safe_block)" in
    *"#999"*) bad "an unresolvable claim reached the safe block" ;;
    *) ok "unknown is held, not passed through" ;;
esac
case "$(safe_block)" in
    *"Codegen output is committed."*) ok "the invariant in the same field survives" ;;
    *) bad "the whole field was discarded over one unresolvable claim" ;;
esac

# --- 5. cited with no checkable assertion ------------------------------------
echo "5. issue cited with no state assertion" >&2
run "$WORK/bin" --config "$UNVERIFIABLE" --repo Sassy-Dog/solador
[ "$STATUS" -eq 3 ] && ok "exit 3" || bad "expected exit 3, got $STATUS ($OUT)"
case "$OUT" in
    *"unverifiable"*) ok "named as unverifiable rather than silently kept" ;;
    *) bad "no 'unverifiable' reason: $OUT" ;;
esac

# --- 6. degradation is not a pass --------------------------------------------
echo "6. no gh on PATH — fail-closed, not skip" >&2
run - --config "$STALE" --repo Sassy-Dog/solador
[ "$STATUS" -eq 3 ] && ok "exit 3 with no gh available" || bad "expected exit 3 with no gh, got $STATUS ($OUT)"
[ "$STATUS" -ne 10 ] && ok "not a skip exit" || bad "degraded to a skip"
case "$OUT" in
    *"unresolvable"*) ok "every citing claim is dropped as unresolvable" ;;
    *) bad "no unresolvable drop without gh: $OUT" ;;
esac
case "$(safe_block)" in
    *"#334"*) bad "a claim passed through unverified because gh was missing" ;;
    *) ok "nothing citing an issue survived unverified" ;;
esac

# --- 7. lint mode ------------------------------------------------------------
echo "7. --lint (offline)" >&2
run - --config "$STALE" --lint
[ "$STATUS" -eq 3 ] && ok "exit 3 on a config carrying time-varying claims" || bad "expected exit 3, got $STATUS ($OUT)"
case "$OUT" in
    *"issue-ref"*) ok "the issue reference is reported" ;;
    *) bad "lint missed the issue reference: $OUT" ;;
esac
case "$OUT" in
    *"state-verb"*) ok "the state verb is reported" ;;
    *) bad "lint missed the state verb: $OUT" ;;
esac
run - --config "$CLEAN" --lint
[ "$STATUS" -eq 0 ] && ok "exit 0 on an invariants-only config" || bad "lint fires on invariants: $OUT"
DATED="$WORK/dated.md"
mkconfig "$DATED" "The release path WORKS as of 2026-08-15."
run - --config "$DATED" --lint
[ "$STATUS" -eq 3 ] && ok "an 'as of <date>' claim is reported" || bad "lint missed a dated claim: $OUT"

# --- 8. mutation: neuter the state comparison --------------------------------
# If section 1 passes with the comparison removed, it was never testing it.
echo "8. mutation — the state comparison" >&2
MUT="$WORK/mutant-compare.sh"
if apply_mutation "neuter the state comparison" "$MUT" "$SCRIPT" \
    's|^        expected="OPEN"$|        expected="$state"|' \
    '/^        \[ "\$assert" = "closed" \] \&\& expected="CLOSED"$/d'; then
    if run_mutant "compare" "$MUT" "$WORK/bin" --config "$STALE" --repo Sassy-Dog/solador; then
        [ "$STATUS" -eq 0 ] && ok "the neutered verifier accepts the stale config (so section 1 is load-bearing)" \
            || bad "the neutered verifier still failed ($STATUS) — section 1 proves something else"
    fi
fi

# --- 9. mutation: neuter the unresolvable branch -----------------------------
echo "9. mutation — unresolvable treated as open" >&2
MUT2="$WORK/mutant-unresolved.sh"
if apply_mutation "treat unresolvable as open" "$MUT2" "$SCRIPT" \
    's|^    state="UNRESOLVED"$|    state="OPEN"|'; then
    if run_mutant "unresolved" "$MUT2" - --config "$STALE" --repo Sassy-Dog/solador; then
        [ "$STATUS" -eq 0 ] && ok "assuming-open makes the no-gh run pass (so section 6 is load-bearing)" \
            || bad "the neutered verifier still failed ($STATUS) — section 6 proves something else"
    fi
fi

# --- 10. no skip exit in the source ------------------------------------------
# The whole design is "unknown is held". A later `exit 10` for a missing gh
# re-creates #249 with every test above still green, because every fixture here
# has a gh to talk to except section 6 — which is exactly what such an edit
# would turn into a pass.
echo "10. source: no skip exit" >&2
if grep -qE '^[[:space:]]*exit 10\b' "$SCRIPT"; then
    bad "the verifier has a skip exit — unknown must be held, never skipped"
else
    ok "no skip exit"
fi
if grep -q "NO skip exit" "$SCRIPT"; then
    ok "the decision is recorded in the header"
else
    bad "the header no longer records why there is no skip exit"
fi

# --- flattening for the prose gates ------------------------------------------
flatten() {
    tr '\n' ' ' <"$1" | sed -E 's/[[:space:]]+/ /g'
}
FLAT_GROOM="$WORK/flat-groom.txt"
FLAT_CONTRACT="$WORK/flat-contract.txt"
FLAT_TEMPLATE="$WORK/flat-template.txt"
flatten "$GROOM" >"$FLAT_GROOM"
flatten "$CONTRACT" >"$FLAT_CONTRACT"
flatten "$TEMPLATE" >"$FLAT_TEMPLATE"

must_exist() {
    # must_exist <flat-file> <label> <pattern>
    if grep -qF -- "$3" "$1"; then ok "$2"; else bad "$2 — missing: $3"; fi
}

# --- 11. groom-backlog carries the injection gate ----------------------------
echo "11. groom-backlog/SKILL.md" >&2
must_exist "$FLAT_GROOM" "invokes the verifier" "verify-gotcha-claims.sh"
must_exist "$FLAT_GROOM" "injects only the safe block" "BEGIN SAFE GOTCHAS"
must_exist "$FLAT_GROOM" "unknown is held" "Unknown is held, never passed through"
must_exist "$FLAT_GROOM" "unresolvable drops too" "Unresolvable is dropped too"
must_exist "$FLAT_GROOM" "every drop is reported" "gotchas dropped:"
# The pre-fix instruction copied the field straight into the body. Its wording
# is recorded here so the must-not-exist check below cannot go vacuous.
PREFIX_WORDING="Record the repo gotchas a cold sub-agent needs, from the config's"
if grep -qF -- "$PREFIX_WORDING" "$FLAT_GROOM"; then
    bad "still instructs copying gotcha_summary straight into the body"
else
    ok "the raw-field instruction is gone"
fi
printf '%s\n' "4. $PREFIX_WORDING \`gotcha_summary\`." >"$WORK/prefix-groom.txt"
if grep -qF -- "$PREFIX_WORDING" "$WORK/prefix-groom.txt"; then
    ok "that check matches the pre-fix wording (not vacuous)"
else
    bad "the must-not-exist pattern matches nothing, even the pre-fix text"
fi

# --- 12. the contract carries the rule ---------------------------------------
echo "12. config-contract.md" >&2
must_exist "$FLAT_CONTRACT" "states the rule" "INVARIANTS ONLY"
must_exist "$FLAT_CONTRACT" "worked good example" "never in the Tauri shell"
must_exist "$FLAT_CONTRACT" "worked rotting example" "(Windows + Authenticode) remain"
must_exist "$FLAT_CONTRACT" "bans an issue number with a state claim" "issue number with a state claim"
must_exist "$FLAT_CONTRACT" "bans as-of dates" "as of \`<date>\`"
must_exist "$FLAT_CONTRACT" "bans roadmap status" "Roadmap status"
must_exist "$FLAT_CONTRACT" "names the injection-time gate" "verify-gotcha-claims.sh"
must_exist "$FLAT_CONTRACT" "existing configs are detectable" "--lint"

# --- 13. the template steers the generator -----------------------------------
echo "13. groom-backlog.config.md template" >&2
must_exist "$FLAT_TEMPLATE" "the slot carries the rule" "INVARIANTS ONLY"
must_exist "$FLAT_TEMPLATE" "points at the contract" "config-contract.md"

# --- 14. inline code does not end a claim ------------------------------------
# The fixture is built from shell idioms, NOT from this repo's own config: run
# against `.claude/sassy-dog/groom-backlog.md` the verifier reports 5/5/0 both
# before and after the fix, because no in-span `.` there is followed by a SPACE
# — which is what `[.;!?] +` matches. (That field does contain in-span dots, in
# `` `.claude-plugin/plugin.json` ``; dots are not the point, `. ` is.) A
# fixture drawn from there proves nothing.
echo "14. code spans carrying . ; ! ? do not split a claim" >&2
run "$WORK/bin" --config "$INLINE" --repo Sassy-Dog/solador
# THREE groups, not four sentences: `before the push.` ends in a 4-character
# token, so the sentence after it is welded on. That is the inversion's
# accepted cost showing up in the primary fixture — the point of this assertion
# is that no SPAN was cut, which the intact-span probes below establish.
case "$OUT" in
    *"claims=3"*) ok "three groups — no span was cut (two sentences welded, by design)" ;;
    *) bad "the field did not resolve to 3 groups: $OUT" ;;
esac
case "$OUT" in
    *"DROP  unverifiable"*'under `bash -e` (#77), so keep the guard.'*)
        ok "the #77 citation is judged on the whole sentence" ;;
    *) bad "the citing claim was not judged whole: $OUT" ;;
esac
case "$(safe_block)" in
    *"Exit-code capture"*) bad "a truncated head reached the safe block" ;;
    *) ok "no fragment of the dropped claim reached the safe block" ;;
esac
case "$(safe_block)" in
    *'`. ./scripts/lib.sh`'*) ok ". — a leading-dot span survives intact" ;;
    *) bad "the \`. ./scripts/lib.sh\` span was cut" ;;
esac
case "$(safe_block)" in
    *'`test $? -eq 0 && echo ok`'*) ok "? — a question-mark span survives intact" ;;
    *) bad "the \`test \$? -eq 0\` span was cut" ;;
esac
case "$(safe_block)" in
    *'`[ ! -f "$f" ] && exit 1`'*) ok "! — a bang span survives intact" ;;
    *) bad "the \`[ ! -f \"\$f\" ]\` span was cut" ;;
esac
case "$(safe_block)" in
    *'`*.tf`'*'`run.sh fmt`'*) ok "\`*.tf\` and \`run.sh\` survive intact" ;;
    *) bad "a dotted-filename span was cut" ;;
esac
if safe_block_intact; then
    ok "the safe block is non-empty and its backticks pair"
else
    bad "the safe block is empty or carries an unterminated backtick"
fi
# ANTI-VACUITY. Every assertion above is "this substring is in the safe block",
# which passes for free if the substring is not in the FIXTURE either — a typo
# in a probe reads exactly like a pass. Each probe is therefore required to be
# present in the fixture source first, and the `? ` boundary is checked
# explicitly: the pre-#262 fixture's only `?` was `code=$?`, followed by a
# backtick, so the boundary it claimed to cover could never fire.
for probe in '`. ./scripts/lib.sh`' '`test $? -eq 0 && echo ok`' \
             '`[ ! -f "$f" ] && exit 1`' '`*.tf`' '`run.sh fmt`' 'Exit-code capture'; do
    if grep -qF -- "$probe" "$INLINE"; then
        ok "probe present in the fixture: $probe"
    else
        bad "probe absent from the fixture — the assertion using it is vacuous: $probe"
    fi
done
case "$OUT" in
    *'test $? -eq 0 '*) ok "the ? case is a real \`? \` followed by a space, not \`code=\$?\`" ;;
    *) bad "no \`? \` boundary in the fixture — the ? assertion is vacuous" ;;
esac

# --- 15. a ``…`` span is one span, not two ticks -----------------------------
# Pairing tick-by-tick binds the two opening backticks to EACH OTHER and leaves
# the body exposed, which reproduces #262 in full: the head carries an even tick
# count, so a parity guard waves it through and classifies it an invariant.
echo "15. a double-backtick span does not split" >&2
run "$WORK/bin" --config "$DOUBLE" --repo Sassy-Dog/solador
case "$OUT" in
    *"claims=1"*) ok "one claim — the double-backtick span body was not cut" ;;
    *) bad "the double-tick field did not resolve to 1 claim: $OUT" ;;
esac
case "$OUT" in
    *"DROP  unverifiable"*) ok "judged whole, and dropped on its own citation" ;;
    *) bad "not judged as one unverifiable claim: $OUT" ;;
esac
case "$(safe_block)" in
    *"Exit-code capture"*) bad "a truncated head from a double-backtick span reached the safe block" ;;
    *) ok "nothing from the dropped claim reached the safe block" ;;
esac

# --- 16. an unpaired run quarantines the WHOLE field -------------------------
# Not just the text after it: greedy pairing is a guess about which ticks were
# delimiters, and an unpaired run proves the guess wrong somewhere without
# saying where. `INVERTED` is the proof that the damage can land BEFORE the
# stray tick, so a prefix-only quarantine still certifies a fabricated head.
echo "16. an unpaired backtick run drops the whole field" >&2
for fixture in "$UNBALANCED" "$UNBALANCED_EARLY" "$INVERTED"; do
    label="$(basename "$fixture" .md)"
    run "$WORK/bin" --config "$fixture" --repo Sassy-Dog/solador
    [ "$STATUS" -eq 3 ] && ok "$label: exit 3" || bad "$label: expected exit 3, got $STATUS ($OUT)"
    case "$OUT" in
        *"DROP  malformed"*) ok "$label: named as malformed" ;;
        *) bad "$label: no 'DROP … malformed' line: $OUT" ;;
    esac
    case "$OUT" in
        *"claims=1"*) ok "$label: the field is one unparseable unit, not fragments" ;;
        *) bad "$label: the field was split despite being unparseable: $OUT" ;;
    esac
    if [ -z "$(safe_block)" ]; then
        ok "$label: nothing is certified"
    else
        bad "$label: something reached the safe block: $(safe_block)"
    fi
done
# The verdict must not depend on where the stray tick sits — that is the whole
# reason the field, not the fragment, is what gets judged.
run "$WORK/bin" --config "$UNBALANCED" --repo Sassy-Dog/solador
late="$OUT"
run "$WORK/bin" --config "$UNBALANCED_EARLY" --repo Sassy-Dog/solador
case "${late#*claims=}${OUT#*claims=}" in
    "1 kept=0 dropped=1"*"1 kept=0 dropped=1"*) ok "same verdict whether the stray tick is early or late" ;;
    *) bad "the verdict moved with the stray tick's position" ;;
esac
# --lint sees it too: a config that lints clean while losing a claim at
# injection teaches the operator the wrong thing about their own config.
run - --config "$UNBALANCED" --lint
[ "$STATUS" -eq 3 ] && ok "--lint reports it offline" || bad "--lint missed the unpaired run: $OUT"
case "$OUT" in
    *"MALFORMED unpaired-backtick-run"*) ok "--lint names the shape" ;;
    *) bad "--lint did not name the unpaired run: $OUT" ;;
esac

# --- 17. GROUP LINKAGE is the guard the others were approximating ------------
# Every fixture below defeated a previous, narrower fix: three rounds of
# tightening WHERE the cut lands, each with a next input. Linkage changes what
# is COMMITTED instead — fragments of one sentence live or die together — so a
# mis-parse costs a drop rather than a lie. Removing it must bring every one of
# those fabrications back, and this is the mutation that proves it.
echo "17. mutation — group linkage" >&2
MUTG="$WORK/mutant-nolinkage.sh"
if apply_mutation "give every fragment its own group" "$MUTG" "$SCRIPT" \
    's|function starts_new(prev,   t) {|function starts_new(prev,   t) { return 1;|'; then
    # Fixtures for which section 20 measures linkage as the SOLE protection.
    # CLAUSE_WELD is a third; two are enough here, and section 20 is what keeps
    # this list honest — a mutation aimed at a fixture some other rule also
    # covers reports `undetected` and proves nothing, loudly.
    for probe in "EXPOSED_SPAN:before you run \`." \
                 "ABBREV:Use the flag, e.g."; do
        var="${probe%%:*}"; want="${probe#*:}"
        cfg="${!var}"   # indirect expansion: eval here would hide it from shellcheck
        if run_mutant "nolinkage/$var" "$MUTG" "$WORK/bin" --config "$cfg" --repo Sassy-Dog/solador; then
            case "$(safe_block)" in
                *"$want"*) ok "$var: without linkage the fabrication returns" ;;
                *) bad "$var: no fabrication without linkage — the fixture proves nothing: $OUT" ;;
            esac
        fi
    done
fi

# --- 17b. the parse still earns its keep -------------------------------------
# With linkage in place a bad parse is no longer DANGEROUS, so these mutations
# are asserted on PRESERVATION, not on fabrication. That distinction is the
# layering: the parse decides how much of a good field survives, linkage decides
# that a bad one cannot lie.
echo "17b. mutation — the span mask (preservation)" >&2
MUT3="$WORK/mutant-unmasked.sh"
if apply_mutation "unmask the span body" "$MUT3" "$SCRIPT" \
    's|out = out ticks SOH nspan STX ticks|out = out ticks span[nspan] ticks|'; then
    if run_mutant "unmask" "$MUT3" "$WORK/bin" --config "$INLINE" --repo Sassy-Dog/solador; then
        case "$OUT" in
            *"claims=4"*) bad "the unmasked splitter still yields 4 claims — section 14 proves something else" ;;
            *) ok "the unmasked splitter cuts the field into more claims" ;;
        esac
        case "$(safe_block)" in
            *'Exit-code capture is `code=0;'*) bad "it fabricated despite linkage — linkage is not holding" ;;
            *) ok "but linkage still refuses to certify a truncated head" ;;
        esac
    fi
fi

echo "17c. mutation — run-length pairing (preservation)" >&2
MUT4="$WORK/mutant-tickwise.sh"
if apply_mutation "pair tick-by-tick instead of run-by-run" "$MUT4" "$SCRIPT" \
    's|while (i + run <= len \&\& substr(line, i + run, 1) == "`") run++|run = 1|'; then
    if run_mutant "tickwise" "$MUT4" "$WORK/bin" --config "$DOUBLE_CITED" --repo Sassy-Dog/solador; then
        # The body carries BOTH a sentence boundary and the citation, so
        # tick-wise pairing exposes the boundary, the halves land in different
        # groups, and the citation-free half is certified. Linkage cannot save
        # this one. Section 20 records that MASKING also covers it, so this
        # proves run-pairing is load-bearing — not that it is solely
        # responsible, which would be the easy overstatement.
        case "$(safe_block)" in
            *'``run alpha.'*) ok "tick-wise pairing fabricates past linkage (so run-pairing is load-bearing)" ;;
            *) bad "tick-wise pairing did not fabricate — section 15 proves something else: $OUT" ;;
        esac
    fi
fi

echo "17d. mutation — the whole-field quarantine" >&2
MUT5="$WORK/mutant-noquarantine.sh"
if apply_mutation "let an unpaired field fall through to the split" "$MUT5" "$SCRIPT" \
    's|if (unpaired) { nspan = 0; emit("UNPAIRED", 1, line); next }|if (0) { }|'; then
    if run_mutant "noquarantine" "$MUT5" "$WORK/bin" --config "$UNBALANCED" --repo Sassy-Dog/solador; then
        case "$OUT" in
            *"DROP  malformed"*) bad "the unpaired field was still quarantined — section 16 proves something else" ;;
            *) ok "without it an unpaired field is parsed as if it were sound (so section 16 is load-bearing)" ;;
        esac
    fi
fi

echo "17e. mutation — the splitter's failure is not swallowed" >&2
# `| split_claims ... || true` would turn a broken splitter into "empty field,
# exit 0" — a clean all-clear on a field nobody parsed.
MUT6="$WORK/mutant-brokensplit.sh"
if apply_mutation "make the splitter fail outright" "$MUT6" "$SCRIPT" \
    's|^split_claims() {$|split_claims() { return 9; #|'; then
    if OUT="$(PATH="$WORK/bin:$PATH" bash "$MUT6" --config "$CLEAN" --repo Sassy-Dog/solador 2>&1)"; then
        bad "a failed splitter exited 0 — a silent all-clear on an unparsed field"
    else
        ok "a failed splitter does not exit 0"
    fi
    case "$OUT" in
        *"splitter failed"*) ok "and says so rather than reporting an empty field" ;;
        *) bad "a failed splitter was reported as an empty field: $OUT" ;;
    esac
fi

# --- 17f. the vacuity guard itself works -------------------------------------
# `apply_mutation` exists because `cmp -s` exits 2 on a MISSING file, which an
# `if` reads as "differs". Guarding the guard: a sed that matches nothing must
# be REPORTED, not waved through. Run it in a subshell so its deliberate
# failure does not mark this suite failed.
echo "17f. a no-op mutation is refused" >&2
if ( fail=0; apply_mutation "no-op probe" "$WORK/mutant-noop.sh" "$SCRIPT" \
        's|ZZZ_THIS_MATCHES_NOTHING_ZZZ|x|' >/dev/null 2>&1; exit "$fail" ); then
    bad "a sed matching nothing was accepted as a mutation"
else
    ok "a sed matching nothing is refused as vacuous"
fi

# --- 18. the four inputs that defeated the four narrower fixes ---------------
# Each of these was found AFTER the fix that was supposed to have closed the
# class, and each is kept as a fixture so the next narrowing cannot quietly
# reopen it. What they now share is a verdict, not a mechanism: the sentence is
# dropped whole and nothing partial is certified.
echo "18. every known mis-parse degrades to an honest drop" >&2
for probe in "AMBIGUOUS_FIELD:an even number of stray ticks" \
             "FLUSH_TICK:stray ticks flush against a word" \
             "EXPOSED_SPAN:a mis-bind that exposes a dot-source span" \
             "CLAUSE_WELD:a clause welded across a dropped citation"; do
    var="${probe%%:*}"; label="${probe#*:}"
    cfg="${!var}"   # indirect expansion: eval here would hide it from shellcheck
    run "$WORK/bin" --config "$cfg" --repo Sassy-Dog/solador
    [ "$STATUS" -eq 3 ] && ok "$label: exit 3" || bad "$label: expected exit 3, got $STATUS ($OUT)"
    case "$(safe_block)" in
        *'`code=0;'*|*'run `.'*|*"Set FOO=1;"*)
            bad "$label: a fragment was certified: $(safe_block)" ;;
        *) ok "$label: no fragment of the dropped sentence is certified" ;;
    esac
done
# THE ACCEPTED COST, asserted so nobody "fixes" it back. `…which remains open.`
# ends in a 4-character token, so `Always export it.` is welded to the dropped
# sentence and goes with it. A neighbouring invariant is lost. That is the
# trade the inversion took deliberately: over-linking is lossy and visible in
# the report, whereas the alternative certified `Deploy only to U.S.` — a
# complete, meaning-inverted sentence the author never wrote.
run "$WORK/bin" --config "$CLAUSE_WELD" --repo Sassy-Dog/solador
case "$(safe_block)" in
    *"Always export it."*) bad "the trailing sentence survived — the inversion is not in effect" ;;
    *) ok "the welded neighbour is lost with its group (the accepted cost)" ;;
esac
# Losing a neighbour is only acceptable because nothing partial is certified.
if [ -z "$(safe_block)" ]; then
    ok "and nothing partial is certified in its place"
else
    bad "something was certified from a dropped group: $(safe_block)"
fi

# --- 18b. correctly-paired input is never quarantined ------------------------
# The deleted padded-span heuristic dropped these. Space padding is REQUIRED
# Markdown when span content starts or ends with a backtick, and `;`/`.` inside
# a span is the ordinary shell idiom this whole change exists to protect.
echo "18b. legal input survives untouched" >&2
for probe in "PADDED_SPAN:a padded double-backtick span" \
             "LEGAL_PADDED:a padded span carrying ; and ." \
             "CLEAN:ordinary invariants"; do
    var="${probe%%:*}"; label="${probe#*:}"
    cfg="${!var}"   # indirect expansion: eval here would hide it from shellcheck
    run "$WORK/bin" --config "$cfg" --repo Sassy-Dog/solador
    [ "$STATUS" -eq 0 ] && ok "$label: exit 0" || bad "$label: legal input was dropped ($OUT)"
    case "$OUT" in
        *"DROP"*) bad "$label: legal input produced a DROP" ;;
        *) ok "$label: nothing dropped" ;;
    esac
done
case "$(safe_block)" in
    *"Business logic lives in \`crates/\`"*) ok "the unrelated invariant beside it is intact" ;;
    *) bad "the invariant beside the padded span was lost: $(safe_block)" ;;
esac

# --- 19. a semicolon does not end a sentence ---------------------------------
# `;` joins clauses INSIDE a sentence. Splitting there made a clause an
# independent claim, which is what let the citation-bearing clause drop while
# its neighbours were rejoined into a confident inversion of the original.
# Linkage would now catch it regardless — this keeps the citation judged on the
# whole sentence rather than on a clause of it.
echo "19. a semicolon joins clauses, it does not end a claim" >&2
run "$WORK/bin" --config "$CLAUSE_WELD" --repo Sassy-Dog/solador
# One group: `;` no longer cuts, and the inversion welds the trailing sentence
# on. What matters is that the clause carrying the citation is never separated
# from the text around it.
case "$OUT" in
    *"claims=1"*) ok "one group — the clause is never an independent claim" ;;
    *) bad "the clause was still split out: $OUT" ;;
esac
case "$OUT" in
    *"DROP  unresolvable"*"Set FOO=1; the guard is disabled per #999"*)
        ok "the citation is judged on the whole sentence, clause included" ;;
    *) bad "the citing sentence was not judged whole: $OUT" ;;
esac

# --- 19b. an abbreviation is not a sentence end ------------------------------
# `e.g.` matches `[.!?] +` exactly like a full stop, so the fragment before it
# is a sentence fragment. It has no backtick in it at all, which is why no
# amount of pairing work could ever have reached it.
echo "19b. e.g./i.e./etc. do not end a claim" >&2
run "$WORK/bin" --config "$ABBREV" --repo Sassy-Dog/solador
case "$(safe_block)" in
    *"Use the flag, e.g."*) bad "an abbreviation fragment was certified: $(safe_block)" ;;
    *) ok "the fragment before the abbreviation is not certified alone" ;;
esac
case "$(safe_block)" in
    *"Prefer bun."*) ok "the real sentence beside it survives" ;;
    *) bad "the whole field went, not just the affected sentence: $(safe_block)" ;;
esac



# --- 20. the coverage matrix is asserted, not asserted-about ----------------
# Narrow mutation scoping is only honest if the SCOPE itself is checked. A
# comment saying "linkage is the sole protection for ABBREV" rots silently: if
# a later change makes some other rule cover it, the mutation in section 17
# quietly starts proving nothing and still reports `detected`.
#
# THE DETECTOR IS GENERAL, AND THAT IS THE WHOLE POINT OF THIS SECTION. Its
# first version probed for a per-fixture LITERAL fragment, and was wrong in
# four cells — including one that declared the unpaired-run quarantine
# redundant while removing it certified `Exit-code capture is` at exit 0, a
# silent all-clear. A literal derived from today's behaviour cannot see a
# fabrication that truncates to a different string tomorrow, which is the same
# self-confirmation this whole gate exists to refuse. So a mutant "fabricates"
# when it certifies text THE UNMUTATED RUN DOES NOT — no literals, no sentence
# model, and a mutant that merely drops more is correctly not counted.
#
# ITS ONE BOUNDARY, stated rather than discovered later: containment cannot see
# a truncation whose text is a SUBSTRING of the reference block. Every fixture
# here carries a dropping citation, so the reference is empty or shorter and
# the detector is exact. Add a fixture whose citation verifies TRUE and the
# unmutated run keeps the whole sentence — a truncating mutant would then read
# as "no fabrication". That fails SAFE: the row-equality check below reports
# `declared [X], observed [none]` and goes red rather than passing quietly.
echo "20. coverage matrix (which rules protect each fixture)" >&2

MATRIX_MUTANTS="linkage tickwise unquarantine unmask semicolon"
apply_mutation "matrix: sentence-start inversion" "$WORK/mx-linkage.sh" "$SCRIPT" \
    's|function starts_new(prev,   t) {|function starts_new(prev,   t) { return 1;|' >/dev/null
apply_mutation "matrix: run-length pairing" "$WORK/mx-tickwise.sh" "$SCRIPT" \
    's|while (i + run <= len \&\& substr(line, i + run, 1) == "`") run++|run = 1|' >/dev/null
apply_mutation "matrix: unpaired quarantine" "$WORK/mx-unquarantine.sh" "$SCRIPT" \
    's|if (unpaired) { nspan = 0; emit("UNPAIRED", 1, line); next }|if (0) { }|' >/dev/null
apply_mutation "matrix: span mask" "$WORK/mx-unmask.sh" "$SCRIPT" \
    's|out = out ticks SOH nspan STX ticks|out = out ticks span[nspan] ticks|' >/dev/null
apply_mutation "matrix: semicolon boundary" "$WORK/mx-semicolon.sh" "$SCRIPT" \
    's|gsub(/\[.!?\] +/, "&\\n", out)|gsub(/[.;!?] +/, "\&\\n", out)|' >/dev/null

# Declared coverage, MEASURED with the general detector above.
#   * Four of the five rules are each LOAD-BEARING for at least one fixture —
#     removing it there reproduces a real fabrication. Only three are ever the
#     SOLE protection (linkage, unmask, unquarantine); `tickwise` shares
#     DOUBLE_CITED with `unmask`, which is why the floors below test presence
#     in a row rather than sole responsibility.
#   * DOUBLE_CITED has two protections (run-pairing and masking), so 17c
#     proves run-pairing is load-bearing, not solely responsible.
#   * `semicolon` is the one column with no fixture. That does NOT make the
#     rule redundant and is not grounds for deleting it: its job is that a
#     citation is judged on a whole sentence rather than on a clause of it,
#     which section 19 asserts directly. An empty column here means only that
#     no fixture's FABRICATION is prevented by it alone.
matrix_declared() {
    case "$1" in
        EXPOSED_SPAN)    printf '%s' 'linkage' ;;
        ABBREV)          printf '%s' 'linkage' ;;
        CLAUSE_WELD)     printf '%s' 'linkage' ;;
        DOUBLE_CITED)    printf '%s' 'tickwise unmask' ;;
        AMBIGUOUS_FIELD) printf '%s' 'unmask' ;;
        FLUSH_TICK)      printf '%s' 'unmask' ;;
        UNBALANCED)      printf '%s' 'unquarantine' ;;
    esac
}

matrix_covered=""
for fx in EXPOSED_SPAN ABBREV CLAUSE_WELD DOUBLE_CITED AMBIGUOUS_FIELD FLUSH_TICK UNBALANCED; do
    cfg="${!fx}"
    run "$WORK/bin" --config "$cfg" --repo Sassy-Dog/solador
    reference="$(safe_block)"
    observed=""
    for m in $MATRIX_MUTANTS; do
        OUT="$(PATH="$WORK/bin:$PATH" bash "$WORK/mx-$m.sh" --config "$cfg" --repo Sassy-Dog/solador 2>&1)"
        got="$(safe_block)"
        [ -z "$got" ] && continue
        case "$reference" in
            *"$got"*) ;;                      # certified no more than the real run
            *) observed="$observed $m" ;;     # certified text the real run does not
        esac
    done
    observed="$(printf '%s' "$observed" | sed -E 's/^ +//; s/ +$//')"
    want="$(matrix_declared "$fx")"
    if [ "$observed" = "$want" ]; then
        ok "$fx: protected by [$want]"
    else
        bad "$fx: coverage moved — declared [${want:-none}], observed [${observed:-none}]"
    fi
    matrix_covered="$matrix_covered $observed"
done

# Vacuity floors. A matrix in which no mutation ever fabricates would pass
# every row above while proving that none of the mutations work at all.
for m in linkage tickwise unquarantine unmask; do
    case " $matrix_covered " in
        *" $m "*) ok "matrix: '$m' is load-bearing for at least one fixture" ;;
        *) bad "matrix: '$m' protects no fixture — its mutation proves nothing" ;;
    esac
done


if [ "$fail" -eq 0 ]; then
    echo "gotcha-claims: all assertions passed" >&2
    exit 0
fi
echo "gotcha-claims: FAILURES above" >&2
exit 1
