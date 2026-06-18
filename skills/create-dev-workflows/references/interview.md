# Phase 2 — the interview

Ask ONLY what detection couldn't establish or what's policy (not fact). Use AskUserQuestion; batch into at most two rounds. Show detected values as the recommended option — the user confirms rather than recites.

## Questions

### 1. take-it wanted? (skip in update mode unless the user raised it)

Parallel issue-shipping is opt-in. Default **yes** if the repo has GitHub Issues + Actions and a worktree-friendly dev loop; default **no** if the repo is a prototype or the user runs strictly serial. A trio without take-it is a valid steady state — update mode must never add take-it unasked.

### 2. plate-it write policy

| Option | Meaning |
|---|---|
| **Read-only** (default for new adoptions) | Plate reports; never files. `IF:WRITE_GATE_SENTRY` off. |
| **Gated Sentry→GH auto-file** | Qualifying Sentry hits (sentry-triage gate defaults: unresolved · lastSeen ≤ 7d · userCount ≥ 2 ∨ events ≥ 5 ∨ error ∧ events ≥ 2) auto-file so the plate always hands take-it real issue numbers. Burst rail: > 5 would-file → stop and ask. |

Offer the gate defaults verbatim; record any threshold tweak in `{{SENTRY_GATE_SUMMARY}}`. Requires Sentry detected + an escalation repo.

### 3. Merge policy — always confirm, never trust the probe alone

Show the detected value (`merge_queue: true/false/null` + repo settings) and have the user confirm queue vs direct. State the stakes: a wrong "queue" guess means `--auto` calls that silently never merge; a wrong "direct" guess bypasses queue serialization. Sets `IF:MERGE_QUEUE` and `{{MERGE_POLICY_NOTE}}`.

### 3b. fill-it / drain-it wanted? (opt-in pair; skip in update mode unless raised)

Both require `IF:BOARD` with a **Ready** status column; drain-it additionally requires take-it. Default **no** unless the repo already runs a Ready-based flow. If drain-it is wanted, confirm two policy facts:

- `{{MAX_IN_FLIGHT}}` — concurrent in-flight cap (default **5**).
- `{{DISPATCH_MODEL}}` — model for dispatched sub-agents (default **`opus`** = latest Opus alias, for cost control; the coordinator tick stays on the session model). Record verbatim in the rendered §4.
- Pin `{{BOARD_READY_OPTION_ID}}` (and Backlog id for bounce-backs) alongside the other board IDs.
- fill-it: confirm `{{GOTCHA_SUMMARY}}` — the one-line list of repo gotchas every refined issue body should carry (e.g. codegen paths, i18n catalogs, migration policy).

### 4. Commands (fact confirmation, free-text)

- Pre-flight commands (`{{PREFLIGHT_COMMANDS}}`) — propose from the runner; user edits.
- Migration regen command (`{{MIGRATION_REGEN_COMMAND}}`) if `IF:MIGRATIONS`.
- Codegen command + output dirs if `IF:CODEGEN`.

### 4b. clean-it never-discard files (fact confirmation; clean-it is core, so always asked)

clean-it auto-discards untracked noise against an allowlist — confirm the **never-discard** list of
gitignored-but-precious files it must leave alone (`{{NEVER_DISCARD}}`). Propose `.env.local` for web
apps (Vercel Blob token / Neon branch URL / OIDC); add any repo-specific local secret/state files.
The dep-globs, noise allowlist, and `delete_branch_on_merge` are derived from detection (no question);
the claim-label step renders only if take-it is on and a `status:in-progress`-style label exists.

### 5. Project-specific surfaces & rules (free text, optional)

Anything detection can't know: in-app feedback tables/CLIs, funnel-health surfaces with PRD targets, infra-drift checks, tenant-scoping invariants for sub-agents, deprecation scans, repo-unique cleanup steps. Each answer lands inside the matching `PROJECT-SPECIFIC` fence (`extra-surfaces`, `scoring-overrides`, `subagent-rules`, `extra-gates`, `extra-cleanup`, `extra-guardrails`) — never woven into template-owned sections, or the next update loses it.

## Defaults summary (when the user says "just use defaults")

take-it: yes (if Issues + Actions) · plate-it: read-only · merge: detected value but still confirmed · scoring: repo-health defaults · clean-it: core (always rendered), never-discard `.env.local` for web apps · no project-specific extras.
