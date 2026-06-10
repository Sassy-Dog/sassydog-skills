---
name: codebase-assessment
description: >
  This skill should be used when the user asks to "assess this repo", "audit the codebase",
  "run a project assessment", "do a full repository health check", "review the whole repo and
  file issues", "what tech debt do we have", "find risks across the codebase", or wants a
  comprehensive, evidence-based engineering audit (architecture, security, testing, CI/CD,
  infra, DX, dependencies, observability) turned into a tracked GitHub Issue backlog. Also
  triggers for periodic re-assessment, e.g. "a new frontier model dropped, re-assess the repo".
---

# Codebase Assessment

Turn a whole repository into a deduped, evidence-backed, PR-sized GitHub Issue backlog under one tracking **Epic** — by fanning out specialized review agents, adversarially verifying their findings, and filing only what survives.

**Repo-agnostic.** Works on any GitHub repo. Operates on **one repo per run** (the current working dir unless a target is given). A periodic routine loops multiple repos — that lives outside this skill.

**Default = preview, not file.** Filing issues is outward-facing and hard to undo. Always present the proposed Epic + child issues for approval and file only after the user confirms. Never create issues silently.

## Core Principle

A finding only earns an issue if it has **concrete `file:line` evidence**, survives an **adversarial second look**, and is **not already tracked** by an existing issue. Everything else is noise — drop it. One issue = one coherent PR's worth of work.

## Workflow

Follow the five phases. Full dispatch details, the finding schema, and exact `gh` commands live in the reference files — read them when you reach that phase.

### Phase 0 — Scope & detect (you, the main agent)

1. Resolve the target repo (cwd or the path/arg given). Confirm a GitHub remote:
   `gh repo view --json nameWithOwner,defaultBranchRef`.
2. Detect stack(s) by globbing manifests: `package.json`, `*.csproj`, `Cargo.toml`, `pubspec.yaml`, `*.tf`/`*.bicep`, `Dockerfile`, `.github/workflows/`, Nx/Bun/tRPC config. This decides which review agents to dispatch.
3. **Build the dedupe index** (used in Phase 2 and Phase 4):
   `gh issue list --state open --limit 500 --json number,title,labels,body`
   (also pull recently-closed for context). Keep it in memory for the whole run.

### Phase 1 — Fan out (parallel review agents)

Dispatch the relevant `ai-agent-skills:*-reviewer` agents **in a single message with multiple Agent tool calls** so they run concurrently. Skip domains with no signal (no IaC → skip `infra-platform-reviewer`). Give each agent the repo path, the detected stack, and its scope. Each returns findings in the shared schema with mandatory `file:line` evidence.

See **`orchestration.md`** for the agent→domain map and the finding schema.

### Phase 2 — Adversarial review (you)

For every finding: open the cited `file:line` and confirm the evidence is real and the problem genuine (not mere preference/convention); sanity-check severity, likelihood, and blast radius. Dedupe findings against each other **and against the Phase-0 GitHub index**. For high-impact findings, optionally dispatch perspective-diverse skeptic subagents prompted to *refute* — keep only survivors. Be skeptical by default; a false issue costs more than a missed one.

### Phase 3 — Group into PR-sized work items

Cluster surviving findings so each cluster is one coherent PR (e.g. "harden GitHub Actions workflows" may bundle 3 findings). Each cluster becomes one child issue.

### Phase 4 — Preview, then file

1. **Print the full preview**: the Epic (exec summary + scores) and every child issue (title, body, labels, and its dedupe decision). Ask the user to approve, edit, or cancel. **File nothing yet.**
2. On approval, follow **`references/github-issue-ops.md`**: ensure labels exist idempotently, re-check dedupe per issue right before creation (comment on a match instead of duplicating), create child issues, create the Epic, then attach each child as a **native sub-issue** (`gh api`), with a task-list fallback.

### Phase 5 — Report

Print the Epic URL, the child issue list, and the executive summary.

## Reference Files

- **`assessment-rubric.md`** — the 15 assessment areas, scoring (1–10 health/security/DX/maintainability), severity & likelihood definitions, and the executive-summary format. Review agents consult their section; you use it for the Epic summary.
- **`orchestration.md`** — agent→domain map, per-agent scope, the finding output schema, and the adversarial-review / dedupe / grouping logic.
- **`references/github-issue-ops.md`** — label taxonomy, child-issue & Epic body templates, and exact `gh`/`gh api` commands for dedupe, labels, issue creation, and native sub-issue linking.

## Red Flags — STOP

- About to file an issue with no `file:line` evidence → drop it or downgrade to the Epic's "watch list".
- About to create issues without showing the preview first → STOP, preview and get approval.
- A finding that's "best practice" with no concrete harm in *this* repo → that's cargo-cult; drop it.
- Skipped the dedupe index fetch → you will create duplicates. Fetch it in Phase 0.
