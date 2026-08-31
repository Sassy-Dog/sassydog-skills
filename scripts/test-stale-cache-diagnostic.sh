#!/usr/bin/env bash
# Pins the stale-cache diagnostic and the no-auto-stamp record (issues #296, #301).
#
# WHY THIS EXISTS. #301 shipped three decisions and NONE of them was pinned by
# anything. Worse, the idiom it deleted — `ls` the cache directory and compare
# the version STRING against the manifest — was itself shipped deliberately, in
# #12, and survived until #296 measured it giving the wrong answer. A documented
# diagnostic that returns "current" on a stale cache is worse than no diagnostic,
# because a reader who runs it stops looking.
#
# THE DECISIONS, and each is the kind a later "simplify this" sweep removes:
#
#   1. COMPARE CONTENT, NEVER VERSION STRINGS. Measured on `main`: cache and
#      clone both at `2026.8.100`, with 18 skill files and all ten agent files
#      differing. The version string cannot distinguish N merges of content
#      because the manifest is stamped only in release PRs — which is #296's
#      other half, still open and blocked on branch protection owned by
#      Terraform in `Sassy-Dog/platform`.
#   2. THE `--scope` WARNING. `claude plugin update` defaults to `user`. A
#      reader who correctly identifies a `project` copy and then runs the bare
#      command updates the WRONG copy, sees no error, and finds the comparison
#      unchanged. The failure is silent on both the read and the write side.
#   3. THE COMPARISON MUST BE ABLE TO FAIL LOUDLY. `diff` on a missing path
#      writes to STDERR and leaves stdout empty, and silence is this block's
#      "current" answer — so the `2>&1` and the `[ -d ]` guard are what make the
#      documented rule true of what a reader actually sees. Drop either and the
#      block reports "current" for a path that was never compared.
#
# It reads two tracked files. No gh, no network, no repo mutation.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

asserts=0; fails=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1" >&2; }
bad() { asserts=$((asserts + 1)); fails=$((fails + 1)); echo "  FAIL  $1" >&2; }

README="README.md"
VERSIONING="docs/VERSIONING.md"

echo "stale-cache diagnostic + no-auto-stamp record (issues #296, #301)"

for f in "$README" "$VERSIONING"; do
    if [ -r "$f" ]; then ok "read $f"; else bad "missing file: $f"; fi
done
[ "$fails" -eq 0 ] || { echo "test-stale-cache-diagnostic: FAILED" >&2; exit 1; }

# Flattened AND emphasis-stripped, because this repo hard-wraps prose: a
# line-scoped grep turns a wrap into a false verdict, and that is a false PASS
# for a must-exist and a false PASS for a veto alike.
flat() { tr '\n' ' ' <"$1" | tr -s ' '; }
emph() { flat "$1" | sed -e 's/\*//g' -e 's/`//g'; }

README_FLAT="$(flat "$README")";     README_EMPH="$(emph "$README")"
VERS_FLAT="$(flat "$VERSIONING")";   VERS_EMPH="$(emph "$VERSIONING")"

has() { if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi; }

# A VETO that fails CLOSED: grep exits 2 on an invalid ERE, and an
# `if grep … || grep …` reads that as "not found" — a veto failing open, the one
# direction a veto must never fail.
absent() { # <plain> <stripped> <ERE> <label>
    local a b
    grep -qE -- "$3" <<<"$1"; a=$?
    grep -qE -- "$3" <<<"$2"; b=$?
    if [ "$a" -ge 2 ] || [ "$b" -ge 2 ]; then
        bad "$4 — the veto pattern is malformed (grep rc $a/$b); it would fail OPEN"
    elif [ "$a" -eq 0 ] || [ "$b" -eq 0 ]; then
        bad "$4"
    else
        ok "$4"
    fi
}

# --- 1. content, never the version string ------------------------------------
has "$README_FLAT" "Compare content" "the diagnostic's step is COMPARE CONTENT"
has "$README_FLAT" "diff -rq" "it compares with diff -rq rather than reading a version"
has "$README_FLAT" "Any output at all means the cache is stale" \
    "any output at all means stale — the rule a reader scanning for 'differ' would miss"

# THE DELETED IDIOM. #12 shipped it, it survived until #296 measured it wrong,
# and it is exactly what a reader reaching for the simplest check re-invents.
absent "$README_FLAT" "$README_EMPH" 'ls ~/\.claude/plugins/cache/sassydog-skills/sassy-dog/' \
    "the ls-the-cache-directory idiom has not come back"
absent "$README_FLAT" "$README_EMPH" 'Compare against .?version.? in .?\.claude-plugin/plugin\.json.? on .?main' \
    "and nothing tells a reader to compare against the manifest version again"

# --- 2. all three directories, and WHY scripts/ is one of them ---------------
# SCOPED TO THE CODE BLOCK, and that scoping is the whole assertion. Measured:
# checking the flattened FILE for `skills`, `agents`, `scripts`, `2>&1` and
# `[ -d ` passed on a README whose code block had each of them REMOVED, because
# the paragraph underneath explains every one by name. A presence check
# satisfied by the prose ABOUT a guard rather than by the guard is the exact
# false pass this gate exists to refuse — three mutants proved it before this
# window existed.
compare_block="$(awk '
    /^```bash$/ { buf = ""; inblk = 1; next }
    inblk && /^```$/ { if (buf ~ /diff -rq/) { printf "%s", buf; exit } inblk = 0; next }
    inblk { buf = buf $0 "\n" }' "$README")"
if [ -n "$compare_block" ]; then
    ok "the content-compare code block resolves"
else
    bad "the content-compare code block did not resolve — every check over it would be vacuous"
fi

hasb() { if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3"; fi; }
hasb "$compare_block" "for d in skills agents scripts; do" \
    "the loop itself compares all three directories"
hasb "$compare_block" "2>&1" \
    "the diff folds stderr into stdout IN THE CODE, not only in the prose"
hasb "$compare_block" '[ -d "$INSTALL_PATH/$d" ]' \
    "the directory guard is IN THE CODE, not only in the prose"
hasb "$compare_block" "diff -rq" \
    "and the comparison is diff -rq over content"
# Matched on the EMPHASIS-STRIPPED copy: the phrase carries a backtick mid-word
# (`align-labels.sh\` is the only root-\`scripts/\``), so a literal match against
# the plain text fails on prose that is present and correct.
has "$README_EMPH" "align-labels.sh is the only root-scripts/ path any skill invokes at runtime" \
    "scripts/ is justified by the one file a skill invokes at runtime, not by bulk"

# --- 3. the comparison can fail loudly ---------------------------------------
has "$README_FLAT" "silence is the answer that means" \
    "and the reason is stated: silence is this block's CURRENT answer"
has "$README_FLAT" "is **not** a clean result" \
    "an error naming a missing path is explicitly not a clean result"

# The four output shapes. A reader scanning for `differ` skips the two that say
# a file is missing OUTRIGHT, which is what was measured on a real copy.
for row in 'Files … differ' 'Only in …/marketplaces/…' 'Only in …/cache/…' 'no output'; do
    has "$README_FLAT" "$row" "the output table carries the '$row' row"
done

# --- 4. the --scope trap, on BOTH sides --------------------------------------
has "$README_FLAT" "--scope" "the update command carries --scope"
has "$README_FLAT" "defaults to" "and states that the default is not always the reader's copy"
has "$README_FLAT" "the same wrong-copy trap as step 1, on the write side" \
    "the wrong-copy trap is named on the WRITE side too, not just the read side"
has "$VERS_FLAT" "--scope <scope>" "VERSIONING's update command carries --scope as well"

# --- 5. step 2 is load-bearing ------------------------------------------------
has "$README_FLAT" "Step 2 is load-bearing rather than tidiness" \
    "refreshing the marketplace clone is stated to be load-bearing, not tidiness"

# --- 6. the no-auto-stamp record (#296's blocked half) ------------------------
has "$VERS_FLAT" "so the committed value lags, by design and by a wide margin" \
    "VERSIONING records that the committed value lags by design"
has "$VERS_FLAT" "git log -1 -G" \
    "and gives the REPRODUCIBLE way to find the last stamp (-G on the version line)"
has "$VERS_FLAT" "which is not the same thing" \
    "stating why plain 'git log -1 -- <path>' answers a different question"

# --- 7. vacuity floor ---------------------------------------------------------
# A floor beneath the count cannot tell "everything measured" from "an extractor
# silently stopped matching". Set just under today's total so a collapse fails
# and a deliberate trim does not.
FLOOR=26
if [ "$asserts" -ge "$FLOOR" ]; then
    ok "assertion floor met ($asserts >= $FLOOR)"
else
    bad "only $asserts assertions ran (floor $FLOOR) — an extractor is matching nothing"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-stale-cache-diagnostic: FAILED ($fails of $asserts assertions)" >&2
    exit 1
fi
echo "stale-cache diagnostic tests: all green ($asserts assertions)"
