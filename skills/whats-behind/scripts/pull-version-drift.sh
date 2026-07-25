#!/usr/bin/env bash
# pull-version-drift.sh — read-only probe: where does each repo sit relative to
# the rest of the portfolio on shared, pinned versions? Emits one JSON object.
#
# Env:
#   PORTFOLIO_ROOT  directory holding the product checkouts (default: cwd)
#   MAX_DEPTH       how deep to look for repos (default: 2 — covers multi-repo
#                   product groups like velovate/velovate-app)
#
# Output shape:
#   { "root": "...", "repos": [ "..." ],
#     "actions":   { "<action>": { "<repo>": ["v1","v2"], ... } },
#     "toolchains":{ "<pin>":    { "<repo>": ["1.2.3"],  ... } },
#     "runners":   { "<repo>":   { "hosted": N, "self_hosted": N } },
#     "dependabot":{ "<repo>":   { "config": true|false, "github_actions": true|false } },
#     "skipped":   [ "<dir>: <reason>" ] }
#
# THE COMPARISON IS PEER-RELATIVE, NOT ABSOLUTE. This deliberately does not ask
# a registry "what is the newest version of X". A portfolio has its own moving
# standard: if eleven repos run actions/checkout v7 and one runs v4, that one is
# behind regardless of what upstream has released this week. Peer-relative also
# degrades gracefully offline and never nags about a version nobody has adopted.
#
# It reports RAW OBSERVATIONS, not verdicts — which repo pins what. Ranking the
# laggards and correlating them with missing Dependabot config is the caller's
# job (see references/interpreting.md); keeping that out of the script means the
# rubric can change without touching parsing.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: one unreadable repo must not
# void the sweep. Unparseable directories land in `skipped` and the loop goes on.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

ROOT="${PORTFOLIO_ROOT:-$PWD}"
MAX_DEPTH="${MAX_DEPTH:-2}"
[[ -d "$ROOT" ]] || { echo "skipped: PORTFOLIO_ROOT not a directory: ${ROOT}" >&2; exit 10; }

# Discover git repos up to MAX_DEPTH, where depth counts the REPO, not its .git
# directory — hence the +1. Depth 2 is the default because products are a mix of
# one-repo and multi-repo groups; a depth-1 scan silently misses every nested
# repo (velovate/velovate-app, lupita/lupita), which is exactly the failure this
# default exists to prevent.
mapfile -t REPO_DIRS < <(find "$ROOT" -mindepth 1 -maxdepth "$((MAX_DEPTH + 1))" -type d -name .git 2>/dev/null \
    | sed 's#/\.git$##' | sort)

[[ ${#REPO_DIRS[@]} -eq 0 ]] && { echo "skipped: no git repos under ${ROOT}" >&2; exit 10; }

skipped=()
actions_rows=""
tool_rows=""
runner_rows=""
dep_rows=""
repo_names=""

for dir in "${REPO_DIRS[@]}"; do
    name="${dir#"$ROOT"/}"
    repo_names+=$(jq -cn --arg n "$name" '$n')$'\n'
    wf="$dir/.github/workflows"

    if [[ ! -d "$wf" ]]; then
        skipped+=("${name}: no .github/workflows")
    else
        # Pinned-SHA uses carry the human version in a trailing comment
        # (`uses: actions/checkout@<sha> # v7.0.0`); floating uses carry it
        # inline. Read both, else every SHA-pinned repo looks version-less —
        # and SHA-pinning is the house standard, so that would blank the report.
        while IFS=$'\t' read -r action version; do
            [[ -z "$action" || -z "$version" ]] && continue
            actions_rows+=$(jq -cn --arg a "$action" --arg r "$name" --arg v "$version" \
                '{action:$a, repo:$r, version:$v}')$'\n'
        # NOTE the sed delimiters: the pattern itself contains `#` (the version
        # comment), so `s#...#...#` breaks with "bad flag in substitute command".
        done < <(grep -rhoE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@([a-f0-9]{40} *# *v?[0-9][0-9.]*|v[0-9][0-9.]*)' "$wf" 2>/dev/null \
            | sed -E 's/^uses: *//' \
            | sed -E 's/@[a-f0-9]{40} *# *v?/\t/; s/@v/\t/' \
            | awk -F'\t' 'NF==2 && $2 ~ /^[0-9]/ {print $1"\t"$2}' | sort -u)

        # Toolchain pins that repos share and drift on independently.
        while IFS=$'\t' read -r pin version; do
            [[ -z "$pin" || -z "$version" ]] && continue
            tool_rows+=$(jq -cn --arg p "$pin" --arg r "$name" --arg v "$version" \
                '{pin:$p, repo:$r, version:$v}')$'\n'
        done < <(grep -rhoE '(bun-version|node-version|dotnet-version|flutter-version|xcode-version|go-version|toolchain): *"?[0-9][0-9.]*' "$wf" 2>/dev/null \
            | sed -E 's/: *"?/\t/' | sort -u)

        hosted=$(grep -rhcE 'runs-on: *(ubuntu|macos|windows)-' "$wf" 2>/dev/null | paste -sd+ - | bc 2>/dev/null)
        selfh=$(grep -rhcE 'runs-on:.*self-hosted' "$wf" 2>/dev/null | paste -sd+ - | bc 2>/dev/null)
        runner_rows+=$(jq -cn --arg r "$name" --argjson h "${hosted:-0}" --argjson s "${selfh:-0}" \
            '{repo:$r, hosted:$h, self_hosted:$s}')$'\n'
    fi

    # Dependabot coverage — the usual ROOT CAUSE of action drift, so it is
    # collected alongside rather than left to a separate pass.
    cfg="$dir/.github/dependabot.yml"
    [[ -f "$cfg" ]] || cfg="$dir/.github/dependabot.yaml"
    if [[ -f "$cfg" ]]; then
        ga=$(grep -cE 'package-ecosystem: *"?github-actions' "$cfg" 2>/dev/null)
        dep_rows+=$(jq -cn --arg r "$name" --argjson g "$([[ "${ga:-0}" -gt 0 ]] && echo true || echo false)" \
            '{repo:$r, config:true, github_actions:$g}')$'\n'
    else
        dep_rows+=$(jq -cn --arg r "$name" '{repo:$r, config:false, github_actions:false}')$'\n'
    fi
done

fails_json="$(printf '%s\n' "${skipped[@]+"${skipped[@]}"}" | jq -Rs 'split("\n")|map(select(length>0))')"

jq -n \
  --arg root "$ROOT" \
  --argjson repos "$(printf '%s' "$repo_names" | jq -sc .)" \
  --argjson actions "$(printf '%s' "$actions_rows" | jq -sc .)" \
  --argjson tools "$(printf '%s' "$tool_rows" | jq -sc .)" \
  --argjson runners "$(printf '%s' "$runner_rows" | jq -sc .)" \
  --argjson dependabot "$(printf '%s' "$dep_rows" | jq -sc .)" \
  --argjson skipped "$fails_json" '
  {
    root: $root,
    repos: $repos,
    actions: ( $actions | group_by(.action)
               | map({ key: .[0].action,
                       value: ( group_by(.repo)
                                | map({ key: .[0].repo, value: [ .[].version ] | unique | sort })
                                | from_entries ) })
               | from_entries ),
    toolchains: ( $tools | group_by(.pin)
                  | map({ key: .[0].pin,
                          value: ( group_by(.repo)
                                   | map({ key: .[0].repo, value: [ .[].version ] | unique | sort })
                                   | from_entries ) })
                  | from_entries ),
    runners: ( $runners | map({ key: .repo, value: { hosted, self_hosted } }) | from_entries ),
    dependabot: ( $dependabot | map({ key: .repo, value: { config, github_actions } }) | from_entries ),
    skipped: $skipped
  }'
