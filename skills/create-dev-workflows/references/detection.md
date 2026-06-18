# Phase 1 — capability detection

Run the bundled probe from the target repo's root:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/create-dev-workflows/scripts/detect-capabilities.sh
```

It emits one JSON object; every probe degrades to `null`/`[]` plus an entry in `detect_failures` rather than aborting. Treat the output as *evidence to confirm*, not truth — the interview validates anything consequential.

## Output fields → template inputs

| JSON field | Feeds | Notes |
|---|---|---|
| `repo`, `default_branch` | `{{REPO_SLUG}}`, `{{DEFAULT_BRANCH}}`, `{{ORG}}` | |
| `repo_settings` | merge policy | `autoMergeAllowed`, `deleteBranchOnMerge`, `squashMergeAllowed` |
| `merge_queue` | `IF:MERGE_QUEUE` | **Best-effort** — GraphQL scopes often block it. `null` → MUST confirm in interview. A wrong merge policy is the most expensive mistake the generator can make (the `--auto` method-flag trap silently never-merges). |
| `pr_template.path/.sections` | `{{PR_TEMPLATE_PATH}}`, `{{PR_TEMPLATE_SECTION_CHECKLIST}}` | Sections become the §4 checklist, one `- [ ]` line each |
| `workflows`, `ci_workflow_guess` | `{{CI_WORKFLOW}}` | Confirm the guess if multiple workflows exist |
| `project_boards` | `IF:BOARD`, `{{BOARD_NUMBER}}` | Numbers/titles only. If a board is selected, discover its IDs at generation time per `github-issues/references/board-graphql.md` (`gh project field-list`) and pin them as `{{BOARD_PROJECT_ID}}`, `{{BOARD_STATUS_FIELD_ID}}`, option IDs. **An existing-but-empty board may mean the backlog is label-driven** — ask, don't assume (sets `{{BACKLOG_SOURCE_DESCRIPTION}}`/`{{BACKLOG_SOURCE_NOTE}}`). |
| `labels` | `{{PRIORITY_LABELS}}` | Detect a `P0..P3`-style taxonomy if present |
| `migrations.kind/.dirs` | `IF:MIGRATIONS`, `{{MIGRATION_DIRS}}`, `{{SCHEMA_DIR}}` | The regen command (`{{MIGRATION_REGEN_COMMAND}}`) is interview-confirmed — detection can't know `./dev db-generate` vs `bunx drizzle-kit generate` |
| `codegen` | `IF:CODEGEN`, `{{CODEGEN_COMMAND}}`, `{{CODEGEN_OUTPUT_DIRS}}` | Hint only; confirm the actual command |
| `monorepo` | `{{STACK_SUMMARY}}`, `{{PREFLIGHT_COMMANDS}}`, clean-it `{{DEP_VERSION_GLOBS}}`/`{{NOISE_ALLOWLIST}}` | Preflight derives from runner + scripts: e.g. bun → `bun run lint && bun run type-check && bun run --filter <pkg> test`; confirm in interview. **clean-it facts derive from `runner` + `migrations.dirs`** (no extra probe) — see the derivation table below |
| `repo_settings.deleteBranchOnMerge` | clean-it `{{DELETE_BRANCH_ON_MERGE}}` | Drives whether clean-it's stale-remote-branch step is a no-op |
| `sentry`, `posthog`, `testflight_bundle_id` | `IF:SENTRY`/`IF:POSTHOG`/`IF:TESTFLIGHT`, `{{BUNDLE_ID}}` | `sentry: true` means the SDK is initialized — org/project slugs (`{{SENTRY_ORG}}`, `{{SENTRY_PROJECTS}}`) come from the interview or a Sentry MCP project listing |

## clean-it fact derivation (from existing fields — no extra probe)

clean-it is **core** (always rendered). Derive its facts from the JSON the script already emits:

| Template input | Derive from | Example |
|---|---|---|
| `{{DEP_VERSION_GLOBS}}` (files that block stash auto-drop) | `monorepo.runner` + `migrations.dirs` | bun/npm/pnpm → `package.json bun.lock bun.lockb`; flutter → `pubspec.yaml pubspec.lock *.podspec`; dotnet → `*.csproj`; **always append each `migrations.dirs` entry** |
| `{{NOISE_ALLOWLIST}}` (extra auto-discard, beyond the universal `.DS_Store`/`*.swp`/`tmp/` defaults baked into `repo-cleanup`) | `monorepo.runner` | bun/npm/pnpm → `**/node_modules/`; flutter → `**/.dart_tool/ **/build/`; dotnet → `**/bin/ **/obj/` |
| `{{DELETE_BRANCH_ON_MERGE}}` | `repo_settings.deleteBranchOnMerge` | `true`/`false` verbatim |
| `IF:CLAIM_LABEL` + `{{CLAIM_LABEL}}` | take-it selected **and** `labels` contains a `status:in-progress`-style claim label | only render when take-it is on AND such a label exists |

## Hand checks the script can't do

After the script, verify in the session (cheap, parallel):

- **clean-it never-discard list** (`{{NEVER_DISCARD}}`): gitignored-but-precious files the noise sweep must leave alone — scan `.gitignore` / repo docs for `.env.local`, local secret files, etc. Default `.env.local` if a web app; confirm in the interview (it's unconfirmable from the stack alone).
- **clean-it claim label** (`{{CLAIM_LABEL}}`): if take-it is selected, grep the existing/rendered take-it for the label it sets to claim an issue (commonly `status:in-progress`); only then render `IF:CLAIM_LABEL`.

- **Sentry slugs**: if `sentry: true` and an MCP server is connected, list projects for the org to propose `{{SENTRY_PROJECTS}}`.
- **Critical paths** for repo-health scoring (`{{SCAN_PATHS}}`, `{{EXCLUDE_PATHSPECS}}`): propose source dirs from the layout, excluding detected migration/generated dirs.
- **Review orchestrator**: `ls .claude/agents/*review*` in the target repo → offers `IF:REVIEW_ORCHESTRATOR` + `{{REVIEW_ORCHESTRATOR_AGENT}}`.
- **Mobile release workflow**: if a workflow name matches `mobile|release.*ios|eas`, propose `{{RELEASE_WORKFLOW}}` + `{{MOBILE_PATH_PREFIX}}` (sets `IF:MOBILE`).
