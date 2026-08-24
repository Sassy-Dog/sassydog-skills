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
sed -e 's|^        expected="OPEN"$|        expected="$state"|' \
    -e '/^        \[ "\$assert" = "closed" \] \&\& expected="CLOSED"$/d' \
    "$SCRIPT" >"$MUT"
if cmp -s "$SCRIPT" "$MUT"; then
    bad "the mutation changed nothing — the proof is vacuous"
else
    ok "mutation applied"
    OUT="$(PATH="$WORK/bin:$PATH" bash "$MUT" --config "$STALE" --repo Sassy-Dog/solador 2>&1)"
    STATUS=$?
    [ "$STATUS" -eq 0 ] && ok "the neutered verifier accepts the stale config (so section 1 is load-bearing)" \
        || bad "the neutered verifier still failed ($STATUS) — section 1 proves something else"
fi

# --- 9. mutation: neuter the unresolvable branch -----------------------------
echo "9. mutation — unresolvable treated as open" >&2
MUT2="$WORK/mutant-unresolved.sh"
sed -e 's|^    state="UNRESOLVED"$|    state="OPEN"|' "$SCRIPT" >"$MUT2"
if cmp -s "$SCRIPT" "$MUT2"; then
    bad "the mutation changed nothing — the proof is vacuous"
else
    ok "mutation applied"
    OUT="$(PATH="$NOGH_BIN" bash "$MUT2" --config "$STALE" --repo Sassy-Dog/solador 2>&1)"
    STATUS=$?
    [ "$STATUS" -eq 0 ] && ok "assuming-open makes the no-gh run pass (so section 6 is load-bearing)" \
        || bad "the neutered verifier still failed ($STATUS) — section 6 proves something else"
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

if [ "$fail" -eq 0 ]; then
    echo "gotcha-claims: all assertions passed" >&2
    exit 0
fi
echo "gotcha-claims: FAILURES above" >&2
exit 1
