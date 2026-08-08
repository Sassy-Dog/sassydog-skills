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
and the optional `board`, `migrations`, `codegen`, `claim_label`, and `stacked_prs` blocks. Contract:
`sassy-dog:refresh-skills` → `references/config-contract.md`.

`stack_summary` (the repo's tech stack, always present) and `stacked_prs` (stacked pull requests,
usually absent) are unrelated despite the shared word.

Repo slug and default branch are derived, never configured:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
```

**If it reads `NO_CONFIG`**, this repo is not set up. Dispatching cold sub-agents without a stack
summary or pre-flight commands produces low-quality PRs, so **stop and say so** rather than
guessing. This is the one workflow skill where `NO_CONFIG` blocks: everything it does is
outward-facing and hard to unwind. Tell the user to run
`sassy-dog:refresh-skills` first.

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

On yes, delegate to `sassy-dog:refresh-skills`. **Never write config yourself** — the
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

### Stack detection (ONLY if `stacked_prs:` is configured)

**With no `stacked_prs:` block, skip this section entirely** — every issue dispatches independently,
exactly as before. That is the default.

When it IS configured, check whether the named issues form a declared chain:

1. Read each named issue's body for a `stack:` line (groom-backlog writes it on the **bottom** issue,
   naming every member bottom → top).
2. A chain applies only when **every** member it names is in the set the user just handed you. A
   partial overlap is not a stack — say which members are missing and dispatch independently rather
   than silently shipping half a chain.
3. Confirm this repo can actually use stacks:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/stack-probe.sh --repo "<slug>"
   ```

   Exit `11` means the repo is not enabled for the preview. Say so plainly and dispatch the chain
   **serially instead** — issue by issue, waiting for each to merge — because the members depend on
   each other and parallel worktrees would collide. Do not silently fall back to parallel.
4. Depth over `stacked_prs.max_depth` → dispatch the first `max_depth` layers as a stack and hold
   the rest for a later invocation. Announce which layers were held.

Announce the resolved shape before dispatching, as in
`Taking #101 → #102 → #103 as a 3-layer stack — 1 sub-agent.`

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
`sassy-dog:github-issues` (`references/board-graphql.md`), using the board IDs from config.

**Without a board** — one call per batch via `sassy-dog:github-issues`:

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

### Stacked variant (ONLY for a chain resolved in §2)

A stack is sequential by construction — layer 2 needs layer 1's code — so it gets **ONE sub-agent in
ONE worktree building every layer in order**, not one agent per issue. Dispatching the layers to
parallel agents is the failure this shape exists to prevent: they would each branch from the default
branch and rediscover the dependency as a conflict.

Substitute steps 6–8 of the prompt above with the following; steps 1–5 (worktree confinement, never
`git stash`, no shared-interpreter installs, read the issue, follow `CLAUDE.md` and
`## subagent-rules`, run the pre-flight) apply unchanged **per layer**:

> You are shipping a STACK of {depth} GitHub issues, bottom → top: {ordered list, e.g. #101 → #102 → #103}.
> Each layer's PR targets the branch of the layer below it; the bottom targets `{default_branch}`.
>
> Work the layers **strictly in order**. For each one:
>
> 1. Branch from the layer below — `git switch -c {prefix}/issue-{N}-{slug}` while that lower branch
>    is checked out. The bottom layer branches from `{default_branch}`. **Never return to
>    `{default_branch}` between layers**; that is what breaks the chain.
> 2. Implement only that layer's issue. Keep the layers genuinely separable — if you find yourself
>    editing a lower layer's code from an upper one, STOP and report it, because the split is wrong.
> 3. Run the pre-flight and fix anything red before moving up: {preflight_commands from config}
> 4. Commit with a conventional-commit message containing a literal `Closes #{N}` line.
> 5. Push, then open the PR against the layer below:
>    `gh pr create --base <branch of the layer below, or {default_branch} for the bottom>`.
>    The body MUST contain `Closes #{N}` on its own line and cover {pr_template_sections from config}.
>
> After every layer has a PR, link them into a stack bottom → top. Pass explicit JSON — the field
> must be an array of integers, which `gh api -f` would send as strings:
>
> ```bash
> echo '{"pull_requests":[<pr numbers bottom to top>]}' \
>   | gh api "repos/{repo_slug}/stacks" -X POST --input -
> ```
>
> If that call fails, the PRs are still correct and correctly based — report the failure and let the
> coordinator link them. **A failed link is recoverable; a wrong base is not.**
>
> **Do NOT merge any layer.** Report back one line:
> `RESULT: stack=<bottom..top issue numbers> prs=<pr numbers bottom to top> linked=<yes|no> status=<opened|partial|failed> note=<one-line>`

If a middle layer fails, the layers below it are still valid, independent PRs. Report the partial
stack rather than discarding the work — the coordinator can land what exists and re-dispatch the rest.

## 6. Coordinator: watch + merge (delegated)

Use the capability skill for ALL polling, merge, and teardown mechanics — do NOT reimplement them
inline:

```
Skill: sassy-dog:pr-shepherd
Args: "Watch PRs <numbers from the RESULT lines> in <repo>. Merge policy:
       <merge_queue ? 'MERGE QUEUE — enqueue greens with gh pr merge --auto (no method flag, no
       --delete-branch), confirm isInMergeQueue, handle ejects'
                    : 'DIRECT — gh pr merge --squash --delete-branch, serialize coupled PRs'>.
       <if migrations: 'Coupled-PR concern: migrations in <migrations.dirs> (regenerate with
       <migrations.regen_command>).'>
       <if codegen: 'Coupled-PR concern: codegen (<codegen.hint>).'>
       <if a stack was dispatched: 'STACKED: PRs <bottom..top> are layers of one stack. Merge
       bottom-up only — stack-probe.sh gates this; merge-shepherd exits 23 on a blocked layer
       (re-run) and 24 when it needs a human. Tear the shared worktree down only after the TOP
       layer is terminal.'>
       After all PRs are terminal, tear down these worktrees: <paths from the batch manifest>,
       then reconcile the local default branch."
```

A stack's worktree is shared by every layer, so it appears **once** in the manifest, not once per
issue. Tearing it down after the bottom layer merges would strand the layers above it.

If `sassy-dog:pr-shepherd` is not in your available skills, STOP and tell the user to install
the plugin (`claude plugin install sassy-dog`) — do not improvise the merge loop from memory.

Run the coordinator synchronously; backgrounding it orphans PRs at "checks pending".

## 7. Final report

| Issue | PR | Status | Notes |
| --- | --- | --- | --- |
| #218 | #260 | ✅ MERGED | one-line summary |
| #240 | #261 | ⚠️ FAILED | named failing check + log excerpt |
| #216 | — | ⏭ SKIPPED | reason |

When no board is configured, clear the claim label for every MERGED row via
`sassy-dog:github-issues`' `issue-claim.sh release N1 N2` — `Closes #N` closed the issue but
does not strip labels, and a stale claim label misleads the next loop's in-flight reconcile.

Always end with: claims to unwind by hand (assignments, plus board cards or `in-progress` labels
for unshipped issues) and a next-action one-liner per failure.

## Guardrails

- **Single-writer**: sub-agents never merge or enqueue; only the coordinator does, and only for
  green PRs.
- **Never auto-rebase a CONFLICTING PR** — surface it. Expect an upper stack layer to go
  `CONFLICTING` after the layer below squash-merges; that is the normal shape, not a fault.
- Cap parallelism at 5. Don't dispatch on stubs or `blocked` issues.
- **Never split a stack across parallel agents**, and never dispatch a partially-named chain. One
  chain = one agent = one worktree, layers built in order.

Apply any `## extra-guardrails` section from config on top of these.
