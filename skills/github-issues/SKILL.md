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

Issue and ProjectV2 board operations for any GitHub repo: board snapshots, backlog reads, stale-issue detection, and idempotent dedupe-then-file issue creation. Reads are free; **the single write path is `scripts/file-or-link-issue.sh`, and every write is preview-then-confirm.**

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

## Bundled scripts

| Script | Purpose |
|--------|---------|
| `scripts/board-snapshot.sh` | ProjectV2 snapshot grouped by status. Read-only. Guards the `--limit` truncation trap. |
| `scripts/stale-issues.sh` | shipped-but-still-open + stub-body detection. Read-only. Handles compound PR-title refs like `(#419 + #421)`. |
| `scripts/file-or-link-issue.sh` | **The only write path.** Marker-keyed create-or-find + optional board add. `--dry-run` for previews. |

## Guardrails

- Never `gh issue create` directly when filing from an automated signal — route through `file-or-link-issue.sh` so idempotency and markers can't drift.
- Mutating board calls go through pr-shepherd's `gh-retry.sh` (Projects GraphQL flakes); board claims are best-effort, never a hard failure.
- Signal escalated on an existing issue → comment on it, don't re-file.
