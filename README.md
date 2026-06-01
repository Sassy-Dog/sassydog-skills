# ai-agent-skills

Sassy Dog AI agent skills marketplace for Claude Code, Gemini CLI, and other AI coding tools.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| `ai-agent-skills` | `github-secrets` | GitHub Actions secrets & variables — scope hierarchy, CLI usage, common mistakes |
| `ai-agent-skills` | `testflight` | TestFlight / App Store Connect API — builds, testers, feedback |
| `ai-agent-skills` | `codebase-assessment` | Multi-agent repository audit → deduped, PR-sized GitHub Issues under a tracking Epic |

### Review agents

`codebase-assessment` ships dedicated audit-mode agents (namespaced `ai-agent-skills:<name>`):
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
