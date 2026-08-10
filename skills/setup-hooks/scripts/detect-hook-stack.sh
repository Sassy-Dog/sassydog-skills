#!/usr/bin/env bash
# detect-hook-stack.sh — read-only probe: which formatter/linter tools does THIS
# repo's configuration call for? Emits one JSON object; every probe degrades to
# detected:false and appends to detect_failures rather than aborting (same
# contract as setup-config' detect-capabilities.sh).
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

# tool <name> <detected 0/1> <why> [extra-json-object]
results=""
add() {
    local name="$1" det="$2" why="$3" extra="${4:-}"
    [ -n "$extra" ] || extra='{}'
    results+=$(jq -cn --arg n "$name" --argjson d "$det" --arg w "$why" --argjson e "$extra" \
        '{($n): ({detected: ($d == 1), why: $w} + $e)}')$'\n'
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

# markdownlint version pin: the hook must lint with the SAME markdownlint-cli2
# the repo's CI enforces. An unpinned `npx -y markdownlint-cli2` resolves to
# LATEST at hook time, so a repo whose CI pins an older release gets a hook
# that blocks on rules CI does not run (measured: CI 0.18.1 vs hook 0.23.2,
# MD060 flagging a README CI calls clean). Precedence: an explicit
# markdownlint-cli2@<spec> in .github/workflows/*, then in a shell script those
# workflows invoke (one hop — the common "CI calls scripts/preflight.sh"
# shape), then Makefile/justfile/package.json, then the package.json dependency
# range. Empty pin => the render drops the blocking half and is fix-only.
pin_spec_in() {  # <file> -> prints the pinned spec (version or range), or nothing
    local f="$1" hit
    [ -f "$f" ] || return 1
    hit=$(grep -ohE 'markdownlint-cli2@[0-9A-Za-z.^~><=*+|-]+' "$f" 2>/dev/null | head -1)
    [ -n "$hit" ] || return 1
    printf '%s' "${hit#markdownlint-cli2@}"
}

mdl_pin=""; mdl_pin_source=""
scan=()
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] && scan+=("$f")
done
if [ ${#scan[@]} -gt 0 ]; then
    # one hop: the shell scripts those workflows invoke
    while IFS= read -r ref; do
        ref="${ref#./}"
        [ -n "$ref" ] && [ -f "$ref" ] && scan+=("$ref")
    done < <(grep -ohE '[A-Za-z0-9_./-]+\.sh' "${scan[@]}" 2>/dev/null | sort -u)
fi
for f in Makefile makefile GNUmakefile justfile Justfile .justfile package.json; do
    [ -f "$f" ] && scan+=("$f")
done
for f in "${scan[@]+"${scan[@]}"}"; do
    if spec=$(pin_spec_in "$f"); then
        mdl_pin="$spec"; mdl_pin_source="$f"
        break
    fi
done
if [ -z "$mdl_pin" ] && [ -f package.json ]; then
    spec=$(jq -r '(.devDependencies["markdownlint-cli2"] // .dependencies["markdownlint-cli2"]) // empty' package.json 2>/dev/null)
    if [ -n "$spec" ]; then mdl_pin="$spec"; mdl_pin_source="package.json (dependency range)"; fi
fi
if [ "$det" = 1 ]; then
    if [ -n "$mdl_pin" ]; then
        why="$why + pin markdownlint-cli2@$mdl_pin from $mdl_pin_source"
    else
        why="$why + NO version pin discovered — render fix-only (blocking half omitted)"
        note "markdownlint: no version pin found in .github/workflows/*, CI shell scripts, Makefile, justfile or package.json — the hook renders fix-only so it cannot block on rules CI does not run"
    fi
fi
add markdownlint "$det" "$why" \
    "$(jq -cn --arg p "$mdl_pin" --arg s "$mdl_pin_source" '{pin: $p, pin_source: $s}')"

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
