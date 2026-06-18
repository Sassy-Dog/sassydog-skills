# ai-agent-skills

Sassy Dog AI agent skills marketplace for Claude Code, Gemini CLI, and other AI coding tools.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| `ai-agent-skills` | `github-secrets` | GitHub Actions secrets & variables — scope hierarchy, CLI usage, common mistakes |
| `ai-agent-skills` | `testflight` | TestFlight / App Store Connect API — builds, testers, feedback |
| `ai-agent-skills` | `assess-it` | Multi-agent repository audit → deduped, PR-sized GitHub Issues under a tracking Epic |
| `ai-agent-skills` | `create-dev-workflows` | Generator: creates/updates a repo's project-specific `plate-it` / `fill-it` / `take-it` / `drain-it` / `send-it` / `clean-it` workflow skills |
| `ai-agent-skills` | `github-issues` | Issue/board reads, stale-issue detection, idempotent dedupe-then-file issue creation |
| `ai-agent-skills` | `sentry-triage` | Gate-and-escalate Sentry triage; qualifying hits escalate via `github-issues` |
| `ai-agent-skills` | `pr-shepherd` | PR lifecycle mechanics — check polling, merge queue vs direct merge, coupled-PR serialization, worktree teardown |
| `ai-agent-skills` | `repo-cleanup` | Post-shipping git reconciliation mechanics — `[gone]`/squash-merged branch sweep, stale-worktree teardown, stash triage, untracked-noise sweep (the engine behind a repo's `clean-it`) |
| `ai-agent-skills` | `repo-health` | Scripted signal scans — TODO/FIXME markers, skipped tests, CI duration/flake, mobile release lag |

### Generator + capability skills

`create-dev-workflows` generates **project-level** `plate-it` (prioritized work plate), `fill-it` (backlog grooming to Ready), `drain-it` (loop-driven Ready-column dispatcher), `take-it`
(parallel issue-shipping: "take #341, #432"), `send-it` (single-PR end-to-end), and `clean-it`
(post-shipping git reconciliation) skills into a product repo's `.claude/skills/`. The plugin
deliberately ships no generic runtime versions of these — only project skills exist at runtime, so
trigger phrases always resolve to the repo's own skill. Generated skills stay thin by delegating
shared mechanics to the capability skills (`github-issues`, `sentry-triage`, `pr-shepherd`,
`repo-cleanup`, `repo-health`, `testflight`). `plate-it` / `send-it` / `clean-it` are core (always
generated); `take-it` / `fill-it` / `drain-it` are opt-in. (`clean-it`'s engine is `repo-cleanup`,
named distinctly so the "clean it" phrase resolves to the project skill, not the capability.)

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
