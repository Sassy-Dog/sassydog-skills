---
pr_template_path: ""
pr_template_sections: [Summary, Changes, Verification]
preflight_commands: |
  bash scripts/preflight.sh
coauthor: Claude Opus 5 (1M context) <noreply@anthropic.com>
merge_queue: false
---

## extra-gates

**Merge policy note** — direct squash merge (`gh pr merge --squash --delete-branch`). There is no
merge queue and auto-merge is disabled; never use `--auto`, which would silently never merge. The
repo setting `deleteBranchOnMerge` is off, so `--delete-branch` is what cleans up. PRs run the `CI`
workflow (job `ci`), required by branch protection on `main`.

**PR body** — no `.github/PULL_REQUEST_TEMPLATE.md` exists; use the three sections above:

- **Summary** — what and why, one short paragraph
- **Changes** — bullet list of skills/agents/scripts touched
- **Verification** — how it was exercised (e.g. `claude --plugin-dir ~/Repos/sassy-dog/ai-agent-skills`
  plus invoking the skill), or why not applicable

**README/version sync gate** — if the diff adds or removes a skill (`skills/*/SKILL.md`) or reviewer
agent (`agents/*.md`):

- `README.md`'s plugin/skill table and agent list must be updated in the same PR.
- `.claude-plugin/plugin.json` `version` must be re-stamped for release-worthy changes: run
  `bash scripts/stamp-version.sh` (monthly CalVer; **never hand-edit** — one-way ratchet, see
  `docs/VERSIONING.md`).

**Post-release plugin update reminder** — if the merged diff bumped `version` in
`.claude-plugin/plugin.json`, consumer machines do NOT pick up releases automatically. After the
merge, remind the operator to run `claude plugin update ai-agent-skills@sassy-dog-skills` (the
marketplace-qualified name — the bare name returns "not found") on each consumer machine, then
re-check that `ls ~/.claude/plugins/cache/sassy-dog-skills/ai-agent-skills/` shows the new version.
See README "Updating / Troubleshooting".

## extra-guardrails

<!-- Additional send-it guardrails go here. -->
