---
pr_template_path: ".github/PULL_REQUEST_TEMPLATE.md"
pr_template_sections: [Summary, Changes, Verification]
preflight_commands: |
  bash scripts/preflight.sh
merge_queue: true
---

## extra-gates

**Merge policy note** — `main` has a **merge queue** (squash method). Enqueue with
`gh pr merge --auto`, with **no** method flag and **no** `--delete-branch` — GitHub rejects
`--delete-branch` outright when a queue is enabled, and `deleteBranchOnMerge` is on, so cleanup is
automatic. Confirm `isInMergeQueue` after enqueuing. PRs run the `CI` workflow (job `ci`), required
by branch protection on `main`; `ci.yml` carries the `merge_group` trigger, without which queue
entries strand.

**PR body** — `.github/PULL_REQUEST_TEMPLATE.md` carries these sections; fill it rather than
composing a body from scratch, and keep the sections in its order:

- **Summary** — what and why, one short paragraph
- **Changes** — bullet list of skills/agents/scripts touched
- **Verification** — how it was exercised (e.g. `claude --plugin-dir ~/Repos/sassy-dog/sassydog-skills`
  plus invoking the skill), or why not applicable

**README/version sync gate** — if the diff adds or removes a skill (`skills/*/SKILL.md`) or reviewer
agent (`agents/*.md`):

- `README.md`'s plugin/skill table and agent list must be updated in the same PR.
- `.claude-plugin/plugin.json` `version` must be re-stamped for release-worthy changes: run
  `bash scripts/stamp-version.sh` (monthly CalVer; **never hand-edit** — one-way ratchet, see
  `docs/VERSIONING.md`).

**Post-merge plugin update reminder** — consumer machines do NOT pick up changes automatically,
and a `version` bump is NOT the trigger: content lands on `main` on every merge while the manifest
is stamped only when some PR happens to carry a fresh stamp, so a cached copy and `main` routinely share one `version` over
different files (issue #296). After ANY merge that changes `skills/`, `agents/` or `scripts/` (skills invoke `scripts/`
at runtime through `${CLAUDE_PLUGIN_ROOT}`), remind the
operator to run `claude plugin update sassy-dog@sassydog-skills` (the marketplace-qualified name —
the bare name returns "not found") on each consumer machine. Do not verify with `ls`: the version
string cannot answer the question, and the cache holds every version ever installed. Verify by the
content comparison in README "Updating / Troubleshooting" → "`claude plugin marketplace
update` is not a plugin update", which is the single copy of that
procedure — do not restate its steps here.

## extra-guardrails

<!-- Additional send-it guardrails go here. -->
