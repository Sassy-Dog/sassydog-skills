---
name: send-it
description: >
  Ship a PR end-to-end — worktree audit, freshness gates, pre-flight CI guardrails,
  template-compliant PR body, commit, push, watch checks, merge, clean up. Use when the user says
  "send it", "ship it", "open the PR", "create a PR", or asks to merge a branch. Reads the current
  repo's settings from `.claude/sassy-dog/send-it.md`; run `refresh-skills` if that file
  is missing.
---

# Send-It

End-to-end PR flow, in order: worktree audit → freshness gates → pre-flight guardrails → PR body →
commit/push → watch + merge (delegated to `ai-agent-skills:pr-shepherd`).

## 1. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/send-it.md" 2>/dev/null || echo "NO_CONFIG"`

Frontmatter supplies `preflight_commands`, `pr_template_path`, `pr_template_sections`,
`merge_queue`, and the optional `migrations`, `codegen`, `review_agent`, and `stacked_prs` blocks.
Contract: `ai-agent-skills:refresh-skills` → `references/config-contract.md`.

Repo slug and default branch are **derived, never configured**:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
```

### If it reads `NO_CONFIG`

Run §2 — the worktree audit is universal and never skipped. Then **stop before pushing** and say so:

> No `.claude/sassy-dog/send-it.md` in this repo. I can audit the worktree and draft the commit,
> but I don't know this repo's pre-flight commands or PR template. If this repo has a project-level
> `send-it` under `.claude/skills/`, use that instead. Otherwise: tell me the pre-flight command, or
> run `ai-agent-skills:refresh-skills`.

### Offer to set this repo up

Then offer to fix it — this is the next step, so ask now:

- **If `.claude/skills/send-it/SKILL.md` exists with a `generated-by:` marker** — this repo is on the
  superseded generated-skills architecture. Say so concretely: *"This repo has a generated
  `send-it` I can migrate — I'd extract its config, show you the result, and remove the old skill
  only after you approve. Want me to?"*
- **Otherwise** — nothing to extract from: *"I can set this repo up. It takes a few questions about
  how this repo works. Want me to?"*

Naming which path applies matters: one of them ends in deleting a file the user may not know is
there.

On yes, delegate to `ai-agent-skills:refresh-skills`. **Never write config yourself** — the
refresher owns the contract, and a skill that writes its own forks the format the moment the
contract moves.

**Offer once per session.** Running deliberately in an unconfigured repo is legitimate; re-prompting
every invocation is noise. If declined, carry on and don't raise it again.

**Do NOT infer pre-flight commands from a `Makefile` target, a `scripts/` entry, or the CI
workflow.** A guessed command that exits 0 without running anything is indistinguishable from a
passing check, and this skill *pushes and merges* on the strength of it. Skipping the gates
knowingly is recoverable; believing a gate passed when it never ran is not.

The optional §3 gates are simply off — no `migrations:` block means no migration check, and that is
correct, not degraded.

## 2. Worktree audit

**Non-negotiable, even on a "trivial" one-file PR.** Run first:

```bash
git status --short
git stash list
```

For **every** entry — modified, added, deleted, untracked, including pre-existing dirt — pick
exactly one action and announce it before proceeding:

| Action | When | How |
| --- | --- | --- |
| **Ship with this PR** | Part of the same logical change | `git add <file>` — explicit paths, never `git add -A` |
| **Ship as a separate PR** | Real work, unrelated scope that does NOT depend on this branch | Branch + commit it FIRST on its own branch, push, open PR; then return |
| **Ship as a stack layer** | Real work, separate scope, but it *builds on* this branch | Only if `stacked_prs:` is configured — see §6a. Otherwise treat it as "ship with this PR" or stash; do NOT branch it from the default branch, because it would not compile without this branch's changes |
| **Stash for later** | Mid-flight WIP | `git stash push -m "<descriptive name>" -- <files>` |
| **Discard** | Truly unwanted | `git restore <file>` / `rm <file>` — only after confirming |

Untracked files (`??`) are the highest-risk class: invisible to `git diff`, easy to lose. Do not
proceed until `git status --short` is empty OR every entry has a confirmed disposition. "I'll just
stage the file I changed" is the failure mode this step exists to prevent.

## 3. Freshness gates

Run each gate **only if** the matching config block is present. Skip silently otherwise.

### If `migrations:` is set

Schema source of truth changed ⇒ a generated migration must ship alongside it. Collect the changed
set once, against the derived default branch:

```bash
CHANGED=$( { git diff --name-only "origin/<default_branch>"; git ls-files --others --exclude-standard; } | sort -u )
```

If anything under `migrations.schema_dir` changed, run `migrations.regen_command`, then
`git status --short <migrations.dirs>`. A new migration → stage and commit it **with** the schema
change. Nothing produced → already in lockstep.

**Destructive-SQL guard** — never ship data-losing SQL; write a data-preserving multi-step
migration instead. Scan changed `.sql` files under `migrations.dirs` for `TRUNCATE`, `DROP TABLE`,
`DROP COLUMN`, and `ALTER TABLE … DROP`, and stop if any match.

### If `codegen:` is set

Never ship stale generated artifacts. If the source the generator reads changed, run
`codegen.command` and `git status --short <codegen.output_dirs>`, then commit the regenerated
output with the change.

## 4. Pre-flight CI guardrails

Mirror CI locally, scoped to changed paths — seconds locally beats a CI round-trip. Run
`preflight_commands` **exactly as written in config**.

**Never substitute a command you inferred.** With no configured value there is no pre-flight; stop
and ask rather than running something that looks equivalent.

Any check fails → fix before commit. Never push and rely on CI to surface it.

### If `review_agent:` is set

Lint, type, and test cannot catch design regressions. Before drafting the PR body, dispatch the
configured agent against the staged diff versus the default branch, with a one-line scope
statement. Blocking findings → fix and re-run. Nits → roll in, or note "Known and accepted" in the
PR body.

Apply any `## extra-gates` section from config here.

## 5. Template-compliant PR body

**MANDATORY CHECKPOINT.** The body must contain every section listed in `pr_template_sections`,
matching `pr_template_path`. Never pass a one-liner `--body "fix bug"` that bypasses the template.

### Issue references — close-on-merge rules

- Closing an issue requires a literal `Closes #<N>` (or `Fixes`/`Resolves`) **on its own line** —
  one line per issue. Comma lists don't reliably parse.
- **A title parenthetical like `fix(web): foo (#240)` is a hyperlink, NOT a close trigger.** This
  is the classic shipped-but-still-open cause.
- If `sentry:` is configured and this fixes a Sentry issue, add `Fixes <SENTRY-SHORT-ID>` on its
  own line — the Sentry↔GitHub integration only parses the literal keyword form.
- Partial or follow-up work → omit the keyword, leave the issue open.

## 6. Commit, push, watch, merge

Commit with a conventional-commit subject, a brief why, the `Closes #<N>` line, and the co-author
trailer:

```text
Co-Authored-By: Claude <your model> <noreply@anthropic.com>
```

**Derive the model name from whichever model is running — never from config.** The trailer records
who actually wrote the commit, so a stored value is wrong the moment a different model does the
work, and wrong in the most confident-looking way: every commit carries it. This is the
configure-only-what-cannot-be-derived rule applied to the one fact that changes without anyone
touching the repo. Push with `git push -u origin "$(git branch --show-current)"`, then
`gh pr create` with the §5 body.

**Derive the base — never assume the default branch.** `gh pr create` silently defaults to the
repo's default branch, which is wrong for any branch cut from another feature branch and is how a
PR ends up showing a diff full of someone else's commits:

```bash
git merge-base --fork-point "$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" 2>/dev/null
git log --oneline --graph --decorate -15   # what does this branch actually sit on?
```

If this branch was cut from the default branch (the normal case), nothing changes. If it was cut
from another **branch that still has an open PR**, pass that branch explicitly:
`gh pr create --base <that branch>`. State the base you chose and why — a silently wrong base is
invisible in the PR body and obvious only in the diff.

### 6a. If this is a stack layer (ONLY if `stacked_prs:` is configured)

**Skip this whole section when the config has no `stacked_prs:` block.** Nothing below applies, and
a branch cut from another feature branch is still handled by the base derivation above.

When it IS configured and this branch sits on another open PR's branch, link the two into a stack
after creating this PR — bottom (the existing PR) then top (yours):

```bash
echo '{"pull_requests":[<lower pr>,<this pr>]}' \
  | gh api "repos/<slug>/stacks" -X POST --input -
```

Pass explicit JSON: `pull_requests` must be integers, and `gh api -f` would send strings. If the
repo is not enabled for the preview the call fails — that is harmless. The PR is already correctly
based, which is the part that matters; linking only adds GitHub's stack UI and merge ordering.

**Then hand off and stop watching for a merge.** `ai-agent-skills:pr-shepherd` will not merge a
layer while a lower one is open (exit 23), and refuses a stack under a merge queue outright
(exit 24). Say which applies rather than leaving the user watching a PR that will not land.

**Watch + merge is delegated.** Do NOT reimplement polling or merging inline:

```
Skill: ai-agent-skills:pr-shepherd
Args: "Shepherd PR #<N> in <repo>: mergeable check first, watch checks, then
       <merge_queue ? 'enqueue via merge queue (--auto, no method flag, confirm isInMergeQueue)'
                    : 'squash-merge with --delete-branch'>.
       After merge, reconcile local <default_branch> and delete the feature branch."
```

If `ai-agent-skills:pr-shepherd` is not in your available skills, STOP and tell the user to install
the plugin (`claude plugin install ai-agent-skills`) — do not improvise the merge flow from memory.

## Guardrails

- Never silently scope to "the file we just edited" — §2 in full, every time.
- Never ship a schema change without its migration; never ship destructive SQL.
- Never push past a failing pre-flight check; never merge past a red CI.
- Never force-push the default branch.
- **Never let `gh pr create` default its base** on a branch cut from another feature branch — derive
  it and say which base you used.
- Draft PRs: stop after `gh pr create` — the author flips to ready.

Apply any `## extra-guardrails` section from config on top of these.
