---
name: dispatch-ready
description: >
  Loop-driven dispatcher: each invocation is one idempotent tick that reconciles in-flight PRs,
  then tops the pipeline back up to the configured concurrency limit, pulling ONLY from issues
  marked Ready, respecting dependencies and migration/codegen sequencing, until Ready is empty.
  Designed to run under "/loop 5m /dispatch-ready" but a single manual invocation is also valid.
  Use when the user says "let's work ready items", "work ready items", "dispatch ready items",
  "dispatch ready items in the backlog", "dispatch the backlog", "work the ready queue", "drain
  it", "drain the backlog", "work through Ready", "keep shipping until Ready is empty", or invokes
  it via /loop. Reads the current repo's settings from `.claude/sassy-dog/dispatch-ready.md`.
---

# Dispatch-Ready

One invocation = **one tick** of a drain loop.

All state lives in GitHub — status, assignees, PRs, branches — never in conversation memory,
because under `/loop` each tick may run with no recollection of the previous one. The contract with
groom-backlog: **dispatch-ready pulls exclusively from Ready** and trusts that Ready means dispatchable.
Anything that smells undispatchable gets bounced back, never patched up inline.

> Formerly `drain-it`. The "drain it" trigger still resolves here.

## 1. Repo config

!`root="$(git rev-parse --show-toplevel 2>/dev/null)"; echo "CONFIG_SOURCE: ${root:-<not a git repo>}"; cat "$root/.claude/sassy-dog/dispatch-ready.md" 2>/dev/null || echo "NO_CONFIG"`

**Check `CONFIG_SOURCE` before using any of this.** It is the repo root resolved from the
**session's** working directory at skill-load time — not necessarily the repo you are about to act
on — and cwd resets between Bash calls, so you cannot influence it. If it names a repo other than
the one you are working in, **discard the block above**, read that repo's own
`.claude/sassy-dog/dispatch-ready.md` by absolute path, and use that instead. Config is meant to be applied
exactly as written, so the wrong one silently applies another repo's rules: on 2026-08-18 two agents
shipping in `sassydog-routines` and `sassydog-skills` were each handed `platform`'s Terraform gates,
and caught it only by noticing the mismatch themselves.

Frontmatter supplies `max_in_flight` and `review_site`, plus the optional `board`, `migrations`,
`codegen`, `merge_queue`, and `stacked_prs` keys. Contract: `sassy-dog:setup-config` →
`references/config-contract.md`.

**`review_site:` decides WHERE this loop's review gate runs** — `agent`, each dispatched sub-agent
reviewing its own diff before it opens a PR (§5), or `coordinator`, this tick reviewing each open
PR before it merges (§2). **Absent selects `agent`**, the fail-safe site. It never decides *whether*
a review runs or *which* agent runs it. That is `review_agent:`'s resolution order, owned by
`send-it` and unchanged by this key — read it from `sassy-dog:setup-config` →
`references/config-contract.md` (`review_agent`) rather than re-deriving it here.

**If it reads `NO_CONFIG`**, STOP. Dispatch-ready dispatches sub-agents and merges PRs unattended, on a
loop — running it against an unconfigured repo means guessing a concurrency cap and skipping
migration serialization while nobody is watching. Tell the user to run
`sassy-dog:setup-config` first.

**Before the generic message, check for a stranded pre-rename config**: if
`.claude/sassy-dog/drain-it.md` exists, this repo is configured but predates the
`drain-it` → `dispatch-ready` rename. Say exactly that, and route to
`sassy-dog:setup-config` (update mode) — it performs the config rename. Still STOP; never
read the old filename directly.

### Offer to set this repo up

Then offer to fix it — this is the next step, so ask now:

- **If `.claude/skills/drain-it/SKILL.md` exists with a `generated-by:` marker** (the legacy
  generated-skills name) — this repo is on the superseded generated-skills architecture. Say so
  concretely: *"This repo has a generated `drain-it` I can migrate — I'd extract its config, show
  you the result, and remove the old skill only after you approve. Want me to?"*
- **Otherwise** — nothing to extract from: *"I can set this repo up. It takes a few questions about
  how this repo works. Want me to?"*

Naming which path applies matters: one of them ends in deleting a file the user may not know is
there.

On yes, delegate to `sassy-dog:setup-config`. **Never write config yourself** — the
refresher owns the contract, and a skill that writes its own forks the format the moment the
contract moves.

**Offer once per session.** Running deliberately in an unconfigured repo is legitimate; re-prompting
every invocation is noise. If declined, carry on and don't raise it again.

## 2. Reconcile in-flight (always first)

Find work this loop already started.

**With `board:`** — the board snapshot is the source of truth: cards in **In progress** / **In
review** with assignee @me **and not carrying `blocked`**, per §3's definition, are in-flight.
`board-snapshot.sh` returns `labels` per item, so the exclusion is computable here; where it is
not — a snapshot with no labels — treat the issue as blocked rather than as in-flight, since
failing the other way fails open into the bug the exclusion exists to prevent.

**Without a board** — live issue state is the source of truth. Snapshot the queue via
`sassy-dog:github-issues`' `queue-snapshot.sh` — one call returns `ready[]`, `in_flight[]`,
and `blocked[]` with the `touches:` and `Depends on #N` body contracts already parsed. In-flight is
`in_flight[]` entries with `mine: true`.

Either way, in-flight counts whether or not a PR exists yet: a sub-agent mid-implementation has
only a `*/issue-N-*` branch, and PR-based queries undercount, which overshoots the cap.

- **Open PRs from those branches** → delegate to `sassy-dog:pr-shepherd`: mergeable check,
  merge greens per the configured merge policy, tear down worktrees for merged PRs, reconcile the
  local default branch. **Hand it only the PRs the review bullets below have cleared, and never one whose
  issue carries `blocked`** — a human's demotion is not a merge instruction, and §4's `blocked`
  filter governs Ready SELECTION rather than this hand-off, so it does not cover this. A PR whose
  review reported `NO REPORT` or `SKIPPED`, or carries a Blocking finding, is withheld from this
  hand-off, on either `review_site` — with one carve-out, `review_agent: skip`, whose every run
  legitimately reports `SKIPPED`, so holding on it would turn the documented opt-out into a blanket
  merge freeze. `take-it` draws the same line for the same reason. This exception is stated here
  rather than three bullets down
  because this is the bullet that merges: a corrective a reader reaches only after the merge has
  been ordered is a corrective that never runs. **How a tick learns the outcome: read the PR
  body**, where take-it's step 6 requires the sub-agent to have written the verbatim line — this
  loop reads no RESULT lines, and a later tick is a different session from the one that dispatched.
  **Keep the issue → open-PR mapping this step produces** — §4's Collision
  filter reads those PRs' actual changed files, and re-deriving the mapping there costs a second
  round of lookups.
- **Open PRs on blocked issues** → resolve these too, and hand them to nobody. **With `board:`**
  the blocked set is the board's items carrying the `blocked` label, **plus any `blocked`-labelled
  issue the board does not carry at all** — `issue-claim.sh block` writes labels and never cards, so
  an issue blocked by hand, archived, or past the board query's own limit is on no card. Read that
  second half with
  `gh issue list --repo "$REPO" --state open --label blocked --limit 200 --json number`; without a
  named command this half is an instruction nobody can execute, and it is the half #282's own state
  consists of. Take the union: an issue the board cannot see is precisely the one whose PR would
  otherwise veto nothing and never reach the held set. **Without a board** it is `blocked[]` from the snapshot above. Both paths, like every other rule in this section and in
  §4 — a bullet written for one path only is invisible on the other, and the half it omits is the
  half that goes dark. `issue-claim.sh block` strips `in-progress`, so a blocked issue is not
  in-flight and the branch query above cannot see its PR at all;
  `gh issue view <N> --repo "$REPO" --json closedByPullRequestsReferences` names it (an OPEN entry
  only), the same lookup §4 already sanctions. **Known limit — and it bites hardest exactly here:**
  that field sees only PRs carrying a closing keyword, and this population (a redispatch PR, one
  opened by hand) is the likeliest to lack one, so fall back to the `*/issue-N-*` branch and never
  read an empty result as "no PR" — an unenumerated PR is silent and terminal. **Bounded** like
  §4's sibling lookup, and stated honestly: up to TWO calls per blocked issue per tick where the
  branch fallback is needed; the snapshot's `--limit` bounds the boardless path, and the board path
  is bounded by the board query's own limit plus the `--limit` on the label query named above. The set grows
  monotonically — nothing removes `blocked` but a human, and `promote` never does — so a repo that
  accumulates blocked issues pays for all of them every tick; if that cost ever bites under `/loop`, it degrades into "live state could not be
  verified", which is this fix's own failure mode wearing the bug's face. This loop may not advance
  these PRs, so they are never handed to `sassy-dog:pr-shepherd` — they are read so **§7 can see
  them**. A human-gated PR that nobody enumerated is not a smaller version of the §7 gap, it is a
  worse one: it leaves §7's held set empty, and an empty held set admits DRAIN COMPLETE, so the
  loop self-cancels with the PR still open (#282).
- **Failed or red PRs** → surface in the tick report with the failing check named, and comment
  `dispatch-ready: attempt 1 failed — <check>: <one-line cause>` on the issue. ONE redispatch with the
  failure context appended is allowed on a later tick. A second failure demotes to blocked — via
  the board plus a `blocked` label, or `issue-claim.sh block N --comment "dispatch-ready: 2 failed
  attempts — <cause>"` — and a human decides next. **Never park failures in Ready**: Ready must
  stay synonymous with dispatchable.
- **Open PRs not yet reviewed, when `review_site: coordinator`** → review before merging, never
  after. Dispatch the agent resolved by `send-it`'s order against the PR's diff versus the derived
  default branch, and hand only reviewed PRs to `sassy-dog:pr-shepherd` this tick. A PR whose review
  could not run at all — no agent resolved, or the dispatch failed — reports
  `review: SKIPPED — no review_agent resolved (lint/type/test only)` with the cause, and is held,
  not merged on an unreported review. Under `review_site: agent` this bullet does not run: the
  sub-agent reviewed before its PR existed.
- **A review dispatched that never came back, when `review_site: coordinator`** → a review report is
  the *return value* of the agent this tick dispatched, read from that agent's final text. A tick
  never blocks, polls or idles waiting for a notification to carry one in — a tick that waits is a
  loop that stopped waiting for the review. When nothing readable came back, report
  `review: NO REPORT — <agent> dispatched, no report returned (lint/type/test only)` naming the
  agent, and **hold the PR** exactly as above — never merge it, and never hand it to
  `sassy-dog:pr-shepherd` this tick. **Never fold that into the SKIPPED line**: that line says no
  agent ran, and here one did (#273).
- **PRs carrying a Blocking review finding** → **never merge past one.** This is the existing
  failure path, not new machinery: surface it in the tick report with the finding named, comment
  `dispatch-ready: attempt 1 failed — review: <finding>` on the issue, and allow ONE redispatch
  carrying that finding as context on a later tick — the same single-redispatch budget a failed
  check gets. A second failure demotes to `blocked` the same way, with the finding in the comment,
  and a human decides. **Never park it back in Ready**: Ready must stay synonymous with
  dispatchable. On the `agent` site this rarely fires, because findings were fixed before the PR
  existed — but it still fires when a sub-agent could not resolve a reviewer at all, and equally
  when its PR body carries the `NO REPORT` line: the agent ran and its report reached nobody, so
  the PR is held and never merged on it. Those are exactly the cases that must not pass silently,
  and on the
  default `agent` site they are the ONLY way a review outcome reaches this loop — a rule stated
  only in the `coordinator` bullets above would leave the default site merging unreviewed work.
  **Read that outcome from the PR body**, where take-it's step 6 requires the sub-agent to have
  written the verbatim line: this loop does not read RESULT lines, and a later tick is a different
  session from the one that dispatched. The comment template on this path names the outcome rather
  than a finding — `dispatch-ready: attempt 1 failed — review: no report returned` — since a lost
  report has no finding to name.
- **`CONFLICTING` PRs** → never auto-rebase; **demote on sight.** Surface it in the tick report
  naming the PR *and the conflict*: §6's `holds:` line classifies by §7's table, which answers row
  1 (`blocked`) once this bullet has written, so the word `CONFLICTING` reaches the operator only
  if this bullet puts it there. Demote the issue in the same tick — via the board plus a `blocked`
  label, or `issue-claim.sh block N --comment "dispatch-ready: PR #<pr> is CONFLICTING — needs a
  rebase this loop may not perform, then clear the blocked label to resume the drain"`, that
  subcommand requiring a comment — so a human resolves the conflict. Name the label in it:
  `promote` never strips `blocked`, so a rebase alone no longer returns the issue to the queue.
  **Demote ONCE**: skip an issue that already carries `blocked` and write nothing, leaving it to
  the blocked-PR bullet above. That is an idempotency predicate, not an attempt
  counter — it asks whether the demotion has been *written*, never how many times the PR has
  failed — and without it this bullet re-fires every tick against a PR that stays `CONFLICTING`
  until a human rebases, posting a fresh comment each time, since `issue-claim.sh` makes the label
  edits idempotent and the comment not. The Guardrails' **idempotent ticks** rule forbids exactly
  that. **If the demotion write fails**, say so in the tick report and treat the issue as still
  in-flight this tick: a tick that believes it demoted and did not is #282 again wearing this fix.
  **Read that from live state, never from the exit code alone** — `issue-claim.sh` reports `ok` and
  exits 0 when the label edit lands and only the *comment* fails, saying so on stderr, so a
  demotion can be real while the reason nobody posted is not. `Demote ONCE` then never retries it,
  which is the trade: re-comment nothing, and report the missing reason instead.
  **No redispatch, and no attempt counter** — this is deliberately NOT the shape the failed-check
  bullet above has, and aligning the two is the tidy to refuse: a sub-agent sent to rebase the
  branch IS this loop advancing that PR, which §7's discriminator table forbids for `CONFLICTING`
  in as many words, so that option costs a §7 row as well and re-opens a decision already settled
  there. `take-it` keeps the bare surface-and-hold form for the mirror-image reason and must not be
  aligned to this one: it is a bounded batch with no §7 and no forever-tick, so a hold there ends
  when the batch does. **A bare surface-and-hold is what this replaces, and it was the defect**:
  nothing cleared the claim, so the issue stayed `in-progress`, in-flight never reached zero, and
  with COMPLETE vetoed by the open PR and STALLED forbidden by in-flight, the loop ticked forever —
  #282's class one bullet over, and not covered by it (#290). No other route reaches a demotion
  either: a conflicted PR stops CI firing at all, `sassy-dog:pr-shepherd` recording that `no checks
  reported` reads identically to `CI hasn't started`, so the failed-check bullet's counter never
  starts. **A stacked upper layer demotes like any other**, and that cost is accepted rather than
  carved out: a layer goes `CONFLICTING` the moment the layer below squash-merges, which
  `sassy-dog:pr-shepherd`'s stacked-PR reference calls the expected shape rather than a fault — but
  this loop may not rebase it either, so it is a human gate like the rest. Say which it is in the
  comment. **The demotion changes which §7 row matches, never whether the PR is enumerated** — the
  first bullet above already resolved it from the in-flight branch this tick, and both rows answer
  held, `CONFLICTING` (row 2) before and `blocked` (row 1) after — so COMPLETE stays vetoed and the
  held set stays non-empty across the write. **Carry that PR into §4's collision sources and the
  migration slot for this tick**, from the issue → open-PR mapping the first bullet already keeps:
  §4 draws its blocked half from the blocked-PR bullet's enumeration, taken *before* this write, so
  a PR demoted here sits in neither half until the next tick — while §3 frees its slot in this one,
  which is exactly the state where §4 would dispatch a Ready issue into a still-open human-gated
  PR. From the next tick on the blocked-PR bullet enumerates it and the hand-off bullet's own
  `blocked` predicate withholds it from `sassy-dog:pr-shepherd`; on the demotion tick that
  predicate reads state not yet written, and what withholds it instead is `merge-shepherd.sh`
  refusing a `CONFLICTING` PR ahead of every other check. **Never park it back in Ready**: Ready
  must stay synonymous with dispatchable.

## 3. Compute capacity

In-flight is the set of issues claimed by this loop — assignee @me plus board status or the
`in-progress` label — **and not carrying `blocked`**. That last clause is stated here because this
is the file's only "in-flight is" sentence, and §2's board path, §4's filters and §7's first
conjunct all read it: `issue-claim.sh block` writes labels and never moves a card, so without it a
demoted issue stays in-flight on a board repo permanently and neither terminal state can ever fire.
Do NOT resolve the resulting asymmetry with §4's Claimed filter by aligning the two — §4 skips on a
disjunction on purpose, and `issue-claim.sh` documents why. **Capacity = `max_in_flight` −
in-flight.**

A green PR sitting in the merge queue still counts as in-flight until it is actually MERGED.
Compute capacity from post-reconcile live state and accept that a queue-pending slot frees up next
tick, not this one. Capacity ≤ 0 → emit the tick report and stop; the next tick tops up.

## 4. Select from Ready — and only Ready

**With `board:`** — take the **Ready** column in board order, since board order is priority.

**Without a board** — take `ready[]` from the §2 snapshot, already ordered issue-number ascending
(oldest first). When the repo defines priority labels, issues carrying them sort ahead; that's the
boardless stand-in for "board order = priority".

Filter, in order:

| Filter | Rule |
| --- | --- |
| Claimed | Skip if assignee set, or status ≠ Ready / `in-progress` label present — another session got it |
| Blocked | Skip the `blocked` label |
| Dependencies | Skip while any literal `Depends on #N` references an issue that is not CLOSED — re-eligible automatically once the dep merges. **Exempt: members of a stack this tick is dispatching** (below). |
| Collision | Skip if the issue's `touches:` set intersects the **effective file set** of anything §2 resolved a PR for — in-flight issues **and blocked issues with an open PR** — same repo-relative path, or a glob on one side matching a path on the other. The effective set is the in-flight issue's open PR's *actual changed files* where it has a PR, and its declared `touches:` where it does not (next section). Defer to a later tick; re-eligible once the overlapping issue merges. An issue with **no** `touches:` line intersects nothing, but is flagged `unannotated` in the tick report so the coupling gap is visible rather than silently risky. **Exempt: overlap between members of the same stack** (below). |

### Collision — an in-flight PR's real files beat the declaration

`touches:` is a **prediction**, written at grooming time, and it under-declares systematically. On
2026-08-24 in this repo, #247 and #249 both edited `scripts/preflight.sh` and #249 never declared
it — it declared 3 files, its PR changed 9. The declared sets showed no overlap, so the filter
called the two independent; the collision was caught only because a human was reading live PR
contents. Two mandatory repo rules widen almost every PR past what grooming can predict, and
neither is knowable when the touch-set is written:

- **doc reconciliation** (`CLAUDE.md`, `README.md`, `docs/`) — which claims a change falsifies is
  visible only once the change exists;
- **CI wiring** (`scripts/preflight.sh` and the tests it gates) — grooming often does not yet know
  a test will be needed.

**A blocked issue's open PR counts here even though it is not in-flight.** §3 excludes it from
in-flight so the terminal states can be reached; that exclusion must not also remove its files from
this filter, or the loop dispatches a Ready issue straight into a still-open human-gated PR — the
class §4's own 2026-08-24 incident records. §2 resolved that PR one bullet above; reuse it. The
same applies to the migration slot below: a blocked migration PR still holds it.

So for an issue that **already has an open PR**, in-flight or blocked, intersect against what that
PR actually changed rather than against what its issue predicted:

```bash
gh pr view "$PR" --repo "$REPO" --json files --jq '.files[].path'
```

§2 already resolved which in-flight issues have an open PR — reuse that mapping; where it is
absent, `gh issue view <N> --repo "$REPO" --json closedByPullRequestsReferences` names the PR (an
OPEN entry only; a merged one is no longer in flight). Cost is one `gh` call per in-flight issue
per tick. This stays here rather than moving into a capability skill: `queue-snapshot.sh` parses
the declared contracts, and the intersection **judgement** — which set to trust, and what to do
when it cannot be read — has always been the calling skill's.

Resolve a source per in-flight issue, and **name the source in the tick report**, so an
under-declaration is visible instead of silent:

| In-flight issue | Set used | Reported source |
| --- | --- | --- |
| Open PR, `gh pr view` succeeded | that PR's changed files | `pr` |
| No PR yet — sub-agent still implementing | declared `touches:` | `declared (no PR yet)` |
| Open PR, but the read failed or was rate-limited | declared `touches:` | `declared (PR read failed)` |

**A failed read is never "no overlap".** Fall back to the declared set and *say so* — the declared
set is a narrower check, not an absent one, and a hold it produces is still a hold. Never let
"could not read the PR" resolve to "that PR touches nothing": unknown is not clear. Same for a PR
whose file list came back empty *because the call errored* — an error is a failed read, not an
empty diff.

**Known limitation: this narrows the gap, it does not close it.** An issue with no PR yet offers
nothing but its declaration, and that is precisely the window in which a sub-agent is writing the
undeclared `CLAUDE.md` edit. `sassy-dog:pr-shepherd`'s coupled-PR serialization stays the fallback
for that window.

**Do not "simplify" this back into a declared-set-only filter**, and do not close the remaining gap
by having `groom-backlog` over-declare (appending `CLAUDE.md` / `README.md` / `preflight.sh` to
every touch-set). Over-declaration was considered and rejected in #257: near-universal overlap on
`CLAUDE.md` would plausibly serialize the whole queue to one issue at a time.

### Stacks (ONLY if `stacked_prs:` is configured)

**With no `stacked_prs:` block this section does not run**, and a dependency chain serializes across
ticks exactly as before. That is the default and it is correct, not degraded.

When it IS configured, `queue-snapshot.sh` surfaces a `stack` array on the bottom issue of each
declared chain. A chain is dispatchable as one stacked unit when **every** member is in `ready[]`,
unclaimed, and unblocked. Then two filter exemptions apply, and only within that chain:

- **Dependencies** — members may depend on each other and still dispatch together. That is the whole
  point: the chain ships now instead of one layer per tick. Dependencies pointing *outside* the
  chain still block it, as a unit.
- **Collision** — overlapping `touches:` sets *between members of the same stack* are expected, not
  hazardous: layer 2 is branched from layer 1, so it edits layer 1's files on top of layer 1's
  version by construction. Overlap between a stack member and any **other** in-flight issue still
  blocks the whole chain.

**Capacity: a chain costs ONE `max_in_flight` slot**, because it is one sub-agent in one worktree —
not one slot per layer. It does open N PRs, so a chain under a cap of 3 can still leave more PRs
in flight than an unstacked tick would; that is expected and bounded by `stacked_prs.max_depth`.

Verify the repo is actually enabled before dispatching a chain:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/stack-probe.sh --repo "<slug>"
```

Exit `11` means the preview is not enabled here. **Do not fall back to parallel dispatch** — the
members really do depend on each other. Drop the exemptions, let the ordinary Dependencies filter
serialize the chain across ticks, and note it once in the tick report.
| Smell test | Run take-it's pre-flight smell test — research-shaped titles, open-question sections, stub bodies. Failures bounce back to groom-backlog with a required comment. Never "fix it up" inline; that hides the grooming gap. |
| Reference decay | Re-resolve the body's code references against the current tree (below). Exit `3` holds the issue this tick. |

### Reference decay — re-check at dispatch, not just at grooming

groom-backlog resolves every reference before promoting, so an issue in Ready
was accurate **when it was groomed**. Then other issues merge. A rename three
PRs ago turns a correct body into one that sends a cold worktree agent looking
for a symbol that is no longer there, and nothing about the issue changed to
show it — this is why the check runs again here rather than being trusted from
promotion:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/verify-issue-refs.sh <N> --format text
```

Exit `3` → **hold the issue this tick** and report it as
`#N (reference drift: <ref> → <suggestion>)`. It is not a failed attempt, so it
costs no redispatch budget, and it is not `blocked` either — the body needs a
one-line correction, not a human decision. Fix the body and it dispatches next
tick; if the same issue holds on drift twice, bounce it to groom-backlog with a
comment rather than correcting it inline, which hides the grooming gap the same
way the smell test does.

Exit `0` dispatches normally. Exit `10` is a **skip, not a pass** — say so in
the tick report and dispatch anyway; a missing `python3` is not evidence the
body is sound.

`likely-new` findings never hold an issue. An issue naming the files it is
asking someone to create is the normal case.

**If `migrations:` is configured** — additional filter: at most ONE issue touching
`migrations.dirs` in flight at a time, in-flight included. Hold the rest in Ready.

**If `codegen:` is configured** — additional filter: codegen-coupled issues may run in parallel,
but flag them to pr-shepherd so their merges serialize.

Take the first `capacity` survivors. The Collision filter is the primary defense against concurrent
file-overlapping dispatch; `sassy-dog:pr-shepherd`'s coupled-PR serialization
(`references/serialization.md`) stays the **fallback** for the overlaps it still cannot see —
`unannotated` issues, and in-flight issues with no PR yet, whose undeclared edits become visible
only once their PR exists. That fallback is unchanged by reading live PR contents here; it now
catches less, not nothing.

## 5. Dispatch

Use take-it's mechanics verbatim: claim → fast-forward the local default branch → one sub-agent per
issue, `isolation: "worktree"`, single message, batch manifest in `.git/dispatch-ready-batch.json`,
take-it's self-contained sub-agent prompt.

A stack chain uses take-it's **stacked variant** instead: one sub-agent, one worktree, layers built
in order, PRs based on the layer below, linked via `POST /repos/{slug}/stacks`. Claim every member
up front — a half-claimed chain lets another loop pick up a layer mid-build. The shared worktree
appears **once** in the manifest, and teardown waits for the TOP layer to be terminal.

The reused prompt carries take-it's shared-state isolation rules — worktree confinement, never
`git stash`, never an editable or dev install into a shared interpreter or global store — **its
doc-reconciliation step**, which requires the sub-agent to fix any doc its change made untrue before
committing, and **its review gate**, under the site this repo configures. Keep all of them intact
when appending failure context for a §2 redispatch.

**Honour `review_site:` when you build the prompt.** With `review_site: agent` — the default an
absent key selects — take-it's step-6 review gate stays in the prompt verbatim and each sub-agent
reviews its own diff before opening its PR. With `review_site: coordinator`, drop that one step and
review each PR in §2 of a later tick instead, before it merges. **Never drop it from both**, and
never substitute a different agent for the one `review_agent:`'s order resolves — this key chooses
the site alone.

**Step 6's delivery half travels with the gate, whichever site is configured.** A sub-agent reads
its review's final text itself, never blocks waiting on a notification to deliver one, and reports a
dispatch that came back with nothing as `review: NO REPORT`, never as a skip. Under
`review_site: coordinator` that half does not disappear with the step — it moves here, to §2, which
owes the PRs it reviews exactly the same three outcomes.

Those two gates are the ones most easily lost here, because these agents open their own PRs from a
cold worktree and never see an interactive session's instructions: a gate that lives only in
`send-it` never runs for them at all. That is why the review gate is a config key read here rather
than a rule stated once in `send-it`, and why dropping it from the prompt under
`review_site: coordinator` obliges §2 to run it — never to skip it.

**Model policy: pass `model: "opus"` on every dispatched Agent call.** Implementation work runs on
Opus because it is the cheaper tier relative to the coordinator's session model — only this
coordinator tick stays on the session model. Do not silently change the sub-agent model in either
direction.

Sub-agents NEVER merge. Single-writer: merges happen in §2 of a tick.

## 6. Tick report

Terse — this prints every few minutes under `/loop`:

```text
DRAIN TICK — in-flight 3/5 | merged this tick: #1712 | dispatched: #1707 #1711 | Ready remaining: 4
holds: #1713 (Depends on #1717, still open) · #1708 (migration slot busy) · #1709 (overlaps in-flight #1707) · PR #1699 (open, #1698 blocked)
collision sources: #1707 pr · #1710 declared (no PR yet) · #1706 declared (PR read failed — narrower check)
stacks: #1720 → #1721 → #1722 dispatched as 1 layer-stack (1 slot, 3 PRs)
unannotated (dispatched without a touches set — coupling unchecked): #1711
review: #1709 BLOCKING (unvalidated path join in scripts/render.sh) — redispatch 1 of 1
```

Plus one line per failure with its next action. Drop the `unannotated` line on ticks that dispatch
nothing unannotated, the `stacks:` line on ticks that dispatch no chain, and the `review:` line on
ticks with no review outcome to report — but never drop a Blocking finding or a
`review: SKIPPED` from it, nor a `review: NO REPORT`, which are outcomes, not noise. The
`holds:` line carries **held PRs alongside held issues**, in the same reason-per-item shape, drawn
from §2's enumeration and classified by §7's table — from §2 rather than from §7 because §2 is
where the PRs are resolved and §6 renders before any terminal state is decided, and a held PR is
worth seeing on every tick, not only on the one that ends the loop. The
`collision sources:` line renders whenever anything is in flight and names every in-flight issue's
source, since a `pr` source is
what proves the filter saw real files; drop it only on a tick with nothing in flight, and never
drop a `declared (PR read failed)` entry — a degraded check is an outcome too. When a chain was
declared but the repo is not enabled for the preview, say so once rather than every tick:
`stacks: #1720→#1722 declared but stacks unavailable in this repo — sequencing by dependency instead`.

## 7. Terminal states — drain complete, drain stalled, drain degraded

A drain loop ends itself in exactly three states. All must be **confirmed from live GitHub state
read this tick** — the §2 reconcile plus the §4 read, never a stale or transient one. If live
state could not be verified this tick — an API failure mid-tick — the tick proves nothing: leave
the loop alone, write no stall or degraded record, and let the next tick re-check.

### DRAIN DEGRADED

**Evaluated BEFORE COMPLETE and STALLED, and that order is the rule rather than a presentation
choice.** §7 already refuses to act on a tick whose live state could not be verified — *the tick
proves nothing*. A degraded platform is that same condition arriving **without an error**: the
reads succeed, return incomplete data, and COMPLETE and STALLED consume them as fact. Measured
2026-08-26 — PR #283's required `ci` never fired during an outage, two consecutive ticks reported
the state accurately and did nothing, and the coordinator then proposed closing and reopening the
PR, which during an outage could leave it worse than doing nothing. Evaluating this state after
the other two lets a degraded read produce a confident terminal verdict first.

This state **consumes** `pr-shepherd`'s probe and never re-derives platform health itself:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-shepherd/scripts/probe-platform-health.sh --pr "$PR" --repo "$REPO"
```

Run it against **ONE** in-flight PR, not each: the verdict is about the platform, not the PR, and
a per-PR fan-out multiplies calls into a service already struggling.

Three conjuncts, and each excludes a normal state the loop already handles:

1. **In-flight is non-zero and nothing moved this tick** — no dispatch, no merge, no tracked PR
   changing state. In-flight zero belongs to COMPLETE and STALLED; this state exists for the case
   neither can see, where work EXISTS and cannot progress.
2. **Nothing this loop is permitted to advance** — §2's discriminator, reused and unchanged. A
   **red** check is a failure with its own redispatch path, so the loop still has an action and
   this conjunct is false. A **pending** check that is genuinely queued is the loop waiting, not
   the loop stuck. An active **foreign** claim resolves without a human.
3. **The probe returns a `degraded` verdict** — `degraded (attributed)` or `degraded
   (unattributed)`, and nothing else. **`unknown` is NOT degraded**, and it is the one a later
   *these both mean trouble* sweep will fold in: `unknown` means the probe could not measure,
   which is precisely the state that must not stop a loop. `healthy` is not degraded either — if
   the platform is fine and work is stuck, that is STALLED's question or a real defect, and
   stopping the loop would hide it.

**Report WHY an `unknown` could not measure, and treat a probe that says nothing as one.** On an
`unknown` whose `self_measured` is `not_measured`, the probe's `explains` field carries the reason
and the first-party detail behind it — including its own `PLATFORM_GH_TIMEOUT` bound firing, which
is the single most useful fact this loop can print during the outage this state exists for, and
which the bare verdict flattens into the same sentence as "no `--pr` was given". So render the
reason, not the word: `probe: unknown — not measured: pr_read_failed; gh pr view 305 exited 124 —
the PLATFORM_GH_TIMEOUT bound fired`. The OTHER `unknown` — a clean first-party read beside a
status page that could not be read — carries no such tail, and its cause is in `status_page_detail`
instead; report that field there rather than an empty reason. A run that returns **no stdout at
all** — killed by a tool timeout before it could emit, or exiting non-zero on a usage error such as
a missing `jq` — is `unknown` by the same rule and is reported as `probe: no verdict — exit <rc>:
<first stderr line>`, because "the harness killed it" and "this VM has no `jq`" are different
problems and the exit code is what separates them. None of these forms is `degraded`, none stops
the loop, and none is `healthy`: a probe that did not speak is not a platform that is fine.

**Two-tick confirmation, the same shape as STALLED and for the same reason**: a flaky call is not
an outage. The record is `.git/dispatch-ready-degraded.json` — its **own** file, not the stall
record. They answer different questions, a tick can legitimately be mid-confirmation on neither,
one, or both, and sharing one file would let either confirmation clear the other's clock.

- **No record** → write this tick's verdict and finish normally, appending to the tick report:
  `degraded: suspected — <verdict>; a second degraded tick ends the loop`.
- **Record present** → DEGRADED is confirmed. Delete the record and announce loudly:

```text
DRAIN DEGRADED — the platform is degraded and nothing in flight can progress:
  probe: degraded (attributed) — Actions: major_outage
  in flight: #286 (PR #305 — required check `ci` has no run for the head)
Loop <id> cancelled — the platform recovers on its own; restart the drain once it has.
```

Then take the **same stop path as DRAIN COMPLETE** below — one path, never a parallel one.

Any tick that dispatches, merges, or reads a `healthy` verdict deletes a leftover
`.git/dispatch-ready-degraded.json`: recovery resets the confirmation clock exactly as progress
resets the stall clock. An `unknown` verdict **leaves the record alone** — it is neither progress
nor degradation, and clearing on it would let one unreadable status page reset a genuine two-tick
outage count indefinitely. A `no verdict` run leaves it alone for the same reason — it is an
`unknown` that could not even say so.

### DRAIN COMPLETE

Ready empty AND in-flight zero AND nothing still claimed AND **no open PR this loop tracks** →
announce loudly and take the stop path below immediately — an empty queue needs no confirmation
tick. **"Nothing still claimed" means no in-flight issue per §3 and no active FOREIGN claim** — an
item §4's Claimed filter skipped because another session holds it. It is not implied by in-flight
zero, which counts `mine: true` only. It deliberately does NOT mean "no assignee anywhere":
`issue-claim.sh block` leaves the assignee on purpose and only `promote` clears it, so a blocked
issue's leftover assignee is residue rather than a claim — reading it as one would make COMPLETE
unreachable on any repo that has ever blocked an issue, which is this bug wearing the other face:

```text
DRAIN COMPLETE — Ready is empty and nothing is in flight.
```

**COMPLETE is unchanged, veto included** — the fourth conjunct above IS the veto, stated where the
instruction is rather than three paragraphs below it. An open PR this loop tracks still means the
drain is not complete, in-flight until actually MERGED per §3, exactly as the safety rails restate
it. A veto a reader reaches only after "announce loudly and take the stop path immediately" is the
corrective §2 warns about: one that never runs. In #282's own state both of the old conjuncts were
true, so the rule as written told the loop to self-cancel.
What #282 changed is only where that veto leads. A PR this loop may not advance used to veto COMPLETE
and reach no other state either; it now joins STALLED's held set, and the veto ranges over exactly
the set that held set is drawn from.

### DRAIN STALLED

In-flight zero AND dispatched zero this tick AND **nothing this loop is permitted to advance**,
over a **non-empty** held set — every Ready item held by a §4 filter, and every open PR held by the
discriminator below. All four conjuncts are stated here rather than corrected further down, for the
reason COMPLETE's condition now states all of its own. Nothing
this loop controls can change GitHub state before the next tick: no PRs it may merge, no agents
working, and dependency holds only resolve when a dep closes — with nothing in flight, only
external or human action closes one. The loop is stalled, not idle; "Ready isn't empty" alone must
never keep it alive.

**The third conjunct is "nothing to advance", and it replaced "Ready non-empty"** — that
difference is the whole of #282. Ready empty, in-flight zero and an open unmerged PR was covered by
NEITHER terminal state: COMPLETE is vetoed by the open PR, and STALLED could not fire on an empty
queue. The loop ticked forever, reporting the state accurately and doing nothing (observed
2026-08-26 on #273 / PR #279; cancelled by hand). The action that creates the state is the action
that hides it — `issue-claim.sh block` strips `ready` and `in-progress` together, so recording
"a human must decide this" is precisely what removes the issue from the one set the old conjunct
consulted.

**Deleting that conjunct outright would have been the wrong fix**, and re-deriving it that way is
the tempting simplification here: an open PR is not automatically a human gate. One whose checks
are still running or red can advance on its own, and firing STALLED there cancels a loop that was
about to make progress.

**The held set must be non-empty.** Nothing held, nothing in flight and no open PR is COMPLETE,
which fires first and needs no confirmation tick. "Nothing to advance" satisfied vacuously — by a
queue that simply finished — must never announce STALLED.

#### The discriminator — may this loop advance it?

**"Every open PR this tick sees" is the union §2 resolves** — open PRs on in-flight branches, and
open PRs on blocked issues. Both halves are load-bearing: a PR nobody enumerated cannot be held,
and the second half is precisely the one #282's own state consists of. Their state comes from
`sassy-dog:pr-shepherd`'s `poll-prs.sh --once <PR>…`, which returns `mergeable`, `mergeStateStatus`
and the check counts in one pass; the judgement below stays here, the way §4 keeps its intersection
judgement while borrowing `gh pr view`. **Both halves of that invocation are load-bearing.**
Without `--once` it is watch mode, which blocks for up to an hour — the "a tick that waits is a
loop that stopped" rule two sections up. Without the explicit PR numbers `--once` falls back to
whatever fifty open PRs `gh pr list` returns first — no sort is specified, so a long-lived held PR,
which is exactly #282's shape, is as likely to fall outside the fifty as inside. That is both the
widening the paragraph above forbids and a silently truncated read of it.

**That union is also the set COMPLETE's veto ranges over, and the identity is the invariant.** A PR
that can veto COMPLETE but can never enter the held set gives Ready empty, in-flight zero and a
held set that is empty — COMPLETE vetoed, STALLED forbidden, ticking forever. That is #282 exactly,
one shape over, and it is what an unqualified "any open PR vetoes COMPLETE" reading produces the
moment a Dependabot PR, a hand-opened PR with no issue, or another session's PR is sitting there.
So the veto is scoped to this union and never to every open PR in the repo. Widen one half without
the other and the forever-tick comes back; narrow one without the other and the loop self-cancels
on work it is still holding.

**The blocked half is deliberately REPO-WIDE, and that is a decision rather than an oversight.**
`queue-snapshot.sh` returns blocked issues as bare numbers — open, `blocked`-labelled, no assignee
and no labels — so a tick genuinely cannot tell an issue this loop demoted from one a human blocked
by hand, and `issue-claim.sh block` leaves the assignee rather than clearing it. Rather than filter
on a signal neither section can read, take them all: over-including ends the loop LOUDLY, naming
the PR and the gate holding it, and a human who disagrees restarts the drain. Under-including is
the failure this whole section exists to close. The exclusion that matters is untouched — a
Dependabot PR, or a hand-opened PR whose issue is neither in-flight nor blocked, is in neither half
of the union and vetoes nothing.

Ask it of every one of them, take the **first matching row**, and carry the answer per PR into the
held set:

| Open PR this tick | May this loop advance it? | Effect |
| --- | --- | --- |
| Its issue carries `blocked` | **No** — §2 already routed it to a human | held: joins the held set |
| `CONFLICTING` | **No** — §2 never auto-rebases; a human resolves the conflict | held: joins the held set |
| Held by a §2 review outcome — a Blocking finding, a `NO REPORT`, or a held `SKIPPED` — with its ONE §2 redispatch spent | **No** — never merged past, and nothing left to redispatch | held: joins the held set |
| Checks still running, and not `CONFLICTING` | **Yes** — a later tick merges it once it goes green | keeps the loop alive |
| Checks red, its issue not `blocked`, and its ONE §2 redispatch unspent | **Yes** — that redispatch is still available | keeps the loop alive |
| Anything else this loop is not permitted to merge this tick | **No** — held is the default | held: joins the held set |

**Rows 2 to 6 cannot fire at the moment STALLED is decided, and that is by construction rather
than by accident.** STALLED's first conjunct is in-flight zero, which empties the branch half of
the union — so every PR still enumerable carries `blocked`, and row 1 matches it first. The
argument is exhaustive over the union, so it reaches the default row too: at that instant nothing
falls through to it. This is the same shape as the self-resolving carve-out below, and it is stated
for the same reason: a reader who works it out later will otherwise read the rows below row 1 as
live guarantees, or delete them as dead prose. They are neither. They classify
held-versus-advanceable for the two OTHER consumers of this table — §6's `holds:` line, which
renders on every tick including ticks with work in flight, and the safety rails' "an open PR this
loop may still advance" — and they are what stops a later widening of §2's enumeration from
silently answering "alive" for a shape nobody classified. Delete them and that widening becomes a
silent #282; treat them as reachable at STALLED time and the reasoning above them is wrong.

**The last row is a default, not a catch-all to delete.** §2 holds a PR for more reasons than the
rows above enumerate and will not stay exhaustive, and a table that silently answers "alive" for a
shape it does not know re-creates #282 one shape at a time. Held is the right default *here*
because it is the answer §2 already gives: a PR this loop may not merge is a PR it cannot advance.
The two defaults are not mirror images: held ends the loop and names the PR wherever it fires,
alive ticks forever and reports nothing. (Which of them fires at STALLED-decision time is a
separate question, answered by the paragraph above — there, row 1 has already matched.)

**`CONFLICTING` needs its own row, above the checks rows, and the ordering is the point.** A
conflicted PR stops CI firing at all, and `no checks reported` is indistinguishable from
`CI hasn't started` — `sassy-dog:pr-shepherd` records exactly that. Without the row a conflicted
PR matches "checks still running" and is answered with something that can never happen: §6's
`holds:` line would report it as advancing on every tick, and the rails would read it as a PR this
loop may still advance. It is NOT what lets a stalled queue confirm — at STALLED-decision time the
paragraph above applies and row 1 has already matched — and saying so here would contradict it.

**The redispatch budget is the hinge on both failure rows**, so read this before "simplifying" the
rows into fewer. §2 grants exactly ONE redispatch per issue, taken on a later tick; while it is
unspent this loop still has an action of its own, and a state it can still act on is not a stall.
Once it is spent §2 demotes to `blocked`, which is why the label is the usual way a held PR
presents — and why the review-outcome row is not redundant beside it: the label is a write
this loop performs, the finding is a fact it reads, and a demotion not yet written must never read
as advanceable. It is also why the red-checks row asks for the budget and not for the label
alone: an unspent budget is what makes a red PR advanceable, while a spent one whose demotion has
not been written yet matches no row above and falls to the default. Unknown is not clear.

**Read the review outcome from the PR body**, exactly as §2 reads it — take-it's step 6 requires
the sub-agent to have written the verbatim line. This loop reads no RESULT lines, and a later tick
is a different session from the one that dispatched. **Read the redispatch budget from the issue,
not from the PR**: §2 spends it by commenting `dispatch-ready: attempt 1 failed — <cause>` on the
issue, so that comment is the record of whether it is spent, and a tick that never reads it cannot
answer either failure row. No such comment means the budget is unspent.

**A gate that could not be read is not a hold**, and this is not in tension with "unknown is not
clear" two paragraphs up — the two answer different questions. An unknown *state that was read*
(a shape no row names) is held: the loop has no action for it. State that *could not be read at
all* is not a fact about the PR, it is a failed tick, and it falls under this section's opening
rule: live state was not verified, so the tick proves nothing — leave the loop alone and write no
stall record.

Two carve-outs keep the state precise:

- **Self-resolving holds can never trip it — but a hold against a BLOCKED PR is not one.** A
  collision or migration hold against in-flight work resolves when that work merges, and requires
  in-flight > 0, so the in-flight = 0 conjunct excludes it by construction. Since §4 now
  intersects against blocked issues' open PRs too, the same filters can also hold on a PR no one
  may advance: that hold survives in-flight = 0, and it is a human gate like any other, so it
  belongs in the held set rather than keeping the loop alive.
- **A foreign claim is not a human gate.** An item skipped by the Claimed filter is another
  session's in-flight (`mine: false`) and resolves when that session merges, no human needed. A
  tick whose holds include an active foreign claim is idle, not stalled — keep looping.

**Both carve-outs survive the new conjunct unchanged**, and PR rows weaken neither: a
self-resolving hold still requires in-flight > 0, and another session's open PR is that session's
in-flight, resolving when it merges. A foreign claim is therefore not a human gate, and the union
above cannot turn one into a PR row either — a foreign in-flight issue is `mine: false` and not
blocked, so neither half of the union reaches it. The safety rails carry the same rule for the
tick as a whole.

**Confirm across two consecutive ticks before stopping** — a single stalled tick may be racing
another session that is about to close a dependency, unblock an issue, or merge a PR. Ticks share
no memory, so persist the observation next to the §5 batch manifest, in
`.git/dispatch-ready-stall.json`: the held set — held issue numbers AND held PR numbers — with each
one's hold root (the open `Depends on #N` it chains to, the `blocked` label, the decision gate, the
Blocking finding a held PR carries).

**"Matches exactly" compares the identifiers and each one's hold ROOT, never the rendered
sentence.** Two honest ticks word the same hold differently, and a comparison over free text never
converges; a comparison over identifiers alone confirms a stall across two genuinely different
states, since a PR whose gate changed between ticks is still the same number. A record written
before this section grew PR rows carries issue numbers only: it cannot match a hold-set containing
a PR, so it is discarded and rewritten, which costs one extra tick and never a false confirmation.

**The record is written from the held set, never from `ready[]`**, which is what makes it reachable
with Ready empty. Before #282 it was written only inside a branch that required Ready non-empty, so
in the uncovered state the two-tick clock never started and there was nothing to confirm. A
hold-set of nothing but PRs starts that clock exactly like any other.

- **No record, or the recorded hold-set differs from this tick's** → write this tick's hold-set
  and finish normally, appending to the tick report:
  `stall: suspected — nothing in flight and nothing this loop may advance; an identical hold-set next tick ends the loop`.
- **Record matches this tick's hold-set exactly** → STALLED is confirmed. Delete the record and
  announce loudly, naming the reason **per held item** so the human knows exactly what unlocks
  the queue — PR rows alongside issue rows, each naming the PR and the gate holding it:

```text
DRAIN STALLED — nothing dispatchable, nothing in flight, and nothing this loop may advance:
  #103 #104 #105 #106 #108 → chain to #102 (parked in Backlog: awaiting planning session)
  #22 → blocked label (dispatch-ready: 2 failed attempts — CI check needs a human call)
  PR #279 (#273) → open, issue blocked (3 Blocking review findings, redispatch spent)
Loop <id> cancelled — resolve the gate(s), then restart the drain.
```

Then take the **same stop path as DRAIN COMPLETE** below — one path, never a parallel one. A held
set of nothing but PRs takes that same path: it is a terminal state like any other, and the cron
self-cancel below is not optional on it.

Any tick that dispatches, merges, observes in-flight work, or sees an open PR it may still advance
deletes a leftover `.git/dispatch-ready-stall.json`: progress resets the confirmation clock. **A
tick that does both** — merges the last in-flight PR and still ends holding something — deletes the
record first and then writes this tick's hold-set: progress wins, and the new hold-set starts a
fresh two-tick count rather than inheriting the old one's.

### Stop path — both terminal states

Stop the loop yourself, according to how this tick was invoked:

| Mode | Recognize it by | Stop path |
| --- | --- | --- |
| **Self-paced loop** (ScheduleWakeup) | This tick was woken by a wake-up the previous tick scheduled | Do not schedule another wake-up — the loop ends here |
| **Cron / fixed interval** (CronCreate-backed) | A cron job fires the skill on a schedule | **Self-cancel the cron** — see below. Do not merely advise the user to cancel; act |
| **Manual invocation** | No loop context | Nothing to cancel — announce and finish. A stalled manual tick announces STALLED immediately: the two-tick confirmation gates loop cancellation, and there is no loop |

**Cron self-cancel.** Find the loop's job id yourself: run `CronList` and select the job whose
prompt is this dispatch-ready invocation.

- **Exactly one match** → `CronDelete <id>`, then append to the report — after COMPLETE: `Loop
  <id> cancelled — run groom-backlog to refill Ready and start a new drain when there's more to
  ship.`; after STALLED: `Loop <id> cancelled — resolve the gate(s), then restart the drain.`
- **Zero, multiple, or ambiguous matches** → delete NOTHING. Announce the terminal state, list
  the candidate ids, and tell the user to `CronDelete` the right one. Deleting the wrong job is
  worse than a few extra no-op ticks.

Safety rails: self-cancel ONLY on a terminal state confirmed above. For DEGRADED, a single
degraded tick, a `healthy` verdict, an `unknown` verdict, a `no verdict` run, a red check, a
genuinely pending check
or an active foreign claim all mean the loop may still make progress — stay alive. For COMPLETE, anything still
claimed or an open PR this loop tracks — the union §7's discriminator ranges over, in-flight until
actually MERGED per §3 — means the drain is not complete; the veto and the held set must range over
the same set, or the state they disagree about ticks forever.
For STALLED, any dispatch, any in-flight work (mine or foreign), an open PR this loop may still
advance, an empty held set, or a hold-set that changed since the recorded tick means the loop may
still make progress — stay alive. An API-failure tick never self-cancels and never counts toward
stall confirmation. Ticks that fire between confirmation and cancellation are no-ops, not errors:
each re-runs this section and retries.

## Guardrails

- **Ready only.** Everything else is groom-backlog's job — dispatch-ready never promotes, never grooms, never
  files issues.
- **Hard cap `max_in_flight`**, counting carry-over from previous ticks, not just this tick's
  dispatches. A stack chain is one slot, not one per layer.
- **Never dispatch a partial chain**, and never split one across parallel agents. If any member is
  claimed, blocked, or missing from Ready, the whole chain waits.
- **Idempotent ticks**: every action re-checks live GitHub state first; a crashed tick must be
  safely re-runnable, with worktrees reclaimable via the batch manifest.
- **Single-writer**: only the coordinator merges or enqueues; max one redispatch per issue without
  a human.
- **Never merge past a Blocking review finding**, and never park one back in Ready — one redispatch
  carrying the finding, then `blocked`. A review that could not run, or that ran and never came
  back, is reported under its own name and the PR is held — never passed over in silence, and
  never waited out.
- If `sassy-dog:pr-shepherd` or take-it is missing, STOP and say so — do not improvise
  dispatch or merge mechanics.

Apply any `## extra-sequencing` section from config as additional §4 filters.
