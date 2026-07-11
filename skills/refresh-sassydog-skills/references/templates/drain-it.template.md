<!--
TEMPLATE: drain-it · version 5
Render rules: see plate-it.template.md header. Same conventions.
REQUIRES: take-it generated in the same repo (drain-it reuses take-it's dispatch mechanics
verbatim). Board-optional: IF:BOARD true renders board-backed state (Ready column, In
progress/In review); IF:BOARD false renders the boardless degraded-board contract (queue =
`ready` label, in-flight = assignee @me + `in-progress` label, demotion = strip labels +
`blocked` + comment).
-->
---

name: drain-it
description: >
  Loop-driven dispatcher for {{PROJECT_NAME}}: each invocation is one idempotent tick that
  reconciles in-flight PRs, then tops the pipeline back up to {{MAX_IN_FLIGHT}} concurrent
  issues pulled ONLY from <!-- IF:BOARD -->the board's Ready column<!-- ELSE -->open issues carrying the `ready` label<!-- ENDIF -->, respecting dependencies and
  migration/codegen sequencing, until Ready is empty. Designed to run under
  "/loop 5m /drain-it" but a single manual invocation is also valid. Use when the user says
  "drain it", "drain the backlog", "work through Ready", "keep shipping until Ready is empty",
  or invokes it via /loop. {{PROJECT_NAME}}-specific
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: drain-it | template-version: 5 -->

# {{PROJECT_NAME}} Drain-It

One invocation = **one tick** of a drain loop. All state lives in GitHub (<!-- IF:BOARD -->board status<!-- ELSE -->labels<!-- ENDIF -->, assignees, PRs, branches) — never in conversation memory, because under `/loop` each tick may run with no recollection of the previous one. The contract with fill-it: **drain-it pulls exclusively from Ready** (<!-- IF:BOARD -->the board's Ready column<!-- ELSE -->the `ready` label<!-- ENDIF -->) and trusts that Ready means dispatchable; anything that smells undispatchable gets bounced back, never patched up inline.

## 1. Reconcile in-flight (always first)

Find work this loop already started. <!-- IF:BOARD -->**The board snapshot is the source of truth**: cards in **In progress** / **In review** with assignee @me are in-flight<!-- ELSE -->**Live issue state is the source of truth**: open issues with assignee @me AND the `in-progress` label are in-flight (`gh issue list --repo {{REPO_SLUG}} --state open --assignee @me --label in-progress`)<!-- ENDIF --> — whether or not a PR exists yet (a sub-agent mid-implementation has only a `*/issue-N-*` branch; PR-based queries undercount and overshoot the cap).

- Open PRs from those branches → delegate to `ai-agent-skills:pr-shepherd`: mergeable check, merge greens (<!-- IF:MERGE_QUEUE -->merge queue: `gh pr merge --auto`, no method flag, no `--delete-branch`, confirm `isInMergeQueue` via GraphQL<!-- ELSE -->direct: `--squash --delete-branch`<!-- ENDIF -->), tear down worktrees for merged PRs, reconcile local {{DEFAULT_BRANCH}}.
- **Failed/red PRs**: surface in the tick report with the failing check named. Comment `drain-it: attempt 1 failed — <check>: <one-line cause>` on the issue. ONE redispatch with the failure context added to the prompt is allowed on a later tick; a second failure <!-- IF:BOARD -->moves the card back to **Backlog** with a `blocked` label and a comment<!-- ELSE -->strips the claim and adds `blocked` plus a comment (`gh issue edit N --repo {{REPO_SLUG}} --remove-label ready --remove-label in-progress --add-label blocked`)<!-- ENDIF --> — a human (or fill-it, after the human weighs in) decides next. Never park failures in Ready: Ready must stay synonymous with dispatchable.
- **`CONFLICTING` PRs**: never auto-rebase; surface and hold.

## 2. Compute capacity

`in-flight` = <!-- IF:BOARD -->cards in In progress/In review claimed by this loop (claim = assignee @me + board status)<!-- ELSE -->open issues claimed by this loop (claim = assignee @me + `in-progress` label)<!-- ENDIF -->. **Capacity = {{MAX_IN_FLIGHT}} − in-flight.** A green PR sitting in the merge queue still counts as in-flight until it is actually MERGED — compute capacity from post-reconcile live state and accept that a queue-pending slot frees up next tick, not this one. Capacity ≤ 0 → emit the tick report and stop; the next tick tops up.

## 3. Select from Ready — and only Ready

<!-- IF:BOARD -->
Snapshot board {{BOARD_NUMBER}} via `ai-agent-skills:github-issues`; take the **Ready** column in board order (board order = priority). Filter, in order:
<!-- ELSE -->
Query the queue: `gh issue list --repo {{REPO_SLUG}} --state open --label ready --json number,title,labels,assignees`, ordered by **issue number ascending** (oldest first); when the repo defines priority labels, issues carrying them sort ahead — the boardless stand-in for "board order = priority". Filter, in order:
<!-- ENDIF -->

| Filter | Rule |
|--------|------|
| Claimed | Skip if assignee set or <!-- IF:BOARD -->status ≠ Ready<!-- ELSE -->`in-progress` label present<!-- ENDIF --> (another session got it) |
| Blocked | Skip `blocked` label |
| Dependencies | Skip while any literal `Depends on #N` references an issue that is not CLOSED — re-eligible automatically once the dep merges |
| Collision | Skip if the issue's `touches:` set intersects any **in-flight** issue's `touches:` set. Read each in-flight issue's `touches:` line (the in-flight set is known from §1) and intersect: same repo-relative path, or a glob on one side matching a path on the other. Defer to a later tick — re-eligible automatically once the overlapping issue merges (its slot frees, its files unlock). An issue with **no** `touches:` line is treated as intersecting nothing (fill-it left it unannotated), but is flagged `unannotated` in the tick report so the coupling gap is visible, not silently risky. |
| Smell test | Run take-it's pre-flight smell test (research-shaped titles, open-question sections, stub bodies). Failures: comment why + <!-- IF:BOARD -->move the card back to Backlog<!-- ELSE -->remove the `ready` label<!-- ENDIF --> for fill-it. Never "fix it up" inline — that hides the grooming gap. |

<!-- IF:MIGRATIONS -->
Additional filter — **migration serialization**: at most ONE issue touching {{MIGRATION_DIRS}} in flight at a time (in-flight included); hold the rest in Ready.
<!-- ENDIF -->
<!-- IF:CODEGEN -->
Additional filter — **codegen coupling**: codegen-coupled issues may run in parallel, but flag them to pr-shepherd so their merges serialize.
<!-- ENDIF -->

Take the first `capacity` survivors. The Collision filter is the primary defense against concurrent file-overlapping dispatch; `ai-agent-skills:pr-shepherd`'s coupled-PR serialization (`references/serialization.md`) stays the **fallback** for overlaps this filter can't see — chiefly `unannotated` issues that turn out to collide at merge time.

## 4. Dispatch

Use take-it's mechanics verbatim (claim → fast-forward local {{DEFAULT_BRANCH}} → one sub-agent per issue, `isolation: "worktree"`, single message, batch manifest in `.git/drain-it-batch.json`, take-it's self-contained sub-agent prompt). The reused prompt carries take-it's shared-state isolation rules — worktree confinement, never `git stash`, never an editable/dev install into a shared interpreter or global store (Python: `pip install -e` repoints imports for every parallel agent; in-worktree venv or `PYTHONPATH` instead) — keep them intact when appending failure context for a §1 redispatch.

**Model policy: pass `model: "opus"` on every dispatched Agent call.** The alias resolves to the latest Opus (4.8 today). Implementation work runs on Opus because it is the cheaper tier relative to the coordinator's session model — only this coordinator tick stays on the session model. Do not silently change the sub-agent model in either direction.

Sub-agents NEVER merge (single-writer: merges happen in §1 of a tick).

## 5. Tick report (terse — this prints every few minutes under /loop)

```
DRAIN TICK — in-flight 3/{{MAX_IN_FLIGHT}} | merged this tick: #1712 | dispatched: #1707 #1711 | Ready remaining: 4
holds: #1713 (Depends on #1717, still open) · #1708 (migration slot busy) · #1709 (touches overlaps in-flight #1707)
unannotated (dispatched without a touches set — coupling unchecked): #1711
```

Plus one line per failure with its next action. Drop the `unannotated` line on ticks that dispatch nothing unannotated.

## 6. Drain complete

<!-- IF:BOARD -->Ready column empty<!-- ELSE -->Zero open issues with the `ready` label<!-- ENDIF --> AND in-flight zero, **confirmed from live GitHub state read this tick** (the §1 reconcile + §3 <!-- IF:BOARD -->snapshot<!-- ELSE -->query<!-- ENDIF --> — never a stale or transient read) → announce loudly:

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

Safety rails: self-cancel ONLY on the confirmed complete state above. Anything still <!-- IF:BOARD -->In progress/In review<!-- ELSE -->claimed (assignee @me + `in-progress`)<!-- ENDIF -->, an open PR (in-flight until actually MERGED, per §2), or <!-- IF:BOARD -->a non-empty Ready column<!-- ELSE -->any open issue still labeled `ready`<!-- ENDIF --> means the drain is not complete and the loop stays alive. If live state could not be verified this tick (e.g. API failure mid-tick), leave the cron alone — the next tick re-checks. Ticks that fire between completion and cancellation are no-ops, not errors: each one re-runs this section and retries the self-cancel.

## Guardrails

- **Ready only.** <!-- IF:BOARD -->Backlog items<!-- ELSE -->Issues not labeled `ready`<!-- ENDIF --> are fill-it's job — drain-it never promotes, never grooms, never files issues.
- **Hard cap {{MAX_IN_FLIGHT}} in flight**, counting carry-over from previous ticks, not just this tick's dispatches.
- **Idempotent ticks**: every action re-checks live GitHub state first; a crashed tick must be safely re-runnable (worktrees reclaimable via the batch manifest).
- **Single-writer**: only the coordinator merges/enqueues; max one redispatch per issue without a human.
- If `ai-agent-skills:pr-shepherd` or take-it is missing, STOP and say so — do not improvise dispatch or merge mechanics.

<!-- BEGIN PROJECT-SPECIFIC: extra-sequencing -->
<!-- END PROJECT-SPECIFIC -->
