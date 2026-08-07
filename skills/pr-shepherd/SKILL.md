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
6. **Stacked PRs** — is any PR a layer of a stack? Detected automatically by `scripts/stack-probe.sh`, never asked. (See `references/stacked-prs.md`.)

## Workflow

### 1. Mergeable check — always first

`CONFLICTING` silently blocks CI from firing ("no checks reported" looks identical to "CI hasn't started"). Check before any watch loop:

```bash
gh pr view "$PR" --repo "$REPO" --json mergeable,mergeStateStatus --jq '"\(.mergeable) \(.mergeStateStatus)"'
```

For more than one PR — or a "where does everything stand" probe — prefer the scripted snapshot over hand-rolled `--jq` variants; it reuses the poller's type-aware pending predicate and prints the same table + JSON as a watch tick:

```bash
REPO="$REPO" bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/poll-prs.sh --once "$PR"   # zero PR args = every open PR
```

Surface `CONFLICTING` immediately — do not auto-rebase. For generated-file conflicts, point the caller at the regenerate-don't-hand-merge recipe in `references/serialization.md`.

### 1b. Stack check — before any merge decision

A middle layer of a stacked PR reports green + `MERGEABLE` + `CLEAN` exactly like an ordinary PR, because its base *is* a real branch and there is no textual conflict. Merging on that reading lands an upper layer into a lower layer's branch while the bottom is still open. `merge-shepherd.sh` gates this automatically; when driving by hand, probe first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/stack-probe.sh "$PR" --repo "$REPO"
```

Exit `0` in a stack · `10` not stacked · `11` stacks unavailable in this repo · `1` error. A non-empty `lower_open` means **merge the layer below first**. Read `references/stacked-prs.md` before acting on a stack — in particular, why detection needs two probes and why a merge queue plus a stack is refused rather than guessed.

### 2. Watch checks

Single PR, interactive: `gh pr checks "$PR" --watch --fail-fast`.

Multiple PRs (batch): use the bundled poller — read-only, polls every 60s, exits when all PRs are terminal, emits final JSON for the merge decision:

```bash
REPO="$REPO" bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/poll-prs.sh "$PR1" "$PR2"
```

Run it synchronously — backgrounding the watcher orphans PRs at "checks pending" with nobody deciding. For a single no-wait snapshot (state reconciliation at the top of a loop tick, not a watch), use `--once` — exit `0` = all terminal, `11` = something still pending (same "re-run later" code as `merge-shepherd.sh`).

### 3. Merge or enqueue greens

Merge only PRs with **all checks green AND `mergeable=MERGEABLE` AND `mergeStateStatus=CLEAN`**. The command differs by regime — read `references/merge-queue.md` before this step; the queue's `--auto` method-flag trap silently never-merges.

**"All checks green" is not the same as "no red checks" — an empty rollup satisfies the second and not the first.** `CLEAN` means *nothing blocks the merge*, and a base branch with no required checks blocks nothing, so a PR with **zero** checks reports `CLEAN` and zero pending — indistinguishable from a fully green one. Two ways to land there, both real: an intermediate chained or stacked PR (its base is a feature branch, which carries no protection), or CI that simply has not started yet. Observed live on 2026-08-06, when an Actions outage left three chained PRs reading `CLEAN` with no checks at all.

`merge-shepherd.sh` gates this and exits `21`. It refuses only where the repo **demonstrably runs CI on pull requests** (`actions/runs?event=pull_request` reports a non-zero `total_count`), so repos with no CI by design are unaffected; `--allow-no-checks` overrides. Checking by hand, confirm the rollup is non-empty before trusting `CLEAN`:

```bash
gh pr view "$PR" --repo "$REPO" --json statusCheckRollup --jq '.statusCheckRollup | length'
```

**Preferred write path — the bundled step script.** `scripts/merge-shepherd.sh` drives one PR through the whole write step as a stateless, idempotent "advance one step" against live GitHub state: mergeable check → red/pending gate → enqueue `--auto` (or `--direct` squash-merge) → GraphQL `isInMergeQueue` confirmation → teardown + ff-only default-branch reconcile. Every invocation is short, so a session killed mid-merge (memory-pressured hosts reap idle long-lived loops) costs one re-run instead of an orphaned merge:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/merge-shepherd.sh "$PR" --repo "$REPO" [--direct] [--worktree "$WT"] [--watch 240]
```

Distinct exit codes let the caller loop "re-run until terminal" without parsing output: `0` merged (+teardown) · `10` enqueued · `11` waiting/in-flight (re-run) · `20` red checks · `21` no checks reported where this repo expects them (re-run) · `22` conflicting · `23` blocked by an open lower stack layer (re-run — it clears when the layer below lands) · `24` stack needs a human (a lower layer closed unmerged, or the repo runs a merge queue). Queue mode is the default (`--auto`, NO method flag, NO `--delete-branch`, GraphQL-only enqueue confirm); pass `--direct` for repos without a merge queue (`--squash --delete-branch`). It already encodes the guardrails — never merges past red (advisory failures also stop it), never auto-rebases `CONFLICTING`, wraps the merge call in `gh-retry.sh`.

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

For red PRs: do not merge; pull the failing logs so the report names the failure — the bundled script handles run-id extraction and non-Actions checks (Vercel-style StatusContexts have no fetchable log; it prints their link instead of erroring):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/pr-failure-log.sh "$PR" --repo "$REPO"
```

**Stale pre-fix check trap — verify the head SHA before counting a redispatch failure.** After a fix has been *requested* (a redispatch or resume message to a fix agent) but before it has been *pushed*, the PR's head is still the failed commit, so `mergeStateStatus`/`statusCheckRollup` keep reporting the old failing run — the PR reads red even though the fix is in flight. A naive "PR is red → attempt N failed" read parks shippable work. Before treating a red read as a failed fix attempt:

1. Record the PR's `headRefOid` whenever a failure is observed (`poll-prs.sh` prints it per tick and includes it in the final JSON — no extra API call needed).
2. On a later red read, compare the current `headRefOid` (or the failing run's `headSha`) to the recorded failed SHA.
3. **Same SHA → the fix has not landed yet.** Report "fix pending / in flight" and keep waiting — do NOT increment the attempt count, escalate, or park the PR.
4. **New SHA and still red → the fix pushed and failed.** Only now count the attempt and apply the caller's escalation policy.

Callers doing redispatch bookkeeping (e.g. a generated drain-it's "ONE redispatch with the failure context") must key attempt counts to head SHAs, never to bare "PR is red" reads.

### 4. Teardown and reconcile

After a batch with worktree-isolated sub-agents, read `references/worktree-teardown.md`, then:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/teardown.sh <wt_path...>   # or --sweep
```

Then reconcile the session (cwd back to repo root, switch to default branch, `git pull --ff-only`, delete local feature branches) — `teardown.sh --reconcile-only` runs exactly that reconcile (including clearing origin-identical untracked stragglers that block the ff) without touching any worktree or branch, and exits `1` when the ff fails so the caller sees it. Squash-merge repos: "remote branch gone" is the merged signal, never `git branch --merged`. Teardown also deletes each worktree's `worktree-agent-*` **isolation branch** — it never had an upstream, so it is never `[gone]` and would otherwise accumulate one orphan per merge (see the isolation-branch leak in `references/worktree-teardown.md`).

## Bundled scripts

| Script | Purpose |
|--------|---------|
| `scripts/poll-prs.sh` | Polls 1+ PRs every 60s until all terminal. Read-only. Surfaces `headRefOid` per tick and in the final JSON so callers can spot stale pre-fix runs before counting a redispatch failure. `--once` = single snapshot tick, no loop (zero PR args probes every open PR); exit 0 all-terminal / 11 pending. `REPO`, `POLL_INTERVAL`, `POLL_MAX_TICKS` env. Exit 124 on watch timeout. |
| `scripts/pr-failure-log.sh` | Names a red PR's failing checks and prints each one's `--log-failed` tail, labeled. Handles the run-id extraction from check links and prints non-Actions (StatusContext) checks as external links instead of erroring. Read-only. Exit 0 reported / 10 no failures / 1 a log fetch failed. |
| `scripts/merge-shepherd.sh` | The single WRITER: stateless, idempotent merge step for ONE PR — red/pending gate, empty-rollup gate (`CLEAN` + zero checks is not green; `--allow-no-checks` overrides), stacked-layer gate (never merges a layer with open lower layers), enqueue `--auto` (or `--direct` squash), GraphQL enqueue confirm, teardown + ff-only reconcile. Teardown also deletes the worktree's `worktree-agent-*` isolation branch (never the PR's own head branch — `--delete-branch`/`[gone]` owns that). Re-run after any kill; bounded `--watch N` mode. Exit codes 0/10/11/20/21/22/23/24. `DEFAULT_BRANCH` / `ISOLATION_BRANCH_PREFIX` env (same contract as `teardown.sh`). |
| `scripts/poll-queue.sh` | Queue-phase companion to `poll-prs.sh`: polls 1+ enqueued PRs' merge-queue state (GraphQL) until each is `MERGED`, ejected, or closed without merge. `OPEN` + `isInMergeQueue:false` is disambiguated via the last `RemovedFromMergeQueueEvent`: reason `merged` reports `merged` (the PR-state flip lags the queue-entry removal); any other reason — or no removal event (never enqueued) — reports `ejected`, loudly. Read-only — never re-enqueues or recovers. Same env/contract: `REPO`, `POLL_INTERVAL`, `POLL_MAX_TICKS`, exit 124 on timeout, final JSON on stdout. |
| `scripts/stack-probe.sh` | The single stacked-PR detection primitive: REST `GET /repos/{o}/{n}/stacks` for repo availability + GraphQL `PullRequest.stack` for membership (both are needed — GraphQL `null` cannot distinguish "repo not enabled" from "PR not stacked"). Emits `position`, `entries[]` bottom→top, and the derived `lower_open` / `lower_closed_unmerged` the merge gate reads. Read-only. Exit 0 in a stack / 10 not stacked / 11 stacks unavailable / 1 error. |
| `scripts/gh-retry.sh` | Exponential-backoff retry for mutating `gh` calls on transient failures (502/503/504, "Merge already in progress", transient GraphQL). Exit 124 on exhaustion so the caller decides best-effort vs escalate. |
| `scripts/teardown.sh` | Batch worktree cleanup: force-removes locked agent worktrees, deletes local branches + their `worktree-agent-*` isolation branches, prunes, clears origin-identical stragglers, ff-reconciles the default branch. `--sweep` reclaims orphans whose remote branch is gone AND sweeps orphan isolation branches whose worktree is gone (ancestry OR merged-PR classification; unmerged ones surfaced, live ones untouched). `--reconcile-only` runs just the default-branch reconcile + residual report (exit 1 if the ff fails). Never drops stashes. `DEFAULT_BRANCH` / `ISOLATION_BRANCH_PREFIX` env override. |

## Guardrails

- **Single-writer**: only the coordinating session merges/enqueues; sub-agents never do. One owner per PR — never point `merge-shepherd.sh` and a watcher session (or two writers) at the same PR from different sessions.
- **Never merge past a red check**; never auto-rebase `CONFLICTING`.
- **Never read an empty check rollup as green.** `CLEAN` + zero pending is also what "no checks ran at all" looks like — count the rollup, don't just check for failures.
- **Never merge a stack layer while a lower layer is open.** Stacks merge bottom-up; `CLEAN` on a middle layer is truthful and says nothing about ordering. A stack under a merge queue is refused outright, not guessed at (`references/stacked-prs.md`).
- **Never treat an inconclusive stack probe as "not stacked."** Unknown means wait and re-run, not merge.
- **Never count a red PR as a failed fix attempt on a stale head** — confirm the failing run's head SHA is newer than the previously-failed one first (see the stale pre-fix check trap in §3).
- **Never force-push the default branch.**
- Draft PRs: watch only; the author flips to ready.
- Board claims and issue edits via `gh-retry.sh` are best-effort — exit 124 means log and continue, not abort.
