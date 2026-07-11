<!--
TEMPLATE: send-it · version 1
Render rules: see plate-it.template.md header. Same conventions.
-->
---
name: send-it
description: >
  Ship a PR end-to-end in the {{PROJECT_NAME}} repo — worktree audit, pre-flight CI guardrails,
  <!-- IF:MIGRATIONS -->migration-freshness gate, <!-- ENDIF --><!-- IF:CODEGEN -->codegen-freshness gate, <!-- ENDIF -->template-compliant PR body, commit, push,

watch CI, merge, clean up. Use when the user says "send it", "ship it", "open the PR",
  "create a PR", or asks to merge a branch. {{PROJECT_NAME}}-specific
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: send-it | template-version: 1 -->

# {{PROJECT_NAME}} Send-It

End-to-end PR flow for this repo, in order: worktree audit → freshness gates → pre-flight guardrails → PR body → commit/push → watch + merge (delegated to `ai-agent-skills:pr-shepherd`).

{{MERGE_POLICY_NOTE}}

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

<!-- IF:MIGRATIONS -->
## 2. Migration freshness

Schema source of truth changed ⇒ a generated migration must ship alongside it:

```bash
CHANGED=$( { git diff --name-only origin/{{DEFAULT_BRANCH}}; git ls-files --others --exclude-standard; } | sort -u )
if echo "$CHANGED" | grep -q '^{{SCHEMA_DIR}}'; then
  {{MIGRATION_REGEN_COMMAND}}        # emits a new migration if the schema drifted
  git status --short {{MIGRATION_DIRS}}
fi
```

New migration produced → stage and commit it **with** the schema change. Nothing produced → already in lockstep.

**Destructive-SQL guard** — never ship data-losing SQL; write a data-preserving multi-step migration instead:

```bash
MIGS=$(echo "$CHANGED" | grep '^{{MIGRATION_DIRS}}.*\.sql$' || true)
[ -n "$MIGS" ] && echo "$MIGS" | xargs grep -ilE 'TRUNCATE|DROP TABLE|DROP COLUMN|ALTER TABLE .* DROP' 2>/dev/null \
  && echo "⛔ Destructive SQL in a changed migration — rewrite before shipping."
```
<!-- ENDIF -->
<!-- IF:CODEGEN -->
## 2{{CODEGEN_SECTION_SUFFIX}}. Codegen freshness

Never ship stale generated artifacts. If the schema/source the generator reads changed, re-run it and commit the regenerated output with the change:

```bash
{{CODEGEN_COMMAND}}
git status --short {{CODEGEN_OUTPUT_DIRS}}
```
<!-- ENDIF -->

## 3. Pre-flight CI guardrails

Mirror CI locally, scoped to changed paths — seconds locally beats a CI round-trip:

```bash
{{PREFLIGHT_COMMANDS}}
```

Any check fails → fix before commit. Never push and rely on CI to surface it.

<!-- IF:REVIEW_ORCHESTRATOR -->
## 3.5 Design-level review pass

Lint/type/test can't catch design regressions. Before drafting the PR body:

```
Agent({ subagent_type: "{{REVIEW_ORCHESTRATOR_AGENT}}",
        prompt: "Review the staged diff vs origin/{{DEFAULT_BRANCH}} for this PR. <one-line scope>" })
```

Blocking findings → fix and re-run. Nits → roll in or note "Known and accepted" in the PR body.
<!-- ENDIF -->

<!-- BEGIN PROJECT-SPECIFIC: extra-gates -->
<!-- END PROJECT-SPECIFIC -->

## 4. Template-compliant PR body

**MANDATORY CHECKPOINT.** The body must contain the sections from `{{PR_TEMPLATE_PATH}}`:

{{PR_TEMPLATE_SECTION_CHECKLIST}}

Never pass a one-liner `--body "fix bug"` that bypasses the template.

### Issue + tracker references (close-on-merge rules)

- Closing an issue requires a literal `Closes #<N>` (or `Fixes`/`Resolves`) **on its own line** in the body — one line per issue; comma lists don't reliably parse.
- **A title parenthetical like `fix(web): foo (#240)` is a hyperlink, NOT a close trigger** — the classic shipped-but-still-open cause.
<!-- IF:SENTRY -->
- Fixing a Sentry issue: add `Fixes <SENTRY-SHORT-ID>` on its own line (the Sentry↔GitHub integration only parses the literal keyword form).
<!-- ENDIF -->
- Partial/follow-up work → omit the keyword, leave the issue open.

## 5. Commit, push, watch, merge

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): short imperative

Why, briefly.

Closes #<N>

Co-Authored-By: {{COAUTHOR_LINE}}
EOF
)"
git push -u origin "$(git branch --show-current)"
gh pr create --title "..." --body "..."   # template-compliant body from §4
```

**Watch + merge (delegated).** Do NOT reimplement polling/merging inline:

Skill: `ai-agent-skills:pr-shepherd`
Args: "Shepherd PR #<N> in {{REPO_SLUG}}: mergeable check first, watch checks, then <!-- IF:MERGE_QUEUE -->enqueue via merge queue (`--auto`, no method flag, confirm isInMergeQueue)<!-- ELSE -->squash-merge with `--delete-branch`<!-- ENDIF -->. After merge, reconcile local {{DEFAULT_BRANCH}} and delete the feature branch."

If `ai-agent-skills:pr-shepherd` is not in your available skills, STOP and tell the user to install the plugin (`claude plugin install ai-agent-skills`) — do not improvise the merge flow from memory.

## Guardrails

- Never silently scope to "the file we just edited" — §1 in full, every time.
<!-- IF:MIGRATIONS -->
- Never ship a schema change without its migration; never ship destructive SQL.
<!-- ENDIF -->
- Never push past a failing pre-flight check; never merge past a red CI.
- Never force-push {{DEFAULT_BRANCH}}.
- Draft PRs: stop after `gh pr create` — the author flips to ready.

<!-- BEGIN PROJECT-SPECIFIC: extra-guardrails -->
<!-- END PROJECT-SPECIFIC -->
