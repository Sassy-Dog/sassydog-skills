---
name: github-issues
description: >
  This skill should be used when the user asks to "snapshot the project board", "show the board
  by status", "pull the backlog with labels", "find stale issues", "which issues shipped but are
  still open", "find stub issues that need scoping", "file an issue but check for duplicates first",
  "dedupe before filing", "link this Sentry or feedback item to a GitHub issue", or any task
  involving GitHub issue/board reads via gh + GraphQL, label taxonomy, stale-issue detection, or
  gated dedupe-then-file issue creation. Also triggers when a project workflow skill (a generated
  survey-work or take-it) invokes sassy-dog:github-issues by name.
---

# GitHub Issues

Issue and ProjectV2 board operations for any GitHub repo: board snapshots, backlog reads, stale-issue detection, idempotent dedupe-then-file issue creation, and the fill/drain label-state transitions. Reads are free; **this skill bundles exactly two write paths — `scripts/file-or-link-issue.sh` (issue creation, preview-then-confirm) and `scripts/issue-claim.sh` (label-state transitions, dry-runnable)** — plus one it points at, `${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh`, which owns the engineering-dimension and severity half of the label taxonomy.

## Reads

### Board snapshot (grouped by status column)

```bash
PROJECT_NUMBER=<n> OWNER=<org> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/board-snapshot.sh
```

Emits `{counts, truncated, items[]}`. If `truncated: true`, raise `PROJECT_LIMIT` — the newest issues are what got dropped. For board ID discovery (project/field/option IDs), card moves, and the board-vs-labels source-of-truth question, read `references/board-graphql.md`.

### Backlog via labels

Some repos run label-driven backlogs with an empty board — an empty snapshot does not mean no backlog:

```bash
gh issue list --repo <R> --state open --limit 200 --json number,title,labels,updatedAt
```

### Boardless work-queue snapshot (fill/drain)

One call replaces the per-tick ready/in-flight/blocked list reads AND parses the two machine-readable body contracts (`touches:` collision sets, literal `Depends on #N` lines) in one place:

```bash
REPO=<owner/name> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/queue-snapshot.sh
```

Emits `{repo, me, ready[], in_flight[], blocked[]}` — `ready` ordered number-ascending with `touches`/`depends_on`/`unannotated` per issue; `in_flight` carries a `mine` flag rather than silently filtering to @me, so a loop can count its own claims while still seeing other sessions'. Judgment (touches-set intersection, priority, the smell test) stays with the caller — this is a read, not a dispatcher.

### Reference check (grooming drift)

Resolves an issue body's code references against a real checkout — paths,
symbols, and `-p` package args:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/verify-issue-refs.sh <N> --tree /path/to/checkout --format text
```

Bodies get written from plans and older issues while the tree moves underneath
them, producing specs whose types and invariants are right and whose *locations*
are fiction — which reads as perfectly dispatchable. Exit `3` means at least one
`likely-drift` finding; `0` means none.

**The tier is the point, not the absence.** Every issue names things that do not
exist yet, so unresolved-means-broken would flag the whole backlog. A finding is
`likely-drift` only when something *close* exists — an invented reference is
usually nearly right, which is what lets it survive review: a near-match symbol,
a package missing its workspace prefix, a near-match **sibling file** in the
directory the path names. Everything else is `likely-new` and is reported
without gating.

**Two path rules keep the gate credible.** A path from a `touches:` line is
never drift — `touches:` declares what the PR will *write*, so it names files
that do not exist yet by design. And for any other path, "its parent directory
exists" is where the checker goes looking for evidence, not evidence in itself:
without a near-match sibling it stays `likely-new`. Gating on the bare location
fired on every new file added to an existing directory, every tick, until the
operator learned to skim past the gate — which is exactly when a real finding
slips through (issue #199). The cost is real and accepted: an invented path with
nothing resembling it beside it is no longer caught.

Run it in **both** places, because two different failure modes look identical in
the text: a reference that never existed is catchable at grooming, while one
that a later merge renamed was true when written and only a re-check at dispatch
can see it.

It resolves references; it does not read code. An issue proposing a helper that
duplicates a shipped one under another name passes clean.

### Gotcha check (config claims that rot)

Resolves a `groom-backlog` config's `gotcha_summary` against real issue state,
before `groom-backlog` copies any of it into an issue body:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/verify-gotcha-claims.sh --config <repo-root>/.claude/sassy-dog/groom-backlog.md --repo <owner/name>
```

`gotcha_summary` is prose in a frontmatter slot, so nothing recomputes it and no
human curates it — it is the one config field that can assert a time-varying fact
and never be revisited. One repo's asserted "#15 is not finished — #308 (updater)
and #334 (Windows + Authenticode) remain" for nine days after all three closed
(issue #249), aimed at a cold worktree agent with no way to check it.

**Callers inject the text between the SAFE GOTCHAS markers, never the raw field.**
Exit `3` means at least one claim was dropped. A claim citing `#N` survives only
when its asserted state is explicit and currently true; wrong, ambiguous, and
**unresolvable** all drop. There is deliberately **no skip exit** — a missing
`gh` or an undetermined repo makes every citing claim unresolvable, so unknown is
held rather than passed through. Claims citing no issue are invariants and are
kept, annotated `KEEP time-varying` when they carry a date or a roadmap position
that nothing here can resolve.

`--lint` is the offline half — no `gh`, no network — reporting the four banned
shapes (issue-ref, state-verb, dated, roadmap) so an existing config carrying
them can be named at refresh rather than carried forward. The rule those shapes
come from is `sassy-dog:setup-config` → `references/config-contract.md`.

### Stale-issue detection

```bash
REPO=<owner/name> bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/stale-issues.sh
```

Two buckets: `shipped-but-still-open` (merged PR referenced the issue only in a title parenthetical — never auto-closed) and `stub-body` (needs scoping). **Before flagging a stub to the user, read its comments** — `gh issue view N --comments` — scope often lives in a follow-up comment.

## Writes: dedupe-then-file

Read `references/dedupe-and-file.md` before the first write of a session. The contract in brief:

1. The caller's qualifying gate runs first (this skill doesn't judge severity).
2. Idempotency by body marker (`<source>-source: <STABLE_ID>`) — re-runs return the existing issue, never a duplicate.
3. **Preview-then-confirm**: dry-run the batch, show `would-file` results, file only on approval.
4. **Burst rail**: > 5 would-file in one run → stop and show the list; consider one umbrella issue.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/file-or-link-issue.sh \
  --repo <owner/name> \
  --marker "sentry-source: PROJ-123" \
  --title "<title>" --body-file /tmp/body.md \
  --labels "bug,sentry-escalation" \
  --ensure-label "sentry-escalation:9c846b:Auto-filed from a Sentry hit" \
  --project-id PVT_xxx --status-field-id PVTSSF_xxx --status-option-id <backlog-id> \
  --dry-run
```

Output actions: `filed` / `already-linked` / `filed-no-board` / `would-file`. Board placement is optional and degrades gracefully.

## Writes: label-state transitions (fill/drain claims)

The org label taxonomy has **two canonical homes, disjoint by design.** Neither script defines the other's labels — two homes for one label is precisely the drift both exist to prevent:

| Subset | Canonical home | Written |
|--------|----------------|---------|
| dev-workflow **state**: `ready`, `in-progress`, `blocked` | `scripts/issue-claim.sh` (this skill) | ensure-created at the claim/promote/block transition that needs it |
| signal escalation: `sentry-escalation` | value in `scripts/issue-claim.sh`'s table | written by `scripts/file-or-link-issue.sh --ensure-label`, whose caller quotes that row |
| engineering **dimensions + severity** (10 + 4) | `${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh` | applied repo-wide, ambient classification (below) |

Dependabot's per-ecosystem labels (`javascript`, `github_actions`, `rust`, `dart`, …) are auto-created and correctly differ per repo — no script here touches them.

`scripts/issue-claim.sh` is the canonical home of the boardless dev-workflow label taxonomy — those labels, their colors, and their descriptions are defined in the script, nowhere else. Read them from the script itself with `issue-claim.sh taxonomy` (emits `name|color|description`, needs no gh/jq/repo); the table below is the same data for humans:

| Label | Color | Meaning |
|-------|-------|---------|
| `ready` | `38fa99` | Dispatchable: a cold worktree agent could ship this (groom-backlog promoted) |
| `in-progress` | `190132` | Claimed by a take-it/dispatch-ready loop |
| `blocked` | `52363d` | Needs a human decision before it can be dispatched (dispatch-ready demoted) |
| `sentry-escalation` | `9c846b` | Auto-filed from a Sentry hit |

**The colors are measured, not chosen.** All four used to share a hex exactly with a canonical label from the other taxonomy (`ready`/`sev:low`, `in-progress`/`architecture`, `blocked`/`sev:critical`, `sentry-escalation`/`sev:critical`) — ΔE 0, on issues that carry one label from each set. The replacements are the maximum-separation point of a CIEDE2000 sweep over the union of both taxonomies; `align-labels.sh --collisions` now gates the pair. Don't nudge them toward a palette default.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/issue-claim.sh \
  <claim|release|block|promote|demote> <N> [N ...] \
  [--repo <owner/name>] [--comment "why"] [--force] [--dry-run]

bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/issue-claim.sh \
  sync-labels [--repo <owner/name>] [--dry-run]      # reconcile the 4 labels, touch no issue
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/issue-claim.sh taxonomy
```

- `claim` — assignee @me + `in-progress`, strips `ready`; **skips issues already assigned to someone else** (double-pick guard; `--force` overrides).
- `release` — strips `in-progress` (post-merge: `Closes #N` closes the issue but never strips labels).
- `block` / `demote` — **require `--comment`**; a demotion without a reason is a silent failure for the next human.
- Every label is reconciled before use: created when absent, **corrected when its color or description has drifted**, untouched when it already matches. A colour change therefore reaches repos that already carry the label — it used to be `gh label create || true`, which fails on an existing label and silently left every onboarded repo on the old colour forever.
- `sync-labels` does that reconcile for all four labels in one pass without touching an issue — the entry point for propagating a taxonomy change to a repo that isn't currently transitioning anything. `--dry-run` previews.
- Mutations route through pr-shepherd's `gh-retry.sh`; one JSON line per issue on stdout (`sync-labels` emits one per label); batch continues past per-issue failures (exit 2 if any hard-failed). A label reconcile that fails never fails the claim, but it is always announced on stderr.

## Writes: canonical dimension + severity labels

`${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh` — plugin root, **not** this skill's `scripts/` — is the canonical home of the other half: the 10 engineering dimensions (`architecture` `assessment` `ci-cd` `dx` `infra` `observability` `security` `tech-debt` `testing` `epic`) and the 4 severities (`sev:critical` `sev:high` `sev:medium` `sev:low`). Colors and descriptions live in that script's table and are deliberately **not** mirrored here — a second copy is the drift the table exists to prevent. Read them with `--check`.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo <owner/name> --check     # drift report, exit 3 if drifted, no writes
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo <owner/name> --dry-run   # same pass, always exit 0
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo <owner/name>             # create missing + correct drifted
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --collisions                    # cross-set colour check only, no repo
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh taxonomy                        # the table as data, no repo
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo <owner/name> --migrate <plan> --dry-run
bash ${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh --repo <owner/name> --migrate <plan>
```

- Idempotent: it creates what is absent and corrects color/description/case drift, so an already-aligned repo issues zero writes. One JSON line per label on stdout, summary on stderr.
- **The default pass never deletes a label and never relabels an issue.** Only `--migrate` can, and it is the one destructive capability in this plugin.
- **`--migrate <plan>` folds a repo's one-off labels onto the canonical set: relabel first, delete second, structurally.** `<plan>` is data — one `<repo>|<old>|<new>` per line, `#` comments allowed, `-` reads stdin — so one file drives every repo and each run processes only the lines matching `--repo`. Deleting a label strips it from every issue carrying it, unrecoverably, so `gh label delete` has exactly ONE call site in the script, inside `migrate_delete_gate()`, whose own body re-queries GitHub immediately above it and withholds the delete on every path that is not "zero issues still carry the old label" — a failed or truncated re-query included, because unknown is not verified. Held-back mappings are named on stderr and exit 4. Run `--dry-run` first and read it: the preview names every issue it would relabel and every label it would then gate a delete on. Targets are never invented — run the align pass first — and a mapping touching `ready` / `in-progress` / `blocked` / `sentry-escalation` is refused (exit 64) before any network call, because those belong to the other taxonomy.
- Three colors sit deliberately off their modal palette value so chips stay distinguishable (`security`, `tech-debt`, `epic`), and `infra`'s was picked by measured perceptual distance. The script header records which collision each one escaped; don't "tidy" them back.
- **Cross-set check.** Each taxonomy used to validate only against itself, which is how four pairs reached ΔE 0. `--collisions` scores every (dev-workflow × canonical) pair with CIEDE2000 and fails below ΔE 10; `--check` runs it too and folds a hit into its exit 3. It reads the dev-workflow colors from `issue-claim.sh taxonomy` rather than copying them — a shared *check*, never a shared *table*.
- **`taxonomy` is the mirror of that emitter**: `name|color|description` per canonical label, no gh, no jq, no repo, no network. A consumer that needs the table as *data* reads it here; one that needs it *applied* runs the align pass. Neither transcribes it — `assess-it` did, froze at the pre-#158 colours, and painted a collision into every repo it audited (issue #167). Gate 8 of `scripts/preflight.sh` now fails on any taxonomy colour that appears outside its home.

## Bundled scripts

| Script | Purpose |
|--------|---------|
| `scripts/board-snapshot.sh` | ProjectV2 snapshot grouped by status. Read-only. Guards the `--limit` truncation trap. |
| `scripts/queue-snapshot.sh` | Boardless fill/drain queue read: ready/in-flight/blocked buckets + parsed `touches:` and `Depends on #N` body contracts. Read-only. Exit 10 skip convention. |
| `scripts/verify-issue-refs.sh` | Resolves a body's paths, symbols, and `-p` package args against a checkout. Tiers each miss `likely-drift` (something close exists — a near-match symbol, package, or sibling file) vs `likely-new` (nothing resembles it, or the path came from `touches:`), and suggests the near match. Read-only. Exit 0 clean / 3 drift / 10 skipped / 64 usage. |
| `scripts/verify-gotcha-claims.sh` | Resolves a `groom-backlog` config's `gotcha_summary` against issue state and emits only the claims that survive, between SAFE GOTCHAS markers. Fail-closed: wrong state, ambiguous assertion, and unresolvable all drop, so there is no skip exit. `--lint` reports time-varying shapes offline. Read-only. Exit 0 clean / 3 dropped or found / 64 usage. |
| `scripts/stale-issues.sh` | shipped-but-still-open + stub-body + tracking-parent-complete detection. Read-only. Handles compound PR-title refs like `(#419 + #421)`. Detector 3 reads the epic-split `Part of #<parent>` convention with a prefix guard (`#28` never claims `#283`'s children) and reports `truncated: true` — never a clean-looking empty result — when its all-state pull hits `ALL_LIMIT` (default 500). |
| `scripts/file-or-link-issue.sh` | Write path #1: issue creation. Marker-keyed create-or-find + optional board add. `--dry-run` for previews. |
| `scripts/issue-claim.sh` | Write path #2: fill/drain label-state transitions (claim/release/block/promote/demote), plus `sync-labels` (reconcile the taxonomy, touch no issue) and `taxonomy` (print it). Owns the dev-workflow half of the label taxonomy; labels are created *and corrected* in place; `--dry-run`; retries via pr-shepherd's `gh-retry.sh`. |

Not bundled here but paired with it: `${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh` owns the dimension + severity half. It lives at the plugin root because it aligns a whole repo rather than serving one issue-flow call.

## Guardrails

- Never `gh issue create` directly when filing from an automated signal — route through `file-or-link-issue.sh` so idempotency and markers can't drift.
- Never hand-roll `gh label create` or claim-label `gh issue edit` calls in a fill/drain flow — route through `issue-claim.sh` so the taxonomy (names, colors, descriptions, the double-pick guard) can't drift.
- Never hand-roll the dimension/severity labels either — route through `align-labels.sh`, and never define a label in both scripts: one label, one home.
- Mutating board calls go through pr-shepherd's `gh-retry.sh` (Projects GraphQL flakes); board claims are best-effort, never a hard failure.
- Signal escalated on an existing issue → comment on it, don't re-file.
