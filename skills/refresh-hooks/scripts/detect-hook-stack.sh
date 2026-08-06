#!/usr/bin/env bash
# detect-hook-stack.sh — read-only probe: which formatter/linter tools does THIS
# repo's configuration call for? Emits one JSON object; every probe degrades to
# detected:false and appends to detect_failures rather than aborting (same
# contract as refresh-skills' detect-capabilities.sh).
#
# Evidence rule: a tool counts as detected only on REPO EVIDENCE (config file,
# manifest section, tracked file types) — never on what happens to be installed
# on this machine, because committed hooks must hold on every teammate's
# machine. references/detection.md documents each probe and its traps.
#
# Usage: detect-hook-stack.sh   (run from anywhere inside the target repo)
# Exit:  0 ok · 1 missing gh-independent tooling (jq) or not a git repo
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "detect-hook-stack: jq not on PATH" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "detect-hook-stack: not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

failures=()
note() { failures+=("$1"); }

# tool <name> <detected 0/1> <why>
results=""
add() {
    local name="$1" det="$2" why="$3"
    results+=$(jq -cn --arg n "$name" --argjson d "$det" --arg w "$why" \
        '{($n): {detected: ($d == 1), why: $w}}')$'\n'
}

has_tracked() { git ls-files "$1" | head -1 | grep -q .; }

# --- ruff: config section or ruff.toml, plus tracked *.py -------------------
why=""
det=0
if has_tracked '*.py'; then
    if [ -f ruff.toml ] || [ -f .ruff.toml ]; then
        det=1; why="ruff.toml present + tracked *.py"
    elif [ -f pyproject.toml ] && grep -q '^\[tool\.ruff' pyproject.toml 2>/dev/null; then
        det=1; why="pyproject.toml [tool.ruff] + tracked *.py"
    else
        why="tracked *.py but no ruff config (add ruff.toml or [tool.ruff] to opt in)"
    fi
else
    why="no tracked *.py"
fi
add ruff "$det" "$why"

# --- prettier: config file or package.json "prettier" key -------------------
why=""; det=0
if [ -f .prettierrc ] || [ -f .prettierrc.json ] || [ -f .prettierrc.yaml ] || [ -f .prettierrc.yml ] \
    || [ -f .prettierrc.js ] || [ -f prettier.config.js ] || [ -f prettier.config.mjs ]; then
    det=1; why="prettier config file present"
elif [ -f package.json ] && jq -e '.prettier' package.json >/dev/null 2>&1; then
    det=1; why="package.json prettier key"
else
    why="no prettier config"
fi
add prettier "$det" "$why"

# --- markdownlint: cli2 config + tracked *.md --------------------------------
why=""; det=0
if [ -f .markdownlint-cli2.jsonc ] || [ -f .markdownlint-cli2.yaml ] || [ -f .markdownlint.jsonc ] || [ -f .markdownlint.json ]; then
    if has_tracked '*.md'; then det=1; why="markdownlint config + tracked *.md"; else why="config but no tracked *.md"; fi
else
    why="no markdownlint config"
fi
add markdownlint "$det" "$why"

# --- shellcheck: tracked *.sh (no config file convention — presence of shell
#     scripts IS the evidence; CI repos that shellcheck already prove intent) --
why=""; det=0
if has_tracked '*.sh'; then
    det=1; why="tracked *.sh"
    grep -rq "shellcheck" .github/workflows/ 2>/dev/null && why="tracked *.sh + shellcheck in CI"
else
    why="no tracked *.sh"
fi
add shellcheck "$det" "$why"

# --- dart / rustfmt / gofmt / dotnet-format: manifest presence ----------------
if [ -f pubspec.yaml ]; then add dart 1 "pubspec.yaml"; else add dart 0 "no pubspec.yaml"; fi
if [ -f Cargo.toml ]; then add rustfmt 1 "Cargo.toml"; else add rustfmt 0 "no Cargo.toml"; fi
if [ -f go.mod ]; then add gofmt 1 "go.mod"; else add gofmt 0 "no go.mod"; fi
why=""; det=0
if has_tracked '*.sln' || has_tracked '*.csproj'; then
    det=1; why="tracked .sln/.csproj (SLOW per-edit — opt-in only)"
else
    why="no .sln/.csproj"
fi
add dotnet_format "$det" "$why"

# --- existing generated hooks (refresh-mode signal) ---------------------------
existing="[]"
if ls .claude/hooks/sassydog-*.sh >/dev/null 2>&1; then
    existing=$(ls .claude/hooks/sassydog-*.sh | jq -Rn '[inputs]')
fi

# ------------------------------------------------------------------------------
tools=$(printf '%s' "$results" | jq -sc 'add // {}')
jq -n \
    --arg root "$ROOT" \
    --argjson tools "$tools" \
    --argjson existing "$existing" \
    --argjson fails "$(printf '%s\n' "${failures[@]+"${failures[@]}"}" | jq -Rn '[inputs | select(length > 0)]')" \
    '{repo_root: $root, tools: $tools, existing_generated_hooks: $existing, detect_failures: $fails}'
