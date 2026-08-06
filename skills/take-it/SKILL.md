---
name: take-it
description: >
  Parallel issue-shipping. The user names one or more GitHub issue numbers; dispatch one sub-agent
  per issue (each in its own git worktree), implement the fix, open a PR with Closes #N, and a
  coordinator loop polls to auto-merge greens and surface failures. Use when the user says "take
  #341, #432", "take #N", "take it #N", "go take #N and #M", "pick up #N", "knock out #N", or any
  variant handing over a list of GitHub issue numbers to ship in parallel. Reads the current repo's
  settings from `.claude/sassy-dog/take-it.md`.
---

# Take-It

Parallel issue-shipping: the user hands you GitHub issue numbers; this skill ships them
concurrently. It is the *executor* — it assumes the user already knows what they want shipped and
does not re-prioritize.

## 1. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/take-it.md" 2>/dev/null || echo "NO_CONFIG"`

Frontmatter supplies `stack_summary`, `preflight_commands`, `pr_template_sections`, `merge_queue`,
and the optional `board`, `migrations`, `codegen`, and `claim_label` blocks. Contract:
`ai-agent-skills:refresh-skills` → `references/config-contract.md`.

Repo slug and default branch are derived, never configured:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
```

**If it reads `NO_CONFIG`**, this repo is not set up. Dispatching cold sub-agents without a stack
summary or pre-flight commands produces low-quality PRs, so **stop and say so** rather than
guessing. This is the one workflow skill where `NO_CONFIG` blocks: everything it does is
outward-facing and hard to unwind. Tell the user to run
`ai-agent-skills:refresh-skills` first.

### Offer to set this repo up

Then offer to fix it — this is the next step, so ask now:

- **If `.claude/skills/take-it/SKILL.md` exists with a `generated-by:` marker** — this repo is on the
  superseded generated-skills architecture. Say so concretely: *"This repo has a generated
  `take-it` I can migrate — I'd extract its config, show you the result, and remove the old skill
  only after you approve. Want me to?"*
- **Otherwise** — nothing to extract from: *"I can set this repo up. It takes a few questions about
  how this repo works. Want me to?"*

Naming which path applies matters: one of them ends in deleting a file the user may not know is
there.

On yes, delegate to `ai-agent-skills:refresh-skills`. **Never write config yourself** — the
refresher owns the contract, and a skill that writes its own forks the format the moment the
contract moves.

**Offer once per session.** Running deliberately in an unconfigured repo is legitimate; re-prompting
every invocation is noise. If declined, carry on and don't raise it again.

## 2. Parse the issue list

**The numbers are ALWAYS GitHub issue numbers, NEVER list positions.** "take 218 219" means
`gh issue view 218` and `gh issue view 219`. Echo the resolved list before dispatching, as in
"Taking #218, #219 — 2 sub-agents." Empty or ambiguous input ("do the easy ones") → STOP and ask.
Cap at **5 sub-agents per dispatch**; queue the rest for the next round.

### Pre-flight smell test

| Pattern in title or body | Action |
| --- | --- |
| Title starts with `Assess`, `Investigate`, `Evaluate`, `Spike:`, `Decide:` | Flag — research doc, not implementation; confirm before dispatching |
| Body is a batch checklist of many independent sub-items | Flag — dispatch as ONE PR or a coherent subset; confirm intent |
| Body contains `## Open questions` / `## Decision criteria` | Flag — decision not yet made |

## 3. Pre-flight per issue

```bash
gh issue view N --json number,title,state,labels,body,assignees
```

Skip and announce if: not OPEN; `blocked` label; assignee already set; the board card is already
In progress/In review (when `board:` is configured) or the `in-progress` label is present (when it
is not); or the body is a stub under 80 characters — but **check `gh issue view N --comments`
before calling it a stub**, since scope often lives in a follow-up comment.

For survivors capture title, body, and labels. Map label → conventional-commit prefix: `bug`→`fix`,
`enhancement`→`feat`, `documentation`→`docs`, else `chore`.

## 4. Claim each issue

Best-effort, so parallel sessions don't double-pick.

**With `board:` configured** — set the assignee and move the card to In progress per
`ai-agent-skills:github-issues` (`references/board-graphql.md`), using the board IDs from config.

**Without a board** — one call per batch via `ai-agent-skills:github-issues`:

```bash
issue-claim.sh claim N1 N2
```

Idempotent: ensures the `in-progress` label exists, sets assignee @me, adds `in-progress`, strips
`ready`, **skips issues already assigned to someone else** (the double-pick guard), and retries
transient GitHub failures.

Claim failures are logged, never fatal — the PR's `Closes #N` closes the issue regardless.

## 5. Dispatch sub-agents in parallel

**First, fast-forward the local default branch.** Worktrees branch from local HEAD, not origin; a
stale base lands the PR `CONFLICTING`:

```bash
git fetch origin --quiet
git switch "$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)" >/dev/null 2>&1 \
  && git pull --ff-only
```

**Issue ALL Agent calls in a single message** with `isolation: "worktree"`. **Record the batch
manifest** as results return — `{issue, pr, worktreePath, worktreeBranch}` — somewhere durable such
as `.git/take-it-batch.json`, so a crashed coordinator's worktrees stay reclaimable.

**Sub-agent prompt template** (self-contained — the agent has zero conversation context):

> You are shipping GitHub issue **#{N}** in this repo ({stack_summary from config}).
>
> **Issue title:** {title} · **Labels:** {labels}
> **Issue body:**
>
> ```
> {body}
> ```
>
> **Your job:**
>
> 1. **Stay inside your assigned worktree.** cwd resets between Bash calls — prefix every call with
>    `cd <your worktree path> &&`, and verify `pwd && git rev-parse --show-toplevel && git branch
>    --show-current` before your first edit. **Never `git stash`** (worktrees share one `.git`; a
>    stash collides with the other parallel agents). Commit WIP to your branch or discard
>    explicitly. **Never run an editable/dev install into a shared interpreter or global store** —
>    under parallel worktree agents, whoever installs last repoints imports for everyone, so a green
>    test run may silently be testing another agent's source (Python: `pip install -e` writes the
>    editable link into the shared interpreter's `site-packages`; Node: `npm link` and global
>    installs are the same trap). Work isolated: create a throwaway venv/env *inside your worktree*
>    and never commit it, or run against your tree without installing. Verify the import resolves
>    inside YOUR worktree before trusting a green run.
> 2. Read the issue carefully. If scope is genuinely unclear after the body and linked issues/PRs,
>    STOP and report back — do not guess.
> 3. Implement the change following the repo's `CLAUDE.md`.
> 4. Follow the repo-specific implementation rules from the config's `## subagent-rules` section.
> 5. Run the pre-flight locally and fix anything red: {preflight_commands from config}
> 6. Commit on branch `{prefix}/issue-{N}-{slug}` with a conventional-commit message containing a
>    literal `Closes #{N}` line.
> 7. Push and open a PR — the body MUST contain `Closes #{N}` on its own line, and must cover
>    {pr_template_sections from config}.
> 8. **Do NOT merge.** Report back: `RESULT: pr=<N> branch=<name> status=<opened|skipped|failed>
>    note=<one-line>`

## 6. Coordinator: watch + merge (delegated)

Use the capability skill for ALL polling, merge, and teardown mechanics — do NOT reimplement them
inline:

```
Skill: ai-agent-skills:pr-shepherd
Args: "Watch PRs <numbers from the RESULT lines> in <repo>. Merge policy:
       <merge_queue ? 'MERGE QUEUE — enqueue greens with gh pr merge --auto (no method flag, no
       --delete-branch), confirm isInMergeQueue, handle ejects'
                    : 'DIRECT — gh pr merge --squash --delete-branch, serialize coupled PRs'>.
       <if migrations: 'Coupled-PR concern: migrations in <migrations.dirs> (regenerate with
       <migrations.regen_command>).'>
       <if codegen: 'Coupled-PR concern: codegen (<codegen.hint>).'>
       After all PRs are terminal, tear down these worktrees: <paths from the batch manifest>,
       then reconcile the local default branch."
```

If `ai-agent-skills:pr-shepherd` is not in your available skills, STOP and tell the user to install
the plugin (`claude plugin install ai-agent-skills`) — do not improvise the merge loop from memory.

Run the coordinator synchronously; backgrounding it orphans PRs at "checks pending".

## 7. Final report

| Issue | PR | Status | Notes |
| --- | --- | --- | --- |
| #218 | #260 | ✅ MERGED | one-line summary |
| #240 | #261 | ⚠️ FAILED | named failing check + log excerpt |
| #216 | — | ⏭ SKIPPED | reason |

When no board is configured, clear the claim label for every MERGED row via
`ai-agent-skills:github-issues`' `issue-claim.sh release N1 N2` — `Closes #N` closed the issue but
does not strip labels, and a stale claim label misleads the next loop's in-flight reconcile.

Always end with: claims to unwind by hand (assignments, plus board cards or `in-progress` labels
for unshipped issues) and a next-action one-liner per failure.

## Guardrails

- **Single-writer**: sub-agents never merge or enqueue; only the coordinator does, and only for
  green PRs.
- **Never auto-rebase a CONFLICTING PR** — surface it.
- Cap parallelism at 5. Don't dispatch on stubs or `blocked` issues.

Apply any `## extra-guardrails` section from config on top of these.
