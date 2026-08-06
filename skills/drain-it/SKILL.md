---
name: drain-it
description: >
  Loop-driven dispatcher: each invocation is one idempotent tick that reconciles in-flight PRs,
  then tops the pipeline back up to the configured concurrency limit, pulling ONLY from issues
  marked Ready, respecting dependencies and migration/codegen sequencing, until Ready is empty.
  Designed to run under "/loop 5m /drain-it" but a single manual invocation is also valid. Use when
  the user says "drain it", "drain the backlog", "work through Ready", "keep shipping until Ready
  is empty", or invokes it via /loop. Reads the current repo's settings from
  `.claude/sassy-dog/drain-it.md`.
---

# Drain-It

One invocation = **one tick** of a drain loop.

All state lives in GitHub — status, assignees, PRs, branches — never in conversation memory,
because under `/loop` each tick may run with no recollection of the previous one. The contract with
groom-it: **drain-it pulls exclusively from Ready** and trusts that Ready means dispatchable.
Anything that smells undispatchable gets bounced back, never patched up inline.

## 1. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/drain-it.md" 2>/dev/null || echo "NO_CONFIG"`

Frontmatter supplies `max_in_flight` and the optional `board`, `migrations`, `codegen`, and
`merge_queue` keys. Contract: `ai-agent-skills:refresh-skills` →
`references/config-contract.md`.

**If it reads `NO_CONFIG`**, STOP. Drain-it dispatches sub-agents and merges PRs unattended, on a
loop — running it against an unconfigured repo means guessing a concurrency cap and skipping
migration serialization while nobody is watching. Tell the user to run
`ai-agent-skills:refresh-skills` first.

## 2. Reconcile in-flight (always first)

Find work this loop already started.

**With `board:`** — the board snapshot is the source of truth: cards in **In progress** / **In
review** with assignee @me are in-flight.

**Without a board** — live issue state is the source of truth. Snapshot the queue via
`ai-agent-skills:github-issues`' `queue-snapshot.sh` — one call returns `ready[]`, `in_flight[]`,
and `blocked[]` with the `touches:` and `Depends on #N` body contracts already parsed. In-flight is
`in_flight[]` entries with `mine: true`.

Either way, in-flight counts whether or not a PR exists yet: a sub-agent mid-implementation has
only a `*/issue-N-*` branch, and PR-based queries undercount, which overshoots the cap.

- **Open PRs from those branches** → delegate to `ai-agent-skills:pr-shepherd`: mergeable check,
  merge greens per the configured merge policy, tear down worktrees for merged PRs, reconcile the
  local default branch.
- **Failed or red PRs** → surface in the tick report with the failing check named, and comment
  `drain-it: attempt 1 failed — <check>: <one-line cause>` on the issue. ONE redispatch with the
  failure context appended is allowed on a later tick. A second failure demotes to blocked — via
  the board plus a `blocked` label, or `issue-claim.sh block N --comment "drain-it: 2 failed
  attempts — <cause>"` — and a human decides next. **Never park failures in Ready**: Ready must
  stay synonymous with dispatchable.
- **`CONFLICTING` PRs** → never auto-rebase; surface and hold.

## 3. Compute capacity

In-flight is the set of issues claimed by this loop — assignee @me plus board status or the
`in-progress` label. **Capacity = `max_in_flight` − in-flight.**

A green PR sitting in the merge queue still counts as in-flight until it is actually MERGED.
Compute capacity from post-reconcile live state and accept that a queue-pending slot frees up next
tick, not this one. Capacity ≤ 0 → emit the tick report and stop; the next tick tops up.

## 4. Select from Ready — and only Ready

**With `board:`** — take the **Ready** column in board order, since board order is priority.

**Without a board** — take `ready[]` from the §2 snapshot, already ordered issue-number ascending
(oldest first). When the repo defines priority labels, issues carrying them sort ahead; that's the
boardless stand-in for "board order = priority".

Filter, in order:

| Filter | Rule |
| --- | --- |
| Claimed | Skip if assignee set, or status ≠ Ready / `in-progress` label present — another session got it |
| Blocked | Skip the `blocked` label |
| Dependencies | Skip while any literal `Depends on #N` references an issue that is not CLOSED — re-eligible automatically once the dep merges |
| Collision | Skip if the issue's `touches:` set intersects any **in-flight** issue's `touches:` set — same repo-relative path, or a glob on one side matching a path on the other. Defer to a later tick; re-eligible once the overlapping issue merges. An issue with **no** `touches:` line intersects nothing, but is flagged `unannotated` in the tick report so the coupling gap is visible rather than silently risky. |
| Smell test | Run take-it's pre-flight smell test — research-shaped titles, open-question sections, stub bodies. Failures bounce back to groom-it with a required comment. Never "fix it up" inline; that hides the grooming gap. |

**If `migrations:` is configured** — additional filter: at most ONE issue touching
`migrations.dirs` in flight at a time, in-flight included. Hold the rest in Ready.

**If `codegen:` is configured** — additional filter: codegen-coupled issues may run in parallel,
but flag them to pr-shepherd so their merges serialize.

Take the first `capacity` survivors. The Collision filter is the primary defense against concurrent
file-overlapping dispatch; `ai-agent-skills:pr-shepherd`'s coupled-PR serialization
(`references/serialization.md`) stays the **fallback** for overlaps this filter cannot see —
chiefly `unannotated` issues that turn out to collide at merge time.

## 5. Dispatch

Use take-it's mechanics verbatim: claim → fast-forward the local default branch → one sub-agent per
issue, `isolation: "worktree"`, single message, batch manifest in `.git/drain-it-batch.json`,
take-it's self-contained sub-agent prompt.

The reused prompt carries take-it's shared-state isolation rules — worktree confinement, never
`git stash`, never an editable or dev install into a shared interpreter or global store. Keep them
intact when appending failure context for a §2 redispatch.

**Model policy: pass `model: "opus"` on every dispatched Agent call.** Implementation work runs on
Opus because it is the cheaper tier relative to the coordinator's session model — only this
coordinator tick stays on the session model. Do not silently change the sub-agent model in either
direction.

Sub-agents NEVER merge. Single-writer: merges happen in §2 of a tick.

## 6. Tick report

Terse — this prints every few minutes under `/loop`:

```text
DRAIN TICK — in-flight 3/5 | merged this tick: #1712 | dispatched: #1707 #1711 | Ready remaining: 4
holds: #1713 (Depends on #1717, still open) · #1708 (migration slot busy) · #1709 (touches overlaps in-flight #1707)
unannotated (dispatched without a touches set — coupling unchecked): #1711
```

Plus one line per failure with its next action. Drop the `unannotated` line on ticks that dispatch
nothing unannotated.

## 7. Drain complete

Ready empty AND in-flight zero, **confirmed from live GitHub state read this tick** — the §2
reconcile plus the §4 read, never a stale or transient one → announce loudly:

```text
DRAIN COMPLETE — Ready is empty and nothing is in flight.
```

Then stop the loop yourself, according to how this tick was invoked:

| Mode | Recognize it by | Stop path |
| --- | --- | --- |
| **Self-paced loop** (ScheduleWakeup) | This tick was woken by a wake-up the previous tick scheduled | Do not schedule another wake-up — the loop ends here |
| **Cron / fixed interval** (CronCreate-backed) | A cron job fires the skill on a schedule | **Self-cancel the cron** — see below. Do not merely advise the user to cancel; act |
| **Manual invocation** | No loop context | Nothing to cancel — announce and finish |

**Cron self-cancel.** Find the loop's job id yourself: run `CronList` and select the job whose
prompt is this drain-it invocation.

- **Exactly one match** → `CronDelete <id>`, then append to the report: `Loop <id> cancelled — run
  groom-it to refill Ready and start a new drain when there's more to ship.`
- **Zero, multiple, or ambiguous matches** → delete NOTHING. Announce completion, list the
  candidate ids, and tell the user to `CronDelete` the right one. Deleting the wrong job is worse
  than a few extra no-op ticks.

Safety rails: self-cancel ONLY on the confirmed complete state above. Anything still claimed, an
open PR (in-flight until actually MERGED, per §3), or any issue still in Ready means the drain is
not complete and the loop stays alive. If live state could not be verified this tick — an API
failure mid-tick — leave the cron alone; the next tick re-checks. Ticks that fire between
completion and cancellation are no-ops, not errors: each re-runs this section and retries.

## Guardrails

- **Ready only.** Everything else is groom-it's job — drain-it never promotes, never grooms, never
  files issues.
- **Hard cap `max_in_flight`**, counting carry-over from previous ticks, not just this tick's
  dispatches.
- **Idempotent ticks**: every action re-checks live GitHub state first; a crashed tick must be
  safely re-runnable, with worktrees reclaimable via the batch manifest.
- **Single-writer**: only the coordinator merges or enqueues; max one redispatch per issue without
  a human.
- If `ai-agent-skills:pr-shepherd` or take-it is missing, STOP and say so — do not improvise
  dispatch or merge mechanics.

Apply any `## extra-sequencing` section from config as additional §4 filters.
