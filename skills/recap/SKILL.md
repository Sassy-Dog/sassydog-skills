---
name: recap
description: >
  Render the session's end-of-work summary in the fixed recap format — what shipped, what surfaced
  along the way, which signals deserve a GitHub issue, and the immediate next steps. Use when the
  user says "recap", "recap the session", "recap the day", "summarize what we did", "summarize the
  session", "what did we get done", "wrap up the session", "debrief", or asks for a summary of the
  work just finished. Read-only: it reports and recommends; it never files issues or mutates
  anything.
---

# Recap

One retrospective report of the session just worked: what happened, what it revealed, and what to
do next — the same shape every time, so the user can scan it instead of re-reading the session.

**Acting principle:** a recap is evidence, not memory. Report only what was actually observed in
this session; anything uncertain renders as uncertain, never inferred — a confident summary built
on unverified claims reads exactly like a real one. Before asserting a terminal state ("merged",
"closed", "landed"), re-check it with a quick read (`gh pr view`, `gh issue view`) if the session's
last observation of it is stale.

## 1. Gather

Walk the session once and sort every event into exactly one bucket:

- **Work completed** — things that changed state and finished: merged PRs, pushed commits, config
  or infrastructure mutations, external actions (routine/trigger updates, secrets set). Each item
  keeps its evidence: PR number, commit SHA, run or session id, or link.
- **What surfaced** — findings the session produced that required no action yet: gotchas hit,
  diagnoses made, signals noticed (a flaky test, a coverage gap, a doc mismatch). One line each on
  why it matters.
- **Issues we should file** — the subset of surfaced signals with NO tracking issue anywhere. Each
  gets a proposed title, suggested labels, and a one-line rationale — enough that filing it later
  is mechanical. Check `gh issue list --search` before proposing; a signal that is already tracked
  belongs under "what surfaced" with its issue number instead.
- **Immediate next steps** — actions, not states. "PR #13 awaiting merge" is a state; "**Merge PR
  #13** — green and waiting on a human press" is a step. Order by priority; when the step is a
  one-liner, include the literal command (`take #99`, `gh pr merge 13 --auto`).

In-flight work that is still running (a watcher, an unfinished agent, an unmerged PR) is a next
step, never "completed".

## 2. Render

Output exactly this shape, inline as markdown:

```markdown
# Recap (YYYY-MM-DD)

## ✅ Work completed

- **<short bold action phrase>** — outcome, with evidence (PR #N · commit · link)

## 🔍 What surfaced

- **<finding>** — one line on why it matters (issue #N if already tracked)

## 📋 Issues we should file

- **<proposed title>** — `label`, `label` — one-line rationale

## 👉 Immediate next steps

1. **<short bold action phrase>** — one-line detail · `command` when it is a one-liner
```

Format rules:

- Sections in exactly this order; next steps LAST.
- An empty section is DROPPED entirely — except `## ✅ Work completed` and `## 👉 Immediate next
  steps`, which always render. An empty completed section says so honestly ("Nothing shipped this
  session"); an empty next-steps section is almost always a gather failure, not a clean slate.
- Every next step leads with the short bold action phrase; detail after the em-dash.
- Prose is complete sentences with evidence inline — fixed section names only, never a per-run
  taxonomy.

## 3. Read-only contract

This skill never files issues, never edits issues, and never mutates anything — in any repo, under
any invocation. "Issues we should file" is a recommendation list; when the user approves filing,
route it through `sassy-dog:github-issues` (its `file-or-link-issue.sh` dedupe-then-file path),
never file directly from here.
