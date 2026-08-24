#!/usr/bin/env bash
# test-review-orchestrator-allowlist.sh — every agent the PR-review orchestrator
# can dispatch, and every reviewer the config contract names as a legal
# `review_surfaces:` value, must SHIP IN THIS PLUGIN (issue #246).
#
# Why this exists: `agents/pr-review-orchestrator.md` fans out only to reviewers
# that live in this repo's `agents/` directory — that is what makes the review
# resolve in a consumer repo that has the plugin and nothing else. Nothing
# checked it. The failure this catches is invisible to the author who ships it:
# agent names like `react-typescript-engineer` and `iac-cloud-architect` exist as
# USER-LEVEL agents in a typical Sassy Dog developer's `~/.claude/agents/`, so a
# PR adding one to the surface table passes every gate, works when the author
# tests it, and fails only in a consumer repo where that agent does not exist.
# #236's original proposal did exactly that — its `review_surfaces:` example
# named both — and it was caught only by someone checking `agents/` by hand.
#
# That is the #167 shape: a reference correct on the machine it was written on
# and wrong everywhere it ships. #167's answer was a file-listing comparison
# across the tracked tree, and this gate is the same posture: extract the names,
# compare them against what `agents/` actually holds. No `gh`, no network.
#
# Six sections:
#
#   1. The orchestrator's dispatch set. The Reviewer column of its surface
#      table, every `<x>-reviewer` token anywhere in the body, and every value
#      of its `review_surfaces:` example must each have an `agents/<name>.md`.
#      Any OTHER `sassy-dog:<name>` token must resolve to an agent or a skill
#      this plugin ships — a prose mention of `sassy-dog:send-it` is legal, a
#      mention of `sassy-dog:react-typescript-engineer` is not.
#   2. The config contract's `review_surfaces` surface (issue #246's Decision).
#      #238 restricted the map's values to the same nine reviewers and
#      `config-contract.md` transcribes that list, so a stale name there is the
#      identical defect one file over — and leaving it out would reproduce the
#      very third-copy shape #167 is about.
#   3. Every OTHER tracked Markdown file carrying a `review_surfaces:` block
#      (README.md today). The value restriction is a property of the map, not of
#      one document; a fourth copy of the example is the same defect again.
#   4-6. Mutation proofs. A gate that cannot go red is decorative, so each
#      extraction path above is fired at a doctored copy of its own source in a
#      synthetic tree — including the unprefixed BARE name, which is exactly how
#      #236's sketch wrote it — and that same synthetic tree is first scanned
#      UNMUTATED, so a harness failing for an unrelated reason (an incomplete
#      agents/ mirror) cannot be mistaken for a working gate.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-review-orchestrator-allowlist.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-review-orchestrator-allowlist: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

ORCH="agents/pr-review-orchestrator.md"
CONTRACT="skills/setup-config/references/config-contract.md"

for f in "$ORCH" "$CONTRACT"; do
    [ -f "$f" ] || { echo "test-review-orchestrator-allowlist: missing input $f" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "review-orchestrator-allowlist tests (work: $WORK)" >&2

# --- extractors ---------------------------------------------------------------
# Each takes a FILE and prints candidate agent names, one per line, unsorted.

# The Reviewer column of the orchestrator's surface table — the dispatch set
# itself. Scoped to the table whose header names `subagent_type`, so an
# unrelated table added to the same file later is not read as agent names (and
# if that header is ever reworded, section 1's vacuity floor fires rather than
# the guard quietly covering nothing).
table_targets() {
    awk -F'|' '
        /^\|/ {
            cell = $(NF - 1)
            gsub(/`/, "", cell)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
            if (cell ~ /subagent_type/) { intable = 1; next }
            if (!intable) next
            if (cell == "" || cell ~ /^-+$/) next
            print cell
            next
        }
        { intable = 0 }
    ' "$1"
}

# Every `<x>-reviewer` token, with or without the `sassy-dog:` prefix (the
# character class stops at the `:`, so the prefixed form yields the bare name).
reviewer_tokens() {
    grep -oE '[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*-reviewer' "$1"
}

# Every `sassy-dog:<name>` token, prefix stripped.
namespaced_tokens() {
    grep -oE 'sassy-dog:[a-zA-Z0-9_-]+' "$1" | sed 's/^sassy-dog://'
}

# The values of every `review_surfaces:` map entry in the file. Taking the text
# after the LAST colon on the line handles a quoted or unquoted glob key and a
# prefixed or bare value in one move — and the BARE form is the one that
# matters, since that is how #236's sketch named a user-level agent.
map_values() {
    awk '
        /^[[:space:]]*review_surfaces:[[:space:]]*(#.*)?$/ { inmap = 1; next }
        inmap && /^[[:space:]]+[^[:space:]]/ { print; next }
        { inmap = 0 }
    ' "$1" |
        sed -e 's/[[:space:]]*#.*$//' -e 's/[`"'"'"']//g' -e 's/.*://' -e 's/[[:space:]]//g' |
        grep -v '^$'
}

# The body of a `### <heading>` section, written to a temp file whose path is
# printed (the extractors above all take a file).
section_of() {
    local out
    out="$(mktemp "$WORK/section.XXXXXX")"
    awk -v pat="$2" '/^#+ /{ insec = ($0 ~ "^### .*" pat) } insec' "$1" >"$out"
    printf '%s\n' "$out"
}

# --- resolvers ----------------------------------------------------------------
# Names arrive on stdin; each prints back only the ones that do NOT resolve
# against the tree rooted at $1. Pure — they never touch $fail, so the mutation
# proofs below run the very same code path the real checks run.

unresolved_agents() {
    local root="$1" name
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        [ -f "$root/agents/$name.md" ] || printf '%s\n' "$name"
    done
}

unresolved_plugin_refs() {
    local root="$1" name
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        [ -f "$root/agents/$name.md" ] || [ -d "$root/skills/$name" ] || printf '%s\n' "$name"
    done
}

scan_orchestrator() {  # FILE ROOT -> every name it references that ROOT does not ship
    local file="$1" root="$2"
    { table_targets "$file"; reviewer_tokens "$file"; map_values "$file"; } |
        sed 's/^sassy-dog://' | sort -u | unresolved_agents "$root"
    namespaced_tokens "$file" | grep -v -- '-reviewer$' | sort -u | unresolved_plugin_refs "$root"
}

scan_contract() {  # FILE ROOT -> every reviewer it names that ROOT does not ship
    local file="$1" root="$2" sec
    sec="$(section_of "$file" 'review_surfaces')"
    { reviewer_tokens "$sec"; map_values "$file"; } |
        sed 's/^sassy-dog://' | sort -u | unresolved_agents "$root"
    rm -f "$sec"
}

# --- 1. the orchestrator dispatches only agents this plugin ships -------------
missing="$(scan_orchestrator "$ORCH" ".")"
if [ -n "$missing" ]; then
    bad "$ORCH references agents this plugin does not ship: $(echo "$missing" | tr '\n' ' ')— add agents/<name>.md or use one of the shipped reviewers (issue #246)"
else
    ok "$ORCH references only agents/skills this plugin ships"
fi

# Vacuity: a broken extractor reports a clean tree exactly like a correct one.
# Both floors are today's shipped nine — the set may grow freely; a genuine
# REMOVAL is a deliberate change that updates these two numbers with it.
n_table="$(table_targets "$ORCH" | sort -u | grep -c .)"
n_tokens="$(reviewer_tokens "$ORCH" | sort -u | grep -c .)"
if [ "$n_table" -ge 9 ] && [ "$n_tokens" -ge 9 ]; then
    ok "extraction is live: $n_table surface-table targets, $n_tokens distinct *-reviewer tokens"
else
    bad "extraction scored only $n_table table targets / $n_tokens reviewer tokens (expected >= 9 of each) — the matcher is broken, not the tree clean"
fi

# --- 2. the config contract's review_surfaces surface (#246's Decision) -------
missing="$(scan_contract "$CONTRACT" ".")"
if [ -n "$missing" ]; then
    bad "$CONTRACT names reviewers this plugin does not ship: $(echo "$missing" | tr '\n' ' ')— #238 restricts review_surfaces values to the nine shipped agents (issue #246)"
else
    ok "$CONTRACT's review_surfaces surface names only shipped reviewers"
fi

# Vacuity for section 2: the section must be FOUND (an empty one silently covers
# nothing) and the file must yield at least one map value. The reviewer-token
# extractor's own health is proved by section 1's floor, so the transcription in
# this section is deliberately not floored — a future rewording that stops
# transcribing the nine and points at `agents/` instead would be one copy fewer,
# not a regression to fail on.
sec="$(section_of "$CONTRACT" 'review_surfaces')"
n_sec="$(grep -c . "$sec")"
n_map="$(map_values "$CONTRACT" | grep -c .)"
rm -f "$sec"
if [ "$n_sec" -gt 0 ] && [ "$n_map" -ge 1 ]; then
    ok "contract extraction is live: ### review_surfaces section is $n_sec lines, $n_map map values read"
else
    bad "contract extraction found a $n_sec-line section and $n_map map values — the '### review_surfaces' heading or the map block shape moved"
fi

# --- 3. every other tracked doc carrying a review_surfaces: block ------------
# The value restriction belongs to the map, not to one document, and README.md
# carries the same example. A copy is a copy at the moment it is written.
map_files=0
map_entries=0
while IFS= read -r f; do
    vals="$(map_values "$f")"
    [ -z "$vals" ] && continue
    map_files=$((map_files + 1))
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        map_entries=$((map_entries + 1))
        v="${v#sassy-dog:}"
        [ -f "agents/$v.md" ] || bad "$f's review_surfaces example names '$v', which this plugin does not ship (issue #246)"
    done <<<"$vals"
done < <(git ls-files '*.md')
if [ "$map_files" -ge 2 ] && [ "$map_entries" -ge 3 ]; then
    ok "$map_entries review_surfaces values across $map_files tracked docs all name shipped agents"
else
    bad "the tree sweep found only $map_entries values in $map_files docs — the review_surfaces block matcher is broken, not the tree clean"
fi

# --- synthetic tree for the mutation proofs ----------------------------------
# Mirrors what the plugin ships (names only), so a doctored copy is scanned
# against a tree that is complete except for the agent it invents.
mkdir -p "$WORK/mut/agents" "$WORK/mut/skills"
for f in agents/*.md; do : >"$WORK/mut/$f"; done
for d in skills/*/; do mkdir -p "$WORK/mut/${d%/}"; done

# --- 4. control: the mirror reaches the same verdict as the real tree ---------
# Asserted as an EQUALITY with sections 1-2 rather than as "clean", so a genuine
# regression in the shipped files fails there and only there — a control that
# demanded clean would fire a second, misleading line blaming the harness.
real_verdict="$( { scan_orchestrator "$ORCH" "."; scan_contract "$CONTRACT" "."; } | sort -u)"
mirror_verdict="$( { scan_orchestrator "$ORCH" "$WORK/mut"; scan_contract "$CONTRACT" "$WORK/mut"; } | sort -u)"
if [ "$real_verdict" = "$mirror_verdict" ]; then
    ok "control: the synthetic tree reaches the same verdict as the real one"
else
    bad "control: the synthetic agents/ mirror is incomplete (extra unresolved: $(comm -13 <(printf '%s\n' "$real_verdict") <(printf '%s\n' "$mirror_verdict") | tr '\n' ' ')) — the mutation proofs below would 'fail' for the wrong reason"
fi

# --- 5. mutation: the orchestrator -------------------------------------------
# M1 — a surface-table row rerouted to a user-level agent. This is the exact
# #236 near-miss: it resolves on the author's machine and nowhere else.
awk '!done && /^\| / && /sassy-dog:/ {
        sub(/sassy-dog:[a-z0-9-]+/, "sassy-dog:react-typescript-engineer"); done = 1
     } 1' "$ORCH" >"$WORK/mut/m1.md"
m1="$(scan_orchestrator "$WORK/mut/m1.md" "$WORK/mut")"
if grep -qx 'react-typescript-engineer' <<<"$m1"; then
    ok "mutation M1: a surface-table row naming a user-level agent FAILS the gate"
else
    bad "mutation M1: a surface-table row rerouted to react-typescript-engineer went undetected"
fi

# M2 — a fan-out call naming a plausible reviewer this plugin does not ship.
{ cat "$ORCH"; printf '\nAgent({ subagent_type: "sassy-dog:frontend-reviewer" })\n'; } >"$WORK/mut/m2.md"
m2="$(scan_orchestrator "$WORK/mut/m2.md" "$WORK/mut")"
if grep -qx 'frontend-reviewer' <<<"$m2"; then
    ok "mutation M2: an unshipped *-reviewer dispatch FAILS the gate"
else
    bad "mutation M2: a dispatch to the unshipped frontend-reviewer went undetected"
fi

# --- 6. mutation: the config contract ----------------------------------------
# M3 — a BARE (unprefixed) map value, the form #236's sketch actually used.
awk '/^[[:space:]]*review_surfaces:/ && !done {
        print; print "  \"apps/web/**\": react-typescript-engineer"; done = 1; next
     } 1' "$CONTRACT" >"$WORK/mut/m3.md"
m3="$(scan_contract "$WORK/mut/m3.md" "$WORK/mut")"
if grep -qx 'react-typescript-engineer' <<<"$m3"; then
    ok "mutation M3: a bare, unprefixed review_surfaces value FAILS the gate"
else
    bad "mutation M3: a bare react-typescript-engineer map value went undetected"
fi

# M4 — the transcribed nine drifting out of step with agents/, the #167 shape.
sed 's/dx-docs-reviewer/docs-reviewer/g' "$CONTRACT" >"$WORK/mut/m4.md"
m4="$(scan_contract "$WORK/mut/m4.md" "$WORK/mut")"
if grep -qx 'docs-reviewer' <<<"$m4"; then
    ok "mutation M4: a stale name in the transcribed allowlist FAILS the gate"
else
    bad "mutation M4: a stale docs-reviewer in the contract's enumeration went undetected"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "review-orchestrator-allowlist tests: all pass" >&2
    exit 0
fi
echo "review-orchestrator-allowlist tests: FAILURES above" >&2
exit 1
