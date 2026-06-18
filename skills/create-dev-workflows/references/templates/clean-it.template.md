<!--
TEMPLATE: clean-it · version 1
Render rules: see plate-it.template.md header. Same conventions.
  {{FACT}}                    → replace with the detected/confirmed value
  IF:FLAG ... ELSE ... ENDIF  → keep one arm based on interview answers, drop the markers
  BEGIN/END PROJECT-SPECIFIC  → KEEP the fence markers in the generated file (update mode splices these)
  Drop this comment block. Frontmatter `---` MUST be line 1 of the rendered file. The generated-by
  marker sits immediately AFTER the closing `---`, never before it.

  IF:CLAIM_LABEL is set when the repo has take-it AND take-it claims issues with a status label
  (e.g. status:in-progress) — renders the claim-label cleanup fact. {{CLAIM_LABEL}} is that label.
-->
---
name: clean-it
description: >
  Clean up local + remote git state in the {{PROJECT_NAME}} repo after a productive day —
  fast-forward {{DEFAULT_BRANCH}} and prune, inventory stale branches/worktrees, triage orphan
  stashes, sweep untracked-file noise, remove stale worktrees, delete merged-PR branches local +
  remote. Use when the user says "clean it", "clean up", "tidy the repo", "clean branches", or asks
  to remove stale worktrees/branches/stashes. {{PROJECT_NAME}}-specific
  <!-- IF:CLAIM_LABEL -->Also clears leftover {{CLAIM_LABEL}} claim labels on issues whose PR already merged.<!-- ENDIF -->
---

<!-- generated-by: ai-agent-skills:create-dev-workflows | template: clean-it | template-version: 1 -->

# {{PROJECT_NAME}} Clean-It

Post-shipping git reconciliation for this repo. This skill is **thin**: it holds {{PROJECT_NAME}}'s
facts and delegates the actual mechanics (the `[gone]` grep trap, squash-merge `-D`, stash triage by
`closedByPullRequestsReferences`, agent-worktree teardown) to `ai-agent-skills:repo-cleanup`, so the
plumbing lives in one place across all repos.

**Acting principle:** assess first, act on what's confident, escalate only on mixed signal —
substantive WIP, dep-file touches, abandoned-but-non-trivial work. Never auto-drop a stash on an OPEN
issue; never auto-discard outside the allowlist.

## Project facts

| Fact | Value |
|---|---|
| Repo | `{{REPO_SLUG}}` |
| Default branch | `{{DEFAULT_BRANCH}}` |
| `delete_branch_on_merge` | `{{DELETE_BRANCH_ON_MERGE}}` |
| Dep/version-file globs (block stash auto-drop) | {{DEP_VERSION_GLOBS}} |
| Extra noise allowlist (auto-discard) | {{NOISE_ALLOWLIST}} |
| Never-discard (precious, gitignored) | {{NEVER_DISCARD}} |
<!-- IF:CLAIM_LABEL -->
| Claim label to clear on shipped issues | `{{CLAIM_LABEL}}` |
<!-- ENDIF -->

## Run

Delegate the full reconciliation to the capability skill, passing the facts above:

```
Skill: ai-agent-skills:repo-cleanup
Args: "Reconcile {{REPO_SLUG}} post-shipping. default-branch={{DEFAULT_BRANCH}};
       delete-branch-on-merge={{DELETE_BRANCH_ON_MERGE}};
       dep-version-globs={{DEP_VERSION_GLOBS}};
       noise-allowlist={{NOISE_ALLOWLIST}};
       never-discard={{NEVER_DISCARD}}<!-- IF:CLAIM_LABEL -->;
       claim-label={{CLAIM_LABEL}}<!-- ENDIF -->.
       Inventory read-only first, then sync+prune, triage stashes, sweep untracked noise, tear down
       stale/detached worktrees, delete [gone] + squash-merged branches, mop up stale remote
       branches<!-- IF:CLAIM_LABEL -->, clear orphan claim labels<!-- ENDIF -->. Apply the assess-first / ask-on-mixed-signal principle."
```

If `ai-agent-skills:repo-cleanup` is not in your available skills, STOP and tell the user to install
the plugin (`claude plugin install ai-agent-skills`) — do not improvise the reconciliation from
memory (the `[gone]` grep trap and squash-merge `-D` are easy to get wrong and lose work).

<!-- BEGIN PROJECT-SPECIFIC: extra-cleanup -->
<!-- Repo-unique cleanup steps that repo-cleanup doesn't cover (extra label hygiene, cache dirs,
     vendored-artifact pruning, etc.) go here and survive template updates. -->
<!-- END PROJECT-SPECIFIC -->

## Guardrails

- Never delete a branch with an OPEN PR; never delete `{{DEFAULT_BRANCH}}` (local or remote).
- Never `--force` remove a worktree whose SHA isn't in `{{DEFAULT_BRANCH}}` without confirming.
- Never auto-drop a stash on an OPEN issue; `closedByPullRequestsReferences`, not bare issue state, is the "shipped" signal.
- Never auto-discard untracked files outside the allowlist or anything in the never-discard list.
- Don't disable `delete_branch_on_merge`; don't run inside a worktree you're about to remove.

<!-- BEGIN PROJECT-SPECIFIC: extra-guardrails -->
<!-- END PROJECT-SPECIFIC -->
