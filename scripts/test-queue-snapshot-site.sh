#!/usr/bin/env bash
# test-queue-snapshot-site.sh — the execution site is read from LABELS, and the
# three body contracts are untouched by that (issue #340, epic #322).
#
# WHY A LABEL, and why this gate is small. #340 first shipped `site:` as a
# fourth BODY contract, beside `touches:`, `Depends on #N` and `stack:`. A body
# line can be quoted, so an issue documenting the contract — or a template
# carrying an unfilled placeholder — declared a site by accident, and both
# issues introducing the contract did exactly that. Preventing it meant
# deciding what a fenced block, a code span, an HTML comment, an info string
# and their interactions mean: a subset of CommonMark, discovered one review at
# a time. Four rounds found four more shapes at a flat rate while the surface
# grew. A label cannot be quoted in prose, so the whole class is gone and this
# file is what is left of it.
#
# THE BODY CONTRACTS MUST NOT HAVE MOVED. `touches:`, `stack:` and `Depends on`
# read the raw line exactly as they did before #340, and section 8 pins that
# from the direction that matters: a body carrying a prose `site:` line — a
# fenced example, a template placeholder — declares nothing at all now.
#
# WHAT THE ROWS COVER, and the one that is a rule rather than a case:
#   * present -> value, absent -> null, in BOTH buckets (sections 1-2).
#   * the emitted shape is the pre-#340 key set plus `site` and `sites`, checked
#     as a SET so a renamed or dropped field fails (section 3).
#   * folding, on the key and on the value independently, and a value written
#     with spaces around it (section 4).
#   * PREFIX, never substring: `offsite:x` and a label named `website` declare
#     nothing (section 5).
#   * an empty value declares nothing, and does not turn a real declaration
#     beside it into a conflict (section 6).
#   * SEVERAL labels must never resolve to "any site" (section 7). That is the
#     direction #322's originating bug ran — an unread declaration letting the
#     wrong loop claim the issue — so `sites` is the fact and `site` is null on
#     a conflict as well as on an absence. The rows pin both halves, because a
#     consumer reading the scalar alone is reading half the contract.
#
# THE MUTANTS' REACH IS DERIVED, NEVER WRITTEN DOWN. The version of this gate
# that #340 first shipped carried a hand-written roster asserting which rows
# each mutant reddened, over a 21x94 matrix nothing re-computed. Three separate
# rounds of review found three rows that had gone vacuous — reachable by no
# mutant, or by a different one than the roster claimed — and each time the fix
# was to correct the sentence. The sentence was the defect. So `mutant` diffs
# each mutant's answers against the shipped baseline, and two things are
# checked against that flip set rather than against prose: the row a mutant
# names is a MEMBER of it, and the rows NO mutant flips are derived and
# compared to `UNPINNED_ROWS`. A row nothing can redden proves nothing, and
# this is what makes that state impossible to add silently.
#
# Network-free: a PATH-shimmed mock `gh`. `REPO=<owner/name>` in the
# environment suppresses queue-snapshot's `gh repo view` lookup (it runs that
# only when REPO is EMPTY). Three things make "no network" structural rather
# than intended: the shim's resolution is verified immediately after `chmod`
# and EXITS if PATH did not pick it up, the slug uses the RFC 2606 `.invalid`
# TLD because `mock-org` is a REAL GitHub organization, and the mock HONOURS
# `--json`, so dropping `labels` from the pull reddens rather than passing.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-queue-snapshot-site.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-queue-snapshot-site: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SNAP="$REPO_ROOT/skills/github-issues/scripts/queue-snapshot.sh"
[ -f "$SNAP" ] || { echo "test-queue-snapshot-site: $SNAP not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-queue-snapshot-site: jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "test-queue-snapshot-site: python3 is required" >&2; exit 1; }

WORK="$(mktemp -d)"
# FAIL CLOSED, STRUCTURALLY. There is no `set -e` here (see the options line
# above), so a failed `mktemp -d` leaves $WORK EMPTY and execution continues
# into `mkdir -p "$WORK/bin"` — that is `mkdir -p /bin`, `cat > /bin/gh`,
# `chmod +x /bin/gh`. Non-root hosts fail the write and the run dies loudly; as
# root (devcontainer, docker CI image, `act`, a root self-hosted runner) it
# succeeds and leaves a fake `gh` on PATH permanently, while `rm -rf ""` cleans
# nothing. Same guard, same reason, as scripts/test-file-or-link-issue.sh.
if [ -z "$WORK" ] || [ ! -d "$WORK" ] || [ "$WORK" = "/" ]; then
    echo "mktemp -d did not produce a usable scratch directory (got '${WORK:-}'); refusing to run" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
FX="$WORK/fixtures"
mkdir -p "$BIN" "$FX"

fail=0
asserts=0
ok()  { asserts=$((asserts + 1)); echo "  ok    $1" >&2; }
bad() { asserts=$((asserts + 1)); fail=1; echo "  FAIL  $1" >&2; }

echo "queue-snapshot site labels (issue #340) — work: $WORK" >&2

# --- the mock gh --------------------------------------------------------------
# queue-snapshot makes exactly two kinds of call: `gh api user` and one
# `gh issue list … --label <bucket> --json <fields>` per bucket. Anything else
# is a contract breach and exits non-zero, which queue-snapshot turns into an
# empty bucket — caught by the size assertions rather than passed over.
#
# `--json` is HONOURED: each fixture is projected to the requested field list,
# the same way scripts/test-stale-issues.sh and scripts/test-file-or-link-issue.sh
# do it. A mock that served whole objects regardless would keep every row here
# green after `labels` was dropped from the pull, which is now the one change
# that silently empties every site.
cat >"$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
    api)
        [ "${2:-}" = "user" ] || { echo "mock gh: unhandled api call: $*" >&2; exit 1; }
        echo "mock-login"
        ;;
    issue)
        [ "${2:-}" = "list" ] || { echo "mock gh: unhandled issue call: $*" >&2; exit 1; }
        label=""; fields=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --label) label="${2:-}"; shift 2 ;;
                --json)  fields="${2:-}"; shift 2 ;;
                *)       shift ;;
            esac
        done
        [ -n "$label" ]  || { echo "mock gh: issue list without --label" >&2; exit 1; }
        [ -n "$fields" ] || { echo "mock gh: issue list without --json" >&2; exit 1; }
        f="$SCENARIO_DIR/$label.json"
        [ -f "$f" ] || { echo "mock gh: no payload for label '$label'" >&2; exit 1; }
        jq --arg fields "$fields" \
            'map(with_entries(select(.key as $k | ($fields | split(",")) | index($k))))' "$f"
        ;;
    *) echo "mock gh: unhandled invocation: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$BIN/gh"

# STRUCTURAL, not ordering. A failed `chmod`, or a noexec `$TMPDIR`, means PATH
# search skips the shim and queue-snapshot reaches the operator's REAL `gh` —
# read-only here, but authenticated requests against somebody else's namespace,
# and this file's header claims "no network". Same shape and same reason as
# test-file-or-link-issue.sh: the check sits immediately after the chmod and
# EXITS rather than recording a failed assertion.
if [ "$(PATH="$BIN:$PATH" command -v gh)" != "$BIN/gh" ]; then
    echo "test-queue-snapshot-site: the mock gh shim did not install at $BIN/gh — refusing to run, because every read below would reach the real GitHub API" >&2
    exit 1
fi

# --- recorded issues ----------------------------------------------------------
python3 - "$FX" <<'PY'
import json, os, sys

out = sys.argv[1]

def issue(n, title, labels, body="", assignees=()):
    return {
        "number": n,
        "title": title,
        "body": body,
        "labels": [{"name": x} for x in labels],
        "assignees": [{"login": x} for x in assignees],
    }

PROSE = (
    "The contract used to live here:\n\n"
    "```text\nsite: vdi\n```\n\n"
    "site: vdi\n"
)

ready = [
    # 101 — the contract.
    issue(101, "declared", ["ready", "site:vdi"]),
    # 102 — nothing declared. Also the control for the emitted key set, and it
    # carries the body contracts so section 3 can check them unchanged.
    issue(102, "undeclared", ["ready"], "touches: a/b c/d\nDepends on #7\n"),
    # 103/112 — folding, keyed separately so one mutant cannot cover both.
    issue(103, "key case", ["ready", "SITE:vdi"]),
    issue(112, "value case", ["ready", "site:VDI"]),
    # 104 — a label written with spaces around the value.
    issue(104, "padded value", ["ready", "site: vdi "]),
    # 105 — TWO declarations. `site` must not read as "any site".
    issue(105, "conflict", ["ready", "site:vdi", "site:mac"]),
    # 106 — the same site twice, spelled differently: one declaration, not a
    # conflict. Without this row, deduplication and conflict detection are
    # indistinguishable.
    issue(106, "same site twice", ["ready", "site:vdi", "Site:VDI"]),
    # 107/108 — PREFIX, not substring, from both sides: a longer name that
    # CONTAINS the prefix, and one that starts with it but has no colon.
    issue(107, "prefix not substring", ["ready", "offsite:x"]),
    issue(108, "no colon", ["ready", "website"]),
    # 109 — a bare `site:` names no site.
    issue(109, "empty value", ["ready", "site:"]),
    # 110 — and an empty one beside a real one is not a conflict.
    issue(110, "empty beside real", ["ready", "site:", "site:vdi"]),
    # 111 — THE REASON FOR THE MOVE. A body that quotes the old body contract,
    # fenced and in prose, declares nothing at all.
    issue(111, "prose only", ["ready"], PROSE),
]

in_progress = [
    issue(201, "claimed, declared", ["in-progress", "site:vdi"], "", ["mock-login"]),
    issue(202, "claimed, undeclared", ["in-progress"], "", ["someone-else"]),
]

blocked = [{"number": 301}, {"number": 302}]

for name, payload in (("ready", ready), ("in-progress", in_progress), ("blocked", blocked)):
    with open(os.path.join(out, name + ".json"), "w") as fh:
        json.dump(payload, fh)
PY

READY_N=12

# --- runner -------------------------------------------------------------------
OUT="$WORK/out.json"
STATUS=0
run_snapshot() { # <script-path>
    PATH="$BIN:$PATH" SCENARIO_DIR="$FX" REPO=mock-org.invalid/mock-repo \
        bash "$1" >"$OUT" 2>"$WORK/err"
    STATUS=$?
}

site_of()  { jq -r --argjson n "$2" ".$1[] | select(.number==\$n) | .site | tostring" "$OUT"; }
sites_of() { jq -c --argjson n "$2" ".$1[] | select(.number==\$n) | .sites" "$OUT"; }

expect_site() { # <label> <bucket> <number> <expected>
    local got; got="$(site_of "$2" "$3")"
    if [ "$got" = "$4" ]; then ok "$1"; else bad "$1 — #$3 site=$got, expected $4"; fi
}
expect_sites() { # <label> <bucket> <number> <expected-json>
    local got; got="$(sites_of "$2" "$3")"
    if [ "$got" = "$4" ]; then ok "$1"; else bad "$1 — #$3 sites=$got, expected $4"; fi
}

# --- 0. the run, and the buckets are populated --------------------------------
# queue-snapshot turns a failed `gh issue list` into `[]`, so a broken mock
# would empty every bucket. That does not pass silently — `site_of` on an empty
# bucket yields the empty string, which every row below rejects — so this
# assertion is the DIAGNOSTIC: it turns a page of red rows into one line naming
# the cause, and runs first so that line is read first.
echo "0. the snapshot runs and the mock served every bucket" >&2
run_snapshot "$SNAP"
if [ "$STATUS" = "0" ]; then
    ok "queue-snapshot exits 0 against the mock"
else
    bad "queue-snapshot exited $STATUS"
    sed 's/^/          | /' "$WORK/err" >&2
fi
if jq -e . "$OUT" >/dev/null 2>&1; then ok "stdout is valid JSON"; else bad "stdout is not valid JSON"; fi
n_ready="$(jq '.ready | length' "$OUT")"
n_flight="$(jq '.in_flight | length' "$OUT")"
n_blocked="$(jq '.blocked | length' "$OUT")"
if [ "$n_ready" = "$READY_N" ] && [ "$n_flight" = "2" ] && [ "$n_blocked" = "2" ]; then
    ok "buckets are populated (ready=$READY_N in_flight=2 blocked=2)"
else
    bad "bucket sizes ready=$n_ready in_flight=$n_flight blocked=$n_blocked, expected $READY_N/2/2"
    sed 's/^/          | /' "$WORK/err" >&2
fi

# --- 1/2. present and absent, in BOTH buckets ---------------------------------
echo "1. a site: label declares, in both buckets" >&2
expect_site  "a site:vdi label declares in ready[]" ready 101 vdi
expect_sites "  and sites carries it" ready 101 '["vdi"]'
expect_site  "and in in_flight[] — both buckets, per #340" in_flight 201 vdi

echo "2. no site: label declares nothing, in both buckets" >&2
expect_site  "no site: label in ready[] gives null" ready 102 null
expect_sites "  with an empty sites" ready 102 '[]'
expect_site  "no site: label in in_flight[] gives null" in_flight 202 null

# --- 3. no shape change for existing consumers --------------------------------
# A key SET check, not a spot check: a renamed or dropped field is the failure
# this catches, and `site`/`sites` are the only additions permitted.
echo "3. the emitted shape is the old one plus site and sites" >&2
ready_keys="$(jq -r '.ready[] | select(.number==102) | keys_unsorted | sort | join(",")' "$OUT")"
flight_keys="$(jq -r '.in_flight[] | select(.number==202) | keys_unsorted | sort | join(",")' "$OUT")"
if [ "$ready_keys" = "assignees,depends_on,labels,number,site,sites,stack,title,touches,unannotated" ]; then
    ok "ready[] carries exactly its pre-#340 keys plus site and sites"
else
    bad "ready[] keys drifted: $ready_keys"
fi
if [ "$flight_keys" = "assignees,labels,mine,number,site,sites,stack,title,touches" ]; then
    ok "in_flight[] carries exactly its pre-#340 keys plus site and sites"
else
    bad "in_flight[] keys drifted: $flight_keys"
fi
control="$(jq -c '.ready[] | select(.number==102) | {touches, depends_on, stack, unannotated}' "$OUT")"
if [ "$control" = '{"touches":["a/b","c/d"],"depends_on":[7],"stack":[],"unannotated":false}' ]; then
    ok "and the body contracts are byte-for-byte what they were"
else
    bad "the body contracts changed: $control"
fi
if [ "$(jq -r '.in_flight[] | select(.number==201) | .mine' "$OUT")" = "true" ]; then
    ok "the 'mine' flag still resolves beside a declared site"
else
    bad "'mine' no longer resolves on an issue carrying a site label"
fi
if [ "$(jq -c '.blocked' "$OUT")" = "[301,302]" ]; then
    ok "blocked[] is still bare numbers"
else
    bad "blocked[] changed shape"
fi

# --- 4. folding and whitespace ------------------------------------------------
echo "4. the key and the value both fold" >&2
expect_site "the KEY folds: SITE:vdi declares" ready 103 vdi
expect_site "the VALUE folds: site:VDI declares vdi" ready 112 vdi
expect_site "a value written with spaces around it is stripped" ready 104 vdi

# --- 5. prefix, never substring -----------------------------------------------
echo "5. the match is a prefix" >&2
expect_site  "offsite:x is not a site label" ready 107 null
expect_sites "  and declares nothing" ready 107 '[]'
expect_site  "a label named 'website' is not one either" ready 108 null

# --- 6. an empty value names no site ------------------------------------------
echo "6. a bare site: label declares nothing" >&2
expect_site  "site: with no value gives null" ready 109 null
expect_sites "  and an empty sites" ready 109 '[]'
expect_site  "and it does not make a real declaration beside it a conflict" ready 110 vdi

# --- 7. several labels must never read as "any site" --------------------------
# The fail-safe direction. #322's originating bug was an unread declaration
# letting the wrong loop claim an issue, and a conflict resolving to "any site"
# is that bug with two labels instead of none.
echo "7. two declarations are a conflict, not an absence" >&2
expect_sites "sites carries BOTH declared values" ready 105 '["mac","vdi"]'
expect_site  "  and the scalar refuses to pick one" ready 105 null
expect_sites "the same site twice is ONE declaration, not a conflict" ready 106 '["vdi"]'
expect_site  "  so the scalar still resolves" ready 106 vdi

# --- 8. the body declares nothing — the reason for the move -------------------
echo "8. a prose site: line in the body declares nothing" >&2
expect_site  "a body quoting the old contract, fenced and in prose, declares nothing" ready 111 null
expect_sites "  and carries no site at all" ready 111 '[]'

# --- 9. mutation proofs, and the matrix derived from them ---------------------
# `mutant` diffs each mutant's answers against the shipped baseline and records
# the flip set. The row a mutant names must be a MEMBER of it; nothing else
# about its reach is asserted, because a hand-written claim about reach is what
# went stale three times in this gate's first life.
echo "9. mutation proofs" >&2
MUT="$WORK/mutant.sh"
mutants_run=0
FLIPPED="$WORK/flipped.txt"
: >"$FLIPPED"

site_map() {
    jq -r '.ready[] | "\(.number)\t\(.site|tostring)|\(.sites|tostring)"' "$1" | sort -n
}
run_snapshot "$SNAP"
BASELINE="$WORK/baseline.tsv"
site_map "$OUT" >"$BASELINE"
if [ "$(grep -c . "$BASELINE")" = "$READY_N" ]; then
    ok "captured the shipped baseline for all $READY_N rows"
else
    bad "the baseline holds $(grep -c . "$BASELINE") rows, expected $READY_N — every flip set below would be measured against the wrong thing"
fi

mutant() { # <label> <named-row> <from> <to>
    local label="$1" named="$2" flips
    if ! python3 - "$SNAP" "$MUT" "$3" "$4" <<'PY'
import io, sys
src, dst, frm, to = sys.argv[1:5]
s = io.open(src, encoding="utf-8").read()
if s.count(frm) != 1:
    sys.stderr.write("occurrences=%d\n" % s.count(frm))
    sys.exit(1)
io.open(dst, "w", encoding="utf-8").write(s.replace(frm, to))
PY
    then
        bad "$label — the mutation target did not match exactly once in $SNAP (stale mutant)"
        return 1
    fi
    if cmp -s "$SNAP" "$MUT"; then
        bad "$label — the mutant is identical to the source"
        return 1
    fi
    run_snapshot "$MUT"
    if [ "$STATUS" != "0" ] || ! jq -e ".ready | length == $READY_N" "$OUT" >/dev/null 2>&1; then
        bad "$label — the mutant did not run (exit $STATUS), so its verdict proves nothing"
        return 1
    fi
    mutants_run=$((mutants_run + 1))
    site_map "$OUT" >"$WORK/mutant.tsv"
    # Rows whose answer differs from the baseline. Both files carry the same
    # row numbers in the same order, so a changed value is a line unique to one.
    flips="$(comm -13 "$BASELINE" "$WORK/mutant.tsv" | cut -f1 | tr '\n' ' ')"
    printf '%s\n' $flips >>"$FLIPPED"
    case " $flips " in
        *" $named "*) ok "$label reddens row $named as declared (flips: ${flips% })" ;;
        *) bad "$label does NOT redden row $named — it flips '${flips% }'. Either the roster names the wrong row or the decision has stopped being load-bearing" ;;
    esac
    return 0
}

if mutant "M1: without the extraction nothing declares" 101 \
    '            if value:
                found.add(value)' \
    '            pass'; then :; fi

if mutant "M2: a substring test lets offsite:x declare" 107 \
    '        if name[:len(SITE_PREFIX)].lower() == SITE_PREFIX:' \
    '        if SITE_PREFIX in name.lower():'; then :; fi

if mutant "M3: without the key fold SITE:vdi stops declaring" 103 \
    '        if name[:len(SITE_PREFIX)].lower() == SITE_PREFIX:' \
    '        if name[:len(SITE_PREFIX)] == SITE_PREFIX:'; then :; fi

if mutant "M4: without the value fold site:VDI declares a different site" 112 \
    '            value = name[len(SITE_PREFIX):].strip().lower()' \
    '            value = name[len(SITE_PREFIX):].strip()'; then :; fi

if mutant "M5: without the empty-value filter a bare site: names a site" 109 \
    '            if value:' \
    '            if True:'; then :; fi

if mutant "M6: a scalar that picks one of two turns a conflict into a claim" 105 \
    '        "site": sites[0] if len(sites) == 1 else None,' \
    '        "site": sites[0] if sites else None,'; then :; fi

if mutant "M7: dropping labels from the pull darkens every site" 101 \
    'FIELDS="number,title,labels,assignees,body"' \
    'FIELDS="number,title,assignees,body"'; then :; fi

# Every mutant in this section ran. Derived from the source rather than
# transcribed: the count is whatever `mutant` was called with, and a call that
# died has already recorded its own failure above.
declared="$(grep -c '^if mutant ' "$0")"
if [ "$mutants_run" -eq "$declared" ]; then
    ok "every declared mutant ran ($mutants_run of $declared)"
else
    bad "only $mutants_run of $declared declared mutants ran — the rest proved nothing"
fi

# --- the derived matrix: which rows NO mutant can redden ----------------------
# UNPINNED_ROWS is the only hand-written claim about the matrix left in this
# file, and the gate checks it. Each entry needs a reason, because a row nothing
# can redden proves nothing:
#
#   102  the undeclared control. Every mutant here either widens what counts as
#        a declaration or narrows it, and #102 carries no `site:`-shaped label
#        at all, so nothing can make it declare. Its job is section 3's key set
#        and the body-contract check, both of which are assertions rather than
#        mutation targets.
#   108  a label named `website`. M2's substring widening does not reach it —
#        there is no colon — so it is the half of the prefix rule that only a
#        rule change, not a loosening, could break. Row 107 carries the mutant.
#   111  the prose-only body. Nothing in this file can make a body line declare
#        again: that capability was deleted with the parser, which is the point
#        of the row. It fails only if `site` starts being read from the body.
UNPINNED_ROWS="102 108 111"
derived_unpinned=""
flipped_set=" $(sort -un "$FLIPPED" | tr '\n' ' ') "
while read -r n _; do
    case "$flipped_set" in
        *" $n "*) ;;
        *) derived_unpinned="$derived_unpinned $n" ;;
    esac
done <"$BASELINE"
derived_unpinned="${derived_unpinned# }"
if [ "$derived_unpinned" = "$UNPINNED_ROWS" ]; then
    ok "the rows no mutant reddens are exactly the declared set ($UNPINNED_ROWS)"
else
    bad "rows no mutant reddens: '$derived_unpinned', declared: '$UNPINNED_ROWS' — a row nothing can redden proves nothing, so give it a mutant or declare it with a reason"
fi

run_snapshot "$SNAP"

# --- 10. the header states the resolution -------------------------------------
# #340's acceptance requires the multi-declaration choice to be stated in the
# script header, because a deterministic answer is only useful to a reader who
# can find out what it is. Scoped to the LEADING COMMENT BLOCK: flattening the
# whole file would let a needle satisfied by a python comment further down pass
# a check named "the header documents the resolution". Within that block the
# leading `#` is stripped BEFORE the join — the same normalisation
# test-doc-reconciliation.sh applies to blockquote markers, and for the same
# reason: without it a wrapped sentence flattens to "... not an # absence" and
# every needle spanning a wrap silently fails.
echo "10. the header documents the resolution" >&2
FLAT="$WORK/snap.flat"
awk '/^#/ {print; next} /^[[:space:]]*$/ {next} {exit}' "$SNAP" |
    sed -e 's/^[[:space:]]*#[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' |
    tr '\n' ' ' | tr -s ' \t' ' ' >"$FLAT"
# TWO negative needles, because one of them cannot catch the regression this
# section exists to prevent. `def parse_body` is a CODE line, and the awk
# already drops every line that is not a comment — so a flatten that swallowed
# the whole file's `#` comments (measured on the previous gate: delete the awk's
# `{exit}`) still never contains it and the guard stays green. The second needle
# is a phrase living ONLY in the python comment region, which is exactly the
# text a runaway flatten would pull in.
flatten_bounded=1
grep -qF -- 'def parse_body' "$FLAT" && flatten_bounded=0
grep -qF -- 'first matching line wins; entries split on commas' "$FLAT" && flatten_bounded=0
if [ -s "$FLAT" ] && [ "$flatten_bounded" = "1" ]; then
    ok "the flattened text is the leading comment block only, code and python comments excluded"
else
    bad "the header flatten is empty or reached past the comment block — every needle below would be measuring the wrong text"
fi
expect_flat() { # <label> <needle>
    if grep -qF -- "$2" "$FLAT"; then ok "$1"; else bad "$1 — missing from $SNAP's header: $2"; fi
}
expect_flat "the header says the site comes from labels, not the body" \
    'read from LABELS, not from the body'
expect_flat "  and that no label means any site" \
    'no label means "any site"'
expect_flat "  and why a label rather than a body line" \
    'A body line can be QUOTED'
expect_flat "  and that the three body contracts are untouched" \
    'keep the raw-line parse they have always had'
expect_flat "  that the match is a prefix, never a substring" \
    'It is a PREFIX, never a substring'
expect_flat "  that the value folds" \
    'stripped and folded to lowercase'
expect_flat "  that an empty value declares nothing" \
    'label with an EMPTY value declares nothing'
expect_flat "  that sites is the fact and site the convenience" \
    'is the FACT'
expect_flat "  and that a conflict is not an absence" \
    'IS A CONFLICT, NOT AN ABSENCE'
expect_flat "  with the reason it must not read as unconstrained" \
    'cannot resolve to "any site"'
expect_flat "  and that no character grammar is applied to the value" \
    'No character grammar is applied'

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "queue-snapshot site tests: all green ($asserts assertions, $mutants_run mutants)" >&2
    exit 0
fi
echo "queue-snapshot site tests: FAILURES above ($asserts assertions)" >&2
exit 1
