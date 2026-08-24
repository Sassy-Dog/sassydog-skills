# Phase 2 — the interview

Ask ONLY what detection couldn't establish or what's policy (not fact). Use AskUserQuestion; batch into at most two rounds. Show detected values as the recommended option — the user confirms rather than recites.

## Questions

### 0. Merge policy — merge queue or direct? (ALWAYS confirmed, never remembered)

The single most expensive fact to get wrong, and the one most likely to be stale in an existing
render. **Read it from live state, then show the user what you found:**

```bash
gh api graphql -f query='{repository(owner:"OWNER",name:"NAME"){mergeQueue(branch:"BRANCH"){id configuration{mergeMethod}}}}' \
  --jq '.data.repository.mergeQueue'
```

| Result | `merge_queue` | What the skills do |
|---|---|---|
| non-null | `true` | `gh pr merge --auto`, no method flag, **no** `--delete-branch` (GitHub rejects it when a queue is enabled), confirm `isInMergeQueue` |
| `null` | `false` | `gh pr merge --squash --delete-branch` |

This plugin's own repo had `merge_queue: false` written into a generated skill after the queue was
enabled; the error only surfaced as a rejected merge. Never carry this value forward.

### 1. take-it wanted? (skip in update mode unless the user raised it)

Parallel issue-shipping is opt-in. Default **yes** if the repo has GitHub Issues + Actions and a worktree-friendly dev loop; default **no** if the repo is a prototype or the user runs strictly serial. A trio without take-it is a valid steady state — update mode must never add take-it unasked.

### 2. survey-work write policy

| Option | Meaning |
|---|---|
| **Read-only** (default for new adoptions) | Plate reports; never files. `IF:WRITE_GATE_SENTRY` off. |
| **Gated Sentry→GH auto-file** | Qualifying Sentry hits (sentry-triage gate defaults: unresolved · lastSeen ≤ 7d · userCount ≥ 2 ∨ events ≥ 5 ∨ error ∧ events ≥ 2) auto-file so the plate always hands take-it real issue numbers. Burst rail: > 5 would-file → stop and ask. |

Offer the gate defaults verbatim; record any threshold tweak in `{{SENTRY_GATE_SUMMARY}}`. Requires Sentry detected + an escalation repo.

### 2b. Sentry project — confirm a prior claim (asked ONLY when the sibling scan hit)

Never ask "which project is this repo's?" — that question invites a name match. The project is
established by the culprit check in `detection.md` (its culprits must resolve in *this* repo), and a
candidate that fails it is not offered to the user at all; it becomes `sentry: none`.

Ask this question only when the best-effort sibling-checkout scan found the verified slug already
declared in another repo's `.claude/sassy-dog/survey-work.md`. Name the other repo and its config
path, and **default the answer to "it is already owned — do not configure it here"**: two repos
declaring one project double-report the same Sentry issues while both plates still look complete,
so a wrong "yes" is invisible. Configure it here only on an explicit confirmation that this repo is
the right owner (or that both genuinely emit into it).

A *miss* here asks nothing and blocks nothing. The scan is secondary by design: a cloud session has
no sibling checkouts on disk, so it finds nothing there — which is exactly why the culprit check,
not this question, is the guard that has to hold.

### 3. Merge policy — always confirm, never trust the probe alone

Show the detected value (`merge_queue: true/false/null` + repo settings) and have the user confirm queue vs direct. State the stakes: a wrong "queue" guess means `--auto` calls that silently never merge; a wrong "direct" guess bypasses queue serialization. Sets `IF:MERGE_QUEUE` and `{{MERGE_POLICY_NOTE}}`.

### 3b. groom-backlog / dispatch-ready wanted? (opt-in pair; skip in update mode unless raised)

Both are **board-optional**: with `IF:BOARD` they drive the board's **Ready** status column; boardless renders drive the `ready` + `in-progress` labels instead (the degraded-board contract — Ready column → `ready` label, In progress + assignee → assignee @me + `in-progress`, failure demotion → strip labels + `blocked` + comment). dispatch-ready additionally requires take-it. Default **no** unless the repo already runs a Ready-based flow (board column or `ready` label). If dispatch-ready is wanted, confirm two policy facts:

- `{{MAX_IN_FLIGHT}}` — concurrent in-flight cap (default **5**).
- `{{DISPATCH_MODEL}}` — model for dispatched sub-agents (default **`opus`** = latest Opus alias, for cost control; the coordinator tick stays on the session model). Record verbatim in the rendered §4.
- If `IF:BOARD`: pin `{{BOARD_READY_OPTION_ID}}` (and Backlog id for bounce-backs) alongside the other board IDs.
- groom-backlog: confirm `{{GOTCHA_SUMMARY}}` — the one-line list of repo gotchas every refined issue body should carry (e.g. codegen paths, i18n catalogs, migration policy). **Ask for invariants, not status.** A trap that stays true until the architecture changes belongs here; an issue number with a state claim (`#334 … remains`), an "as of `<date>`", or a roadmap position does not — nothing recomputes this field, so a status written here rots in place and is copied verbatim into issue bodies (config-contract.md, "`gotcha_summary` carries INVARIANTS ONLY"). If the user offers one, say why and rewrite it with them.

### 3c. Stacked PRs? (opt-in; default NO — skip in update mode unless raised)

Asked only when take-it or dispatch-ready is on, and only after the merge-policy question, because the two interact.

Enabling writes the `stacked_prs:` block and lets `groom-backlog` propose a `stack:` chain and the dispatchers build one. **Default no.** Do not ask this as "do you want the new feature?" — ask whether this repo has work that arrives as *genuinely dependent chains* (schema then consumer, extract then refactor). A repo whose issues are mostly independent gains nothing and takes on a sequential dispatch shape for free.

State two things plainly before the user answers:

- **The preview is still rolling out per-repo.** Run `sassy-dog:pr-shepherd`'s `scripts/stack-probe.sh --repo <slug>` and report the result. Exit 11 means this repo cannot use stacks *yet* — enabling the block is still legal and simply dormant until GitHub enables it, but say so rather than letting the user assume it works today.
- **If `merge_queue: true`,** dispatchers may open stacks that `pr-shepherd` will refuse to land (exit 24) until GitHub finishes shipping queue support. That is a real cost; confirm the user accepts landing those by hand.

`{{STACK_MAX_DEPTH}}` — layer cap (default **4**). Beyond it the dispatchers fall back to independent PRs.

### 4. Commands (fact confirmation, free-text)

- Pre-flight commands (`{{PREFLIGHT_COMMANDS}}`) — propose from the runner; user edits.
- Migration regen command (`{{MIGRATION_REGEN_COMMAND}}`) if `IF:MIGRATIONS`.
- Codegen command + output dirs if `IF:CODEGEN`.
- Secret bootstrap command (`{{SECRET_BOOTSTRAP_CMD}}`) if detection reports a `secret_manager` (`.envrc`/`doppler.yaml`) — the one-liner survey-work §1 runs to load managed secrets BEFORE its env presence probes (propose `eval "$(doppler secrets download --no-file --format env 2>/dev/null)"` for Doppler repos). Confirming it sets `IF:SECRET_BOOTSTRAP`. In update/adopt mode, an "environment bootstrap" note sitting in a PROJECT-SPECIFIC fence (typically under §2.C — too late, the §1 probes already ran) is the tell: offer to promote that command into this placeholder.

### 4b. tidy-repo never-discard files (fact confirmation; tidy-repo is core, so always asked)

tidy-repo auto-discards untracked noise against an allowlist — confirm the **never-discard** list of
gitignored-but-precious files it must leave alone (`{{NEVER_DISCARD}}`). Propose `.env.local` for web
apps (Vercel Blob token / Neon branch URL / OIDC); add any repo-specific local secret/state files.
The dep-globs, noise allowlist, and `delete_branch_on_merge` are derived from detection (no question);
the claim-label step renders only if take-it is on and a `status:in-progress`-style label exists.

### 5. Project-specific surfaces & rules (free text, optional)

Anything detection can't know: in-app feedback tables/CLIs, funnel-health surfaces with PRD targets, infra-drift checks, tenant-scoping invariants for sub-agents, deprecation scans, repo-unique cleanup steps. Each answer lands inside the matching `PROJECT-SPECIFIC` fence (`extra-surfaces`, `scoring-overrides`, `subagent-rules`, `extra-gates`, `extra-cleanup`, `extra-guardrails`) — never woven into template-owned sections, or the next update loses it.

## Defaults summary (when the user says "just use defaults")

delegation: plugin-backed · take-it: yes (if Issues + Actions) · survey-work: read-only · merge: detected value but still confirmed · scoring: repo-health defaults · tidy-repo: core (always rendered), never-discard `.env.local` for web apps · secret bootstrap: only when detection finds a `secret_manager` (Doppler repos get the `doppler secrets download` eval) · **stacked PRs: off** · no project-specific extras.
