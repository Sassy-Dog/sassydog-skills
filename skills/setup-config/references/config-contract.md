# Repo config contract

The generic workflow skills — `survey-work`, `groom-backlog`, `take-it`, `dispatch-ready`, `send-it`, `tidy-repo` —
ship one implementation each in the plugin and read their per-repo behavior from:

```text
<repo-root>/.claude/sassy-dog/<skill-name>.md
```

One file per skill. Each file is YAML frontmatter (facts and toggles) followed by `##` sections
(freeform prose). This document is the source of truth for that format; `setup-config`
writes these files and the six skills read them.

## Governing principle: configure only what cannot be derived

Never write a fact into config that the skill can obtain at runtime. A configured value is a value
that can drift; a derived value cannot.

**Always derived, never configured:**

| Fact | How the skill gets it |
| --- | --- |
| Repo slug | `gh repo view --json nameWithOwner --jq .nameWithOwner` |
| Default branch | `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` |
| `delete_branch_on_merge` | `gh repo view --json deleteBranchOnMerge --jq .deleteBranchOnMerge` |
| Current branch | `git branch --show-current` |
| Repo root | `git rev-parse --show-toplevel` |
| Commit co-author trailer | the running model's own name — `Co-Authored-By: Claude <model> <noreply@anthropic.com>` |

This is why no `repo:` or `default_branch:` key appears in the schemas below, even though the old
templates rendered `{{REPO_SLUG}}` and `{{DEFAULT_BRANCH}}` into every generated skill.

**This is not theoretical.** Migrating this repo surfaced two facts that had drifted in its
generated skills: they asserted `delete_branch_on_merge: false` and "there is no merge queue", while
the repo had since enabled both. The derivable one self-corrected the moment it became derived. The
other — `merge_queue`, which has no `gh repo view` equivalent — carried the staleness across, and
only a rejected `gh pr merge --delete-branch` exposed it.

So: the principle removes drift exactly where a fact is derivable, and nowhere else. **A refresh
must re-verify every configured fact against live state**, not copy it forward from the previous
render. `merge_queue` in particular should be checked via the `mergeQueue(branch:)` GraphQL field
rather than asked about or inherited.

## Governing principle: presence is the toggle

The old templates carried paired state — an `IF:SENTRY` flag *and* `{{SENTRY_ORG}}`/`{{SENTRY_PROJECTS}}`
facts — which can disagree. In config, **the presence of a block enables the feature**:

```yaml
sentry:                     # present  -> the Sentry surface runs
  org: sassy-dog
  projects: [qrninja-web]
```

Omit the `sentry:` key entirely and the surface is skipped. There is no `sentry: false`. The same
holds for `board`, `testflight`, `mobile`, `migrations`, `codegen`, `secret_bootstrap`,
`review_agent`, and `claim_label`.

Two keys are genuine scalars rather than blocks, because they carry no sub-facts:

- `merge_queue: true|false` — merge queue vs. direct squash-merge
- `write_policy: read-only|gated` — whether `survey-work` may file issues under its Sentry gate

## Shared blocks

These appear in whichever skill files need them. A repo that uses a project board puts the same
`board:` block in `survey-work.md`, `groom-backlog.md`, `take-it.md`, and `dispatch-ready.md`.

```yaml
board:
  number: 4                 # project number
  owner: Sassy-Dog
  project_id: PVT_kwDO...   # GraphQL node IDs, from board-snapshot.sh
  status_field_id: PVTSSF_...
  ready_option_id: 47fc9ee4
  backlog_option_id: f75ad846
  in_progress_option_id: 98236657

sentry:
  org: sassy-dog
  projects: [qrninja-web, qrninja-mobile]
  gate: defaults            # or an explicit override of the qualifying gate

testflight:
  bundle_id: com.sassy-dog.qrninja

mobile:
  release_workflow: mobile-release.yml
  path_prefix: apps/mobile/

migrations:
  schema_dir: packages/db/src/schema
  dirs: packages/db/src/migrations
  regen_command: bun run db:generate

codegen:
  command: bun run codegen
  output_dirs: apps/web/src/generated
  hint: run codegen after touching any tRPC router

stacked_prs:
  max_depth: 4              # cap on layers a dispatcher will build

secret_bootstrap: eval "$(doppler secrets download --no-file --format env 2>/dev/null)"
review_agent: qr-ninja-review-orchestrator
claim_label: in-progress
posthog: true
merge_queue: false
```

Omit any block the repo doesn't use.

### `stacked_prs` — read by `groom-backlog`, `take-it`, `dispatch-ready`, `send-it`

Presence enables GitHub [stacked PRs](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs): `groom-backlog` may propose a `stack:` chain, and the dispatchers may build one. **Absent is the correct value for a repo that has not deliberately opted in**, and it is absent everywhere today.

Three things are deliberately NOT configured here, because they are derived:

| Fact | How it is obtained |
| --- | --- |
| Is this repo enabled for stacks? | `sassy-dog:pr-shepherd` → `scripts/stack-probe.sh` (REST `GET /repos/{o}/{n}/stacks`, 200 vs 404) |
| Is a given PR a stack layer, and which? | the same probe (GraphQL `PullRequest.stack`) |
| Is it safe to merge this layer now? | the probe's derived `lower_open` |

The preview is still rolling out per-repo, so enablement is exactly the kind of fact that would go stale the day after it was written down. Config carries only the *policy* — may we stack here, and how deep.

**`stacked_prs` and `merge_queue: true` together are refused at merge time,** not at config time: GitHub's queue support for stacks is still rolling out, and `pr-shepherd` stops with exit 24 rather than guessing. Setting both is legal — it simply means the dispatchers may open stacks that a human has to land.

## Per-skill schemas

Each section lists only the keys that skill reads *in addition to* the shared blocks above.

### `survey-work.md`

```yaml
scan_paths: apps packages          # tech-debt scan roots
exclude_pathspecs: ":(exclude)packages/db/src/migrations"
ci_workflow: ci.yml
priority_labels: [p0, p1, p2]
write_policy: read-only            # or `gated` to allow the Sentry->GitHub file path
```

Prose sections: `## extra-surfaces`, `## scoring-overrides`, `## extra-guardrails`.

### `groom-backlog.md`

```yaml
gotcha_summary: >
  Repo-specific traps a cold sub-agent must know before an issue is dispatchable.
```

Prose sections: `## extra-rubric`.

### `take-it.md`

```yaml
stack_summary: Bun workspaces monorepo; Next.js 15 web + Drizzle db package
preflight_commands: |
  bun run lint
  bun run typecheck
pr_template_sections: [Summary, Testing, Risk]
```

Prose sections: `## subagent-rules`, `## extra-guardrails`.

### `dispatch-ready.md`

```yaml
max_in_flight: 3
```

Prose sections: `## extra-sequencing`.

### `send-it.md`

```yaml
pr_template_path: .github/pull_request_template.md
pr_template_sections: [Summary, Testing, Risk]
preflight_commands: |
  bash scripts/preflight.sh
```

Prose sections: `## extra-gates`, `## extra-guardrails`.

### `tidy-repo.md`

```yaml
dep_version_globs: ["**/package.json", "**/bun.lock"]
noise_allowlist: ["*.log", ".DS_Store"]
never_discard: [".env.local", "*.pem"]
```

Prose sections: `## extra-cleanup`, `## extra-guardrails`.

## Prose sections

Section names carry over verbatim from the `BEGIN/END PROJECT-SPECIFIC` fence slots the old
generated skills used, so migration is a mechanical lift:

| Old fence slot | New config section | File |
| --- | --- | --- |
| `extra-surfaces` | `## extra-surfaces` | `survey-work.md` |
| `scoring-overrides` | `## scoring-overrides` | `survey-work.md` |
| `extra-rubric` | `## extra-rubric` | `groom-backlog.md` |
| `subagent-rules` | `## subagent-rules` | `take-it.md` |
| `extra-sequencing` | `## extra-sequencing` | `dispatch-ready.md` |
| `extra-gates` | `## extra-gates` | `send-it.md` |
| `extra-cleanup` | `## extra-cleanup` | `tidy-repo.md` |
| `extra-guardrails` | `## extra-guardrails` | four files |

All eight slots must round-trip through migration. The old `update-mode.md` slot list omitted
`extra-rubric` and `extra-sequencing`; that omission is fixed here.

Prose is never generated or rewritten by a refresh — it is carried across verbatim, which is the
whole point of keeping it separate from the frontmatter facts.

## How skills read this

Each skill inlines its config at load time with dynamic context injection:

```text
!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/<skill>.md" 2>/dev/null || echo "NO_CONFIG"`
```

`git rev-parse` rather than `${CLAUDE_PROJECT_DIR}` because the substitution order between
placeholder expansion and shell execution is not specified, and every one of these skills requires
a git repo regardless. The command is safe outside a repo — it yields `NO_CONFIG` with no stderr.

**`NO_CONFIG` is a first-class state, not an error.** A skill that finds no config must derive what
it safely can, run in its most conservative mode, and tell the user to run
`sassy-dog:setup-config`.

### The no-invention rule

**"Derivable" means derivable from git or `gh` in this repo. It does NOT mean "reachable by some
other means."** This distinction is the whole safety property, and it is easy to lose.

Observed 2026-08-05: the generic `survey-work` was run in an un-migrated repo, correctly reported
`NO_CONFIG`, and then invoked the Sentry surface anyway and ran the tech-debt scan with the example
`SCAN_PATHS` from `repo-health`'s own docs. Sentry projects *are* listable for the org, and a scan
path *can* be guessed from the directory tree — so both looked derivable. The result was a plate
built on invented inputs that read exactly like a real one.

Two rules follow, and both are load-bearing:

1. **A surface with no config block is OFF**, however reachable it looks. Render it
   `skipped — not configured`.
2. **State the rule at the point of use, not only in the `NO_CONFIG` preamble.** The failure above
   happened because the instruction lived in §1 and the temptation lived in §3. By the time a skill
   reaches the pull section it has read a lot of text, and a parenthetical `*(if configured)*` is a
   weak signal against a concrete, available action. Each conditional surface must carry its own
   **ONLY if** guard.

The asymmetry that justifies the strictness: **skipping a surface knowingly is recoverable; acting
on a fabricated one is not**, because the output is indistinguishable from a real result. This is
sharpest in `send-it`, which pushes and merges on the strength of a pre-flight command — a guessed
command that exits 0 without running anything looks exactly like a passing check.

Skills that write or dispatch unattended (`take-it`, `dispatch-ready`) do not degrade at all; they stop.

## Cloud sessions and routines

A repo carrying these config files must also declare, in its own `.claude/settings.json`, both the
marketplace (`extraKnownMarketplaces` → `sassydog-skills` from `Sassy-Dog/sassydog-skills`) and the
plugin (`enabledPlugins` → `sassy-dog@sassydog-skills`). Plugin skills enabled only in user settings
do not transfer to cloud sessions or scheduled routines — only repo-declared plugins install at
session start, and they install *from the marketplace the repo declares*. `enabledPlugins` alone
references the marketplace by name only; the name resolves locally through user-level registration
(`~/.claude/plugins/known_marketplaces.json`), which never reaches a cloud VM. Without both
declarations a scheduled `dispatch-ready` silently finds no skill, while every local session works fine.
