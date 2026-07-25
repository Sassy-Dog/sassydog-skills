# ai-agent-skills

Sassy Dog AI agent skills marketplace for Claude Code, Gemini CLI, and other AI coding tools.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| `ai-agent-skills` | `github-secrets` | GitHub Actions secrets & variables — scope hierarchy, CLI usage, common mistakes |
| `ai-agent-skills` | `testflight` | TestFlight / App Store Connect API — builds, testers, feedback |
| `ai-agent-skills` | `assess-it` | Multi-agent repository audit → deduped, PR-sized GitHub Issues under a tracking Epic |
| `ai-agent-skills` | `refresh-sassydog-skills` | Generator/refresher: creates, updates, and re-syncs a repo's project-specific `plate-it` / `fill-it` / `take-it` / `drain-it` / `send-it` / `clean-it` workflow skills (plugin-backed or independent/vendored) |
| `ai-agent-skills` | `refresh-sassydog-hooks` | Generator/refresher: renders a repo's stack-specific Claude Code hooks (`.claude/hooks/sassydog-*.sh` + settings.json wiring) from detection — format-on-edit, lint-findings-fed-back; re-runnable as the stack evolves |
| `ai-agent-skills` | `github-issues` | Issue/board reads, stale-issue detection, idempotent dedupe-then-file issue creation |
| `ai-agent-skills` | `sentry-triage` | Gate-and-escalate Sentry triage; qualifying hits escalate via `github-issues` |
| `ai-agent-skills` | `pr-shepherd` | PR lifecycle mechanics — check polling, merge queue vs direct merge, coupled-PR serialization, worktree teardown |
| `ai-agent-skills` | `repo-cleanup` | Post-shipping git reconciliation mechanics — `[gone]`/squash-merged branch sweep, stale-worktree teardown, stash triage, untracked-noise sweep (the engine behind a repo's `clean-it`) |
| `ai-agent-skills` | `repo-health` | Scripted signal scans — TODO/FIXME markers, skipped tests, CI duration/flake, mobile release lag |
| `ai-agent-skills` | `whats-on-fire` | Org-wide portfolio sweep — Sentry issues + crons, stalled PRs, red default branches, Dependabot exposure, and blind spots (products with no monitoring/alerting/scanning); ranks across products and routes each to the owning repo's `plate-it` |

### Generator + capability skills

`refresh-sassydog-skills` generates and refreshes **project-level** `plate-it` (prioritized work plate), `fill-it` (backlog grooming to Ready), `drain-it` (loop-driven Ready dispatcher — board column or `ready` label), `take-it`
(parallel issue-shipping: "take #341, #432"), `send-it` (single-PR end-to-end), and `clean-it`
(post-shipping git reconciliation) skills into a product repo's `.claude/skills/`. The plugin
deliberately ships no generic runtime versions of these — only project skills exist at runtime, so
trigger phrases always resolve to the repo's own skill. Generated skills stay thin by delegating
shared mechanics to the capability skills (`github-issues`, `sentry-triage`, `pr-shepherd`,
`repo-cleanup`, `repo-health`, `testflight`). `plate-it` / `send-it` / `clean-it` are core (always
generated); `take-it` / `fill-it` / `drain-it` are opt-in. (`clean-it`'s engine is `repo-cleanup`,
named distinctly so the "clean it" phrase resolves to the project skill, not the capability.)

`refresh-sassydog-hooks` is the same pattern one layer down: it detects the repo's stack (ruff,
prettier, markdownlint, shellcheck, dart, rustfmt, gofmt, dotnet format — keyed on repo config, not
installed binaries) and renders a single PostToolUse dispatcher into `.claude/hooks/`, wired into
`.claude/settings.json`. Formatters fix silently; unfixable lint findings exit 2 so they feed
straight back for an immediate fix. Re-runs reconcile only entries the generator owns (command path
references `sassydog-`), never hand-written hooks.

**Delegation modes.** By default generated skills are **plugin-backed**: they delegate to the
plugin's capability skills, so every machine running them needs the plugin installed. A repo can
instead be set up **independent**: refresh vendors the needed capability skills (transitive
closure — `pr-shepherd`, `github-issues`, `repo-cleanup`, `repo-health`, plus `sentry-triage` /
`testflight` when detected) into the repo's own `.claude/skills/`, each stamped with a
`vendored-by:` marker, so a fresh clone works with no plugin install. Later refreshes re-sync the
vendored copies from the current plugin (hand-edits to them are overwritten), and a repo can switch
modes at any time ("make this repo independent" / "switch back to plugin mode"). The presence of
`vendored-by:` markers *is* the persisted mode — there's no config file to drift.

### Review agents

`assess-it` ships dedicated audit-mode agents (namespaced `ai-agent-skills:<name>`):
`architecture-reviewer`, `code-quality-reviewer`, `security-reviewer`, `testing-reviewer`,
`cicd-release-reviewer`, `infra-platform-reviewer`, `observability-ops-reviewer`,
`dx-docs-reviewer`, `dependency-supply-chain-reviewer`.

## Installation

### Claude Code

```bash
# Add as a marketplace
claude plugin marketplace add Sassy-Dog/ai-agent-skills

# Install the plugin
claude plugin install ai-agent-skills
```

### Local Development

```bash
claude --plugin-dir ~/Repos/sassy-dog/ai-agent-skills
```

## Updating / Troubleshooting

Plugin updates are **manual** — the cache does not follow releases. After every release (a new CalVer stamped into `.claude-plugin/plugin.json` via `scripts/stamp-version.sh` — see `docs/VERSIONING.md`), each consumer machine must run:

```bash
claude plugin update ai-agent-skills@sassy-dog-skills
```

### The bare plugin name fails

`claude plugin update ai-agent-skills` returns "not found" — the error doesn't hint at the fix. The marketplace-qualified name is required: `ai-agent-skills@sassy-dog-skills`.

### `claude plugin marketplace update` is not a plugin update

`claude plugin marketplace update` only `git pull`s the marketplace clone. It succeeds even when the *plugin cache* — the code your skills actually run from — is still stale. Diagnose with:

```bash
ls ~/.claude/plugins/cache/sassy-dog-skills/ai-agent-skills/
# 2026.6.4    <- installed version (stale)
```

Compare against `version` in `.claude-plugin/plugin.json` on `main` (e.g. `2026.7.16`). If they differ, run the qualified update command above. This failure mode is silent: no error anywhere — skills just keep old bugs and trigger phrases stop matching.

### Updates freeze at the cached version (SAML error)

Plugin install/update does a fresh **SSH** clone of this INTERNAL repo. The SSH key must be SSO-authorized for the `Sassy-Dog` org — on <https://github.com/settings/keys>, use **Configure SSO** on the key. Without it, updates fail with a SAML error or freeze silently at the cached version.

## Repository layout

This repo is a single plugin: skills, agents, and the manifest live at the root.

```
ai-agent-skills/
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # Subagents (auto-discovered, namespaced ai-agent-skills:<name>)
│   └── *-reviewer.md
└── skills/
    └── my-skill/
        ├── SKILL.md             # Required — frontmatter + instructions
        ├── references/          # Optional — detailed reference docs
        └── scripts/             # Optional — executable tools
```
