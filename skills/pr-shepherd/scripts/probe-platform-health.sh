#!/usr/bin/env bash
# probe-platform-health.sh — "is the platform degraded right now, or is this a
# real defect?", answered as a structured verdict a caller REPORTS.
#
# WHY THIS EXISTS. A hard `gh` error is already handled everywhere — an
# API-failure tick proves nothing and the callers know it. What was not handled
# is a `gh` call that SUCCEEDS and returns incomplete data, which the caller
# then reads as live state. Measured 2026-08-26 on this repo's PR #283 during a
# platform outage: `gh pr view 283 --json statusCheckRollup` exited 0 with two
# entries and no `ci`; `gh run list` for that head returned no `CI` run at all
# across ~40 minutes while the two PRIOR heads on the same branch had one within
# minutes; `mergeStateStatus` read `BLOCKED`; later `ci` appeared in the rollup
# with an EMPTY state and still no run behind it. Nothing errored. The
# coordinator produced three hypotheses — Actions queueing, a path filter, a
# transient miss — all three wrong, and proposed closing and reopening the PR,
# which during an outage could have made it worse. The real cause was known only
# because the operator said so.
#
# THE ASYMMETRY IS THE WHOLE DESIGN, and it is the part a later "simplify the
# verdicts" sweep will flatten:
#
#     red explains a stall. GREEN EXPLAINS NOTHING, and says so in those words.
#
# A green status page is NOT evidence of health. githubstatus.com lags real
# degradation by minutes to tens of minutes and routinely under-reports partial
# Actions failures. So the probe may only ever ADD an explanation. If a caller
# reads green and concludes "so this is a real defect — escalate", the probe is
# WORSE than not having one: it converts an unknown into a confident wrong
# answer. The self-measured signal is what is load-bearing; the status page
# answers a different question — is it them or us — and answers it late.
#
# NEVER A GATE. This changes what a tick SAYS, not what it DOES. The verdict
# must appear in no merge, hold, block or redispatch decision. A PR missing a
# required check is held either way — the hold was already correct, the
# ATTRIBUTION was what was missing. Worth recording why the merge path is the
# least exposed surface: branch protection is enforced SERVER-SIDE, so a PR
# missing a required check is refused by GitHub itself and not by this loop's
# reading of it. The cost of degradation here is wasted work and wrong
# escalations, not bad merges.
#
# THE EXIT CODE CARRIES NO VERDICT, DELIBERATELY. Every one of the four verdicts
# exits 0; only a usage error exits non-zero. This is a deliberate ASYMMETRY
# with stack-probe.sh, whose exit codes ARE a gate (23/24 in merge-shepherd.sh)
# because that is its job — and aligning the two is exactly the tidy to refuse.
# A verdict in an exit code is one `set -e`, one `&&`, or one `if` away from
# being the gate this must never be, and that wiring would be invisible in
# review. Structure it out instead of forbidding it in prose.
#
# Usage:
#   probe-platform-health.sh [--pr <n>] [--repo owner/name]
#                            [--status-url <url>] [--min-age <secs>]
#   Repo defaults to the cwd checkout (gh repo view); --repo overrides.
#   With no --pr there is NO first-party measurement, so a green page yields
#   `unknown` rather than `healthy` — see the table below.
#
# Env:
#   PLATFORM_STATUS_URL        attribution endpoint
#                              (default https://www.githubstatus.com/api/v2/summary.json)
#   PLATFORM_STATUS_TIMEOUT    seconds for that fetch (default 5)
#   PLATFORM_GH_TIMEOUT        seconds any ONE `gh` call may take (default 30),
#                              applied with `timeout`/`gtimeout` when either is
#                              on PATH — see the bound's own paragraph below.
#   PLATFORM_PROBE_MIN_AGE     head-age floor in seconds (default 300) — below it
#                              the run-COMPARISON signals are SUPPRESSED, because
#                              a workflow that has not started yet is not
#                              missing, and firing on a fresh push manufactures
#                              exactly the confident wrong answer this exists to
#                              prevent.
#   PLATFORM_STATUS_COMPONENTS comma-separated, lower-cased substrings of the
#                              status-page components that can plausibly explain
#                              missing CHECK data (default below). Scoping is not
#                              optional: githubstatus.com carries a dozen
#                              components, and treating a Copilot or Codespaces
#                              blip as an explanation for a red `ci` invents an
#                              excuse for a genuine failure — the same
#                              confident-wrong-answer this file exists to refuse,
#                              pointed the other way.
#
# THE FOUR VERDICTS. They are four distinct answers and collapsing any pair
# re-creates the bug:
#
#   first-party      status page     verdict
#   -----------      -----------     -------
#   anomaly          incident        degraded (attributed)
#   anomaly          operational     degraded (unattributed)   <- never healthy
#   anomaly          unknown         degraded (unattributed)   <- never healthy
#   clean            incident        degraded (attributed)
#   clean            operational     healthy
#   clean            unknown         unknown                   <- never healthy
#   not measured     incident        degraded (attributed)
#   not measured     operational     unknown                   <- never healthy
#   not measured     unknown         unknown
#
# AN UNREACHABLE STATUS ENDPOINT NEVER MANUFACTURES A VERDICT OF ITS OWN. It
# contributes `unknown` and nothing else: it can never produce `healthy` (a
# verifier that degrades to "assume fine" is worth nothing on the day it
# matters — the verify-gotcha-claims.sh rule) and it can never on its own
# produce `degraded` (rows 6, 8 and 9 above). Where it appears beside a
# first-party anomaly (row 3) the DEGRADATION was measured first-party and only
# the attribution is missing, which is what the word "unattributed" means — the
# vocabulary has no fifth value for it, and a page you could not read adds
# exactly as much as a page that is green, which is nothing. Read row 3 and row
# 6 together before "aligning" either one.
#
# `clean` MEANS SOMETHING WAS MEASURED AND CAME BACK CLEAN — NEVER "NOTHING WAS
# LOOKED AT". This is the FIRST-PARTY door into `healthy`, and it is the one an
# earlier edition of this script left open: a single-commit PR branch has no
# prior head to compare against, so the run comparison had no baseline, found
# nothing, and reported `clean` -> `healthy` on a branch whose CI had never
# started. That is #285 one step EARLIER than the incident it was written for,
# and the dominant branch shape in this org. So each first-party check reports
# whether it could RUN. ONLY THE RUN COMPARISON EARNS `clean` -- the sentence
# that used to stand here said `clean` requires that "at least one of them did"
# and then listed BOTH checks, which is the exact inverse of the rule four lines
# below it, in the same paragraph. A reader who stopped at the list concluded
# the empty-state check could earn `clean`, which is the door the rule exists to
# nail shut. `ROLLUP_CHECK` is REPORTED in `checks_run` and contributes
# anomalies; it is consulted by no verdict path at all.
# The run comparison earns `clean` only with at least one prior head on the
# branch, a non-empty intersection across them (an empty one compared nothing),
# a head past the age floor, an untruncated runs page, and a rollup that is not
# empty while runs exist on this head. The empty-state check is a real signal
# but it detects a MALFORMED rollup entry and can never detect an ABSENT one —
# which is #285's headline signal — so a rollup that simply lacks `ci` looks
# identical to a healthy one through it. Accepting it as sufficient left this
# door open on the exact shape the probe was written for: measured, #285's own
# rollup on a single-commit branch reported `healthy`.
# Not earned -> `not_measured`, whose green-page row is `unknown`, and the
# REASON is preserved rather than blanked — `no_prior_heads`,
# `no_required_baseline`, `head_too_fresh`, `runs_page_truncated`,
# `rollup_empty_with_runs`, `head_age_unknown`, `run_comparison_failed`,
# `pr_read_failed`, `probe_errors_present`, `verdict_emitter_failed`,
# `no_pr_given` and `nothing_measurable` are precisely why the verdict is not a
# measurement. That list is the full set the code emits; if you add a reason,
# add it here.
#
# A gh TRANSPORT FAILURE IS `not_measured`, NOT AN ANOMALY, and this is a
# deliberate reading of #285 rather than a slip. #285 lists "gh calls erroring
# or returning structurally incomplete payloads" among the first-party signals,
# and a *semantically* incomplete payload — a rollup missing a check, an entry
# with no state — is exactly that and is treated as an anomaly below. But a call
# that FAILS, or comes back unparsable, or omits the key it was asked for,
# cannot distinguish a platform fault from an expired token, a rate limit or a
# closed laptop. Reporting a local auth failure as "the platform is degraded" is
# the confident wrong answer this file exists to refuse, so a transport failure
# records itself in `probe_errors`, makes the run `not_measured`, and lets the
# status page decide the row. The cost is stated: during a real outage that also
# breaks gh, a green page yields `unknown` rather than `degraded`. `unknown`
# explains nothing, which is the truth — we do not know.
#
# EVERY `gh` CALL IS BOUNDED, AND A TIMED-OUT CALL IS A TRANSPORT FAILURE. The
# probe's entire trigger condition is "GitHub may be degraded right now", and
# an edition of this file left the three LOAD-BEARING calls (`gh pr view`, the
# commit read, the `actions/runs` read) unbounded while bounding the OPTIONAL
# attribution fetch — the one its own header calls never load-bearing. A hang
# there costs the caller its whole tick, and the caller is a loop. So every
# `gh` call goes through `gh_bounded`, which prefixes `timeout`/`gtimeout` when
# either is on PATH. `timeout` reports a fired bound as exit 124, which lands
# in the SAME `gh_call_failed` path as any other non-zero exit: `not_measured`,
# NEVER an anomaly. That is not a shortcut — it is the transport-failure rule
# above applied unchanged, and it is the reading to keep: a call we cut off
# ourselves tells us even less about the platform than one that errored.
# Where NEITHER binary is on PATH the calls run exactly as they did before and
# the probe records `timeout_unavailable` in `probe_errors`, because a bound
# that silently did not apply is the same "silence read as an answer" this file
# exists to refuse. That entry is scoped `probe`, not `first_party`: the calls
# still ran and their results are as trustworthy as they ever were, so folding
# it in would turn every run on a host without coreutils into `not_measured`.
#
# THE EMITTER CANNOT EXIT 0 WITH EMPTY STDOUT. The final `jq -n` used to run
# with no handler under a script with no `set -e` and an unconditional
# `exit 0`, so a dead emitter handed the caller exit 0 and NO output —
# `jq -r .verdict` then yields the empty string, which is not one of the four
# verdicts and is not `unknown` either, while the stderr summary line still
# printed and looked normal. Measured: `jq -n --argjson a "" '$a'` exits 2 and
# prints nothing, and `$ANOMALIES`/`$PROBE_ERRORS` are the only two emitter
# inputs nothing validates before use (the counts derived from them ARE
# defended, so the file already treats them as possibly unusable). The status
# is now captured and the output re-parsed before it is printed; on any failure
# a minimal HAND-BUILT `unknown` object is emitted instead. It carries no
# measured value at all — every field is a literal, because the measured values
# are precisely what could not be serialised — and it reports
# `verdict_emitter_failed` as both its reason and its `probe_errors` entry.
# It still exits 0: the no-verdict case is what a non-zero exit is reserved for,
# and this path HAS a verdict. Turning it into a non-zero exit would put a
# verdict in an exit code, which the paragraph above forbids.
#
# FIRST-PARTY SIGNALS (the load-bearing half; all are read-only):
#   missing_workflow_run  a (workflow, event) pair that ran on EVERY prior head
#                         of this branch has no run on the current head
#   no_run_for_head       prior heads carried runs; this head carries none
#   empty_state_check     a rollup entry with no status, no conclusion and no
#                         state — a CheckRun always has a status and a
#                         StatusContext always has a state, so all-three-empty
#                         is a placeholder, not a check that is running. It is
#                         a DIRECT read of the rollup, so it is neither
#                         age-suppressed nor conditional on the runs call —
#                         during an outage those are exactly what fail together.
#
# THE RUN COMPARISON IS RUN-TO-RUN, NOT ROLLUP-TO-RUN, AND THAT IS DELIBERATE.
# `statusCheckRollup` names CHECKS (for Actions, JOB names — "Analyze
# (actions)"), while `actions/runs` names WORKFLOWS ("CI"). They are different
# namespaces, so differencing one against the other reports a missing check for
# every workflow whose job names differ from its own name, on a perfectly
# healthy repo. Both sides of the difference therefore come from the SAME
# `actions/runs` payload, which is also exactly the comparison that was measured
# during the outage. The rollup is used only for the empty-state signal, which
# needs no cross-namespace comparison at all.
#
# THE BASELINE IS AN INTERSECTION, NOT A UNION, and the whitelist beside it is
# the other half of the same guard. A workflow legitimately absent from one head
# is ordinary: `paths:`/`paths-ignore:` filters (the norm in the monorepos this
# ships to), an `if:` condition. So
# a workflow counts as missing only if it ran on EVERY prior head examined and
# on none of the current one. And only head-triggered events are compared at
# all — a `workflow_dispatch` or `schedule` run on a prior head can never recur
# on this one, so a union-and-blacklist reading reports it missing forever.
# KNOWN LIMIT, stated rather than patched, and it has TWO shapes rather than
# one. (a) A path filter that matched every prior head and not this one still
# reports a missing run. (b) A workflow THIS VERY PR renames or deletes does
# too, and that shape was wrongly listed above as covered — the intersection
# guard makes a workflow ordinary when it is absent from SOME PRIOR head, and a
# deletion is absent from the CURRENT one, which is the opposite arrangement.
# Measured: prior heads running CI+Docs and a current head running CI only
# returns `degraded (unattributed)` naming `Docs`, i.e. the probe attributes the
# PR-s own change to the platform. Listing it as handled was worse than not
# mentioning it, because the next maintainer would not add it here. That is why this
# verdict is `unattributed` and why the probe gates nothing — a false positive
# costs an explanation, never a decision.
#
# PAGINATION IS A KNOWN LIMIT AND IT CUTS BOTH WAYS. One page of 100 runs,
# newest first, and BOTH directions are measured — an edition of this comment
# claimed each of them was the only one, so neither half may be deleted.
#   OVER-detect: dropping a whole prior head takes `required` from ["CI"] to
#     ["CI","Docs"] on a branch where a path filter had skipped that head, and
#     fabricates a missing-run anomaly.
#   UNDER-detect, and this WAS the direction that reached `healthy`: the page
#     boundary lands INSIDE the oldest included head's run set, so that head
#     contributes a TRUNCATED set, the intersection shrinks, and a genuinely
#     missing workflow drops out of `required`. Measured on two fixtures
#     differing ONLY in truncation, same underlying reality: the full page gave
#     `degraded (unattributed)` and the 100-run page gave `healthy`.
# That is now CLOSED. `truncated` was computed, reported, and then ignored by
# the one decision that consumes it, which is why recording it as a known limit
# was not enough. A truncated page no longer earns `clean`: it yields
# `not_measured` with reason `runs_page_truncated`. The test is `!= "no"` and
# not `= "yes"`, because `unknown` means the flag itself could not be read and
# certifies nothing either.
# `truncated` is still emitted, since suppressing the claim to completeness is
# not the same as hiding why. The ACCEPTED COST is real and is not a defect:
# on a branch with >= 100 head-triggered runs the probe can no longer emit
# `healthy` at all, only `unknown`. Over-detection is unchanged and still
# possible. Note also that `>= 100` against `per_page=100` cannot distinguish a
# complete 100-run page from a truncated one, so a branch sitting at exactly
# 100 is treated as truncated -- fail-closed, and deliberate.
#
# Read-only. Never merges, enqueues, re-runs, closes, reopens or comments.
#
# Emits one JSON object on stdout and a one-line human summary on stderr.
# Exit codes: 0 for EVERY verdict (see above) · 1 usage error.
set -uo pipefail

STATUS_URL="${PLATFORM_STATUS_URL:-https://www.githubstatus.com/api/v2/summary.json}"
STATUS_TIMEOUT="${PLATFORM_STATUS_TIMEOUT:-5}"
GH_TIMEOUT="${PLATFORM_GH_TIMEOUT:-30}"
MIN_AGE="${PLATFORM_PROBE_MIN_AGE:-300}"
STATUS_COMPONENTS="${PLATFORM_STATUS_COMPONENTS:-actions,api requests,webhooks,pull requests,git operations}"
REPO=""
PR=""

need_value() { # <flag> <remaining argc>
  # `shift 2` on a lone trailing flag shifts NOTHING (shift fails when it would
  # go past the end), so the while loop spins forever on `--status-url` with no
  # value. The caller here is an agent composing a command line inside a loop
  # tick, which makes a truncated flag realistic and a hang the worst possible
  # outcome for a diagnostic.
  if [ "$2" -lt 2 ]; then echo "error: $1 requires a value" >&2; exit 1; fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        need_value "$1" $#
                   [ -n "$2" ] || { echo "error: --repo requires owner/name" >&2; exit 1; }
                   REPO="$2"; shift 2 ;;
    --pr)          need_value "$1" $#
                   [ -n "$2" ] || { echo "error: --pr requires a PR number" >&2; exit 1; }
                   PR="$2"; shift 2 ;;
    --status-url)  need_value "$1" $#; STATUS_URL="$2"; shift 2 ;;
    --min-age)     need_value "$1" $#; MIN_AGE="$2"; shift 2 ;;
    -h|--help) sed -n '2,${/^#/!q; s/^# \{0,1\}//p;}' "$0"; exit 0 ;;
    *) echo "unexpected arg: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }

if [ -n "$PR" ]; then
  case "$PR" in *[!0-9]*|"") echo "error: --pr must be numeric, got: $PR" >&2; exit 1 ;; esac
fi
case "$MIN_AGE" in *[!0-9]*|"") echo "error: --min-age must be numeric seconds, got: $MIN_AGE" >&2; exit 1 ;; esac
case "$STATUS_TIMEOUT" in
  *[!0-9]*|""|0) echo "error: PLATFORM_STATUS_TIMEOUT must be a positive number of seconds, got: $STATUS_TIMEOUT" >&2; exit 1 ;;
esac
# Validated like every other knob, and for a sharper reason than tidiness: this
# value is the FIRST argument to `timeout`, so an unvalidated one is an argument
# injection into a command prefix. `0` is rejected rather than read as "no
# bound" — a bound that silently means unbounded is the shape this whole file
# refuses; drop `timeout` from PATH to get the unbounded behaviour, and the
# probe will say so in `probe_errors`.
case "$GH_TIMEOUT" in
  *[!0-9]*|""|0) echo "error: PLATFORM_GH_TIMEOUT must be a positive number of seconds, got: $GH_TIMEOUT" >&2; exit 1 ;;
esac
# The status URL reaches curl, so it is validated like any other argument. A
# value starting `-K` is read by curl as `--config` and can set `output`,
# `upload-file`, `header` or `proxy`; `file://` and `http://` are enabled by
# default and would put attacker-chosen text into a field the caller is told to
# report, in a repo that is PUBLIC by exception.
case "$STATUS_URL" in
  https://?*) : ;;
  *) echo "error: the status URL must be https://, got: $STATUS_URL" >&2; exit 1 ;;
esac

# Resolved BEFORE the repo lookup, because that lookup is a `gh` call too and a
# hang in it is a hang. `timeout` first, `gtimeout` second: on macOS the GNU
# binary installs under the `g` prefix, and a probe that is bounded on CI and
# unbounded on every developer laptop is the worse half of both worlds.
GH_TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then GH_TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then GH_TIMEOUT_CMD="gtimeout"
fi
gh_bounded() { # <gh args...> — the ONE place `gh` is invoked
  # PURE, deliberately: every call site runs this inside `$( )`, so an
  # `add_error` here would mutate PROBE_ERRORS in a SUBSHELL and the entry
  # would be silently discarded. The ledger is written by the callers.
  if [ -n "$GH_TIMEOUT_CMD" ]; then
    "$GH_TIMEOUT_CMD" "$GH_TIMEOUT" gh "$@"
  else
    gh "$@"
  fi
}
gh_rc_note() { # <rc> — names the bound when IT is what fired, and nothing otherwise
  # 124 is `timeout`'s "the bound fired" code. Naming it matters because `gh`
  # has no such exit code of its own, so an unannotated "exited 124" in the
  # ledger reads as an unexplained gh failure rather than as our own cutoff.
  if [ "$1" -eq 124 ] && [ -n "$GH_TIMEOUT_CMD" ]; then
    printf ' — the %ss PLATFORM_GH_TIMEOUT bound fired' "$GH_TIMEOUT"
  fi
  return 0
}

if [ -z "$REPO" ]; then
  REPO="$(gh_bounded repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "$REPO" ] || { echo "error: not in a GitHub repo and --repo not given" >&2; exit 1; }
fi
case "$REPO" in */*) : ;; *) echo "error: repo must be owner/name, got: $REPO" >&2; exit 1 ;; esac

ANOMALIES='[]'
PROBE_ERRORS='[]'
add_anomaly() { # <kind> <detail>
  ANOMALIES="$(jq -c --arg k "$1" --arg d "$2" '. + [{kind:$k, detail:$d}]' <<<"$ANOMALIES")"
}
add_error() { # <scope: first_party|attribution|probe> <kind> <detail>
  # SCOPE matters: only a FIRST-PARTY failure can make the run unmeasured. A
  # failed status fetch is an attribution failure, and folding it in would turn
  # every unreachable-endpoint run into `not_measured`, erasing the difference
  # between "I read your PR and it was clean" and "I read nothing".
  # `probe` is the third value and is neither: it reports on the probe's own
  # machinery — a bound that could not be applied, an emitter that died — where
  # the measurement itself is unaffected. It is recorded so the ledger is not
  # silent about it, and it is scoped OUT of the first-party count on purpose.
  PROBE_ERRORS="$(jq -c --arg s "$1" --arg k "$2" --arg d "$3" \
    '. + [{scope:$s, kind:$k, detail:$d}]' <<<"$PROBE_ERRORS")"
}
[ -n "$GH_TIMEOUT_CMD" ] || add_error probe timeout_unavailable \
  "neither timeout nor gtimeout is on PATH, so every gh call ran unbounded; PLATFORM_GH_TIMEOUT=$GH_TIMEOUT was not applied"

SELF="not_measured"
SELF_REASON="no_pr_given"
HEAD=""
# ONE definition of what may not reach a reported field, injected into every jq
# program that sanitises one. Written as CODEPOINTS rather than a regex class,
# and that is forced rather than stylistic: the Unicode TAG BLOCK
# (U+E0000-U+E007F) is the standard invisible ASCII-mirroring carrier for
# prompt injection, it lives OUTSIDE the BMP, and jq's `\uXXXX` escape cannot
# express a non-BMP codepoint at all -- so the regex class this replaces was
# structurally incapable of covering the one carrier that matters most here,
# no matter how carefully it was transcribed.
#
# A fork-PR author controls branch and job names; those reach `anomalies[].detail`
# and `head_ref`; SKILL.md tells the coordinator -- which holds merge authority --
# to REPORT that field; and this repo is PUBLIC by exception. Bidi alone was the
# wrong threat model.
#
# Covered: C0 (<32), DEL, U+0085 NEL, U+061C ALM, U+200E/U+200F, U+2028/U+2029
# line+paragraph separators, U+202A-U+202E bidi embedding/override,
# U+2066-U+2069 bidi isolates, U+E0000-U+E007F tag block.
# Each is REPLACED by a space, never deleted, so a sanitised value can never
# become empty and re-enter the empty-name path this file already closed once.
UNSAFE_JQ_DEF='def unsafe_cp: . < 32 or . == 127 or . == 133 or . == 1564
    or (. >= 8206 and . <= 8207) or (. >= 8232 and . <= 8233)
    or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)
    or (. >= 917504 and . <= 917631);
  def clean: explode | map(if unsafe_cp then 32 else . end) | implode;'

BRANCH=""
BRANCH_SAFE=""
HEAD_AGE=""
MERGE_STATE=""
pr_raw=""
# Did each first-party check actually get to run? `clean` requires at least one.
RUN_CHECK="not_run"
ROLLUP_CHECK="not_run"
RUNS_TRUNCATED="unknown"

# --- first-party measurement -------------------------------------------------
if [ -n "$PR" ]; then
  SELF_REASON=""
  rc=0
  pr_raw="$(gh_bounded pr view "$PR" --repo "$REPO" \
      --json number,headRefOid,headRefName,statusCheckRollup,mergeStateStatus 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    add_error first_party gh_call_failed "gh pr view $PR exited $rc$(gh_rc_note "$rc")"
    SELF_REASON="pr_read_failed"
  elif [ -z "$pr_raw" ] || ! jq -e . >/dev/null 2>&1 <<<"$pr_raw"; then
    add_error first_party incomplete_payload "gh pr view $PR exited 0 with no parsable JSON"
    SELF_REASON="pr_read_failed"
  else
    HEAD="$(jq -r '(.headRefOid // "") | gsub("[^0-9a-fA-F]"; "")' <<<"$pr_raw")"
    # BRANCH is used for TWO different things and needs both forms. The raw value
    # goes into the API query (URL-encoded at the call site); BRANCH_SAFE is what
    # reaches any reported string, because a fork-PR author controls it and a
    # bidi override or a newline in a reported field is the same injection the
    # check-name sanitiser exists to stop.
    #
    # THAT SENTENCE IS ONLY TRUE BECAUSE THE CLASSES WERE UNIFIED. It used to
    # assert a parity that did not exist: this site stripped control characters
    # AND bidi, while the check-name, missing-run and status-detail sanitisers
    # stripped control characters only, so a job name carrying RLO/LRM passed
    # through all three unchanged. Fork-PR authors control job names, those land
    # in `anomalies[].detail`, SKILL.md orders the coordinator to REPORT that
    # field, and this repo is PUBLIC. One class now covers every string that
    # reaches a reported field; a site that drops back to the control-only form
    # re-opens exactly that hole, so the gate compares the sites to each other.
    BRANCH="$(jq -r '.headRefName // ""' <<<"$pr_raw")"
    BRANCH_SAFE="$(jq -r "$UNSAFE_JQ_DEF"' (.headRefName // "") | clean' <<<"$pr_raw")"
    MERGE_STATE="$(jq -r '(.mergeStateStatus // "") | gsub("[^A-Z_]"; "")' <<<"$pr_raw")"
    if ! jq -e 'has("statusCheckRollup") and has("mergeStateStatus")' >/dev/null 2>&1 <<<"$pr_raw"; then
      HEAD=""
      add_error first_party incomplete_payload "gh pr view $PR omitted statusCheckRollup or mergeStateStatus, which the call requested"
      SELF_REASON="pr_read_failed"
    elif [ -z "$HEAD" ] || [ -z "$BRANCH" ]; then
      HEAD=""
      add_error first_party incomplete_payload "gh pr view $PR returned JSON without headRefOid/headRefName"
      SELF_REASON="pr_read_failed"
    fi
  fi
fi

# --- empty-state signal: a DIRECT rollup read ---------------------------------
# Deliberately outside both the age floor and the actions/runs call. It is not
# an inference, and an outage degrades those two together — gating this on
# either is what dropped the #285 fingerprint exactly when it mattered.
if [ -n "$pr_raw" ]; then
  rollup_n="$(jq -r '(.statusCheckRollup // []) | length' <<<"$pr_raw" 2>/dev/null || echo 0)"
  if [ "${rollup_n:-0}" -gt 0 ]; then
    empty_rc=0
    # A bash variable CANNOT hold a NUL byte, so capturing NUL-delimited
    # output into one silently loses every delimiter and the read loop runs
    # ZERO times — the very 'generator produced nothing' failure the capture
    # was added to detect, reintroduced by the fix for it. Newline delimiting
    # is safe here BECAUSE the sanitiser below strips control characters
    # first, so no emitted name can contain a newline; the capture is what
    # lets the exit status be checked at all.
    empty_out="$(jq -r "$UNSAFE_JQ_DEF"'
      # `//` falls back only on null/false, so `.name // .context` KEEPS an
      # empty-string name and the entry then vanishes at the `[ -n "$ck" ]`
      # guard below — found, emitted, silently discarded, verdict `healthy`.
      # That is the headline signal of this probe producing the confident
      # wrong answer its header calls worse than having no probe at all, so
      # absence is tested by LENGTH and never by `//`.
      def firstnonempty($a; $b): if (($a | length) > 0) then $a
                                 elif (($b | length) > 0) then $b
                                 else "(unnamed)" end;
      [ .statusCheckRollup[]?
        | select( ((.status // "") == "")
                  and ((.conclusion // "") == "")
                  and ((.state // "") == "") )
        | (firstnonempty(((.name // "") | tostring); ((.context // "") | tostring)) | clean)
      ] | unique | .[]
    ' <<<"$pr_raw")" || empty_rc=$?
    if [ "$empty_rc" -ne 0 ]; then
      # A generator that died is not "no anomalies found" — it is no read at all.
      add_error first_party incomplete_payload "the empty-state read over the rollup failed (jq exited $empty_rc)"
    else
      ROLLUP_CHECK="ran"
      while IFS= read -r ck; do
        # The generator now guarantees a non-empty token per matching entry
        # (`clean` only SUBSTITUTES characters, never deletes, and the
        # fallback is a literal), so this guard can only skip the single
        # empty line a here-string yields for empty input. It must never
        # again be the thing that decides whether an anomaly is reported.
        [ -n "$ck" ] && add_anomaly empty_state_check "$ck is in the rollup with no status, conclusion or state"
      done <<<"$empty_out"
    fi
  fi
fi

# --- run comparison -----------------------------------------------------------
if [ -n "$HEAD" ]; then
  # Head age, computed in jq (fromdateiso8601/now) rather than with `date`,
  # which takes incompatible flags on BSD and GNU.
  rc=0
  commit_raw="$(gh_bounded api "repos/$REPO/commits/$HEAD" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    add_error first_party gh_call_failed "gh api repos/$REPO/commits/$HEAD exited $rc$(gh_rc_note "$rc")"
  else
    HEAD_AGE="$(jq -r '
      (.commit.committer.date // .commit.author.date // "") as $d
      | if $d == "" then "" else
          ((($d | fromdateiso8601) | (now - .) | floor) as $age
           # A NEGATIVE age is an invalid measurement, not a fresh head.
           # `GIT_COMMITTER_DATE` is author-settable and GitHub preserves it, so a
           # future-dated commit is `-lt MIN_AGE` forever and would permanently
           # suppress the load-bearing signal under a reason (`head_too_fresh`)
           # that is false on its face. Empty routes it to `head_age_unknown`.
           | if $age < 0 then "" else ($age | tostring) end)
        end
    ' <<<"$commit_raw" 2>/dev/null)"
    [ -n "$HEAD_AGE" ] || add_error first_party incomplete_payload "commit $HEAD carried no committer date"
  fi

  # A branch name is not URL-safe: `#` is a legal git ref character and would
  # truncate the query string, dropping per_page; `+` would decode as a space.
  BRANCH_ENC="$(jq -rn --arg b "$BRANCH" '$b|@uri')"
  rc=0
  runs_raw="$(gh_bounded api "repos/$REPO/actions/runs?branch=$BRANCH_ENC&per_page=100" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    add_error first_party gh_call_failed "gh api actions/runs for $BRANCH_SAFE exited $rc$(gh_rc_note "$rc")"
  elif [ -z "$runs_raw" ] || ! jq -e 'has("workflow_runs")' >/dev/null 2>&1 <<<"$runs_raw"; then
    add_error first_party incomplete_payload "actions/runs for $BRANCH_SAFE exited 0 without a workflow_runs key"
  else
    # THE PAYLOAD TRAVELS ON STDIN, NEVER ON ARGV. Measured on this repo, one
    # page of 100 runs is ~1.6 MB (~16 KB per run); Linux caps a single argv
    # element at MAX_ARG_STRLEN = 131,072 bytes, so `jq -n --argjson runs
    # "$runs_raw"` died at roughly the EIGHTH run on the branch — the run
    # comparison was dead on every real repo, and dead hardest where the
    # intersection baseline is richest. CLAUDE.md records the same lesson from
    # #263: the cap existed for argv, so the payload travels by file.
    rc=0
    derived="$(jq --arg head "$HEAD" '
      # Only HEAD-TRIGGERED events are comparable: a workflow_dispatch or
      # schedule run on a prior head can never recur on this one.
      ["pull_request","pull_request_target","push","merge_group"] as $auto
      | [ .workflow_runs[]? | select(.event as $e | $auto | index($e)) ] as $r
      | ([ $r[] | select(.head_sha == $head) | "\(.name) (\(.event))" ] | unique) as $cur
      | ([ $r[] | select(.head_sha != $head) | .head_sha ] | unique) as $prior_heads
      | ([ $prior_heads[] as $h
           | [ $r[] | select(.head_sha == $h) | "\(.name) (\(.event))" ] | unique ]) as $sets
      # INTERSECTION of every prior head, never the union: a workflow absent
      # from one prior head is ordinary (path filter, if:, a rename).
      | (if ($sets | length) == 0 then []
         else ($sets | reduce .[] as $s (null; if . == null then $s else (. - (. - $s)) end))
         end) as $required
      | { cur: $cur,
          prior_heads: ($prior_heads | length),
          required: $required,
          missing: ($required - $cur),
          truncated: ((.workflow_runs | length) >= 100) }
    ' <<<"$runs_raw")" || rc=$?

    n_prior_heads=""; n_cur=""; n_required=""; RUNS_TRUNCATED="unknown"
    if [ "$rc" -eq 0 ] && [ -n "$derived" ]; then
      n_prior_heads="$(jq -r '.prior_heads' <<<"$derived" 2>/dev/null)"
      n_cur="$(jq -r '.cur | length' <<<"$derived" 2>/dev/null)"
      n_required="$(jq -r '.required | length' <<<"$derived" 2>/dev/null)"
      RUNS_TRUNCATED="$(jq -r 'if .truncated then "yes" else "no" end' <<<"$derived" 2>/dev/null)"
      [ -n "$RUNS_TRUNCATED" ] || RUNS_TRUNCATED="unknown"
    fi
    # Each value is checked SEPARATELY. Concatenating them and testing once is
    # what it looks like, and it passes when one is empty and the others are
    # digits ("2" + "" + "0" is all digits).
    DERIVED_OK=1
    for v in "$n_prior_heads" "$n_cur" "$n_required"; do
      case "$v" in ""|*[!0-9]*) DERIVED_OK=0 ;; esac
    done

    if [ "$DERIVED_OK" -ne 1 ]; then
      # A derivation that produced nothing must NEVER reach the branch that
      # asserts the check ran. `[ "" -eq 0 ]` prints an error and is falsy, so
      # an unguarded fall-through lands in the `else` and certifies a
      # measurement that never happened — the `clean`-means-measured door, one
      # layer below where it was first closed.
      add_error first_party incomplete_payload "the run comparison for $BRANCH_SAFE produced no usable result (jq exited $rc)"
      [ -n "$SELF_REASON" ] || SELF_REASON="run_comparison_failed"
    elif [ -z "$HEAD_AGE" ]; then
      SELF_REASON="head_age_unknown"
    elif [ "$HEAD_AGE" -lt "$MIN_AGE" ]; then
      SELF_REASON="head_too_fresh"
    elif [ "$n_prior_heads" -eq 0 ]; then
      # No baseline exists, so nothing was compared. Saying `clean` here is the
      # first-party door into `healthy` that #285 walks through one step early.
      SELF_REASON="no_prior_heads"
    else
      if [ "$n_required" -eq 0 ]; then
        # An EMPTY intersection compared nothing: every prior head ran a
        # different set, so no workflow was ever required of this head. Setting
        # RUN_CHECK here would certify a comparison that had no subject, which
        # is the `clean`-means-measured door one more layer down.
        SELF_REASON="no_required_baseline"
      elif [ "${rollup_n:-0}" -eq 0 ] && [ "$n_cur" -gt 0 ]; then
        # An EMPTY rollup beside runs that DID happen on this head is two API
        # surfaces contradicting each other, which is #285 itself in its most
        # extreme form: `gh pr view --json statusCheckRollup` exiting 0 with
        # fewer checks than reality, here with ALL of them missing. The
        # empty-state read is skipped entirely when the rollup has no entries
        # (there is nothing to iterate), so `ROLLUP_CHECK` stays `not_run`, no
        # anomaly is raised, and the run comparison earned `clean` UNOPPOSED.
        # Measured: verdict `healthy`, zero anomalies, zero probe_errors.
        #
        # The sibling this file must agree with already refuses the same shape:
        # `merge-shepherd.sh` carries a dedicated empty-rollup gate on the
        # principle that `CLEAN` plus zero checks is not green. The probe held
        # both halves of the contradiction — `rollup_n` and `n_cur` — and
        # compared them nowhere.
        #
        # `n_cur > 0` is the whole guard: a repo with no CI at all has an empty
        # rollup AND no runs, which is ordinary and must stay `clean`. This
        # fires only when runs exist and the rollup denies them.
        SELF_REASON="rollup_empty_with_runs"
      elif [ "$RUNS_TRUNCATED" != "no" ]; then
        # A TRUNCATED page cannot certify completeness. The header states this
        # cuts both ways and names under-detection as the direction that
        # matters: a page boundary landing inside the oldest included head`s
        # run set shrinks the intersection, the missing run is not required of
        # anybody, and the comparison reaches `clean` -> `healthy`. Measured on
        # two fixtures differing ONLY in truncation, same underlying reality:
        # the full page gave `degraded (unattributed)` and the 100-run page
        # gave `healthy`. That is the acceptance criterion of #285 failing in
        # the file that exists to satisfy it, so truncation is consulted by the
        # verdict and not merely reported beside it.
        #
        # `!= "no"` and not `= "yes"`: `unknown` means the flag itself could
        # not be read, which certifies nothing either. Anomalies already found
        # are still reported - they are first-party measurements, and the
        # anomaly branch is ahead of this one - so this suppresses only the
        # claim to have looked EVERYWHERE, never a positive finding.
        SELF_REASON="runs_page_truncated"
      else
        RUN_CHECK="ran"
      fi
      if [ "$n_cur" -eq 0 ]; then
        # `$required` is consulted HERE TOO, not only for missing_workflow_run.
        # With disjoint per-head workflow sets the intersection is empty, so
        # nothing was ever required of this head and its having no run is
        # ordinary. Applying the intersection guard to one signal and not its
        # sibling is exactly the over-detection the header disclaims.
        if [ "$n_required" -gt 0 ]; then
          add_anomaly no_run_for_head "$HEAD has no workflow run; $n_required workflow(s) ran on every one of $n_prior_heads prior head(s) of $BRANCH_SAFE (page truncated: $RUNS_TRUNCATED)"
        fi
      else
        missing_rc=0
        missing_out="$(jq -r "$UNSAFE_JQ_DEF"' .missing[] | clean' <<<"$derived")" || missing_rc=$?
        if [ "$missing_rc" -ne 0 ]; then
          # Same rule as the rollup generator: RUN_CHECK was set above, so a
          # silent failure here would certify a comparison it discarded.
          RUN_CHECK="not_run"
          SELF_REASON="run_comparison_failed"
          add_error first_party incomplete_payload "the missing-run read failed (jq exited $missing_rc)"
        else
          while IFS= read -r wf; do
            [ -n "$wf" ] && add_anomaly missing_workflow_run "$wf ran on every one of $n_prior_heads prior head(s) of $BRANCH_SAFE, not on $HEAD (page truncated: $RUNS_TRUNCATED)"
          done <<<"$missing_out"
        fi
      fi
    fi
  fi
fi

n_anomalies="$(jq -r 'length' <<<"$ANOMALIES" 2>/dev/null)"
n_fp_errors="$(jq -r '[.[] | select(.scope == "first_party")] | length' <<<"$PROBE_ERRORS" 2>/dev/null)"
case "$n_anomalies" in ""|*[!0-9]*) n_anomalies=0 ;; esac
case "$n_fp_errors" in ""|*[!0-9]*) n_fp_errors=0 ;; esac
if [ "$n_anomalies" -gt 0 ]; then
  SELF="anomaly"
  # The reason field describes why a measurement did NOT happen; carrying one
  # onto an anomaly re-applies a suppression the code deliberately refused.
  SELF_REASON=""
elif [ "$n_fp_errors" -gt 0 ]; then
  # A call that failed is not degradation — but it is not a clean read either:
  # the probe cannot certify what it could not fetch. Without this the ledger
  # was decorative, and a run with BOTH gh api calls failing and a clean rollup
  # reported `healthy`, which is what this file, SKILL.md and CLAUDE.md all
  # already said it must not do.
  SELF="not_measured"
  [ -n "$SELF_REASON" ] || SELF_REASON="probe_errors_present"
elif [ "$RUN_CHECK" = "ran" ]; then
  # ONLY the run comparison earns `clean`. The empty-state check is a real
  # signal but it detects a MALFORMED entry and can never detect an ABSENT
  # one — which is #285's headline signal — so a rollup that simply lacks `ci`
  # looks identical to a healthy one through it. Accepting it as sufficient
  # left the first-party door into `healthy` open on exactly the shape this
  # probe was written for: measured, #285's own rollup on a single-commit
  # branch reported `healthy`.
  SELF="clean"
  SELF_REASON=""
else
  SELF="not_measured"
  # The reason is PRESERVED, never blanked: `no_prior_heads`, `head_too_fresh`
  # and `no_required_baseline` are exactly why the verdict is not a measurement,
  # so discarding them loses the only explanation the caller has.
  [ -n "$SELF_REASON" ] || SELF_REASON="nothing_measurable"
fi

# --- attribution (never load-bearing) ----------------------------------------
STATUS="unknown"
STATUS_DETAIL="status endpoint unreachable or unreadable"
if command -v curl >/dev/null 2>&1; then
  # `--fail` is what makes a non-2xx a FAILURE: without it curl exits 0 on a
  # 503 and hands over the error body, and an error body carrying a `status`
  # key satisfied the recognisability gate below and resolved `operational`.
  # `--proto '=https'`, `--max-redirs 0` and the `--` terminator are the other
  # half: without `--`, a URL beginning `-K` is read as curl's `--config`, so an
  # attacker-supplied value could set `output`, `upload-file`, `header` or
  # `proxy`. The https-only check sits with the other usage validation above.
  rc=0
  status_raw="$(curl -sS --fail --proto '=https' --max-redirs 0 \
      --max-time "$STATUS_TIMEOUT" -H 'Accept: application/json' -- "$STATUS_URL" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    add_error attribution status_fetch_failed "curl exited $rc fetching the status endpoint"
  elif [ -n "$status_raw" ] && jq -e . >/dev/null 2>&1 <<<"$status_raw"; then
    STATUS="$(jq -r --arg comps "$STATUS_COMPONENTS" '
      ($comps | ascii_downcase | split(",") | map(sub("^ +";"") | sub(" +$";"")) | map(select(length > 0))) as $rel
      | (if (.status | type) == "object" then (.status.indicator // "") else "" end) as $ind
      | (($ind == "major") or ($ind == "critical")) as $broad
      | def relevant($n): ($rel | any(. as $c | ($n // "" | ascii_downcase) | contains($c)));
        # An ARRAY is required, not merely a key. `{"status":"error","code":503}`
        # and `{"status":"Service Unavailable"}` both carry a `status` key, and
        # under a key-presence test they classified `operational` — a non-2xx
        # body manufacturing a green platform. A scope that filters to nothing
        # (`","`, `"   "`) is `unknown` for the same reason: it cannot answer.
        if (($rel | length) == 0) then "unknown"
        elif ((type == "object")
              and (((.components | type) == "array") or ((.incidents | type) == "array")) | not)
        then "unknown"
        # A payload carrying NEITHER a component nor an incident answers
        # nothing. It is not a green platform, it is a page with no content,
        # and reading it as `operational` resolves `healthy` through whatever
        # is actually happening.
        elif ((((.components // []) | length) == 0)
              and (((.incidents // []) | length) == 0)) then "unknown"
        # A scope matching NO component name cannot answer either, and this is
        # the door an OPERATOR opens by accident. `relevant` asks whether a
        # component NAME CONTAINS a scope token, so the MORE SPECIFIC value
        # `github actions` matches the component `Actions` not at all while
        # `actions` matches it: a plausible-looking PLATFORM_STATUS_COMPONENTS
        # override silently disables attribution AND manufactures `operational`
        # through a live outage. Measured, Actions in `major_outage`:
        # `actions,api requests` -> incident, `github actions` -> operational,
        # `zzz-nope` -> operational. An EMPTY scope was already `unknown` for
        # exactly this reason; a scope that filters to nothing is the same fact
        # arriving one step later, and it was the THIRD door into `healthy`.
        elif ((((.components // []) | length) > 0)
              and (([ .components[]? | select(relevant(.name)) ] | length) == 0)) then "unknown"
        else
          ([ .components[]? | select((.status // "") != "operational") | select(relevant(.name)) ]) as $comp
          | ([ .incidents[]?
               | select((.status // "") != "resolved" and (.status // "") != "postmortem")
               | select( ((.components // []) | any(relevant(.name)))
                         or (((.components // []) | length) == 0 and $broad) ) ]) as $inc
          | if (($comp | length) > 0) or (($inc | length) > 0) then "incident" else "operational" end
        end
    ' <<<"$status_raw" 2>/dev/null)"
    if [ -z "$STATUS" ]; then
      STATUS="unknown"
      add_error attribution status_unreadable "the status classifier failed on the fetched payload"
    fi
    case "$STATUS" in
      incident)
        STATUS_DETAIL="$(jq -r "$UNSAFE_JQ_DEF" --arg comps "$STATUS_COMPONENTS" '
          ($comps | ascii_downcase | split(",") | map(sub("^ +";"") | sub(" +$";"")) | map(select(length > 0))) as $rel
          | (if (.status | type) == "object" then (.status.indicator // "") else "" end) as $ind
          | (($ind == "major") or ($ind == "critical")) as $broad
          | def relevant($n): ($rel | any(. as $c | ($n // "" | ascii_downcase) | contains($c)));
            [ ( (if (.status | type) == "object" then (.status.description // "") else "" end)
                | if . == "" then "" else "page-wide: " + . end ),
              ( [ .incidents[]?
                  | select((.status // "") != "resolved" and (.status // "") != "postmortem")
                  | select( ((.components // []) | any(relevant(.name)))
                            or (((.components // []) | length) == 0 and $broad) )
                  | .name ] | join("; ") ),
              ( [ .components[]? | select((.status // "") != "operational")
                  | select(relevant(.name)) | "\(.name): \(.status)" ] | join("; ") )
            ] | map(select(. != "")) | join(" | ")
            | clean
        ' <<<"$status_raw" 2>/dev/null)"
        # The gsub above is what strips BIDI; `tr` is byte-oriented and cannot
        # match a multibyte RLO at all, so it is kept only as a belt-and-braces
        # pass over the shell-assembled result. Third-party text, but it reaches
        # the same reported field as the first-party strings.
        STATUS_DETAIL="$(printf '%s' "$STATUS_DETAIL" | tr -d '\000-\037\177')"
        [ -n "$STATUS_DETAIL" ] || STATUS_DETAIL="an incident is open on a check-relevant component" ;;
      operational)
        STATUS_DETAIL="no check-relevant component is impaired"
        page_desc="$(jq -r "$UNSAFE_JQ_DEF"' (if (.status | type) == "object" then (.status.description // "") else "" end) | clean' <<<"$status_raw" 2>/dev/null | tr -d '\000-\037\177')"
        [ -z "$page_desc" ] || STATUS_DETAIL="$STATUS_DETAIL (page-wide: $page_desc)" ;;
      *)
        # Covers THREE distinct ways attribution can fail, and must not assert
        # any one of them: an unrecognisable payload, a payload carrying no
        # components AND no incidents, and a configured scope that matched no
        # component name. Naming only the first was false for the other two.
        STATUS_DETAIL="the status page could not attribute: unrecognisable, empty, or no component matched the configured scope" ;;
    esac
  else
    add_error attribution status_unparsable "the status endpoint returned no parsable JSON"
  fi
else
  add_error attribution curl_missing "curl is not installed"
  STATUS_DETAIL="curl is not installed, so attribution could not be attempted"
fi

# --- verdict ------------------------------------------------------------------
# The separator is "/" and not "|" ON PURPOSE: `|` is case-pattern alternation,
# so `anomaly|incident)` would silently match the single word "anomaly" and the
# whole table would collapse to its first row.
case "$SELF/$STATUS" in
  anomaly/incident)       VERDICT="degraded (attributed)" ;;
  anomaly/operational)    VERDICT="degraded (unattributed)" ;;
  anomaly/unknown)        VERDICT="degraded (unattributed)" ;;
  clean/incident)         VERDICT="degraded (attributed)" ;;
  clean/operational)      VERDICT="healthy" ;;
  clean/unknown)          VERDICT="unknown" ;;
  not_measured/incident)  VERDICT="degraded (attributed)" ;;
  *)                      VERDICT="unknown" ;;
esac

# `explains` is keyed on BOTH axes, not on the verdict alone. An incident beside
# a first-party read that found nothing wrong explains nothing about THIS PR,
# and saying it does invents an excuse for a genuine red check.
case "$VERDICT" in
  "healthy")
    EXPLAINS="nothing — a green status page is not evidence of health, and this verdict never licenses escalating a stall as a real defect" ;;
  "unknown")
    if [ "$SELF" = "clean" ]; then
      EXPLAINS="nothing — this PR's own check data was read and was complete, but the status endpoint could not be, so nothing is attributed and this verdict never licenses escalating a stall as a real defect"
    else
      EXPLAINS="nothing — the probe could not measure; unknown is not health, and this verdict never licenses escalating a stall as a real defect"
    fi ;;
  "degraded (attributed)")
    if [ "$SELF" = "anomaly" ]; then
      EXPLAINS="a stall — an open platform incident on a check-relevant component, alongside first-party evidence of missing or incomplete check data"
    elif [ "$SELF" = "clean" ]; then
      EXPLAINS="nothing about this PR — a platform incident is open, but this PR's own check data was compared and came back complete, so the incident is context and not an explanation for anything observed here"
    else
      EXPLAINS="nothing measured here — a platform incident is open, and this run measured nothing first-party, so the incident is context and not an explanation for anything observed on this PR"
    fi ;;
  "degraded (unattributed)")
    EXPLAINS="a stall — first-party evidence of degradation; the status page neither corroborates nor refutes it, and its silence is not a refutation" ;;
  *)
    EXPLAINS="nothing — this build emitted a verdict it has no explanation for, which is itself a defect; treat it as unknown" ;;
esac

# --- emit ---------------------------------------------------------------------
# CAPTURED, then RE-PARSED, then printed. The status alone is not enough: the
# contract is "one JSON object on stdout", and a partial write that exits
# non-zero would satisfy an exit-status check while handing the caller half an
# object. Both failures land on the same fallback.
emit_rc=0
emitted="$(jq -n \
  --arg repo "$REPO" \
  --arg verdict "$VERDICT" \
  --arg self "$SELF" \
  --arg self_reason "$SELF_REASON" \
  --arg run_check "$RUN_CHECK" \
  --arg runs_truncated "$RUNS_TRUNCATED" \
  --arg rollup_check "$ROLLUP_CHECK" \
  --arg status "$STATUS" \
  --arg status_detail "$STATUS_DETAIL" \
  --arg status_url "$STATUS_URL" \
  --arg head "$HEAD" \
  --arg branch "$BRANCH_SAFE" \
  --arg merge_state "$MERGE_STATE" \
  --arg head_age "$HEAD_AGE" \
  --arg explains "$EXPLAINS" \
  --argjson anomalies "$ANOMALIES" \
  --argjson probe_errors "$PROBE_ERRORS" \
  --argjson pr "${PR:-null}" \
  '{repo:$repo, pr:$pr, verdict:$verdict,
    self_measured:$self,
    self_measured_reason:(if $self_reason == "" then null else $self_reason end),
    checks_run:{run_comparison:$run_check, rollup_empty_state:$rollup_check,
                runs_page_truncated:$runs_truncated},
    anomalies:$anomalies,
    probe_errors:$probe_errors,
    status_page:$status, status_page_detail:$status_detail, status_page_url:$status_url,
    head_sha:(if $head == "" then null else $head end),
    head_ref:(if $branch == "" then null else $branch end),
    head_age_seconds:(if $head_age == "" then null else ($head_age|tonumber) end),
    merge_state_status:(if $merge_state == "" then null else $merge_state end),
    explains:$explains}')" || emit_rc=$?

if [ "$emit_rc" -ne 0 ] || [ -z "$emitted" ] || ! jq -e . >/dev/null 2>&1 <<<"$emitted"; then
  # EVERY FIELD IS A LITERAL. The measured values are exactly what could not be
  # serialised, so re-interpolating them here would re-run the failure inside
  # the handler for it; a placeholder that cannot itself fail is worth more than
  # a richer one that can. `verdict` is `unknown` because that is the verdict
  # for "nothing could be measured", and `explains` says so in the same words
  # every other unknown does — a caller reporting this object must not read it
  # as anything softer.
  emitted='{"repo":null, "pr":null, "verdict":"unknown",
    "self_measured":"not_measured",
    "self_measured_reason":"verdict_emitter_failed",
    "checks_run":{"run_comparison":"not_run", "rollup_empty_state":"not_run",
                  "runs_page_truncated":"unknown"},
    "anomalies":[],
    "probe_errors":[{"scope":"probe", "kind":"verdict_emitter_failed",
      "detail":"the verdict emitter failed, so every measured field was discarded and this object is a hand-built placeholder"}],
    "status_page":"unknown",
    "status_page_detail":"not reported: the verdict emitter failed",
    "status_page_url":null,
    "head_sha":null, "head_ref":null, "head_age_seconds":null,
    "merge_state_status":null,
    "explains":"nothing — the verdict emitter failed, so nothing that was measured survived; unknown is not health, and this verdict never licenses escalating a stall as a real defect"}'
  SUMMARY="platform: unknown — the verdict emitter failed (jq exited $emit_rc); nothing that was measured survived"
else
  SUMMARY="platform: $VERDICT — explains $EXPLAINS"
fi

# `printf` is a bash BUILTIN, so the payload never becomes an argv element and
# the 131,072-byte MAX_ARG_STRLEN cap that killed `--argjson runs` cannot reach
# it. The single `exit 0` below is shared by both paths on purpose: a verdict
# never travels in an exit code, and the fallback carries a verdict.
printf '%s\n' "$emitted"
echo "$SUMMARY" >&2
exit 0
