# sassydog-skills

Sassy Dog AI agent skills marketplace for Claude Code, Gemini CLI, and other AI coding tools.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| `sassy-dog` | `survey-work` | Prioritized work plate — customer pain, backlog, tech debt, dev experience, synthesized next bets (formerly `plate-it`) |
| `sassy-dog` | `groom-backlog` | Backlog grooming — refine issues until dispatchable, then promote to Ready (formerly `groom-it`, originally `fill-it`) |
| `sassy-dog` | `take-it` | Parallel issue-shipping — "take #341, #432", one worktree sub-agent per issue |
| `sassy-dog` | `dispatch-ready` | Loop-driven Ready dispatcher — one idempotent tick per invocation, under `/loop` (formerly `drain-it`) |
| `sassy-dog` | `send-it` | Single-PR end-to-end — worktree audit, freshness gates, pre-flight, PR body, watch, merge |
| `sassy-dog` | `tidy-repo` | Post-shipping git reconciliation — stale branches, worktrees, stashes, untracked noise (formerly `clean-it`) |
| `sassy-dog` | `github-secrets` | GitHub Actions secrets & variables — scope hierarchy, CLI usage, common mistakes |
| `sassy-dog` | `testflight` | TestFlight / App Store Connect API — builds, testers, feedback |
| `sassy-dog` | `assess-it` | Multi-agent repository audit → deduped, PR-sized GitHub Issues under a tracking Epic |
| `sassy-dog` | `recap` | Session wrap-up report — work completed, what surfaced, issues to file, immediate next steps |
| `sassy-dog` | `setup-config` | Generator/refresher: writes and re-syncs a repo's `.claude/sassy-dog/*.md` workflow-skill config plus its `.claude/settings.json` plugin declaration |
| `sassy-dog` | `setup-hooks` | Generator/refresher: renders a repo's stack-specific Claude Code hooks (`.claude/hooks/sassydog-*.sh` + settings.json wiring) from detection — format-on-edit, lint-findings-fed-back; re-runnable as the stack evolves |
| `sassy-dog` | `setup-deps` | Generator/refresher: renders a repo's `.github/dependabot.yml` (grouped, per detected ecosystem) plus its dependency automation workflows — auto-merge, `bun.lock` sync, pod lockfile sync — from stack detection; re-runnable as the stack evolves |
| `sassy-dog` | `github-issues` | Issue/board reads, stale-issue detection, idempotent dedupe-then-file issue creation |
| `sassy-dog` | `sentry-triage` | Gate-and-escalate Sentry triage; qualifying hits escalate via `github-issues` |
| `sassy-dog` | `pr-shepherd` | PR lifecycle mechanics — check polling, merge queue vs direct merge, coupled-PR serialization, worktree teardown |
| `sassy-dog` | `repo-cleanup` | Post-shipping git reconciliation mechanics — `[gone]`/squash-merged branch sweep, stale-worktree teardown, stash triage, untracked-noise sweep (the engine behind a repo's `tidy-repo`) |
| `sassy-dog` | `repo-health` | Scripted signal scans — TODO/FIXME markers, skipped tests, CI duration/flake, mobile release lag |
| `sassy-dog` | `whats-on-fire` | Org-wide portfolio sweep — Sentry issues + crons, stalled PRs, red default branches, Dependabot exposure, and blind spots (products with no monitoring/alerting/scanning); ranks across products and routes each to the owning repo's `survey-work` |
| `sassy-dog` | `whats-behind` | Portfolio currency audit — peer-relative version drift across pinned Actions, toolchains, runner labels, and Dependabot coverage; reports which repos lag and whether the cause is a missing automation config |

### Workflow skills + capability skills

The six workflow skills — `survey-work` (prioritized work plate), `groom-backlog` (backlog grooming to
Ready), `take-it` (parallel issue-shipping: "take #341, #432"), `dispatch-ready` (loop-driven Ready
dispatcher), `send-it` (single-PR end-to-end), and `tidy-repo` (post-shipping git reconciliation) —
each have **one** generic implementation, shipped in the plugin. There is no per-repo copy.

Per-repo behavior lives in that repo's `.claude/sassy-dog/<skill>.md`: YAML frontmatter for facts
and toggles, `##` sections for freeform prose that survives refreshes. Each skill inlines its config
at load time, and treats a missing config as a first-class `NO_CONFIG` state — degrading to a
conservative mode rather than erroring. `take-it` and `dispatch-ready` are the two exceptions that stop
instead, because both act unattended and outward-facing.

Facts that can be derived are never configured: repo slug, default branch, and
`delete_branch_on_merge` all come from `gh repo view` at runtime, so they cannot drift.

[Stacked PRs](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs) are supported
and **opt-in per repo** via a `stacked_prs:` config block, absent by default. Handling an existing
stack safely is not opt-in: `pr-shepherd` always probes before merging, because a middle layer
reports green + `MERGEABLE` + `CLEAN` exactly like an ordinary PR and merging on that reading lands
it out of order. Whether a repo is enabled for the preview, whether a PR is a layer, and whether a
layer is safe to merge now are all derived at runtime by `pr-shepherd`'s `stack-probe.sh` — the
config carries only the policy.

Workflow skills stay thin by delegating shared mechanics to the capability skills
(`github-issues`, `sentry-triage`, `pr-shepherd`, `repo-cleanup`, `repo-health`, `testflight`).
`repo-cleanup` remains distinct from `tidy-repo`: the former is the mechanics engine, the latter the
user-facing flow.

`setup-hooks` is the same pattern one layer down: it detects the repo's stack (ruff,
prettier, markdownlint, shellcheck, dart, rustfmt, gofmt, dotnet format — keyed on repo config, not
installed binaries) and renders a single PostToolUse dispatcher into `.claude/hooks/`, wired into
`.claude/settings.json`. Formatters fix silently; unfixable lint findings exit 2 so they feed
straight back for an immediate fix. Re-runs reconcile only entries the generator owns (command path
references `sassydog-`), never hand-written hooks. The generated script itself carries a
`generated-by:` producer marker, and because that marker is committed in every consumer repo the
ownership matcher accepts every producer name this generator has ever emitted, in either marker
namespace, and normalises to the current form on write — a matcher narrowed to the current name
would treat every pre-rename consumer script as hand-written and silently skip it.

`setup-deps` is the third generator in that family, aimed at dependency automation: it detects the
repo's ecosystems from tracked files, renders `.github/dependabot.yml` grouped per ecosystem, and
adds the workflows that keep Dependabot's PRs mergeable — auto-merge behind a real required check,
plus `bun.lock` / `Podfile.lock` sync where Dependabot cannot rewrite the lockfile itself. Its
`generated-by:` marker is committed inside every consumer repo's `.github/`, so the same ownership
rule applies: the matcher accepts every producer name this generator has ever emitted, in either
marker namespace, normalising to the current form on write, while a file with no marker at all is
reported as hand-written and never overwritten.

### Review agents

`assess-it` ships dedicated audit-mode agents (namespaced `sassy-dog:<name>`):
`architecture-reviewer`, `code-quality-reviewer`, `security-reviewer`, `testing-reviewer`,
`cicd-release-reviewer`, `infra-platform-reviewer`, `observability-ops-reviewer`,
`dx-docs-reviewer`, `dependency-supply-chain-reviewer`.

## Installation

### Claude Code

```bash
# Add as a marketplace
claude plugin marketplace add Sassy-Dog/sassydog-skills

# Install the plugin
claude plugin install sassy-dog
```

### Local Development

```bash
claude --plugin-dir ~/Repos/sassy-dog/sassydog-skills
```

## Updating / Troubleshooting

### One-time re-add after the rename to `sassy-dog`

The plugin was renamed `ai-agent-skills` → `sassy-dog` and the marketplace `sassy-dog-skills` →
`sassydog-skills` in the same release (issue #71). A machine that added the marketplace under the
old name cannot update across the rename — plugin name, marketplace name, and cache path all moved
at once. Treat it as uninstall-and-reinstall, exactly once per machine:

```bash
claude plugin marketplace remove sassy-dog-skills
claude plugin marketplace add Sassy-Dog/sassydog-skills
claude plugin install sassy-dog
```

Plugin updates are **manual** — the cache does not follow releases. After every release (a new CalVer stamped into `.claude-plugin/plugin.json` via `scripts/stamp-version.sh` — see `docs/VERSIONING.md`), each consumer machine must run:

```bash
claude plugin update sassy-dog@sassydog-skills
```

### The bare plugin name fails

`claude plugin update sassy-dog` returns "not found" — the error doesn't hint at the fix. The marketplace-qualified name is required: `sassy-dog@sassydog-skills`.

### `claude plugin marketplace update` is not a plugin update

`claude plugin marketplace update` only `git pull`s the marketplace clone. It succeeds even when the *plugin cache* — the code your skills actually run from — is still stale. Diagnose with:

```bash
ls ~/.claude/plugins/cache/sassydog-skills/sassy-dog/
# 2026.6.4    <- installed version (stale)
```

Compare against `version` in `.claude-plugin/plugin.json` on `main` (e.g. `2026.7.16`). If they differ, run the qualified update command above. This failure mode is silent: no error anywhere — skills just keep old bugs and trigger phrases stop matching.

### Updates freeze at the cached version (SAML error)

Plugin install/update does a fresh **SSH** clone of this INTERNAL repo. The SSH key must be SSO-authorized for the `Sassy-Dog` org — on <https://github.com/settings/keys>, use **Configure SSO** on the key. Without it, updates fail with a SAML error or freeze silently at the cached version.

## Repository layout

This repo is a single plugin: skills, agents, and the manifest live at the root.

```
sassydog-skills/
├── .claude-plugin/plugin.json   # Plugin manifest
├── agents/                      # Subagents (auto-discovered, namespaced sassy-dog:<name>)
│   └── *-reviewer.md
└── skills/
    └── my-skill/
        ├── SKILL.md             # Required — frontmatter + instructions
        ├── references/          # Optional — detailed reference docs
        └── scripts/             # Optional — executable tools
```
