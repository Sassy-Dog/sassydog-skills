---
name: clean-it
description: >
  Clean up local + remote git state after a productive day — fast-forward the default branch and
  prune, inventory stale branches/worktrees, triage orphan stashes, sweep untracked-file noise,
  remove stale worktrees, delete merged-PR branches local + remote. Use when the user says "clean
  it", "clean up", "tidy the repo", "clean branches", or asks to remove stale
  worktrees/branches/stashes. Reads the current repo's settings from
  `.claude/sassy-dog/clean-it.md`; run `refresh-sassydog-skills` if that file is missing.
---

# Clean-It

Post-shipping git reconciliation for the current repo.

This skill is **thin**: it reads the repo's facts from config and delegates the actual mechanics —
the `[gone]` grep trap, squash-merge `-D`, stash triage by `closedByPullRequestsReferences`,
agent-worktree teardown — to `ai-agent-skills:repo-cleanup`, so the plumbing lives in one place
across every repo.

**Acting principle:** assess first, act on what's confident, escalate only on mixed signal —
substantive WIP, dep-file touches, abandoned-but-non-trivial work. Never auto-drop a stash on an
OPEN issue; never auto-discard outside the allowlist.

## 1. Derive the repo facts

These are never configured — read them live so they cannot drift:

```bash
gh repo view --json nameWithOwner,defaultBranchRef,deleteBranchOnMerge \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name) dbom=\(.deleteBranchOnMerge)"'
```

## 2. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/clean-it.md" 2>/dev/null || echo "NO_CONFIG"`

The block above is this repo's `.claude/sassy-dog/clean-it.md`, inlined at load time. Its
frontmatter carries the sweep policy — `dep_version_globs`, `noise_allowlist`, `never_discard`,
optional `claim_label` — and its `##` sections carry repo-specific prose. The contract is
`ai-agent-skills:refresh-sassydog-skills` → `references/config-contract.md`.

**If it reads `NO_CONFIG`**, this repo has not been set up yet. The §1 facts are still available,
so the branch/worktree work is safe to do. But run with an **empty** noise allowlist and an empty
dep-version-glob list: with no `never_discard` list you cannot know which untracked files are
precious, so **discard nothing at all** and report what you would have swept.

**Do not infer an allowlist from the repo's `.gitignore` or file extensions.** `.gitignore` lists
files that are intentionally untracked, which is the opposite of disposable — that is exactly where
`.env.local` lives. Then tell the user:

> No `.claude/sassy-dog/clean-it.md` in this repo — running in conservative mode with no
> auto-discard. Run `ai-agent-skills:refresh-sassydog-skills` to set this repo up.

## 3. Run

Delegate the full reconciliation, passing the §1 facts and the §2 policy:

```
Skill: ai-agent-skills:repo-cleanup
Args: "Reconcile <repo> post-shipping. default-branch=<default_branch>;
       delete-branch-on-merge=<delete_branch_on_merge>;
       dep-version-globs=<dep_version_globs>;
       noise-allowlist=<noise_allowlist>;
       never-discard=<never_discard>;
       claim-label=<claim_label, omit if unset>.
       Inventory read-only first, then sync+prune, triage stashes, sweep untracked noise, tear
       down stale/detached worktrees, delete [gone] + squash-merged branches, mop up stale remote
       branches, clear orphan claim labels if a claim label is set. Apply the assess-first /
       ask-on-mixed-signal principle."
```

`repo`, `default_branch`, and `delete_branch_on_merge` come from §1; the rest come from §2's
frontmatter. Omit `claim-label` entirely when the config does not set one.

If `ai-agent-skills:repo-cleanup` is not in your available skills, STOP and tell the user to
install the plugin (`claude plugin install ai-agent-skills`) — do not improvise the reconciliation
from memory. The `[gone]` grep trap and squash-merge `-D` are easy to get wrong and lose work.

## 4. Repo-specific cleanup

If the config has an `## extra-cleanup` section, perform those steps after the delegation above.
They cover repo-unique work `repo-cleanup` doesn't know about — extra label hygiene, cache
directories, vendored-artifact pruning.

## Guardrails

- Never delete a branch with an OPEN PR; never delete the default branch, local or remote.
- Never `--force` remove a worktree whose SHA isn't in the default branch without confirming.
- Never auto-drop a stash on an OPEN issue; `closedByPullRequestsReferences`, not bare issue
  state, is the "shipped" signal.
- Never auto-discard untracked files outside the allowlist, or anything in the never-discard list.
- Don't disable `delete_branch_on_merge`; don't run inside a worktree you're about to remove.

Apply any `## extra-guardrails` section from the config on top of these.
