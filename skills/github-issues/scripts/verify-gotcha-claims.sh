#!/usr/bin/env bash
# verify-gotcha-claims.sh — resolve a groom-backlog config's `gotcha_summary`
# against real issue state BEFORE any of it is copied into an issue body.
#
# Why this exists (issue #249). `gotcha_summary` is free prose living in a
# frontmatter slot, which means it inherits neither protection the config format
# provides: it is not derived (nothing recomputes it after setup) and it is not
# in the `##` prose lane a human consciously curates. It is therefore the one
# field that can assert a TIME-VARYING fact and have nothing — generator,
# contract, or habit — ever revisit it. `Sassy-Dog/solador`'s config asserted
# "#15 is not finished — #308 (updater) and #334 (Windows + Authenticode)
# remain" for nine days after all three closed, and the consumer of that text is
# a cold worktree agent with zero conversation context and no way to check it.
#
# WHAT "FAIL-CLOSED" MEANS HERE. A claim citing `#N` survives only when its
# asserted state is explicit AND currently true. Everything else is dropped with
# a reason: the state is wrong, the issue cannot be resolved, or the claim cites
# an issue without asserting anything checkable. UNKNOWN IS HELD, NEVER PASSED
# THROUGH — that is the whole design, so there is deliberately NO skip exit. A
# missing `gh`, an unknown repo, or a network failure makes every citing claim
# unresolvable and therefore dropped; it never makes them pass. A verifier that
# degrades to "assume fine" is indistinguishable from no verifier at all on the
# exact day it matters.
#
# Claims with no `#N` at all are invariants — "business logic lives in
# `crates/`, never in the Tauri shell" — and are kept untouched. They are what
# the field is for; see setup-config/references/config-contract.md.
#
# A CLAIM MUST FIRST BE A CLAIM (issue #262). Fail-closed classification is only
# as good as the unit handed to it, and the splitter used to cut inside inline
# code: the `;` in `code=0; cmd || code=$?` ended a claim, and the truncated head
# — citing no `#N` — was classified an invariant and shipped inside the SAFE
# markers. So the splitter below PARSES backtick runs rather than counting
# ticks, quarantines the WHOLE field when a run has no partner, and — the part
# that actually ends the family — LINKS the fragments of a sentence into a
# group that is committed or dropped together.
#
# THE COST IS OVER-LINKING, AND IT IS DELIBERATE. Because a new group needs
# positive evidence, any sentence following an abbreviation-shaped token — four
# characters or fewer included — is welded to its predecessor and dropped with
# it. `Pin every action to a full SHA. bun install must run …` loses the SHA
# invariant when the second sentence cites a dead issue. That is accepted: a
# lost invariant is visible in the report, a fabricated one is not. Two
# consequences follow. A neighbouring sentence can be dropped for a citation
# that is not its own, and a sentence whose REFERENT was dropped can survive
# ("Always export it." after the clause defining "it" has gone) — resolving
# that means anaphora, which this deliberately does not attempt.
#
# TWO GUESSES WERE TRIED AND BOTH ARE DELETED. Do not reintroduce either.
# Backtick PARITY cannot see a cut landing between an even number of ticks, nor
# one in text carrying none, so it certifies exactly the fragments it appears
# to catch, and it mis-names the reason on merely stale claims. A padded-span
# HEURISTIC ("a span padded with a space and carrying sentence punctuation is
# probably mis-bound prose") then caught three reported shapes and missed a
# fourth, while dropping legal input: ` git add .; git commit ` is correctly
# paired Markdown, and padding is REQUIRED when span content starts or ends
# with a backtick. Each narrowing had a next input, because which ticks the
# author meant is not decidable from the text. Group linkage removes the need
# to decide: a wrong guess costs a drop, never a fabrication.
#
# The caller copies the text between the SAFE GOTCHAS markers into the issue
# body. It never copies the raw config field: dropping a claim from a report
# while the body still carries it protects nobody.
#
# `--lint` is the offline half, for finding configs that already carry
# time-varying claims so a refresh can NAME them rather than silently preserving
# them. No `gh`, no network: it reports shapes (issue refs, state verbs, "as of
# <date>", roadmap status), never truth.
#
# Usage:
#   verify-gotcha-claims.sh --config <path> [--repo owner/name]
#   verify-gotcha-claims.sh --text-file <path> [--repo owner/name]
#   verify-gotcha-claims.sh --config <path> --lint
#
# Env:  REPO=owner/name  (fallback when --repo is absent; else inferred with
#                         `gh repo view` from cwd)
#
# Exit: 0 nothing dropped (or, under --lint, nothing found)
#       3 at least one claim dropped (or, under --lint, at least one finding)
#       64 usage
# Read-only: never writes, never mutates, one `gh issue view` per distinct ref.
set -uo pipefail

CONFIG=""
TEXT_FILE=""
REPO_SLUG="${REPO:-}"
LINT=0

usage() {
    cat >&2 <<'USAGE'
usage: verify-gotcha-claims.sh (--config PATH | --text-file PATH) [--repo owner/name] [--lint]
  --config PATH     a .claude/sassy-dog/groom-backlog.md; gotcha_summary is read from its frontmatter
  --text-file PATH  raw gotcha text instead of a config file
  --repo owner/name the repo the cited #N belong to (else $REPO, else `gh repo view`)
  --lint            offline: report time-varying shapes, resolve nothing
exit: 0 clean · 3 claims dropped / findings · 64 usage
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)    CONFIG="${2:-}"; shift 2 || true ;;
        --text-file) TEXT_FILE="${2:-}"; shift 2 || true ;;
        --repo)      REPO_SLUG="${2:-}"; shift 2 || true ;;
        --lint)      LINT=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "verify-gotcha-claims: unknown argument '$1'" >&2; usage; exit 64 ;;
    esac
done

if [ -n "$CONFIG" ] && [ -n "$TEXT_FILE" ]; then
    echo "verify-gotcha-claims: --config and --text-file are mutually exclusive" >&2
    exit 64
fi
if [ -z "$CONFIG" ] && [ -z "$TEXT_FILE" ]; then
    usage
    exit 64
fi

SRC="${CONFIG:-$TEXT_FILE}"
if [ ! -f "$SRC" ]; then
    echo "verify-gotcha-claims: no such file: $SRC" >&2
    exit 64
fi

# --- extract the field -------------------------------------------------------
# Frontmatter only, and only `gotcha_summary:`. Handles the inline scalar and
# the folded/literal block form the template renders (`gotcha_summary: >`).
extract_summary() {
    awk '
        NR == 1 && $0 == "---" { inf = 1; next }
        inf == 1 && $0 == "---" { exit }
        inf != 1 { next }
        grab == 1 {
            if ($0 ~ /^[ \t]*$/) { print ""; next }
            if ($0 ~ /^[ \t]+/) { sub(/^[ \t]+/, ""); print; next }
            grab = 0
        }
        /^gotcha_summary:/ {
            val = $0
            sub(/^gotcha_summary:[ \t]*/, "", val)
            if (val ~ /^[>|]/) { grab = 1 } else if (val != "") { print val }
            next
        }
    ' "$1"
}

if [ -n "$CONFIG" ]; then
    RAW="$(extract_summary "$CONFIG")"
else
    RAW="$(cat "$TEXT_FILE")"
fi

# Fold to one paragraph, then split into claims on sentence boundaries. A claim
# is the unit that is kept or dropped: discarding the whole field over one
# rotted sentence would throw away the invariants that make it worth having.
SUMMARY="$(printf '%s\n' "$RAW" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CLAIMS="$WORK/claims"
CACHE="$WORK/cache"
: >"$CACHE"

# INLINE CODE IS PARSED, NOT PATTERN-MATCHED, BEFORE THE SPLIT (issue #262). A
# sentence-boundary regex that cannot see backticks cuts a claim in half at the
# `;` in `code=0; cmd || code=$?`, and the damage is not the lost tail — that
# keeps the `(#N)` and drops as unverifiable. It is the HEAD: `exit-code capture
# is `code=0;` cites no issue at all, so it is classified an INVARIANT and
# emitted into the SAFE block the caller copies verbatim into an issue body. The
# tool then fabricates a truncated instruction and certifies it as verified,
# which is strictly worse than losing the claim. Shell idioms are where `;`,
# `.`, `!` and `?` live (`. ./scripts/lib.sh`, `[ ! -f "$f" ]`, `[ $? -ne 0 ]`),
# so the field's most useful entries are the likeliest to be cut.
#
# SPANS ARE PAIRED BY BACKTICK RUN, NOT BY COUNTING TICKS. Toggling on each
# backtick is the obvious implementation and it is wrong in both directions: a
# ``…`` delimiter pairs its two ticks with each other, leaving the span BODY
# exposed to the split, and one stray tick inverts the whole line so prose is
# masked and code is not. Both shapes reproduce #262 byte-for-byte — measured,
# not reasoned about. So a run of N backticks opens a span and only a run of
# exactly N closes it, which is how Markdown itself pairs them.
#
# AN UNPAIRED RUN QUARANTINES THE WHOLE FIELD, not merely the text after it.
# That looks like over-reach and is not: pairing left-to-right is a GUESS about
# which ticks the author meant as delimiters, and an unpaired run proves the
# guess wrong somewhere — but not where. In `The flag is `--strict and the guard
# is `code=0; cmd || code=$?` in run.sh.` greedy pairing binds tick 1 to tick 2
# and calls tick 3 the stray; the author bound 2 to 3 and typo'd tick 1. The two
# readings disagree about text BEFORE the unpaired run, so a prefix-only
# quarantine still splits inside what the author wrote as code and still
# certifies the head. Everything or nothing is the only sound line, so the field
# is emitted as ONE claim tagged MALFORMED and dropped, wherever the stray tick
# sits. The cost is real — one typo drops every gotcha — and it is the right
# cost: the drop is named in the report and in `--lint`, while a fabricated
# invariant is silent by construction.
#
# Parity is deliberately NOT the truncation test. It was written that way first
# and removed: a cut landing between an even number of ticks, or in text
# carrying none at all, is invisible to it, so it certifies exactly the
# fragments it appears to guard — and on a merely stale claim it mis-names the
# reason, pointing the operator at the wrong sentence.
split_claims() {
    awk '
        function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
        function restore(s,   t, at, ph) {
            # index/substr, never sub(): span text is DATA, and a span holding
            # `\1` or `&` is ordinary shell prose that sub() would rewrite.
            for (t = 1; t <= nspan; t++) {
                ph = SOH t STX
                at = index(s, ph)
                if (at > 0) s = substr(s, 1, at - 1) span[t] substr(s, at + length(ph))
            }
            return s
        }
        function emit(tag, grp, s) { s = trim(restore(s)); if (s != "") print tag "\t" grp "\t" s }
        # A cut only starts a NEW group when it looks like a real sentence
        # start. Everything else stays welded to the fragment before it, so a
        # spurious cut can never let one half be certified while the other is
        # dropped — see the GROUP LINKAGE note above.
        # THE DEFAULT IS TO CONTINUE, NOT TO SPLIT. Deciding where a sentence
        # STARTS is the same guess as deciding where to cut, and it was wrong in
        # both directions: `Deploy only to U.S. East until #999 …` certified
        # `Deploy only to U.S.` — a complete, meaning-INVERTED sentence — while
        # a lowercase continuation welded two real sentences. Inverting the
        # default converts the first failure into the second: over-linking is
        # lossy, but it can never certify text the author did not write, which
        # is the same trade the whole-field quarantine already takes.
        #
        # A new group therefore requires POSITIVE evidence: the previous
        # fragment ends in a terminator AND the token before it is not
        # abbreviation-shaped. Abbreviation-shaped is deliberately generous —
        # a single letter (`Ask J.`), anything internally dotted (`U.S.`,
        # `e.g.`), or any token of four characters or fewer (`No.`, `Etc.`,
        # and yes `SHA.`, `push.`). Generous means MORE legitimate invariants
        # are welded to a dropped neighbour and lost with it. That cost is
        # accepted: a lost invariant is visible in the report, a fabricated one
        # is not. Do not narrow this to recover them.
        function abbrev_shaped(t) {
            if (t == "")             return 1     # nothing before the terminator
            if (t ~ /^[A-Za-z]$/)    return 1     # initial: "Ask J."
            if (t ~ /\./)            return 1     # internally dotted: "U.S.", "e.g."
            if (length(t) <= 4)      return 1     # "No.", "Etc.", "SHA.", "vs."
            if (tolower(t) == "approx") return 1  # longer, still an abbreviation
            return 0
        }
        function starts_new(prev,   t) {
            if (prev == "")          return 1     # first fragment of the field
            if (prev !~ /[.!?]$/)    return 0     # no terminator: mid-sentence cut
            t = prev
            sub(/[.!?]+$/, "", t)                 # drop the terminator
            sub(/^.*[ ]/, "", t)                  # keep the last token
            return abbrev_shaped(t) ? 0 : 1
        }
        BEGIN { SOH = sprintf("%c", 1); STX = sprintf("%c", 2) }
        {
            # The placeholder bytes are ours alone. Prose never carries them;
            # stripping first means a span can never contain one either, so a
            # crafted field cannot forge a placeholder.
            gsub(SOH, ""); gsub(STX, "")
            line = $0
            len = length(line)
            out = ""; nspan = 0; i = 1; unpaired = 0; prev = ""
            while (i <= len) {
                if (substr(line, i, 1) != "`") { out = out substr(line, i, 1); i++; continue }
                run = 0
                while (i + run <= len && substr(line, i + run, 1) == "`") run++
                endrun = 0                        # not `close`: that is an awk builtin
                j = i + run
                while (j <= len) {
                    if (substr(line, j, 1) != "`") { j++; continue }
                    q = 0
                    while (j + q <= len && substr(line, j + q, 1) == "`") q++
                    if (q == run) { endrun = j; break }
                    j += q
                }
                if (endrun == 0) { unpaired = 1; break }
                ticks = substr(line, i, run)
                nspan++
                span[nspan] = substr(line, i + run, endrun - (i + run))
                out = out ticks SOH nspan STX ticks
                i = endrun + run
            }
            if (unpaired) { nspan = 0; emit("UNPAIRED", 1, line); next }
            # `;` IS NOT A SENTENCE BOUNDARY. It joins clauses INSIDE one
            # sentence, and splitting there is what let a clause be dropped
            # while its neighbours were welded back together when the SAFE
            # block is rejoined: "Set FOO=1; the guard is disabled per #999, which
            # remains open. Always export it." dropped the middle clause on its
            # `#999` and emitted "Set FOO=1; Always export it." — grammatical,
            # confident, and the exact opposite of what the author wrote. That
            # is worse than #262, which at least emitted visibly broken text.
            # A claim is a SENTENCE; the citation is judged on all of it.
            # GROUP LINKAGE. Every rule above decides WHERE a cut lands; none
            # of them changes the fact that a cut clause can drop while its
            # neighbours are welded back together by the safe block. Three
            # rounds of narrowing the pairing guess each had a next input, so
            # the guess is no longer load-bearing: fragments are TAGGED with a
            # group, resolved individually, and committed together. If any
            # fragment of a group drops, none of that group is certified. A
            # mis-bind therefore degrades from a fabricated sentence into an
            # honest drop, which is the property the pairing heuristics were
            # only ever approximating.
            gsub(/[.!?] +/, "&\n", out)           # spaces trail the break; trim() takes them
            m = split(out, piece, "\n")
            g = 0
            for (k = 1; k <= m; k++) {
                cur = trim(restore(piece[k]))
                if (cur == "") continue
                if (g == 0)             g = 1
                else if (starts_new(prev)) g++
                print "OK\t" g "\t" cur
                prev = cur
            }
        }
    '
}

# `|| true` here would turn a splitter failure into an empty field and a clean
# exit 0 — a silent all-clear indistinguishable from a config with nothing to
# verify, which is the one report this tool must never produce.
if ! printf '%s\n' "$SUMMARY" | split_claims >"$CLAIMS"; then
    echo "gotcha-claims: the claim splitter failed on $SRC — nothing can be certified" >&2
    echo "--- BEGIN SAFE GOTCHAS ---"
    echo "--- END SAFE GOTCHAS ---"
    exit 3
fi

if [ ! -s "$CLAIMS" ]; then
    echo "gotcha-claims: gotcha_summary is empty in $SRC — nothing to verify" >&2
    echo "--- BEGIN SAFE GOTCHAS ---"
    echo "--- END SAFE GOTCHAS ---"
    exit 0
fi

# --- time-varying shapes -----------------------------------------------------
# Shapes, never truth: what the contract says may not live in this field. Used
# by --lint on a whole config, and again below to ANNOTATE a claim that is kept
# — an "as of <date>" or a roadmap status cites no `#N`, so nothing can resolve
# it, and passing it through unremarked is how it survives the next ten refreshes.
time_varying_kinds() {
    local claim="$1" lower kinds=""
    lower="$(printf '%s' "$claim" | tr '[:upper:]' '[:lower:]')"
    case "$claim" in *'#'[0-9]*) kinds="$kinds issue-ref" ;; esac
    case "$lower" in
        *remain*|*"still open"*|*"not finished"*|*unfinished*|*outstanding*|*"not yet"*|*shipped*|*landed*|*"is closed"*|*"already done"*)
            kinds="$kinds state-verb" ;;
    esac
    case "$lower" in
        *"as of "*) kinds="$kinds dated" ;;
        *20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) kinds="$kinds dated" ;;
    esac
    case "$lower" in
        *roadmap*|*milestone*|*"next up"*|*"planned for"*|*"coming in"*|*"will ship"*)
            kinds="$kinds roadmap" ;;
    esac
    printf '%s\n' "$(printf '%s' "$kinds" | sed -E 's/^ //; s/ /,/g')"
}

# --- lint mode: shapes, offline ---------------------------------------------
if [ "$LINT" -eq 1 ]; then
    findings=0
    malformed=0
    # Group the fragments back into sentences first. Reporting a FRAGMENT as
    # the author's time-varying claim shows them text they never wrote — the
    # same fabrication this file exists to prevent, in the offline half.
    LINT_GROUPED="$WORK/lint-grouped"
    awk -F'\t' '
        { if (NR > 1 && $2 != prev) printf "\n"
          if (NR == 1 || $2 != prev) { printf "%s\t%s", $1, $3; prev = $2 }
          else printf " %s", $3 }
        END { if (NR > 0) printf "\n" }
    ' "$CLAIMS" >"$LINT_GROUPED"
    while IFS="$(printf '\t')" read -r tag claim; do
        # An unpaired backtick run is reported HERE too, not only at injection:
        # lint is what a refresh runs to find configs that will misbehave, and a
        # field that lints clean while losing a claim at injection teaches the
        # operator the wrong thing about their config.
        if [ "$tag" != "OK" ]; then
            findings=$((findings + 1))
            malformed=$((malformed + 1))
            case "$tag" in
                UNPAIRED) printf 'MALFORMED unpaired-backtick-run · "%s"\n' "$claim" ;;
                *)        printf 'MALFORMED unrecognised-splitter-tag(%s) · "%s"\n' "$tag" "$claim" ;;
            esac
            continue
        fi
        kinds="$(time_varying_kinds "$claim")"
        if [ -n "$kinds" ]; then
            findings=$((findings + 1))
            printf 'TIME-VARYING %s · "%s"\n' "$kinds" "$claim"
        fi
    done <"$LINT_GROUPED"
    if [ "$findings" -eq 0 ]; then
        echo "gotcha-claims lint: $SRC — no time-varying claims"
        exit 0
    fi
    if [ "$malformed" -gt 0 ]; then
        echo "gotcha-claims lint: $SRC — $findings finding(s), $malformed from an unpaired backtick run; gotcha_summary carries invariants only (config-contract.md)"
    else
        echo "gotcha-claims lint: $SRC — $findings time-varying claim(s); gotcha_summary carries invariants only (config-contract.md)"
    fi
    exit 3
fi

# --- resolve the repo --------------------------------------------------------
# An undetermined repo is not a skip: it makes every citing claim unresolvable,
# and unresolvable is dropped.
if [ -z "$REPO_SLUG" ] && command -v gh >/dev/null 2>&1; then
    REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

# --- resolve one issue, cached ----------------------------------------------
resolve_issue() {
    local n="$1" cached raw state
    cached="$(awk -F'\t' -v n="$n" '$1 == n { print $2; exit }' "$CACHE")"
    if [ -n "$cached" ]; then
        printf '%s\n' "$cached"
        return 0
    fi
    state="UNRESOLVED"
    if [ -n "$REPO_SLUG" ] && command -v gh >/dev/null 2>&1; then
        if raw="$(gh issue view "$n" --repo "$REPO_SLUG" --json state --jq .state 2>/dev/null)"; then
            raw="$(printf '%s' "$raw" | tr -d '[:space:]"' | tr '[:lower:]' '[:upper:]')"
            case "$raw" in
                OPEN|CLOSED) state="$raw" ;;
            esac
        fi
    fi
    printf '%s\t%s\n' "$n" "$state" >>"$CACHE"
    printf '%s\n' "$state"
}

# --- what state does the claim assert? --------------------------------------
# Both classes matching, or neither, is UNKNOWN — and unknown is held.
asserted_state() {
    local text open=0 closed=0
    text="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$text" in
        *remain*|*"still open"*|*"still needs"*|*"still not"*|*"not finished"*|*unfinished*|*outstanding*|*pending*|*"not yet"*|*"is open"*|*"are open"*|*"stays open"*|*"blocked on"*|*"waiting on"*|*"in flight"*|*"to do"*|*todo*)
            open=1 ;;
    esac
    case "$text" in
        *closed*|*shipped*|*landed*|*merged*|*"is fixed"*|*"was fixed"*|*resolved*|*"is done"*|*"already done"*|*"is complete"*|*"is finished"*)
            closed=1 ;;
    esac
    if [ "$open" -eq 1 ] && [ "$closed" -eq 1 ]; then
        printf 'unknown\n'
    elif [ "$open" -eq 1 ]; then
        printf 'open\n'
    elif [ "$closed" -eq 1 ]; then
        printf 'closed\n'
    else
        printf 'unknown\n'
    fi
}

# A report line embeds claim text, and the report is printed ABOVE the safe
# block. Every report line is prefixed (`KEEP …`/`DROP …`) so it can never
# equal a marker line, but a consumer matching the marker as a SUBSTRING would
# still be fooled — so marker text is neutralised on its way into the report.
# Dropping a claim from a report while the body still carries it protects
# nobody; neither does a report that can forge the body's fences.
for_report() {
    printf '%s' "$1" | sed -e 's/--- BEGIN SAFE GOTCHAS ---/--- BEGIN SAFE GOTCHAS (quoted) ---/g' \
                           -e 's/--- END SAFE GOTCHAS ---/--- END SAFE GOTCHAS (quoted) ---/g'
}

kept=0
dropped=0
total=0
KEPT_FILE="$WORK/kept"
: >"$KEPT_FILE"
REPORT="$WORK/report"
: >"$REPORT"

FRAGS="$WORK/frags"
: >"$FRAGS"

# PASS 1 — resolve each fragment on its own. Nothing is committed here: a
# verdict is recorded against the fragment's GROUP, and the group is what is
# kept or dropped in pass 2.
while IFS="$(printf '\t')" read -r tag grp claim; do
    # Anything that is not an explicit OK is dropped. The splitter emits only
    # these two tags today, so the `*)` arm is unreachable — and it is the
    # right unreachable arm: a fail-OPEN default here would silently certify a
    # tag a later change introduced.
    if [ "$tag" != "OK" ]; then
        case "$tag" in
            UNPAIRED) why="an unpaired backtick run makes the whole field unparseable" ;;
            *)        why="unrecognised splitter tag '$tag'" ;;
        esac
        printf '%s\t%s\t%s\t%s\n' "$grp" "drop" "malformed      $why" "$claim" >>"$FRAGS"
        continue
    fi
    # A `#N` inside a code span is still extracted, deliberately: the masked
    # line is right there and excluding span text would be a two-line change,
    # but `Reproduce with `gh issue view #999`` then resolves nothing and passes
    # unverified. Fail-closed keeps the drop; recorded so it is not "fixed".
    refs="$(printf '%s\n' "$claim" | grep -oE '#[0-9]+' | tr -d '#' | sort -un || true)"
    if [ -z "$refs" ]; then
        kinds="$(time_varying_kinds "$claim")"
        if [ -n "$kinds" ]; then
            printf '%s\t%s\t%s\t%s\n' "$grp" "keep" "time-varying:$kinds" "$claim" >>"$FRAGS"
        else
            printf '%s\t%s\t%s\t%s\n' "$grp" "keep" "invariant" "$claim" >>"$FRAGS"
        fi
        continue
    fi

    assert="$(asserted_state "$claim")"
    verdict="keep"
    reason=""
    for n in $refs; do
        state="$(resolve_issue "$n")"
        if [ "$state" = "UNRESOLVED" ]; then
            verdict="drop"
            if [ -n "$REPO_SLUG" ]; then
                reason="unresolvable   #${n} could not be resolved"
            else
                reason="unresolvable   #${n} could not be resolved (no repo determined)"
            fi
            break
        fi
        if [ "$assert" = "unknown" ]; then
            verdict="drop"
            reason="unverifiable   #${n} is cited with no checkable state assertion"
            break
        fi
        expected="OPEN"
        [ "$assert" = "closed" ] && expected="CLOSED"
        if [ "$state" != "$expected" ]; then
            verdict="drop"
            reason="contradicted   #${n} is ${state}, the claim asserts ${assert}"
            break
        fi
    done

    if [ "$verdict" = "drop" ]; then
        printf '%s\t%s\t%s\t%s\n' "$grp" "drop" "$reason" "$claim" >>"$FRAGS"
    else
        printf '%s\t%s\t%s\t%s\n' "$grp" "keep" "confirmed" "$claim" >>"$FRAGS"
    fi
done <"$CLAIMS"

# PASS 2 — commit per GROUP. A group is the sentence a fragment came from, so
# if any fragment of it dropped, none of it is certified: that is what stops a
# spurious cut certifying one half of a sentence while the other half carries
# the citation that killed it. The report names the group once, with the text
# it would have emitted, so a reader sees the whole sentence that went.
DROPPED_GROUPS="$WORK/dropped-groups"
awk -F'\t' '$2 == "drop" { print $1 }' "$FRAGS" | sort -u >"$DROPPED_GROUPS"

group_is_dropped() {
    awk -v g="$1" '$0 == g { found = 1 } END { exit found ? 0 : 1 }' "$DROPPED_GROUPS"
}

for grp in $(awk -F'\t' '{ print $1 }' "$FRAGS" | awk '!seen[$0]++'); do
    total=$((total + 1))
    joined="$(awk -F'\t' -v g="$grp" '$1 == g { printf "%s%s", sep, $4; sep = " " }' "$FRAGS")"
    if group_is_dropped "$grp"; then
        dropped=$((dropped + 1))
        reason="$(awk -F'\t' -v g="$grp" '$1 == g && $2 == "drop" { print $3; exit }' "$FRAGS")"
        printf 'DROP  %s · "%s"\n' "$reason" "$(for_report "$joined")" >>"$REPORT"
        continue
    fi
    kept=$((kept + 1))
    printf '%s\n' "$joined" >>"$KEPT_FILE"
    while IFS="$(printf '\t')" read -r fgrp _fv label fclaim; do
        [ "$fgrp" = "$grp" ] || continue
        case "$label" in
            time-varying:*)
                printf 'KEEP  time-varying  %s (%s — nothing here can resolve it; the contract says invariants only)\n' \
                    "$fclaim" "${label#time-varying:}" >>"$REPORT" ;;
            confirmed)
                printf 'KEEP  confirmed     %s (state true right now; an issue-state claim rots — prefer an invariant)\n' \
                    "$fclaim" >>"$REPORT" ;;
            *)
                printf 'KEEP  invariant     %s\n' "$fclaim" >>"$REPORT" ;;
        esac
    done <"$FRAGS"
done

printf 'gotcha-claims: repo=%s claims=%d kept=%d dropped=%d\n' "${REPO_SLUG:-unknown}" "$total" "$kept" "$dropped"
cat "$REPORT"
echo "--- BEGIN SAFE GOTCHAS ---"
if [ -s "$KEPT_FILE" ]; then
    tr '\n' ' ' <"$KEPT_FILE" | sed -E 's/ +$//'
    echo
fi
echo "--- END SAFE GOTCHAS ---"

if [ "$dropped" -gt 0 ]; then
    exit 3
fi
exit 0
