---
name: sentry-triage
description: >
  This skill should be used when the user asks to "triage Sentry", "pull top unresolved Sentry
  issues", "what's blowing up in Sentry", "which Sentry errors qualify for a GitHub issue",
  "cross-reference Sentry with GitHub", "escalate Sentry hits to the backlog", or any task that
  applies a qualifying gate (unresolved, recent, user/event thresholds) to Sentry issues and
  optionally files GitHub issues from the survivors. Also triggers when a project workflow skill
  (a generated plate-it) invokes ai-agent-skills:sentry-triage by name. For Sentry SDK setup or
  open-ended natural-language Sentry exploration, defer to the sentry plugin's own skills.
---

# Sentry Triage

Gate-and-escalate triage: pull not-resolved Sentry issues for a project, apply a qualifying gate, cross-reference against GitHub, and (only with explicit approval) escalate survivors to GitHub issues. Reads only — this skill never mutates Sentry state.

## Inputs to establish first

1. **Org + project slug(s)** — from the caller or by listing projects. Don't hunt for phantom projects: platforms sharing a DSN don't appear separately.
2. **Gate policy** — the caller's thresholds, or the defaults in `references/qualifying-gate.md`.
3. **Escalation target** — repo (and optional board IDs) if filing is on the table; otherwise this is a read-only report.

## Workflow

### 1. Pull

**MCP-first**: use the connected Sentry MCP server's project-listing and issue-search tools (resolve the project slug first, then search). Do not hardcode `mcp__...` tool IDs — resolve by capability. No MCP connected → `references/api-fallback.md` (REST with `SENTRY_AUTH_TOKEN`).

Query `!is:resolved` — one call covers unresolved + ignored (status is exclusive; boolean `OR` returns HTTP 400 — full syntax notes in `references/query-syntax.md`). Pull per issue: `shortId, title, count, userCount, lastSeen, firstSeen, level, culprit, permalink, status`.

**Then resolve environments before gating** (gate rule 6). Issue search does not return an environment breakdown, and an issue can span several, so ask the events dataset once per project rather than per issue: an aggregate over the `errors` dataset with fields `["environment", "count()"]` grouped by environment, scoped to the same window. An issue whose events are *entirely* in a non-production environment is `skip-nonprod`. Skipping this step is not a smaller version of the gate — it is the version that ranks CI noise as a customer-facing outage, because a CI environment manufactures `userCount` (see the rule 6 rationale).

### 2. Gate

Read `references/qualifying-gate.md`; apply each rule and tag non-qualifiers (`skip-noise` / `skip-stale` / `skip-parked` / `already-linked`) so the report shows *why* something didn't escalate, not just that it didn't.

Cross-reference against GitHub by marker: `gh issue list --search '"sentry-source: <SHORT_ID>" in:body' --state all`. If the caller also pulled TestFlight crash feedback, fuzzy-merge on `culprit`/stack signature before reporting — the same crash in two surfaces is one item, not two.

### 3. Report

One line per issue: `SHORT_ID · title · events/users · lastSeen · level · gate verdict · GH peer (#N or —)`. Qualifiers first, then skips grouped by reason. No section for empty buckets.

### 4. Escalate (only if asked, never silently)

Filing goes through `ai-agent-skills:github-issues` — its `file-or-link-issue.sh` with `--marker "sentry-source: <SHORT_ID>"`, following that skill's preview-then-confirm contract and burst rail (> 5 candidates → stop and summarize). Never raw `gh issue create`.

## Hard prohibitions

- Never resolve, ignore, assign, or otherwise mutate Sentry issues.
- Never escalate `ignored` issues — ignoring was a human decision.
- Never file without a preview the user approved in this run.
