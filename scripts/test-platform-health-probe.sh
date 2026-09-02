#!/usr/bin/env bash
# test-platform-health-probe.sh — pr-shepherd's degradation probe returns FOUR
# distinct verdicts, and never gates anything (issue #285).
#
# WHY THIS EXISTS. The workflow skills could not distinguish "GitHub told me the
# truth" from "GitHub told me a DEGRADED truth". A hard `gh` error is handled
# everywhere; a call that exits 0 carrying incomplete data is read as live
# state. Measured 2026-08-26 on this repo's PR #283 during a platform outage:
# `gh pr view --json statusCheckRollup` exited 0 with two entries and no `ci`,
# no `CI` run existed for that head across ~40 minutes while two prior heads on
# the same branch each had one within minutes, and later `ci` appeared in the
# rollup with an EMPTY state and still no run behind it. Nothing errored; three
# hypotheses were produced and all three were wrong.
#
# WHAT MAKES IT WORTH A GATE. Every way of getting this wrong is silent, and
# they come in opposite pairs:
#
#   * Collapse a verdict toward `healthy` and the probe becomes WORSE than not
#     having one — it converts an unknown into a confident wrong answer, which
#     is this repo's dominant bug class. A green status page lags real
#     degradation by minutes to tens of minutes, so it can never be evidence of
#     health; an unreachable one certainly cannot.
#   * Let the verdict reach a DECISION and a platform outage starts changing
#     what the loop does, not just what it says. #285 is explicit that this is a
#     diagnostic: a PR missing a required check is held either way, and the hold
#     was already correct — the attribution was what was missing.
#   * Over-attribute, and the probe invents an EXCUSE for a real failure. That
#     is the same confident wrong answer pointed the other way, and it has its
#     own cases here (an irrelevant status component; an incident beside a clean
#     first-party read).
#
# THE FOUR VERDICTS ARE THE DESIGN. `healthy`, `degraded (attributed)`,
# `degraded (unattributed)` and `unknown` must stay four distinct answers, and
# both collapse directions are mutation-proved. Row 3 of the probe's table — a
# first-party anomaly beside an UNREADABLE status page — resolves to
# `degraded (unattributed)` rather than `unknown`, because the degradation was
# measured first-party and only the attribution is missing. That is deliberate
# and is pinned, alongside rows 6/8/9 which pin the other half of the same rule:
# an unreachable endpoint never manufactures a `healthy` and never manufactures
# a `degraded` on its own. Read those assertions together before "aligning"
# either one. EVERY row of the nine-row table has at least one case.
#
# THE TWO DOORS INTO `healthy`, BOTH GUARDED. The status-page door is the
# obvious one. The FIRST-PARTY door is the one an earlier edition left open: a
# single-commit PR branch has no prior head, so the run comparison had no
# baseline, found nothing, and reported `clean` -> `healthy` on a branch whose
# CI had never started — #285 one step earlier, on the dominant branch shape in
# this org. `clean` now requires that at least one first-party check actually
# RAN, and both the case and its mutation are here.
#
# FOUR SCOPING DECISIONS, each measured rather than assumed:
#
#   1. NEVER-A-GATE IS ASSERTED STRUCTURALLY, TWICE, because prose alone cannot
#      hold it. (a) Every verdict exits 0, so no `set -e`/`&&`/`if` can turn one
#      into a gate — the deliberate asymmetry with stack-probe.sh, whose exit
#      codes ARE a gate because gating is its job. (b) No sibling pr-shepherd
#      script and no OTHER skill names the probe at all, over a sibling list held
#      as an EQUALITY against `git ls-files`, so a new script cannot ship
#      unscanned. Both are mutation-proved, (b) by wiring the probe into
#      merge-shepherd.sh.
#   2. THE SKILL.md CHECK IS SECTION-SCOPED, not file-scoped. A whole-file grep
#      for the probe's name is satisfied by its own §2b and by the bundled-script
#      table, so it would report a probe wired into the MERGE section as clean.
#      The decision sections (§1, §1b, §3) are asserted to not name it, and that
#      is mutation-proved by inserting a mention into §3.
#   3. THE RUN COMPARISON IS RUN-TO-RUN, NOT ROLLUP-TO-RUN. `statusCheckRollup`
#      names checks (for Actions, JOB names) and `actions/runs` names WORKFLOWS;
#      differencing the two namespaces reports a missing check for every workflow
#      whose job names differ from its own name, on a healthy repo. The healthy
#      fixture's rollup names deliberately match no workflow name, so a fixture
#      where they lined up would make that case vacuous. The probe's derivation
#      jq is no longer even HANDED the rollup, which is the structural half.
#   4. THE BASELINE IS AN INTERSECTION AND THE EVENTS ARE WHITELISTED, both to
#      stop ordinary absence reading as degradation: a `paths:` filter, an `if:`,
#      a renamed workflow, or a one-off `workflow_dispatch` on a prior head. Each
#      has a case and a mutation, because the union reading and the
#      no-whitelist reading are both what a later simplification produces.
#
# THE AGE FLOOR IS CONTRACT, not an optimisation, and its SCOPE is contract too.
# A workflow that has not started yet is not missing, so the run-comparison
# signals are age-suppressed. The empty-state signal is NOT: it is a direct read
# of the rollup, and it is also the one signal that must survive the
# `actions/runs` call failing, since an outage degrades both calls together.
# Both halves have cases; suppressing the empty-state signal is mutated.
#
# A gh TRANSPORT FAILURE IS `not_measured`, NEVER AN ANOMALY, and that is a
# deliberate reading of #285 rather than a slip — see the probe's header. An
# expired token, a rate limit or a closed laptop is not platform degradation,
# and reporting one as such is the confident wrong answer this file exists to
# refuse. Cased and mutated in both directions.
#
# NO `| grep -q` PIPELINE ANYWHERE (gate 30's rule, issue #256): `grep -q`
# closes the pipe on its first match and `pipefail` promotes the writer's
# SIGPIPE 141, which reports a caught mutation as a miss. An earlier edition of
# THIS FILE shipped exactly that shape in `section_names_probe`, where it fails
# OPEN — the must-NOT-name assertions, the entire point of the file, would have
# read a SIGPIPE as "does not name it". Every check here captures first and then
# matches against a herestring or a file operand.
#
# Network-free: PATH-shimmed mock `gh` AND mock `curl`, both serving recorded
# payloads from a scenario directory and recording every invocation, so the
# read-only claim is measured rather than asserted, by METHOD and not merely by
# path prefix. `--repo` is always passed, which suppresses the probe's only
# other gh use (the cwd repo lookup) — so a machine with a real authenticated gh
# behaves exactly like CI — and every env knob the probe reads is pinned, so an
# operator's ambient PLATFORM_* setting cannot change what this measures.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-platform-health-probe.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-platform-health-probe: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPTS_DIR="$REPO_ROOT/skills/pr-shepherd/scripts"
PROBE="$SCRIPTS_DIR/probe-platform-health.sh"
SKILL="$REPO_ROOT/skills/pr-shepherd/SKILL.md"
PROBE_BASENAME="probe-platform-health.sh"

[ -f "$PROBE" ] || { echo "test-platform-health-probe: $PROBE not found" >&2; exit 1; }
[ -f "$SKILL" ] || { echo "test-platform-health-probe: $SKILL not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-platform-health-probe: jq is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

fail=0
asserts=0
ok() { asserts=$((asserts + 1)); echo "  ok    $1" >&2; }
bad() { asserts=$((asserts + 1)); fail=1; echo "  FAIL  $1" >&2; }

echo "platform-health-probe tests (work: $WORK)" >&2

# --- the mocks ----------------------------------------------------------------
cat >"$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$MOCK_CALLS"
case "${1:-}" in
    pr)
        if [ "${2:-}" != "view" ]; then
            echo "mock gh: unhandled pr subcommand: $*" >&2; exit 1
        fi
        if [ -f "$SCENARIO_DIR/pr.fail" ]; then exit 4; fi
        cat "$SCENARIO_DIR/pr.json"
        ;;
    api)
        case "${2:-}" in
            repos/*/commits/*)
                if [ -f "$SCENARIO_DIR/commit.fail" ]; then exit 5; fi
                cat "$SCENARIO_DIR/commit.json" ;;
            *actions/runs*)
                if [ -f "$SCENARIO_DIR/runs.fail" ]; then exit 6; fi
                cat "$SCENARIO_DIR/runs.json" ;;
            *) echo "mock gh: unhandled api path: $*" >&2; exit 1 ;;
        esac
        ;;
    *) echo "mock gh: unhandled invocation: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$BIN/gh"

cat >"$BIN/curl" <<'MOCK'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$MOCK_CALLS"
if [ -f "$SCENARIO_DIR/status.unreachable" ]; then exit 7; fi
cat "$SCENARIO_DIR/status.json"
MOCK
chmod +x "$BIN/curl"

# --- recorded payloads --------------------------------------------------------
# The outage shape from #285: the rollup carries an empty-state `ci`, the head
# has one unrelated run, and BOTH prior heads carried `CI`.
PR_ANOMALY='{"number":283,"headRefOid":"5a8f58b","headRefName":"feat/probe",
  "mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"CheckRun","name":"CodeQL","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"CheckRun","name":"ci","status":"","conclusion":"","state":""}]}'
RUNS_ANOMALY='{"workflow_runs":[
  {"name":"CodeQL","event":"pull_request","head_sha":"5a8f58b"},
  {"name":"CI","event":"pull_request","head_sha":"6255349"},
  {"name":"CodeQL","event":"pull_request","head_sha":"6255349"},
  {"name":"CI","event":"pull_request","head_sha":"8c44c7f"},
  {"name":"CodeQL","event":"pull_request","head_sha":"8c44c7f"}]}'

# The healthy shape. Its rollup names are JOB names that deliberately match no
# workflow name — that mismatch is what makes the cross-namespace question
# answerable, and a fixture whose names lined up would make it vacuous. It also
# carries a StatusContext (Vercel-style: `context`/`state`, and NO
# `status`/`conclusion`), which is the only fixture that can tell the
# empty-state predicate's `.state` conjunct from a healthy external check.
PR_CLEAN='{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean",
  "mergeStateStatus":"CLEAN",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"CheckRun","name":"build (ubuntu-latest)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"StatusContext","context":"vercel","state":"SUCCESS"}]}'
RUNS_CLEAN='{"workflow_runs":[
  {"name":"CI","event":"pull_request","head_sha":"aa11bb2"},
  {"name":"CodeQL","event":"pull_request","head_sha":"aa11bb2"},
  {"name":"CI","event":"pull_request","head_sha":"9900aab"},
  {"name":"CodeQL","event":"pull_request","head_sha":"9900aab"}]}'

# #285's OWN rollup shape: entries present, all well-formed, and `ci` simply
# ABSENT. Nothing here is malformed, so the empty-state check finds nothing —
# which is the point: it cannot see an absent check, so it must not be able to
# earn `clean` by itself.
PR_ABSENT_CHECK='{"number":501,"headRefOid":"ee55ff6","headRefName":"feat/absent",
  "mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"CheckRun","name":"CodeQL","status":"COMPLETED","conclusion":"SUCCESS"}]}'

# No runs at all on the branch, so there is no prior head to compare against.
# Paired with a POPULATED rollup in case 8, because an empty one would let that
# case pass for the wrong reason.
RUNS_EMPTY='{"workflow_runs":[]}'

# Prior heads ran CI; the current head has NO run at all — #285's headline shape.
RUNS_NO_HEAD='{"workflow_runs":[
  {"name":"CI","event":"pull_request","head_sha":"9900aab"},
  {"name":"CI","event":"pull_request","head_sha":"7711ccd"}]}'

# Same head as PR_CLEAN but an EMPTY rollup, so the rollup check cannot run and
# the age floor alone decides. With PR_CLEAN's populated rollup the empty-state
# check runs, earns `clean` on its own, and the age case would measure nothing —
# which is exactly how a first draft of that case passed while proving nothing.
PR_EMPTY_ROLLUP='{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean",
  "mergeStateStatus":"BLOCKED","statusCheckRollup":[]}'

# Two prior heads with DISJOINT workflow sets, and no run on the current head.
# The intersection is empty, so nothing was ever required of this head and its
# having no run is ordinary — the guard that applies to missing_workflow_run has
# to apply to no_run_for_head too, or the "under-detects rather than
# over-detects" claim in the probe's header is false for half the signals.
RUNS_DISJOINT='{"workflow_runs":[
  {"name":"CI","event":"pull_request","head_sha":"9900aab"},
  {"name":"Docs","event":"pull_request","head_sha":"7711ccd"}]}'

# "Docs" ran on ONE prior head only, so it is not required of the current head.
# The union reading calls that degradation; the intersection reading does not.
RUNS_PARTIAL='{"workflow_runs":[
  {"name":"CI","event":"pull_request","head_sha":"aa11bb2"},
  {"name":"CI","event":"pull_request","head_sha":"9900aab"},
  {"name":"Docs","event":"pull_request","head_sha":"9900aab"},
  {"name":"CI","event":"pull_request","head_sha":"7711ccd"}]}'

# A one-off manual run on the only prior head. It can never recur on this head,
# so a no-whitelist reading reports it missing forever.
RUNS_DISPATCH='{"workflow_runs":[
  {"name":"CI","event":"pull_request","head_sha":"aa11bb2"},
  {"name":"CI","event":"pull_request","head_sha":"9900aab"},
  {"name":"Release","event":"workflow_dispatch","head_sha":"9900aab"}]}'

# An empty-state entry whose `name` is the EMPTY STRING, and one whose
# `context` is. jq's `//` falls back only on null/false, so both used to
# survive the generator as "" and then vanish at the shell guard - found,
# emitted, silently discarded, verdict `healthy`. Head and runs are
# PR_CLEAN's, so the run comparison resolves clean and the empty-state entry
# is the ONLY signal in play; without that pairing the case could pass for
# the wrong reason.
PR_EMPTY_NAME='{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean",
  "mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"CheckRun","name":"","status":"","conclusion":"","state":""}]}'
PR_EMPTY_CONTEXT='{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean",
  "mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"Analyze (actions)","status":"COMPLETED","conclusion":"SUCCESS"},
    {"__typename":"StatusContext","context":"","state":""}]}'

# The two conjuncts M15 never reached. A check still RUNNING (status
# IN_PROGRESS, conclusion null) is the most common PR state in this org, so a
# regression dropping the `.status` conjunct fabricates `degraded` on every PR
# with CI mid-flight; the second entry is the mirror for `.conclusion`.
# NEITHER matches the shipped predicate, so the unmutated run is healthy and
# each mutant has somewhere to move.
PR_MIDFLIGHT='{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean",
  "mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[
    {"__typename":"CheckRun","name":"CI / build","status":"IN_PROGRESS","conclusion":null},
    {"__typename":"CheckRun","name":"CI / lint","status":"","conclusion":"SUCCESS"}]}'

# A FULL page (100 runs) is what the probe reads as truncated. Its comparison
# is RUNS_CLEAN's and resolves clean, so the only difference between this
# fixture and RUNS_CLEAN is that the page is full - which is the whole point:
# same underlying reality, and before the fix the pair gave `healthy` and
# `degraded`. The padding repeats a workflow already on a prior head, so it
# adds no name to any set and cannot change the intersection.
RUNS_TRUNCATED_FULL="$(jq -cn '{workflow_runs:
  ([{name:"CI",event:"pull_request",head_sha:"aa11bb2"},
    {name:"CodeQL",event:"pull_request",head_sha:"aa11bb2"},
    {name:"CI",event:"pull_request",head_sha:"9900aab"},
    {name:"CodeQL",event:"pull_request",head_sha:"9900aab"}]
   + [range(96) | {name:"CI",event:"pull_request",head_sha:"9900aab"}])}')"

# Hostile first-party text. A fork-PR author controls BOTH the branch name and
# the job name, and both reach reported fields. Built with jq rather than typed
# so the bytes are unambiguous. Every other fixture in this file is clean
# ASCII, which is exactly why all six sanitisers were removable with the gate
# green before this existed.
BIDI_RLO="$(jq -rn '"\u202e"')"
BIDI_LRM="$(jq -rn '"\u200e"')"
# U+E0041, in the Unicode TAG BLOCK — non-BMP, so it is written as a surrogate
# pair. This is the character a regex class could not express at all, which is
# why the shared class is codepoint arithmetic; without it in the fixture the
# tag-block mutant has nothing to leak and its proof is vacuous.
TAG_CHR="$(jq -rn '"\udb40\udc41"')"
PR_HOSTILE="$(jq -cn --arg rlo "$BIDI_RLO" --arg lrm "$BIDI_LRM" --arg tag "$TAG_CHR" '{
  number:301, headRefOid:"aa11bb2",
  headRefName:("feat/x" + $rlo + "y" + $lrm + "z"),
  mergeStateStatus:"BLOCKED",
  statusCheckRollup:[
    {__typename:"CheckRun", name:"Analyze (actions)", status:"COMPLETED", conclusion:"SUCCESS"},
    {__typename:"CheckRun", name:("CI" + $rlo + "job" + $lrm + "k" + $tag + "z"),
     status:"", conclusion:"", state:""}]}')"

STATUS_GREEN='{"status":{"indicator":"none","description":"All Systems Operational"},
  "components":[{"name":"Actions","status":"operational"},
                {"name":"API Requests","status":"operational"},
                {"name":"Copilot","status":"operational"}],
  "incidents":[]}'
STATUS_INCIDENT='{"status":{"indicator":"major","description":"Partial System Outage"},
  "components":[{"name":"Actions","status":"partial_outage"},
                {"name":"API Requests","status":"operational"}],
  "incidents":[{"name":"Incident with Actions","status":"investigating",
                "components":[{"name":"Actions"}]}]}'
# Real githubstatus.com carries a dozen components. A Copilot blip raises the
# global indicator but explains nothing about a check.
STATUS_IRRELEVANT='{"status":{"indicator":"minor","description":"Partially Degraded Service"},
  "components":[{"name":"Actions","status":"operational"},
                {"name":"API Requests","status":"operational"},
                {"name":"Copilot","status":"degraded_performance"}],
  "incidents":[{"name":"Incident with Copilot","status":"investigating",
                "components":[{"name":"Copilot"}]}]}'
# Reachable, 200, parsable JSON — and not a statuspage summary at all. This is
# deliberately the shape that DEFEATED a key-presence gate: it carries a
# `status` key, so `has("status")` passed and the payload classified
# `operational` — a non-2xx body manufacturing a green platform. An
# `{"error":...}` body happened to be caught by that gate, which would have made
# this case vacuous.
STATUS_GARBAGE='{"status":"Service Unavailable","code":503}'

scenario() { # <name> <pr_json> <runs_json> <head_age_secs> <status kind>
    local d="$WORK/sc-$1"
    mkdir -p "$d"
    printf '%s\n' "$2" >"$d/pr.json"
    printf '%s\n' "$3" >"$d/runs.json"
    jq -n --argjson age "$4" '{commit:{committer:{date:((now - $age)|floor|todateiso8601)}}}' >"$d/commit.json"
    case "$5" in
        green)       printf '%s\n' "$STATUS_GREEN" >"$d/status.json" ;;
        incident)    printf '%s\n' "$STATUS_INCIDENT" >"$d/status.json" ;;
        irrelevant)  printf '%s\n' "$STATUS_IRRELEVANT" >"$d/status.json" ;;
        garbage)     printf '%s\n' "$STATUS_GARBAGE" >"$d/status.json" ;;
        unreachable) : >"$d/status.unreachable"; printf '{}\n' >"$d/status.json" ;;
        *) echo "scenario: bad status kind '$5'" >&2; exit 1 ;;
    esac
    echo "$d"
}

# --- runner -------------------------------------------------------------------
STDOUT=""; STDERR=""; STATUS=0; VERDICT=""
run_probe() { # <script> <scenario_dir> [extra probe args...]
    local script="$1" dir="$2"
    shift 2
    : >"$WORK/calls"
    # Every PLATFORM_* knob the probe reads is pinned: an operator's ambient
    # setting must not change what this gate measures.
    PATH="$BIN:$PATH" SCENARIO_DIR="$dir" MOCK_CALLS="$WORK/calls" \
    PLATFORM_STATUS_URL="https://status.example.invalid/api/v2/summary.json" \
    PLATFORM_STATUS_TIMEOUT=5 \
    PLATFORM_PROBE_MIN_AGE=300 \
    PLATFORM_STATUS_COMPONENTS="${SCOPE_OVERRIDE:-actions,api requests,webhooks,pull requests,git operations}" \
        bash "$script" --repo mock-org/mock-repo "$@" >"$WORK/stdout" 2>"$WORK/stderr"
    STATUS=$?
    STDOUT="$(cat "$WORK/stdout")"
    STDERR="$(cat "$WORK/stderr")"
    if [ -n "$STDOUT" ]; then
        VERDICT="$(jq -r '.verdict // "«no verdict»"' <<<"$STDOUT" 2>/dev/null)"
        [ -n "$VERDICT" ] || VERDICT="«unparsable»"
    else
        VERDICT="«no output»"
    fi
}

field() { jq -r "$1 // \"\"" <<<"$STDOUT" 2>/dev/null; }
kinds() { jq -r '[.anomalies[].kind] | sort | join(",")' <<<"$STDOUT" 2>/dev/null; }
errkinds() { jq -r '[.probe_errors[].kind] | sort | join(",")' <<<"$STDOUT" 2>/dev/null; }

# Does any REPORTED VALUE carry a character the sanitisers must strip?
#
# Scoped to scalar VALUES, never to the serialized document: the class includes
# U+0000-U+001F, the pretty-printed JSON is full of newlines, and a whole-text
# test therefore answers "yes" for every run including the clean ones. Measured
# - it made the unmutated baseline look unsafe and the mutant indistinguishable
# from it, so the proof reported UNDETECTED while the probe was behaving.
#
# Written as CODEPOINT arithmetic rather than a character class so this file
# states the spec in a form that cannot be silently mangled by a copy: the
# class is U+0000-U+001F, U+007F, U+0085, U+061C, U+200E/U+200F,
# U+2028/U+2029, U+202A-U+202E, U+2066-U+2069 and the U+E0000-U+E007F tag block.
# It is deliberately NOT harvested from the probe - that would let a probe which
# narrowed its class narrow the assertion with it. Section 26's source-level
# check is what compares the probe's own sites to each other.
UNSAFE_JQ='def is_unsafe: explode | any(
  . < 32 or . == 127 or . == 133 or . == 1564
  or (. >= 8206 and . <= 8207) or (. >= 8232 and . <= 8233)
  or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)
  or (. >= 917504 and . <= 917631));'

json_has_unsafe() { # <json text> -> yes|no
    local r
    r="$(jq -r "$UNSAFE_JQ"' [paths(scalars) as $p | getpath($p) | tostring | select(is_unsafe)] | length > 0' <<<"$1" 2>/dev/null)"
    if [ "$r" = "true" ]; then echo yes; else echo no; fi
}

# The stderr line is plain text, so its own line structure is legitimate: TAB
# and NEWLINE are excluded, everything else in the class is not.
text_has_unsafe() { # <text> -> yes|no
    local r
    r="$(jq -rn --arg t "$1" '$t | explode | any(
            (. < 32 and . != 9 and . != 10 and . != 13) or . == 127
            or . == 133 or . == 1564
            or (. >= 8206 and . <= 8207) or (. >= 8232 and . <= 8233)
            or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)
            or (. >= 917504 and . <= 917631))' 2>/dev/null)"
    if [ "$r" = "true" ]; then echo yes; else echo no; fi
}

dump() {
    printf '%s\n' "$STDERR" | sed 's/^/          | E /' >&2
    printf '%s\n' "$STDOUT" | sed 's/^/          | O /' >&2
}

expect_verdict() { # <label> <expected>
    if [ "$VERDICT" = "$2" ]; then ok "$1 (verdict: $VERDICT)"; else bad "$1 — verdict '$VERDICT', expected '$2'"; dump; fi
}
expect_field() { # <label> <jq-path> <expected>
    local got; got="$(field "$2")"
    if [ "$got" = "$3" ]; then ok "$1 ($2 = $got)"; else bad "$1 — $2 = '$got', expected '$3'"; dump; fi
}
expect_status() { # <label> <expected>
    if [ "$STATUS" = "$2" ]; then ok "$1 (exit $STATUS)"; else bad "$1 — exit $STATUS, expected $2"; dump; fi
}
expect_kind() { # <label> <kind>
    local k; k="$(kinds)"
    if grep -qF -- "$2" <<<"$k"; then ok "$1"; else bad "$1 — anomalies were '$k', expected to include $2"; dump; fi
}
expect_errkind() { # <label> <kind>
    local k; k="$(errkinds)"
    if grep -qF -- "$2" <<<"$k"; then ok "$1"; else bad "$1 — probe_errors were '$k', expected to include $2"; dump; fi
}
expect_explains_nothing() { # <label>
    # BOTH halves. A bare `nothing*` glob is satisfied by "nothing prevents
    # escalating this stall as a real defect" — the exact inversion of the rule,
    # passing the matcher that exists to guard it.
    local e; e="$(field .explains)"
    case "$e" in
        nothing*)
            if grep -qF -- "never licenses escalating" <<<"$e"; then
                ok "$1"
            elif grep -qF -- "not an explanation" <<<"$e"; then
                ok "$1"
            else
                bad "$1 — explains opens with 'nothing' but drops the never-escalate half: '$e'"; dump
            fi ;;
        *) bad "$1 — explains reads '$e', which does not open by saying it explains nothing"; dump ;;
    esac
}
refute_explains_nothing() { # <label>
    local e; e="$(field .explains)"
    case "$e" in
        nothing*) bad "$1 — a degraded verdict reported that it explains nothing: '$e'"; dump ;;
        *) ok "$1" ;;
    esac
}

# ==============================================================================
echo "1. clean first-party + green page = healthy (table row 5)" >&2
D="$(scenario healthy "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "clean + operational resolves healthy" "healthy"
expect_status "  and exits 0, like every other verdict" 0
expect_field "  first-party measurement is recorded as clean" .self_measured "clean"
expect_field "  and it says which check earned that (the run comparison ran)" \
    .checks_run.run_comparison "ran"
expect_field "  the page is recorded as operational" .status_page "operational"
expect_field "  no anomaly from job names, and none from the StatusContext entry" \
    '(.anomalies | length | tostring)' "0"
expect_explains_nothing "  and healthy is reported as explaining nothing"

echo "2. first-party anomaly + relevant incident = degraded (attributed) (row 1)" >&2
D="$(scenario attributed "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 incident)"
run_probe "$PROBE" "$D" --pr 283
expect_verdict "anomaly + incident resolves degraded (attributed)" "degraded (attributed)"
expect_status "  and exits 0" 0
expect_field "  first-party measurement is recorded as an anomaly" .self_measured "anomaly"
expect_kind "  the missing CI workflow run is named" "missing_workflow_run"
expect_kind "  the empty-state rollup entry is named" "empty_state_check"
refute_explains_nothing "  a degraded verdict does NOT report that it explains nothing"

echo "3. first-party anomaly + GREEN page = degraded (unattributed), never healthy (row 2)" >&2
D="$(scenario unattributed "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 green)"
run_probe "$PROBE" "$D" --pr 283
expect_verdict "a green page does not refute a first-party anomaly" "degraded (unattributed)"
expect_field "  the page really was read as green (so this is not passing by accident)" \
    .status_page "operational"
expect_status "  and exits 0" 0
refute_explains_nothing "  the verdict explains the stall rather than explaining nothing"

echo "4. clean first-party + UNREACHABLE endpoint = unknown (row 6)" >&2
D="$(scenario unknown-clean "$PR_CLEAN" "$RUNS_CLEAN" 3600 unreachable)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "an unreadable status page degrades to unknown, not to health" "unknown"
expect_field "  the page is recorded as unknown, never operational" .status_page "unknown"
expect_field "  first-party measurement really was clean, so the verdict came from the page" \
    .self_measured "clean"
expect_status "  and exits 0" 0
expect_explains_nothing "  and unknown is reported as explaining nothing"

echo "5. first-party anomaly + UNREACHABLE endpoint = degraded (unattributed) (row 3)" >&2
D="$(scenario unattributed-dark "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 unreachable)"
run_probe "$PROBE" "$D" --pr 283
expect_verdict "an unreadable page adds exactly as much as a green one: nothing" \
    "degraded (unattributed)"
expect_field "  the page is recorded as unknown" .status_page "unknown"
expect_status "  and exits 0" 0

echo "6. clean first-party + relevant incident = degraded (attributed) (row 4)" >&2
D="$(scenario clean-incident "$PR_CLEAN" "$RUNS_CLEAN" 3600 incident)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "an open incident on a check-relevant component still attributes" \
    "degraded (attributed)"
expect_field "  but the first-party read is still reported as clean" .self_measured "clean"
expect_explains_nothing "  and it must NOT claim to explain check data the same payload shows is complete"

echo "7. nothing measured first-party (no --pr): rows 7, 8 and 9" >&2
D="$(scenario nomeasure-green "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D"
expect_verdict "row 8: unmeasured over a green page is unknown, never healthy" "unknown"
expect_field "  and says so" .self_measured "not_measured"
expect_field "  naming why it could not measure" .self_measured_reason "no_pr_given"
D="$(scenario nomeasure-incident "$PR_CLEAN" "$RUNS_CLEAN" 3600 incident)"
run_probe "$PROBE" "$D"
expect_verdict "row 7: an open incident still attributes without a first-party signal" \
    "degraded (attributed)"
D="$(scenario nomeasure-dark "$PR_CLEAN" "$RUNS_CLEAN" 3600 unreachable)"
run_probe "$PROBE" "$D"
expect_verdict "row 9: nothing measured and an unreadable page is unknown" "unknown"

# ==============================================================================
echo "8. the FIRST-PARTY door into healthy: no baseline is not 'clean'" >&2
# The fixture is PR_CLEAN — a POPULATED rollup — deliberately. With an empty
# rollup neither check can run and the case passes for the wrong reason: the
# door that was still open is the one where the rollup check runs, finds no
# malformed entry, and earns `clean` on a branch whose runs were never compared.
# Measured on the pre-fix source, this exact fixture returned `healthy` and made
# M8 report UNDETECTED.
D="$(scenario no-baseline "$PR_CLEAN" "$RUNS_EMPTY" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a single-commit branch is unknown even when its rollup is populated and clean" "unknown"
expect_field "  nothing was measured" .self_measured "not_measured"
expect_field "  and it names the missing baseline" .self_measured_reason "no_prior_heads"
expect_field "  the run comparison is reported as not having run" \
    .checks_run.run_comparison "not_run"
expect_field "  while the rollup check DID run — and is not sufficient on its own" \
    .checks_run.rollup_empty_state "ran"

# #285's own rollup shape on a single-commit branch: entries present, no `ci`,
# and no malformed entry to find. The empty-state check cannot see an ABSENT
# check, so this is the shape that must never read `healthy`.
D="$(scenario absent-check "$PR_ABSENT_CHECK" "$RUNS_EMPTY" 4000 green)"
run_probe "$PROBE" "$D" --pr 501
expect_verdict "#285's own rollup shape is never certified healthy" "unknown"
expect_field "  because a missing check is invisible to the empty-state read" \
    .self_measured "not_measured"

echo "9. no_run_for_head — #285's headline signal, and its intersection guard" >&2
D="$(scenario no-run-head "$PR_CLEAN" "$RUNS_NO_HEAD" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_kind "a head carrying no run at all, where every prior head ran one, is named" "no_run_for_head"
expect_verdict "  and a green page does not refute it" "degraded (unattributed)"
D="$(scenario no-run-disjoint "$PR_CLEAN" "$RUNS_DISJOINT" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_field "  but with DISJOINT prior heads nothing was required, so no anomaly is invented" \
    '(.anomalies | length | tostring)' "0"
expect_verdict "  and an empty intersection compared nothing, so it is unknown rather than healthy" "unknown"
expect_field "  which it says in as many words" .self_measured_reason "no_required_baseline"

# ==============================================================================
echo "10. ordinary absence is not degradation (intersection + event whitelist)" >&2
D="$(scenario partial-baseline "$PR_CLEAN" "$RUNS_PARTIAL" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a workflow that ran on only ONE prior head is not required of this one" "healthy"
expect_field "  with no anomaly invented from a path filter or a rename" \
    '(.anomalies | length | tostring)' "0"
D="$(scenario dispatch-baseline "$PR_CLEAN" "$RUNS_DISPATCH" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a one-off workflow_dispatch run on a prior head is never 'missing' here" "healthy"

# ==============================================================================
echo "11. the age floor, and the signal it must NOT suppress" >&2
D="$(scenario fresh "$PR_EMPTY_ROLLUP" "$RUNS_NO_HEAD" 60 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a head younger than the floor suppresses the run signals" "unknown"
expect_field "  and says why" .self_measured_reason "head_too_fresh"
expect_field "  with no anomaly manufactured from a workflow that has not started" \
    '(.anomalies | length | tostring)' "0"
D="$(scenario fresh-empty-state "$PR_ANOMALY" "$RUNS_ANOMALY" 60 green)"
run_probe "$PROBE" "$D" --pr 283
expect_kind "the empty-state read is NOT age-suppressed — it is a direct rollup read" "empty_state_check"
expect_verdict "  so the #285 fingerprint survives on a fresh head" "degraded (unattributed)"

echo "12. the empty-state read survives the runs call failing" >&2
D="$(scenario runs-down "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 green)"
: >"$D/runs.fail"
run_probe "$PROBE" "$D" --pr 283
expect_kind "an outage that breaks actions/runs does not take the rollup signal with it" \
    "empty_state_check"
expect_verdict "  and the verdict still reports degradation" "degraded (unattributed)"
expect_errkind "  with the failed call recorded separately" "gh_call_failed"

# ==============================================================================
echo "13. a gh TRANSPORT failure is not_measured, never an anomaly" >&2
D="$(scenario ghfail "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 green)"
: >"$D/pr.fail"
run_probe "$PROBE" "$D" --pr 283
expect_errkind "the failed call is recorded as a probe error" "gh_call_failed"
expect_field "  it is NOT an anomaly (an expired token is not platform degradation)" \
    '(.anomalies | length | tostring)' "0"
expect_verdict "  so the run is unknown, not a confident claim about the platform" "unknown"
expect_status "  and it still exits 0" 0

echo "12b. a FUTURE-dated head is an invalid measurement, not a fresh one" >&2
# `GIT_COMMITTER_DATE` is author-settable and GitHub preserves it, so an
# unclamped age makes a fork-PR author able to suppress the load-bearing signal
# on their own PR forever, under a reason (`head_too_fresh`) that is false on its
# face. A negative age is routed to `head_age_unknown` instead.
# PR_CLEAN, not PR_ANOMALY: an anomaly wins the SELF decision and blanks the
# reason, so the age routing would be invisible.
D="$(scenario future-head "$PR_CLEAN" "$RUNS_CLEAN" -86400 green)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a negative age is not read as a fresh head" .self_measured_reason "head_age_unknown"
expect_field "  and the age is not reported as a number" .head_age_seconds ""

echo "12c. a payload missing a key the call ASKED FOR is a transport failure" >&2
# The call requests statusCheckRollup and mergeStateStatus; validating only
# headRefOid let an absent rollup default to `[]` and the run reach `healthy`
# with an empty error ledger — which this file's own header forbids in as many
# words.
D="$(scenario missing-keys "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
printf '%s\n' '{"number":301,"headRefOid":"aa11bb2","headRefName":"feat/clean"}' >"$D/pr.json"
run_probe "$PROBE" "$D" --pr 301
expect_errkind "the omitted keys are recorded" "incomplete_payload"
expect_field "  and the run is not clean" .self_measured "not_measured"
expect_verdict "  so it is unknown, never healthy" "unknown"

echo "13b. a first-party error is not a clean read either — the ledger is consulted" >&2
# Both gh api calls fail while the ROLLUP is present and clean. The rollup check
# runs and finds nothing, so `clean` is reachable — and reporting it would
# certify a platform the probe half failed to read. Measured on the first
# edition: `{"verdict":"healthy","probe_errors":[…,…]}`, contradicting this
# file, SKILL.md and CLAUDE.md at once.
D="$(scenario errors-but-clean-rollup "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
: >"$D/commit.fail"
: >"$D/runs.fail"
run_probe "$PROBE" "$D" --pr 301
expect_errkind "the failed calls are on the ledger" "gh_call_failed"
expect_field "  the rollup check really did run, so a clean verdict was reachable" \
    .checks_run.rollup_empty_state "ran"
expect_field "  and it is still not called clean" .self_measured "not_measured"
expect_field "  naming the failed calls as why it could not measure" \
    .self_measured_reason "probe_errors_present"
expect_verdict "  so a half-read platform is unknown, never healthy" "unknown"

echo "14. a structurally incomplete payload is a transport failure too" >&2
D="$(scenario shortpayload "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 green)"
printf '{"number":283}\n' >"$D/pr.json"
run_probe "$PROBE" "$D" --pr 283
expect_errkind "a 0-exit payload missing headRefOid is recorded" "incomplete_payload"
expect_verdict "  and resolves unknown, never healthy" "unknown"

# ==============================================================================
echo "15. attribution is SCOPED — an unrelated component invents no excuse" >&2
D="$(scenario irrelevant "$PR_CLEAN" "$RUNS_CLEAN" 3600 irrelevant)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a Copilot blip is not a check-relevant component" .status_page "operational"
expect_verdict "  so it never manufactures an excuse for a red check" "healthy"

echo "16. a reachable but unrecognisable status payload is unknown, never healthy" >&2
D="$(scenario garbage "$PR_CLEAN" "$RUNS_CLEAN" 3600 garbage)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a 200 carrying non-statuspage JSON is not 'operational'" .status_page "unknown"
expect_verdict "  and the verdict degrades to unknown" "unknown"

# ==============================================================================
echo "16b. a degenerate component scope cannot answer, so it must not say 'operational'" >&2
# `${VAR:-default}` restores the default for an EMPTY value, so the dangerous
# inputs are the non-empty degenerate ones: `,` and `   ` both parse to an empty
# scope, match nothing, and a scope that matches nothing looks exactly like a
# platform with nothing wrong. Measured through the shipped script against a
# major Actions outage, both returned `healthy`.
D="$(scenario degenerate-scope "$PR_CLEAN" "$RUNS_CLEAN" 3600 incident)"
for scope in "," "   "; do
    : >"$WORK/calls"
    PATH="$BIN:$PATH" SCENARIO_DIR="$D" MOCK_CALLS="$WORK/calls" \
    PLATFORM_STATUS_URL="https://status.example.invalid/api/v2/summary.json" \
    PLATFORM_STATUS_COMPONENTS="$scope" \
        bash "$PROBE" --repo mock-org/mock-repo --pr 301 >"$WORK/stdout" 2>"$WORK/stderr"
    STDOUT="$(cat "$WORK/stdout")"
    VERDICT="$(jq -r '.verdict // "«no verdict»"' <<<"$STDOUT" 2>/dev/null)"
    expect_field "a scope of '$scope' matches nothing, so attribution is unknown" \
        .status_page "unknown"
    expect_verdict "  and an open Actions outage is never reported as healthy" "unknown"
done

echo "16c. the status URL is validated before it reaches curl" >&2
# Unvalidated, a value starting `-K` is read by curl as `--config`, which can set
# `output` (arbitrary file write), `upload-file`, `header` or `proxy`; and
# `file://`/`http://` put attacker-chosen text into a field the caller is told to
# report, in a repo that is PUBLIC by exception.
for badurl in "http://status.example.invalid/s.json" "file:///etc/passwd" "-K/tmp/curlrc"; do
    run_probe "$PROBE" "$D" --pr 301 --status-url "$badurl"
    expect_status "a non-https status URL ('$badurl') is refused" 1
done

echo "16d. the runs page reports whether it was truncated" >&2
# Pagination cuts BOTH ways and the under-detect direction reaches `healthy`, so
# the caller is told when the page was full rather than left to assume it was not.
D="$(scenario untruncated "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a short page is reported as not truncated" .checks_run.runs_page_truncated "no"
BIG_RUNS="$(jq -nc '{workflow_runs: ([range(0;100) | {name:"CI", event:"pull_request", head_sha:("h" + (. | tostring))}] + [{name:"CI",event:"pull_request",head_sha:"aa11bb2"}])}')"
D="$(scenario truncated "$PR_CLEAN" "$BIG_RUNS" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a full page is reported as truncated, so the caller can see the limit" \
    .checks_run.runs_page_truncated "yes"

echo "17. the probe never writes" >&2
D="$(scenario readonly "$PR_ANOMALY" "$RUNS_ANOMALY" 3600 incident)"
run_probe "$PROBE" "$D" --pr 283
call_count="$(grep -c . "$WORK/calls")"
if [ "$call_count" -ge 4 ]; then
    ok "the degraded run actually reached the mocks ($call_count calls)"
else
    bad "only $call_count mock calls recorded — the read-only claim below would be vacuous"
fi
# Classified by METHOD, not by path prefix: `gh api repos/o/n/pulls/1/merge -X PUT`
# is a write whose path starts exactly like a read. The scan is per TOKEN and
# matches PREFIXES, because the attached forms are what `gh` documents and what
# people type — `-XPUT`, `-fbody=x`, `--field=body=x` and `--input=-` all slipped
# past a space-padded substring test, and `gh api` becomes a POST the moment any
# `-f` is present.
offending=""
while IFS= read -r line; do
    for tok in $line; do
        case "$tok" in
            -X*|--method*|-f*|-F*|--field*|--raw-field*|--input*)
                offending="$offending$line"$'\n'; continue 2 ;;
        esac
    done
    case "$line" in
        "gh pr view "*|"gh api repos/"*|"curl "*) : ;;
        *) offending="$offending$line"$'\n' ;;
    esac
done <"$WORK/calls"
if [ -z "$offending" ]; then
    ok "every recorded call is a read: no method flag, no field flag, no write verb"
else
    bad "the probe made a call outside its read-only contract:"$'\n'"$offending"
fi

echo "18. exit codes carry no verdict, but still carry usage errors" >&2
run_probe "$PROBE" "$D" --pr not-a-number
expect_status "a usage error is the one non-zero exit" 1
# A lone trailing flag must not spin: `shift 2` with one arg left shifts nothing.
run_probe "$PROBE" "$D" --pr 283 --min-age
expect_status "a value-less trailing flag is rejected rather than looping forever" 1

# ==============================================================================
echo "19. no sibling script and no other skill consults the probe" >&2
section_of() { # <file> <heading prefix>
    awk -v h="$2" '
        substr($0, 1, length(h)) == h { inseg = 1; next }
        inseg && /^##+ / { exit }
        inseg { print }
    ' "$1"
}
# CAPTURE, then match against a herestring. The earlier edition of this function
# piped awk into `grep -qF` under pipefail, where a SIGPIPE 141 on a MATCH reads
# as "not found" — so every must-NOT-name assertion below failed OPEN, which is
# gate 30's whole subject (#256) landing on the gate that exists to refuse
# exactly this class of silent pass.
# region_text <file> <start heading prefix> <end heading prefix> — `section_of`
# stops at the NEXT `##+ ` line, which truncates any section that has
# subheadings: §7 ends at `### DRAIN DEGRADED` and §4 at `### Collision`, so a
# scan over either measured a fraction of it and reported clean. This one is
# bounded by an explicit end heading instead.
region_text() {
    awk -v h="$2" -v e="$3" '
        substr($0, 1, length(h)) == h { inseg = 1; next }
        inseg && substr($0, 1, length(e)) == e { exit }
        inseg { print }
    ' "$1" | tr '\n' ' ' | tr -s ' \t'
}
section_text() { # <file> <heading prefix>
    local s
    s="$(section_of "$1" "$2")"
    printf '%s' "$s" | tr '\n' ' ' | tr -s ' \t'
}
section_names_probe() { # <file> <heading prefix>
    local t
    t="$(section_text "$1" "$2")"
    grep -qF -- "$PROBE_BASENAME" <<<"$t"
}
SIBLINGS=(gh-retry.sh merge-shepherd.sh poll-prs.sh poll-queue.sh pr-failure-log.sh stack-probe.sh teardown.sh)
# EQUALITY against the TRACKED listing (git ls-files, like every other corpus in
# this repo), so a new script cannot ship unscanned and an untracked scratch
# file cannot redden the gate with a message that blames the list.
listed="$(printf '%s\n' "${SIBLINGS[@]}" | sort | tr '\n' ' ')"
tracked="$(git ls-files 'skills/pr-shepherd/scripts/*.sh')"
actual="$(printf '%s\n' "$tracked" | sed 's|.*/||' | grep -v -x -F "$PROBE_BASENAME" | sort | tr '\n' ' ')"
if [ "$listed" = "$actual" ]; then
    ok "the scanned sibling list equals the tracked scripts (${#SIBLINGS[@]} files)"
else
    bad "sibling list drift — scanning [$listed] but the tree tracks [$actual]"
fi

scan_for_probe() { # <file...>  — echoes each file that names the probe
    local f
    for f in "$@"; do
        if [ ! -f "$f" ]; then printf 'MISSING:%s\n' "$f"; continue; fi
        if grep -qF -- "$PROBE_BASENAME" "$f"; then printf '%s\n' "$f"; fi
    done
}
# The FILENAME is not the only way to wire the verdict in. #285's own follow-up
# work will be written in verdict VOCABULARY — "on a degraded verdict, hold the
# PR" names no script — and a filename-only scan reports that as clean; measured,
# a section doing exactly that left this gate at exit 0. The two `degraded (…)`
# literals are distinctive enough to scan for; `healthy` and `unknown` are
# ordinary English and are deliberately NOT in the set.
VERDICT_VOCAB=('degraded (attributed)' 'degraded (unattributed)' 'platform-degradation verdict')
scan_for_verdict() { # <file...>  — echoes "<file>: <literal>" per hit
    local f lit
    for f in "$@"; do
        [ -f "$f" ] || continue
        for lit in "${VERDICT_VOCAB[@]}"; do
            if grep -qF -- "$lit" "$f"; then printf '%s: %s\n' "$f" "$lit"; fi
        done
    done
}
sibling_paths=()
for s in "${SIBLINGS[@]}"; do sibling_paths+=("$SCRIPTS_DIR/$s"); done
hits="$(scan_for_probe "${sibling_paths[@]}")"
if [ -z "$hits" ]; then
    ok "no merge, poll, retry or teardown script consults the platform verdict"
else
    bad "the probe is referenced by a decision-making script, which makes it a gate: $hits"
fi

# The rule says "no merge, HOLD, BLOCK or REDISPATCH decision", and the block and
# redispatch sites do not live in pr-shepherd at all. #285's scope note is
# explicit that ACTING on the verdict is separate work, so naming the probe in
# any of these is a deliberate change that must come back through this gate.
# `dispatch-ready/SKILL.md` is NOT here, and its absence is a scoped decision
# rather than an exemption (#286). Its §7 legitimately consults the verdict to
# reach DRAIN DEGRADED — a decision to STOP, which writes nothing — while its
# §2 and §4, the hold/merge/redispatch and selection surfaces, must not. That is
# the same shape this gate already applies to pr-shepherd's own file, whose §2b
# legitimately uses the vocabulary: SECTION-scoped, never file-scoped. The
# section scan is below, and it carries a POSITIVE control so the carve-out
# cannot silently widen from "§7 may" to "the file may".
DECISION_DOCS=(
    "$REPO_ROOT/skills/take-it/SKILL.md"
    "$REPO_ROOT/skills/send-it/SKILL.md"
)
while IFS= read -r ref; do
    [ -n "$ref" ] && DECISION_DOCS+=("$REPO_ROOT/$ref")
done < <(git ls-files 'skills/pr-shepherd/references/*.md')
doc_hits="$(scan_for_probe "${DECISION_DOCS[@]}")"
if [ -z "$doc_hits" ]; then
    ok "no dispatching skill and no pr-shepherd reference doc names the probe (${#DECISION_DOCS[@]} docs)"
else
    # A MISSING: line fails here too: a renamed path that silently drops out of
    # the corpus leaves the ok-line reporting a doc count it never read.
    bad "the verdict reached a hold/block/redispatch surface (or a scanned path vanished), which #285 scopes out: $doc_hits"
fi
vocab_hits="$(scan_for_verdict "${sibling_paths[@]}" "${DECISION_DOCS[@]}")"
if [ -z "$vocab_hits" ]; then
    ok "and none of them is wired to the verdict VOCABULARY either"
else
    bad "a decision surface consults the platform verdict by name rather than by filename: $vocab_hits"
fi
# dispatch-ready's ACTION sections. §7 may name the probe (#286); §2 and §4 may
# not — those are where a PR is held, merged, redispatched or an issue selected,
# and #285's never-a-gate rule is drawn on exactly that act-vs-stop line.
DR_SKILL="$REPO_ROOT/skills/dispatch-ready/SKILL.md"
dr_vocab=""
for spec in "## 2. Reconcile in-flight|## 3. Compute capacity" "## 4. Select from Ready|## 5."; do
    heading="${spec%%|*}"; endh="${spec##*|}"
    dr_text="$(region_text "$DR_SKILL" "$heading" "$endh")"
    [ -n "$dr_text" ] || dr_vocab="$dr_vocab$heading: EMPTY SECTION (renamed? the scan over it is vacuous)"$'\n'
    for lit in "${VERDICT_VOCAB[@]}"; do
        if grep -qF -- "$lit" <<<"$dr_text"; then dr_vocab="$dr_vocab$heading: $lit"$'\n'; fi
    done
    if grep -qF -- "probe-platform-health" <<<"$dr_text"; then
        dr_vocab="$dr_vocab$heading: names the probe script"$'\n'
    fi
done
if [ -z "$dr_vocab" ]; then
    ok "dispatch-ready's ACTION sections (2, 4) consult neither the probe nor its vocabulary"
else
    bad "dispatch-ready wired the verdict into an action surface, which #285 forbids and #286 does not license: $dr_vocab"
fi

# POSITIVE CONTROL. The carve-out is "§7 may", and a scan that finds the verdict
# nowhere in dispatch-ready would report the two assertions above as clean while
# measuring a file in which #286 was reverted. So §7 must actually name it.
dr_s7="$(region_text "$DR_SKILL" "### DRAIN DEGRADED" "### DRAIN COMPLETE")"
if grep -qF -- "probe-platform-health" <<<"$dr_s7" && grep -qF -- "degraded (attributed)" <<<"$dr_s7"; then
    ok "and §7 DOES name the probe and its vocabulary, so the carve-out is live rather than vacuous"
else
    bad "§7 no longer consults the probe — #286's DRAIN DEGRADED is gone, and the scans above prove nothing"
fi

# pr-shepherd's OWN decision sections are the nearest surface of all and were
# in neither corpus above — the filename check covers them, but the filename is
# not how a gating rule gets written. Its §2b legitimately uses the vocabulary,
# so this is section-scoped rather than file-scoped.
sec_vocab=""
for heading in "### 1. Mergeable check" "### 1b. Stack check" "### 3. Merge or enqueue greens"; do
    sec_text="$(section_text "$SKILL" "$heading")"
    [ -n "$sec_text" ] || sec_vocab="$sec_vocab$heading: EMPTY SECTION (renamed? the scan over it is vacuous)"$'\n'""
    for lit in "${VERDICT_VOCAB[@]}"; do
        if grep -qF -- "$lit" <<<"$sec_text"; then sec_vocab="$sec_vocab$heading: $lit"$'\n'; fi
    done
done
if [ -z "$sec_vocab" ]; then
    ok "and pr-shepherd's own decision sections use none of it either"
else
    bad "the verdict vocabulary reached a pr-shepherd decision section: $sec_vocab"
fi

# ==============================================================================
echo "20. the probe is named in its own section, not in the decision sections" >&2
for heading in "### 2b. Platform degradation probe" "## Bundled scripts"; do
    if section_names_probe "$SKILL" "$heading"; then
        ok "'$heading' names the probe"
    else
        bad "'$heading' does not name $PROBE_BASENAME — the section is missing or renamed"
    fi
done
for heading in "### 1. Mergeable check" "### 1b. Stack check" "### 3. Merge or enqueue greens"; do
    # FAIL CLOSED on an empty window first. `section_of` returns nothing for a
    # heading prefix that matches nothing, and an empty section passes every
    # must-NOT-name check below — so a rename silently RETIRES this scan, which
    # is the `window_is_bounded` lesson. Measured: renaming §1 and wiring a hold
    # decision into it left this gate green.
    if [ -z "$(section_text "$SKILL" "$heading")" ]; then
        bad "'$heading' resolves to an EMPTY section — renamed or removed, and every scan over it is now vacuous"
    elif section_names_probe "$SKILL" "$heading"; then
        bad "'$heading' names $PROBE_BASENAME — the verdict has reached a decision section"
    else
        ok "'$heading' does not consult the probe"
    fi
done
GUARDRAILS="$(section_text "$SKILL" "## Guardrails")"
if grep -qF -- "Never let the platform-degradation verdict gate anything." <<<"$GUARDRAILS"; then
    ok "Guardrails carries the never-a-gate rule"
else
    bad "Guardrails no longer carries the never-a-gate rule"
fi
# …and by CANON, for the same reason §2b is. Presence keeps the sentence and
# permits "…except on a `degraded (attributed)` verdict, where the PR is held"
# appended to it — and Guardrails is exactly where a gating exception gets
# written. Canon is on the BULLET, so the rest of the list stays free to change.
GR_BULLET="$(grep -F -- '- **Never let the platform-degradation verdict gate anything.**' "$SKILL" | tr -s ' ')"
GR_SUM="$(printf '%s' "$GR_BULLET" | cksum | cut -d' ' -f1)"
GR_CANON="65229782"
if [ "$GR_SUM" = "$GR_CANON" ]; then
    ok "Guardrails bullet canon matches (an appended exception fails here)"
else
    bad "Guardrails bullet drift — got $GR_SUM want $GR_CANON :: $(printf '%.90s' "$GR_BULLET")"
fi

# ==============================================================================
echo "21. SKILL.md states the contract the probe implements" >&2
SKILL_FLAT="$WORK/skill.flat"
tr '\n' ' ' <"$SKILL" | tr -s ' \t' >"$SKILL_FLAT"
expect_prose() { # <label> <needle>
    if grep -qF -- "$2" "$SKILL_FLAT"; then ok "$1"; else bad "$1 — missing from $SKILL: $2"; fi
}
expect_prose "the healthy row is documented" \
    '| `healthy` | a first-party check actually ran, found nothing wrong, AND the status page is green |'
expect_prose "the attributed row is documented" \
    '| `degraded (attributed)` | the platform reports an open incident on a check-relevant component |'
expect_prose "the unattributed row is documented" \
    '| `degraded (unattributed)` | first-party evidence of degradation the status page does not corroborate |'
expect_prose "the unknown row is documented" \
    '| `unknown` | nothing could be measured, or the status endpoint could not be read |'
expect_prose "green is stated NOT to be evidence of health" \
    '**A green status page is NOT evidence of health.**'
expect_prose "the asymmetry is stated in the words the issue requires" \
    '`red` explains a stall; `green` explains nothing, and must be reported in those words.'
expect_prose "callers are told to report the explains field, not the verdict alone" \
    '**Report the `explains` field, not the verdict alone.**'
expect_prose "and that three verdicts explain nothing, not two" \
    'A `healthy` or an `unknown` verdict explains nothing — and so does a `degraded (attributed)` verdict whose `self_measured` is not `anomaly`'
expect_prose "an unreachable endpoint is neither healthy nor degraded on its own" \
    '**An unreachable status endpoint contributes `unknown`** — never `healthy`, and never `degraded` on its own.'
expect_prose "the never-a-gate rule names all four decisions it stays out of" \
    'it appears in **no** merge, hold, block or redispatch decision'
expect_prose "the exit-code contract is stated as what makes never-a-gate structural" \
    'every verdict exits `0` so it cannot become one through a `set -e` or an `if`'
expect_prose "the first-party door into healthy is documented as closed" \
    '`clean` means a check RAN and found nothing'
expect_prose "the transport-failure reading is documented rather than left implicit" \
    'a failed `gh` call is `not_measured`, never an anomaly'
expect_prose "attribution is documented as scoped to check-relevant components" \
    '**attribution is scoped to check-relevant status components**'

# ==============================================================================
echo "22. §2b is pinned by CANON, not by presence alone" >&2
# Presence-only needles are satisfied by a document that still CONTAINS every
# sentence they grep for and now also contains its INVERSE. Measured twice on
# this very section, both at exit 0: a paragraph telling the caller to hold a PR
# on a degraded verdict, and one telling it a `healthy` verdict confirms the
# stall is a real defect — precisely the two harms this gate's own header names.
# preflight.sh's entries for test-review-gate-decisions.sh,
# test-drain-terminal-states.sh and test-audit-lost-reviewer.sh record the same
# defeat, which is why those moved to canon. Canon compares every blank-line
# block of §2b for equality after flattening, so ADDING prose fails as loudly
# as removing it. The accepted cost
# is that a legitimate reword must update a checksum here: a loud false red,
# which this repo prefers to a needle that can be satisfied and inverted at once.
canon_blocks() { # <file> <heading> — one flattened block per line
    section_of "$1" "$2" | awk '
        BEGIN { RS = "" }
        { gsub(/[ \t\n]+/, " "); sub(/^ /, ""); sub(/ $/, ""); if (length($0)) print }
    '
}
# Regenerate after a deliberate §2b edit; the trailing comment is the block's
# opening words, so a drifted row says which paragraph moved.
CANON_2B=(
    "1622634225"   # A `gh` call that *errors*…
    "1892531078"   # Run the probe when a watch has gone nowhere…
    "2635286258"   # | rollup entry | probe | poll-prs | merge-shepherd
    "67846098"   # So "the poller went quiet"…
    "3301345540"   # ```bash … probe-platform-health.sh --pr …
    "1562190426"   # It returns one of exactly **four** verdicts…
    "3181854606"   # | Verdict | What it means | … the four rows
    "409465134"   # **A green status page is NOT evidence of health.**…
    "2796344907"   # **An unreachable status endpoint contributes `unknown`**…
    "1330756923"   # `clean` also needs the age floor + untruncated page; **two doors**…
    "1955687869"   # **Never a gate.**…
    "2952808899"   # **ONE carve-out** — a decision to STOP, #286
)
canon_i=0
canon_bad=""
while IFS= read -r blk; do
    blk_sum="$(printf '%s' "$blk" | cksum | cut -d' ' -f1)"
    blk_want="${CANON_2B[$canon_i]:-«unrecorded»}"
    if [ "$blk_sum" != "$blk_want" ]; then
        canon_bad="$canon_bad    block $((canon_i + 1)): got $blk_sum want $blk_want :: $(printf '%.72s' "$blk")"$'\n'
    fi
    canon_i=$((canon_i + 1))
done < <(canon_blocks "$SKILL" "### 2b. Platform degradation probe")
if [ "$canon_i" -eq "${#CANON_2B[@]}" ] && [ -z "$canon_bad" ]; then
    ok "§2b canon: all ${#CANON_2B[@]} blocks match byte-for-byte after flattening"
else
    bad "§2b canon drift — $canon_i blocks present, ${#CANON_2B[@]} recorded:"$'\n'"$canon_bad"
fi

# ==============================================================================
echo "23. the shipped DEFAULTS are asserted, since every run above overrides them" >&2
# Pinning all four PLATFORM_* knobs in run_probe is right — an operator's
# ambient value must not change what this gate measures — but it left the `:-`
# defaults dead code under test, and the defaults are the only values that ever
# ship: every documented invocation runs with no PLATFORM_* set. Measured:
# emptying the component default left this gate green while the real probe went
# from `degraded (attributed)` to `healthy` during an open Actions incident,
# which is M13's declared harm reached through the default instead of the line
# M13 mutates.
expect_default() { # <label> <exact source line>
    if grep -qF -- "$2" "$PROBE"; then ok "$1"; else bad "$1 — not found in $PROBE: $2"; fi
}
expect_default "the status endpoint defaults to githubstatus.com over https" \
    'STATUS_URL="${PLATFORM_STATUS_URL:-https://www.githubstatus.com/api/v2/summary.json}"'
expect_default "the fetch timeout defaults to 5s" \
    'STATUS_TIMEOUT="${PLATFORM_STATUS_TIMEOUT:-5}"'
expect_default "the head-age floor defaults to 300s" \
    'MIN_AGE="${PLATFORM_PROBE_MIN_AGE:-300}"'
# Both anomaly generators must CAPTURE their exit status. A process
# substitution's failure is invisible to pipefail, and RUN_CHECK is already
# "ran" by the time the missing-run loop executes, so a dead generator would
# affirmatively certify a comparison whose result it discarded. Source-level,
# because no fixture can make jq fail on a payload the earlier guards accept.
expect_default "the empty-state generator captures its exit status" \
    'empty_out="$(jq -r '
expect_default "  and checks it before trusting the read" \
    'if [ "$empty_rc" -ne 0 ]; then'
expect_default "the missing-run generator captures its exit status" \
    'missing_out="$(jq -r '
expect_default "  and un-sets RUN_CHECK when the read it certifies never happened" \
    'RUN_CHECK="not_run"'
expect_default "the component scope defaults to the check-relevant set" \
    'STATUS_COMPONENTS="${PLATFORM_STATUS_COMPONENTS:-actions,api requests,webhooks,pull requests,git operations}"'
# And one BEHAVIOURAL run with the two behaviour-carrying knobs unset, so the
# defaults are exercised and not merely read. The URL stays pinned: unsetting it
# would reach the real network, which this gate must never do.
D="$(scenario defaults "$PR_CLEAN" "$RUNS_CLEAN" 3600 irrelevant)"
: >"$WORK/calls"
PATH="$BIN:$PATH" SCENARIO_DIR="$D" MOCK_CALLS="$WORK/calls" \
PLATFORM_STATUS_URL="https://status.example.invalid/api/v2/summary.json" \
    bash "$PROBE" --repo mock-org/mock-repo --pr 301 >"$WORK/stdout" 2>"$WORK/stderr"
STATUS=$?
STDOUT="$(cat "$WORK/stdout")"
VERDICT="$(jq -r '.verdict // "«no verdict»"' <<<"$STDOUT" 2>/dev/null)"
expect_verdict "with no PLATFORM_* set, the default component scope still excludes Copilot" "healthy"

# ==============================================================================
echo "24. an empty-string name is an ANOMALY, not a silently dropped entry" >&2
# jq's `//` falls back only on null/false. `.name // .context // "(unnamed)"`
# therefore KEEPS an empty-string name, the shell guard `[ -n "$ck" ]` drops the
# entry, and the probe answers `healthy` on a rollup it had already flagged.
# The `(unnamed)` fallback was dead code, which is the tell that coverage was
# intended and never landed.
D="$(scenario emptyname "$PR_EMPTY_NAME" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "an empty-string check name is degraded (unattributed), never healthy" "degraded (unattributed)"
expect_kind "and it is reported as an empty-state check" "empty_state_check"
expect_field "the fallback name reaches the detail, so the entry is nameable" \
    '.anomalies[0].detail' "(unnamed) is in the rollup with no status, conclusion or state"

D="$(scenario emptyctx "$PR_EMPTY_CONTEXT" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "an empty-string StatusContext context is degraded too, not dropped" "degraded (unattributed)"

# The predicate has THREE conjuncts and M15 mutated only `.state`, so dropping
# `.status` or `.conclusion` was undetected. This fixture is what gives those
# two mutants somewhere to move: a check still RUNNING and a concluded check
# with no status, NEITHER of which is an empty-state placeholder. It also
# creates the `midflight` scenario the mutants below reuse - a mutant naming a
# scenario no case builds runs against a missing directory and reports
# `unknown` for both arms, which reads as UNDETECTED for the wrong reason.
D="$(scenario midflight "$PR_MIDFLIGHT" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a check mid-flight is NOT an empty-state placeholder" "healthy"
expect_field "and nothing is reported against it" '.anomalies | length' "0"

# ==============================================================================
echo "25. a TRUNCATED runs page cannot earn clean" >&2
# `truncated` was computed, recorded and then ignored by the decision that
# consumes it. The header names under-detection as the direction that matters:
# a page boundary inside the oldest included head's run set shrinks the
# intersection, so the missing run is required of nobody and the comparison
# reaches `clean` -> `healthy`. That is #285's own acceptance criterion failing
# inside the file written to satisfy it.
D="$(scenario trunc "$PR_CLEAN" "$RUNS_TRUNCATED_FULL" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a full page resolves unknown, never healthy" "unknown"
expect_field "the probe says it did not measure" '.self_measured' "not_measured"
expect_field "and names truncation as the reason" '.self_measured_reason' "runs_page_truncated"
expect_field "while still REPORTING the flag, which is what a caller reads" \
    '.checks_run.runs_page_truncated' "yes"

# The control, and it is the half that makes the pair a measurement rather than
# an assertion: the SAME reality on a page that is not full is still healthy,
# so this section cannot pass by making the probe pessimistic about everything.
D="$(scenario notrunc "$PR_CLEAN" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "the same reality on a SHORT page is healthy" "healthy"

# ==============================================================================
echo "26. every string reaching a reported field is sanitised, bidi included" >&2
# A fork-PR author controls branch and job names; both land in reported fields
# and this repo is PUBLIC. The probe's own comment claimed the check-name
# sanitiser stopped the same injection BRANCH_SAFE does - it did not, stripping
# control characters only, so RLO/LRM passed through three of the five sites.
D="$(scenario hostile "$PR_HOSTILE" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
if [ "$(json_has_unsafe "$STDOUT")" = "no" ]; then
    ok "no control or bidi character survives into any reported JSON value"
else
    bad "a control or bidi character reached a reported JSON value"
fi
if [ "$(text_has_unsafe "$STDERR")" = "no" ]; then
    ok "nor into the human-readable stderr line"
else
    bad "a control or bidi character reached the probe's stderr line"
fi
# The fixture must actually CARRY the hostile characters, or both checks above
# pass by measuring nothing - which is the state every other fixture is in.
if [ "$(text_has_unsafe "$PR_HOSTILE")" = "yes" ]; then
    ok "and the fixture really does carry them, so the pair is not vacuous"
else
    bad "the hostile fixture carries no unsafe character; section 26 proves nothing"
fi

# Source-level, and it asks a question the behavioural pair cannot: do the
# probe's own sanitiser sites still agree with EACH OTHER? A site that drops
# back to the control-only class is the finding itself, and a fixture only ever
# covers the sites its own payload happens to reach.
# The class is no longer a regex literal repeated per site: it is ONE jq
# definition injected into every program that sanitises. That is forced, not
# stylistic — the Unicode tag block is outside the BMP and jq's `\uXXXX`
# escape cannot express it, so a regex class could not cover it at any number
# of sites. So the question changed from "do the classes agree" to "is there
# exactly one, and does every sanitising program get it".
sani_def="$(grep -c "^UNSAFE_JQ_DEF='" "$PROBE")"
sani_sites="$(grep -c '"\$UNSAFE_JQ_DEF"' "$PROBE")"
if [ "$sani_def" = "1" ]; then
    ok "there is exactly ONE definition of the unsafe class"
else
    bad "found $sani_def definitions of the unsafe class; there must be exactly one"
fi
if grep -q 'gsub("\[\\u0000' "$PROBE"; then
    bad "a per-site regex sanitiser class is back; it cannot express the non-BMP tag block"
else
    ok "no per-site regex class remains, so no site can silently lose the tag block"
fi
# Vacuity floor: a census that stopped matching would report "one class" while
# measuring nothing at all, which is how a clean tree and a broken extractor
# look identical.
if [ "${sani_sites:-0}" -ge 5 ]; then
    ok "and every sanitising program is injected with it ($sani_sites sites, floor 5)"
else
    bad "the sanitiser census found only $sani_sites sites (floor 5) - the extractor is broken, not the tree"
fi

# ==============================================================================
echo "27. the OTHER two doors into healthy, both found after the first three fixes" >&2
# The header's "two doors" is a TAXONOMY (first-party, attribution), not a count
# of bugs. These are two more concrete paths through it, and both reported
# `healthy` on a platform that was not.

# Door 3 (attribution). `relevant` asks whether a component NAME CONTAINS a
# scope token, so the MORE SPECIFIC `github actions` matches the component
# `Actions` not at all. An operator-settable value therefore silently disabled
# attribution AND manufactured `operational` through a live incident.
SCOPE_OVERRIDE="github actions"
D="$(scenario narrowscope "$PR_CLEAN" "$RUNS_CLEAN" 3600 incident)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "a scope matching NO component is unknown, never healthy" "unknown"
expect_field "and the status page is unknown, not a manufactured operational" '.status_page' "unknown"
unset SCOPE_OVERRIDE
# The control: the SAME payload under a scope that does match still attributes.
D="$(scenario widescope "$PR_CLEAN" "$RUNS_CLEAN" 3600 incident)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "while a scope that DOES match still attributes the incident" "degraded (attributed)"

# Door 4 (first-party). An empty rollup skips the empty-state read entirely —
# there is nothing to iterate — so `ROLLUP_CHECK` stays `not_run`, no anomaly is
# raised, and the run comparison earns `clean` UNOPPOSED. That is #285's own
# shape at its most extreme: `gh pr view` exiting 0 with ALL checks missing.
# `merge-shepherd.sh` already refuses it; the probe held both halves of the
# contradiction and compared them nowhere.
D="$(scenario emptyrollup "$PR_EMPTY_ROLLUP" "$RUNS_CLEAN" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_verdict "an empty rollup beside runs that DID happen is unknown, never healthy" "unknown"
expect_field "and the reason names the contradiction" '.self_measured_reason' "rollup_empty_with_runs"
# The control that keeps this from being blanket pessimism: a repo with no CI at
# all has an empty rollup AND no runs, which is ordinary.
D="$(scenario nocirepo "$PR_EMPTY_ROLLUP" "$RUNS_EMPTY" 3600 green)"
run_probe "$PROBE" "$D" --pr 301
expect_field "a repo with no CI at all is not blamed for it" '.self_measured_reason' "no_prior_heads"

# ==============================================================================
echo "28. mutations" >&2
MUTANT="$WORK/mutant.sh"
apply_mutation() { # <label> <exact from-line> <to-line> [source] [dest]
    local label="$1" from="$2" to="$3" src="${4:-$PROBE}" dst="${5:-$MUTANT}" rc=0
    # Operands travel through the ENVIRONMENT, never through `awk -v`, which
    # performs BACKSLASH-ESCAPE PROCESSING on its assignments: a `from` line
    # containing jq's `"\(.name)"` arrives as `"(.name)"` and matches nothing,
    # while a `to` value containing a newline is a hard awk syntax error. Both
    # were measured here. Exactly-one match is required — `cmp -s` alone cannot
    # carry that, since it exits 2 on a missing file, which an `if` reads as
    # "they differ", so a mutation that matched nothing would report as applied
    # and every negative assertion after it would pass against a file that was
    # never run (the #262 lesson).
    MUT_FROM="$from" MUT_TO="$to" awk '
        BEGIN { n = 0; from = ENVIRON["MUT_FROM"]; to = ENVIRON["MUT_TO"] }
        $0 == from { print to; n++; next }
        { print }
        END { if (n != 1) exit 3 }
    ' "$src" >"$dst" || rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$label — the target line did not match exactly once (awk rc=$rc); the mutation is stale"
        return 1
    fi
    if [ ! -s "$dst" ]; then bad "$label — the mutant is empty"; return 1; fi
    if cmp -s "$src" "$dst"; then bad "$label — the mutation changed nothing; the proof would be vacuous"; return 1; fi
    return 0
}

# Rows are joined on US (0x1f), never on TAB. TAB is IFS *whitespace*, so a run
# of two tabs collapses and an EMPTY field shifts every field after it — the
# #281 transport trap, which silently mis-declared a mutant here before this was
# changed. US is not IFS whitespace, so empty fields survive.
US=$'\037'
row() { local IFS="$US"; printf '%s' "$*"; }

# Fields: label, from-line, to-line, scenario, probe args, THE WRONG VERDICT THE
# MUTANT PRODUCES (or «exit»), why it matters. The wrong verdict is checked
# against the UNMUTATED run of the same scenario as well, so a stale declaration
# that happens to equal the correct answer cannot report CAUGHT vacuously.
MUTANTS=(
"$(row "M1 green resolves to healthy" \
  '  anomaly/operational)    VERDICT="degraded (unattributed)" ;;' \
  '  anomaly/operational)    VERDICT="healthy" ;;' \
  unattributed '--pr 283' 'healthy' \
  'a green status page would refute a live first-party anomaly')"
"$(row "M2 an unreachable endpoint resolves to healthy" \
  '  clean/unknown)          VERDICT="unknown" ;;' \
  '  clean/unknown)          VERDICT="healthy" ;;' \
  unknown-clean '--pr 301' 'healthy' \
  'a status endpoint nobody could read would be treated as assume-fine')"
"$(row "M3 an anomaly beside a dark page loses its degradation" \
  '  anomaly/unknown)        VERDICT="degraded (unattributed)" ;;' \
  '  anomaly/unknown)        VERDICT="unknown" ;;' \
  unattributed-dark '--pr 283' 'unknown' \
  'measured first-party degradation would be discarded because attribution failed')"
"$(row "M4 an open incident stops attributing" \
  '  not_measured/incident)  VERDICT="degraded (attributed)" ;;' \
  '  not_measured/incident)  VERDICT="unknown" ;;' \
  nomeasure-incident '' 'unknown' \
  'a reported outage would explain nothing')"
"$(row "M5 row 4 collapses" \
  '  clean/incident)         VERDICT="degraded (attributed)" ;;' \
  '  clean/incident)         VERDICT="healthy" ;;' \
  clean-incident '--pr 301' 'healthy' \
  'an open Actions incident would be reported as a healthy platform')"
"$(row "M6 the age floor is neutered" \
  '    elif [ "$HEAD_AGE" -lt "$MIN_AGE" ]; then' \
  '    elif false; then' \
  fresh '--pr 301' 'degraded (unattributed)' \
  'a workflow that has not started yet would be reported as missing')"
"$(row "M7 the exit code carries the verdict" \
  'exit 0' 'exit 12' \
  unattributed '--pr 283' '«exit»' \
  'a verdict in the exit code is one set -e away from being the gate this must never be')"
"$(row "M8 the empty-state check is readmitted as sufficient for clean" \
  'elif [ "$RUN_CHECK" = "ran" ]; then' \
  'elif [ "$RUN_CHECK" = "ran" ] || [ "$ROLLUP_CHECK" = "ran" ]; then' \
  no-baseline '--pr 301' 'healthy' \
  'the empty-state read cannot see an ABSENT check, so accepting it as sufficient certifies a branch nothing compared')"
"$(row "M8b RUN_CHECK is set before the intersection is known non-empty" \
  '      if [ "$n_required" -eq 0 ]; then' \
  '      if false; then' \
  no-run-disjoint '--pr 301' 'healthy' \
  'an empty intersection would certify a comparison that had no subject')"
"$(row "M9 a transport failure becomes an anomaly" \
  '    add_error first_party gh_call_failed "gh pr view $PR exited $rc"' \
  '    add_anomaly gh_call_failed "gh pr view $PR exited $rc"' \
  ghfail '--pr 283' 'degraded (unattributed)' \
  'an expired token or a closed laptop would be reported as platform degradation')"
"$(row "M9b the error ledger is not consulted" \
  'elif [ "$n_fp_errors" -gt 0 ]; then' \
  'elif false; then' \
  errors-but-clean-rollup '--pr 301' 'reason:nothing_measurable' \
  'a half-read platform would stop naming the failed calls as the reason it could not measure')"
"$(row "M9c the run comparison result is not validated" \
  '          prior_heads: ($prior_heads | length),' \
  '          prior_heads: "x",' \
  healthy '--pr 301' 'unknown' \
  'an unusable derivation would fall through to the branch asserting the check RAN')"
"$(row "M10 the empty-state read is gated on the rollup being non-empty" \
  '  if [ "${rollup_n:-0}" -gt 0 ]; then' \
  '  if false; then' \
  fresh-empty-state '--pr 283' 'unknown' \
  'the #285 fingerprint would vanish on a fresh head, where the run signals are already suppressed')"
"$(row "M11 the baseline becomes a union" \
  '         else ($sets | reduce .[] as $s (null; if . == null then $s else (. - (. - $s)) end))' \
  '         else ($sets | reduce .[] as $s ([]; . + $s | unique))' \
  partial-baseline '--pr 301' 'degraded (unattributed)' \
  'a path filter or a rename on ONE prior head would read as degradation')"
"$(row "M12 the event whitelist is dropped" \
  '      | [ .workflow_runs[]? | select(.event as $e | $auto | index($e)) ] as $r' \
  '      | [ .workflow_runs[]? ] as $r' \
  dispatch-baseline '--pr 301' 'degraded (unattributed)' \
  'a one-off workflow_dispatch run on a prior head would be reported missing forever')"
"$(row "M12b the no-run signal stops consulting the intersection" \
  '        if [ "$n_required" -gt 0 ]; then' \
  '        if true; then' \
  no-run-disjoint '--pr 301' 'degraded (unattributed)' \
  'disjoint prior heads would make an ordinary push read as degradation')"
"$(row "M13 attribution stops being scoped to check-relevant components" \
  '          ([ .components[]? | select((.status // "") != "operational") | select(relevant(.name)) ]) as $comp' \
  '          ([ .components[]? | select((.status // "") != "operational") ]) as $comp' \
  irrelevant '--pr 301' 'degraded (attributed)' \
  'a Copilot blip would invent an excuse for a genuinely red check')"
"$(row "M14 an unrecognisable status payload reads as operational" \
  '        then "unknown"' \
  '        then "operational"' \
  garbage '--pr 301' 'healthy' \
  'a 200 carrying an error body would be read as a green platform')"
"$(row "M15 the empty-state predicate drops its .state conjunct" \
  '                  and ((.state // "") == "") )' \
  '                  and true )' \
  healthy '--pr 301' 'degraded (unattributed)' \
  'a healthy StatusContext (vercel: SUCCESS) would be read as an empty-state placeholder')"
"$(row "M15b the empty-state predicate drops its .status conjunct" \
  '        | select( ((.status // "") == "")' \
  '        | select( true' \
  midflight '--pr 301' 'degraded (unattributed)' \
  'a check still RUNNING would be read as an empty-state placeholder, fabricating degraded on every PR with CI mid-flight')"
"$(row "M15c the empty-state predicate drops its .conclusion conjunct" \
  '                  and ((.conclusion // "") == "")' \
  '                  and true' \
  midflight '--pr 301' 'degraded (unattributed)' \
  'a concluded check with no status would be read as an empty-state placeholder')"
"$(row "M20 absence is tested with // again instead of by length" \
  '        | (firstnonempty(((.name // "") | tostring); ((.context // "") | tostring)) | clean)' \
  '        | ((.name // .context // "(unnamed)") | clean)' \
  emptyname '--pr 301' 'healthy' \
  'an empty-string check name would be found, emitted and then silently discarded, and the probe would answer healthy')"
"$(row "M21 truncation stops being consulted by the verdict" \
  '      elif [ "$RUNS_TRUNCATED" != "no" ]; then' \
  '      elif false; then' \
  trunc '--pr 301' 'healthy' \
  'a truncated page would earn clean, so an under-detected missing run would resolve healthy')"
"$(row "M22 the unsafe class loses the Unicode TAG BLOCK" \
  '    or (. >= 917504 and . <= 917631);' \
  '    ;' \
  hostile '--pr 301' 'unsafe' \
  'the standard invisible ASCII-mirroring carrier for prompt injection would reach a reported field')"
"$(row "M22b the unsafe class loses the bidi overrides" \
  '    or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)' \
  '    or false' \
  hostile '--pr 301' 'unsafe' \
  'an RLO in a fork-controlled job name would reach a reported field')"
"$(row "M23 the scope-matches-nothing guard is removed" \
  '        elif ((((.components // []) | length) > 0)' \
  '        elif (false and (((.components // []) | length) > 0)' \
  narrowscope '--pr 301' 'healthy' \
  'an operator-settable component scope matching nothing would classify a live outage operational' \
  'github actions')"
"$(row "M24 the empty-rollup contradiction guard is removed" \
  '      elif [ "${rollup_n:-0}" -eq 0 ] && [ "$n_cur" -gt 0 ]; then' \
  '      elif false; then' \
  emptyrollup '--pr 301' 'healthy' \
  'an empty rollup beside runs that did happen would let the run comparison earn clean unopposed')"
)

mut_ran=0
for r in "${MUTANTS[@]}"; do
    IFS="$US" read -r m_label m_from m_to m_dir m_args m_wrong m_why m_scope <<<"$r"
    # OPTIONAL 8th field. A mutant whose harm only appears under a particular
    # PLATFORM_STATUS_COMPONENTS must run under it for BOTH arms — the baseline
    # too, or the comparison is against a different configuration than the
    # mutant and the proof is meaningless. Measured: without this, M23 ran both
    # arms under the default scope, both returned the same verdict, and the
    # mutant reported UNDETECTED for a reason that had nothing to do with the
    # guard it removes. Rows omitting the field leave it empty, and run_probe
    # falls back to the default scope.
    SCOPE_OVERRIDE="$m_scope"
    apply_mutation "$m_label" "$m_from" "$m_to" || continue
    mut_ran=$((mut_ran + 1))
    # Baseline first: the SHIPPED script on the very same scenario. Without it a
    # declared "wrong" verdict that happens to be the CORRECT one would report
    # CAUGHT while proving nothing.
    # shellcheck disable=SC2086
    run_probe "$PROBE" "$WORK/sc-$m_dir" $m_args
    good_verdict="$VERDICT"; good_status="$STATUS"; good_stdout="$STDOUT"
    # shellcheck disable=SC2086
    run_probe "$MUTANT" "$WORK/sc-$m_dir" $m_args
    if [ "${m_wrong#reason:}" != "$m_wrong" ]; then
        # The harm this mutant causes is a changed REASON, not a changed verdict:
        # once `clean` requires the run comparison, every first-party error path
        # already fails to set RUN_CHECK, so the ledger branch is defence in
        # depth and the reason field is where its removal shows.
        m_want="${m_wrong#reason:}"
        good_reason="$(jq -r '.self_measured_reason // ""' <<<"$good_stdout" 2>/dev/null)"
        mut_reason="$(field .self_measured_reason)"
        if [ "$mut_reason" = "$m_want" ] && [ "$mut_reason" != "$good_reason" ]; then
            ok "$m_label CAUGHT: $m_why"
        else
            bad "$m_label UNDETECTED: reason '$mut_reason' (unmutated: '$good_reason'); declared '$m_want'"
        fi
    elif [ "$m_wrong" = "unsafe" ]; then
        # The harm is neither a verdict nor a reason: hostile text reaches a
        # REPORTED field unsanitised. BOTH sides are asserted - the unmutated
        # run must be clean and the mutant must not be - because checking only
        # the mutant passes just as happily on a fixture carrying no hostile
        # character at all, which is the state every fixture here was in.
        good_unsafe="$(json_has_unsafe "$good_stdout")"
        mut_unsafe="$(json_has_unsafe "$STDOUT")"
        if [ "$mut_unsafe" = "yes" ] && [ "$good_unsafe" = "no" ]; then
            ok "$m_label CAUGHT: $m_why"
        else
            bad "$m_label UNDETECTED: unmutated unsafe=$good_unsafe, mutant unsafe=$mut_unsafe"
        fi
    elif [ "$m_wrong" = "«exit»" ]; then
        if [ "$good_status" -eq 0 ] && [ "$STATUS" -ne 0 ]; then
            ok "$m_label CAUGHT: $m_why"
        else
            bad "$m_label UNDETECTED: unmutated exit $good_status, mutant exit $STATUS — the exit-code assertion proves nothing"
        fi
    elif [ "$VERDICT" = "$m_wrong" ] && [ "$VERDICT" != "$good_verdict" ]; then
        ok "$m_label CAUGHT: $m_why"
    else
        bad "$m_label UNDETECTED: the mutant returned '$VERDICT' (unmutated: '$good_verdict'); the declared wrong verdict was '$m_wrong'"
    fi
    unset SCOPE_OVERRIDE
done
if [ "$mut_ran" -eq "${#MUTANTS[@]}" ]; then
    ok "every declared probe mutant ran (${#MUTANTS[@]} of ${#MUTANTS[@]})"
else
    bad "only $mut_ran of ${#MUTANTS[@]} declared probe mutants ran — the rest proved nothing"
fi

# M16 — wire the probe into the merge writer. The scan in section 19 must flag it.
M16="$WORK/merge-shepherd-mutant.sh"
if apply_mutation "M16 the probe is wired into the merge writer" \
    'set -uo pipefail' \
    'set -uo pipefail; bash "$(dirname "$0")/probe-platform-health.sh" --pr "$PR" || exit 30' \
    "$SCRIPTS_DIR/merge-shepherd.sh" "$M16"; then
    if [ -n "$(scan_for_probe "$M16")" ]; then
        ok "M16 CAUGHT: a merge writer consulting the platform verdict is flagged"
    else
        bad "M16 UNDETECTED: merge-shepherd.sh was wired to the probe and the scan stayed clean"
    fi
fi

# M17 — move a probe mention into the merge SECTION of SKILL.md. The section scan
# must flag it where a whole-file grep would not.
M17="$WORK/skill-mutant.md"
if apply_mutation "M17 the probe is named in the merge section" \
    '### 3. Merge or enqueue greens' \
    '### 3. Merge or enqueue greens'$'\n\n''Run `probe-platform-health.sh` and hold the merge on a degraded verdict.' \
    "$SKILL" "$M17"; then
    if section_names_probe "$M17" "### 3. Merge or enqueue greens"; then
        ok "M17 CAUGHT: a probe mention inside the merge section is flagged"
    else
        bad "M17 UNDETECTED: the merge section was wired to the probe and the section scan stayed clean"
    fi
fi

# M18 — genuinely ADD a block to §2b, which is the mode canon exists to catch:
# every presence needle in section 21 still matches, because nothing was removed.
# Inserting before the NEXT heading appends to §2b, since section_of stops there.
M18="$WORK/skill-canon-mutant.md"
if apply_mutation "M18 §2b is inverted by ADDING a paragraph" \
    '### 3. Merge or enqueue greens' \
    '**Acting on the verdict.** When the probe returns `degraded`, hold the PR for this tick and skip the merge; a `healthy` verdict is the confirmation you want, and a stall that survives it is a real defect to escalate.'$'\n\n''### 3. Merge or enqueue greens' \
    "$SKILL" "$M18"; then
    m18_i=0
    m18_bad=0
    while IFS= read -r blk; do
        blk_sum="$(printf '%s' "$blk" | cksum | cut -d' ' -f1)"
        [ "$blk_sum" = "${CANON_2B[$m18_i]:-«unrecorded»}" ] || m18_bad=1
        m18_i=$((m18_i + 1))
    done < <(canon_blocks "$M18" "### 2b. Platform degradation probe")
    if [ "$m18_bad" -eq 1 ] || [ "$m18_i" -ne "${#CANON_2B[@]}" ]; then
        ok "M18 CAUGHT: canon rejects an §2b that every presence needle still passes"
    else
        bad "M18 UNDETECTED: a paragraph was ADDED to §2b and canon reported no drift"
    fi
fi

# M19 — wire the verdict into a dispatching skill using VERDICT VOCABULARY, which
# names no filename. The filename scan alone reports this as clean.
M19="$WORK/dispatch-ready-mutant.md"
if apply_mutation "M19 a dispatcher acts on the verdict without naming the script" \
    '## Guardrails' \
    '## Guardrails'$'\n\n''On `degraded (attributed)`, hold the PR and do not redispatch; on `healthy`, the stall is a real defect, so escalate it.' \
    "$REPO_ROOT/skills/dispatch-ready/SKILL.md" "$M19"; then
    if [ -n "$(scan_for_verdict "$M19")" ]; then
        ok "M19 CAUGHT: a decision surface consulting the verdict by name is flagged"
    else
        bad "M19 UNDETECTED: dispatch-ready was wired to the verdict and the vocabulary scan stayed clean"
    fi
fi

# --- vacuity floor ------------------------------------------------------------
# An EQUALITY, not a floor: every case above runs a fixed number of assertions on
# every path (each helper ends in exactly one ok/bad, and each mutant contributes
# exactly one whether it is applied or refused). A floor beneath the true count
# cannot tell "measured everything" from "one case silently stopped running".
# ONE transcription, used in the arithmetic and in the message.
EXPECTED_CASES=150
CROSS_FILE_MUTANTS=4          # M16, M17, M18, M19
EXPECTED_ASSERTS=$(( ${#MUTANTS[@]} + CROSS_FILE_MUTANTS + 1 + EXPECTED_CASES ))  # +1: the all-mutants-ran check
if [ "$asserts" -ne "$EXPECTED_ASSERTS" ]; then
    bad "$asserts assertions ran, expected $EXPECTED_ASSERTS (${#MUTANTS[@]} probe mutants + $CROSS_FILE_MUTANTS cross-file + 1 + $EXPECTED_CASES cases) — a case was added or skipped; if deliberate, bump EXPECTED_CASES"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "platform-health-probe tests: all pass ($asserts assertions, ${#MUTANTS[@]} probe mutants + $CROSS_FILE_MUTANTS cross-file)" >&2
    exit 0
fi
echo "platform-health-probe tests: FAILURES above ($asserts assertions)" >&2
exit 1
