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

Frontmatter supplies `max_in_flight` and the optional `board`, `migrations`, `codegen`,
`merge_queue`, and `stacked_prs` keys. Contract: `ai-agent-skills:refresh-skills` →
`references/config-contract.md`.

**If it reads `NO_CONFIG`**, STOP. Drain-it dispatches sub-agents and merges PRs unattended, on a
loop — running it against an unconfigured repo means guessing a concurrency cap and skipping
migration serialization while nobody is watching. Tell the user to run
`ai-agent-skills:refresh-skills` first.

### Offer to set this repo up

Then offer to fix it — this is the next step, so ask now:

- **If `.claude/skills/drain-it/SKILL.md` exists with a `generated-by:` marker** — this repo is on the
  superseded generated-skills architecture. Say so concretely: *"This repo has a generated
  `drain-it` I can migrate — I'd extract its config, show you the result, and remove the old skill
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
| Dependencies | Skip while any literal `Depends on #N` references an issue that is not CLOSED — re-eligible automatically once the dep merges. **Exempt: members of a stack this tick is dispatching** (below). |
| Collision | Skip if the issue's `touches:` set intersects any **in-flight** issue's `touches:` set — same repo-relative path, or a glob on one side matching a path on the other. Defer to a later tick; re-eligible once the overlapping issue merges. An issue with **no** `touches:` line intersects nothing, but is flagged `unannotated` in the tick report so the coupling gap is visible rather than silently risky. **Exempt: overlap between members of the same stack** (below). |

### Stacks (ONLY if `stacked_prs:` is configured)

**With no `stacked_prs:` block this section does not run**, and a dependency chain serializes across
ticks exactly as before. That is the default and it is correct, not degraded.

When it IS configured, `queue-snapshot.sh` surfaces a `stack` array on the bottom issue of each
declared chain. A chain is dispatchable as one stacked unit when **every** member is in `ready[]`,
unclaimed, and unblocked. Then two filter exemptions apply, and only within that chain:

- **Dependencies** — members may depend on each other and still dispatch together. That is the whole
  point: the chain ships now instead of one layer per tick. Dependencies pointing *outside* the
  chain still block it, as a unit.
- **Collision** — overlapping `touches:` sets *between members of the same stack* are expected, not
  hazardous: layer 2 is branched from layer 1, so it edits layer 1's files on top of layer 1's
  version by construction. Overlap between a stack member and any **other** in-flight issue still
  blocks the whole chain.

**Capacity: a chain costs ONE `max_in_flight` slot**, because it is one sub-agent in one worktree —
not one slot per layer. It does open N PRs, so a chain under a cap of 3 can still leave more PRs
in flight than an unstacked tick would; that is expected and bounded by `stacked_prs.max_depth`.

Verify the repo is actually enabled before dispatching a chain:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/stack-probe.sh --repo "<slug>"
```

Exit `11` means the preview is not enabled here. **Do not fall back to parallel dispatch** — the
members really do depend on each other. Drop the exemptions, let the ordinary Dependencies filter
serialize the chain across ticks, and note it once in the tick report.
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

A stack chain uses take-it's **stacked variant** instead: one sub-agent, one worktree, layers built
in order, PRs based on the layer below, linked via `POST /repos/{slug}/stacks`. Claim every member
up front — a half-claimed chain lets another loop pick up a layer mid-build. The shared worktree
appears **once** in the manifest, and teardown waits for the TOP layer to be terminal.

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
stacks: #1720 → #1721 → #1722 dispatched as 1 layer-stack (1 slot, 3 PRs)
unannotated (dispatched without a touches set — coupling unchecked): #1711
```

Plus one line per failure with its next action. Drop the `unannotated` line on ticks that dispatch
nothing unannotated, and the `stacks:` line on ticks that dispatch no chain. When a chain was
declared but the repo is not enabled for the preview, say so once rather than every tick:
`stacks: #1720→#1722 declared but stacks unavailable in this repo — sequencing by dependency instead`.

## 7. Terminal states — drain complete, drain stalled

A drain loop ends itself in exactly two states. Both must be **confirmed from live GitHub state
read this tick** — the §2 reconcile plus the §4 read, never a stale or transient one. If live
state could not be verified this tick — an API failure mid-tick — the tick proves nothing: leave
the loop alone, write no stall record, and let the next tick re-check.

### DRAIN COMPLETE

Ready empty AND in-flight zero → announce loudly and take the stop path below immediately — an
empty queue needs no confirmation tick:

```text
DRAIN COMPLETE — Ready is empty and nothing is in flight.
```

### DRAIN STALLED

In-flight zero AND dispatched zero this tick AND Ready non-empty — every Ready item held by a §4
filter. Nothing this loop controls can change GitHub state before the next tick: no PRs to merge,
no agents working, and dependency holds only resolve when a dep closes — with nothing in flight,
only external or human action closes one. The loop is stalled, not idle; "Ready isn't empty" alone
must never keep it alive.

Two carve-outs keep the state precise:

- **Self-resolving holds can never trip it.** Collision holds, migration-slot holds, and deps on
  in-flight issues all require in-flight > 0 — the in-flight = 0 conjunct excludes them by
  construction.
- **A foreign claim is not a human gate.** An item skipped by the Claimed filter is another
  session's in-flight (`mine: false`) and resolves when that session merges, no human needed. A
  tick whose holds include an active foreign claim is idle, not stalled — keep looping.

**Confirm across two consecutive ticks before stopping** — a single stalled tick may be racing
another session that is about to close a dependency or unblock an issue. Ticks share no memory,
so persist the observation next to the §5 batch manifest, in `.git/drain-it-stall.json`: the held
issue numbers with each one's hold root (the open `Depends on #N` it chains to, the `blocked`
label, the decision gate).

- **No record, or the recorded hold-set differs from this tick's** → write this tick's hold-set
  and finish normally, appending to the tick report:
  `stall: suspected — nothing in flight, all Ready held; an identical hold-set next tick ends the loop`.
- **Record matches this tick's hold-set exactly** → STALLED is confirmed. Delete the record and
  announce loudly, naming the reason **per held item** so the human knows exactly what unlocks
  the queue:

```text
DRAIN STALLED — nothing dispatchable and nothing in flight; all Ready items gate on human action:
  #103 #104 #105 #106 #108 → chain to #102 (parked in Backlog: awaiting planning session)
  #22 → blocked label (drain-it: 2 failed attempts — CI check needs a human call)
Loop <id> cancelled — resolve the gate(s), then restart the drain.
```

Then take the **same stop path as DRAIN COMPLETE** below — one path, never a parallel one.

Any tick that dispatches, merges, or observes in-flight work deletes a leftover
`.git/drain-it-stall.json`: progress resets the confirmation clock.

### Stop path — both terminal states

Stop the loop yourself, according to how this tick was invoked:

| Mode | Recognize it by | Stop path |
| --- | --- | --- |
| **Self-paced loop** (ScheduleWakeup) | This tick was woken by a wake-up the previous tick scheduled | Do not schedule another wake-up — the loop ends here |
| **Cron / fixed interval** (CronCreate-backed) | A cron job fires the skill on a schedule | **Self-cancel the cron** — see below. Do not merely advise the user to cancel; act |
| **Manual invocation** | No loop context | Nothing to cancel — announce and finish. A stalled manual tick announces STALLED immediately: the two-tick confirmation gates loop cancellation, and there is no loop |

**Cron self-cancel.** Find the loop's job id yourself: run `CronList` and select the job whose
prompt is this drain-it invocation.

- **Exactly one match** → `CronDelete <id>`, then append to the report — after COMPLETE: `Loop
  <id> cancelled — run groom-it to refill Ready and start a new drain when there's more to
  ship.`; after STALLED: `Loop <id> cancelled — resolve the gate(s), then restart the drain.`
- **Zero, multiple, or ambiguous matches** → delete NOTHING. Announce the terminal state, list
  the candidate ids, and tell the user to `CronDelete` the right one. Deleting the wrong job is
  worse than a few extra no-op ticks.

Safety rails: self-cancel ONLY on a terminal state confirmed above. For COMPLETE, anything still
claimed or an open PR (in-flight until actually MERGED, per §3) means the drain is not complete.
For STALLED, any dispatch, any in-flight work (mine or foreign), or a hold-set that changed since
the recorded tick means the loop may still make progress — stay alive. An API-failure tick never
self-cancels and never counts toward stall confirmation. Ticks that fire between confirmation and
cancellation are no-ops, not errors: each re-runs this section and retries.

## Guardrails

- **Ready only.** Everything else is groom-it's job — drain-it never promotes, never grooms, never
  files issues.
- **Hard cap `max_in_flight`**, counting carry-over from previous ticks, not just this tick's
  dispatches. A stack chain is one slot, not one per layer.
- **Never dispatch a partial chain**, and never split one across parallel agents. If any member is
  claimed, blocked, or missing from Ready, the whole chain waits.
- **Idempotent ticks**: every action re-checks live GitHub state first; a crashed tick must be
  safely re-runnable, with worktrees reclaimable via the batch manifest.
- **Single-writer**: only the coordinator merges or enqueues; max one redispatch per issue without
  a human.
- If `ai-agent-skills:pr-shepherd` or take-it is missing, STOP and say so — do not improvise
  dispatch or merge mechanics.

Apply any `## extra-sequencing` section from config as additional §4 filters.
