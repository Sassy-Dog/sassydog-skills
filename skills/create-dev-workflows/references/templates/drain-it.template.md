<!--
TEMPLATE: drain-it · version 3
Render rules: see plate-it.template.md header. Same conventions.
REQUIRES: a ProjectV2 board with a Ready column (IF:BOARD must be true) AND take-it generated
in the same repo (drain-it reuses take-it's dispatch mechanics verbatim).
-->
---

name: drain-it
description: >
  Loop-driven dispatcher for {{PROJECT_NAME}}: each invocation is one idempotent tick that
  reconciles in-flight PRs, then tops the pipeline back up to {{MAX_IN_FLIGHT}} concurrent
  issues pulled ONLY from the board's Ready column, respecting dependencies and
  migration/codegen sequencing, until Ready is empty. Designed to run under
  "/loop 5m /drain-it" but a single manual invocation is also valid. Use when the user says
  "drain it", "drain the backlog", "work through Ready", "keep shipping until Ready is empty",
  or invokes it via /loop. {{PROJECT_NAME}}-specific
---

<!-- generated-by: ai-agent-skills:create-dev-workflows | template: drain-it | template-version: 3 -->

# {{PROJECT_NAME}} Drain-It

One invocation = **one tick** of a drain loop. All state lives in GitHub (board status, assignees, PRs, branches) — never in conversation memory, because under `/loop` each tick may run with no recollection of the previous one. The contract with fill-it: **drain-it pulls exclusively from Ready** and trusts that Ready means dispatchable; anything that smells undispatchable gets bounced back, never patched up inline.

## 1. Reconcile in-flight (always first)

Find work this loop already started. **The board snapshot is the source of truth**: cards in **In progress** / **In review** with assignee @me are in-flight — whether or not a PR exists yet (a sub-agent mid-implementation has only a `*/issue-N-*` branch; PR-based queries undercount and overshoot the cap).

- Open PRs from those branches → delegate to `ai-agent-skills:pr-shepherd`: mergeable check, merge greens (<!-- IF:MERGE_QUEUE -->merge queue: `gh pr merge --auto`, no method flag, no `--delete-branch`, confirm `isInMergeQueue` via GraphQL<!-- ELSE -->direct: `--squash --delete-branch`<!-- ENDIF -->), tear down worktrees for merged PRs, reconcile local {{DEFAULT_BRANCH}}.
- **Failed/red PRs**: surface in the tick report with the failing check named. Comment `drain-it: attempt 1 failed — <check>: <one-line cause>` on the issue. ONE redispatch with the failure context added to the prompt is allowed on a later tick; a second failure moves the card back to **Backlog** with a `blocked` label and a comment — a human (or fill-it, after the human weighs in) decides next. Never park failures in Ready: Ready must stay synonymous with dispatchable.
- **`CONFLICTING` PRs**: never auto-rebase; surface and hold.

## 2. Compute capacity

`in-flight` = cards in In progress/In review claimed by this loop (claim = assignee @me<!-- IF:BOARD --> + board status<!-- ENDIF -->). **Capacity = {{MAX_IN_FLIGHT}} − in-flight.** A green PR sitting in the merge queue still counts as in-flight until it is actually MERGED — compute capacity from post-reconcile live state and accept that a queue-pending slot frees up next tick, not this one. Capacity ≤ 0 → emit the tick report and stop; the next tick tops up.

## 3. Select from Ready — and only Ready

Snapshot board {{BOARD_NUMBER}} via `ai-agent-skills:github-issues`; take the **Ready** column in board order (board order = priority). Filter, in order:

| Filter | Rule |
|--------|------|
| Claimed | Skip if assignee set or status ≠ Ready (another session got it) |
| Blocked | Skip `blocked` label |
| Dependencies | Skip while any literal `Depends on #N` references an issue that is not CLOSED — re-eligible automatically once the dep merges |
| Smell test | Run take-it's pre-flight smell test (research-shaped titles, open-question sections, stub bodies). Failures: comment why + move the card back to Backlog for fill-it. Never "fix it up" inline — that hides the grooming gap. |

<!-- IF:MIGRATIONS -->
Additional filter — **migration serialization**: at most ONE issue touching {{MIGRATION_DIRS}} in flight at a time (in-flight included); hold the rest in Ready.
<!-- ENDIF -->
<!-- IF:CODEGEN -->
Additional filter — **codegen coupling**: codegen-coupled issues may run in parallel, but flag them to pr-shepherd so their merges serialize.
<!-- ENDIF -->

Take the first `capacity` survivors.

## 4. Dispatch

Use take-it's mechanics verbatim (claim → fast-forward local {{DEFAULT_BRANCH}} → one sub-agent per issue, `isolation: "worktree"`, single message, batch manifest in `.git/drain-it-batch.json`, take-it's self-contained sub-agent prompt). The reused prompt carries take-it's shared-state isolation rules — worktree confinement, never `git stash`, never an editable/dev install into a shared interpreter or global store (Python: `pip install -e` repoints imports for every parallel agent; in-worktree venv or `PYTHONPATH` instead) — keep them intact when appending failure context for a §1 redispatch.

**Model policy: pass `model: "opus"` on every dispatched Agent call.** The alias resolves to the latest Opus (4.8 today). Implementation work runs on Opus because it is the cheaper tier relative to the coordinator's session model — only this coordinator tick stays on the session model. Do not silently change the sub-agent model in either direction.

Sub-agents NEVER merge (single-writer: merges happen in §1 of a tick).

## 5. Tick report (terse — this prints every few minutes under /loop)

```
DRAIN TICK — in-flight 3/{{MAX_IN_FLIGHT}} | merged this tick: #1712 | dispatched: #1707 #1711 | Ready remaining: 4
holds: #1713 (Depends on #1717, still open) · #1708 (migration slot busy)
```

Plus one line per failure with its next action.

## 6. Drain complete

Ready empty AND in-flight zero, **confirmed from live GitHub state read this tick** (the §1 reconcile + §3 snapshot — never a stale or transient read) → announce loudly:

```
DRAIN COMPLETE — Ready is empty and nothing is in flight.
```

Then stop the loop yourself, according to how this tick was invoked — three modes:

| Mode | Recognize it by | Stop path |
|------|-----------------|-----------|
| **Self-paced loop** (ScheduleWakeup) | This tick was woken by a wake-up the previous tick scheduled | Do not schedule another wake-up — the loop ends here |
| **Cron / fixed interval** (`/loop <interval> /drain-it`, CronCreate-backed) | A cron job fires the skill on a schedule | **Self-cancel the cron** — see below. Do not merely advise the user to cancel; act |
| **Manual invocation** | No loop context | Nothing to cancel — announce and finish |

**Cron self-cancel.** The skill must find the loop's job id itself: run `CronList` and select the job whose `prompt` is this drain-it invocation (`/drain-it` or the skill invoked by name).

- **Exactly one match** → `CronDelete <id>`, then append to the report: `Loop <id> cancelled — run fill-it to refill Ready and start a new drain when there's more to ship.`
- **Zero, multiple, or ambiguous matches** (several drain-it crons; a prompt that only mentions drain-it among other work) → delete NOTHING. Fall back to announcing completion, listing the candidate ids, and telling the user to `CronDelete` the right one — deleting the wrong job is worse than a few extra no-op ticks.

Safety rails: self-cancel ONLY on the confirmed complete state above. Anything still In progress/In review, an open PR (in-flight until actually MERGED, per §2), or a non-empty Ready means the drain is not complete and the loop stays alive. If live state could not be verified this tick (e.g. API failure mid-tick), leave the cron alone — the next tick re-checks. Ticks that fire between completion and cancellation are no-ops, not errors: each one re-runs this section and retries the self-cancel.

## Guardrails

- **Ready only.** Backlog items are fill-it's job — drain-it never promotes, never grooms, never files issues.
- **Hard cap {{MAX_IN_FLIGHT}} in flight**, counting carry-over from previous ticks, not just this tick's dispatches.
- **Idempotent ticks**: every action re-checks live GitHub state first; a crashed tick must be safely re-runnable (worktrees reclaimable via the batch manifest).
- **Single-writer**: only the coordinator merges/enqueues; max one redispatch per issue without a human.
- If `ai-agent-skills:pr-shepherd` or take-it is missing, STOP and say so — do not improvise dispatch or merge mechanics.

<!-- BEGIN PROJECT-SPECIFIC: extra-sequencing -->
<!-- END PROJECT-SPECIFIC -->
