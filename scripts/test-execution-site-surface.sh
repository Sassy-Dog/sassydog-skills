#!/usr/bin/env bash
# test-execution-site-surface.sh — pins the HUMAN-FACING half of the
# execution-site contract (issue #343, epic #322): `groom-backlog`'s rubric #9,
# the `survey-work` plate's backlog lines, and `setup-config`'s interview
# question for `execution_site`.
#
# The machine half — how a `site:<name>` label resolves to a `sites` list — is
# #340's and is gated by scripts/test-queue-snapshot-site.sh against the parser
# itself. Nothing here re-tests that. This gate covers the prose that tells a
# human, and a cold sub-agent, what to DO with the value, which is exactly the
# surface no parser test can reach.
#
# THE SHAPE OF THE BUG IT GUARDS. Four decisions here read like drift to a later
# "align this with its siblings" sweep, and every one of them is load-bearing:
#
#   1. THE DECLARATION IS A LABEL, AND GROOMING NEVER WRITES A BODY LINE. It
#      sits beside three body contracts (`touches:`, `Depends on #N`, `stack:`)
#      that grooming DOES write, so "add a `site:` line while you are in there"
#      is the natural-looking edit. #340 shipped the body form first and
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
#      labels instead of zero. THIS ROW REPLACED ITS OWN INVERSE. Before #341
#      the contract said several labels "match no checkout", both surfaces said
#      so, and this gate pinned it; the retired wording is now banned outright,
#      proved against the sentence it retired, so the two rewrites cannot drift
#      back one file at a time.
#   3b. NEITHER SURFACE RESOLVES LABELS ITSELF. Both run
#      `queue-snapshot.sh --sites-of`, because neither read is a bucket — the
#      buckets are label-scoped and these two list open issues and grooming
#      candidates. A paraphrase forks the rules, measured: one dropped the
#      `strip()` and answered `" vdi"` for a label the script calls legal.
#   4. THE PLATFORM PROPOSES; THE USER NAMES. The interview offers a default and
#      never writes one — an unanswered question leaves the key ABSENT, and
#      absent means "any site". `vdi` carries a meaning no platform string does.
#
# WHY THE INTERVIEW MUST NOT COPY THE PLATFORM TABLE. `references/config-contract.md`
# owns the `uname -s` → proposed-name mapping. A second copy in the interview is
# a copy that drifts, and this one has a known drift direction: an earlier draft
# of #343 wrote `darwin`/`win32` — a language runtime's platform constants,
# which no `uname -s` ever emits. So the table's own tokens are asserted ABSENT
# from the three consumer files, and the same pattern is first pointed at the
# table's home, so a matcher that matches nothing fails loudly instead of
# reporting a clean tree (the anti-vacuity trick from test-label-taxonomy.sh).
#
# WHY THE INTERVIEW IS CONFINED TO THE THREE ONE-TIME MODES. A refresh runs
# again and again, so a proposal made there is re-offered forever; create,
# migrate and adopt run once per repo, so declining once is a decline that
# sticks. That is the ONLY mechanism recording a "declined" — the key has no
# `none` form (config-contract.md excludes it from the confirmed-absent set) —
# which is why the pre-#343 sentences saying the interview does not exist yet
# are asserted GONE from `setup-config/SKILL.md`, `update-mode.md` and
# `migrate-mode.md`. Each of those three must-not-exist patterns is proved
# non-vacuous against the exact sentence it retired, held here as a literal, so
# a pattern that could never match cannot pass as a clean file.
#
# Must-exist assertions run on a WHITESPACE-FLATTENED copy: this repo hard-wraps
# prose, so a line-scoped grep turns a wrap into a false miss. Same normalisation
# as test-doc-reconciliation.sh.
#
# MUTATION-PROVED, and the proof found four defective rows before this shipped.
# 41 mutations are applied one at a time — each an edit a later sweep would
# plausibly make — and every one reddens the row naming it. Three of the first
# draft's rows stayed green under their own mutation, all for the same reason:
# the phrase they matched ALSO occurs in prose the row does not govern, so it
# could never fall.
#   * 'out of the top 5' is what the blind-spots rule already says about a dark
#     surface, seven paragraphs below the site rule.
#   * 'skipped on a refresh' is §2c's phrase about the three confirmed-absent
#     keys, and §2c says the OPPOSITE — "Not skipped on a refresh".
#   * 'only issues this checkout can take' appears twice in the plate, so
#     deleting the rule left the sample block's comment matching.
# Each now anchors on a phrase unique to the decision it pins. The lesson
# generalises to any row added here: in a repo whose surfaces all discuss
# ranking, refreshes and checkouts, a plausible-sounding phrase is very often
# already present somewhere else, and a row that matches it is decoration.
#
# The fourth was a BAN too narrow for its own subject, and it is the one worth
# copying elsewhere. Section 4b banned `matches no checkout`; a mutant wrote
# "several labels match no checkout" and walked straight through. The first fix
# — `matches? no checkout` — was ALSO wrong and still passed the mutant, because
# `?` binds to the preceding character: that reads "matche" plus an optional
# "s", never the bare verb. It is `match(es)? no checkout`, verified against
# both spellings rather than reasoned about. A ban is only as wide as the
# inflections of the claim it retires, and an English rewrite reaches for them
# all; nothing but a mutant writing the other spelling finds this.
#
# Source-level: seven tracked files, no `gh`, no network.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-execution-site-surface.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-execution-site-surface: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

GROOM="skills/groom-backlog/SKILL.md"
SURVEY="skills/survey-work/SKILL.md"
INTERVIEW="skills/setup-config/references/interview.md"
SETUP="skills/setup-config/SKILL.md"
UPDATE="skills/setup-config/references/update-mode.md"
MIGRATE="skills/setup-config/references/migrate-mode.md"
CONTRACT="skills/setup-config/references/config-contract.md"

fails=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1" >&2; fails=$((fails + 1)); }

echo "Execution-site human surface (issue #343, epic #322)"

for f in "$GROOM" "$SURVEY" "$INTERVIEW" "$SETUP" "$UPDATE" "$MIGRATE" "$CONTRACT"; do
    [ -r "$f" ] || bad "missing file: $f"
done
[ "$fails" -eq 0 ] || { echo "test-execution-site-surface: FAILED" >&2; exit 1; }

# Flatten to one line for phrase matching: strip leading blockquote markers and
# list indentation, then join. Without it a hard wrap between two words of an
# asserted phrase is a false miss.
flat() {
    sed -e 's/^[[:space:]]*>[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' "$1" |
        tr '\n' ' ' | tr -s ' '
}
groom_flat="$(flat "$GROOM")"
survey_flat="$(flat "$SURVEY")"
interview_flat="$(flat "$INTERVIEW")"
setup_flat="$(flat "$SETUP")"
update_flat="$(flat "$UPDATE")"
migrate_flat="$(flat "$MIGRATE")"
contract_flat="$(flat "$CONTRACT")"

# want <label> <haystack> <pattern>...  — every pattern must be present.
want() {
    local label="$1" hay="$2"; shift 2
    local pat
    for pat in "$@"; do
        if ! printf '%s' "$hay" | grep -qiE -- "$pat"; then
            bad "$label (missing: $pat)"
            return
        fi
    done
    ok "$label"
}

# reject <label> <haystack> <pattern> <proof>
#
# A must-not-exist check passes trivially when its pattern is malformed or has
# been reworded past the thing it bans, so the pattern is first run against
# <proof> — the literal sentence it exists to keep out. A pattern that cannot
# match its own subject FAILS here rather than reporting a clean file.
reject() {
    local label="$1" hay="$2" pat="$3" proof="$4"
    if ! printf '%s' "$proof" | grep -qiE -- "$pat"; then
        bad "$label — the ban pattern does not match its own proof string; it is vacuous"
        return
    fi
    if printf '%s' "$hay" | grep -qiE -- "$pat"; then
        bad "$label"
    else
        ok "$label"
    fi
}

# --- 1. groom-backlog: rubric #9 is a LABEL rule ------------------------------

rubric_row="$(grep -E '^\| 9 \|' "$GROOM" | tr '\n' ' ')"
if [ -n "$rubric_row" ]; then
    want "groom-backlog rubric #9 requires a site:<name> label" "$rubric_row" \
        'execution site' 'site:<name>' 'label'
else
    bad "groom-backlog has no rubric row 9 — the site test is gone from the table"
fi

want "groom-backlog applies the label and never writes a body line" "$groom_flat" \
    'never writes a .site:. line into the body'

want "groom-backlog keeps the reason a label was chosen over a body line" "$groom_flat" \
    'label cannot be quoted in prose'

# The resolution rules have ONE home. Restating them here is how the two copies
# start disagreeing about what an empty value or a folded name means.
want "groom-backlog runs the resolver instead of paraphrasing it" "$groom_flat" \
    'queue-snapshot.sh --sites-of' 'never by paraphrasing its rules'

want "groom-backlog never invents the site name" "$groom_flat" \
    'never invent the name' 'execution_site'

want "groom-backlog treats several site: labels as narrowing, never a defect" "$groom_flat" \
    'labels NARROW; they never widen' 'never remove one to .resolve a conflict'

want "groom-backlog carries the operational-checklist verdict, never Ready" "$groom_flat" \
    'parked: operational' 'never Ready'

# The verdict has to reach the REPORT, not only the rubric prose: the final
# table is the only part of a grooming run a reader is guaranteed to see.
want "the operational verdict is in §6's final-table verdict list" "$groom_flat" \
    'verdict \(\*\*Ready\*\*[^)]*parked: operational'

want "groom-backlog guards the body-line edit in its Guardrails" "$groom_flat" \
    'never write a .site:. line into an issue body'

# --- 2. survey-work: the plate separates here-vs-elsewhere --------------------

want "survey-work resolves the site from the labels it already pulled" "$survey_flat" \
    'execution site from the labels'

want "survey-work runs the resolver instead of re-deriving it" "$survey_flat" \
    'queue-snapshot.sh --sites-of' 'rather than re-deriving its rules'

# Rule 2 of the four: the no-label case is the overwhelming majority, and a
# token on every line is the "improvement" that makes the plate useless.
want "an unlabelled issue renders exactly as it did before" "$survey_flat" \
    'renders exactly as it did before this rule existed'

want "an off-site issue is marked, not hidden" "$survey_flat" \
    'not this checkout' 'never demote it for being elsewhere'

want "several site: labels render as narrowing, with no third rendering" "$survey_flat" \
    'no third rendering for a multi-member declaration' 'never reported as undispatchable'

# A recommendation the dispatcher then refuses trains a reader to stop trusting
# the line, which costs more than the omission does.
want "the To ship: line names only what this checkout can take" "$survey_flat" \
    'only issues this checkout can take' 'hands the user a .take. that the dispatcher will refuse'

want "survey-work stays read-only about the label" "$survey_flat" \
    'never act on it' 'stays read-only whatever the'

# --- 3. setup-config: the interview that fills the key ------------------------

if grep -qE '^### 3d\.' "$INTERVIEW"; then
    ok "interview.md carries a §3d execution-site question"
else
    bad "interview.md has no §3d — nothing asks for execution_site"
fi

want "§3d is confined to the three one-time modes" "$interview_flat" \
    'asked once, in create, migrate and adopt modes' 'skipped on a refresh unless the user raises it'

want "§3d points at the contract's table instead of carrying one" "$interview_flat" \
    'uname -s' 'config-contract.md'

want "§3d asks with no default where the table proposes nothing" "$interview_flat" \
    'no proposal at all' 'no default'

want "§3d proposes and never assumes" "$interview_flat" \
    'never assumed' 'never write a value the user did not say'

want "a declined or unanswered §3d omits the key" "$interview_flat" \
    'declined, unanswered' 'omitted'

want "the defaults summary refuses to default execution_site" "$interview_flat" \
    'never defaulted either'

# --- 4. the platform table has exactly one home -------------------------------
#
# `uname -s` tokens, not proposed names: `mac` and `windows` are common words,
# while these strings appear nowhere else by accident. update-mode.md is
# excluded deliberately — it explains what `uname -s` answers and what it does
# NOT answer, which is the opposite of proposing from it.

TABLE_TOKENS='Darwin|MINGW64|MSYS_NT|CYGWIN_NT'
if printf '%s' "$contract_flat" | grep -qE -- "$TABLE_TOKENS"; then
    ok "the uname -s table is where the contract says it is"
else
    bad "config-contract.md no longer carries the uname -s table — the ban below would be vacuous"
fi
for pair in "interview.md:$interview_flat" "groom-backlog:$groom_flat" "survey-work:$survey_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    if printf '%s' "$body" | grep -qE -- "$TABLE_TOKENS"; then
        bad "$name restates the uname -s table — it has exactly one home, and a copy drifts"
    else
        ok "$name does not restate the uname -s table"
    fi
done

# --- 5. the pre-#343 "no interview exists yet" sentences are gone -------------
#
# Each proof is the retired sentence itself. They were true until this change
# landed, and each one instructs its mode NOT to propose — left in place they
# read as a live rule contradicting §3d.

reject "setup-config/SKILL.md no longer claims nothing proposes the key" \
    "$setup_flat" \
    'nothing proposes an .execution_site' \
    '**Nothing proposes an `execution_site:` today** — the platform-derived name becomes a proposal'

reject "update-mode.md no longer claims the §3d section is unwritten" \
    "$update_flat" \
    'until that section exists' \
    'to add; until that section exists there is no question shape and no way to record "declined"'

reject "migrate-mode.md no longer claims a decline cannot be recorded" \
    "$migrate_flat" \
    'until it exists there is no way to record' \
    "and until it exists there is no way to record that the user declined."

# ...and each mode now states its own half, so the rule is not merely deleted.

# --- 4b. the retired "matches no checkout" semantics stay retired -------------
#
# Until #341 the contract said several `site:` labels match no checkout, and
# both surfaces said so — grooming refused Ready, the plate called the issue
# undispatchable. #341 settled the opposite: membership NARROWS, and every
# named checkout may take the issue. Two files were rewritten, so the failure
# mode is one of them drifting back alone; the proof is the sentence each one
# actually carried.

reject "groom-backlog does not resurrect the match-no-checkout reading" \
    "$groom_flat" \
    'match(es)? no checkout' \
    'Several are a **conflict that matches no checkout**, not "any site"'

reject "survey-work does not resurrect the match-no-checkout reading" \
    "$survey_flat" \
    'match(es)? no checkout' \
    'renders as `site: CONFLICT (<a>, <b>)` — matches no checkout; undispatchable *anywhere*'

# Both surfaces reach the ONE resolver rather than each carrying their own.
for pair in "groom-backlog:$groom_flat" "survey-work:$survey_flat"; do
    name="${pair%%:*}"; body="${pair#*:}"
    want "$name runs queue-snapshot.sh --sites-of" "$body" \
        'queue-snapshot.sh --sites-of'
done

want "setup-config's guardrail names §3d and its three modes" "$setup_flat" \
    'interview §3d' 'create, migrate and adopt modes only'

want "update-mode refuses to ask on a refresh" "$update_flat" \
    'do not ask it on a refresh'

want "migrate-mode asks §3d as its one offer" "$migrate_flat" \
    'interview §3d'

if [ "$fails" -ne 0 ]; then
    echo "test-execution-site-surface: FAILED ($fails)" >&2
    exit 1
fi
echo "Execution-site surface tests: all green"
