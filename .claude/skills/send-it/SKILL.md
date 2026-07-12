---
name: send-it
description: >
  Ship a PR end-to-end in the ai-agent-skills repo — worktree audit, pre-flight guardrails,
  template-compliant PR body, commit, push, watch checks, merge, clean up. Use when the user
  says "send it", "ship it", "open the PR", "create a PR", or asks to merge a branch.
  ai-agent-skills-specific.
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: send-it | template-version: 1 -->

# ai-agent-skills Send-It

End-to-end PR flow for this repo, in order: worktree audit → pre-flight guardrails → PR body → commit/push → watch + merge (delegated to `ai-agent-skills:pr-shepherd`).

**Merge policy: direct squash merge** — `gh pr merge --squash --delete-branch`. There is no merge queue and auto-merge is disabled; never use `--auto` (it would silently never merge). Repo setting `deleteBranchOnMerge` is off, so the `--delete-branch` flag is what cleans up. PRs run the `CI` workflow (job `ci`), required by branch protection on `main` — pr-shepherd watches it before merging.

## 1. Worktree audit

**Non-negotiable, even on a "trivial" one-file PR.** Run first:

```bash
git status --short
git stash list
```

For **every** entry (modified, added, deleted, untracked — including pre-existing dirt), pick exactly one action and announce it before proceeding:

| Action | When | How |
|---|---|---|
| **Ship with this PR** | Part of the same logical change | `git add <file>` — explicit paths, never `git add -A` |
| **Ship as a separate PR** | Real work, unrelated scope | Branch + commit it FIRST on its own branch, push, open PR; then return |
| **Stash for later** | Mid-flight WIP | `git stash push -m "<descriptive name>" -- <files>` |
| **Discard** | Truly unwanted | `git restore <file>` / `rm <file>` — only after confirming |

Untracked files (`??`) are the highest-risk class: invisible to `git diff`, easy to lose. Do not proceed until `git status --short` is empty OR every entry has a confirmed disposition. "I'll just stage the file I changed" is the failure mode this step exists to prevent.

## 2. Pre-flight guardrails

Mirror the `CI` workflow locally (no build step in this repo; CI runs this same script):

```bash
bash scripts/preflight.sh
```

One call runs every gate — shellcheck (`-S warning`), frontmatter sanity, the positional-token and legacy-name guards, manifest JSON, markdownlint — plus best-effort actionlint. Any gate fails → fix before commit (`bash scripts/preflight.sh --fix` auto-fixes markdownlint findings first). Never push a known-red change.

<!-- BEGIN PROJECT-SPECIFIC: extra-gates -->
**README/version sync gate** — if the diff adds or removes a skill (`skills/*/SKILL.md`) or reviewer agent (`agents/*.md`):

- `README.md`'s plugin/skill table and agent list must be updated in the same PR.
- `.claude-plugin/plugin.json` `version` must be bumped for release-worthy changes.

```bash
git diff --name-only origin/main | grep -qE '^(skills/[^/]+/SKILL\.md|agents/)' \
  && { git diff --name-only origin/main | grep -q '^README.md$' || echo "⚠️ skill/agent set changed but README.md untouched — sync the table or justify"; }
```

**Post-release plugin update reminder** — if the merged diff bumped `version` in `.claude-plugin/plugin.json`: consumer machines do NOT pick up releases automatically. After the merge, remind the operator to run `claude plugin update ai-agent-skills@sassy-dog-skills` (marketplace-qualified name — the bare name returns "not found") on each consumer machine, then re-check that `ls ~/.claude/plugins/cache/sassy-dog-skills/ai-agent-skills/` shows the new version. See README "Updating / Troubleshooting".
<!-- END PROJECT-SPECIFIC -->

## 3. Template-compliant PR body

**MANDATORY CHECKPOINT.** No `.github/PULL_REQUEST_TEMPLATE.md` exists in this repo — use this standard body, every section present:

- [ ] **Summary** — what and why, one short paragraph
- [ ] **Changes** — bullet list of skills/agents/scripts touched
- [ ] **Verification** — how it was exercised (e.g. `claude --plugin-dir ~/Repos/sassy-dog/ai-agent-skills` + invoked the skill), or why not applicable

Never pass a one-liner `--body "fix bug"` that bypasses the template.

### Issue + tracker references (close-on-merge rules)

- Closing an issue requires a literal `Closes #<N>` (or `Fixes`/`Resolves`) **on its own line** in the body — one line per issue; comma lists don't reliably parse.
- **A title parenthetical like `fix(web): foo (#240)` is a hyperlink, NOT a close trigger** — the classic shipped-but-still-open cause.
- Partial/follow-up work → omit the keyword, leave the issue open.

## 4. Commit, push, watch, merge

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): short imperative

Why, briefly.

Closes #<N>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push -u origin "$(git branch --show-current)"
gh pr create --title "..." --body "..."   # template-compliant body from §3
```

**Watch + merge (delegated).** Do NOT reimplement polling/merging inline:

Skill: `ai-agent-skills:pr-shepherd`
Args: "Shepherd PR #<N> in Sassy-Dog/ai-agent-skills: mergeable check first, watch checks, then squash-merge with `--delete-branch`. After merge, reconcile local main and delete the feature branch."

If `ai-agent-skills:pr-shepherd` is not in your available skills, STOP and tell the user to install the plugin (`claude plugin install ai-agent-skills`) — do not improvise the merge flow from memory.

## Guardrails

- Never silently scope to "the file we just edited" — §1 in full, every time.
- Never push past a failing pre-flight check; never merge past a red CI.
- Never force-push main.
- Draft PRs: stop after `gh pr create` — the author flips to ready.

<!-- BEGIN PROJECT-SPECIFIC: extra-guardrails -->
<!-- END PROJECT-SPECIFIC -->
