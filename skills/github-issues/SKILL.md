---
name: github-issues
description: >
  This skill should be used when the user asks to "snapshot the project board", "show the board
  by status", "pull the backlog with labels", "find stale issues", "which issues shipped but are
  still open", "find stub issues that need scoping", "file an issue but check for duplicates first",
  "dedupe before filing", "link this Sentry or feedback item to a GitHub issue", or any task
  involving GitHub issue/board reads via gh + GraphQL, label taxonomy, stale-issue detection, or
  gated dedupe-then-file issue creation. Also triggers when a project workflow skill (a generated
  plate-it or take-it) invokes ai-agent-skills:github-issues by name.
---

# GitHub Issues

Issue and ProjectV2 board operations for any GitHub repo: board snapshots, backlog reads, stale-issue detection, idempotent dedupe-then-file issue creation, and the fill/drain label-state transitions. Reads are free; **there are exactly two write paths — `scripts/file-or-link-issue.sh` (issue creation, preview-then-confirm) and `scripts/issue-claim.sh` (label-state transitions, dry-runnable).**

## Reads

### Board snapshot (grouped by status column)

```bash
PROJECT_NUMBER=<n> OWNER=<org> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/board-snapshot.sh
```

Emits `{counts, truncated, items[]}`. If `truncated: true`, raise `PROJECT_LIMIT` — the newest issues are what got dropped. For board ID discovery (project/field/option IDs), card moves, and the board-vs-labels source-of-truth question, read `references/board-graphql.md`.

### Backlog via labels

Some repos run label-driven backlogs with an empty board — an empty snapshot does not mean no backlog:

```bash
gh issue list --repo <R> --state open --limit 200 --json number,title,labels,updatedAt
```

### Boardless work-queue snapshot (fill/drain)

One call replaces the per-tick ready/in-flight/blocked list reads AND parses the two machine-readable body contracts (`touches:` collision sets, literal `Depends on #N` lines) in one place:

```bash
REPO=<owner/name> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/queue-snapshot.sh
```

Emits `{repo, me, ready[], in_flight[], blocked[]}` — `ready` ordered number-ascending with `touches`/`depends_on`/`unannotated` per issue; `in_flight` carries a `mine` flag rather than silently filtering to @me, so a loop can count its own claims while still seeing other sessions'. Judgment (touches-set intersection, priority, the smell test) stays with the caller — this is a read, not a dispatcher.

### Stale-issue detection

```bash
REPO=<owner/name> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/stale-issues.sh
```

Two buckets: `shipped-but-still-open` (merged PR referenced the issue only in a title parenthetical — never auto-closed) and `stub-body` (needs scoping). **Before flagging a stub to the user, read its comments** — `gh issue view N --comments` — scope often lives in a follow-up comment.

## Writes: dedupe-then-file

Read `references/dedupe-and-file.md` before the first write of a session. The contract in brief:

1. The caller's qualifying gate runs first (this skill doesn't judge severity).
2. Idempotency by body marker (`<source>-source: <STABLE_ID>`) — re-runs return the existing issue, never a duplicate.
3. **Preview-then-confirm**: dry-run the batch, show `would-file` results, file only on approval.
4. **Burst rail**: > 5 would-file in one run → stop and show the list; consider one umbrella issue.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/file-or-link-issue.sh \
  --repo <owner/name> \
  --marker "sentry-source: PROJ-123" \
  --title "<title>" --body-file /tmp/body.md \
  --labels "bug,sentry-escalation" \
  --ensure-label "sentry-escalation:B60205:Auto-filed from a Sentry hit" \
  --project-id PVT_xxx --status-field-id PVTSSF_xxx --status-option-id <backlog-id> \
  --dry-run
```

Output actions: `filed` / `already-linked` / `filed-no-board` / `would-file`. Board placement is optional and degrades gracefully.

## Writes: label-state transitions (fill/drain claims)

`scripts/issue-claim.sh` is the canonical home of the boardless dev-workflow label taxonomy — the labels, their colors, and their descriptions are defined in the script, nowhere else:

| Label | Color | Meaning |
|-------|-------|---------|
| `ready` | `0E8A16` | Dispatchable: a cold worktree agent could ship this (groom-it promoted) |
| `in-progress` | `1D76DB` | Claimed by a take-it/drain-it loop |
| `blocked` | `B60205` | Needs a human decision before it can be dispatched (drain-it demoted) |

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/issue-claim.sh \
  <claim|release|block|promote|demote> <N> [N ...] \
  [--repo <owner/name>] [--comment "why"] [--force] [--dry-run]
```

- `claim` — assignee @me + `in-progress`, strips `ready`; **skips issues already assigned to someone else** (double-pick guard; `--force` overrides).
- `release` — strips `in-progress` (post-merge: `Closes #N` closes the issue but never strips labels).
- `block` / `demote` — **require `--comment`**; a demotion without a reason is a silent failure for the next human.
- Every label is ensure-created (idempotent) before use; mutations route through pr-shepherd's `gh-retry.sh`; one JSON line per issue on stdout; batch continues past per-issue failures (exit 2 if any hard-failed).

## Bundled scripts

| Script | Purpose |
|--------|---------|
| `scripts/board-snapshot.sh` | ProjectV2 snapshot grouped by status. Read-only. Guards the `--limit` truncation trap. |
| `scripts/queue-snapshot.sh` | Boardless fill/drain queue read: ready/in-flight/blocked buckets + parsed `touches:` and `Depends on #N` body contracts. Read-only. Exit 10 skip convention. |
| `scripts/stale-issues.sh` | shipped-but-still-open + stub-body detection. Read-only. Handles compound PR-title refs like `(#419 + #421)`. |
| `scripts/file-or-link-issue.sh` | Write path #1: issue creation. Marker-keyed create-or-find + optional board add. `--dry-run` for previews. |
| `scripts/issue-claim.sh` | Write path #2: fill/drain label-state transitions (claim/release/block/promote/demote). Owns the label taxonomy; ensure-label built in; `--dry-run`; retries via pr-shepherd's `gh-retry.sh`. |

## Guardrails

- Never `gh issue create` directly when filing from an automated signal — route through `file-or-link-issue.sh` so idempotency and markers can't drift.
- Never hand-roll `gh label create` or claim-label `gh issue edit` calls in a fill/drain flow — route through `issue-claim.sh` so the taxonomy (names, colors, descriptions, the double-pick guard) can't drift.
- Mutating board calls go through pr-shepherd's `gh-retry.sh` (Projects GraphQL flakes); board claims are best-effort, never a hard failure.
- Signal escalated on an existing issue → comment on it, don't re-file.
