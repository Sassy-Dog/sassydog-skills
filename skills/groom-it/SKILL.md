---
name: groom-it
description: >
  Backlog grooming: refine open issues until they are fully dispatchable by a cold worktree
  sub-agent, then promote them to Ready. The counterpart that feeds drain-it. Use when the user
  says "groom it", "groom the backlog", "refine the backlog", "scope these issues", "make these
  dispatchable", "get the backlog ready", "fill it", or asks to move issues to Ready. Writes:
  issue-body edits, Ready promotion, and epic-split sub-issues only — never deletes, never closes,
  never dispatches work. Reads the current repo's settings from `.claude/sassy-dog/groom-it.md`.
---

# Groom-It

Groom the backlog until every issue is either **Ready** — a cold sub-agent could ship it — or
**explicitly parked with a named reason**.

Groom-it owns *content quality*; sequencing and dispatch belong to drain-it. The two share one
contract: **Ready means dispatchable.** Nothing reaches Ready that you would not hand to a worktree
agent with zero conversation context.

> Formerly `fill-it`. The "fill it" trigger still resolves here.

## 1. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/groom-it.md" 2>/dev/null || echo "NO_CONFIG"`

Frontmatter supplies `gotcha_summary` and the optional `board` block. Contract:
`ai-agent-skills:refresh-sassydog-skills` → `references/config-contract.md`.

**If it reads `NO_CONFIG`**, run boardless (the `ready`-label flow below) and skip the repo-gotchas
step in §4 — **do not invent gotchas** by reading the repo's CLAUDE.md or CI config; a wrong gotcha
in an issue body misleads a cold sub-agent that has no way to check it. Say the step was skipped.

Grooming is otherwise safe to run un-configured: its writes are issue-body edits and label changes,
both reversible. Do not assume a board exists — a board with no config block is OFF.

## 2. Collect candidates

**With `board:` configured** — the board is authoritative. Snapshot via
`ai-agent-skills:github-issues` (`board-snapshot.sh`, using `board.number` and `board.owner`).
Candidates are every open issue in **Backlog** or with **no status**; open issues missing from the
board get added to it.

**Without a board** — open issues are the backlog and the `ready` label is Ready:

```bash
gh issue list --state open --limit 200 --json number,title,labels,assignees
```

Candidates are every open issue **without** the `ready` label. Skip issues another loop already
claimed — assignee set plus `in-progress` label.

**Either way, re-validate existing Ready items every run.** The snapshot or list is already in
hand, and drift happens: a decision marker or new blocker added after promotion demotes the item
back to Backlog with a comment. Demotion via `ai-agent-skills:github-issues`:
`issue-claim.sh demote N --comment "<the drift>"` — the comment is mandatory. Ready is a promise;
stale promises break drain-it.

Read each candidate IN FULL — `gh issue view N --comments` — scope often lives in follow-up
comments.

## 3. The dispatchability rubric

An issue is **Ready** only if ALL of these hold:

| # | Test | Failure action |
| --- | --- | --- |
| 1 | Problem + desired outcome stated in the body | Refine (§4) |
| 2 | Scope names real touchpoints (files/components/services), or enough pointers that a cold agent finds them in one recon pass | Refine (§4) — recon the codebase yourself, write the map in |
| 3 | Acceptance criteria checklist present | Refine (§4) |
| 4 | Self-contained: screenshots/attachments transcribed into prose, referenced docs committed on the default branch | Refine (§4); ask the user to paste any image you cannot read — until they do, the verdict is **parked: awaiting-user** |
| 5 | No open product decisions: no `(decision)` markers, no `## Open questions`, no "TBD" | Surface the decision with a recommended default; issue stays unpromoted until resolved |
| 6 | Right-sized: one coherent PR per issue | Epic → split (§5) |
| 7 | Dependencies recorded as literal `Depends on #N` lines, one per line | Add them — drain-it enforces ordering from these lines |
| 8 | Touch-set annotated: a single machine-readable `touches:` line naming the repo-relative paths/globs the issue's PR will edit | Add it (§4) — drain-it reads it to avoid dispatching two file-overlapping issues concurrently |

GitHub `user-attachments` URLs are cookie-walled and unreadable from a worktree agent, which is why
test 4 demands transcription rather than a link.

A dependency being open does NOT block Ready — drain-it sequences at dispatch time. Only
*unrecorded* dependencies block, because invisible ordering is how parallel agents collide.

## 4. Refine

Per failing candidate:

1. Ground the scope in the codebase — dispatch `Explore` agents for recon when touchpoints are
   unknown. Never write a scope you haven't verified against real files.
2. Rewrite the body: preserve the original ask as a `> quote`, then problem, scope, touchpoints,
   acceptance, and dispatch-notes sections.
3. Write the **touch-set**: a single `touches:` line listing the repo-relative paths/globs the
   issue's PR will edit, distilled from the scope you just grounded and its `file:line` citations.
   Space-separated, globs allowed. Keep it to files that will actually change, not every file
   mentioned. This is the coupling signal drain-it parses, so under-scoping it re-introduces the
   conflict churn it exists to prevent.
4. Record the repo gotchas a cold sub-agent needs, from the config's `gotcha_summary`.
5. `gh issue edit N --body-file …` — edit the body, don't comment-and-hope.

Decisions are NEVER guessed: present each to the user as a recommendation with trade-offs, then
fold the answer into the body marked **Decision (date)** so it supersedes any `(decision)` marker.

## 5. Epic split

A multi-workstream issue gets child issues — one per dispatchable unit — via the gated write path:
`ai-agent-skills:github-issues` `file-or-link-issue.sh`, marker `epic-split: #<parent>/<slug>`,
body containing `Part of #<parent>` (NOT `Closes`). Children then pass the §3 rubric individually;
the parent stays out of Ready, because it tracks rather than dispatches.

**Run splits FIRST in a grooming pass.** `Depends on #N` lines must point at dispatchable issues —
children, never a tracking parent — so an issue depending on "the schema part of epic #E" cannot
finalize its dependency line until #E's split has produced the child number.

## 6. Promote and report

**With `board:`** — move qualifying cards to **Ready** per `ai-agent-skills:github-issues`
(`references/board-graphql.md`), using the board IDs from config.

**Without a board** — label qualifying issues `ready` via `ai-agent-skills:github-issues`, which
owns the label taxonomy and ensure-creates before use:

```bash
issue-claim.sh promote N1 N2
```

Demotion is the reverse and **requires the reason**: `issue-claim.sh demote N --comment "<why>"`.
Never a silent strip.

Every promoted issue carries its `touches:` line from rubric #8.

Final table: issue · verdict (**Ready** / needs-decision / split → children / parked:
awaiting-user / parked: reason) · what changed. End with the decisions awaiting the user, if any.

## Guardrails

- Never file new issues outside the §5 epic-split gate; synthesis of brand-new work is plate-it's
  job.
- Never close issues, never delete content — the original ask survives as a quote.
- Never promote with an unresolved decision "because the default is obvious" — the default goes to
  the user first.
- Ready is a promise to drain-it. When in doubt, park with a reason instead.

Apply any `## extra-rubric` section from config as additional Ready tests.
