# Dedupe-then-file: the gated issue-creation contract

Filing GitHub issues from automated signals (Sentry hits, feedback rows, scan findings) follows one contract, always routed through `scripts/file-or-link-issue.sh` so the rules live in one place.

## The marker convention

Every auto-filed issue carries a machine-readable marker in its body as an HTML comment footer:

```
<!-- <source>-source: <STABLE_ID> -->
```

Examples: `sentry-source: QRNINJA-WEB-3`, `feedback-source: fb_01HX...`, `assessment-source: epic-207/finding-12`.

- The **caller owns the prefix** (`sentry-source`, `feedback-source`, …); the script treats the marker as an opaque string.
- The ID must be **stable for the underlying signal** (Sentry shortId, feedback row ID) — that's what makes re-runs idempotent.
- The script appends the footer itself; callers never hand-write it into the body.

## The flow

1. **Caller applies its qualifying gate first** (e.g. sentry-triage's thresholds). The script does not judge severity; it deduplicates and files.
2. **Idempotency search**: `gh issue list --state all --search '"<marker>" in:body'`. Hit → return `already-linked` with the existing number. GitHub's search indexes body text including HTML comments.
3. **Dry-run** (`--dry-run` or `DRY_RUN=1`) returns `would-file` without writing — use this for previews.
4. **Create**: title, body file, labels (use `--ensure-label name:COLOR:description` for labels that may not exist yet — idempotent).
5. **Optional board add**: pass `--project-id/--status-field-id/--status-option-id` to land the issue in a column. Board failure degrades to `filed-no-board`, never a hard error.

## Preview-then-confirm — non-negotiable

**Never file issues silently.** Before any non-dry-run invocation:

1. Run the full candidate set with `--dry-run` and collect the `would-file` results.
2. Print the preview: title, labels, marker, and a body summary per candidate.
3. File only after the user approves. Approval for one batch does not carry over to the next run.

## The burst rail

If a single run would file **more than 5 new issues**, STOP and show the full list before filing any — even if a standing gate normally permits auto-filing. A burst that size usually means a new release regressed something systemic (one root cause, many fingerprints) — better one umbrella issue than 14 auto-filed duplicates.

## Match found but signal changed?

When the idempotency search returns `already-linked` but the signal has materially escalated (event count doubled, new release affected), **comment on the existing issue** rather than filing a new one — keep one thread per fingerprint:

```bash
gh issue comment <N> --repo <REPO> --body "Signal update: <what changed, with numbers and a link>"
```

## Stale-state hygiene

Auto-filed issues rot in two known ways; `scripts/stale-issues.sh` detects both:

- **shipped-but-still-open** — a merged PR referenced the issue only in a title parenthetical (`(#419)`), which is a hyperlink, NOT a close keyword. Review and close manually, or comment status if half-shipped. (Prevention: `Closes #N` on its own line in the PR body.)
- **stub-body** — body under 80 chars / placeholder. Before flagging to a human, **read the comments** (`gh issue view N --comments`): some repos scope issues in a follow-up comment, not the OP.
