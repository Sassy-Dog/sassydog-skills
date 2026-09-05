#!/usr/bin/env bash
# test-queue-snapshot-site.sh — queue-snapshot.sh's `site:` parse: it fires on
# the contract, and it fires on NOTHING ELSE (issue #340, epic #322).
#
# What #340 added. `queue-snapshot.sh` already parsed three machine-readable
# body contracts — `touches:`, literal `Depends on #N`, and `stack:`. #340 adds
# a fourth of the same shape: one line, one free-form token, absent meaning
# "any site". It is deliberately SUBSTRATE ONLY. Nothing filters, refuses or
# reports differently because of it; the consuming children (#341 dispatch
# filter, #343 grooming surface) are what make it act.
#
# Why a substrate change still needs a gate, and why BOTH directions. A parse
# that only ever has to prove "it fires" passes just as well when it fires on
# everything, and a field nothing consumes yet is a field nobody will notice is
# wrong. By the time #341 reads it, a false `site` is an issue the loop refuses
# to dispatch with a reason that names a workstation nobody asked about — and
# the answer to "why did my issue stop moving" is three files away. The mirror
# harm is quieter still: a MISSED declaration reads as "any site", so the wrong
# loop claims a site-held issue and burns an attempt it could never satisfy.
# Every row here therefore comes in a pair — the shape that must parse and the
# shape that must not — with the no-`site:` body pinned field-for-field against
# what it emitted before this change.
#
# The false-positive half is not hypothetical, which is why the masking exists
# at all. Both issues that introduced this contract — #322 and #340 — carry a
# fenced example holding a `site: vdi` line, and neither issue is site-held. A
# fence-blind parse therefore marks the substrate issues THEMSELVES as VDI-only
# on the very first tick after the feature lands. The HTML-comment half is the
# same class one step later: `key: <!-- placeholder -->` is the standard issue
# template idiom, and #343 is the child that puts `site:` into templates, so a
# parse reading the raw line rather than the comment-stripped remainder would
# hold every unfilled issue at "requires site `<!--`".
#
# WHAT IS MASKED, EXACTLY. Every bullet below is a near-miss that looks like
# the rule and is not it, and each names the rows that hold it up:
#   * A FENCED block is masked, delimiters included. Openers and closers pair
#     on CHARACTER, RUN LENGTH and a whitespace-only tail (CommonMark), so a
#     ```-fenced example quoted inside a ````-fenced block does not end the
#     quote, a ``` does not close a ~~~, and an info string is not a closer.
#     Rows 118-122 are the three clauses plus the recovery afterwards.
#   * An HTML COMMENT is masked by REMAINDER, not by line: the site parse reads
#     what is left of the line outside every comment span. Rows 115-117. A line
#     that opens or continues a BLOCK comment is an HTML block for its whole
#     length, so no fence opens on it either (row 138), and a `<!--` inside a
#     fence opener's info string is not markup at all (row 136).
#   * Inside a fence, comment syntax is CONTENT — the walk does not run
#     there, or comment state LEAKS PAST the block and masks the first real
#     declaration after it (row 123). The closer itself is unaffected either
#     way: `closes_fence` reads the raw line.
#   * Neither mask may swallow text GitHub RENDERS. Three CommonMark
#     constructs are honoured for that reason, each measured against a real
#     body first: CODE SPANS are blanked before markup is looked for (row 125
#     — this repo's issue #6 carries a backticked `<!-- generated-by: …` with
#     no closer, which masked 25 of its 30 non-blank lines and swallowed a
#     fence opener; row 128 is the same mechanism opening a bogus fence from a
#     backticked info string); the EMPTY COMMENTS `<!-->` and `<!--->` close
#     where they stand (rows 126-127); and a mid-line `<!--` is inline HTML
#     that dies at its paragraph (row 130).
#   * ACCEPTED DIVERGENCES, pinned rather than closed — THREE of them, each
#     with a row, so changing any one is a decision rather than a surprise.
#     None appeared in 554 sampled org bodies.
#       - `<script>`, `<style>` and `<?…?>` are not masked (row 129), so a
#         `site:` inside one is read although GitHub's sanitizer drops those
#         elements with their contents. FALSE POSITIVE; closing it costs a
#         third line-state machine. Row 142 is its RECOVERY row and is why 129
#         is not weak: a correct mask and a never-closing one flip 129
#         identically, and only 142 tells them apart — the same job row 122
#         does for fences.
#       - A code span pairs per LINE, so one spanning a break does not blank
#         and text inside it declares (row 139). FALSE POSITIVE; closing it
#         means carrying span state across lines, which the per-line index map
#         exists to avoid.
#       - An UNCLOSED mid-line `<!--` masks the rest of its paragraph (row
#         140), though CommonMark renders it literally. FALSE NEGATIVE, and
#         bounded — row 130's blank-line rule stops it at the paragraph.
#         Closing it needs lookahead for a closer that may never arrive.
#   * The token has a GRAMMAR (rows 131-135, one row per clause):
#     `^[a-z0-9][a-z0-9._-]{0,63}$`
#     after folding. A consumer echoes the token into a refusal reason (#341)
#     and a public repo's body stays editable after `ready` is applied, so the
#     boundary is asserted once at the parse. Both malformed shapes — no token,
#     and a token failing the grammar — answer alike: not a declaration.
#
# THE ASYMMETRY IS DELIBERATE AND IS PINNED HERE (row 112). All of that applies
# to `site:` alone. `touches:` inside a fence is still parsed, exactly as it
# was before #340, because narrowing it is a BEHAVIOUR change for every
# consumer already reading it — a body whose only `touches:` sits in a fence
# would flip to `unannotated`, and dispatch-ready's collision filter reads
# that. #340 is substrate only, so the older contracts keep the parse they
# shipped with. A later "make the parser consistent" sweep is exactly what this
# row stops; if it fails, read this paragraph before deleting it.
#
# INDENTATION IS NOT A CODE BLOCK, and row 111 is a NESTED list continuation at
# four columns on purpose. CommonMark would make four leading spaces an
# indented code block; the contract's leading-whitespace tolerance is what lets
# it sit under a nested list item, which is already past that threshold. A
# two-space fixture would satisfy this row while a 4-space rule was in force,
# so the row would be measuring nothing — M4 is what proves it is not.
#
# THE MUTATION PROOFS. Twenty-one, each neutering ONE decision, each proved
# applied (the mutant must differ from the source), proved to RUN (a mutant that
# dies proves nothing), and proved by the row it reddens:
#   M1  the extraction itself        -> 101, the plain `site: vdi` row
#   M2  the fenced-content mask      -> 106, the fenced example declares
#   M3  the case fold                -> 103, `Site: VDI` stops matching
#   M4  a 4-space indented-code rule -> 111, the nested list continuation
#   M5  the closer's LENGTH clause   -> 119 (and 122 — see below)
#   M6  the closer's CHAR clause     -> 120, a 3-tick line ends a ~~~ block
#   M7  the closer's TAIL clause     -> 121, a delimiter with a tail closes
#   M8  the comment walk, in fences  -> 123, state leaks past the block
#   M9  `body` dropped from --json   -> 101, every contract at once
#   M10 the site match on `line`     -> 108, a block comment declares
#   M11 ALL THREE closer clauses     -> 118, the pre-fix rule
#   M12 the token grammar            -> 131, shell metacharacters emit
#   M13 code-span blanking           -> 125 (and 128 — same mechanism)
#   M14 the empty-comment forms      -> 126, `<!-->` never closes
#   M15 the inline-comment paragraph -> 130, a mid-line `<!--` runs to EOF
#   M16 the grammar's LENGTH bound   -> 134, a long real hostname is rejected
#   M17 the grammar's FIRST class    -> 135, `--help` becomes a site name
#   M18 the info-string comment reset-> 136, state leaks past the block
#   M19 the backtick info-string rule-> 137, a fence opens and never closes
#   M20 the HTML-block line rule     -> 138, a fence marker masks the body
#   M21 `re.ASCII` on the key match  -> 141, a lookalike key declares
# The named row is the one to read; it is NOT a claim of exclusivity, and two
# of these deliberately reach further. M5 also reddens 122, because a bare
# 3-tick line that wrongly closes the 4-tick block leaves the trailing 4-tick
# delimiter to OPEN one over `site: mac`; M13 also reddens 128, which is the
# same missing blanking seen from the fence side; M10 also reddens 116.
#
# ROW 115 IS DOUBLE-COVERED AND NO MUTANT REDDENS IT, which is worth knowing
# before reading it as M10's proof. The unfilled `<!-- vdi | mac -->`
# placeholder is kept out twice over — the comment span is stripped, and
# independently `<!--` fails the token grammar — so M10 leaves it null for the
# second reason. That is why M10 asserts on 108, whose token is a clean `vdi`
# inside a block comment and has no second cover. Row 117 HAD the same property
# and was reshaped rather than annotated: it now carries a block comment holding
# a clean `vdi`, so the mask is its only rejector and M10 reaches it. Two rows
# of one shape needed one of each. M11 is why row 118 exists at
# all: its tagged inner opener is stopped by the LENGTH clause and the TAIL
# clause independently, so no single-clause mutant reaches it and only the
# pre-fix character-only rule does. Without M2 and M10 in particular a reviewer
# cannot tell the masking from decoration.
#
# ROW 124 IS A SMOKE ROW AND CARRIES NO MUTANT, deliberately. CRLF is what
# GitHub actually stores, so the row is worth having, but `splitlines()` cannot
# be mutated into failing it: under `split("\n")` the `\r` is absorbed
# independently by `^\s*`, by `.split()` and by the grammar's own anchors, so
# every candidate mutation stays green. Read it as coverage, not as a pin.
#
# Network-free: a PATH-shimmed mock `gh` serving recorded `gh issue list`
# payloads per label, plus `gh api user`. `REPO=<owner/name>` in the
# environment is what suppresses queue-snapshot's `gh repo view` lookup (it
# runs that lookup only when REPO is EMPTY), so a machine with a real
# authenticated gh behaves exactly like CI. Two clauses make "no network"
# STRUCTURAL rather than merely intended, both carried from
# test-file-or-link-issue.sh: the shim's resolution is verified immediately
# after `chmod` and EXITS if PATH did not pick it up — a noexec `$TMPDIR` would
# otherwise send every read to the operator's real `gh` — and the slug uses the
# RFC 2606 `.invalid` TLD, because `mock-org` is a REAL GitHub organization and
# 12 runs times 4 reads is 48 authenticated requests into a third party's
# namespace. The mock HONOURS `--json`,
# projecting each fixture to the requested fields, because a script that
# stopped asking for `body` would otherwise still pass every row here while
# returning nothing against real `gh` (M9). queue-snapshot swallows a failed
# list into `[]`, which would make every must-NOT-parse row vacuous, so bucket
# sizes are asserted before any field is read.
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

echo "queue-snapshot site parse (issue #340) — work: $WORK" >&2

# --- the mock gh --------------------------------------------------------------
# queue-snapshot makes exactly two kinds of call: `gh api user` and one
# `gh issue list … --label <bucket> --json <fields>` per bucket. Anything else
# is a contract breach and exits non-zero, which queue-snapshot turns into an
# empty bucket — caught by the size assertions rather than passed over.
#
# `--json` is HONOURED: each fixture is projected to the requested field list,
# the same way scripts/test-stale-issues.sh and scripts/test-file-or-link-issue.sh
# do it. A mock that served whole objects regardless would keep every row here
# green after `body` was dropped from the pull, which is the one change that
# silently empties every body contract at once (M9).
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
# read-only here, but 48 authenticated requests against somebody else's
# namespace, and this file's header claims "no network". Same shape and same
# reason as test-file-or-link-issue.sh: the check sits immediately after the
# chmod and EXITS rather than recording a failed assertion.
if [ "$(PATH="$BIN:$PATH" command -v gh)" != "$BIN/gh" ]; then
    echo "test-queue-snapshot-site: the mock gh shim did not install at $BIN/gh — refusing to run, because every read below would reach the real GitHub API" >&2
    exit 1
fi

# --- recorded issue bodies ----------------------------------------------------
# Written by python3 rather than by hand: every interesting body here is
# multi-line and several nest fences of different lengths, and hand-escaping
# that into JSON is precisely how a fixture ends up testing a shape nobody
# meant to write.
python3 - "$FX" <<'PY'
import json, os, sys

out = sys.argv[1]

def issue(n, title, body, labels, assignees=()):
    return {
        "number": n,
        "title": title,
        "body": body,
        "labels": [{"name": x} for x in labels],
        "assignees": [{"login": x} for x in assignees],
    }

F3 = "`" * 3            # an ordinary fence
F4 = "`" * 4            # a fence long enough to QUOTE an ordinary one

ready = [
    # 101 — the contract, exactly as documented.
    issue(101, "plain", "Some prose.\n\nsite: vdi\n", ["ready"]),
    # 102 — NO site line. The control: every other field must be what it was
    # before #340, and `site` must be null rather than absent.
    issue(102, "no site", "Nothing to declare.\n\ntouches: a/b c/d\nDepends on #7\n", ["ready"]),
    # 103 — leading whitespace, a TAB after the colon, mixed case on both the
    # key and the value, trailing spaces.
    issue(103, "shapes", "   Site:\tVDI  \n", ["ready"]),
    # 104 — two declarations; the first wins.
    issue(104, "multiple", "site: vdi\nsite: mac\n", ["ready"]),
    # 105 — valueless lines declare nothing, and the scan continues past them.
    issue(105, "valueless then valid", "site:\nsite:   \nsite: mac\n", ["ready"]),
    # 106 — the #340/#322 shape: the ONLY `site:` text is a fenced example.
    issue(106, "fenced only",
          "Contract:\n\n%s text\nsite: vdi\n%s\n\nMore prose.\n" % (F3, F3), ["ready"]),
    # 107 — a fenced example AND a real declaration; the real one wins.
    issue(107, "fenced then real",
          "%s text\nsite: vdi\n%s\n\nsite: mac\n" % (F3, F3), ["ready"]),
    # 108 — inside a multi-line HTML comment.
    issue(108, "html comment", "<!--\nsite: vdi\n-->\n", ["ready"]),
    # 109 — backticks tolerated in the value, as in `touches:`.
    issue(109, "backticked", "site: `vdi`\n", ["ready"]),
    # 110 — one token is the contract; the rest of the line is a remark.
    issue(110, "extra tokens", "site: vdi (corp laptop)\n", ["ready"]),
    # 111 — indentation is NOT a code block. FOUR columns, under a NESTED list
    # item: a two-space fixture would pass even with a 4-space rule in force,
    # so it would measure nothing. M4 proves this one is not vacuous.
    issue(111, "nested list continuation", "- a\n  - notes:\n    site: vdi\n", ["ready"]),
    # 112 — the asymmetry: in ONE body, a fenced `touches:` is still parsed
    # (pre-#340 behaviour, untouched) while the fenced `site:` is not.
    issue(112, "asymmetry",
          "Example:\n\n%s text\ntouches: fenced/only.md\nsite: vdi\n%s\n" % (F3, F3), ["ready"]),
    # 113 — tilde fences count too.
    issue(113, "tilde fence", "~~~\nsite: vdi\n~~~\n", ["ready"]),
    # 114 — a site line beside the older contracts: no cross-talk either way.
    issue(114, "coexists", "touches: x/y\nstack: #1 #2\nsite: vdi\nDepends on #9\n", ["ready"]),

    # --- HTML comments are masked by REMAINDER, not by line (B1) --------------
    # 115 — the unfilled issue-template placeholder. Reading the raw line gives
    # `<!--` as the site name.
    issue(115, "comment placeholder", "site: <!-- vdi | mac -->\n", ["ready"]),
    # 116 — a comment BEFORE the value on the same line: the value still counts.
    issue(116, "comment then value", "site: <!-- pick one --> vdi\n", ["ready"]),
    # 117 — first-wins must not lock a COMMENTED-OUT declaration in ahead of a
    # real line. A block comment holding a clean `vdi`, deliberately: with the
    # placeholder shape the grammar rejected `<!--` on its own and the mask was
    # not this row's only rejector, so M10 left it green — the same double
    # cover row 115 has, and there it is documented rather than reshaped.
    issue(117, "commented-out then real",
          "<!--\nsite: vdi\n-->\nsite: mac\n", ["ready"]),

    # --- fence pairing: character, length, tail (N1) --------------------------
    # 118 — a 4-tick quote containing a tagged 3-tick example: the shape the
    # pre-fix character-only pairing got wrong. Two clauses stop it
    # independently (length AND tail), so M11 rather than M5/M6/M7 is its
    # proof — see the mutant roster in the header.
    issue(118, "quoted fence, info string",
          "%smd\nprose\n%s text\nsite: vdi\n%s\n%s\n" % (F4, F3, F3, F4), ["ready"]),
    # 119 — the same quote with a BARE ``` inside: only the LENGTH clause
    # stops that one closing the ```` block.
    issue(119, "quoted fence, bare closer",
          "%smd\n%s\nsite: vdi\n%s\n" % (F4, F3, F4), ["ready"]),
    # 120 — a ``` inside a ~~~ block: only the CHARACTER clause stops it.
    issue(120, "mixed markers", "~~~\n%s\nsite: vdi\n~~~\n" % F3, ["ready"]),
    # 121 — a closer carrying trailing text is not a closer.
    issue(121, "closer with tail", "%s\n%s text\nsite: vdi\n%s\n" % (F3, F3, F3), ["ready"]),
    # 122 — and the block still ENDS: a declaration after it declares. Without
    # this row, "mask everything to end of body" would pass 118-121.
    issue(122, "declares after the block",
          "%smd\n%s\n%s\nsite: mac\n" % (F4, F3, F4), ["ready"]),

    # --- comment syntax is CONTENT inside a fence (N2) ------------------------
    # 123 — an unclosed `<!--` in a fenced example. If the comment walk runs
    # inside fences it eats the closing delimiter and the real declaration.
    issue(123, "unclosed comment in fence",
          "%shtml\n<!-- template\n%s\nsite: mac\n" % (F3, F3), ["ready"]),

    # 124 — a CRLF body, which is what GitHub actually stores. SMOKE ROW: no
    # mutant can redden it (see the header), so read it as coverage, not a pin.
    issue(124, "crlf", "prose\r\nsite: vdi\r\n", ["ready"]),

    # --- markup GitHub RENDERS is never masked (P1/P2) ------------------------
    # 125 — this repo's issue #6, reduced to its mechanism: a backticked
    # `<!-- generated-by: …` with no closer on the line. Read as a comment it
    # runs on, eats the fence opener two lines down, and masks the real
    # declaration. No blank line, so the paragraph rule cannot save it — code
    # span blanking is the only thing that does.
    issue(125, "comment inside a code span",
          "- registered with the raw comment: `<!-- generated-by: x | template: y`\n"
          "- did not register at all\n"
          "%smarkdown\nname: survey-work\n%s\n"
          "site: vdi\n" % (F3, F3), ["ready"]),
    # 126/127 — CommonMark's two empty comments close where they stand.
    # Resuming the search for `-->` past them masks the rest of the body.
    issue(126, "empty comment", "<!-->\nsite: vdi\n", ["ready"]),
    issue(127, "empty comment, long form", "<!--->\nsite: vdi\n", ["ready"]),
    # 128 — a backtick fence's info string may not contain a backtick, so this
    # is a code span and opens nothing. The same blanking as 125, seen from the
    # fence side.
    issue(128, "backtick in an info string",
          "%sgh pr merge%s here\nsite: vdi\n" % (F3, F3), ["ready"]),
    # 129 — THE ACCEPTED DIVERGENCE, pinned so changing it is a decision.
    # GitHub's sanitizer drops <style> with its contents; this parser does not,
    # so the declaration is read. See the header for why it is not closed.
    issue(129, "style block (accepted divergence)",
          "<style>\nsite: nowhere\n</style>\n", ["ready"]),
    # 130 — a mid-line `<!--` is inline HTML and cannot outlive its paragraph.
    # Without the blank-line bound it masks every line to the end of the body.
    issue(130, "unterminated inline comment",
          "We write <!-- markers in the body\n\nsite: vdi\n", ["ready"]),

    # --- the token grammar (C1) ----------------------------------------------
    # 131 — shell metacharacters are not a site name. A consumer echoes this
    # token into a refusal reason, and a public repo's body stays editable
    # after `ready` is applied.
    issue(131, "shell metacharacters", "site: $(id);rm\n", ["ready"]),
    # 132 — 65 characters, one past the grammar's bound.
    issue(132, "over-long token", "site: " + ("a" * 65) + "\n", ["ready"]),
    # 133 — and the grammar is PERMISSIVE: a realistic hostname-shaped name
    # passes. Without this row an over-tight grammar would look correct.
    issue(133, "realistic name", "site: mac-mini.local\n", ["ready"]),
    # 134/135 — the grammar's other two clauses. Without these, tightening the
    # repeat to {0,31} or flattening the first-character class to
    # `^[a-z0-9._-]{1,64}$` both leave every other row green: the first rejects
    # a long but real hostname (false negative), the second accepts `--help`
    # and `.hidden` for a consumer to echo.
    issue(134, "token at the bound", "site: " + ("a" * 64) + "\n", ["ready"]),
    issue(135, "flag-shaped token", "site: --help\n", ["ready"]),

    # --- markup on the fence OPENER's own line -------------------------------
    # 136 — a `<!--` in an info string is not markup. Entering a comment there
    # and letting it survive the block leaks state past the closer, which is
    # M8's defect reached by another route.
    issue(136, "comment in an info string",
          "%spython <!-- x\ncode\n%s\nsite: vdi\n" % (F3, F3), ["ready"]),
    # 137 — CommonMark: a backtick fence's info string may not contain a
    # backtick, so this is a paragraph. Blanking alone does not catch it — the
    # run here is PAIRED and therefore already erased — so the opener carries
    # its own check against the unblanked remainder.
    issue(137, "backtick in an info string, unpaired",
          "%spython `x`\nsite: vdi\n" % F3, ["ready"]),
    # 138 — `<!-- x --> ```` is ONE HTML block, not a comment followed by a
    # fence. Opening a fence there masks the rest of the body.
    issue(138, "html block, then a fence marker",
          "<!-- x --> %s\nsite: vdi\n" % F3, ["ready"]),

    # --- the two remaining ACCEPTED DIVERGENCES, pinned like row 129 ---------
    # 139 — a code span pairs per LINE, so one spanning a break does not blank
    # and text inside it declares. FALSE POSITIVE, recorded in the header.
    issue(139, "multi-line code span (accepted divergence)",
          "`foo\nsite: vdi`\nsite: mac\n", ["ready"]),
    # 140 — an UNCLOSED mid-line `<!--` masks the rest of its paragraph, though
    # CommonMark renders it literally. FALSE NEGATIVE, bounded by row 130's
    # blank-line rule. Recorded in the header.
    issue(140, "unclosed inline comment, no blank line (accepted divergence)",
          "We write <!-- markers\nsite: vdi\n", ["ready"]),

    # 141 — `re.IGNORECASE` on a str pattern folds Unicode, so `ſite:` (U+017F)
    # matched a key whose value grammar is ASCII-only.
    issue(141, "unicode-folded key", "\u017Fite: vdi\n", ["ready"]),
    # 142 — the RECOVERY row for the <style> divergence. Row 129 alone is
    # flipped identically by a correct mask and by one that never closes, so
    # closing the divergence later could ship a mask that swallows the body.
    # This is the style side's row 122.
    issue(142, "style block closes", "<style>\n</style>\nsite: vdi\n", ["ready"]),
]

in_progress = [
    issue(201, "claimed with site", "site: vdi\n", ["in-progress"], ["mock-login"]),
    issue(202, "claimed no site", "nothing here\n", ["in-progress"], ["someone-else"]),
]

blocked = [{"number": 301}, {"number": 302}]

for name, payload in (("ready", ready), ("in-progress", in_progress), ("blocked", blocked)):
    with open(os.path.join(out, name + ".json"), "w") as fh:
        json.dump(payload, fh)
PY

READY_N=42

# --- runner -------------------------------------------------------------------
OUT="$WORK/out.json"
STATUS=0
run_snapshot() { # <script-path>
    PATH="$BIN:$PATH" SCENARIO_DIR="$FX" REPO=mock-org.invalid/mock-repo \
        bash "$1" >"$OUT" 2>"$WORK/err"
    STATUS=$?
}

# site_of <bucket> <number> — the emitted site, or the literal string "null".
site_of() { jq -r --argjson n "$2" ".$1[] | select(.number==\$n) | .site | tostring" "$OUT"; }

expect_site() { # <label> <bucket> <number> <expected>
    local got; got="$(site_of "$2" "$3")"
    if [ "$got" = "$4" ]; then ok "$1"; else bad "$1 — #$3 site=$got, expected $4"; fi
}

# --- 0. the run itself, and the buckets are non-empty -------------------------
# queue-snapshot turns a failed `gh issue list` into `[]`, so a broken mock
# would empty every bucket. That does NOT pass silently — `site_of` on an empty
# bucket yields the empty string, which `expect_site … null` rejects — so the
# rows below fail loudly on their own. This assertion is the DIAGNOSTIC: it
# turns thirty red rows into one line naming the cause, and it runs first so
# that line is the first thing read.
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
    ok "buckets are populated (ready=$READY_N in_flight=2 blocked=2) — no row below is vacuous"
else
    bad "bucket sizes ready=$n_ready in_flight=$n_flight blocked=$n_blocked, expected $READY_N/2/2"
    sed 's/^/          | /' "$WORK/err" >&2
fi

# --- 1. it fires on the contract, in BOTH buckets -----------------------------
echo "1. the documented contract parses" >&2
expect_site "a plain 'site: vdi' line parses in ready[]" ready 101 vdi
expect_site "and in in_flight[] — both buckets, per #340" in_flight 201 vdi

# --- 2. it fires on nothing else ----------------------------------------------
echo "2. a body with no declaration is null in both buckets" >&2
expect_site "no site line in ready[] gives null" ready 102 null
expect_site "no site line in in_flight[] gives null" in_flight 202 null

# --- 3. no shape change for existing consumers --------------------------------
# #340's second acceptance line. A key SET check, not a spot check: a renamed
# or dropped field is the failure this is here to catch, and `site` is the only
# addition permitted.
echo "3. the emitted shape is the old one plus site" >&2
ready_keys="$(jq -r '.ready[] | select(.number==102) | keys_unsorted | sort | join(",")' "$OUT")"
flight_keys="$(jq -r '.in_flight[] | select(.number==202) | keys_unsorted | sort | join(",")' "$OUT")"
if [ "$ready_keys" = "assignees,depends_on,labels,number,site,stack,title,touches,unannotated" ]; then
    ok "ready[] carries exactly its pre-#340 keys plus site"
else
    bad "ready[] keys drifted: $ready_keys"
fi
if [ "$flight_keys" = "assignees,labels,mine,number,site,stack,title,touches" ]; then
    ok "in_flight[] carries exactly its pre-#340 keys plus site"
else
    bad "in_flight[] keys drifted: $flight_keys"
fi
control="$(jq -c '.ready[] | select(.number==102) | {touches, depends_on, stack, unannotated}' "$OUT")"
if [ "$control" = '{"touches":["a/b","c/d"],"depends_on":[7],"stack":[],"unannotated":false}' ]; then
    ok "and the no-site body's other fields are byte-for-byte what they were"
else
    bad "the no-site body's other fields changed: $control"
fi
if [ "$(jq -r '.in_flight[] | select(.number==201) | .mine' "$OUT")" = "true" ]; then
    ok "the 'mine' flag still resolves beside a parsed site"
else
    bad "'mine' no longer resolves on an issue carrying a site"
fi
if [ "$(jq -c '.blocked' "$OUT")" = "[301,302]" ]; then
    ok "blocked[] is still bare numbers"
else
    bad "blocked[] changed shape"
fi

# --- 4. the shapes the anchored regex must still see --------------------------
echo "4. leading whitespace, a tab after the colon, mixed case, CRLF" >&2
expect_site "'   Site:<TAB>VDI  ' parses, case-folded" ready 103 vdi
expect_site "a CRLF body parses — what GitHub actually stores" ready 124 vdi

# --- 5. ambiguity resolves the way the header says ----------------------------
echo "5. multiple and malformed declarations resolve deterministically" >&2
expect_site "two declarations: the FIRST wins" ready 104 vdi
expect_site "a valueless 'site:' declares nothing; the scan continues" ready 105 mac
expect_site "backticks are tolerated in the value" ready 109 vdi
expect_site "only the first token is the site; the rest is a remark" ready 110 vdi

# --- 6. the false-positive half -----------------------------------------------
# The measured one: #322 and #340 both carry a fenced 'site: vdi'.
echo "6. examples and placeholders are not declarations" >&2
expect_site "a fenced example alone gives null (the #322/#340 body shape)" ready 106 null
expect_site "a fenced example plus a real line gives the real one" ready 107 mac
expect_site "a multi-line HTML comment gives null" ready 108 null
expect_site "a tilde fence gives null" ready 113 null
expect_site "an unfilled '<!-- vdi | mac -->' placeholder gives null" ready 115 null
expect_site "  and a comment BEFORE the value leaves the value standing" ready 116 vdi
expect_site "  and first-wins does not lock the placeholder in" ready 117 mac

# --- 7. fence pairing, clause by clause ---------------------------------------
# Each row is the ONLY thing that fails if its clause is dropped; M5/M6/M7 are
# the proof. Row 122 is the recovery — without it, "mask to end of body" would
# satisfy all four.
echo "7. openers and closers pair on character, length and tail" >&2
expect_site "an info string is not a closer (a tagged 3-tick opener in a 4-tick quote)" ready 118 null
expect_site "a shorter run is not a closer (a bare 3-tick line in a 4-tick quote)" ready 119 null
expect_site "a different marker is not a closer (a 3-tick line in a ~~~ block)" ready 120 null
expect_site "trailing text after a closer is not a closer" ready 121 null
expect_site "and the block still ENDS — a line after it declares" ready 122 mac
expect_site "comment syntax inside a fence is content, not markup" ready 123 mac

# --- 8. markup GitHub renders is never masked ---------------------------------
# All false-negative: a masked declaration reads as "no site", which under #341
# means "any site", so the wrong loop claims the issue.
echo "8. code spans, empty comments and inline comments" >&2
expect_site "a code-spanned '<!--' opens no comment (issue #6's shape)" ready 125 vdi
expect_site "the empty comment '<!-->' closes where it stands" ready 126 vdi
expect_site "  and its long form '<!--->' does too" ready 127 vdi
expect_site "a backtick in an info string means a code span, not a fence" ready 128 vdi
expect_site "an unterminated mid-line comment dies at its paragraph" ready 130 vdi
expect_site "a comment in a fence info string does not leak past the block" ready 136 vdi
expect_site "a backtick in a backtick fence's info string means a paragraph" ready 137 vdi
expect_site "a comment then a 3-tick marker is one HTML block, not a fence" ready 138 vdi
expect_site "a Unicode-folded key does not declare" ready 141 null

# The three accepted divergences, pinned rather than closed — see the header.
expect_site "ACCEPTED: a <style> block is NOT masked, though GitHub drops it" ready 129 nowhere
expect_site "  and its recovery row: the block still ENDS" ready 142 vdi
expect_site "ACCEPTED: a code span spanning a line break declares from inside" ready 139 vdi
expect_site "ACCEPTED: an unclosed mid-line comment masks its paragraph" ready 140 null

# --- 9. the token grammar -----------------------------------------------------
echo "9. the token grammar bounds what a consumer is handed" >&2
expect_site "shell metacharacters are not a site name" ready 131 null
expect_site "a token past the 64-character bound is not a site name" ready 132 null
expect_site "and the grammar is permissive — a realistic name passes" ready 133 mac-mini.local
expect_site "  a 64-character token is at the bound, not past it" ready 134 "$(printf 'a%.0s' $(seq 64))"
expect_site "a flag-shaped token is not a site name" ready 135 null

# --- 10. the scope decisions --------------------------------------------------
echo "10. what is deliberately NOT masked" >&2
expect_site "a nested list continuation at four columns declares" ready 111 vdi
asym="$(jq -c '.ready[] | select(.number==112) | {touches, site}' "$OUT")"
if [ "$asym" = '{"touches":["fenced/only.md"],"site":null}' ]; then
    ok "the mask is site-only — a fenced touches: still parses, as before #340"
else
    bad "the touches/site asymmetry broke: $asym — see this file's header before 'fixing' it"
fi
coexist="$(jq -c '.ready[] | select(.number==114) | {touches, stack, depends_on, site}' "$OUT")"
if [ "$coexist" = '{"touches":["x/y"],"stack":[1,2],"depends_on":[9],"site":"vdi"}' ]; then
    ok "no cross-talk: touches, stack, depends_on and site coexist in one body"
else
    bad "cross-talk between the body contracts: $coexist"
fi

# --- 11. mutation proofs ------------------------------------------------------
# Each mutant neuters ONE decision. The exact-string replace is asserted to have
# applied (a drifted target reports "did not match", never a silent pass), the
# mutant is asserted to RUN, and only then is its row read.
echo "11. mutation proofs" >&2
MUT="$WORK/mutant.sh"
mutants_run=0
mutate() { # <label> <from> <to>
    if ! python3 - "$SNAP" "$MUT" "$2" "$3" <<'PY'
import io, sys
src, dst, frm, to = sys.argv[1:5]
s = io.open(src, encoding="utf-8").read()
if s.count(frm) != 1:
    sys.stderr.write("occurrences=%d\n" % s.count(frm))
    sys.exit(1)
io.open(dst, "w", encoding="utf-8").write(s.replace(frm, to))
PY
    then
        bad "$1 — the mutation target did not match exactly once in $SNAP (stale mutant)"
        return 1
    fi
    if cmp -s "$SNAP" "$MUT"; then
        bad "$1 — the mutant is identical to the source"
        return 1
    fi
    run_snapshot "$MUT"
    if [ "$STATUS" != "0" ] || ! jq -e ".ready | length == $READY_N" "$OUT" >/dev/null 2>&1; then
        bad "$1 — the mutant did not run (exit $STATUS), so its verdict proves nothing"
        return 1
    fi
    mutants_run=$((mutants_run + 1))
    return 0
}
reddens() { # <label> <bucket> <number> <value-the-shipped-script-gives>
    local got; got="$(site_of "$2" "$3")"
    if [ "$got" != "$4" ]; then
        ok "$1 (mutant gives '$got', shipped gives '$4')"
    else
        bad "$1 — the mutant still answers '$got', so the row proves nothing"
    fi
}

if mutate "M1 extraction" \
    '                    site = candidate   # both malformed shapes fall through' \
    '                    pass'; then
    reddens "M1: dropping the extraction darkens the plain 'site: vdi' row" ready 101 vdi
fi

if mutate "M2 fenced-content mask" \
    '            yield line, ""                   # fenced content declares nothing' \
    '            yield line, line'; then
    reddens "M2: unmasking fenced content makes the fenced example declare" ready 106 null
fi

if mutate "M3 case fold" \
    ".split() or [''])[0].lower()" \
    ".split() or [''])[0]"; then
    reddens "M3: dropping the case fold breaks 'Site: VDI'" ready 103 vdi
fi

if mutate "M4 indented-code rule" \
    '        visible, vscan, comment = strip_comments(line, scan, comment)' \
    '        visible, vscan, comment = strip_comments(line, scan, comment)
        if re.match(r"^(?: {4}|\t)", line):
            visible = ""'; then
    reddens "M4: a 4-space indented-code rule darkens the nested list row" ready 111 vdi
fi

if mutate "M5 closer length clause" \
    ' and len(marker) >= fence[1]' \
    ''; then
    reddens "M5: without the length clause a bare 3-tick line ends a 4-tick block" ready 119 null
fi

if mutate "M6 closer character clause" \
    'marker[0] == fence[0] and ' \
    ''; then
    reddens "M6: without the character clause a 3-tick line ends a ~~~ block" ready 120 null
fi

if mutate "M7 closer tail clause" \
    '
            and not line[m.end():].strip())' \
    ')'; then
    reddens "M7: without the tail clause a delimiter with trailing text closes" ready 121 null
fi

if mutate "M8 comment walk inside fences" \
    '            if closes_fence(line, fence):' \
    '            visible, vscan, comment = strip_comments(line, blank_code_spans(line), comment)
            if closes_fence(line, fence):'; then
    reddens "M8: walking comments inside a fence leaks state past the block" ready 123 mac
fi

if mutate "M9 body dropped from --json" \
    'FIELDS="number,title,labels,assignees,body"' \
    'FIELDS="number,title,labels,assignees"'; then
    reddens "M9: dropping 'body' from the pull darkens every body contract" ready 101 vdi
fi

if mutate "M10 site matched on the raw line" \
    '            m = site_re.match(visible)' \
    '            m = site_re.match(line)'; then
    reddens "M10: matching the raw line declares from inside a block comment" ready 108 null
fi

# The whole closer test reverted to the pre-fix rule — pairing on the marker
# character alone. This is the one mutant row 118 answers to, because the
# length and tail clauses each stop that shape on their own.
if mutate "M11 pre-fix character-only pairing" \
    '    return (marker[0] == fence[0] and len(marker) >= fence[1]
            and not line[m.end():].strip())' \
    '    return marker[0] == fence[0]'; then
    reddens "M11: pairing on the marker character alone lets a quoted example declare" ready 118 null
fi

if mutate "M12 the token grammar" \
    '                if site_token_re.fullmatch(candidate):' \
    '                if candidate:'; then
    reddens "M12: without the grammar a shell-metacharacter token is emitted" ready 131 null
fi

if mutate "M13 code-span blanking" \
    '        scan = blank_code_spans(line)' \
    '        scan = line'; then
    reddens "M13: without code-span blanking issue #6's body masks its own declaration" ready 125 vdi
fi

# Double-quoted, because the target carries single quotes and bash has no
# escape for one inside a single-quoted string. Nothing here is expanded: no
# `$`, no backtick, no backslash.
if mutate "M14 the empty-comment forms" \
    "            if scan.startswith('>', i):
                i, comment = i + 1, None
            elif scan.startswith('->', i):
                i, comment = i + 2, None" \
    '            pass'; then
    reddens "M14: without them an empty comment never closes and masks the body" ready 126 vdi
fi

if mutate "M15 the inline-comment paragraph bound" \
    "        if comment == 'inline' and not line.strip():
            comment = None                   # inline HTML dies at its paragraph" \
    '        pass'; then
    reddens "M15: without the bound a mid-line '<!--' runs to the end of the body" ready 130 vdi
fi

if mutate "M16 the grammar's length bound" \
    '{0,63}$' \
    '{0,31}$'; then
    reddens "M16: a tightened repeat rejects a long but real hostname" ready 134 "$(printf 'a%.0s' $(seq 64))"
fi

if mutate "M17 the grammar's first-character class" \
    "site_token_re = re.compile(r'^[a-z0-9][a-z0-9._-]{0,63}\$')" \
    "site_token_re = re.compile(r'^[a-z0-9._-]{1,64}\$')"; then
    reddens "M17: a flattened first character accepts a flag-shaped token" ready 135 null
fi

if mutate "M18 the info-string comment reset" \
    '            comment = None                   # an info string is not markup' \
    '            pass'; then
    reddens "M18: without it a comment in an info string leaks past the block" ready 136 vdi
fi

if mutate "M19 the backtick info-string rule" \
    '        if m and not tainted_info:' \
    '        if m:'; then
    reddens "M19: without it an unpaired backtick opens a fence that never closes" ready 137 vdi
fi

if mutate "M20 the HTML-block line rule" \
    "        if scan.lstrip().startswith('<!--'):
            html_line = True" \
    '        pass'; then
    reddens "M20: without it a fence marker after a comment masks the body" ready 138 vdi
fi

if mutate "M21 the ASCII flag on the key match" \
    're.IGNORECASE | re.ASCII' \
    're.IGNORECASE'; then
    reddens "M21: without it Unicode folding lets a lookalike key declare" ready 141 null
fi

if [ "$mutants_run" -eq 21 ]; then
    ok "every declared mutant ran (21 of 21)"
else
    bad "only $mutants_run of 21 declared mutants ran — the rest proved nothing"
fi

# Restore the un-mutated snapshot for anything reading $OUT after this point.
run_snapshot "$SNAP"

# --- 12. the header states the resolution -------------------------------------
# #340's acceptance requires the multiple/malformed choice to be stated in the
# script header, because a deterministic answer is only useful to a reader who
# can find out what it is. Scoped to the LEADING COMMENT BLOCK: flattening the
# whole file would let a needle satisfied by a python comment 100 lines down
# pass a check named "the header documents the resolution". Within that block
# the leading `#` is stripped BEFORE the join — the same normalisation
# test-doc-reconciliation.sh applies to blockquote markers, and for the same
# reason: without it a wrapped sentence flattens to "... read as a # declaration"
# and every needle spanning a wrap silently fails.
echo "12. the header documents the resolution" >&2
FLAT="$WORK/snap.flat"
awk '/^#/ {print; next} /^[[:space:]]*$/ {next} {exit}' "$SNAP" |
    sed -e 's/^[[:space:]]*#[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' |
    tr '\n' ' ' | tr -s ' \t' ' ' >"$FLAT"
# TWO negative needles, because one of them cannot catch the regression this
# section exists to prevent. `def parse_body` is a CODE line, and the awk
# already drops every line that is not a comment — so a flatten that swallowed
# the whole file's `#` comments (measured: delete the awk's `{exit}`) still
# never contains it and the guard stays green. The second needle is a phrase
# living ONLY in the python comment region, which is exactly the text a
# runaway flatten would pull in.
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
expect_flat "the header names the contract as one line, one token" \
    'One line, one free-form'
expect_flat "  and that absent means any site" \
    'ABSENT MEANS "any site"'
expect_flat "  and that the first line carrying a token wins" \
    'The FIRST `site:` line carrying a token wins'
expect_flat "  and that only the first token is the site" \
    'Only the first whitespace-separated token is the site'
expect_flat "  and that case is folded" \
    'Case is folded'
expect_flat "  and that the comparison is case-insensitive on BOTH sides" \
    'case-insensitive on BOTH sides'
expect_flat "  and that the token has a bounded grammar" \
    'The token has a GRAMMAR, applied after folding'
expect_flat "  and why the parse owns that boundary rather than each consumer" \
    'echoes the token into a refusal reason'
expect_flat "  and that BOTH malformed shapes answer alike" \
    'TWO malformed shapes exist and both answer the SAME way'
expect_flat "  and that no token is reserved inside the grammar" \
    'NOTHING IS RESERVED inside that grammar'
expect_flat "  and that code spans are blanked before markup is looked for" \
    'CODE SPANS are blanked before any markup is looked for'
expect_flat "  and that the empty comments close where they stand" \
    'close where they stand'
expect_flat "  and that a mid-line comment dies at its paragraph" \
    'cannot outlive its'
expect_flat "  and that the script/style divergence is accepted, not missed" \
    'ACCEPTED DIVERGENCE, recorded rather than closed'
expect_flat "  and that a fenced line is not a declaration" \
    'Lines inside a FENCED code block are not read as a declaration'
expect_flat "  and that comments are masked by REMAINDER, not by line" \
    'comment-stripped remainder of a line'
expect_flat "  and that indentation is deliberately NOT a code block" \
    'Indentation is deliberately NOT read as a code block'
expect_flat "  and that the CommonMark 4-space rule is what it declines" \
    'four leading spaces an indented code block'
expect_flat "  and that the mask is site-only, with the reason" \
    'applies to `site:` ALONE'

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "queue-snapshot site tests: all green ($asserts assertions, 21 mutants)" >&2
    exit 0
fi
echo "queue-snapshot site tests: FAILURES above ($asserts assertions)" >&2
exit 1
