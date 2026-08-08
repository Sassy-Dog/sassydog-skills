---
name: refresh-skills
description: >
  This skill should be used when the user asks to "refresh the sassydog skills", "refresh the
  project workflow skills", "refresh the dev workflow skills", "set up dev workflow skills",
  "configure survey-work for this repo", "configure plate-it for this repo", "set up the workflow
  skills here", "bootstrap project
  workflow skills", "update the project workflow skills", "re-sync this repo's workflow config",
  "migrate this repo to the new workflow skills", "move the workflow skills to config", or "adopt
  the legacy plate/get/send skills". Writes and re-syncs a repo's `.claude/sassy-dog/*.md` workflow
  config plus its `.claude/settings.json` plugin declaration, and migrates repos still carrying
  older generated skills under `.claude/skills/`. Run from inside the target repository.
---

# Refresh Skills

Configuration generator for the workflow family. The six skills themselves — `survey-work`,
`groom-backlog`, `take-it`, `dispatch-ready`, `send-it`, `tidy-repo` — ship generically in this
plugin. This skill writes the **per-repo config** they read:

```text
.claude/sassy-dog/<skill>.md      # YAML frontmatter (facts) + ## sections (prose)
.claude/settings.json             # enabledPlugins declaration
```

The format is `references/config-contract.md`. **Read it before writing anything.**

This skill does **not** render skill bodies. A repo that still has
`.claude/skills/{plate-it,fill-it,take-it,drain-it,send-it,clean-it}/` is on the superseded
architecture and needs **migrate mode** (Phase 3).

## Two rules that shape everything here

**Configure only what cannot be derived.** Repo slug, default branch, and `delete_branch_on_merge`
come from `gh repo view` at runtime and never appear in config. A configured value is a value that
can drift — see the drift incident recorded in `references/config-contract.md`.

**Re-verify every configured fact against live state.** Never copy a fact forward from an existing
render or config just because it is written down. `merge_queue` in particular has no `gh repo view`
equivalent and must be read from GraphQL:

```bash
gh api graphql -f query='{repository(owner:"OWNER",name:"NAME"){mergeQueue(branch:"BRANCH"){id}}}' \
  --jq '.data.repository.mergeQueue != null'
```

## Phase 0 — locate and pick the mode

Confirm cwd is a git repo with a GitHub remote:

```bash
gh repo view --json nameWithOwner,defaultBranchRef,deleteBranchOnMerge
```

Then pick exactly one mode:

| Found | Mode |
| --- | --- |
| `.claude/skills/<name>/SKILL.md` carrying a `generated-by:` marker | **migrate** (Phase 3) |
| `.claude/sassy-dog/*.md` already present | **update** (Phase 4) |
| Legacy hand-written `*plate-it*` / `*get-it*` / `*send-it*` / `*clean-it*`, no marker | **adopt** (Phase 5) |
| None of the above | **create** (Phase 6) |

**Marker recognition accepts every producer name.** Match on the `generated-by:` prefix and accept
`refresh-skills` (current), `refresh-sassydog-skills` (plugin 0.9.0–2026.7.21), and
`create-dev-workflows` (≤ 0.8.1). Match it **anywhere in the file** — older renders put it on line 1,
where the loader could not parse the frontmatter, and hand-fixes moved it. A repo whose marker is
not recognised falls through to adopt or create mode and its config is silently lost, so this
matcher is load-bearing.

## Phase 1 — detect

Read `references/detection.md`, run `scripts/detect-capabilities.sh` from the repo root, and do the
listed hand-checks (Sentry slugs via MCP, review-orchestrator agents, mobile workflows). Detection
output is evidence, not truth — consequential fields get confirmed in Phase 2.

## Phase 2 — interview

Read `references/interview.md`. Ask only policy questions and unconfirmable facts. Merge policy is
**always** confirmed against live state, never asked from memory — a wrong merge policy is the most
expensive mistake this generator can make.

In migrate mode most answers come from the existing render; ask only about what it cannot supply.

## Phase 3 — migrate mode

Converts a repo from generated skills to config. Read `references/migrate-mode.md` first.

The essential shape:

1. **Extract** facts and `BEGIN/END PROJECT-SPECIFIC` fence contents from each generated SKILL.md
2. **Re-verify** every extracted fact against live state — extracted values are *stale by default*
3. **Map** legacy names to current config files per `references/migrate-mode.md` Step 3
   (`plate-it` → `survey-work.md`, `fill-it` → `groom-backlog.md`, `drain-it` →
   `dispatch-ready.md`, `clean-it` → `tidy-repo.md`), carrying each skill's prose
4. **Write** `.claude/sassy-dog/*.md` + merge `.claude/settings.json`
5. **Preview** the full config and the exact list of directories to be deleted
6. **Delete** the old `.claude/skills/<name>/` directories only after approval

**Order is not negotiable: write config, verify, then delete.** The generated skill is the *source*
the config is extracted from. Deleting first destroys the only copy of the repo's Sentry projects,
board IDs, scan paths, and project-specific prose.

**Never touch a directory without a `generated-by:` marker.** Hand-written skills that happen to
sit alongside — `qr-ninja-design`, `what2wear-clean-it`, velovate's `terraform-apply` — are not
yours.

## Phase 4 — update mode

The repo already has `.claude/sassy-dog/*.md`. Re-run detection, re-verify every fact against live
state, and diff the result against the committed config.

**Frontmatter is regenerated; `##` prose sections are carried across verbatim.** That split is the
whole point of the format — prose is the thing a refresh must never rewrite.

Apply per file, on approval only.

## Phase 5 — adopt mode

Legacy hand-written skills with no marker. Read `references/update-mode.md`. Side-by-side review of
every hand-written section, the user decides per section (fold into config prose / promote upstream
as plugin feedback / drop), then the legacy directories are deleted on approval.

## Phase 6 — create mode

No prior state. Interview, then write config. **Print every file in full and write only after the
user approves** — writing into a product repo is outward-facing and never silent.

## Phase 7 — verify

1. Every written `.claude/sassy-dog/*.md` parses: `---` on line 1, valid YAML frontmatter, `##`
   sections intact.
2. `.claude/settings.json` is valid JSON and declares the plugin. **This is the step most likely to
   be skipped**, because everything works locally without it — plugin skills enabled only in *user*
   settings do not transfer to cloud sessions or scheduled routines, so a scheduled
   `dispatch-ready` silently finds no skill while every local session passes.
3. In migrate mode: `.claude/skills/` contains no marker-carrying directory, and every unmarked one
   still exists.
4. Remind: config is read at skill invocation, so it takes effect immediately — no session restart
   needed, unlike the old generated skills.
5. Suggest a first run: `plate it`, then `send it` on a trivial branch.

## Guardrails

- Never write into the target repo without showing full content and getting approval.
- Never delete a directory lacking a `generated-by:` marker.
- Never delete generated skills before their config is written and verified.
- Never copy a fact forward without re-verifying it against live state.
- Prose in `##` sections is user-owned: carried across verbatim, never rewritten or summarised.
- This skill always runs from the plugin; it is never copied into a consumer repo.
