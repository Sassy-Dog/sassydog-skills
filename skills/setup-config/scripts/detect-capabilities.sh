#!/usr/bin/env bash
# detect-capabilities.sh — read-only repo capability probe for setup-config.
# Emits ONE JSON object on stdout. Every probe degrades to null/[] and appends to
# detect_failures rather than aborting — the interview phase fills the gaps.
#
# Run from the target repo's root.
set -uo pipefail

fail_list=()
note() { fail_list+=("$1"); }

command -v gh >/dev/null || { echo '{"error":"gh CLI not on PATH"}'; exit 1; }
command -v jq >/dev/null || { echo '{"error":"jq not on PATH"}'; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo '{"error":"not a git repo"}'; exit 1; }

# --- repo + default branch ---------------------------------------------------
# NOTE: autoMergeAllowed is NOT a gh-repo-view field (REST-only) — fetched below.
repo_json=$(gh repo view --json nameWithOwner,defaultBranchRef,deleteBranchOnMerge,squashMergeAllowed 2>/dev/null) \
  || { repo_json='{}'; note "gh repo view failed (auth? remote?)"; }
REPO=$(jq -r '.nameWithOwner // empty' <<<"$repo_json")
DEFAULT_BRANCH=$(jq -r '.defaultBranchRef.name // "main"' <<<"$repo_json")
OWNER="${REPO%%/*}"
auto_merge="null"
if [[ -n "$REPO" ]]; then
  auto_merge=$(gh api "repos/$REPO" --jq '.allow_auto_merge // false' 2>/dev/null) || { auto_merge="null"; note "REST repo settings probe failed"; }
fi

# --- merge queue (best-effort; GraphQL scopes vary) ---------------------------
merge_queue="null"
if [[ -n "$REPO" ]]; then
  mq=$(gh api graphql -f query='query($o:String!,$n:String!,$b:String!){
    repository(owner:$o,name:$n){ mergeQueue(branch:$b){ id } }}' \
    -f o="$OWNER" -f n="${REPO#*/}" -f b="$DEFAULT_BRANCH" \
    --jq '.data.repository.mergeQueue != null' 2>/dev/null) || mq=""
  if [[ "$mq" == "true" || "$mq" == "false" ]]; then merge_queue="$mq"; else note "merge-queue probe inconclusive — confirm in interview"; fi
fi

# --- PR template ---------------------------------------------------------------
pr_template_path=""
for p in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md docs/pull_request_template.md; do
  [[ -f "$p" ]] && { pr_template_path="$p"; break; }
done
pr_sections="[]"
[[ -n "$pr_template_path" ]] && pr_sections=$(grep -E '^#{2,3} ' "$pr_template_path" | sed 's/^#\{2,3\} //' | jq -R . | jq -s .)

# --- workflows ------------------------------------------------------------------
workflows="[]"; ci_guess=""
if [[ -d .github/workflows ]]; then
  workflows=$(find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) -exec basename {} \; 2>/dev/null | jq -R . | jq -s .)
  for c in ci.yml ci.yaml main.yml build.yml; do
    [[ -f ".github/workflows/$c" ]] && { ci_guess="$c"; break; }
  done
  [[ -z "$ci_guess" ]] && ci_guess=$(jq -r '.[0] // empty' <<<"$workflows")
fi

# --- project boards (numbers only; field/option IDs discovered at generation) ----
boards="[]"
if [[ -n "$OWNER" ]]; then
  boards=$(gh project list --owner "$OWNER" --format json 2>/dev/null \
    | jq '[.projects[] | {number, title}]' 2>/dev/null) || { boards="[]"; note "project list failed (project scope?)"; }
fi

# --- labels ----------------------------------------------------------------------
labels="[]"
[[ -n "$REPO" ]] && labels=$(gh label list --repo "$REPO" --limit 100 --json name --jq '[.[].name]' 2>/dev/null) \
  || note "label list failed"

# --- migrations --------------------------------------------------------------------
mig_kind=""; mig_dirs="[]"
if ls drizzle.config.* packages/*/drizzle.config.* apps/*/drizzle.config.* >/dev/null 2>&1; then mig_kind="drizzle"; fi
[[ -z "$mig_kind" ]] && git ls-files | grep -q 'prisma/schema.prisma' && mig_kind="prisma"
[[ -z "$mig_kind" ]] && git ls-files | grep -qi 'Migrations/.*\.cs$' && mig_kind="ef-core"
mig_dirs=$(git ls-files | grep -iE '(^|/)migrations/' | sed -E 's|/migrations/.*|/migrations/|i' | sort -u | head -5 | jq -R . | jq -s .)

# --- codegen -------------------------------------------------------------------------
codegen="false"; codegen_hint=""
if ls scripts/codegen*.sh graphql.config.* codegen.yml codegen.ts >/dev/null 2>&1; then
  codegen="true"; codegen_hint=$(ls scripts/codegen*.sh graphql.config.* codegen.yml codegen.ts 2>/dev/null | head -1)
elif git ls-files | grep -q 'pubspec.yaml' && grep -qs build_runner pubspec.yaml */pubspec.yaml 2>/dev/null; then
  codegen="true"; codegen_hint="build_runner"
fi

# --- monorepo / runner / dev entrypoint ----------------------------------------------
layout=$(ls -d apps packages 2>/dev/null | jq -R . | jq -s .)
runner=""
[[ -f bun.lock || -f bun.lockb ]] && runner="bun"
[[ -z "$runner" && -f pnpm-lock.yaml ]] && runner="pnpm"
[[ -z "$runner" && -f package-lock.json ]] && runner="npm"
[[ -z "$runner" && -f pubspec.yaml ]] && runner="flutter"
[[ -z "$runner" ]] && git ls-files | grep -q '\.csproj$' && runner="dotnet"
dev_script=""
for d in ./dev ./run.sh; do [[ -x "$d" ]] && { dev_script="$d"; break; }; done
[[ -z "$dev_script" && -f package.json ]] && jq -e '.scripts.dev' package.json >/dev/null 2>&1 && dev_script="$runner run dev"

# --- observability + product surfaces --------------------------------------------------
sentry="false"
git grep -lqiE '@sentry/|sentry_flutter|sentry\.init|Sentry\.Init' -- ':(exclude)*.lock*' >/dev/null 2>&1 && sentry="true"
posthog="false"
git grep -lqi 'posthog' -- ':(exclude)*.lock*' >/dev/null 2>&1 && posthog="true"
bundle_id=""
if git ls-files | grep -qE '(^|/)(ios/|app\.json)'; then
  bundle_id=$(git grep -hoE '"bundleIdentifier"\s*:\s*"[^"]+"|PRODUCT_BUNDLE_IDENTIFIER = [A-Za-z0-9.$()-]+' 2>/dev/null \
    | head -1 | grep -oE '[a-z]+\.[a-z0-9-]+\.[a-zA-Z0-9.-]+' | head -1) || true
fi

# --- secret manager / env bootstrap hint --------------------------------------------------
# A direnv/secret-manager config means the process env is loaded lazily — non-interactive
# agent shells never fire direnv, so survey-work's §1 presence probes need a bootstrap command
# first (IF:SECRET_BOOTSTRAP; the exact command is interview-confirmed).
secret_files=$(ls .envrc doppler.yaml doppler.yml 2>/dev/null | jq -R . | jq -s .)
secret_hint=""
if [[ -f doppler.yaml || -f doppler.yml ]]; then secret_hint="doppler"
elif [[ -f .envrc ]] && grep -qi doppler .envrc 2>/dev/null; then secret_hint="doppler"
elif [[ -f .envrc ]]; then secret_hint="direnv"
fi

# --- assemble ---------------------------------------------------------------------------
jq -n \
  --arg repo "$REPO" --arg branch "$DEFAULT_BRANCH" \
  --argjson repo_settings "$(jq --argjson am "$auto_merge" '{autoMergeAllowed: $am, deleteBranchOnMerge, squashMergeAllowed}' <<<"$repo_json")" \
  --argjson merge_queue "$merge_queue" \
  --arg prt "$pr_template_path" --argjson prs "$pr_sections" \
  --argjson workflows "$workflows" --arg ci "$ci_guess" \
  --argjson boards "$boards" --argjson labels "$labels" \
  --arg mig_kind "$mig_kind" --argjson mig_dirs "$mig_dirs" \
  --argjson codegen "$codegen" --arg codegen_hint "$codegen_hint" \
  --argjson layout "$layout" --arg runner "$runner" --arg dev "$dev_script" \
  --argjson sentry "$sentry" --argjson posthog "$posthog" --arg bundle "$bundle_id" \
  --argjson secret_files "$secret_files" --arg secret_hint "$secret_hint" \
  --argjson failures "$(printf '%s\n' "${fail_list[@]:-}" | grep -v '^$' | jq -R . | jq -s .)" \
  '{
    repo: ($repo | select(. != "") // null),
    default_branch: $branch,
    repo_settings: $repo_settings,
    merge_queue: $merge_queue,
    pr_template: { path: ($prt | select(. != "") // null), sections: $prs },
    workflows: $workflows,
    ci_workflow_guess: ($ci | select(. != "") // null),
    project_boards: $boards,
    labels: $labels,
    migrations: { kind: ($mig_kind | select(. != "") // null), dirs: $mig_dirs },
    codegen: { present: $codegen, hint: ($codegen_hint | select(. != "") // null) },
    monorepo: { layout: $layout, runner: ($runner | select(. != "") // null), dev_script: ($dev | select(. != "") // null) },
    sentry: $sentry,
    posthog: $posthog,
    testflight_bundle_id: ($bundle | select(. != "") // null),
    secret_manager: { hint: ($secret_hint | select(. != "") // null), files: $secret_files },
    detect_failures: $failures
  }'
