---
name: create-dev-workflows
description: >
  This skill should be used when the user asks to "set up dev workflow skills", "create
  plate/take/send skills for this repo", "generate the plate-it/take-it/send-it trio", "add a
  plate-it skill here", "bootstrap project workflow skills", "update the project workflow skills",
  "regenerate the dev workflow skills from the latest templates", "re-sync this repo's workflow
  skills with the plugin templates", or "adopt the legacy plate/get/send skills". Creates or
  updates the project-specific plate-it / take-it / send-it skills under a product repo's
  .claude/skills/. Run from inside the target repository.
---

# Create Dev Workflows

Generator for the project dev-workflow trio:

- **plate-it** — synthesize all work surfaces into one prioritized plate
- **take-it** — parallel issue-shipping ("take #341, #432"): one sub-agent per issue in isolated worktrees
- **send-it** — single-PR end-to-end flow with repo-specific gates

The plugin deliberately ships **no generic runtime versions** of these — only project-level skills generated here, so "plate it" in a repo always resolves to that repo's own skill. Generated skills are thin: project facts + policy gates, delegating shared mechanics to the capability skills (`ai-agent-skills:github-issues`, `sentry-triage`, `pr-shepherd`, `repo-health`, `testflight`).

## Phase 0 — locate & mode

1. Confirm cwd is a git repo with a GitHub remote: `gh repo view --json nameWithOwner,defaultBranchRef`.
2. Pick the mode:
   - `.claude/skills/{plate-it,take-it,send-it}/SKILL.md` containing a `generated-by` marker (match it anywhere in the file — older renders placed it on line 1, fixed ones right after the frontmatter) → **update mode**
   - legacy hand-written skills matching `*plate-it*`/`*get-it*`/`*send-it*` without the marker → **adopt mode**
   - neither → **create mode**

## Phase 1 — detect

Read `references/detection.md`, run `scripts/detect-capabilities.sh` from the repo root, and do the listed hand-checks (Sentry slugs via MCP, review-orchestrator agents, mobile workflows). Detection output is evidence, not truth — consequential fields (merge policy above all) get confirmed in Phase 2.

## Phase 2 — interview

Read `references/interview.md`. Ask only policy questions and unconfirmable facts: take-it wanted? plate-it write policy? merge queue vs direct (always confirmed — a wrong merge policy is the most expensive generator mistake)? command confirmations; free-text project-specific surfaces/rules (these land in PROJECT-SPECIFIC fences).

## Phase 3 — generate or update

Templates live in `references/templates/` (`plate-it`, `take-it`, `send-it`). Render rules are in each template's header: fill `{{FACTS}}`, resolve `IF:` conditionals from policy answers, keep the `generated-by` marker (it sits immediately after the closing `---` — the rendered file's frontmatter `---` must be line 1 or Claude Code won't parse it) and PROJECT-SPECIFIC fence markers, drop template-comment blocks.

- **Create mode**: render all selected skills, then **print every rendered file in full and write only after the user approves** — writing into a product repo is an outward-facing action; never write silently.
- **Update / adopt mode**: read `references/update-mode.md` first. Update = re-render + splice fences + per-file diff + approval. Adopt = side-by-side review of hand-written content, then replace the legacy prefixed skills (deleting their directories and superseded scripts on approval).
- **Naming guard**: generated names are plain (`plate-it`, `take-it`, `send-it`); check no personal skill (`~/.claude/skills/<name>`) shadows them — personal beats project for same-name skills. If one exists, stop and surface it.

## Phase 4 — verify

1. Frontmatter sanity: opening `---` is line 1 of each written file (nothing before it — Claude Code won't parse the frontmatter otherwise), name matches directory, description present, valid YAML.
2. Remind: skills load on the next session in that repo.
3. Suggest first runs: `plate it` (with `DRY_RUN=1` if a write gate was enabled), `send it` on a trivial branch, and `take #<small-issue>` once comfortable.

## Guardrails

- Never write or overwrite files in the target repo without showing the full content/diff and getting approval.
- Never delete hand-written skills except through adopt mode's reviewed replacement.
- Update mode never adds take-it to a repo that doesn't have it unless the user asks (a trio-minus-take-it is a valid steady state).
- Project-specific knowledge goes inside fences; if the user asks to hand-edit a template-owned section, offer the fence instead and explain why (updates will clobber template-owned text).
