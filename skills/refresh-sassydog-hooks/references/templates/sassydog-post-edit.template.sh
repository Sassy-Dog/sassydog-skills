#!/usr/bin/env bash
# generated-by: ai-agent-skills:refresh-sassydog-hooks | template: sassydog-post-edit | template-version: 1
#
# PostToolUse (Edit|Write) formatter/linter dispatcher. Reads the hook event
# JSON on stdin, extracts the edited file's path, routes by extension.
#
# Contract:
#   - formatters fix in place, silently                    -> exit 0
#   - linters with UNFIXABLE findings print them to stderr -> exit 2
#     (the harness feeds stderr back to Claude for an immediate fix)
#   - anything unexpected (no path, missing tool, no route) -> exit 0, never block
#
# TEMPLATE NOTE (stripped on render): every `# {{IF:<TOOL>}} ... # {{ENDIF}}`
# block below is kept only when Phase 1 detected that tool in the target repo;
# the marker comment lines themselves are always removed. With all blocks
# present this file is valid bash that passes lint clean, so any render (block
# deletion only) is valid by construction. Hand-edits to a rendered copy are
# overwritten on refresh.
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

lint_fail() {  # $1 = tool label, $2 = findings
    {
        echo "$1 findings in $file (fix these now):"
        echo "$2" | head -20
    } >&2
    exit 2
}

case "$file" in
# {{IF:RUFF}}
    *.py)
        command -v ruff >/dev/null 2>&1 || exit 0
        ruff format --quiet "$file" >/dev/null 2>&1 || true
        if ! out=$(ruff check --fix --quiet "$file" 2>&1); then
            lint_fail "ruff (unfixable)" "$out"
        fi
        ;;
# {{ENDIF}}
# {{IF:PRETTIER}}
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.css|*.scss|*.json)
        command -v npx >/dev/null 2>&1 || exit 0
        npx --no-install prettier --write --log-level silent "$file" >/dev/null 2>&1 || true
        ;;
# {{ENDIF}}
# {{IF:MARKDOWNLINT}}
    *.md)
        command -v npx >/dev/null 2>&1 || exit 0
        npx -y markdownlint-cli2 --fix "$file" >/dev/null 2>&1 || true
        if ! out=$(npx -y markdownlint-cli2 "$file" 2>&1); then
            lint_fail "markdownlint (unfixable)" "$(echo "$out" | grep -v '^npm')"
        fi
        ;;
# {{ENDIF}}
# {{IF:SHELLCHECK}}
    *.sh)
        command -v shellcheck >/dev/null 2>&1 || exit 0
        if ! out=$(shellcheck -S warning "$file" 2>&1); then
            lint_fail "shellcheck" "$out"
        fi
        ;;
# {{ENDIF}}
# {{IF:DART}}
    *.dart)
        command -v dart >/dev/null 2>&1 || exit 0
        dart format "$file" >/dev/null 2>&1 || true
        ;;
# {{ENDIF}}
# {{IF:RUSTFMT}}
    *.rs)
        command -v rustfmt >/dev/null 2>&1 || exit 0
        rustfmt "$file" >/dev/null 2>&1 || true
        ;;
# {{ENDIF}}
# {{IF:GOFMT}}
    *.go)
        command -v gofmt >/dev/null 2>&1 || exit 0
        gofmt -w "$file" >/dev/null 2>&1 || true
        ;;
# {{ENDIF}}
# {{IF:DOTNET_FORMAT}}
    *.cs)
        command -v dotnet >/dev/null 2>&1 || exit 0
        dotnet format --include "$file" >/dev/null 2>&1 || true
        ;;
# {{ENDIF}}
esac

exit 0
