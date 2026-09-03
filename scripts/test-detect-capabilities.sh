#!/usr/bin/env bash
# test-detect-capabilities.sh — setup-config's capability probe reads the
# PRODUCT, never the answers previously recorded about the product (issue #317).
#
# THE BUG IT GUARDS, and why it was silent. `detect-capabilities.sh` decided
# `posthog` with a bare-word `git grep` over the whole tracked tree. #267 then
# gave consumers `posthog: none` to write into
# `.claude/sassy-dog/survey-work.md` — a TRACKED file. So the moment a repo
# answered §2c of the interview, the detector's only `posthog` hit in an
# otherwise quiet tree was the config key itself, and every later `setup-config`
# refresh reported positive evidence against `posthog: none` while citing the
# file that records the answer. Nothing crashed and nothing was overwritten:
# update mode correctly STOPS and surfaces a tree that contradicts a `none`
# (`setup-config/references/update-mode.md`), so the failure mode is a refresh
# that halts on the same manufactured contradiction forever, in every consumer
# that adopted the form. The only remedy available to a consumer was a paragraph
# of rationale written into its own config prose — and a rationale copied into N
# consumer repos is the #167 third-copy shape, one copy per repo, with nothing
# able to correct them all.
#
# WHY THE SENTRY HALF IS HERE ANYWAY. The `sentry` grep did NOT reproduce the
# self-match: its patterns are SDK-shaped (`@sentry/`, `sentry_flutter`,
# `sentry.init`, `Sentry.Init`) and never match the literal `sentry: none`. The
# pathspec is symmetric on purpose — a hook script or a settings file UNDER
# `.claude/` that names `sentry.init` in prose is documentation rather than an
# integration, and an asymmetry between two adjacent lines reads as an oversight
# to the next editor, who fixes it in whichever direction they guess. (A ROOT
# `CLAUDE.md` is not covered by any of this: it sits outside `.claude/` and
# still matches, deliberately — see the CLAUDEMD fixture, which pins that. It is
# NOT the DOCS fixture: DOCS carries a root `CLAUDE.md` too, but its `README.md`
# and `docs/adr-001.md` hold both verdicts true on their own, so DOCS stays green
# under an added `':(exclude)CLAUDE.md'` and measures nothing about this claim.
# That is what M10 records, and it is why the two fixtures are separate.)
#
# WHAT IS BEHAVIOUR HERE AND WHAT IS SPELLING. Properties 2-4 run the SHIPPED
# script inside real git fixtures and read its JSON, so they measure the
# verdict rather than the source. But the spelling IS pinned, in two coupled
# places, and this is a deliberate trade rather than an oversight: property 1
# builds its pre-fix command by STRIPPING the literal `':(exclude).claude/**'`
# from the extracted line, and property 5 asserts that literal. A
# behaviour-preserving respelling — `:!.claude/**` and `:(top,exclude).claude/**`
# are both exactly equivalent, measured — therefore goes red at properties 1
# and 5 while every verdict stays correct. That is the cost of property 1 being
# able to prove its own fixture adequate at all: stripping requires knowing what
# to strip. If the pathspec is ever respelled, update BOTH sites together; the
# failure is loud and self-describing, not silent.
#
# Five properties are asserted:
#
#   1. Fixture adequacy, PER SELF-MATCH FIXTURE. The two grep lines are
#      EXTRACTED from the shipped script, the `.claude` pathspec is stripped
#      from each, and the result is run in CONFIG and in HOOK separately: each
#      must MATCH on its own. CONFIG is the exact #317 shape — the config key as
#      the SOLE occurrence in the tree — and HOOK is the same shape one
#      directory over. Running them separately is the point: a fixture carrying
#      the strings twice would let either half rot while the other kept the
#      property green. If the strip itself fails, the per-fixture checks are
#      SKIPPED and one guard message is emitted instead — the pathspec is gone
#      or respelled, and adequacy cannot be measured through it.
#   2. CONFIG and HOOK each detect `posthog: false` and `sentry: false`. This is
#      #317 itself; before the fix both were `true`.
#   3. SOURCE (a real SDK in `src/`), DOCS (root `CLAUDE.md`, `README.md`,
#      `docs/`) and CLAUDEMD (a root `CLAUDE.md` and NOTHING else) each detect
#      `true` for both. DOCS is not decoration: the caveat shipped in
#      `interview.md` §2c and `update-mode.md` PROMISES that a repo which merely
#      documents PostHog still trips detection, and without this fixture a
#      broader exclusion — `':(exclude)*.md'`, say — would keep every other
#      assertion green while breaking that promise. CLAUDEMD is the narrower
#      sibling and is not redundant with it: it is the ONLY fixture whose sole
#      occurrence is the root `CLAUDE.md`, so it is the only one that can go red
#      on an exclusion aimed at that file alone (M10).
#   4. BOTH (config mention AND real source) detects `true`; LOCK (the strings
#      only in `bun.lock`) detects `false` — the pre-existing `*.lock*` pathspec
#      still does its own job on the line this change edited; and NESTED
#      (`apps/web/.claude/sassy-dog/survey-work.md`, nothing at the root)
#      detects `true`, pinning the ANCHORING decision below.
#   5. Source-level shape guard: each grep line carries BOTH
#      `:(exclude).claude/**` and `:(exclude)*.lock*`.
#
# THE ANCHORING DECISION, pinned by the NESTED fixture. `.claude/**` is
# ROOT-ANCHORED: `apps/web/.claude/sassy-dog/survey-work.md` still matches, so a
# monorepo carrying a hand-placed nested agent config can still self-match. That
# is the deliberate narrow reading of #317's decision, because `setup-config`
# writes `.claude/sassy-dog/*.md` at the REPO ROOT and nowhere else, so the
# shape the issue measured cannot arise nested from the generator. The fixture
# exists so the limit is a recorded decision rather than an accident — if a
# nested consumer config ever becomes a thing the generator writes, this fixture
# is the one that must flip, and it will fail loudly when the pathspec grows.
#
# THE MUTATION RECORD — every red set below was OBSERVED by applying the
# mutation and reading which assertions failed, not predicted from the code:
#
#   M1  drop `':(exclude).claude/**'` from the posthog line   -> 4 red:
#       property 1's strip guard (ONE message — the stripper cannot remove what
#       is already gone, so the two per-fixture adequacy checks are skipped
#       rather than run), property 2's verdict on CONFIG (`false|true`) and on
#       HOOK (`false|true`), and property 5's posthog/`.claude` assertion.
#   M2  same, sentry line                                    -> 4 red, mirrored
#       (`true|false` on both fixtures).
#   M3  drop it from BOTH lines                              -> 5 red: the strip
#       guard once, both verdicts at `true|true`, property 5 twice.
#   M4  drop `':(exclude)*.lock*'` from both lines           -> 3 red: LOCK
#       reads `true|true`, plus property 5's lockfile assertion twice. Property
#       1 does not move — it strips only the `.claude` pathspec.
#   M5  empty CONFIG's `survey-work.md`                      -> 2 red: property
#       1 reports config-only inadequate, and NESTED fails too, since it reuses
#       the same writer one directory down. HOOK stays GREEN — which is the
#       whole reason the two self-match fixtures are separate. Before the split
#       a single fixture carried both strings, and emptying the config file left
#       this gate ALL GREEN with the exact #317 shape pinned by nothing.
#   M6  empty HOOK's script                                  -> 1 red: property
#       1 reports hook-only inadequate. Nothing else moves.
#   M7  respell to `':!.claude/**'`, exactly equivalent      -> 3 red: the strip
#       guard once and property 5 twice. Every VERDICT stays correct, which is
#       the trade the spelling paragraph above records rather than a bug.
#   M8  BROADEN the exclusion with `':(exclude)*.md'`        -> 3 red, and DOCS
#       is the one that matters: it reads `false|false` against the caveat both
#       reference docs ship. Property 5 stays green throughout — a shape guard
#       cannot see an over-reach, only a missing pathspec — so without the DOCS
#       fixture the only red would have been the config fixture's own adequacy
#       probe, which reports the mutation as its own inadequacy and points the
#       next reader at the wrong thing entirely.
#   M9  run the whole gate under a hostile global git config -> 0 red, i.e.
#       green, which is the assertion: `core.excludesFile` ignoring `.claude/`
#       plus `commit.gpgsign=true` with an unusable key. Without the isolation
#       below, the first leaves the config fixture UNTRACKED — property 2 then
#       passes because there is nothing to find — and the second fails the
#       fixture build.
#   M10 add `':(exclude)CLAUDE.md'` to both lines            -> 1 red: CLAUDEMD
#       reads `false|false`. DOCS stays GREEN — it carries a root `CLAUDE.md`
#       but also a `README.md` and a `docs/adr-001.md`, either of which holds
#       both verdicts true on its own. That is the whole reason CLAUDEMD exists:
#       before it, the header's root-`CLAUDE.md` claim cited DOCS and this
#       mutation ran the gate ALL GREEN, so the one deliberate carve-out in the
#       pathspec was pinned by nothing while reading as measured.
#
# `gh` is MOCKED and every call fails: the probe requires it on PATH but
# degrades every gh-backed field to null/[] with a note, and none of those
# fields is read here. The fixtures' git operations AND the probe runs use
# `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1` with a forced `add`, so a
# contributor's global `core.excludesFile` cannot quietly leave `.claude/`
# untracked (which would make property 2 pass for the wrong reason) and a
# `commit.gpgsign=true` with no key cannot fail the fixture build. No network,
# and no real repo is touched.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-detect-capabilities.sh
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-detect-capabilities: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

command -v jq >/dev/null 2>&1 || { echo "test-detect-capabilities: jq not on PATH" >&2; exit 1; }

DETECT="skills/setup-config/scripts/detect-capabilities.sh"
[ -f "$DETECT" ] || { echo "test-detect-capabilities: $DETECT not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "detect-capabilities tests (work: $WORK)" >&2

# --- the shipped grep lines, EXTRACTED rather than transcribed -----------------
# A test carrying its own copy of the pathspec would keep passing after the
# pathspec was reverted in the script. Both lines are single-line by
# construction; if that stops being true the extractor says so instead of
# silently matching nothing.
extract_line() { # <assignment-target>
    awk -v target="$1" '$0 ~ ("^git grep .*&& " target "=\"true\"$") { print; n++ }
                        END { exit (n == 1 ? 0 : 1) }' "$DETECT"
}
sentry_line="$(extract_line sentry)" || {
    bad "expected exactly one 'git grep … && sentry=\"true\"' line in $DETECT — this test extracts it; update the extractor"
    echo "detect-capabilities tests: FAILED" >&2
    exit 1
}
posthog_line="$(extract_line posthog)" || {
    bad "expected exactly one 'git grep … && posthog=\"true\"' line in $DETECT — this test extracts it; update the extractor"
    echo "detect-capabilities tests: FAILED" >&2
    exit 1
}

# --- fixtures ------------------------------------------------------------------
# Real working-tree files, because `git grep` reads the tree. Tiny repos;
# nothing here depends on size (that is issue #172's gate, not this one).
#
# Every git call runs with the contributor's global and system config OUT of the
# way. Two failure modes that would otherwise be silent: a global
# `core.excludesFile` ignoring `.claude/` leaves the config fixture untracked, so
# property 2 passes because there is nothing to find rather than because the
# pathspec worked; and `commit.gpgsign=true` with no usable key fails the commit.
gitf() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"; }

mkrepo() { # <dir>
    mkdir -p "$1"
    gitf -c init.defaultBranch=main init -q "$1"
    gitf -C "$1" config user.email test@example.invalid
    gitf -C "$1" config user.name test
}

commit_all() { # <dir> <label>
    # -f defeats any ignore rule that could hide .claude/; the status is CHECKED,
    # because a fixture that failed to build would otherwise be read as a repo
    # with nothing in it — the same verdict this gate expects for a clean tree.
    if ! gitf -C "$1" add -A -f >/dev/null 2>&1; then
        bad "fixture $2: git add failed"
        return 1
    fi
    if ! gitf -C "$1" -c commit.gpgsign=false commit -qm fixture >/dev/null 2>&1; then
        bad "fixture $2: git commit failed"
        return 1
    fi
}

# The consumer's answer to §2c, written where setup-config writes it. This file
# is the SOLE occurrence of either string in the CONFIG fixture — that is the
# exact #317 shape, and property 1 depends on it.
write_config() { # <root-dir>
    mkdir -p "$1/.claude/sassy-dog"
    cat > "$1/.claude/sassy-dog/survey-work.md" <<'CFG'
---
posthog: none
mobile: none
---

## extra-guardrails

This product has no analytics, and no error monitoring wired up: nobody has run
sentry.init here.
CFG
}

# The same shape one directory over: an agent hook that names both in prose.
write_hook() { # <root-dir>
    mkdir -p "$1/.claude/hooks"
    cat > "$1/.claude/hooks/sassydog-format.sh" <<'HOOK'
#!/usr/bin/env bash
# This dispatcher does not touch posthog and does not call sentry.init; both are
# named here only so the exclusion has something to exclude.
exit 0
HOOK
}

# A real integration, in tracked source outside .claude/.
write_source() { # <root-dir>
    mkdir -p "$1/src"
    cat > "$1/src/analytics.ts" <<'SRC'
import posthog from "posthog-js";
import * as Sentry from "@sentry/browser";
Sentry.init({ dsn: process.env.DSN });
SRC
}

neutral_src() { # <root-dir>
    mkdir -p "$1/src"
    printf 'export const noop = 1;\n' > "$1/src/app.ts"
}

CONFIG="$WORK/config-only"
mkrepo "$CONFIG"; write_config "$CONFIG"; neutral_src "$CONFIG"; commit_all "$CONFIG" config-only

HOOK="$WORK/hook-only"
mkrepo "$HOOK"; write_hook "$HOOK"; neutral_src "$HOOK"; commit_all "$HOOK" hook-only

SOURCE="$WORK/source-only"
mkrepo "$SOURCE"; write_source "$SOURCE"; commit_all "$SOURCE" source-only

# Documentation ONLY — no src/, no .claude/. The shipped caveat says a repo that
# merely documents PostHog still trips detection; this is what holds a later
# "just exclude the markdown too" from passing every other assertion.
DOCS="$WORK/docs-only"
mkrepo "$DOCS"
mkdir -p "$DOCS/docs"
printf '# Repo guide\n\nWe evaluated posthog and rejected it; sentry.init lives nowhere here.\n' > "$DOCS/CLAUDE.md"
printf '# Product\n\nNo posthog, no sentry.init.\n' > "$DOCS/README.md"
printf '# ADR 1\n\nposthog was considered. sentry.init was not wired.\n' > "$DOCS/docs/adr-001.md"
commit_all "$DOCS" docs-only

# The root CLAUDE.md ALONE. DOCS cannot pin the root-CLAUDE.md decision even
# though it carries the file: its README.md and docs/adr-001.md keep it at
# `true|true` under an added `':(exclude)CLAUDE.md'`, so the claim would read as
# measured while nothing measured it. This fixture is the only place it IS
# measured — see M10.
CLAUDEMD="$WORK/claude-md-only"
mkrepo "$CLAUDEMD"
printf '# Repo guide\n\nWe evaluated posthog and rejected it; sentry.init lives nowhere here.\n' > "$CLAUDEMD/CLAUDE.md"
neutral_src "$CLAUDEMD"; commit_all "$CLAUDEMD" claude-md-only

BOTH="$WORK/both"
mkrepo "$BOTH"; write_config "$BOTH"; write_source "$BOTH"; commit_all "$BOTH" both

LOCK="$WORK/lock-only"
mkrepo "$LOCK"
printf '"posthog-js@1.0.0": {}\n"@sentry/browser@8.0.0": {}\nsentry.init\n' > "$LOCK/bun.lock"
neutral_src "$LOCK"; commit_all "$LOCK" lock-only

# Root-anchored: this one is EXPECTED to still be detected. See the anchoring
# decision in the header.
NESTED="$WORK/nested"
mkrepo "$NESTED"
mkdir -p "$NESTED/apps/web"
write_config "$NESTED/apps/web"
neutral_src "$NESTED"; commit_all "$NESTED" nested

# --- mock gh -------------------------------------------------------------------
# The probe refuses to start without gh on PATH, and treats every gh failure as a
# recorded detect_failure. None of the gh-backed fields is read here.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
exit 1
GH
chmod +x "$WORK/bin/gh"

# --- 1. fixture adequacy, per self-match fixture --------------------------------
# Strip the .claude pathspec from each EXTRACTED line and run the result in each
# fixture whose ONLY occurrence is under .claude/. Both must match there, or that
# fixture has stopped carrying the self-match and its half of property 2 proves
# nothing.
strip_claude_pathspec() { # <line>
    printf '%s\n' "$1" | sed "s|[[:space:]]*':(exclude)\.claude/\*\*'||"
}

probe_lines() { # <dir> <sentry-cmd> <posthog-cmd> -> "<sentry>|<posthog>"
    (
        cd "$1" || exit 1
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
        # shellcheck disable=SC2034  # both are set by the eval'd shipped lines
        sentry="false"; posthog="false"
        eval "$2"
        eval "$3"
        printf '%s|%s' "$sentry" "$posthog"
    )
}

prefix_sentry="$(strip_claude_pathspec "$sentry_line")"
prefix_posthog="$(strip_claude_pathspec "$posthog_line")"
if [ "$prefix_sentry" = "$sentry_line" ] || [ "$prefix_posthog" = "$posthog_line" ]; then
    bad "could not strip ':(exclude).claude/**' from the extracted grep lines — either the pathspec is gone (that is the #317 regression, see property 5) or it has been respelled, in which case this stripper and property 5 must both be updated (header: 'what is behaviour here and what is spelling')"
else
    for pair in "config-only:$CONFIG" "hook-only:$HOOK"; do
        label="${pair%%:*}"; dir="${pair#*:}"
        prefix_verdict="$(probe_lines "$dir" "$prefix_sentry" "$prefix_posthog")"
        if [ "$prefix_verdict" = "true|true" ]; then
            ok "fixture adequacy ($label): without the .claude exclusion both greps DO match (sentry|posthog = $prefix_verdict)"
        else
            bad "fixture $label no longer proves the bug: with the .claude exclusion stripped, the shipped greps report '$prefix_verdict' instead of 'true|true'. Its half of property 2 is vacuous until the fixture carries the self-match again"
        fi
    done
fi

# --- 2-4. end to end: the shipped probe on each fixture ------------------------
verdict() { # <dir> -> "<sentry>|<posthog>" or a diagnostic
    local out err rc
    err="$WORK/stderr.$$"
    out="$( cd "$1" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        PATH="$WORK/bin:$PATH" bash "$REPO_ROOT/$DETECT" 2>"$err" )"
    rc=$?
    # A probe that did not RUN must never be reported as a pathspec verdict: an
    # `{"error":…}` object parses to `null|null`, which reads like an over-reach
    # and would send the next reader after the wrong thing entirely.
    if [ -z "$out" ]; then
        printf '«probe did not run: exit %s, stderr: %s»' "$rc" "$(tr '\n' ' ' <"$err" | cut -c1-200)"
        return
    fi
    if [ "$(jq -r 'has("error")' <<<"$out" 2>/dev/null)" = "true" ]; then
        printf '«probe refused to run: %s»' "$(jq -r '.error' <<<"$out")"
        return
    fi
    jq -r '[(.sentry|tostring), (.posthog|tostring)] | join("|")' <<<"$out" 2>/dev/null \
        || printf '«unparseable: %s»' "$out"
}

expect() { # <label> <dir> <expected> <failure-note>
    local got
    got="$(verdict "$2")"
    if [ "$got" = "$3" ]; then
        ok "$1: sentry|posthog = $got"
    else
        bad "$1: sentry|posthog = $got, expected $3 — $4"
    fi
}

expect "config-only fixture" "$CONFIG" "false|false" \
    "a tree whose only occurrence is the recorded ANSWER must read as no integration; reporting true here is issue #317, and it makes every refresh contradict the config it just read"
expect "hook-only fixture" "$HOOK" "false|false" \
    "the exclusion covers .claude/ as a whole, not just the sassy-dog config path — an agent hook is configuration too"
expect "source-only fixture" "$SOURCE" "true|true" \
    "the exclusion has over-reached: a real SDK in tracked source outside .claude/ is exactly what this probe exists to find"
expect "docs-only fixture" "$DOCS" "true|true" \
    "a repo that merely DOCUMENTS the surface must still trip detection — interview.md §2c and update-mode.md both promise that, and say to name the file that matched"
expect "claude-md-only fixture" "$CLAUDEMD" "true|true" \
    "a ROOT CLAUDE.md sits outside .claude/ and still matches, by decision. This fixture is the ONLY one that measures it: DOCS stays green under an added ':(exclude)CLAUDE.md' because its README.md and docs/adr-001.md keep both verdicts true"
expect "both fixture" "$BOTH" "true|true" \
    "a real integration must still be detected when the config also mentions the word"
expect "lock-only fixture" "$LOCK" "false|false" \
    "the pre-existing ':(exclude)*.lock*' pathspec is gone or broken — a transitive dependency in a lockfile is not this product's integration"
expect "nested-.claude fixture" "$NESTED" "true|true" \
    "the pathspec is ROOT-ANCHORED by decision (header: 'the anchoring decision'). If it has deliberately grown to exclude nested agent config, flip this expectation and say so there"

# --- 5. source-level shape guard -----------------------------------------------
for pair in "sentry:$sentry_line" "posthog:$posthog_line"; do
    key="${pair%%:*}"; line="${pair#*:}"
    for spec in ":(exclude).claude/**" ":(exclude)*.lock*"; do
        if [ "${line#*"$spec"}" != "$line" ]; then
            ok "$key grep carries '$spec'"
        else
            bad "$key grep no longer carries '$spec': $line"
        fi
    done
done

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "detect-capabilities tests: all green" >&2
    exit 0
else
    echo "detect-capabilities tests: FAILURES above" >&2
    exit 1
fi
