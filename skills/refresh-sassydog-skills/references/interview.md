# Phase 2 — the interview

Ask ONLY what detection couldn't establish or what's policy (not fact). Use AskUserQuestion; batch into at most two rounds. Show detected values as the recommended option — the user confirms rather than recites.

## Questions

### 0. Delegation mode — plugin-backed or independent?

Ask in **create and adopt mode**. In **update mode never re-ask**: any `vendored-by:` marker under
`.claude/skills/*/SKILL.md` → independent (re-sync silently per `references/independent-mode.md`);
none → plugin-backed. Revisit only if the user raises a switch ("make this repo independent",
"switch back to plugin mode").

| Option | Meaning |
|---|---|
| **Plugin-backed** (default) | Generated skills delegate to the `ai-agent-skills` plugin's capability skills. Smallest repo footprint; every machine that runs them needs the plugin installed (`claude plugin install ai-agent-skills`). |
| **Independent** | Refresh vendors the needed capability skills into this repo's `.claude/skills/` (pr-shepherd, github-issues, repo-cleanup, repo-health, plus sentry-triage/testflight when detected) so a fresh clone works with no plugin install. Refresh re-syncs the copies; hand-edits to vendored files are overwritten on the next refresh. |

Sets `IF:INDEPENDENT` and `{{CAP_NS}}` (`ai-agent-skills:` when plugin-backed, empty when
independent). Independent → read `references/independent-mode.md` before Phase 3.

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

Both are **board-optional**: with `IF:BOARD` they drive the board's **Ready** status column; boardless renders drive the `ready` + `in-progress` labels instead (the degraded-board contract — Ready column → `ready` label, In progress + assignee → assignee @me + `in-progress`, failure demotion → strip labels + `blocked` + comment). drain-it additionally requires take-it. Default **no** unless the repo already runs a Ready-based flow (board column or `ready` label). If drain-it is wanted, confirm two policy facts:

- `{{MAX_IN_FLIGHT}}` — concurrent in-flight cap (default **5**).
- `{{DISPATCH_MODEL}}` — model for dispatched sub-agents (default **`opus`** = latest Opus alias, for cost control; the coordinator tick stays on the session model). Record verbatim in the rendered §4.
- If `IF:BOARD`: pin `{{BOARD_READY_OPTION_ID}}` (and Backlog id for bounce-backs) alongside the other board IDs.
- fill-it: confirm `{{GOTCHA_SUMMARY}}` — the one-line list of repo gotchas every refined issue body should carry (e.g. codegen paths, i18n catalogs, migration policy).

### 4. Commands (fact confirmation, free-text)

- Pre-flight commands (`{{PREFLIGHT_COMMANDS}}`) — propose from the runner; user edits.
- Migration regen command (`{{MIGRATION_REGEN_COMMAND}}`) if `IF:MIGRATIONS`.
- Codegen command + output dirs if `IF:CODEGEN`.
- Secret bootstrap command (`{{SECRET_BOOTSTRAP_CMD}}`) if detection reports a `secret_manager` (`.envrc`/`doppler.yaml`) — the one-liner plate-it §1 runs to load managed secrets BEFORE its env presence probes (propose `eval "$(doppler secrets download --no-file --format env 2>/dev/null)"` for Doppler repos). Confirming it sets `IF:SECRET_BOOTSTRAP`. In update/adopt mode, an "environment bootstrap" note sitting in a PROJECT-SPECIFIC fence (typically under §2.C — too late, the §1 probes already ran) is the tell: offer to promote that command into this placeholder.

### 4b. clean-it never-discard files (fact confirmation; clean-it is core, so always asked)

clean-it auto-discards untracked noise against an allowlist — confirm the **never-discard** list of
gitignored-but-precious files it must leave alone (`{{NEVER_DISCARD}}`). Propose `.env.local` for web
apps (Vercel Blob token / Neon branch URL / OIDC); add any repo-specific local secret/state files.
The dep-globs, noise allowlist, and `delete_branch_on_merge` are derived from detection (no question);
the claim-label step renders only if take-it is on and a `status:in-progress`-style label exists.

### 5. Project-specific surfaces & rules (free text, optional)

Anything detection can't know: in-app feedback tables/CLIs, funnel-health surfaces with PRD targets, infra-drift checks, tenant-scoping invariants for sub-agents, deprecation scans, repo-unique cleanup steps. Each answer lands inside the matching `PROJECT-SPECIFIC` fence (`extra-surfaces`, `scoring-overrides`, `subagent-rules`, `extra-gates`, `extra-cleanup`, `extra-guardrails`) — never woven into template-owned sections, or the next update loses it.

## Defaults summary (when the user says "just use defaults")

delegation: plugin-backed · take-it: yes (if Issues + Actions) · plate-it: read-only · merge: detected value but still confirmed · scoring: repo-health defaults · clean-it: core (always rendered), never-discard `.env.local` for web apps · secret bootstrap: only when detection finds a `secret_manager` (Doppler repos get the `doppler secrets download` eval) · no project-specific extras.
