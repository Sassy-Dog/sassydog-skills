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
# pathspec is symmetric on purpose — a hook, a settings file or a CLAUDE.md that
# names `sentry.init` in prose is documentation rather than an integration, and
# an asymmetry between two adjacent lines reads as an oversight to the next
# editor, who fixes it in whichever direction they guess. Both keys are pinned
# so neither direction is a guess.
#
# WHAT THIS GATE IS NOT. It does not assert how the exclusion is SPELLED as its
# primary evidence. Properties 2-4 run the SHIPPED script inside real git
# fixtures and read its JSON, so a rewrite that keeps the behaviour passes and a
# clever pathspec that silently stops excluding fails. Property 5 is a shape
# guard beside that, not instead of it.
#
# Five properties are asserted:
#
#   1. Fixture adequacy. The two grep lines are EXTRACTED from the shipped
#      script, the `.claude` pathspec is stripped from each, and the resulting
#      pre-fix commands are run in the CONFIG fixture: both must MATCH there. If
#      they ever stop matching, the fixture no longer contains the self-match
#      and property 2 has become vacuous — so this says so loudly rather than
#      passing.
#   2. CONFIG fixture — the only `posthog` / `sentry.init` occurrences in the
#      tree are inside `.claude/` — detects `posthog: false` and
#      `sentry: false`. This is #317 itself; before the fix both were `true`.
#   3. SOURCE fixture — the same strings in tracked source outside `.claude/` —
#      detects `true` for both. The exclusion must not suppress a real hit.
#   4. BOTH fixture (config mention AND real source) detects `true` for both,
#      and the LOCK fixture (the strings only in `bun.lock`) detects `false` for
#      both — the pre-existing `*.lock*` exclusion still does its own job on the
#      line this change edited.
#   5. Source-level shape guard: each of the two grep lines carries BOTH
#      `:(exclude).claude/**` and `:(exclude)*.lock*`. Properties 2 and 4 rest
#      on git's pathspec semantics; this one fails the moment either pathspec is
#      dropped, on any git.
#
# THE MUTATION THAT PROVES IT IS NOT VACUOUSLY GREEN. Delete
# `':(exclude).claude/**'` from either grep line in
# `skills/setup-config/scripts/detect-capabilities.sh` and this gate goes red
# twice for that key: property 2 (the CONFIG fixture reports `true`) and
# property 5. Delete `':(exclude)*.lock*'` instead and property 4's LOCK
# fixture reports `true`. Empty either fixture's config file and property 1
# fails as inadequate instead of property 2 passing on nothing. All four were
# run before this file was committed.
#
# `gh` is MOCKED and every call fails: the probe requires it on PATH but
# degrades every gh-backed field to null/[] with a note, and none of those
# fields is read here. No network, and no real repo is touched — the fixtures
# are throwaway `mktemp -d` git repos.
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
# Real working-tree files, because `git grep` reads the tree. Four tiny repos;
# nothing here depends on size (that is issue #172's gate, not this one).
mkrepo() { # <dir>
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email test@example.invalid
    git -C "$1" config user.name test
}

commit_all() { # <dir>
    git -C "$1" add -A
    git -C "$1" commit -qm fixture
}

# The consumer's answer to §2c, written where setup-config writes it.
write_config() { # <dir>
    mkdir -p "$1/.claude/sassy-dog"
    cat > "$1/.claude/sassy-dog/survey-work.md" <<'CFG'
---
posthog: none
mobile: none
---

## extra-guardrails

This product has no analytics. A hook that mentions sentry.init in prose is
documentation, not an integration.
CFG
    mkdir -p "$1/.claude/hooks"
    printf '#!/usr/bin/env bash\n# posthog and sentry.init are named here as prose only\n' \
        > "$1/.claude/hooks/sassydog-format.sh"
}

# A real integration, in tracked source outside .claude/.
write_source() { # <dir>
    mkdir -p "$1/src"
    cat > "$1/src/analytics.ts" <<'SRC'
import posthog from "posthog-js";
import * as Sentry from "@sentry/browser";
Sentry.init({ dsn: process.env.DSN });
SRC
}

CONFIG="$WORK/config-only"
mkrepo "$CONFIG"; write_config "$CONFIG"
mkdir -p "$CONFIG/src"; printf 'export const noop = 1;\n' > "$CONFIG/src/app.ts"
commit_all "$CONFIG"

SOURCE="$WORK/source-only"
mkrepo "$SOURCE"; write_source "$SOURCE"; commit_all "$SOURCE"

BOTH="$WORK/both"
mkrepo "$BOTH"; write_config "$BOTH"; write_source "$BOTH"; commit_all "$BOTH"

LOCK="$WORK/lock-only"
mkrepo "$LOCK"
printf '"posthog-js@1.0.0": {}\n"@sentry/browser@8.0.0": {}\nsentry.init\n' > "$LOCK/bun.lock"
mkdir -p "$LOCK/src"; printf 'export const noop = 1;\n' > "$LOCK/src/app.ts"
commit_all "$LOCK"

# --- mock gh -------------------------------------------------------------------
# The probe refuses to start without gh on PATH, and treats every gh failure as a
# recorded detect_failure. None of the gh-backed fields is read here.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/usr/bin/env bash
exit 1
GH
chmod +x "$WORK/bin/gh"

# --- 1. fixture adequacy -------------------------------------------------------
# Strip the .claude pathspec from each EXTRACTED line and run the result in the
# CONFIG fixture. Both must match, or the fixture has stopped containing the
# self-match and property 2 proves nothing.
strip_claude_pathspec() { # <line>
    printf '%s\n' "$1" | sed "s|[[:space:]]*':(exclude)\.claude/\*\*'||"
}

probe_lines() { # <dir> <sentry-cmd> <posthog-cmd> -> "<sentry>|<posthog>"
    (
        cd "$1" || exit 1
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
    bad "could not strip ':(exclude).claude/**' from the extracted grep lines — either the pathspec is already gone (that is the #317 regression, see property 5) or it is spelled differently and this probe is inert"
else
    prefix_verdict="$(probe_lines "$CONFIG" "$prefix_sentry" "$prefix_posthog")"
    if [ "$prefix_verdict" = "true|true" ]; then
        ok "fixture adequacy: without the .claude exclusion both greps DO match the config fixture (sentry|posthog = $prefix_verdict)"
    else
        bad "fixture no longer proves the bug: with the .claude exclusion stripped, the shipped greps report '$prefix_verdict' on the config fixture instead of 'true|true'. Property 2 is vacuous until the fixture carries the self-match again"
    fi
fi

# --- 2-4. end to end: the shipped probe on each fixture ------------------------
verdict() { # <dir> -> "<sentry>|<posthog>" or a diagnostic
    local out
    out="$( cd "$1" && PATH="$WORK/bin:$PATH" bash "$REPO_ROOT/$DETECT" 2>/dev/null )"
    if [ -z "$out" ]; then
        printf '«no output»'
        return
    fi
    printf '%s' "$out" | jq -r '[(.sentry|tostring), (.posthog|tostring)] | join("|")' 2>/dev/null \
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
    "a tree whose only occurrences are under .claude/ must read as no integration; reporting true here is issue #317, and it makes every refresh contradict the config it just read"
expect "source-only fixture" "$SOURCE" "true|true" \
    "the exclusion has over-reached: a real SDK in tracked source outside .claude/ is exactly what this probe exists to find"
expect "both fixture" "$BOTH" "true|true" \
    "a real integration must still be detected when the config also mentions the word"
expect "lock-only fixture" "$LOCK" "false|false" \
    "the pre-existing ':(exclude)*.lock*' pathspec is gone or broken — a transitive dependency in a lockfile is not this product's integration"

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
