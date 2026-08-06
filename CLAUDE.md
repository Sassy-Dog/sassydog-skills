# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin marketplace** containing a single plugin (`ai-agent-skills`) that bundles reusable skills and review agents for Claude Code, Gemini CLI, and other AI coding tools. Repo visibility is `INTERNAL` (the Sassy Dog org default).

There is **no build step** — the entire repo is Markdown (skills/agents) plus the Bash scripts bundled inside skills' `scripts/` directories. CI (`.github/workflows/ci.yml`, required on `main`) runs `bash scripts/preflight.sh` — the single source of truth for every gate: shellcheck (`-S warning`), `scripts/check-frontmatter.sh` (frontmatter `---` on line 1, `name`/`description` present, name matches directory/filename), the positional-token and legacy-name guards, manifest JSON validation + the CalVer version-of-record guard, the versioning tests (`scripts/test-versioning.sh`), and markdownlint (`.markdownlint-cli2.jsonc`) — plus a separate dockerized actionlint step. **Run `bash scripts/preflight.sh` locally before every PR** (`--fix` auto-fixes markdownlint findings). Those gates are necessary but not sufficient: "correctness" still means accurate trigger phrases and skill instructions that actually work when invoked — verify changes by installing the plugin locally (below) and exercising the skill.

## Layout (flat — everything at root)

This repo *is* the plugin; there is no nesting under a plugin subdirectory.

```
.claude-plugin/
  plugin.json        # plugin manifest — version is the version-of-record, stamped by scripts/stamp-version.sh (never hand-edit)
  marketplace.json   # marketplace entry pointing at the GitHub repo
agents/
  *-reviewer.md      # subagents, auto-discovered, namespaced ai-agent-skills:<name>
skills/
  <skill>/
    SKILL.md         # required: frontmatter (name + description) + instructions
    references/      # optional: deep reference docs (progressive disclosure)
    scripts/         # optional: executable tools the skill calls
```

## How the pieces fit together

Two non-obvious architectures live in this repo.

### Generator + capability skills (the dev-workflow family)

- **The six workflow skills are generic and ship in the plugin.** `plate-it` (prioritized work plate), `groom-it` (backlog grooming), `take-it` (parallel issue-shipping, "take #341, #432"), `drain-it` (loop dispatcher), `send-it` (single-PR end-to-end), and `clean-it` (post-shipping git reconciliation) each have exactly ONE implementation, under `skills/`. Per-repo behavior lives in that repo's `.claude/sassy-dog/<skill>.md` config, read at load time via dynamic context injection. The format is `refresh-skills/references/config-contract.md`. **There is no per-repo copy of these skills** — that is what makes every invocation render namespaced (`ai-agent-skills:plate-it`) and what removes the trigger-phrase competition an earlier generated-skills design had to design around.
- **`NO_CONFIG` is a first-class state.** A skill invoked in a repo with no config must derive what it safely can and run in its most conservative mode. Two exceptions block instead, because both act unattended and outward-facing: `take-it` (dispatches sub-agents) and `drain-it` (dispatches and merges on a loop).
- **Configure only what cannot be derived.** Repo slug, default branch, and `delete_branch_on_merge` come from `gh repo view` at runtime; they never appear in config. A configured value is a value that can drift.
- **Workflow skills are thin and delegate.** Shared mechanics live in the capability skills — `github-issues` (board/issue reads, dedupe-then-file writes), `sentry-triage` (gate-and-escalate), `pr-shepherd` (polling, merge queue vs direct, coupled-PR serialization, worktree teardown), `repo-cleanup` (the `clean-it` engine: `[gone]`/squash branch sweep, stash triage, untracked sweep — reuses `pr-shepherd`'s `teardown.sh --sweep`), `repo-health` (TODO/CI/lag scans), `testflight`. They invoke them by namespaced name (`ai-agent-skills:<skill>`); fix mechanics in the capability skill, never in a workflow skill. **`repo-cleanup` keeps its name** — it is now a capability-boundary distinction (mechanics vs. the user-facing flow) rather than the trigger-collision avoidance it was originally named for.
- **Consumer repos must declare the plugin in their own `.claude/settings.json`.** `enabledPlugins` honors project settings, and plugin skills enabled only in *user* settings do **not** transfer to cloud sessions or scheduled routines — only repo-declared plugins install at session start. Omit it and a scheduled `drain-it` silently finds no skill while every local session works fine. This repo declares itself; see `.claude/settings.json`.
- **`refresh-skills` is a config generator, not a runtime skill.** Run inside a product repo it writes `.claude/sassy-dog/*.md` plus the `.claude/settings.json` plugin declaration. It renders no skill bodies. Its modes: **migrate** (a repo still on generated skills — extract config from them, verify, then delete), **update** (config already present), **adopt** (legacy hand-written skills), **create** (nothing yet). Siblings `refresh-hooks` and `refresh-deps` follow the same generator pattern for hooks and Dependabot config.
- **One delegation mode.** Independent/vendored mode was removed — it was the only path that could produce an unbranded, un-namespaced skill, and no repo used it. Everything delegates `Skill: ai-agent-skills:<cap>`; `pr-shepherd` remains the script root (`repo-cleanup` ships no scripts and calls its `teardown.sh`; `github-issues` calls its `gh-retry.sh`).
- **`refresh-hooks` is the same generator pattern one layer down**: it detects a consumer repo's stack (keyed on repo config presence, never installed binaries) and renders a single PostToolUse formatter/linter dispatcher into `.claude/hooks/sassydog-post-edit.sh` + a `.claude/settings.json` entry. Ownership marker = command path referencing `.claude/hooks/sassydog-`; re-runs reconcile only owned entries and never touch hand-written hooks. The template (`references/templates/sassydog-post-edit.template.sh`) is valid shellcheck-clean bash with ALL tool blocks present — rendering only deletes `# {{IF:TOOL}}` blocks, so every render is valid by construction. Like the skills refresher, it always runs from the plugin.
- **Config format: frontmatter is regenerated, `##` prose is carried across verbatim.** That split is the whole point — prose is what a refresh must never rewrite. Contract: `refresh-skills/references/config-contract.md`; migration: `references/migrate-mode.md`. **Marker recognition must accept every producer name** (`refresh-skills`, `refresh-sassydog-skills`, legacy `create-dev-workflows`) — an unrecognised marker drops the repo into create mode and silently loses its config.
- **Write paths are concentrated.** `github-issues/scripts/file-or-link-issue.sh` is the single issue-creation path (marker-keyed idempotency, `--dry-run`, preview-then-confirm, burst rail). `sentry-triage` never mutates Sentry. Keep it that way.

### Orchestrator + reviewer agents (`assess-it`)

The relationship between the `assess-it` skill and the nine `*-reviewer` agents requires reading `skills/assess-it/SKILL.md` + `orchestration.md` together:

- **`assess-it` is an orchestrator.** It runs a 5-phase audit: detect stack → fan out reviewer agents concurrently (one message, multiple Agent calls) → adversarially verify each finding → cluster into PR-sized work → preview and file GitHub Issues under a tracking Epic.
- **The `*-reviewer` agents are the fan-out workers.** Each owns a domain (architecture, code-quality, security, testing, cicd-release, infra-platform, observability-ops, dx-docs, dependency-supply-chain) and runs in **audit mode**: it FINDS problems and cites `file:line` evidence, it does NOT write code. The agent→domain dispatch map lives in `orchestration.md`.
- **All agents return the same finding schema** (title, area, severity, likelihood, evidence, why_it_matters, proposed_fix, acceptance, pr_size, labels, confidence). When editing one reviewer's output contract, keep it consistent with the schema in `orchestration.md` and the other agents.
- `github-secrets` and `testflight` are standalone capability skills — no agent orchestration.

## Conventions that matter

- **Skill `description` is a trigger spec, not a summary.** It is dense with quoted user phrases ("set a GitHub secret", "check TestFlight feedback") because matching those phrases is what activates the skill. When adding/editing a skill, write the description as the list of utterances that should trigger it.
- **Progressive disclosure.** SKILL.md stays thin and actionable; depth goes in `references/*.md` that the skill says to read "when you reach that phase." Don't inline reference-doc detail into SKILL.md.
- **Reviewer agents carry a "Sassy Dog calibration" section** applied only when the relevant stack is present (e.g. Doppler is the secrets source of truth, all-secrets/zero-`vars.*`, managed identity + Key Vault `kv-sassydog`, pin Actions to SHAs). New org-wide policies belong in the matching reviewer's calibration block.
- **No bare `$1`–`$9`/`$@`/`$*` in SKILL.md bodies or dev-workflow templates.** Skill bodies are arg-substitution surfaces: when a skill is invoked with args (as every thin generated skill invokes its capability skill), positional tokens in the rendered body get replaced with args tokens, corrupting embedded commands. CI greps for them (`skills/*/SKILL.md`, `.claude/skills/*/SKILL.md`, `refresh-skills/references/templates/*`). The guard now asserts that template pathspec is non-empty first — an empty pathspec used to make it pass while covering nothing. Use `cut -f1`/`%(format)` idioms instead, or move the snippet to a `references/` doc or bundled script — neither is substituted.
- **Outward-facing actions require preview-then-confirm.** `assess-it` never files GitHub Issues silently — it prints the full Epic + child-issue preview and files only on approval. Preserve this guard in any change.
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`). Recent history uses PRs to `main`.

## Local development

```bash
# Run Claude Code with this plugin loaded from the working tree
claude --plugin-dir ~/Repos/sassy-dog/ai-agent-skills

# Install from the published marketplace
claude plugin marketplace add Sassy-Dog/ai-agent-skills
claude plugin install ai-agent-skills
```

After editing a skill or agent, reload via `--plugin-dir` and invoke the skill to confirm frontmatter parses and triggers fire.

## Releasing

The plugin version is **monthly-rolling CalVer** (`YYYY.M.<commits-this-month>`, e.g. `2026.7.16`) per the org Versioning spec; the committed `version` in `.claude-plugin/plugin.json` is the version-of-record. **Never hand-edit it** — stamp it:

```bash
bash scripts/stamp-version.sh   # resolves CalVer and writes .claude-plugin/plugin.json
```

Commit the stamped manifest in the release PR. Build number: N/A for this repo; tags optional. Full instance doc — including the **one-way ratchet** (no `0.x`/`1.x` may ever follow CalVer): [`docs/VERSIONING.md`](docs/VERSIONING.md). Keep `README.md`'s plugin/skill table and the agent list in sync when skills or reviewer agents are added or removed.
