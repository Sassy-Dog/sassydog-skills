# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin marketplace** containing a single plugin (`ai-agent-skills`) that bundles reusable skills and review agents for Claude Code, Gemini CLI, and other AI coding tools. Repo visibility is `INTERNAL` (the Sassy Dog org default).

There is **no build, test, or lint step** — the entire repo is Markdown (skills/agents) plus the Bash scripts bundled inside skills' `scripts/` directories. "Correctness" means: valid frontmatter, accurate trigger phrases, and skill instructions that actually work when invoked. Verify changes by installing the plugin locally (below) and exercising the skill, not by running a compiler.

## Layout (flat — everything at root)

This repo *is* the plugin; there is no nesting under a plugin subdirectory.

```
.claude-plugin/
  plugin.json        # plugin manifest (name, version, author) — bump version here on release
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

- **`create-dev-workflows` is a generator, not a runtime skill.** Run inside a product repo, it creates/updates that repo's project-level `plate-it` (prioritized work plate), `take-it` (parallel issue-shipping, "take #341, #432"), and `send-it` (single-PR end-to-end) skills from templates in `references/templates/`. **The plugin deliberately ships no generic runtime versions of the trio** — only project skills exist at runtime, so trigger phrases like "plate it" always resolve to the repo's own skill (this is the precedence guarantee; don't add a generic plate/take/send skill to the plugin).
- **Generated skills are thin and delegate.** Shared mechanics live in the capability skills — `github-issues` (board/issue reads, dedupe-then-file writes), `sentry-triage` (gate-and-escalate), `pr-shepherd` (polling, merge queue vs direct, coupled-PR serialization, worktree teardown), `repo-health` (TODO/CI/lag scans), `testflight`. Generated skills invoke them by namespaced name (`ai-agent-skills:<skill>`); fix mechanics in the capability skill, never in a generated file.
- **Generated files carry a `generated-by` header and `PROJECT-SPECIFIC` fences.** Update mode re-renders from current templates and splices the fences; adopt mode migrates legacy hand-written trios. The contract lives in `create-dev-workflows/references/update-mode.md` — keep it in sync with the template headers.
- **Write paths are concentrated.** `github-issues/scripts/file-or-link-issue.sh` is the single issue-creation path (marker-keyed idempotency, `--dry-run`, preview-then-confirm, burst rail). `sentry-triage` never mutates Sentry. Keep it that way.

### Orchestrator + reviewer agents (`codebase-assessment`)

The relationship between the `codebase-assessment` skill and the nine `*-reviewer` agents requires reading `skills/codebase-assessment/SKILL.md` + `orchestration.md` together:

- **`codebase-assessment` is an orchestrator.** It runs a 5-phase audit: detect stack → fan out reviewer agents concurrently (one message, multiple Agent calls) → adversarially verify each finding → cluster into PR-sized work → preview and file GitHub Issues under a tracking Epic.
- **The `*-reviewer` agents are the fan-out workers.** Each owns a domain (architecture, code-quality, security, testing, cicd-release, infra-platform, observability-ops, dx-docs, dependency-supply-chain) and runs in **audit mode**: it FINDS problems and cites `file:line` evidence, it does NOT write code. The agent→domain dispatch map lives in `orchestration.md`.
- **All agents return the same finding schema** (title, area, severity, likelihood, evidence, why_it_matters, proposed_fix, acceptance, pr_size, labels, confidence). When editing one reviewer's output contract, keep it consistent with the schema in `orchestration.md` and the other agents.
- `github-secrets` and `testflight` are standalone capability skills — no agent orchestration.

## Conventions that matter

- **Skill `description` is a trigger spec, not a summary.** It is dense with quoted user phrases ("set a GitHub secret", "check TestFlight feedback") because matching those phrases is what activates the skill. When adding/editing a skill, write the description as the list of utterances that should trigger it.
- **Progressive disclosure.** SKILL.md stays thin and actionable; depth goes in `references/*.md` that the skill says to read "when you reach that phase." Don't inline reference-doc detail into SKILL.md.
- **Reviewer agents carry a "Sassy Dog calibration" section** applied only when the relevant stack is present (e.g. Doppler is the secrets source of truth, all-secrets/zero-`vars.*`, managed identity + Key Vault `kv-sassydog`, pin Actions to SHAs). New org-wide policies belong in the matching reviewer's calibration block.
- **Outward-facing actions require preview-then-confirm.** `codebase-assessment` never files GitHub Issues silently — it prints the full Epic + child-issue preview and files only on approval. Preserve this guard in any change.
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

Bump `version` in `.claude-plugin/plugin.json`. Keep `README.md`'s plugin/skill table and the agent list in sync when skills or reviewer agents are added or removed.
