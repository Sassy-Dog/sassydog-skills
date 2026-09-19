#!/usr/bin/env bash
# test-fire-watch-block.sh — pins the contract between the daily-fire-watch
# routine's Slack post and its one automated consumer, `work-fire-watch`.
#
# Why this exists: the consumer was first written against THIS repo's
# `whats-on-fire` template and would have matched zero real posts — the routine
# runs the flattened copy in `sassydog-routines`, whose delivered post is Slack
# mrkdwn that changes prose shape from day to day (bullets one morning, inline
# runs the next). Two reviews found it, one by fetching the producer and one by
# reading the channel. The fix was to stop parsing prose: the routine appends a
# fenced `fire-watch-v1` machine block and the consumer reads only that. What
# this gate pins is the part a later tidy would undo without anything failing:
#
#   1. THE SENTINELS ARE SPELLED THE SAME IN BOTH HOMES. The consumer
#      (`skills/work-fire-watch/SKILL.md`) and the contract table
#      (`docs/ROUTINES.md` "Consumers of the posted report") both carry the
#      block name, the channel id, the poster's Slack user id, and the
#      rendered first line `Daily Fire Watch (` — the one WITHOUT the leading
#      `#`, which is how Slack delivers it and how the routines repo's own
#      heartbeat greps for it. A "fix" that restores the Markdown `# ` in one
#      home turns every real post into a stop. The poster id is the security
#      half: the routine posts through a user-scoped connector, so a "bot only"
#      rule can never match and an agent rationalises past it on the forgeable
#      `Sent using` footer — which is exactly the member-authored post the rule
#      exists to exclude. The channel id is the anchor name resolution cannot
#      forge. Neither may be dropped from either home.
#
#   2. THE HANDLE GRAMMAR HAS ONE HOME AND ACCEPTS WHAT THE BLOCK CAN EMIT.
#      `work-recommendations` §3 carries the closed regex and the slug rule;
#      `work-fire-watch` cites it and carries NO second regex literal — the two
#      had already diverged (`|human-only`) inside one PR. The vectors below run
#      the real org's workflow names (`CI`, `Release`, `Routine Heartbeat`)
#      through the slug rule as the prose states it and assert the result
#      matches, because an unslugged `ci-red/CI` silently degrades a red default
#      branch — the one P0 the producer ranks on its own — into a report-only
#      row. Negative vectors pin that the class is closed (`human-only` was
#      removed; `issue:398` is not a handle).
#
#   3. THE GRAMMAR EXTRACTION IS NOT VACUOUS. Exactly one regex literal is
#      found in its home; a flattened copy with it deleted reddens property 2
#      rather than passing on an empty pattern.
#
# Source-level, no `gh`, no network, no Slack.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONSUMER="$ROOT/skills/work-fire-watch/SKILL.md"
DELEGATE="$ROOT/skills/work-recommendations/SKILL.md"
CONTRACT="$ROOT/docs/ROUTINES.md"

fail=0
ok()  { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

for f in "$CONSUMER" "$DELEGATE" "$CONTRACT"; do
    [ -r "$f" ] || { echo "test-fire-watch-block: missing $f" >&2; exit 1; }
done

# --- 1. sentinels in both homes ------------------------------------------------
for needle in 'fire-watch-v1' 'C0BNNEE59PX' 'U0AAJ2WGMTQ' 'Daily Fire Watch (' 'daily-fire-watch could not run.' 'item|<repo>|<kind>|<id>|<tier>|<labels>|<title>' 'top|<rank>|<repo>|<kind>:<id>'; do
    for home in "$CONSUMER" "$CONTRACT"; do
        if grep -qF -- "$needle" "$home"; then
            ok "sentinel '$needle' present in ${home#"$ROOT"/}"
        else
            bad "sentinel '$needle' missing from ${home#"$ROOT"/}"
        fi
    done
done
# The rendered first line has no leading `# ` in either home's sentinel table.
for home in "$CONSUMER" "$CONTRACT"; do
    if grep -qF -- '`# Daily Fire Watch (' "$home" || grep -qE -- '^# Daily Fire Watch \(' "$home"; then
        bad "${home#"$ROOT"/} spells the first-line sentinel with a Markdown '# ' — Slack delivers it without one"
    else
        ok "${home#"$ROOT"/} spells the first-line sentinel as Slack renders it"
    fi
done

# --- 2. one grammar home, and it accepts the block's output -------------------
extract_regex() {  # prints every backticked literal that starts with ^( and ends with )$
    grep -o '`\^([^`]*)\$`' "$1" | sed 's/^`//; s/`$//'
}
n_home="$(extract_regex "$DELEGATE" | wc -l | tr -d ' ')"
n_consumer="$(extract_regex "$CONSUMER" | wc -l | tr -d ' ')"
if [ "$n_home" = "1" ]; then
    ok "work-recommendations carries exactly one handle regex"
else
    bad "work-recommendations carries $n_home handle regex literals (want 1)"
fi
if [ "$n_consumer" = "0" ]; then
    ok "work-fire-watch carries no handle regex literal of its own"
else
    bad "work-fire-watch carries $n_consumer handle regex literal(s) — the grammar has one home"
fi
if grep -qF -- 'work-recommendations` §3' "$CONSUMER"; then
    ok "work-fire-watch cites work-recommendations §3 as the grammar's home"
else
    bad "work-fire-watch does not cite work-recommendations §3"
fi

RE="$(extract_regex "$DELEGATE" | head -n1)"
if [ -z "$RE" ]; then bad "no handle regex extracted — the vector rows below cannot run"; fi

# The five kinds the consumer emits are the five the block defines, and the
# delegate writes exactly three marker prefixes. Bare counts elsewhere in prose
# are safe only while these re-derive them.
for kind in issue pr sentry cron ci-red; do
    if grep -qE -- "^\| \`$kind\` \| " "$CONSUMER"; then ok "consumer emits kind '$kind'"; else bad "consumer's handle table lacks kind '$kind'"; fi
done
markers="$(grep -oE -- '`[a-z-]+-source:`' "$DELEGATE" | sort -u | tr -d '`' | tr '\n' ' ')"
if [ "$markers" = "fire-watch-source: plate-source: sentry-source: " ]; then
    ok "delegate names exactly the three markers: $markers"
else
    bad "delegate's marker set is '$markers' (want fire-watch-source: plate-source: sentry-source:)"
fi
tiers_row="$(grep -E -- '^\| `tier` \|' "$CONSUMER" | cut -d'|' -f3 | grep -oE -- '`[A-Za-z0-9]+`' | tr -d '`' | sort | tr '\n' ' ')"
tiers_order="$(grep -E -- '^by tier — ' "$CONSUMER" | grep -oE -- '`[A-Za-z0-9]+`' | tr -d '`' | sort | tr '\n' ' ')"
if [ -n "$tiers_row" ] && [ "$tiers_row" = "$tiers_order" ]; then
    ok "tier value set equals the tier order list: $tiers_row"
else
    bad "tier values ('$tiers_row') and the order list ('$tiers_order') disagree"
fi

slug() {  # the slug rule as work-recommendations §3 states it
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}
# The prose must still state the three steps the function above implements.
for phrase in 'lowercase the source' 'outside `[a-z0-9._-]`' 'trim `-`'; do
    if grep -qF -- "$phrase" "$DELEGATE"; then
        ok "slug rule states: $phrase"
    else
        bad "slug rule no longer states: $phrase"
    fi
done

positive=(
    '#398' 'pr:#427' 'sentry:5512345' 'sentry:PLATFORM-H' 'sentry:TAILOREDTIP-IOS-4K7'
    "fire-watch:ci-red/$(slug 'CI')" "fire-watch:ci-red/$(slug 'Release')"
    "fire-watch:ci-red/$(slug 'Routine Heartbeat')" "fire-watch:cron/$(slug 'nightly-export')"
    "fire-watch:cron/$(slug 'cron_ci-runner.cve.watch')"
)
negative=(
    'fire-watch:ci-red/CI' 'fire-watch:ci-red/Routine Heartbeat' 'fire-watch:ci-red/'
    'human-only' 'issue:398' '#abc' 'sentry:' 'pr:427' 'fire-watch:secret/x' '398'
)
if [ -n "$RE" ]; then
    for v in "${positive[@]}"; do
        if [[ "$v" =~ $RE ]]; then ok "accepts '$v'"; else bad "rejects '$v' — the block can emit this"; fi
    done
    for v in "${negative[@]}"; do
        if [[ "$v" =~ $RE ]]; then bad "accepts '$v' — the grammar is closed"; else ok "rejects '$v'"; fi
    done
fi

# --- 3. the vectors have teeth: a widened grammar in a flattened copy flips one ---
tmp="$(mktemp)" || { echo "test-fire-watch-block: mktemp failed" >&2; exit 1; }
[ -n "$tmp" ] && [ -w "$tmp" ] || { echo "test-fire-watch-block: unusable temp file" >&2; exit 1; }
trap 'rm -f "$tmp"' EXIT
# Mutant: re-admit `human-only` as a handle kind (the divergence a prior review
# caught) and widen the slug class to accept uppercase.
sed -e 's/|fire-watch:(ci-red|cron)\/\[a-z0-9._-\]+)\$`/|fire-watch:(ci-red|cron)\/[A-Za-z0-9._-]+|human-only)$`/' "$DELEGATE" >"$tmp"
MRE="$(extract_regex "$tmp" | head -n1)"
if [ -n "$MRE" ] && [ "$MRE" != "$RE" ] && [[ 'human-only' =~ $MRE ]] && [[ 'fire-watch:ci-red/CI' =~ $MRE ]]; then
    ok "mutant grammar accepts 'human-only' and 'ci-red/CI' — the negative vectors are load-bearing"
else
    bad "mutant grammar did not flip the negative vectors — the vector rows are not pinning the class"
fi

if [ "$fail" -eq 0 ]; then
    echo "fire-watch block tests: all green"
    exit 0
fi
echo "fire-watch block tests: FAILURES above"
exit 1
