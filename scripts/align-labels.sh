#!/usr/bin/env bash
# align-labels.sh — the canonical home of the ENGINEERING-DIMENSION + SEVERITY
# label taxonomy. The 14 labels, their colours and their descriptions are
# defined in the CANONICAL_LABELS table below, nowhere else. Point it at a repo
# and it creates what is missing and corrects what has drifted.
#
# TWO LABEL TAXONOMIES LIVE IN THIS PLUGIN. THEY ARE DISJOINT BY DESIGN — do
# NOT "unify" them:
#
#   1. This script — engineering dimensions + severity. Ambient classification:
#      what an issue is ABOUT and how bad it is. Long-lived, repo-wide, applied
#      by humans and by assess-it.
#   2. skills/github-issues/scripts/issue-claim.sh (plus the --ensure-label of
#      file-or-link-issue.sh) — the dev-workflow STATE labels `ready`,
#      `in-progress`, `blocked`, `sentry-escalation`. Those are ensure-created
#      at the moment of the state transition that needs them, with canonical
#      colour and description, and MUST NOT appear in the table below: two
#      definitions of one label is exactly the drift both scripts exist to
#      prevent. RESERVED_LABELS asserts it at startup rather than trusting the
#      next editor to remember.
#
# Dependabot's per-ecosystem labels (`javascript`, `github_actions`, `rust`,
# `dart`, …) are auto-created and correctly differ per repo. Not our business.
#
# SCOPE: this script only ensures the canonical labels EXIST with canonical
# definitions. It never deletes a label, never relabels an issue, and never
# maps a repo's one-off labels onto the canonical set — deleting a label strips
# it from every issue carrying it, unrecoverably, so that migration is a
# separate, human-reviewed job.
#
# Usage:
#   align-labels.sh [--repo owner/name] [--dry-run | --check]
#
#   --repo     target repo; defaults to the current repo via `gh repo view`.
#   --dry-run  preview: report what would change, write nothing. Exit 0.
#   --check    drift report: same read-only pass, but exit 3 when the repo is
#              out of alignment — the gateable form for an audit sweep.
#
# Env: DRY_RUN=1 equivalent to --dry-run. REPO honored if --repo absent.
#
# Output: one JSON line per canonical label on stdout:
#   {"label":"security","action":"ok|create|update|would-create|would-update|failed","detail":"..."}
# Human-readable summary goes to stderr.
#
# Exit codes:
#   0  — aligned (or applied successfully, or --dry-run preview)
#   1  — missing tooling (gh/jq), no repo, or the label read failed
#   2  — at least one write failed (the pass CONTINUES past failures)
#   3  — --check only: drift found (nothing was written)
#   64 — usage error
#
# Idempotent by construction: a second run against an aligned repo finds every
# label already matching and issues no gh write at all.
#
# COLOURS ARE LORE — three sit deliberately off their modal palette value so
# chips stay distinguishable, and re-"tidying" them reintroduces a collision:
#   security  ee0701  (was identical to sev:critical)
#   tech-debt c5def5  (was identical to sev:medium)
#   epic      3e4b9e  (was identical to sev:low AND to ready)
# `infra` joined the set in 2026-08 and its colour was picked by measurement,
# not by eye: 5f4811 is the maximum-separation point of a 1,440-colour sweep,
# min ΔE2000 = 28.9 against every label that can share a chip row with it (the
# other 13 canonical labels, the four dev-workflow labels above, and GitHub's
# default set) — versus 5.3 for the tightest pair already inside the canonical
# set. It must NOT reuse c5def5, the colour the pre-canonical `infra` carried
# in three repos, because that is tech-debt's.

set -uo pipefail

# --- the canonical taxonomy: name|color|description --------------------------
# 10 engineering dimensions + 4 severities. Data, not scattered literals: every
# consumer of the taxonomy reads this table.
CANONICAL_LABELS=(
    "architecture|1d76db|Architecture & structure"
    "assessment|5319e7|Filed by assess-it"
    "ci-cd|006b75|CI/CD & release"
    "dx|bfdadc|Developer experience"
    "epic|3e4b9e|Tracking epic"
    "infra|5f4811|Infrastructure & platform"
    "observability|fef2c0|Observability & ops"
    "security|ee0701|Security / supply chain"
    "tech-debt|c5def5|Technical debt"
    "testing|0052cc|Testing & quality"
    "sev:critical|b60205|Critical severity"
    "sev:high|d93f0b|High severity"
    "sev:medium|fbca04|Medium severity"
    "sev:low|0e8a16|Low severity"
)

# Owned by the OTHER taxonomy (issue-claim.sh / file-or-link-issue.sh). Adding
# any of these to the table above forks a single source of truth in two.
RESERVED_LABELS=(ready in-progress blocked sentry-escalation)

usage() {
    cat >&2 <<'EOF'
usage: align-labels.sh [--repo owner/name] [--dry-run | --check]
       --dry-run  preview only, never writes, always exit 0
       --check    read-only drift report, exit 3 if the repo is out of alignment
EOF
    exit 64
}

REPO="${REPO:-}"
dry_run="${DRY_RUN:-0}"
check_only=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)    REPO="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        --check)   check_only=1; dry_run=1; shift ;;
        -h|--help) usage ;;
        *) echo "align-labels: unknown arg: $1" >&2; usage ;;
    esac
done

# Guardrail, enforced rather than documented: the dev-workflow labels are not
# ours to define.
for spec in "${CANONICAL_LABELS[@]}"; do
    for reserved in "${RESERVED_LABELS[@]}"; do
        if [[ "${spec%%|*}" == "$reserved" ]]; then
            echo "align-labels: '$reserved' belongs to the dev-workflow taxonomy owned by" >&2
            echo "  skills/github-issues/scripts/issue-claim.sh — remove it from CANONICAL_LABELS." >&2
            echo "  Two homes for one label is the drift this script exists to prevent." >&2
            exit 64
        fi
    done
done

command -v gh >/dev/null || { echo "align-labels: gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "align-labels: jq not on PATH" >&2; exit 1; }
[[ -z "$REPO" ]] && REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[[ -z "$REPO" ]] && { echo "align-labels: not in a GitHub repo and --repo not given" >&2; exit 1; }

# Mutations go through pr-shepherd's gh-retry.sh when available (pr-shepherd is
# the script root for the whole plugin); resolved relative to this script so the
# path holds wherever the plugin is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_RETRY="$SCRIPT_DIR/../skills/pr-shepherd/scripts/gh-retry.sh"
if [[ -f "$GH_RETRY" ]]; then
    ghw() { bash "$GH_RETRY" -- "$@"; }
else
    ghw() { gh "$@"; }
fi

# One read for the whole pass. The --limit truncation trap: a repo silently
# capped at the limit would make present labels look absent, so ask for more
# than any repo carries and shout if we ever hit the ceiling.
LIMIT=300
if ! existing=$(gh label list --repo "$REPO" --limit "$LIMIT" --json name,color,description 2>/dev/null); then
    echo "align-labels: could not read labels from $REPO (missing repo, or no access?)" >&2
    exit 1
fi
if ! label_count=$(jq 'length' <<<"$existing" 2>/dev/null); then
    echo "align-labels: unexpected label payload from $REPO" >&2
    exit 1
fi
if [[ "$label_count" -ge "$LIMIT" ]]; then
    echo "align-labels: $REPO returned $label_count labels — at the --limit ceiling; raise LIMIT" >&2
    exit 1
fi

emit() {  # $1=label $2=action $3=detail
    jq -cn --arg l "$1" --arg a "$2" --arg d "$3" '{label:$l, action:$a, detail:$d}'
}

n_ok=0
n_create=0
n_update=0
n_failed=0

for spec in "${CANONICAL_LABELS[@]}"; do
    IFS='|' read -r name color desc <<<"$spec"

    cur=$(jq -c --arg n "$name" \
        'map(select((.name | ascii_downcase) == ($n | ascii_downcase)))[0] // empty' \
        <<<"$existing")

    if [[ -z "$cur" ]]; then
        action="create"
        detail="absent"
    else
        cur_name=$(jq -r '.name' <<<"$cur")
        cur_color=$(jq -r '.color | ascii_downcase' <<<"$cur")
        cur_desc=$(jq -r '.description // ""' <<<"$cur")
        drift=""
        [[ "$cur_name" != "$name" ]] && drift="name $cur_name -> $name"
        if [[ "$cur_color" != "$color" ]]; then
            drift="${drift:+$drift; }color $cur_color -> $color"
        fi
        if [[ "$cur_desc" != "$desc" ]]; then
            drift="${drift:+$drift; }description \"$cur_desc\" -> \"$desc\""
        fi
        if [[ -z "$drift" ]]; then
            emit "$name" "ok" ""
            n_ok=$((n_ok + 1))
            continue
        fi
        action="update"
        detail="$drift"
    fi

    if [[ "$dry_run" == "1" ]]; then
        emit "$name" "would-$action" "$detail"
        if [[ "$action" == "create" ]]; then n_create=$((n_create + 1)); else n_update=$((n_update + 1)); fi
        continue
    fi

    rc=0
    if [[ "$action" == "create" ]]; then
        err=$(ghw label create "$name" --repo "$REPO" --color "$color" \
            --description "$desc" 2>&1 >/dev/null) || rc=$?
    else
        err=$(ghw label edit "$cur_name" --repo "$REPO" --name "$name" --color "$color" \
            --description "$desc" 2>&1 >/dev/null) || rc=$?
    fi

    if [[ "$rc" -ne 0 ]]; then
        emit "$name" "failed" "$(echo "$err" | grep -v '^\[gh-retry\]' | head -1)"
        n_failed=$((n_failed + 1))
        continue
    fi

    emit "$name" "$action" "$detail"
    if [[ "$action" == "create" ]]; then n_create=$((n_create + 1)); else n_update=$((n_update + 1)); fi
done

drifted=$((n_create + n_update))
if [[ "$dry_run" == "1" ]]; then
    if [[ "$check_only" == "1" ]]; then mode="check"; else mode="dry-run"; fi
    echo "align-labels: $REPO [$mode] — ${#CANONICAL_LABELS[@]} canonical labels: $n_ok aligned, $n_create to create, $n_update to update (no writes)" >&2
    if [[ "$check_only" == "1" && "$drifted" -gt 0 ]]; then
        exit 3
    fi
    exit 0
fi

echo "align-labels: $REPO — ${#CANONICAL_LABELS[@]} canonical labels: $n_ok aligned, $n_create created, $n_update updated, $n_failed failed" >&2
[[ "$n_failed" -gt 0 ]] && exit 2
exit 0
