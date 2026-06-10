# Worktree teardown & session reconcile

After a batch of parallel sub-agents merges (or fails), the coordinating session must clean its own trace inline — not defer to a future cleanup pass. End state to assert: `git worktree list` shows only the main checkout (plus any genuinely-open PR's worktree), local default branch == origin, no leftover feature branches.

## The squash-ancestry trap

**`git branch --merged` is useless when the repo squash-merges.** A squash-merged branch's tip is NOT an ancestor of the default branch, so `--merged` reports it UNMERGED — a false negative that makes naive cleanup keep everything forever.

The reliable merged signal is **"remote branch gone"**: merges delete the remote branch (via `--delete-branch`, `delete_branch_on_merge`, or the merge queue's own deletion), so a local worktree branch with no `origin/<branch>` counterpart has been merged (or deliberately closed). `teardown.sh --sweep` keys off exactly this. Corollary: never disable remote-branch deletion on merge — the whole cleanup signal depends on it.

## Batch manifest

As each sub-agent returns, record `{issue, pr, worktreePath, worktreeBranch}`. Teardown consumes the `worktreePath`s to clean up *exactly* this batch instead of guessing. Write it somewhere durable (e.g. `.git/<batch-name>.json`) so a crashed coordinator's worktrees stay reclaimable via `--sweep` later.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/teardown.sh <wt_path_1> <wt_path_2> ...
# or, with no manifest (crashed coordinator, older sessions):
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/teardown.sh --sweep
```

The script force-removes each worktree (the Agent runtime leaves them locked, hence `-f -f`), deletes the local branch, prunes, clears origin-identical stragglers, and ff-reconciles the default branch. It reports — but **never auto-drops** — stashes (destructive; human's call).

## Session drift: two failure modes after sub-agent merges

`isolation: "worktree"` shares the underlying `.git` with the main session, so sub-agent activity can corrupt the coordinator's state in two distinct ways:

**Drift A — HEAD on a feature branch.** A sub-agent's commit advanced the session HEAD onto its branch. `git pull --ff-only origin main` then fails with `fatal: Not possible to fast-forward` (the feature tip is the unsquashed commit, not an ancestor of the squash-merge).

**Drift B — cwd inside a sub-agent worktree.** The shell cwd silently became a `.claude/worktrees/agent-*` path. `git switch main` fails with `'main' is already used by worktree at '<main repo path>'`. Symptom: `pwd` shows the worktree path, not the project root.

Single ordered recovery that handles both (substitute the repo root and default branch):

```bash
cd <main-repo-root>                         # snap cwd back (Drift B)
git switch <default-branch> 2>/dev/null || true   # snap HEAD back (Drift A)
git fetch origin <default-branch> --prune   # refresh + drop deleted-remote refs
git pull --ff-only origin <default-branch>  # advance to the squash-merge commit
git branch -D "<feature-branch>" 2>/dev/null || true
```

## Straggler files

A sub-agent whose Bash cwd reset between calls may have written untracked files into the *main* checkout — these block the ff-reconcile. `teardown.sh` clears only the safe subset: untracked files that are now TRACKED on origin's default branch AND byte-identical there (nothing is lost by deleting). Anything else it leaves and reports.

## Rules for the sub-agents themselves (prevention beats cleanup)

Bake these into any dispatch prompt for worktree-isolated sub-agents:

- **Never `git stash`.** Worktrees share one `.git`; stash writes the *global* `refs/stash` — one agent's stash is visible to and collides with every other worktree. Commit WIP to the branch or discard explicitly.
- **`cd` into the assigned worktree on every Bash call** (cwd resets between invocations). Verify with `pwd && git rev-parse --show-toplevel && git branch --show-current` before the first edit.
- **Sub-agents never merge or enqueue.** Single-writer: only the coordinator talks to the merge layer.
