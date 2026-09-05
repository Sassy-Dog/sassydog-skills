---
name: setup-config
description: >
  This skill should be used when the user asks to "set up the config for this repo", "set up this
  repo's sassy-dog config", "configure this repo's workflow skills", "configure survey-work for
  this repo", "configure send-it here", "set up the workflow config", "bootstrap the sassy-dog
  config", "refresh this repo's sassy-dog config", "re-sync this repo's workflow config", "update
  the workflow config", "migrate this repo to config-based workflow skills", "move the workflow
  skills to config", "adopt the legacy hand-written workflow skills", or "declare the sassy-dog
  plugin in this repo's settings". Writes and re-syncs a repo's `.claude/sassy-dog/*.md` workflow
  config plus its `.claude/settings.json` marketplace + plugin declaration, and migrates repos
  still carrying older generated skills under `.claude/skills/`. Run from inside the target
  repository.
---

# Setup Config

Configuration generator for the workflow family. The six skills themselves — `survey-work`,
`groom-backlog`, `take-it`, `dispatch-ready`, `send-it`, `tidy-repo` — ship generically in this
plugin. This skill writes the **per-repo config** they read:

```text
.claude/sassy-dog/<skill>.md      # YAML frontmatter (facts) + ## sections (prose)
.claude/settings.json             # extraKnownMarketplaces + enabledPlugins declarations
```

The format is `references/config-contract.md`. **Read it before writing anything.**

This skill does **not** render skill bodies. A repo that still has
`.claude/skills/{plate-it,fill-it,take-it,drain-it,send-it,clean-it}/` is on the superseded
architecture and needs **migrate mode** (Phase 3).

## Two rules that shape everything here

**Configure only what cannot be derived.** Repo slug, default branch, and `delete_branch_on_merge`
come from `gh repo view` at runtime and never appear in config. A configured value is a value that
can drift — see the drift incident recorded in `references/config-contract.md`.

**Re-verify every configured fact against live state.** Never copy a fact forward from an existing
render or config just because it is written down. `merge_queue` in particular has no `gh repo view`
equivalent and must be read from GraphQL:

```bash
gh api graphql -f query='{repository(owner:"OWNER",name:"NAME"){mergeQueue(branch:"BRANCH"){id}}}' \
  --jq '.data.repository.mergeQueue != null'
```

## Phase 0 — locate and pick the mode

Confirm cwd is a git repo with a GitHub remote:

```bash
gh repo view --json nameWithOwner,defaultBranchRef,deleteBranchOnMerge,visibility
```

`visibility` is on that call for one reason and is read exactly once: it seeds `review_site:`
(Phase 1). Extend this call rather than adding a second one — and never re-read it on a refresh,
for the reason Phase 4 gives.

**Probe the remote before trusting the checkout.** Every signal the mode table reads lives in the
working tree, and the working tree can be days stale. Fetch, then list what the remote default
branch actually carries (BRANCH is `defaultBranchRef` from the probe above — never assume `main`):

```bash
git fetch origin --quiet
git ls-tree --name-only origin/BRANCH .claude/ .claude/sassy-dog/
```

Route on the **union** of local and remote state. Either remote signal means the checkout is
stale, not un-migrated:

- The remote has `.claude/sassy-dog/*.md` that the local checkout lacks — the migration already
  landed on the default branch.
- The remote no longer carries `.claude/skills/` directories the local checkout still has — the
  deletion half of the same landed migration.

On either signal, instruct a fast-forward pull of the default branch, then **re-probe before
picking a mode** — a remote-migrated repo lands in update mode, never migrate mode. This was hit
live (tailoredtip, 2026-08-08): a 9-day-stale checkout still carried the four marker-bearing
`.claude/skills/` directories, Phase 0 picked migrate mode from local state alone, and the entire
extract/interview/preview/write/delete pipeline ran before rebase conflicts against the remote
exposed that the migration had landed the day before. The probe costs one fetch; the failure it
prevents is all of that work built on a vanished premise.

With local and remote in agreement, pick exactly one mode:

| Found | Mode |
| --- | --- |
| `.claude/skills/<name>/SKILL.md` carrying a `generated-by:` marker | **migrate** (Phase 3) |
| `.claude/sassy-dog/*.md` already present | **update** (Phase 4) |
| Legacy hand-written `*plate-it*` / `*get-it*` / `*send-it*` / `*clean-it*`, no marker | **adopt** (Phase 5) |
| None of the above | **create** (Phase 6) |

**Marker recognition accepts every producer name.** Match on the `generated-by:` prefix and accept
`refresh-skills` (plugin 2026.7.22 until this skill became `setup-config`),
`refresh-sassydog-skills` (plugin 0.9.0–2026.7.21), and `create-dev-workflows` (≤ 0.8.1). Match it
**anywhere in the file** — older renders put it on line 1, where the loader could not parse the
frontmatter, and hand-fixes moved it. A repo whose marker is not recognised falls through to adopt
or create mode and its config is silently lost, so this matcher is load-bearing.

`setup-config` is deliberately **absent** from that list, and must stay absent. The list is frozen
history: it matches only the superseded generated-skills path (`.claude/skills/<name>/SKILL.md`),
and the `.claude/sassy-dog/*.md` config this skill writes carries **no** `generated-by:` marker at
all. A `setup-config` marker has never existed to recognise.

## Phase 1 — detect

Read `references/detection.md`, run `scripts/detect-capabilities.sh` from the repo root, and do the
listed hand-checks (Sentry project **verified by culprit**, review-orchestrator agents, mobile
workflows). Detection output is evidence, not truth — consequential fields get confirmed in Phase 2.

### Seed `review_site` — once, from visibility, then never again

`take-it.md` and `dispatch-ready.md` each carry a `review_site:` key deciding **where** their review
gate runs: in each dispatched sub-agent before its PR opens (`agent`), or in the dispatching loop
after each PR opens and before it merges (`coordinator`). Resolve it from the `visibility` field of
the Phase 0 probe and write the resolved value **explicitly** into both files:

| `visibility` | `review_site:` |
| --- | --- |
| `PUBLIC` | `agent` |
| `INTERNAL` / `PRIVATE` | `coordinator` |

**Write the resolved value, never the rule that produced it,** and never leave the key out so a
skill can read visibility at run time. A derived `review_site` means a later visibility change
silently rewrites the repo's review architecture — taking a repo private downgrades pre-PR review
to after-the-fact review with nothing announcing it, the failure class issue #187 documents.
`references/config-contract.md` → `review_site` carries the full argument; read it before
"simplifying" this key into a derivation.

Exposure is only the *default* grounds for the choice, so the seeded value is a proposal like any
other: show it in the preview, and let the user override it on cost, latency, or a wish for
stricter review than the repo's visibility implies.

**The Sentry hand-check is a verification, not a listing.** An MCP project listing proposes
candidates; **name similarity is not evidence**, because a Sentry project and a repo can share a
name and belong to different codebases. Sample the candidate's recent issues and confirm their
`culprit` / route / file paths resolve in *this* repo. Unverified — including no MCP server and no
issues to sample — writes `sentry: none` (the confirmed-absent form, `references/config-contract.md`),
never a guessed block. The sibling-checkout prior-claim scan is best-effort and secondary; it never
substitutes for the culprit check and never blocks the run.

## Phase 2 — interview

Read `references/interview.md`. Ask only policy questions and unconfirmable facts. Merge policy is
**always** confirmed against live state, never asked from memory — a wrong merge policy is the most
expensive mistake this generator can make.

**Never default a confirmed-absent `none`.** `testflight: none`, `posthog: none` and `mobile: none`
are written only on an explicit answer to interview §2c — detection may propose one, but a quiet
tree is not a confirmation, and a guessed `none` retires a real blind spot with nothing announcing
it. (`sentry: none` is the exception in the other direction: it is never asked, it is what a failed
culprit check records.)

In migrate mode most answers come from the existing render; ask only about what it cannot supply.

## Phase 3 — migrate mode

Converts a repo from generated skills to config. Read `references/migrate-mode.md` first.

The essential shape:

1. **Extract** facts and `BEGIN/END PROJECT-SPECIFIC` fence contents from each generated SKILL.md
2. **Re-verify** every extracted fact against live state — extracted values are *stale by default*
3. **Map** legacy names to current config files per `references/migrate-mode.md` Step 3
   (`plate-it` → `survey-work.md`, `fill-it` → `groom-backlog.md`, `drain-it` →
   `dispatch-ready.md`, `clean-it` → `tidy-repo.md`), carrying each skill's prose
4. **Write** `.claude/sassy-dog/*.md` + merge `.claude/settings.json`
5. **Preview** the full config and the exact list of directories to be deleted
6. **Delete** the old `.claude/skills/<name>/` directories only after approval

**Order is not negotiable: write config, verify, then delete.** The generated skill is the *source*
the config is extracted from. Deleting first destroys the only copy of the repo's Sentry projects,
board IDs, scan paths, and project-specific prose.

**Never touch a directory without a `generated-by:` marker.** Hand-written skills that happen to
sit alongside — `qr-ninja-design`, `what2wear-clean-it`, velovate's `terraform-apply` — are not
yours.

## Phase 4 — update mode

The repo already has `.claude/sassy-dog/*.md`. Re-run detection, re-verify every fact against live
state, and diff the result against the committed config.

**Frontmatter is regenerated; `##` prose sections are carried across verbatim.** That split is the
whole point of the format — prose is the thing a refresh must never rewrite.

**`review_site:` is a fact this phase must NOT re-derive.** It was seeded from visibility at
setup and is carried forward unchanged; re-reading visibility here is precisely what would flip a
repo's review architecture on the first refresh after a visibility change, with the change invisible
in every run's output. If live visibility no longer matches what the configured value implies,
**stop and surface both sides** — the same shape a `merge_queue` disagreement gets — and let the
user decide. If the key is absent because the config predates it, propose the seeded value as an
addition and say so in the preview; until then the reading skills default it to `agent`.

**`execution_site:` is the same kind of fact, for a different reason.** It names the workstation
this checkout answers to, and nothing derives that: the platform says what kind of machine this is,
never what the user called it, so re-deriving would overwrite a `vdi` with `windows` on the very
checkout the name exists for. **Carry an existing value across verbatim.** Where the key is absent,
a platform-derived name (`darwin` → `mac`, `win32` → `windows`) may be *proposed* in the preview and
never written silently — the user owns the name. A disagreement is surfaced, never applied.
`config-contract.md` carries the key's contract; `references/update-mode.md` the operational half.

**The three `none` answers are carried forward, not re-asked** — but an **absent** one is asked.
**`sentry: none` is not one of them.** `testflight: none`, `posthog: none` and `mobile: none` each record
a human's confirmation, so re-litigating them on every refresh reopens exactly what the form closed.
The one signal that reaches an existing value is *positive* evidence — an iOS target under a
`mobile: none`, a PostHog SDK under a `posthog: none` — and that is a **stop and surface** like any
other disagreement, never a silent rewrite. **Where one of the three is missing entirely (or carries
a `posthog: false`), put interview §2c to the user for that key**: every consumer repo predates this
form, so absent is the state they are all in, and a refresh that only carries values forward would
change nothing anywhere.

**`sentry: none` is re-derived on every refresh, like any other fact.** It is written when the
culprit check fails *or could not run* — no MCP server, no issues to sample — which are conditions of
the session, not facts about the repo. Freezing it would let one unlucky run permanently retire the
plate's highest-signal surface with no path back, since the only contradicting evidence is the check
that was skipped. See `references/update-mode.md`.

Apply per file, on approval only.

## Phase 5 — adopt mode

Legacy hand-written skills with no marker. Read `references/update-mode.md`. Side-by-side review of
every hand-written section, the user decides per section (fold into config prose / promote upstream
as plugin feedback / drop), then the legacy directories are deleted on approval.

## Phase 6 — create mode

No prior state. Interview, then write config. **Print every file in full and write only after the
user approves** — writing into a product repo is outward-facing and never silent.

## Phase 7 — verify

1. Every written `.claude/sassy-dog/*.md` parses: `---` on line 1, valid YAML frontmatter, `##`
   sections intact.
2. `.claude/settings.json` is valid JSON and declares **both** the marketplace
   (`extraKnownMarketplaces`) and the plugin (`enabledPlugins`). **This is the step most likely to
   be skipped**, because everything works locally without it — plugin skills enabled only in *user*
   settings do not transfer to cloud sessions or scheduled routines, and `enabledPlugins` without
   the marketplace declaration leaves cloud sessions unable to resolve `@sassydog-skills` at all,
   so a scheduled `dispatch-ready` silently finds no skill while every local session passes.
3. In migrate mode: `.claude/skills/` contains no marker-carrying directory, and every unmarked one
   still exists.
4. Remind: config is read at skill invocation, so it takes effect immediately — no session restart
   needed, unlike the old generated skills.
5. Suggest a first run: `plate it`, then `send it` on a trivial branch.

## Guardrails

- Never write into the target repo without showing full content and getting approval.
- Never delete a directory lacking a `generated-by:` marker.
- Never delete generated skills before their config is written and verified.
- Never copy a fact forward without re-verifying it against live state — except `review_site:`,
  which is seeded once and carried forward by design; `execution_site:`, which names a machine no
  live state can name back and is likewise carried verbatim, the platform default being a proposal
  into an ABSENT key only; and the three confirmed-absent `none` forms
  (`testflight:`, `posthog:`, `mobile:`), which record a check that already happened.
  **`sentry: none` is not one of them**: it is re-derived on every refresh, because it is also
  written when the culprit check merely could not run, so freezing it would retire the plate's
  highest-signal surface with no path back (Phase 4, `references/update-mode.md`). A
  live-visibility mismatch is surfaced, never applied.
- Prose in `##` sections is user-owned: carried across verbatim, never rewritten or summarised.
- This skill always runs from the plugin; it is never copied into a consumer repo.
