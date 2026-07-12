<!--
TEMPLATE: fill-it · version 3
Render rules: see plate-it.template.md header. Same conventions.
REQUIRES: GitHub Issues. Board-optional: IF:BOARD true renders board-backed promotion
(ProjectV2 board with Backlog + Ready status columns); IF:BOARD false renders the boardless
degraded-board contract (Ready = the `ready` label, demotion = remove label + comment).
-->
---

name: fill-it
description: >
  Backlog grooming for {{PROJECT_NAME}}: refine open issues until they are fully dispatchable
  by a cold worktree sub-agent, then <!-- IF:BOARD -->move them to Ready on the board<!-- ELSE -->promote them to Ready via the `ready` label<!-- ENDIF -->. The counterpart that
  feeds drain-it. Use when the user says "fill it", "groom the backlog", "refine the backlog",
  "scope these issues", "make these dispatchable", "get the backlog ready", or asks to move
  issues to Ready. Writes: issue-body edits, <!-- IF:BOARD -->board moves<!-- ELSE -->`ready`-label changes<!-- ENDIF -->, and
  epic-split sub-issues only — never deletes, never closes, never dispatches work —
  {{PROJECT_NAME}}-specific
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: fill-it | template-version: 3 -->

# {{PROJECT_NAME}} Fill-It

Groom the backlog until every issue is either **Ready** (a cold sub-agent could ship it) or **explicitly parked with a named reason**. Fill-it owns *content quality*; sequencing and dispatch belong to drain-it. The two share one contract: **Ready means dispatchable.** Nothing reaches Ready that you would not hand to a worktree agent with zero conversation context.

## 1. Collect candidates

<!-- IF:BOARD -->
Board {{BOARD_NUMBER}} is authoritative ({{BACKLOG_SOURCE_DESCRIPTION}}):

- Snapshot via `{{CAP_NS}}github-issues` (`board-snapshot.sh`, `PROJECT_NUMBER={{BOARD_NUMBER}} OWNER={{BOARD_OWNER}}`).
- Candidates: every open issue in **Backlog** or with **no status** (open issues missing from the board get added to it). Re-validate existing Ready items every run (the snapshot is already in hand) — drift happens; a decision marker or new blocker added after promotion demotes the card back to Backlog with a comment. Ready is a promise; stale promises break drain-it.
<!-- ELSE -->
Open issues are the backlog ({{BACKLOG_SOURCE_DESCRIPTION}}); the `ready` label is Ready:

- List via `gh issue list --repo {{REPO_SLUG}} --state open --limit 200 --json number,title,labels,assignees`.
- Candidates: every open issue **without** the `ready` label (skip issues another loop already claimed — assignee set + `in-progress` label). Re-validate issues already carrying `ready` every run (the list is already in hand) — drift happens; a decision marker or new blocker added after promotion demotes the issue via `{{CAP_NS}}github-issues`'s `issue-claim.sh demote N --repo {{REPO_SLUG}} --comment "<the drift>"` (the comment is mandatory). Ready is a promise; stale promises break drain-it.
<!-- ENDIF -->
- Read each candidate IN FULL: `gh issue view N --repo {{REPO_SLUG}} --comments` — scope often lives in follow-up comments.

## 2. The dispatchability rubric

An issue is **Ready** only if ALL of these hold:

| # | Test | Failure action |
|---|------|----------------|
| 1 | Problem + desired outcome stated in the body | Refine (§3) |
| 2 | Scope names real touchpoints (files/components/services) or enough pointers that a cold agent finds them in one recon pass | Refine (§3) — recon the codebase yourself, write the map in |
| 3 | Acceptance criteria checklist present | Refine (§3) |
| 4 | Self-contained: screenshots/attachments transcribed into prose (GitHub `user-attachments` URLs are cookie-walled — unreadable from a worktree agent), referenced docs committed on the default branch | Refine (§3); ask the user to paste any image you cannot read — until they do, the verdict is **parked: awaiting-user** |
| 5 | No open product decisions: no `(decision)` markers, no `## Open questions`, no "TBD" | Surface the decision to the user with a recommended default; issue stays <!-- IF:BOARD -->Backlog<!-- ELSE -->unpromoted<!-- ENDIF --> until resolved |
| 6 | Right-sized: one coherent PR per issue | Epic → split (§4) |
| 7 | Dependencies recorded as literal `Depends on #N` lines (one per line) | Add them — drain-it enforces ordering from these lines |
| 8 | Touch-set annotated: a single machine-readable `touches:` line names the repo-relative paths/globs the issue's PR will edit | Add it (§3) — drain-it reads it to avoid dispatching two file-overlapping issues concurrently |

A dependency being open does NOT block Ready (drain-it sequences at dispatch time) — only *unrecorded* dependencies block, because invisible ordering is how parallel agents collide.

## 3. Refine

Per failing candidate:

1. Ground the scope in the codebase — dispatch `Explore` agent(s) for recon when touchpoints are unknown; never write a scope you haven't verified against real files.
2. Rewrite the body: preserve the original ask as a `> quote`, then problem/scope/touchpoints/acceptance/dispatch-notes sections.
3. Write the **touch-set**: a single `touches:` line on its own line in the body, listing the repo-relative paths/globs the issue's PR will edit — distilled from the scope/touchpoints you just grounded and the evidence `file:line` citations (no new work; you already read them). Space-separated, globs allowed; keep it to the files that will actually change, not every file mentioned. This is the coupling signal drain-it parses to avoid running two file-overlapping issues concurrently, so under-scoping it re-introduces the conflict churn it exists to prevent. Example: `touches: skills/refresh-sassydog-skills/references/templates/drain-it.template.md skills/refresh-sassydog-skills/references/templates/fill-it.template.md`.
4. Record repo gotchas the sub-agent needs ({{GOTCHA_SUMMARY}}).
5. `gh issue edit N --repo {{REPO_SLUG}} --body-file ...` — edit, don't comment-and-hope.

Decisions are NEVER guessed: present each to the user as a recommendation with trade-offs; fold the answer into the body marked **Decision (date)** so it supersedes any `(decision)` marker.

## 4. Epic split

A multi-workstream issue gets child issues (one per dispatchable unit) via the gated write path — `{{CAP_NS}}github-issues` `file-or-link-issue.sh`, marker `epic-split: #<parent>/<slug>`, body containing `Part of #<parent>` (NOT `Closes`). Child issues then pass the §2 rubric individually; the parent stays out of Ready (it tracks, it doesn't dispatch). **Run splits FIRST in a grooming pass**: `Depends on #N` lines must point at dispatchable issues — children, never a tracking parent — so an issue depending on "the schema part of epic #E" cannot finalize its dependency line until #E's split has produced the child number.

## 5. Promote + report

<!-- IF:BOARD -->
Move qualifying cards to **Ready** per `{{CAP_NS}}github-issues` (`references/board-graphql.md`; project `{{BOARD_PROJECT_ID}}`, status field `{{BOARD_STATUS_FIELD_ID}}`, Ready `{{BOARD_READY_OPTION_ID}}`).
<!-- ELSE -->
Label qualifying issues **`ready`** via `{{CAP_NS}}github-issues`'s `issue-claim.sh` — it owns the label taxonomy (names, colors, descriptions) and ensure-creates before use:

```bash
issue-claim.sh promote N1 N2 --repo {{REPO_SLUG}}
```

Demotion is the reverse and **requires the reason**: `issue-claim.sh demote N --repo {{REPO_SLUG}} --comment "<why>"` — never a silent strip.
<!-- ENDIF -->

Every promoted issue carries its `touches:` line (rubric #8) — that's the coupling signal drain-it reads to avoid dispatching two file-overlapping issues at once.

Final table: issue · verdict (**Ready** / needs-decision / split → children / parked: awaiting-user / parked: reason) · what changed. End with the decisions awaiting the user, if any.

## Guardrails

- Never file new issues outside the §4 epic-split gate; synthesis of brand-new work is plate-it's job.
- Never close issues, never delete content — the original ask survives as a quote.
- Never promote with an unresolved decision "because the default is obvious" — the default goes to the user first.
- Ready is a promise to drain-it. When in doubt, park with a reason instead.

<!-- BEGIN PROJECT-SPECIFIC: extra-rubric -->
<!-- END PROJECT-SPECIFIC -->
