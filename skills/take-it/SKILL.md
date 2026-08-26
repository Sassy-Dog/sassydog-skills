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

!`root="$(git rev-parse --show-toplevel 2>/dev/null)"; echo "CONFIG_SOURCE: ${root:-<not a git repo>}"; cat "$root/.claude/sassy-dog/take-it.md" 2>/dev/null || echo "NO_CONFIG"`

**Check `CONFIG_SOURCE` before using any of this.** It is the repo root resolved from the
**session's** working directory at skill-load time — not necessarily the repo you are about to act
on — and cwd resets between Bash calls, so you cannot influence it. If it names a repo other than
the one you are working in, **discard the block above**, read that repo's own
`.claude/sassy-dog/take-it.md` by absolute path, and use that instead. Config is meant to be applied
exactly as written, so the wrong one silently applies another repo's rules: on 2026-08-18 two agents
shipping in `sassydog-routines` and `sassydog-skills` were each handed `platform`'s Terraform gates,
and caught it only by noticing the mismatch themselves.

Frontmatter supplies `stack_summary`, `preflight_commands`, `pr_template_sections`, `merge_queue`,
`review_site`, and the optional `board`, `migrations`, `codegen`, `claim_label`, and `stacked_prs`
blocks. Contract: `sassy-dog:setup-config` → `references/config-contract.md`.

`stack_summary` (the repo's tech stack, always present) and `stacked_prs` (stacked pull requests,
usually absent) are unrelated despite the shared word.

**`review_site:` decides WHERE this skill's review gate runs** — `agent`, each sub-agent reviewing
its own diff before it opens a PR (§5 step 6), or `coordinator`, §6 reviewing each PR after it
opens and before it merges. **Absent selects `agent`**, the fail-safe site. It never decides
*whether* a review runs or *which* agent runs it. That is `review_agent:`'s resolution order, owned
by `send-it` and unchanged by this key — read it from `sassy-dog:setup-config` →
`references/config-contract.md` (`review_agent`) rather than re-deriving it here. Resolve the agent
by that order once per invocation and reuse the resolved name everywhere below.

Repo slug and default branch are derived, never configured:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
```

**If it reads `NO_CONFIG`**, this repo is not set up. Dispatching cold sub-agents without a stack
summary or pre-flight commands produces low-quality PRs, so **stop and say so** rather than
guessing. This is the one workflow skill where `NO_CONFIG` blocks: everything it does is
outward-facing and hard to unwind. Tell the user to run
`sassy-dog:setup-config` first.

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

On yes, delegate to `sassy-dog:setup-config`. **Never write config yourself** — the
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

**Substitute the resolved review agent into step 6 of the template below when `review_site` is
`agent`.** When it is `coordinator`, drop step 6 from the prompt entirely and review in §6 instead —
never drop it from both. When the resolution order yields nothing (`review_agent: skip`), drop the
step and say so once in the §7 report; a review nobody ran and a review nobody mentioned are the
same thing to the reader.

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
> 6. **Run the review gate before you commit** — lint, type and test cannot catch a design
>    regression. Dispatch **{resolved review agent}** against your **changeset** — working tree,
>    staged and untracked included — versus `{default_branch}`, with a one-line scope statement.
>    Not "the staged diff": you have not committed yet, and an untracked file is invisible to
>    `git diff` while being the highest-risk class in the change. **Blocking findings → fix them
>    and re-review before you commit**, so nothing unreviewed ever reaches GitHub. Nits → roll in,
>    or record "Known and accepted" in the PR body. **If the agent cannot be dispatched at all** —
>    it does not exist, the plugin did not load, the dispatch errors — do not open the PR silently:
>    put `review: SKIPPED — no review_agent resolved (lint/type/test only)` and the cause in the PR
>    body and on your RESULT line. A review that printed nothing is indistinguishable from a clean
>    one.
>    **Read the review's final text yourself, and never block on it.** Its report is the return
>    value of the agent you dispatched, not a message that will come find you. The observable is
>    that returned text: either you are holding it, or the dispatch came back with nothing and you
>    take the NO REPORT branch below. There is no third state to sit in, so never stop, idle or
>    wait for one to arrive. On 2026-08-25 an
>    implementing agent deadlocked on a report that had already been delivered to a different
>    session, and lost a completed review cycle (#273). **If it was dispatched and nothing
>    readable came back**, that is a THIRD outcome and not a skip — the agent ran, it simply never
>    came back — so put
>    `review: NO REPORT — <agent> dispatched, no report returned (lint/type/test only)` in the PR
>    body and `review=no-report` on your RESULT line. Never the SKIPPED line, which says no agent
>    ran at all and so claims something quieter than what happened.
> 7. **Reconcile the docs against the repo before you commit.** Re-read the docs describing what
>    you touched — `CLAUDE.md`, the relevant `README.md`, anything in `docs/` — and fix every claim
>    your change just made untrue, in this same PR. A stale doc is a defect in your change, not
>    tidying for later; no other gate reads docs, so a wrong sentence ships silently and stays
>    confident. Scope it to the area you touched plus any claim you happened to disprove — not every
>    markdown file. Too large to close here → say so in the PR body rather than leaving a confident
>    sentence that is wrong. Two traps: **issue state is not evidence** (a closed issue does not
>    prove the behaviour landed, an open one does not prove it did not — read the code, the workflow,
>    the config; and check whether a `#N` you cite is an issue or a PR), and **claims of deliberate
>    absence rot silently** ("nothing tests X", "there is no Y yet") because nothing fails when they
>    stop being true.
> 8. Commit on branch `{prefix}/issue-{N}-{slug}` with a conventional-commit message containing a
>    literal `Closes #{N}` line.
> 9. Push and open a PR — the body MUST contain `Closes #{N}` on its own line, and must cover
>    {pr_template_sections from config}.
> 10. **Do NOT merge.** Report back: `RESULT: pr=<N> branch=<name>
>     status=<opened|skipped|failed> review=<clean|nits|no-report|skipped> note=<one-line>`

### Stacked variant (ONLY for a chain resolved in §2)

A stack is sequential by construction — layer 2 needs layer 1's code — so it gets **ONE sub-agent in
ONE worktree building every layer in order**, not one agent per issue. Dispatching the layers to
parallel agents is the failure this shape exists to prevent: they would each branch from the default
branch and rediscover the dependency as a conflict.

Substitute steps 7–9 of the prompt above with the following; steps 1–6 (worktree confinement, never
`git stash`, no shared-interpreter installs, read the issue, follow `CLAUDE.md` and
`## subagent-rules`, run the pre-flight, run the review gate) apply unchanged **per layer** — a
stack is reviewed layer by layer, because a layer's diff is what its own PR carries.

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
> `RESULT: stack=<bottom..top issue numbers> prs=<pr numbers bottom to top> linked=<yes|no> status=<opened|partial|failed> review=<clean|nits|no-report|skipped> note=<one-line>`

If a middle layer fails, the layers below it are still valid, independent PRs. Report the partial
stack rather than discarding the work — the coordinator can land what exists and re-dispatch the rest.

## 6. Coordinator: watch + merge (delegated)

**Before handing anything onward, on EITHER site: a sub-agent whose RESULT line reported
`review=no-report` OR `review=skipped` is held, never merged.** Both, and for one reason — neither
PR's diff was read by anybody — so they are held identically; the sibling rule in
`dispatch-ready` §2 withholds the same two, and a path that held only one of them would reach the
opposite conclusion about the very same sub-agent's output. This sits ABOVE the coordinator-only
subsection deliberately: under the default `review_site: agent` that subsection does not run at
all, so a rule stated inside it would leave the default site merging PRs whose review reached
nobody, which is the whole of #273 one layer out. Either outcome gets the same treatment a
Blocking finding gets — name it in the §7 report, allow ONE redispatch carrying the outcome as
context, and keep the PR out of the list you hand to `sassy-dog:pr-shepherd` below. A second
failure gets the `blocked` label plus a comment naming the outcome, and a human decides; never
park it back in Ready.

### Review gate on the coordinator site (ONLY when `review_site: coordinator`)

**With `review_site: agent` — the default, and the value an absent key selects — this section does
not run**: every sub-agent already reviewed its own diff at step 6, before its PR existed.

When the site is `coordinator`, review each PR as its RESULT line arrives and **before handing it
to `sassy-dog:pr-shepherd` below**, dispatching the agent resolved in §1 against that PR's diff
versus the derived default branch. Then:

- **Blocking finding** → hold the PR; **never merge past it**. Name the finding in the §7 report and
  allow ONE redispatch carrying it as context. A second failure gets the `blocked` label plus a
  comment naming the finding, and a human decides.
- **Nits** → note them in the report; they never hold a merge.
- **Dispatched, but no report came back** → print
  `review: NO REPORT — <agent> dispatched, no report returned (lint/type/test only)`, name the
  agent, and **hold the PR** — never merge it, and never hand it to `sassy-dog:pr-shepherd`. Never
  hold the run open until one arrives, and never call this a skip: the agent ran, so it is a third
  outcome rather than the line below wearing a different cause.
- **No agent resolved, or the dispatch failed** → print
  `review: SKIPPED — no review_agent resolved (lint/type/test only)` and name which of the two it
  was. Never merge on a review that was never reported.

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
- **Never merge past a Blocking review finding**, on either `review_site`. One redispatch carrying
  the finding, then `blocked` — and a review that could not run, or that ran and never came back,
  is reported under its own name, never passed over and never waited out.
- **Never auto-rebase a CONFLICTING PR** — surface it. Expect an upper stack layer to go
  `CONFLICTING` after the layer below squash-merges; that is the normal shape, not a fault.
- Cap parallelism at 5. Don't dispatch on stubs or `blocked` issues.
- **Never split a stack across parallel agents**, and never dispatch a partially-named chain. One
  chain = one agent = one worktree, layers built in order.

Apply any `## extra-guardrails` section from config on top of these.
