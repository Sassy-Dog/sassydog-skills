#!/usr/bin/env bash
# test-queue-snapshot-site.sh — queue-snapshot.sh's `site:` parse: it fires on
# the contract, and it fires on NOTHING ELSE (issue #340, epic #322).
#
# What #340 added. `queue-snapshot.sh` already parsed two machine-readable body
# contracts — `touches:` and literal `Depends on #N` — plus `stack:`. #340 adds
# a third of the same shape: one line, one free-form token, absent meaning "any
# site". It is deliberately SUBSTRATE ONLY. Nothing filters, refuses or reports
# differently because of it; the consuming children (#341 dispatch filter, #343
# grooming surface) are what make it act.
#
# Why a substrate change still needs a gate, and why BOTH directions. A parse
# that only ever has to prove "it fires" passes just as well when it fires on
# everything, and a field nothing consumes yet is a field nobody will notice is
# wrong. By the time #341 reads it, a false `site` is an issue the loop refuses
# to dispatch with a reason that names a workstation nobody asked about — and
# the answer to "why did my issue stop moving" is three files away. So every
# row here comes in a pair: the shape that MUST parse, and the shape that must
# NOT, with the no-`site:` body pinned field-for-field against what it emitted
# before this change.
#
# The false-positive half is not hypothetical, which is why the mask exists at
# all. Both issues that introduced this contract — #322 and #340 — carry a
# fenced example holding a `site: vdi` line, and neither issue is site-held. A
# fence-blind parse therefore marks the substrate issues THEMSELVES as VDI-only
# on the very first tick after the feature lands, which is as close to a
# self-refuting default as this contract can get. Lines inside a fenced block
# or an HTML comment are not read as declarations.
#
# THE ASYMMETRY IS DELIBERATE AND IS PINNED HERE (row 7). The mask applies to
# `site:` alone. `touches:` inside a fence is still parsed, exactly as it was
# before #340, because narrowing it is a BEHAVIOUR change for every consumer
# already reading it — a body whose only `touches:` sits in a fence would flip
# to `unannotated`, and dispatch-ready's collision filter reads that. #340 is
# substrate only, so the older contracts keep the parse they shipped with. A
# later "make the parser consistent" sweep is exactly what this row stops; if
# it fails, read this paragraph before deleting it.
#
# Indentation is also NOT a code block (row 7). The regex's leading-whitespace
# tolerance is what lets the contract sit as a continuation line under a list
# item, and a 4-space rule would take that away — a scope decision, recorded so
# the omission is not read as an oversight.
#
# THE MUTATION PROOFS. Three, each neutering ONE decision, each proved applied
# (the mutant must differ from the source), proved to RUN (a mutant that dies
# proves nothing), and proved by the row it reddens:
#   M1  the extraction itself       -> the plain `site: vdi` row goes dark
#   M2  the fence/comment mask      -> the fenced-example row starts declaring
#   M3  the case fold               -> `Site: VDI` stops matching `vdi`
# Without M2 in particular a reviewer cannot tell the mask from decoration.
#
# Network-free: a PATH-shimmed mock `gh` serving recorded `gh issue list`
# payloads per label, plus `gh api user`. REPO= suppresses the repo lookup, so
# a machine with a real authenticated gh behaves exactly like CI. queue-snapshot
# swallows a failed list into `[]`, which would make several must-NOT-parse rows
# vacuous, so every scenario asserts its bucket sizes before reading a field.
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
# `gh issue list … --label <bucket>` per bucket. Anything else is a contract
# breach and exits non-zero, which queue-snapshot turns into an empty bucket —
# caught by the size assertions rather than passed over.
cat >"$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    api)
        [ "${2:-}" = "user" ] || { echo "mock gh: unhandled api call: $*" >&2; exit 1; }
        echo "mock-login"
        ;;
    issue)
        [ "${2:-}" = "list" ] || { echo "mock gh: unhandled issue call: $*" >&2; exit 1; }
        label=""
        while [ "$#" -gt 0 ]; do
            [ "$1" = "--label" ] && { label="$2"; break; }
            shift
        done
        f="$SCENARIO_DIR/$label.json"
        [ -f "$f" ] || { echo "mock gh: no payload for label '$label'" >&2; exit 1; }
        cat "$f"
        ;;
    *) echo "mock gh: unhandled invocation: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$BIN/gh"

# --- recorded issue bodies ----------------------------------------------------
# Written by python3 rather than by hand: every interesting body here is
# multi-line, and hand-escaping newlines into JSON is precisely how a fixture
# ends up testing a shape nobody meant to write.
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

FENCE = "`" * 3

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
          "Contract:\n\n%s text\nsite: vdi\n%s\n\nMore prose.\n" % (FENCE, FENCE), ["ready"]),
    # 107 — a fenced example AND a real declaration; the real one wins.
    issue(107, "fenced then real",
          "%s text\nsite: vdi\n%s\n\nsite: mac\n" % (FENCE, FENCE), ["ready"]),
    # 108 — inside a multi-line HTML comment.
    issue(108, "html comment", "<!--\nsite: vdi\n-->\n", ["ready"]),
    # 109 — backticks tolerated in the value, as in `touches:`.
    issue(109, "backticked", "site: `vdi`\n", ["ready"]),
    # 110 — one token is the contract; the rest of the line is a remark.
    issue(110, "extra tokens", "site: vdi (corp laptop)\n", ["ready"]),
    # 111 — indentation is NOT a code block: a continuation line under a list
    # item still declares.
    issue(111, "indented", "- notes:\n  site: vdi\n", ["ready"]),
    # 112 — the asymmetry: in ONE body, a fenced `touches:` is still parsed
    # (pre-#340 behaviour, untouched) while the fenced `site:` is not.
    issue(112, "asymmetry",
          "Example:\n\n%s text\ntouches: fenced/only.md\nsite: vdi\n%s\n" % (FENCE, FENCE), ["ready"]),
    # 113 — tilde fences count too.
    issue(113, "tilde fence", "~~~\nsite: vdi\n~~~\n", ["ready"]),
    # 114 — a site line beside the older contracts: no cross-talk in either
    # direction.
    issue(114, "coexists", "touches: x/y\nstack: #1 #2\nsite: vdi\nDepends on #9\n", ["ready"]),
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

# --- runner -------------------------------------------------------------------
OUT="$WORK/out.json"
STATUS=0
run_snapshot() { # <script-path>
    PATH="$BIN:$PATH" SCENARIO_DIR="$FX" REPO=mock-org/mock-repo \
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
# Every must-NOT-parse row below reads a field out of a bucket. queue-snapshot
# turns a failed `gh issue list` into `[]`, and `null` out of an empty array
# looks exactly like a correct "no site declared" — so the sizes come first.
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
if [ "$n_ready" = "14" ] && [ "$n_flight" = "2" ] && [ "$n_blocked" = "2" ]; then
    ok "buckets are populated (ready=14 in_flight=2 blocked=2) — no row below is vacuous"
else
    bad "bucket sizes ready=$n_ready in_flight=$n_flight blocked=$n_blocked, expected 14/2/2"
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
echo "4. leading whitespace, a tab after the colon, mixed case" >&2
expect_site "'   Site:<TAB>VDI  ' parses, case-folded" ready 103 vdi

# --- 5. ambiguity resolves the way the header says ----------------------------
echo "5. multiple and malformed declarations resolve deterministically" >&2
expect_site "two declarations: the FIRST wins" ready 104 vdi
expect_site "a valueless 'site:' declares nothing; the scan continues" ready 105 mac
expect_site "backticks are tolerated in the value" ready 109 vdi
expect_site "only the first token is the site; the rest is a remark" ready 110 vdi

# --- 6. the false-positive half -----------------------------------------------
# The measured one: #322 and #340 both carry a fenced 'site: vdi'.
echo "6. examples are not declarations" >&2
expect_site "a fenced example alone gives null (the #322/#340 body shape)" ready 106 null
expect_site "a fenced example plus a real line gives the real one" ready 107 mac
expect_site "an HTML comment gives null" ready 108 null
expect_site "a tilde fence gives null" ready 113 null

# --- 7. the scope decisions ---------------------------------------------------
echo "7. what is deliberately NOT masked" >&2
expect_site "indentation is not a code block — a list continuation declares" ready 111 vdi
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

# --- 8. mutation proofs -------------------------------------------------------
# Each mutant neuters ONE decision. The exact-string replace is asserted to have
# applied (a drifted target reports "did not match", never a silent pass), the
# mutant is asserted to RUN, and only then is its row read.
echo "8. mutation proofs" >&2
MUT="$WORK/mutant.sh"
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
    if [ "$STATUS" != "0" ] || ! jq -e '.ready | length == 14' "$OUT" >/dev/null 2>&1; then
        bad "$1 — the mutant did not run (exit $STATUS), so its verdict proves nothing"
        return 1
    fi
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
    '                    site = token[0].lower()' \
    '                    pass'; then
    reddens "M1: dropping the extraction darkens the plain 'site: vdi' row" ready 101 vdi
fi

if mutate "M2 mask" \
    '        if site is None and not masked:' \
    '        if site is None:'; then
    reddens "M2: dropping the fence/comment mask makes the fenced example declare" ready 106 null
fi

if mutate "M3 case fold" \
    '                    site = token[0].lower()' \
    '                    site = token[0]'; then
    reddens "M3: dropping the case fold breaks 'Site: VDI'" ready 103 vdi
fi

# Restore the un-mutated snapshot for anything reading $OUT after this point.
run_snapshot "$SNAP"

# --- 9. the header states the resolution ---------------------------------------
# #340's acceptance requires the multiple/malformed choice to be stated in the
# script header, because a deterministic answer is only useful to a reader who
# can find out what it is. Matched against a WHITESPACE-FLATTENED copy: this
# repo hard-wraps its comment prose, and a line-scoped grep turns a re-wrap into
# a false FAIL. The leading `#` is stripped BEFORE the join — the same
# normalisation test-doc-reconciliation.sh applies to blockquote markers, and
# for the same reason: without it a wrapped sentence flattens to "... read as a
# # declaration" and every needle spanning a wrap silently fails.
echo "9. the header documents the resolution" >&2
FLAT="$WORK/snap.flat"
sed -e 's/^[[:space:]]*#[[:space:]]\{0,1\}//' -e 's/^[[:space:]]*//' "$SNAP" |
    tr '\n' ' ' | tr -s ' \t' ' ' >"$FLAT"
expect_flat() { # <label> <needle>
    if grep -qF -- "$2" "$FLAT"; then ok "$1"; else bad "$1 — missing from $SNAP: $2"; fi
}
expect_flat "the header names the contract as one line, one token" \
    'One line, one free-form'
expect_flat "  and that absent means any site" \
    'ABSENT MEANS "any site"'
expect_flat "  and that the first line carrying a token wins" \
    'The FIRST `site:` line carrying a token wins'
expect_flat "  and that only the first token is the site" \
    'Only the first whitespace-separated token is the site'
expect_flat "  and that case is folded, with the reason" \
    'Case is folded'
expect_flat "  and that a valueless line declares nothing" \
    'carrying no token at all is not a declaration'
expect_flat "  and that fenced/commented lines are not declarations" \
    'are not read as a declaration'
expect_flat "  and that indentation is deliberately NOT a code block" \
    'Indentation is deliberately NOT read as a code block'
expect_flat "  and that the mask is site-only, with the reason" \
    'applies to `site:` ALONE'

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "queue-snapshot site tests: all green ($asserts assertions)" >&2
    exit 0
fi
echo "queue-snapshot site tests: FAILURES above ($asserts assertions)" >&2
exit 1
