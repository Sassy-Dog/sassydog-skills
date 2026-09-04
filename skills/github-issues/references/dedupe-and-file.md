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
2. **Idempotency — two stages, and neither one alone is enough.** GitHub's issue search index is **asynchronous**, so a marker written seconds ago is not in it yet and an empty result is indistinguishable from "never filed". Measured 2026-09-04: #337 was filed at `21:05:37Z`; the same marker re-run at `21:05:44Z` searched, got `[]`, and filed the duplicate #338 — seven seconds — while the identical search four minutes later returned both. The marker footer and the query were correct the whole time; only the freshness assumption was wrong. So the script asks twice:
   - **Search** — `gh issue list --state all --search '"<marker>" in:body' --json number,url,body`. It indexes body text including HTML comments and reaches back to the repo's oldest issue, so it is unbounded in *age*. It is eventually consistent, not fresh.
   - **Recent-listing scan** — `gh issue list --state all --json number,url,body --limit N`, with **no** `--search`. That is a direct object read rather than an index query, so it is **read-after-write consistent**: an issue is visible the instant it exists. It is bounded in *count* — the newest N issues (`--recent-scan`, default 100), which is exactly the window the index has not caught up to.

   **Both stages match the delimited footer `<!-- <marker> -->`, never the bare marker**, through one predicate with two call sites — so `epic-split: #207/alpha` is not reported as already-linked against an existing `epic-split: #207/alpha-two`. Each stage needs it for a *different* reason, which is why applying it to one is not enough: the scan's `contains()` is a plain substring test, while GitHub phrase search matches a token **subsequence** (verified read-only 2026-09-04 — `"stale-issues-title-only" in:body` returns #339/#337/#338, whose marker is `stale-issues-title-only-shipped-detector`; a superstring control returns `[]`). The search route is the *more* likely one, because it fires on a sibling that is already indexed — any sibling more than a few minutes old. Rows are therefore filtered rather than trusted, and a hit that does not carry the footer falls through to the scan instead of short-circuiting. This matters most for `groom-backlog`'s `epic-split: #<parent>/<slug>` children, where free-form slugs make `auth` / `auth-refresh` ordinary: the harm is a real child issue **never filed**, reported as `already-linked` with a sibling's number.

   Hit → `already-linked` with the existing number, plus a `via` field naming which stage answered. The two are complementary — search covers depth, the scan covers recency — so removing either restores a real defect. A retry/backoff loop was rejected: slow on every duplicate-free call, and still racy. A scan that could not be **performed** — a failed call, or a successful one whose payload is not a JSON array — exits `2` rather than filing, because an unverified idempotency read never licenses a write; retrying is always safe. A scan window that came back **full** cannot be distinguished from one with headroom, so the three filing outcomes carry `scan_truncated`.
3. **Dry-run** (`--dry-run` or `DRY_RUN=1`) returns `would-file` without writing — use this for previews. It runs *after* both idempotency stages, so a preview never says `would-file` for a marker that is already filed.
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

When idempotency returns `already-linked` but the signal has materially escalated (event count doubled, new release affected), **comment on the existing issue** rather than filing a new one — keep one thread per fingerprint:

```bash
gh issue comment <N> --repo <REPO> --body "Signal update: <what changed, with numbers and a link>"
```

## Stale-state hygiene

Auto-filed issues rot in two known ways; `scripts/stale-issues.sh` detects both:

- **shipped-but-still-open** — a merged PR named the issue without closing it. Two arms, and each hit carries `matched_via`: a **title** parenthetical (`(#419)`), which is a hyperlink and NOT a close keyword; or a **body** reference carrying no closing keyword, which is where the reference usually lives — GitHub appends `(#N)` to the squash-merge *commit* title, not the PR title. A title hit is near-certain; a body hit is a review prompt, since a PR may cite an issue for background. Review and close manually, or comment status if half-shipped. (Prevention: `Closes #N` on its own line in the PR body.)
- **stub-body** — body under 80 chars / placeholder. Before flagging to a human, **read the comments** (`gh issue view N --comments`): some repos scope issues in a follow-up comment, not the OP.
