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

Merge only PRs with **all checks green AND `mergeable=MERGEABLE` AND `mergeStateStatus=CLEAN`**. The command differs by regime — read `references/merge-queue.md` before this step; the queue's `--auto` method-flag trap silently never-merges.

**Preferred write path — the bundled step script.** `scripts/merge-shepherd.sh` drives one PR through the whole write step as a stateless, idempotent "advance one step" against live GitHub state: mergeable check → red/pending gate → enqueue `--auto` (or `--direct` squash-merge) → GraphQL `isInMergeQueue` confirmation → teardown + ff-only default-branch reconcile. Every invocation is short, so a session killed mid-merge (memory-pressured hosts reap idle long-lived loops) costs one re-run instead of an orphaned merge:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/merge-shepherd.sh "$PR" --repo "$REPO" [--direct] [--worktree "$WT"] [--watch 240]
```

Distinct exit codes let the caller loop "re-run until terminal" without parsing output: `0` merged (+teardown) · `10` enqueued · `11` waiting/in-flight (re-run) · `20` red checks · `22` conflicting. Queue mode is the default (`--auto`, NO method flag, NO `--delete-branch`, GraphQL-only enqueue confirm); pass `--direct` for repos without a merge queue (`--squash --delete-branch`). It already encodes the guardrails — never merges past red (advisory failures also stop it), never auto-rebases `CONFLICTING`, wraps the merge call in `gh-retry.sh`.

**Stateless-eject caveat**: a stateless pass cannot distinguish "the queue ejected it" from "never enqueued" (head-commit checks stay green either way), so an ejected-but-`CLEAN` PR is simply re-enqueued on the next pass — the right recovery for transient ejects. A PR that keeps failing `merge_group` checks on the rebased ref will ping-pong enqueued→waiting; if repeated runs alternate like that, stop re-running, watch with `poll-queue.sh` (eject-aware), and follow "Eject recovery" in `references/merge-queue.md`.

Or drive the steps by hand:

- **Merge queue**: `gh pr merge "$PR" --auto` (NO method flag, NO `--delete-branch`), then confirm `isInMergeQueue:true` within ~30s (`isInMergeQueue` is GraphQL-only — `gh pr view --json isInMergeQueue` fails with `Unknown JSON field`; use the ready-made query in `references/merge-queue.md`, don't improvise). Then watch the queue with the bundled poller — read-only, terminal on `MERGED`, ejected, or closed-without-merge — instead of hand-rolling a loop (improvised loops miss the eject state):

  ```bash
  REPO="$REPO" bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/poll-queue.sh "$PR1" "$PR2"
  ```

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
| `scripts/merge-shepherd.sh` | The single WRITER: stateless, idempotent merge step for ONE PR — red/pending gate, enqueue `--auto` (or `--direct` squash), GraphQL enqueue confirm, teardown + ff-only reconcile. Re-run after any kill; bounded `--watch N` mode. Exit codes 0/10/11/20/22. `DEFAULT_BRANCH` env (same contract as `teardown.sh`). |
| `scripts/poll-queue.sh` | Queue-phase companion to `poll-prs.sh`: polls 1+ enqueued PRs' merge-queue state (GraphQL) until each is `MERGED`, ejected (`OPEN` + `isInMergeQueue:false`, reported loudly), or closed without merge. Read-only — never re-enqueues or recovers. Same env/contract: `REPO`, `POLL_INTERVAL`, `POLL_MAX_TICKS`, exit 124 on timeout, final JSON on stdout. |
| `scripts/gh-retry.sh` | Exponential-backoff retry for mutating `gh` calls on transient failures (502/503/504, "Merge already in progress", transient GraphQL). Exit 124 on exhaustion so the caller decides best-effort vs escalate. |
| `scripts/teardown.sh` | Batch worktree cleanup: force-removes locked agent worktrees, deletes local branches, prunes, clears origin-identical stragglers, ff-reconciles the default branch. `--sweep` reclaims orphans whose remote branch is gone. Never drops stashes. `DEFAULT_BRANCH` env override. |

## Guardrails

- **Single-writer**: only the coordinating session merges/enqueues; sub-agents never do. One owner per PR — never point `merge-shepherd.sh` and a watcher session (or two writers) at the same PR from different sessions.
- **Never merge past a red check**; never auto-rebase `CONFLICTING`.
- **Never force-push the default branch.**
- Draft PRs: watch only; the author flips to ready.
- Board claims and issue edits via `gh-retry.sh` are best-effort — exit 124 means log and continue, not abort.
