#!/usr/bin/env bash
# test-execution-site-surface.sh — pins the HUMAN-FACING half of the
# execution-site contract (issue #343, epic #322): `groom-backlog`'s rubric #9,
# the `survey-work` plate's backlog lines, and `setup-config`'s interview
# question for `execution_site`.
#
# The machine half is gated elsewhere and nothing here re-tests it:
# test-queue-snapshot-site.sh covers the parser (#340), test-site-filter.sh the
# two dispatchers that consume it (#341). This gate covers the prose that tells
# a human, and a cold sub-agent, what to DO with the value — the surface no
# parser test can reach.
#
# THE SHAPE OF THE BUG IT GUARDS. Four decisions here read like drift to a later
# "align this with its siblings" sweep, and every one is load-bearing:
#
#   1. THE DECLARATION IS A LABEL, AND GROOMING NEVER WRITES A BODY LINE. It
#      sits beside three body contracts that grooming DOES write (`touches:`,
#      `Depends on #N`, `stack:`), so "add a `site:` line while you are in
#      there" is the natural-looking edit. #340 shipped the body form first and
#      withdrew it: a raw line can be quoted, and both issues introducing the
#      contract carried a fenced example that declared a site by accident. A
#      label cannot be quoted in prose.
#   2. AN UNLABELLED ISSUE RENDERS EXACTLY AS IT DID BEFORE. The obvious
#      "improvement" is a token on every backlog line — `(any site)` — which
#      grows noise proportional to the backlog to say nothing, and buries the
#      handful of lines that carry a real one.
#   3. SEVERAL `site:` LABELS NARROW, AND ARE NEVER "ANY SITE". Every named
#      checkout may take the issue and membership is the whole test (#341), so
#      neither surface refuses a multi-member declaration, reports it as
#      dispatchable nowhere, or tidies it down to one — removing a label strips
#      the issue from a checkout the declaration named, and nothing reports
#      that. The reading to refuse is the opposite one: resolving several
#      declarations into "any site" re-creates #322's originating bug with two
#      labels instead of zero. THIS DECISION REPLACED ITS OWN INVERSE. Before
#      #341 the contract said several labels "match no checkout", both surfaces
#      said so, and this gate pinned it; section 5 now bans the retired wording
#      outright so the two rewrites cannot drift back one file at a time.
#   4. THE PLATFORM PROPOSES; THE USER NAMES. The interview offers a default and
#      never writes one — an unanswered question leaves the key ABSENT, and
#      absent means "any site". `vdi` carries a meaning no platform string does.
#
# NEITHER SURFACE RESOLVES LABELS ITSELF. Both run
# `queue-snapshot.sh --sites-of`, because neither read is a bucket — the buckets
# are label-scoped and these two list open issues and grooming candidates. A
# paraphrase forks the rules, measured: one dropped the `strip()` and answered
# `" vdi"` for a label the script calls legal.
#
# WHY THE INTERVIEW MUST NOT COPY THE PLATFORM TABLE. `config-contract.md` owns
# the `uname -s` → proposed-name mapping. A second copy is a copy that drifts,
# and this one has a known drift DIRECTION: an earlier draft of #343 wrote
# `darwin` / `win32` — a language runtime's platform constants, which no
# `uname -s` ever emits. So section 4 asserts the table's tokens ABSENT from the
# three consumer files, CASE-INSENSITIVELY and including `win32`: a
# case-sensitive ban catches a faithful copy and admits the lowercase
# runtime-constant form, which is the one this repo has actually written.
# The same pattern is first pointed at the table's home, so a matcher that
# matches nothing fails loudly instead of reporting a clean tree.
#
# WHY THE INTERVIEW IS CONFINED TO THE THREE ONE-TIME MODES. A refresh runs
# again and again, so a proposal made there is re-offered forever; create,
# migrate and adopt run once per repo, so declining once is a decline that
# sticks. That is the ONLY mechanism recording a "declined" — the key has no
# `none` form (config-contract.md excludes it from the confirmed-absent set) —
# which is why section 6 bans the three pre-#343 sentences saying the interview
# does not exist yet, each proved non-vacuous against the exact sentence it
# retired, and why the migrate row pins the ASK rather than the mere mention of
# §3d: a migrate path that stops asking leaves every migrated repo with no offer
# ever, while a gate reading only the section name goes on reporting it as
# asking.
#
# Must-exist assertions run on a WHITESPACE-FLATTENED copy: this repo hard-wraps
# prose, so a line-scoped grep turns a wrap into a false miss. Same
# normalisation as test-doc-reconciliation.sh.
#
# THE MUTANTS RUN HERE, AND THEIR REACH IS DERIVED. The first edition of this
# gate carried the roster in a scratch file and this header claimed "41
# mutations, every one reddens the row naming it" — a claim nothing re-computed,
# which is exactly the shape test-queue-snapshot-site.sh paid three review
# rounds for. It was also false as a standing property the moment a row was
# re-anchored. So the gate now RUNS ITSELF against each mutated copy of the
# subject files (`EXEC_SITE_SRC` moves every subject path, `EXEC_SITE_CHILD`
# suppresses the recursion), diffs the failing-row set against a baseline that
# must be clean, and checks two things against that derived set: the row a
# mutant names is a MEMBER of it, and the rows NO mutant reddens are exactly the
# declared `UNPINNED_ROWS`, which is empty. A row nothing can redden proves
# nothing, and this makes that state impossible to add quietly. Copies only;
# nothing under the tracked tree is written at any point.
#
# FOUR ROWS WENT VACUOUS BEFORE THE HARNESS EXISTED, and the pattern is worth
# carrying to any row added here.
#   * THREE MATCHED PROSE THEY DO NOT GOVERN. 'out of the top 5' is what the
#     blind-spots rule already says about a dark surface; 'skipped on a refresh'
#     is §2c's phrase, and §2c says the OPPOSITE; 'only issues this checkout can
#     take' appears twice in the plate, so deleting the rule left the sample
#     block's comment matching. In a repo whose surfaces all discuss ranking,
#     refreshes and checkouts, a plausible-sounding phrase is very often already
#     present somewhere else, and a row that matches it is decoration.
#   * ONE WAS A BAN NARROWER THAN THE CLAIM IT RETIRED. Section 5 banned
#     `matches no checkout`; a mutant wrote "several labels MATCH no checkout"
#     and walked through. The first fix, `matches?`, was ALSO wrong and still
#     passed, because `?` binds to the preceding character: that reads "matche"
#     plus an optional "s", never the bare verb. The third still admitted
#     `matched by no checkout`, `matching no checkout` and `no checkout
#     matches`. A ban is only as wide as the INFLECTIONS of the claim it
#     retires, an English rewrite reaches for all of them, and nothing but a
#     mutant writing another spelling finds this — so every inflection carries
#     its own proof string.
#
# Source-level: seven tracked files, no `gh`, no network.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-execution-site-surface.sh
set -uo pipefail
export LC_ALL=C

# Resolved BEFORE the `cd`: `$0` is caller-relative and the mutation section
# re-invokes this file by absolute path.
SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-execution-site-surface: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1
command -v python3 >/dev/null 2>&1 || {
    echo "test-execution-site-surface: python3 is required" >&2; exit 1; }

# Only the mutation section sets these, and it sets SRC to a directory holding
# copies of the subjects below.
SRC="${EXEC_SITE_SRC:-$REPO_ROOT}"
CHILD="${EXEC_SITE_CHILD:-0}"

REL_GROOM="skills/groom-backlog/SKILL.md"
REL_SURVEY="skills/survey-work/SKILL.md"
REL_INTERVIEW="skills/setup-config/references/interview.md"
REL_SETUP="skills/setup-config/SKILL.md"
REL_UPDATE="skills/setup-config/references/update-mode.md"
REL_MIGRATE="skills/setup-config/references/migrate-mode.md"
REL_CONTRACT="skills/setup-config/references/config-contract.md"
SUBJECTS="$REL_GROOM $REL_SURVEY $REL_INTERVIEW $REL_SETUP $REL_UPDATE $REL_MIGRATE $REL_CONTRACT"

# Every row this gate can emit. The parent checks the set it actually emitted
# against this, so a row added without its id — or deleted with it left here —
# fails rather than quietly shrinking the matrix.
ROW_IDS="R01 R02 R03 R04 R05 R06 R07 R08 R09
R10 R11 R12 R13 R14 R15 R16
R17 R18 R19 R20 R21 R22 R23
R24 R25 R26 R27
R28 R29
R30 R31 R32 R33 R34 R35
R36 R37 R38 R39 R40"

# Rows no mutant is expected to redden. Empty on purpose: a row nothing can
# redden is a row that proves nothing.
UNPINNED_ROWS=""

fails=0
seen_rows=""
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }
row_ok()  { seen_rows="$seen_rows $1"; ok "$1 $2"; }
row_bad() { seen_rows="$seen_rows $1"; bad "$1 $2"; }

[ "$CHILD" = "1" ] || echo "Execution-site human surface (issue #343, epic #322)"

for f in $SUBJECTS; do
    [ -r "$SRC/$f" ] || bad "missing file: $SRC/$f"
done
[ "$fails" -eq 0 ] || { echo "test-execution-site-surface: FAILED" >&2; exit 1; }

# Flatten to one line for phrase matching: strip leading blockquote markers and
# list indentation, then join. Without it a hard wrap between two words of an
# asserted phrase is a false miss.
flat() {
    sed -e 's/^[[:space:]]*>[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' "$SRC/$1" |
        tr '\n' ' ' | tr -s ' '
}
groom_flat="$(flat "$REL_GROOM")"
survey_flat="$(flat "$REL_SURVEY")"
interview_flat="$(flat "$REL_INTERVIEW")"
setup_flat="$(flat "$REL_SETUP")"
update_flat="$(flat "$REL_UPDATE")"
migrate_flat="$(flat "$REL_MIGRATE")"
contract_flat="$(flat "$REL_CONTRACT")"

# want <row> <label> <haystack> <pattern>...  — every pattern must be present.
want() {
    local row="$1" label="$2" hay="$3"; shift 3
    local pat
    for pat in "$@"; do
        if ! printf '%s' "$hay" | grep -qiE -- "$pat"; then
            row_bad "$row" "$label (missing: $pat)"
            return
        fi
    done
    row_ok "$row" "$label"
}

# reject <row> <label> <haystack> <pattern> <proof>...
#
# A must-not-exist check passes trivially when its pattern is malformed or has
# been reworded past the thing it bans, so the pattern is first run against
# every <proof> — the literal spellings it exists to keep out. A pattern that
# cannot match one of its own subjects FAILS here rather than reporting a clean
# file. One proof per inflection: that is what the third iteration of section
# 5's ban cost.
reject() {
    local row="$1" label="$2" hay="$3" pat="$4"; shift 4
    local proof
    for proof in "$@"; do
        if ! printf '%s' "$proof" | grep -qiE -- "$pat"; then
            row_bad "$row" "$label — the ban does not match its own proof ($proof); it is vacuous"
            return
        fi
    done
    if printf '%s' "$hay" | grep -qiE -- "$pat"; then
        row_bad "$row" "$label"
    else
        row_ok "$row" "$label"
    fi
}

# --- 1. groom-backlog: rubric #9 is a LABEL rule ------------------------------

# The row's own cells, not merely the words in them: 'label' alone is satisfied
# by "**body line, never a label**", which is the one-file-at-a-time inversion
# decision 1 exists to stop.
rubric_row="$(grep -E '^\| 9 \|' "$SRC/$REL_GROOM" | tr '\n' ' ')"
if [ -n "$rubric_row" ]; then
    want R01 "groom-backlog rubric #9 requires a site:<name> label" "$rubric_row" \
        'execution site' 'carries a .site:<name>. label' 'Apply the label'
else
    row_bad R01 "groom-backlog has no rubric row 9 — the site test is gone from the table"
fi

want R02 "groom-backlog applies the label and never writes a body line" "$groom_flat" \
    'never writes a .site:. line into the body\.\*\*'

want R03 "groom-backlog keeps the reason a label was chosen over a body line" "$groom_flat" \
    'label cannot be quoted in prose'

want R04 "groom-backlog runs the resolver instead of paraphrasing it" "$groom_flat" \
    'queue-snapshot.sh --sites-of' 'never by paraphrasing its rules'

want R05 "groom-backlog never invents the site name" "$groom_flat" \
    'never invent the name' "the site name is the user's"

want R06 "groom-backlog treats several site: labels as narrowing, never a defect" "$groom_flat" \
    'labels NARROW; they never widen' 'never remove one to .resolve a conflict'

want R07 "groom-backlog carries the operational-checklist verdict, never Ready" "$groom_flat" \
    'parked: operational' 'never Ready'

# The verdict has to reach the REPORT, not only the rubric prose: the final
# table is the only part of a grooming run a reader is guaranteed to see.
want R08 "the operational verdict is in §6's final-table verdict list" "$groom_flat" \
    'verdict \(\*\*Ready\*\*[^)]*parked: operational'

want R09 "groom-backlog guards the body-line edit in its Guardrails" "$groom_flat" \
    'never write a .site:. line into an issue body'

# --- 2. survey-work: the plate separates here-vs-elsewhere --------------------

want R10 "survey-work resolves the site from the labels it already pulled" "$survey_flat" \
    'execution site from the labels'

want R11 "survey-work runs the resolver instead of re-deriving it" "$survey_flat" \
    'queue-snapshot.sh --sites-of' 'rather than re-deriving its rules'

# Decision 2: the no-label case is the overwhelming majority, and a token on
# every line is the "improvement" that makes the plate useless.
want R12 "an unlabelled issue renders exactly as it did before" "$survey_flat" \
    'renders exactly as it did before this rule existed'

# Anchored on the RULE's own sentence: a bare 'not this checkout' is satisfied
# by the sample plate line, so renaming the marker in the rule alone would leave
# rule and sample disagreeing under a green gate.
want R13 "an off-site issue is marked, not hidden" "$survey_flat" \
    'renders the same tokens plus .\(not this checkout\)' \
    'never demote it for being elsewhere'

# B1: both original patterns lived in the bullet's LAST sentence, so inverting
# the narrowing claim itself — "They **widen**: a second label lifts the
# restriction" — left all 35 rows green. The identical inversion of the twin
# sentence in groom-backlog reddened R06, which names the claim directly: the
# decision was shut in one of its two homes and open in the other, which is the
# "one drifting back alone" failure section 5 exists to prevent.
want R14 "several site: labels render as narrowing, with no third rendering" "$survey_flat" \
    'They \*\*narrow\*\*' 'the reading to refuse is .any site.' \
    'no third rendering for a multi-member declaration' 'never reported as undispatchable'

# The rule head, not only its justification: keeping the argument while
# inverting the rule is the edit a justification-only anchor admits.
want R15 "the To ship: line names only what this checkout can take" "$survey_flat" \
    'only issues this checkout can take reach the closing' \
    'hands the user a .take. that the dispatcher will refuse'

want R16 "survey-work stays read-only about the label" "$survey_flat" \
    'never act on it' 'stays read-only whatever the .write_policy.: a missing label is not filed'

# --- 3. setup-config: the interview that fills the key ------------------------

if grep -qE '^### 3d\.' "$SRC/$REL_INTERVIEW"; then
    row_ok R17 "interview.md carries a §3d execution-site question"
else
    row_bad R17 "interview.md has no §3d — nothing asks for execution_site"
fi

want R18 "§3d is confined to the three one-time modes" "$interview_flat" \
    'asked once, in create, migrate and adopt modes' \
    'skipped on a refresh unless the user raises it'

want R19 "§3d points at the contract's table instead of carrying one" "$interview_flat" \
    'uname -s' 'config-contract.md'

want R20 "§3d asks with no default where the table proposes nothing" "$interview_flat" \
    'no proposal at all' 'no default'

want R21 "§3d proposes and never assumes" "$interview_flat" \
    'never assumed' 'never write a value the user did not say' \
    'never offer a .none. — the confirmed-absent form'

# Decision 4's own cell. A bare 'omitted' occurs four times in this file, twice
# in §2c, so it survives rewriting the cell to write a value.
want R22 "a declined or unanswered §3d omits the key" "$interview_flat" \
    'the key is \*\*omitted\*\*'

want R23 "the defaults summary refuses to default execution_site" "$interview_flat" \
    'never defaulted either'

# --- 4. the platform table has exactly one home -------------------------------
#
# `uname -s` tokens plus the runtime constants an earlier draft reached for, not
# the proposed names: `mac` and `windows` are common words, while these strings
# appear nowhere else by accident. Case-INSENSITIVE, because the drift this ban
# exists to stop is spelled in lower case. update-mode.md is excluded
# deliberately — it explains what `uname -s` answers and what it does NOT
# answer, which is the opposite of proposing from it.

TABLE_TOKENS='Darwin|MINGW64|MSYS_NT|CYGWIN_NT|win32'
if printf '%s' "$contract_flat" | grep -qiE -- "$TABLE_TOKENS"; then
    row_ok R24 "the uname -s table is where the contract says it is"
else
    row_bad R24 "config-contract.md no longer carries the uname -s table — the ban below would be vacuous"
fi
table_row=24
for pair in "interview.md:$interview_flat" "groom-backlog:$groom_flat" "survey-work:$survey_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    table_row=$((table_row + 1))
    if printf '%s' "$body" | grep -qiE -- "$TABLE_TOKENS"; then
        row_bad "R$table_row" "$name restates the uname -s table — it has exactly one home, and a copy drifts"
    else
        row_ok "R$table_row" "$name does not restate the uname -s table"
    fi
done

# --- 5. the retired "matches no checkout" semantics stay retired --------------
#
# Until #341 the contract said several `site:` labels match no checkout, and
# both surfaces said so — grooming refused Ready, the plate called the issue
# undispatchable. #341 settled the opposite: membership NARROWS, and every named
# checkout may take the issue. Two files were rewritten, so the failure mode is
# one drifting back alone; the proofs are the sentence each file actually
# carried, plus every inflection an English rewrite reaches for.

# FOURTH WIDENING. Every proof below used to put "match" ADJACENT to "no
# checkout", so the self-proof above could not expose the gap: a MODAL is the
# most natural way a later editor restates a retired rule, and "no checkout
# WILL match" / "no checkout CAN match" both shipped green. So did the
# quantifier forms — "matches none of the checkouts", "matches neither
# checkout" — and the `site` spelling of the same claim. The window is bounded
# to one sentence (`[^.]`) so the alternation cannot reach across a full stop
# into unrelated prose.
RETIRED_SEMANTICS='(match(es|ed|ing)?( by)? no (checkout|site)|no (checkout|site)[^.]{0,40}match|match(es)? (none of the checkout|neither checkout))'

reject R28 "groom-backlog does not resurrect the match-no-checkout reading" \
    "$groom_flat" \
    "$RETIRED_SEMANTICS" \
    'Several are a **conflict that matches no checkout**, not "any site"' \
    'several labels match no checkout' \
    'no checkout will match a two-site declaration' \
    'no checkout can match them' \
    'it matches none of the checkouts' \
    'it matches neither checkout' \
    'no site matches this declaration' \
    'a two-site issue is matched by no checkout' \
    'matching no checkout, it is parked' \
    'no checkout matches a two-site declaration'

reject R29 "survey-work does not resurrect the match-no-checkout reading" \
    "$survey_flat" \
    "$RETIRED_SEMANTICS" \
    'renders as `site: CONFLICT (<a>, <b>)` — matches no checkout' \
    'several labels match no checkout' \
    'no checkout will match a two-site declaration' \
    'no checkout can match them' \
    'it matches none of the checkouts' \
    'it matches neither checkout' \
    'no site matches this declaration' \
    'a two-site issue is matched by no checkout' \
    'matching no checkout, it is undispatchable' \
    'no checkout matches a two-site declaration'

# --- 6. the pre-#343 "no interview exists yet" sentences are gone -------------
#
# Each proof is the retired sentence itself. They were true until this change
# landed, and each instructs its mode NOT to propose — left in place they read
# as a live rule contradicting §3d.

reject R30 "setup-config/SKILL.md no longer claims nothing proposes the key" \
    "$setup_flat" \
    'nothing proposes an .execution_site' \
    '**Nothing proposes an `execution_site:` today** — the platform-derived name becomes a proposal'

reject R31 "update-mode.md no longer claims the §3d section is unwritten" \
    "$update_flat" \
    'until that section exists' \
    'to add; until that section exists there is no question shape and no way to record "declined"'

reject R32 "migrate-mode.md no longer claims a decline cannot be recorded" \
    "$migrate_flat" \
    'until it exists there is no way to record' \
    "and until it exists there is no way to record that the user declined."

# ...and each mode now states its own half, so the rule is not merely deleted.

want R33 "setup-config's guardrail names §3d and its three modes" "$setup_flat" \
    'interview §3d' 'create, migrate and adopt modes only'

# The adopt-mode step added by this change QUOTES this sentence, so the bare
# phrase now occurs twice in the file and inverting the rule left the row green
# — measured, not guessed. Anchored through the clause only the rule carries.
want R34 "update-mode refuses to ask on a refresh" "$update_flat" \
    'do not ask it on a refresh\*\* unless the user'

# The ASK, not the mention. Naming §3d while telling the mode NOT to run it
# leaves every migrated repo with no offer ever — and that offer is the only
# mechanism recording a decline.
want R35 "migrate-mode asks §3d as its one offer" "$migrate_flat" \
    'put \*\*interview §3d\*\* to the user here' 'the one offer this repo gets'

# --- 6b. decisions that had no row at all -------------------------------------
#
# Each of these was verified as leaving every other row green when inverted. The
# fail-open is the safety property of the whole feature on every repo configured
# before #340, and its failure is INVISIBLE: a plate that silently drops every
# site-labelled issue looks like an empty backlog.

want R36 "a member declaration renders as bare tokens, not a warning" "$survey_flat" \
    'renders as bare .{0,6}site:<name>.{0,6} tokens' 'context, not a warning'

want R37 "an unnamed checkout fails OPEN on the plate" "$survey_flat" \
    'every declared site renders as a bare token and nothing is marked as elsewhere' \
    'the same fail-open the dispatchers take'

want R38 "grooming labels only what genuinely needs it" "$groom_flat" \
    'No label is the right answer for almost every issue' 'strictly a loss' \
    'Never label defensively'

# The folded spelling is what #341 exists for, and these two files are NOT
# subjects of test-site-filter.sh's veto — correct today, pinned by nothing.
for pair in "groom-backlog:$groom_flat" "survey-work:$survey_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    case "$name" in
        groom-backlog) folded_row=R39 ;;
        *)             folded_row=R40 ;;
    esac
    want "$folded_row" "$name writes the folded membership test" "$body" \
        'not sites or execution_site\.lower\(\) in sites'
done

# --- row hygiene --------------------------------------------------------------

declared_sorted="$(printf '%s\n' $ROW_IDS | sort -u)"
seen_sorted="$(printf '%s\n' $seen_rows | grep -E '^R[0-9]+$' | sort -u)"
if [ "$declared_sorted" = "$seen_sorted" ]; then
    [ "$CHILD" = "1" ] || ok "ROWS every declared row ran, and only declared rows ran"
else
    bad "ROWS the rows that ran differ from ROW_IDS — a row was added or deleted without its declaration"
    diff <(echo "$declared_sorted") <(echo "$seen_sorted") | sed 's/^/          | /' >&2
fi

if [ "$CHILD" = "1" ]; then
    [ "$fails" -eq 0 ] && exit 0
    exit 1
fi

# --- 7. mutation proofs, and the matrix derived from them ---------------------

echo "7. mutation proofs"

# FAIL CLOSED ON A BAD SCRATCH DIR. `mktemp -d` failing leaves `$WORK` empty
# under `set -uo pipefail` (no `-e`), which makes `$MDIR` the absolute `/m` —
# and `reset_mutant` then runs `rm -rf "/m"` plus `mkdir -p`/`cp` FORTY-SIX
# times while the trap's `rm -rf ""` cleans nothing. This gate both writes and
# deletes under `$WORK` in a loop, so it needs the guard more than the three
# siblings that carry it verbatim (test-queue-snapshot-site.sh,
# test-site-filter.sh, test-file-or-link-issue.sh).
WORK="$(mktemp -d)"
if [ -z "$WORK" ] || [ ! -d "$WORK" ] || [ "$WORK" = "/" ]; then
    echo "mktemp -d did not produce a usable scratch directory (got '${WORK:-}'); refusing to run" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT
MDIR="$WORK/m"
FLIPPED="$WORK/flipped.txt"
: >"$FLIPPED"
mutants_run=0

run_child() { EXEC_SITE_SRC="$MDIR" EXEC_SITE_CHILD=1 bash "$SELF_ABS" >"$1" 2>&1; }
fails_in() { grep -oE '^  FAIL  R[0-9]+' "$1" | awk '{ print $2 }' | sort -u; }
rows_in()  { grep -cE '^  (ok|FAIL) +R[0-9]+' "$1"; }

DECLARED_ROWS="$(grep -c . <<<"$declared_sorted")"

# THE HARNESS PROVES ITSELF FIRST. A child that measured the wrong tree, or did
# not run at all, reports an empty flip set for every mutant below — which fails
# loudly rather than passing, but only once this run has shown the child works
# against the tracked tree.
BASE="$WORK/baseline.out"
run_child_base() { EXEC_SITE_SRC="$REPO_ROOT" EXEC_SITE_CHILD=1 bash "$SELF_ABS" >"$1" 2>&1; }
run_child_base "$BASE"
base_rc=$?
if [ "$base_rc" = "0" ] && [ -z "$(fails_in "$BASE")" ] && [ "$(rows_in "$BASE")" = "$DECLARED_ROWS" ]; then
    ok "the self-run reproduces a clean baseline over all $DECLARED_ROWS rows"
else
    bad "the self-run baseline is not clean (exit $base_rc, $(rows_in "$BASE") rows) — every flip set below would be measured against the wrong thing"
    sed 's/^/          | /' "$BASE" >&2
fi

EDIT_OK=1
reset_mutant() {
    rm -rf "$MDIR"
    EDIT_OK=1
    local rel
    for rel in $SUBJECTS; do
        mkdir -p "$MDIR/$(dirname "$rel")"
        cp "$REPO_ROOT/$rel" "$MDIR/$rel"
    done
}

edit() { # <relpath> <from> <to> — exact, and it must match exactly once
    if ! python3 - "$MDIR/$1" "$2" "$3" <<'PY'
import io, sys
path, frm, to = sys.argv[1:4]
s = io.open(path, encoding="utf-8").read()
if s.count(frm) != 1:
    sys.stderr.write("occurrences=%d\n" % s.count(frm))
    sys.exit(1)
io.open(path, "w", encoding="utf-8").write(s.replace(frm, to))
PY
    then
        EDIT_OK=0
    fi
}

edit_all() { # <relpath> <from> <to> — every occurrence, and there must be at least one
    if ! python3 - "$MDIR/$1" "$2" "$3" <<'PY'
import io, sys
path, frm, to = sys.argv[1:4]
s = io.open(path, encoding="utf-8").read()
if frm not in s:
    sys.stderr.write("occurrences=0\n")
    sys.exit(1)
io.open(path, "w", encoding="utf-8").write(s.replace(frm, to))
PY
    then
        EDIT_OK=0
    fi
}

mutate() { # <label> <named row>
    local label="$1" named="$2" out="$WORK/mutant.out" flips
    if [ "$EDIT_OK" != "1" ]; then
        bad "$label — a mutation target did not match exactly once (stale mutant)"
        return
    fi
    run_child "$out"
    if [ "$(rows_in "$out")" != "$DECLARED_ROWS" ]; then
        bad "$label — the child emitted $(rows_in "$out") of $DECLARED_ROWS rows, so its verdict proves nothing"
        return
    fi
    mutants_run=$((mutants_run + 1))
    flips="$(fails_in "$out" | tr '\n' ' ')"
    printf '%s\n' $flips >>"$FLIPPED"
    case " $flips " in
        *" $named "*) ok "$label reddens $named (flips: ${flips% })" ;;
        *) bad "$label does NOT redden $named — it flips '${flips% }'. Either the roster names the wrong row or the decision has stopped being load-bearing" ;;
    esac
}

# 1. groom-backlog
reset_mutant
edit "$REL_GROOM" '| 9 | Execution site' '| x | Execution site'
mutate "M01 the rubric row is deleted" R01

# B3's proof: 'label' alone was satisfied by the row's own negation, and the
# sibling prose row stayed green because the prose below was untouched.
reset_mutant
edit "$REL_GROOM" 'carries a `site:<name>` label' 'carries a `site:<name>` **body line, never a label**'
edit "$REL_GROOM" 'Apply the label (below)' 'Add the body line (below)'
mutate "M02 rubric row 9 is inverted to a body line, prose left alone" R01

reset_mutant
edit "$REL_GROOM" 'it never writes a `site:` line into the body' 'it also writes a `site:` line into the body'
mutate "M03 the body-line rule is inverted" R02

reset_mutant
edit "$REL_GROOM" 'A label cannot be quoted in prose' 'A label is a different thing'
mutate "M04 the quoting reason is dropped" R03

reset_mutant
edit "$REL_GROOM" 'never by paraphrasing its rules' 'or by paraphrasing its rules'
mutate "M05 grooming stops running the resolver" R04

reset_mutant
edit_all "$REL_GROOM" 'queue-snapshot.sh --sites-of' 'queue-snapshot.sh --resolve'
mutate "M06 grooming drops the emitter call" R04

reset_mutant
edit "$REL_GROOM" '**Never invent the name.**' '**Pick a sensible name.**'
mutate "M07 the never-invent rule is dropped" R05

reset_mutant
edit "$REL_GROOM" 'labels NARROW; they never widen' 'labels are a special case'
mutate "M08 the narrowing rule is dropped" R06

reset_mutant
edit "$REL_GROOM" '**Never remove one to "resolve a conflict"**' 'Remove one to resolve the conflict'
mutate "M09 grooming starts pruning multi-site declarations" R06

reset_mutant
edit "$REL_GROOM" 'That work is **never Ready**' 'That work is Ready like any other'
mutate "M10 operational work is allowed into Ready" R07

reset_mutant
edit "$REL_GROOM" 'awaiting-user / **parked: operational (site `<x>`)** / parked: reason' \
    'awaiting-user / parked: reason'
mutate "M11 the operational verdict is dropped from the report" R08

reset_mutant
edit "$REL_GROOM" 'Never write a `site:` line into an issue body' 'Avoid body lines'
mutate "M12 the body-line guardrail is dropped" R09

# 2. survey-work
reset_mutant
edit "$REL_SURVEY" "resolve each issue's execution site from the labels" \
    "read each issue's site marker off the body"
mutate "M13 the plate stops reading the label" R10

reset_mutant
edit "$REL_SURVEY" 'rather than re-deriving its rules' 'and reimplement its rules here'
mutate "M14 the plate re-derives the resolution" R11

reset_mutant
edit_all "$REL_SURVEY" 'queue-snapshot.sh --sites-of' 'queue-snapshot.sh --resolve'
mutate "M15 the plate drops the emitter call" R11

reset_mutant
edit "$REL_SURVEY" 'renders exactly as it did before this rule existed' \
    'renders with an (any site) token'
mutate "M16 the unlabelled rendering changes" R12

# The smaller-anchor proof: renaming the marker in the RULE while the sample
# plate line keeps saying "(not this checkout)".
reset_mutant
edit "$REL_SURVEY" 'renders the same tokens plus
  `(not this checkout)`' 'renders the same tokens plus
  `(elsewhere)`'
mutate "M17 the off-site marker is renamed in the rule alone" R13

reset_mutant
edit "$REL_SURVEY" 'Never demote it for being elsewhere' 'Demote it for being elsewhere'
mutate "M18 off-site items are demoted" R13

reset_mutant
edit "$REL_SURVEY" 'There is no
  third rendering for a multi-member declaration' 'There is a separate CONFLICT
  rendering for a multi-member declaration'
mutate "M19 the plate grows a third rendering for several labels" R14

reset_mutant
edit "$REL_SURVEY" 'it is never reported as undispatchable' 'it is reported as undispatchable'
mutate "M20 a multi-site issue is called undispatchable" R14

# The To-ship proof: invert the rule head, keep the justification.
reset_mutant
edit "$REL_SURVEY" '**Only issues this checkout can take reach the closing `To ship:` line**' \
    '**Every ranked issue reaches the closing `To ship:` line**'
mutate "M21 the To ship: rule head is inverted, its argument kept" R15

reset_mutant
edit "$REL_SURVEY" '**Never act on it.**' '**Fix it while you are here.**'
mutate "M22 the plate starts writing labels" R16

# 3. interview
reset_mutant
edit "$REL_INTERVIEW" '### 3d. Execution site' '### 3z. Execution site'
mutate "M23 the §3d heading is gone" R17

reset_mutant
edit "$REL_INTERVIEW" 'Skipped on a refresh unless the user raises it.' 'Asked on every refresh too.'
mutate "M24 §3d moves into the refresh path" R18

reset_mutant
edit "$REL_INTERVIEW" "that contract's \`uname -s\` table" "that contract's platform table"
mutate "M25 §3d stops citing the table" R19

reset_mutant
edit "$REL_INTERVIEW" 'Some platforms have no proposal at all' 'Every platform has a proposal'
mutate "M26 §3d invents a default where the table gives none" R20

reset_mutant
edit "$REL_INTERVIEW" '**Never write a value' '**Always write a value'
mutate "M27 §3d starts assuming" R21

# B2's proof: a coherent decline-writes-`none` sweep. 'omitted' alone occurs
# four times in this file, twice in §2c, so it survives this edit.
reset_mutant
edit "$REL_INTERVIEW" '| Declined, unanswered, or "just use defaults" | the key is **omitted** |' \
    '| Declined, unanswered, or "just use defaults" | `execution_site: none` |'
mutate "M28 a decline writes a value instead of omitting the key" R22

reset_mutant
edit "$REL_INTERVIEW" 'never defaulted either' 'defaulted from the platform'
mutate "M29 the defaults summary defaults the key" R23

# 4. the table's one home
reset_mutant
edit "$REL_CONTRACT" '| `Darwin` | `mac` |
| `MINGW64_NT-…` / `MSYS_NT-…` / `CYGWIN_NT-…` | `windows` |' '| `macOS` | `mac` |
| `MSYS shell` | `windows` |'
mutate "M30 the table's home loses its tokens" R24

# B1's proof: the lowercase runtime-constant form, which is the drift this repo
# has actually written. A case-sensitive ban admits it.
reset_mutant
edit "$REL_INTERVIEW" '### 3d. Execution site' \
    '### 3d. Execution site (darwin -> mac, win32 -> windows, linux -> none)'
mutate "M31 the interview copies the table in runtime-constant form" R25

reset_mutant
edit "$REL_GROOM" '### Rubric #9 — the execution site is a LABEL' \
    '### Rubric #9 — the execution site is a LABEL (Darwin -> mac)'
mutate "M32 groom-backlog copies the table" R26

reset_mutant
edit "$REL_SURVEY" '### Execution site on backlog lines' \
    '### Execution site on backlog lines (darwin -> mac)'
mutate "M33 survey-work copies the table" R27

# 5. the retired semantics, one mutant per inflection the ban must cover
reset_mutant
edit "$REL_GROOM" '### The `parked: operational (site <x>)` verdict' \
    'Several labels match no checkout.

### The `parked: operational (site <x>)` verdict'
mutate "M34 groom-backlog resurrects the bare-verb spelling" R28

reset_mutant
edit "$REL_SURVEY" '### Blind spots' 'A two-site issue is matched by no checkout, so it is undispatchable.

### Blind spots'
mutate "M35 survey-work resurrects the passive spelling" R29

reset_mutant
edit "$REL_SURVEY" '### Blind spots' 'No checkout matches a two-site declaration; render `site: CONFLICT`.

### Blind spots'
mutate "M36 survey-work resurrects the inverted spelling" R29

# 6. the retired sentences and each mode's own half
reset_mutant
edit "$REL_SETUP" '- Prose in `##` sections is user-owned' \
    '  **Nothing proposes an `execution_site:` today** — the platform-derived name becomes a proposal.
- Prose in `##` sections is user-owned'
mutate "M37 the retired sentence returns to setup-config" R30

reset_mutant
edit "$REL_UPDATE" '## Adopt mode (no marker' \
    'The interview that proposes a name is #343'"'"'s to add; until that section exists there is no question shape and no way to record "declined".

## Adopt mode (no marker'
mutate "M38 the retired sentence returns to update-mode" R31

reset_mutant
edit "$REL_MIGRATE" '## `execution_site` on a migration' \
    'Do not propose a platform-derived name, and until it exists there is no way to record that the user declined.

## `execution_site` on a migration'
mutate "M39 the retired sentence returns to migrate-mode" R32

reset_mutant
edit "$REL_SETUP" 'interview §3d, in create, migrate and
  adopt modes only' 'the interview, in some modes'
mutate "M40 setup-config's guardrail stops naming §3d" R33

reset_mutant
edit "$REL_UPDATE" '**Do not ask it on a refresh**' '**Ask it on a refresh**'
mutate "M41 update-mode drops its refusal" R34

# B4's proof: naming §3d while telling the mode not to run it.
reset_mutant
edit "$REL_MIGRATE" 'So put **interview §3d** to the user here, as part of
this mode: it is the one offer this repo gets' \
    'So do **not** put interview §3d to the user here; leave the key absent'
mutate "M42 migrate-mode stops asking while still naming §3d" R35

# B1's two proofs: the narrowing claim inverted, trailing sentence untouched.
reset_mutant
edit "$REL_SURVEY" 'They **narrow**: each' 'They **widen**: a second label lifts the restriction, so each'
mutate "M43 the plate's narrowing claim is inverted, trailing sentence untouched" R14

reset_mutant
edit "$REL_SURVEY" 'the reading to refuse is "any site"' 'the reading to prefer is "any site"'
mutate "M44 the plate stops refusing the any-site reading" R14

# 6b's rows
reset_mutant
edit "$REL_SURVEY" 'It is context, not a warning: the work is takeable here.' \
    'Render it as a loud **(BLOCKED)** warning.'
mutate "M45 a member declaration is rendered as a warning" R36

reset_mutant
edit "$REL_SURVEY" 'every declared site
renders as a bare token and nothing is marked as elsewhere' 'every site-labelled issue
is dropped from the plate'
mutate "M46 an unnamed checkout fails CLOSED on the plate" R37

reset_mutant
edit "$REL_GROOM" '**No label is the right answer for almost every issue.**' \
    '**Label everything to be safe.**'
mutate "M47 grooming starts labelling defensively" R38

reset_mutant
edit_all "$REL_GROOM" 'not sites or execution_site.lower() in sites' \
    'not sites or execution_site in sites'
mutate "M48 groom-backlog drops the config-side fold" R39

reset_mutant
edit_all "$REL_SURVEY" 'not sites or execution_site.lower() in sites' \
    'not sites or execution_site in sites'
mutate "M49 survey-work drops the config-side fold" R40

# N4's qualification mutants. These ADD a clause around a needle that survives,
# rather than deleting or inverting one — the class the other 46 cannot reach.
reset_mutant
edit "$REL_GROOM" 'it never writes a `site:` line into the body.**' \
    'it never writes a `site:` line into the body unless the label cannot be created.**'
mutate "M50 QUALIFIED: the body-line ban grows an exception" R02

reset_mutant
edit "$REL_SURVEY" 'stays read-only whatever the `write_policy`: a missing label is
not filed' 'stays read-only whatever the `write_policy` unless it is `gated`, in which case a missing label is
filed'
mutate "M51 QUALIFIED: the plate's read-only rule grows a write path" R16

reset_mutant
edit "$REL_INTERVIEW" 'never offer a `none` — the confirmed-absent form' \
    'never offer a `none` unless the user asks for one — the confirmed-absent form'
mutate "M52 QUALIFIED: the none refusal grows an exception" R21

rm -rf "$MDIR"

# --- 8. the derived matrix ----------------------------------------------------
#
# A row no mutant reddens proves nothing. Deriving that set rather than
# asserting it is what stops a vacuous row being added quietly later.

flipped_sorted="$(grep -E '^R[0-9]+$' "$FLIPPED" | sort -u)"
unpinned="$(comm -23 <(echo "$declared_sorted") <(echo "$flipped_sorted") | tr '\n' ' ')"
declared_unpinned="$(printf '%s\n' $UNPINNED_ROWS | grep -E '^R[0-9]+$' | sort -u | tr '\n' ' ')"
if [ "${unpinned% }" = "${declared_unpinned% }" ]; then
    ok "the rows NO mutant reddens are exactly the declared set (${unpinned:-none})"
else
    bad "rows no mutant reddens: '${unpinned% }', declared: '${declared_unpinned% }' — a row nothing can redden proves nothing"
fi

if [ "$mutants_run" = "52" ]; then
    ok "every declared mutant ran (52 of 52)"
else
    bad "$mutants_run of 52 mutants ran — the matrix above is measured against a partial set"
fi

if [ "$fails" -ne 0 ]; then
    echo "test-execution-site-surface: FAILED ($fails)" >&2
    exit 1
fi
echo "Execution-site surface tests: all green ($DECLARED_ROWS rows, $mutants_run mutants)"
