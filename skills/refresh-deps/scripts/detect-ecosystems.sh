#!/usr/bin/env bash
# detect-ecosystems.sh — read-only probe: which Dependabot ecosystems does THIS
# repo actually have, and which of them will hand Dependabot a lockfile it cannot
# regenerate? Emits one JSON object; every probe degrades to detected:false and
# appends to detect_failures rather than aborting (same contract as
# setup-hooks' detect-hook-stack.sh).
#
# Evidence rule: an ecosystem counts as detected only on TRACKED REPO FILES —
# never on what happens to be installed on this machine, because the rendered
# config must hold on every teammate's machine and in CI.
#
# `lockfile_risk` is the field that matters most. Dependabot updates a manifest
# (package.json, Podfile) but only writes the lockfile formats it supports. When
# it cannot, CI running a frozen-lockfile install rejects every PR it opens —
# qr-ninja hit exactly this and merged 0 of 20 npm PRs before removing the
# ecosystem. A true here means "this ecosystem needs a lockfile-sync workflow,
# or its PRs will be dead on arrival." Since Dependabot's native `bun`
# ecosystem GA'd (2025-02) the text bun.lock is written natively, so the risk
# survives only for the binary bun.lockb and for cocoapods.
#
# Matching is by PATH REGEX over `git ls-files`, not git pathspec globs: a
# pathspec like 'package.json' matches only the repo root, which would silently
# report "no npm" for every workspaces monorepo in the org. Anchor with (^|/).
#
# Usage: detect-ecosystems.sh   (run from anywhere inside the target repo)
# Exit:  0 ok · 1 jq missing or not a git repo
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "detect-ecosystems: jq not on PATH" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "detect-ecosystems: not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

FILES="$(git ls-files 2>/dev/null)" || { echo "detect-ecosystems: git ls-files failed" >&2; exit 1; }

failures=()
note() { failures+=("$1"); }

results=""
# add <ecosystem> <detected 0/1> <lockfile_risk 0/1> <why>
add() {
    local name="$1" det="$2" risk="$3" why="$4"
    results+=$(jq -cn --arg n "$name" --argjson d "$det" --argjson r "$risk" --arg w "$why" \
        '{($n): {detected: ($d == 1), lockfile_risk: ($r == 1), why: $w}}')$'\n'
}

# has <path-regex> — anchored at a path segment boundary, so it finds nested
# manifests in monorepos as well as root ones.
#
# Herestring, NOT `printf ... | grep -q`. Under `set -o pipefail`, `grep -q`
# exits on the first match, the writer takes SIGPIPE, and the pipeline reports
# 141 — so a MATCH reads as a miss. It only trips once the file list is long
# enough that the writer is still going when grep bails, which means it silently
# under-detects the largest repos while every small-repo test passes.
has() { grep -qE "$1" <<<"$FILES"; }

# --- github-actions: always safe. Touches workflow YAML only, no lockfile. ---
det=0; why="no tracked .github/workflows/*.y*ml"
if has '^\.github/workflows/.*\.ya?ml$'; then det=1; why="tracked workflow files"; fi
add "github-actions" "$det" 0 "$why"

# --- bun: native Dependabot ecosystem (GA 2025-02) ---------------------------
# Dependabot's `bun` ecosystem reads and REWRITES the text bun.lock itself
# (bun >= 1.1.39), so a bun repo needs no lockfile-sync workflow — its version
# PRs arrive frozen-lockfile valid. Caveats that stay true today: security
# updates are not yet supported for bun (version updates only), and the binary
# bun.lockb predates the text format and is NOT readable by the native
# ecosystem — a lockb-only repo falls through to the legacy npm +
# lockfile-sync classification below until it migrates
# (`bun install --save-text-lockfile`).
det=0; why="no tracked bun.lock"
if has '(^|/)bun\.lock$'; then
    if has '(^|/)package\.json$'; then
        det=1; why="tracked bun.lock + package.json — native bun ecosystem writes the text lockfile itself"
    else
        why="bun.lock without package.json — no manifest for Dependabot to update"
    fi
elif has '(^|/)bun\.lockb$'; then
    why="binary bun.lockb only — native bun needs the text bun.lock (bun >= 1.1.39); classified as legacy npm + lockfile sync"
fi
add "bun" "$det" 0 "$why"

# --- npm family: the package MANAGER decides whether Dependabot can finish ---
# Dependabot's npm ecosystem writes package-lock.json / yarn.lock / pnpm-lock.yaml.
# The text bun.lock belongs to the native bun ecosystem above, so it does NOT
# count as npm here. Only the legacy binary bun.lockb still lands in npm with
# lockfile_risk: no Dependabot ecosystem can write it, so those repos keep the
# npm + lockfile-sync pairing (or migrate the lockfile and re-run this probe).
det=0; risk=0; why="no tracked package.json"
if has '(^|/)package\.json$'; then
    if has '(^|/)bun\.lock$'; then
        why="package.json + bun.lock — covered by the native bun ecosystem, not npm"
    elif has '(^|/)bun\.lockb$'; then
        det=1; risk=1
        why="package.json + binary bun.lockb — no Dependabot ecosystem writes it; legacy path: npm + lockfile sync (or migrate via bun install --save-text-lockfile)"
    elif has '(^|/)pnpm-lock\.yaml$'; then
        det=1; why="package.json + pnpm-lock.yaml (Dependabot writes this natively)"
    elif has '(^|/)yarn\.lock$'; then
        det=1; why="package.json + yarn.lock (Dependabot writes this natively)"
    elif has '(^|/)package-lock\.json$'; then
        det=1; why="package.json + package-lock.json (Dependabot writes this natively)"
    else
        det=1; why="package.json with no lockfile — nothing to go stale"
    fi
fi
add "npm" "$det" "$risk" "$why"

# --- cocoapods: Dependabot has NO cocoapods ecosystem at all ----------------
# Pods drift in via a Podfile that a native bump touches; the .lock must be
# refreshed out of band. Flagged so the caller renders the pod sync workflow.
det=0; risk=0; why="no tracked Podfile"
if has '(^|/)Podfile$'; then
    det=1; risk=1; why="tracked Podfile — no Dependabot cocoapods ecosystem; needs lockfile sync"
fi
add "cocoapods" "$det" "$risk" "$why"

# --- nuget ------------------------------------------------------------------
det=0; why="no tracked *.csproj / *.sln / Directory.Packages.props"
if has '\.csproj$|\.sln$|(^|/)Directory\.Packages\.props$'; then
    det=1; why="tracked .NET project files"
fi
add "nuget" "$det" 0 "$why"

# --- pub (Dart / Flutter) ---------------------------------------------------
det=0; why="no tracked pubspec.yaml"
if has '(^|/)pubspec\.yaml$'; then det=1; why="tracked pubspec.yaml"; fi
add "pub" "$det" 0 "$why"

# --- gomod ------------------------------------------------------------------
det=0; why="no tracked go.mod"
if has '(^|/)go\.mod$'; then det=1; why="tracked go.mod"; fi
add "gomod" "$det" 0 "$why"

# --- swift ------------------------------------------------------------------
det=0; why="no tracked Package.swift"
if has '(^|/)Package\.swift$'; then det=1; why="tracked Package.swift"; fi
add "swift" "$det" 0 "$why"

# --- cargo ------------------------------------------------------------------
det=0; why="no tracked Cargo.toml"
if has '(^|/)Cargo\.toml$'; then det=1; why="tracked Cargo.toml"; fi
add "cargo" "$det" 0 "$why"

# --- pip --------------------------------------------------------------------
det=0; why="no tracked requirements.txt / pyproject.toml"
if has '(^|/)requirements\.txt$'; then
    det=1; why="tracked requirements.txt"
elif has '(^|/)pyproject\.toml$'; then
    det=1; why="tracked pyproject.toml"
fi
add "pip" "$det" 0 "$why"

# --- gradle -----------------------------------------------------------------
det=0; why="no tracked build.gradle(.kts)"
if has '(^|/)build\.gradle(\.kts)?$'; then det=1; why="tracked build.gradle"; fi
add "gradle" "$det" 0 "$why"

# --- docker -----------------------------------------------------------------
det=0; why="no tracked Dockerfile"
if has '(^|/)Dockerfile[^/]*$'; then det=1; why="tracked Dockerfile"; fi
add "docker" "$det" 0 "$why"

# --- CI workflow: the check a merge gate would require ----------------------
ci_workflow=""
for cand in ci.yml ci.yaml CI.yml build.yml test.yml; do
    if [ -f ".github/workflows/$cand" ]; then ci_workflow="$cand"; break; fi
done
[ -z "$ci_workflow" ] && note "no conventional CI workflow file (ci.yml/build.yml/test.yml) found"

repo_slug="$(git config --get remote.origin.url 2>/dev/null \
    | sed -E 's#(git@|https://)github\.com[:/]##; s#\.git$##')"
[ -z "$repo_slug" ] && note "no origin remote — repo slug unresolved"

fails_json="$(printf '%s\n' "${failures[@]+"${failures[@]}"}" | jq -Rs 'split("\n")|map(select(length>0))')"

printf '%s' "$results" | jq -s \
    --arg repo "$repo_slug" \
    --arg ci "$ci_workflow" \
    --argjson fails "$fails_json" \
    'add | {
        repo: $repo,
        ci_workflow: (if $ci == "" then null else $ci end),
        ecosystems: .,
        present: [ to_entries[] | select(.value.detected) | .key ],
        needs_lockfile_sync: [ to_entries[] | select(.value.detected and .value.lockfile_risk) | .key ],
        detect_failures: $fails
     }'
