#!/usr/bin/env bash
# render-dependabot.sh — render .github/dependabot.yml from the template and a
# detect-ecosystems.sh report. Writes to stdout; renders nothing else (the
# workflow templates have no per-location repeat and stay hand-rendered).
#
# Why a script rather than "substitute and delete by hand": v3 of the template
# repeats a block PER (ecosystem, directory) pair, and getting that wrong is
# invisible — a lane at the wrong directory is valid YAML that finds nothing
# (issue #169). It implements the three rules documented in the template
# header, and nothing else:
#
#   1. drop the template's own header (everything before the `---` line)
#   2. `# {{IF:FLAG}} … # {{ENDIF}}` survives only for a DETECTED ecosystem
#   3. `# {{FOREACH:DIRECTORY}} … # {{ENDFOREACH}}` is emitted once per
#      directory that ecosystem was detected at, with {{DIRECTORY}} substituted
#
# It refuses to guess: an ecosystem detected with an empty directory list is
# reported on stderr and its block is DROPPED rather than defaulting to "/" —
# defaulting to "/" is precisely the bug this replaces.
#
# ALWAYS pass the result through validate-dependabot.sh before writing it into
# a repo. Rendering is no longer valid-by-construction (see the template
# header); the post-render assertion is what took over that job.
#
# Usage:
#   render-dependabot.sh --detect-json FILE [--template FILE] [--out FILE]
#   detect-ecosystems.sh | render-dependabot.sh --detect-json -
# Exit: 0 rendered · 1 bad input, malformed template, or a token left behind
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "render-dependabot: jq not on PATH" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../references/templates/dependabot.yml.template"
DETECT=""
OUT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --detect-json) DETECT="${2:-}"; shift 2 || exit 1 ;;
        --template)    TEMPLATE="${2:-}"; shift 2 || exit 1 ;;
        --out)         OUT="${2:-}"; shift 2 || exit 1 ;;
        *) echo "render-dependabot: unknown argument '$1'" >&2; exit 1 ;;
    esac
done

[ -n "$DETECT" ] || { echo "render-dependabot: --detect-json is required (use - for stdin)" >&2; exit 1; }
[ -r "$TEMPLATE" ] || { echo "render-dependabot: cannot read template '$TEMPLATE'" >&2; exit 1; }

if [ "$DETECT" = "-" ]; then
    detect_json="$(cat)"
else
    [ -r "$DETECT" ] || { echo "render-dependabot: cannot read '$DETECT'" >&2; exit 1; }
    detect_json="$(cat "$DETECT")"
fi
jq -e . >/dev/null 2>&1 <<<"$detect_json" || { echo "render-dependabot: --detect-json is not valid JSON" >&2; exit 1; }

# flag_to_ecosystem GITHUB_ACTIONS -> github-actions
flag_to_ecosystem() { echo "$1" | tr '[:upper:]_' '[:lower:]-'; }

rendered=""
in_header=1
keep=1
in_if=0
collecting=0
buf=""
eco=""
dirs=""
fail=0

while IFS= read -r line; do
    if [ "$in_header" = "1" ]; then
        # The template's own header explains the render rules and must never
        # reach a consumer repo; the document start is where output begins.
        [ "$line" = "---" ] || continue
        in_header=0
        rendered+="$line"$'\n'
        continue
    fi

    case "$line" in
        '# {{IF:'*'}}')
            if [ "$in_if" = "1" ]; then
                echo "render-dependabot: nested {{IF}} at '$line' — not supported" >&2
                fail=1
            fi
            in_if=1
            eco="${line#\# \{\{IF:}"
            eco="$(flag_to_ecosystem "${eco%\}\}}")"
            if ! jq -e --arg e "$eco" '.ecosystems | has($e)' >/dev/null <<<"$detect_json"; then
                echo "render-dependabot: template names ecosystem '$eco', absent from the detect report" >&2
                fail=1
                keep=0
                dirs=""
            elif [ "$(jq -r --arg e "$eco" '.ecosystems[$e].detected' <<<"$detect_json")" = "true" ]; then
                dirs="$(jq -r --arg e "$eco" '.ecosystems[$e].directories[]?' <<<"$detect_json")"
                if [ -z "$dirs" ]; then
                    echo "render-dependabot: '$eco' is detected but carries no directories — block DROPPED rather than defaulting to \"/\" (a lane at a directory with no manifest finds nothing, silently)" >&2
                    keep=0
                else
                    keep=1
                fi
            else
                keep=0
                dirs=""
            fi
            ;;
        '# {{ENDIF}}')
            if [ "$collecting" = "1" ]; then
                echo "render-dependabot: {{ENDIF}} inside an unclosed {{FOREACH}}" >&2
                fail=1
                collecting=0
            fi
            in_if=0; keep=1; eco=""; dirs=""
            ;;
        '# {{FOREACH:DIRECTORY}}')
            collecting=1; buf=""
            ;;
        '# {{ENDFOREACH}}')
            collecting=0
            if [ "$keep" = "1" ]; then
                while IFS= read -r d; do
                    [ -n "$d" ] || continue
                    rendered+="${buf//\{\{DIRECTORY\}\}/$d}"
                done <<<"$dirs"
            fi
            buf=""
            ;;
        *)
            if [ "$collecting" = "1" ]; then
                buf+="$line"$'\n'
            elif [ "$keep" = "1" ]; then
                rendered+="$line"$'\n'
            fi
            ;;
    esac
done < "$TEMPLATE"

if [ "$in_if" = "1" ] || [ "$collecting" = "1" ]; then
    echo "render-dependabot: template ended inside an unclosed {{IF}}/{{FOREACH}} block" >&2
    fail=1
fi

# A token left behind is a fact nobody substituted — never ship it.
if grep -nE '\{\{[A-Za-z_]+(:[A-Za-z_]+)?\}\}' <<<"$rendered" >&2; then
    echo "render-dependabot: unsubstituted template token(s) above" >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1

if [ -n "$OUT" ]; then
    printf '%s' "$rendered" > "$OUT"
else
    printf '%s' "$rendered"
fi
