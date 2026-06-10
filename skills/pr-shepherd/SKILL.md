---
name: pr-shepherd
description: >
  This skill should be used when the user asks to "watch this PR and merge when green",
  "babysit the PRs", "poll PR checks", "auto-merge the green ones", "enqueue to the merge queue",
  "why is my PR stuck in the queue", "retry that flaky gh call", "clean up the worktrees after the batch",
  or any PR-lifecycle mechanics: mergeable checks, check polling, transient-failure retry,
  merge-queue vs direct merge, serialization of migration/codegen-coupled PRs, post-merge
  worktree teardown and branch reconcile. Also triggers when a project workflow skill
  (a generated take-it or send-it) invokes ai-agent-skills:pr-shepherd by name.
---

# PR Shepherd

PR lifecycle mechanics from "PR opened" to "merged and cleaned up": verify mergeable, watch checks, retry transient GitHub failures, merge (or enqueue) greens, serialize coupled PRs, tear down batch worktrees. Works in any GitHub repo; project workflow skills delegate here so the mechanics live in one place.

This skill does NOT decide *what* to merge — the caller (user or project skill) owns that. It also never auto-rebases a `CONFLICTING` PR; conflicts are surfaced for a human decision.

## Inputs to establish first

From the caller's request (ask if missing and not inferable):

1. **Repo** — `owner/name`, or infer from cwd.
2. **PR number(s)** — what to shepherd.
3. **Merge policy** — merge queue or direct merge. Project skills state this explicitly; otherwise detect (see `references/merge-queue.md`) and confirm a guess rather than acting on it.
4. **Coupled-PR concerns** — does the batch touch migrations / codegen / other derived artifacts? (See `references/serialization.md`.)
5. **Teardown scope** — worktree paths from a batch manifest, if the caller ran parallel sub-agents.

## Workflow

### 1. Mergeable check — always first

`CONFLICTING` silently blocks CI from firing ("no checks reported" looks identical to "CI hasn't started"). Check before any watch loop:

```bash
gh pr view "$PR" --repo "$REPO" --json mergeable,mergeStateStatus --jq '"\(.mergeable) \(.mergeStateStatus)"'
```

Surface `CONFLICTING` immediately — do not auto-rebase. For generated-file conflicts, point the caller at the regenerate-don't-hand-merge recipe in `references/serialization.md`.

### 2. Watch checks

Single PR, interactive: `gh pr checks "$PR" --watch --fail-fast`.

Multiple PRs (batch): use the bundled poller — read-only, polls every 60s, exits when all PRs are terminal, emits final JSON for the merge decision:

```bash
REPO="$REPO" bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/poll-prs.sh "$PR1" "$PR2"
```

Run it synchronously — backgrounding the watcher orphans PRs at "checks pending" with nobody deciding.

### 3. Merge or enqueue greens

Merge only PRs with **all checks green AND `mergeable=MERGEABLE` AND `mergeStateStatus=CLEAN`**. The command differs by regime — read `references/merge-queue.md` before this step; the queue's `--auto` method-flag trap silently never-merges:

- **Merge queue**: `gh pr merge "$PR" --auto` (NO method flag, NO `--delete-branch`), then confirm `isInMergeQueue:true` within ~30s and poll the queue entry until `MERGED` or ejected.
- **Direct**: `gh pr merge "$PR" --squash --delete-branch`.

Wrap every mutating `gh` call in the retry helper (502s, stuck "Merge already in progress" locks, transient GraphQL):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/gh-retry.sh -- pr merge "$PR" --repo "$REPO" --auto
```

If the batch contains coupled PRs (same migrations/codegen directories), follow `references/serialization.md`: under a queue with a gating freshness check, enqueue all and let the queue eject stale ones; without one, merge coupled PRs one at a time with a mergeable re-check between each.

For red PRs: do not merge; pull the failing job log (`gh run view <id> --log-failed | tail -50`) so the report names the failure.

### 4. Teardown and reconcile

After a batch with worktree-isolated sub-agents, read `references/worktree-teardown.md`, then:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/teardown.sh <wt_path...>   # or --sweep
```

Then reconcile the session (cwd back to repo root, switch to default branch, `git pull --ff-only`, delete local feature branches). Squash-merge repos: "remote branch gone" is the merged signal, never `git branch --merged`.

## Bundled scripts

| Script | Purpose |
|--------|---------|
| `scripts/poll-prs.sh` | Polls 1+ PRs every 60s until all terminal. Read-only. `REPO`, `POLL_INTERVAL`, `POLL_MAX_TICKS` env. Exit 124 on timeout. |
| `scripts/gh-retry.sh` | Exponential-backoff retry for mutating `gh` calls on transient failures (502/503/504, "Merge already in progress", transient GraphQL). Exit 124 on exhaustion so the caller decides best-effort vs escalate. |
| `scripts/teardown.sh` | Batch worktree cleanup: force-removes locked agent worktrees, deletes local branches, prunes, clears origin-identical stragglers, ff-reconciles the default branch. `--sweep` reclaims orphans whose remote branch is gone. Never drops stashes. `DEFAULT_BRANCH` env override. |

## Guardrails

- **Single-writer**: only the coordinating session merges/enqueues; sub-agents never do.
- **Never merge past a red check**; never auto-rebase `CONFLICTING`.
- **Never force-push the default branch.**
- Draft PRs: watch only; the author flips to ready.
- Board claims and issue edits via `gh-retry.sh` are best-effort — exit 124 means log and continue, not abort.
