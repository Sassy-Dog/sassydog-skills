# Repo config contract

The generic workflow skills — `survey-work`, `groom-backlog`, `take-it`, `dispatch-ready`, `send-it`, `tidy-repo` —
ship one implementation each in the plugin and read their per-repo behavior from:

```text
<repo-root>/.claude/sassy-dog/<skill-name>.md
```

One file per skill. Each file is YAML frontmatter (facts and toggles) followed by `##` sections
(freeform prose). This document is the source of truth for that format; `setup-config`
writes these files and the six skills read them.

## Governing principle: configure only what cannot be derived

Never write a fact into config that the skill can obtain at runtime. A configured value is a value
that can drift; a derived value cannot.

**Always derived, never configured:**

| Fact | How the skill gets it |
| --- | --- |
| Repo slug | `gh repo view --json nameWithOwner --jq .nameWithOwner` |
| Default branch | `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` |
| `delete_branch_on_merge` | `gh repo view --json deleteBranchOnMerge --jq .deleteBranchOnMerge` |
| Current branch | `git branch --show-current` |
| Repo root | `git rev-parse --show-toplevel` |
| Commit co-author trailer | the running model's own name — `Co-Authored-By: Claude <model> <noreply@anthropic.com>` |

This is why no `repo:` or `default_branch:` key appears in the schemas below, even though the old
templates rendered `{{REPO_SLUG}}` and `{{DEFAULT_BRANCH}}` into every generated skill.

**This is not theoretical.** Migrating this repo surfaced two facts that had drifted in its
generated skills: they asserted `delete_branch_on_merge: false` and "there is no merge queue", while
the repo had since enabled both. The derivable one self-corrected the moment it became derived. The
other — `merge_queue`, which has no `gh repo view` equivalent — carried the staleness across, and
only a rejected `gh pr merge --delete-branch` exposed it.

So: the principle removes drift exactly where a fact is derivable, and nowhere else. **A refresh
must re-verify every configured fact against live state**, not copy it forward from the previous
render. `merge_queue` in particular should be checked via the `mergeQueue(branch:)` GraphQL field
rather than asked about or inherited.

**Re-verification is not adoption.** Live state tells you which merge methods the repo *allows*;
config records the one the repo *intends*. Those are different claims, and the allowed set being a
hard constraint does not make it the right answer. A repo can depend downstream on the intended
method — a build number taken from `git rev-list --count HEAD` increments by exactly 1 per merged PR
only while history stays linear squash-merges, so switching to merge commits corrupts version
ordering with no error anywhere. A refresh that derived the allowed set and picked from it would
make exactly that switch, silently, the day someone enabled merge commits.

> **Derive what is *allowed*. Keep what is *intended*. Stop when they disagree.**

Where a repo states an intended method — in this config, in `docs/`, or in its own skills — and
live state no longer permits it, that disagreement is a **stop and surface**: report both sides and
let the user decide which one is wrong. It is never an automatic rewrite of the configured value,
and never a silent adaptation to whatever happens to be allowed today.

## Governing principle: presence is the toggle

The old templates carried paired state — an `IF:SENTRY` flag *and* `{{SENTRY_ORG}}`/`{{SENTRY_PROJECTS}}`
facts — which can disagree. In config, **the presence of a block enables the feature**:

```yaml
sentry:                     # present  -> the Sentry surface runs
  org: sassy-dog
  projects: [qrninja-web]
```

Omit the `sentry:` key entirely and the surface is skipped. There is no `sentry: false` — the one
documented exception to this principle is `sentry: none`, below. The same
holds for `board`, `testflight`, `mobile`, `migrations`, `codegen`, `secret_bootstrap`,
`review_surfaces`, and `claim_label`.

Four keys are genuine scalars rather than blocks, because they carry no sub-facts:

- `merge_queue: true|false` — merge queue vs. direct squash-merge. It carries **intent**, not an
  observation: a refresh re-verifies it against `mergeQueue(branch:)`, but a live state that
  contradicts the configured value is surfaced to the user rather than written over it
- `write_policy: read-only|gated` — whether `survey-work` may file issues under its Sentry gate
- `review_agent: <agent>|skip` — which agent `send-it`'s review gate dispatches. **This key is not
  governed by presence-is-the-toggle at all: it has a default.** Omitting it does not disable the
  gate, it selects the shipped `sassy-dog:pr-review-orchestrator` — see `review_agent` below. Its
  optional companion `review_surfaces:` is an ordinary presence-toggled block with no default, and
  the difference is the point: one chooses *whether* a review happens, the other only *where* paths
  route inside one
- `review_site: agent|coordinator` — **where** the review gate runs on the two dispatching paths,
  `take-it` and `dispatch-ready`. Like `review_agent:` it carries a default rather than an off
  switch (absent selects `agent`), and unlike every other key here it is *seeded from a derived
  fact and then frozen* — `review_site` below says why that is deliberate rather than drift

### The one exception: `sentry: none`

**`sentry: none` is the FIRST documented exception to presence-is-the-toggle, and it is deliberate.**
It is not a `false` flag by another name and it does not reopen paired state: it carries a fact the
absence of the key cannot carry — that someone **checked**, and this repo genuinely has no error
monitoring to point at.

The reason the exception is worth its cost: `setup-config` may only write a `sentry:` block for a
project it has **verified by culprit** against this repo's own code (`references/detection.md`,
"Sentry project — verify by CULPRIT, never by name"). Verification can fail — no MCP server, no
recent issues to sample, or culprits that resolve in some other codebase — and the alternatives are
both worse than a new form. Guessing a same-named project makes the wrong repo claim another
codebase's P0s, silently. Omitting the key instead makes a *finished* check indistinguishable from
one that never ran, so the next refresh re-litigates it and the next guess is one interview away.

Three states, all distinct:

| Config | Meaning | `survey-work` behaviour |
| --- | --- | --- |
| `sentry:` block with `org`/`projects` | verified project | surface runs |
| `sentry: none` | confirmed: this repo has no error monitoring | reported as a blind spot |
| key absent | never configured / unknown | reported as a blind spot (unconfirmed) |

The exception is scoped to `sentry:` alone. No other key has a `none` form, and adding one requires
the same justification: a confirmed-absent state that a reader would otherwise mistake for an
unfinished check.

## Shared blocks

These appear in whichever skill files need them. A repo that uses a project board puts the same
`board:` block in `survey-work.md`, `groom-backlog.md`, `take-it.md`, and `dispatch-ready.md`.

```yaml
board:
  number: 4                 # project number
  owner: Sassy-Dog
  project_id: PVT_kwDO...   # GraphQL node IDs, from board-snapshot.sh
  status_field_id: PVTSSF_...
  ready_option_id: 47fc9ee4
  backlog_option_id: f75ad846
  in_progress_option_id: 98236657

sentry:
  org: sassy-dog
  projects: [qrninja-web, qrninja-mobile]
  gate: defaults            # or an explicit override of the qualifying gate

testflight:
  bundle_id: com.sassy-dog.qrninja

mobile:
  release_workflow: mobile-release.yml
  path_prefix: apps/mobile/

migrations:
  schema_dir: packages/db/src/schema
  dirs: packages/db/src/migrations
  regen_command: bun run db:generate

codegen:
  command: bun run codegen
  output_dirs: apps/web/src/generated
  hint: run codegen after touching any tRPC router

stacked_prs:
  max_depth: 4              # cap on layers a dispatcher will build

secret_bootstrap: eval "$(doppler secrets download --no-file --format env 2>/dev/null)"
review_agent: qr-ninja-review-orchestrator   # override; omit -> sassy-dog:pr-review-orchestrator
review_surfaces:                            # optional; steers the shipped orchestrator only
  "ops/**": sassy-dog:infra-platform-reviewer
review_site: agent                          # where the gate runs on the dispatching paths
claim_label: in-progress
posthog: true
merge_queue: false
```

Omit any block the repo doesn't use — with two exceptions, `review_agent:` and `review_site:`,
where omitting the key selects a default rather than disabling anything.

### `review_agent` — read by `send-it`

`send-it`'s review gate resolves an agent on **every** run; the config only chooses which one:

| Config | Gate behaviour |
| --- | --- |
| `review_agent: <agent>` | dispatches that agent — a repo's own orchestrator wins |
| key absent | dispatches `sassy-dog:pr-review-orchestrator`, the diff-scoped orchestrator the plugin ships |
| `review_agent: skip` | dispatches nothing, and still prints `review: SKIPPED — no review_agent resolved (lint/type/test only)` |

**Omitting the key selects the shipped orchestrator.** It is no longer the off switch it was before
the default existed: the orchestrator ships with the plugin, so it resolves in any repo that has
the plugin and nothing else, which is what makes default-on statable as a rule instead of a
per-repo opt-in. No `send-it` run can therefore silently ship unreviewed. The accepted cost is one
extra review pass of latency and tokens on every `send-it` run in every consumer repo.

**That claim scopes to `send-it`, and a companion key extends it.** `take-it` and `dispatch-ready`
dispatch sub-agents that open their own PRs from a cold worktree and never invoke `send-it`, so
this default cannot reach them on its own. `review_site` below is what carries the gate into those
two paths; `review_agent` still decides *which* agent runs once it does.

A repo that genuinely wants no design review sets **`review_agent: skip`** — an explicit act that
shows up in the config diff, and one `send-it` still reports on the run rather than passing over in
silence. The same SKIPPED line covers a *resolution failure*, which is a different thing: the two
share that line because they share a consequence — a diff nobody reviewed — and a run that printed
nothing would be indistinguishable from a clean review. They do not share urgency, so `send-it`
names which one it hit on the line after; the quoted line itself is fixed.

**The opt-out is spelled `skip`, not `none`.** `none` belongs to the presence-is-the-toggle
exception above, which records a confirmed absence somebody went and checked for; `review_agent` is
not a presence-toggle key at all, so its opt-out overrides a default rather than confirming an
absence — and `skip` names the line the gate actually prints.

### `review_site` — read by `take-it` and `dispatch-ready`

**Where** the review gate runs on the two dispatching paths. `send-it` does not read this key: it
has exactly one site, its own run, and always reviews there.

| Config | Where the review happens |
| --- | --- |
| `review_site: agent` | each dispatched sub-agent reviews **its own diff before it opens a PR** — `send-it`'s posture exactly: Blocking findings are fixed and re-reviewed before the PR body is drafted, so nothing unreviewed reaches GitHub |
| `review_site: coordinator` | the dispatching loop reviews each PR **after it opens**, before it merges — centralised, single writer, one place to read every outcome |
| key absent | `agent` — the fail-safe site, for the same reason an absent `review_agent` selects an agent rather than none |

**This key chooses the site, never the agent and never whether.** Which agent runs is
`review_agent`'s resolution order in the section above — unchanged by this key, and deliberately
not restated here, because an order written twice drifts into an order honoured in neither place.
No value of `review_site`, and no absence of it, turns the gate off. Only `review_agent: skip`
does, and that still prints the SKIPPED line.

**A Blocking finding is never merged past.** On the `coordinator` site `dispatch-ready` treats one
exactly like a failed check — surface it named, one redispatch carrying the finding as context,
then the `blocked` label — and never parks it back in Ready. That path lives in
`dispatch-ready` §2; this key only decides whether it is the path that runs.

**`NO_CONFIG` is not a hole in this.** `take-it` and `dispatch-ready` are the two workflow skills
that stop outright on `NO_CONFIG` rather than degrading, so an unconfigured repo dispatches nothing
and therefore produces no unreviewed PR by this route. The absent-key default covers the other
half: a repo configured before this key existed still gets a review, at `agent`, until its next
`setup-config` run writes a value.

#### Why this key is CONFIGURED and not DERIVED

This is a deliberate exception to *configure only what cannot be derived*, the governing principle
at the top of this document, and the reason has to live beside the key rather than in the commit
that added it.

Visibility **is** derivable — `gh repo view --json visibility` answers it on any run — so a literal
reading of the principle deletes this key and reads visibility live. Do not. **Deriving it live
means a visibility change silently rewrites the repo's review architecture.** Taking a repo private
would downgrade it from pre-PR review to after-the-fact review with nothing announcing the change:
no config diff, no prompt, no line in any run's output. That is the failure class
[#187](https://github.com/Sassy-Dog/sassydog-skills/issues/187) documents — a visibility transition
silently disabling the protections a repo was relying on — and a review architecture that changes
when nobody chose to change it is the same defect with a different subject.

Seeding once at setup and recording the resolved value keeps the derivation's benefit — nobody
hand-picks a default — without the silent flip, and it leaves room to choose on grounds other than
exposure: cost, latency, or a repo that simply wants stricter review than its visibility implies.

So `setup-config` reads visibility **once**, at setup, and writes the resolved value explicitly:

| `visibility` | Seeded `review_site:` |
| --- | --- |
| `PUBLIC` | `agent` |
| `INTERNAL` / `PRIVATE` | `coordinator` |

In a public repo a bad diff is world-visible the instant it is pushed, so pre-PR review earns its
cost; internally that exposure argument mostly evaporates. **A refresh carries the value forward.**
It is the one configured fact update mode must not re-derive from live state — where live
visibility no longer matches what the value was seeded from, that is a *stop and surface*, exactly
as a `merge_queue` disagreement is, and never an automatic rewrite.

### `review_surfaces` — read by `send-it`, steers `pr-review-orchestrator`

**Optional, and omitted by default.** A glob → reviewer map that steers the shipped orchestrator's
path classification — the third tier, between the plugin's built-in heuristics and authoring a whole
agent. A repo whose infrastructure lives in `ops/` rather than `infra/`, or whose executable
artifacts are Markdown, can route those paths to the right specialist without owning an agent.

```yaml
review_surfaces:
  "ops/**":         sassy-dog:infra-platform-reviewer
  "skills/**/*.md": sassy-dog:code-quality-reviewer
  "**/*.bats":      sassy-dog:testing-reviewer
```

**Values are restricted to the nine reviewers this plugin ships** — `architecture-reviewer`,
`code-quality-reviewer`, `security-reviewer`, `testing-reviewer`, `cicd-release-reviewer`,
`infra-platform-reviewer`, `observability-ops-reviewer`, `dx-docs-reviewer`,
`dependency-supply-chain-reviewer` — with or without the `sassy-dog:` prefix, the bare name meaning
the namespaced agent. Nothing else is legal. An agent living in someone's own `~/.claude/agents/`
resolves on the machine that wrote the map and nowhere else, so a map naming one would steer for its
author and steer nothing for everybody else — the same class of failure as fanning out to an agent a
consumer repo lacks ([#236](https://github.com/Sassy-Dog/sassydog-skills/issues/236)).

**An unresolvable value is a loud error, never a skipped surface.** The orchestrator validates the
map before it dispatches anything; on any bad value it discards the **whole** map, classifies by its
built-in table, reviews the diff as it otherwise would, and returns a **Blocking** finding naming
every offending entry. A typo therefore costs the repo its steering and never its review, and
`send-it`'s Blocking → "fix and re-run" mapping is what makes it loud. A partly-applied map is
deliberately not on offer: some paths steered and some not is precisely the state no report could
describe. A glob that matches nothing is not an error — the map describes the repo's layout, not one
diff.

**The map only ever adds routes.** A path it matches goes to the mapped reviewer *in addition to*
every built-in row it already matched; no form of it removes a route. Under-dispatch is invisible
where over-dispatch is merely slower, and an override-shaped map sits one line away from stripping a
route that exists precisely because it is easy to miss — `"**/*.md"` pointed at `dx-docs-reviewer`
would send a repo whose skill bodies *are* its source back to being reviewed as prose. A repo that
needs a route **removed** has outgrown this tier and wants its own `review_agent:`.

**It reaches the orchestrator only through `send-it`,** which forwards it verbatim in the dispatch
brief without validating it; the orchestrator never reads config itself. Two consequences: a
`review_agent:` naming a repo's own agent is handed no map — the key has no contract outside the
shipped orchestrator, and `send-it` reports that on the run — and `take-it` / `dispatch-ready`, which
open their own PRs without invoking `send-it`, never forward one, so the orchestrator falls back to
its built-in classification there. Those two paths do still run a review, under the
`review_site:` key above; it is an *unsteered* one. Forwarding this map to them is a separate change, not something
the key already does.

**`setup-config` never proposes this key.** There is no detection for it and there should not be:
the globs are a deliberate statement about a repo's layout, and a generator guessing them would be
the no-invention rule's failure mode with a config file to make it look considered. It is hand-set,
by a user who asked for it.

### `stacked_prs` — read by `groom-backlog`, `take-it`, `dispatch-ready`, `send-it`

Presence enables GitHub [stacked PRs](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs): `groom-backlog` may propose a `stack:` chain, and the dispatchers may build one. **Absent is the correct value for a repo that has not deliberately opted in**, and it is absent everywhere today.

Three things are deliberately NOT configured here, because they are derived:

| Fact | How it is obtained |
| --- | --- |
| Is this repo enabled for stacks? | `sassy-dog:pr-shepherd` → `scripts/stack-probe.sh` (REST `GET /repos/{o}/{n}/stacks`, 200 vs 404) |
| Is a given PR a stack layer, and which? | the same probe (GraphQL `PullRequest.stack`) |
| Is it safe to merge this layer now? | the probe's derived `lower_open` |

The preview is still rolling out per-repo, so enablement is exactly the kind of fact that would go stale the day after it was written down. Config carries only the *policy* — may we stack here, and how deep.

**`stacked_prs` and `merge_queue: true` together are refused at merge time,** not at config time: GitHub's queue support for stacks is still rolling out, and `pr-shepherd` stops with exit 24 rather than guessing. Setting both is legal — it simply means the dispatchers may open stacks that a human has to land.

## Per-skill schemas

Each section lists only the keys that skill reads *in addition to* the shared blocks above.

### `survey-work.md`

```yaml
scan_paths: apps packages          # tech-debt scan roots
exclude_pathspecs: ":(exclude)packages/db/src/migrations"
ci_workflow: ci.yml
priority_labels: [p0, p1, p2]
write_policy: read-only            # or `gated` to allow the Sentry->GitHub file path
```

Prose sections: `## extra-surfaces`, `## scoring-overrides`, `## extra-guardrails`.

### `groom-backlog.md`

```yaml
gotcha_summary: >
  Repo-specific traps a cold sub-agent must know before an issue is dispatchable.
```

Prose sections: `## extra-rubric`.

#### `gotcha_summary` carries INVARIANTS ONLY

**An invariant is a trap that stays true until someone changes the architecture. A status is a fact
about today.** This field takes the first and never the second — because it is the one field the
format protects with neither of its two mechanisms. It is not *derived* (nothing recomputes it after
setup, unlike every fact in the table above), and it is not *prose* (it sits in frontmatter, so it
is outside the `##` lane a human curates when reality moves). Nothing revisits it, ever, and
`groom-backlog` copies it into issue bodies read by a cold worktree agent that has no way to check
it.

Good — invariants, all still true a year later:

```yaml
gotcha_summary: >
  Business logic lives in `crates/`, never in the Tauri shell. Renaming `LEGACY_SERVICE` orphans
  every stored credential. Migrations are irreversible in this repo — additive changes only.
```

Rotting — every one of these is a status:

```yaml
gotcha_summary: >
  The release path WORKS as of 2026-08-15. #15 is not finished — #308 (updater) and #334
  (Windows + Authenticode) remain. Windows signing is next up after the 1.2 milestone.
```

Four shapes are banned outright:

| Banned | Example | Why |
| --- | --- | --- |
| An issue number with a state claim | `#334 (Windows + Authenticode) remains` | The issue closes; the sentence does not |
| "X remains" / "still open" / "not finished" | `the updater is still unfinished` | Asserts a moment, reads as a rule |
| "as of `<date>`" | `the release path WORKS as of 2026-08-15` | Its own timestamp is the tell |
| Roadmap status | `Windows signing is next up` | Plans move; this field does not |

**This is not hypothetical.** `Sassy-Dog/solador` carried the rotting example above from 2026-08-15
onward. All three issues closed within two days — #308 on the 16th, #334 and #15 on the 17th — and
nine days later the config still asserted they were open, ready to be written verbatim into a fresh
issue body (issue #249). The same repo asserted the same class of claim in `survey-work.md`'s
`## extra-guardrails`, a **prose** section, and *that* copy was corrected within two days. Same
repo, same week, same kind of claim: the lane with a human curator got maintained and the
frontmatter one rotted. The rule above exists because that seam is in the format, not in one
operator.

Two mechanics back the rule up, and neither replaces it:

- **At injection.** `groom-backlog` §4 never copies this field into an issue body directly. It runs
  `github-issues`' `verify-gotcha-claims.sh`, which resolves every cited `#N` against real issue
  state and **drops** any claim whose asserted state is wrong *or unresolvable* — unknown is held,
  never passed through — then injects only what survived.
- **At refresh.** `verify-gotcha-claims.sh --config <path> --lint` reports the four banned shapes
  offline (no `gh`, no network; exit 3 = findings), so a config that already carries them can be
  **named** rather than carried forward unexamined. A refresh regenerates frontmatter, so an
  offending `gotcha_summary` is rewritten with the user, not silently preserved.

### `take-it.md`

```yaml
stack_summary: Bun workspaces monorepo; Next.js 15 web + Drizzle db package
preflight_commands: |
  bun run lint
  bun run typecheck
pr_template_sections: [Summary, Testing, Risk]
```

Prose sections: `## subagent-rules`, `## extra-guardrails`.

### `dispatch-ready.md`

```yaml
max_in_flight: 3
```

Prose sections: `## extra-sequencing`.

### `send-it.md`

```yaml
pr_template_path: .github/pull_request_template.md
pr_template_sections: [Summary, Testing, Risk]
preflight_commands: |
  bash scripts/preflight.sh
```

Prose sections: `## extra-gates`, `## extra-guardrails`.

### `tidy-repo.md`

```yaml
dep_version_globs: ["**/package.json", "**/bun.lock"]
noise_allowlist: ["*.log", ".DS_Store"]
never_discard: [".env.local", "*.pem"]
```

Prose sections: `## extra-cleanup`, `## extra-guardrails`.

## Prose sections

Section names carry over verbatim from the `BEGIN/END PROJECT-SPECIFIC` fence slots the old
generated skills used, so migration is a mechanical lift:

| Old fence slot | New config section | File |
| --- | --- | --- |
| `extra-surfaces` | `## extra-surfaces` | `survey-work.md` |
| `scoring-overrides` | `## scoring-overrides` | `survey-work.md` |
| `extra-rubric` | `## extra-rubric` | `groom-backlog.md` |
| `subagent-rules` | `## subagent-rules` | `take-it.md` |
| `extra-sequencing` | `## extra-sequencing` | `dispatch-ready.md` |
| `extra-gates` | `## extra-gates` | `send-it.md` |
| `extra-cleanup` | `## extra-cleanup` | `tidy-repo.md` |
| `extra-guardrails` | `## extra-guardrails` | four files |

All eight slots must round-trip through migration. The old `update-mode.md` slot list omitted
`extra-rubric` and `extra-sequencing`; that omission is fixed here.

Prose is never generated or rewritten by a refresh — it is carried across verbatim, which is the
whole point of keeping it separate from the frontmatter facts.

## How skills read this

Each skill inlines its config at load time with dynamic context injection:

```text
!`root="$(git rev-parse --show-toplevel 2>/dev/null)"; echo "CONFIG_SOURCE: ${root:-<not a git repo>}"; cat "$root/.claude/sassy-dog/<skill>.md" 2>/dev/null || echo "NO_CONFIG"`
```

`git rev-parse` rather than `${CLAUDE_PROJECT_DIR}` because the substitution order between
placeholder expansion and shell execution is not specified, and every one of these skills requires
a git repo regardless. The command is safe outside a repo — it yields `NO_CONFIG` with no stderr.

### `CONFIG_SOURCE` — why the block announces where it read from

**The block resolves against the SESSION's working directory, not the repo being acted on**, and
those are the same thing only when the session was started in the target repo. The harness pins cwd
to the session root and **resets it between Bash calls**, so an agent cannot `cd` into another repo
and re-trigger the load — whichever repo the session started in owns config resolution for the whole
session. Cross-repo work is therefore the exposed case: a sub-agent shipping in repo B, dispatched
from a session rooted in repo A, is handed A's config.

The failure is silent in exactly one quadrant, which is why it survived so long:

| Session-root repo | Result |
| --- | --- |
| Unconfigured | `NO_CONFIG` → the skill stops and asks ✓ |
| Configured, same as the target | correct ✓ |
| Configured, **different** from the target | **confident wrong answer**, silent ✗ |

`NO_CONFIG` already fails honestly. The third row did not, because a populated config from the wrong
repo is indistinguishable from the right one — the same class as a truncated API page reading as an
empty one. On 2026-08-18 two sub-agents shipping in `sassydog-routines` and `sassydog-skills` were
each handed `platform`'s Terraform gates (`terraform fmt`, `tflint`,
`infrastructure/environments/core`) while their real gates were `bats`/`ruff`/`actionlint` and
`scripts/preflight.sh`. Both caught it only by noticing the mismatch themselves — and since every
skill instructs that config be applied exactly as written, a *compliant* agent would have run the
wrong gates.

Hence `CONFIG_SOURCE`: the block names the path it read from, so the mismatch is visible rather than
inferred. Each skill's §1 carries the reconciliation rule inline — discard, re-read the target repo's
own file by absolute path, use that. The rule is inline rather than a pointer here on purpose: the
failure mode is an agent proceeding confidently without reading further, and a pointer is exactly
what such an agent skips.

**`NO_CONFIG` is a first-class state, not an error.** A skill that finds no config must derive what
it safely can, run in its most conservative mode, and tell the user to run
`sassy-dog:setup-config`.

### The no-invention rule

**"Derivable" means derivable from git or `gh` in this repo. It does NOT mean "reachable by some
other means."** This distinction is the whole safety property, and it is easy to lose.

Observed 2026-08-05: the generic `survey-work` was run in an un-migrated repo, correctly reported
`NO_CONFIG`, and then invoked the Sentry surface anyway and ran the tech-debt scan with the example
`SCAN_PATHS` from `repo-health`'s own docs. Sentry projects *are* listable for the org, and a scan
path *can* be guessed from the directory tree — so both looked derivable. The result was a plate
built on invented inputs that read exactly like a real one.

Two rules follow, and both are load-bearing:

1. **A surface with no config block is OFF**, however reachable it looks. Render it
   `skipped — not configured`.
2. **State the rule at the point of use, not only in the `NO_CONFIG` preamble.** The failure above
   happened because the instruction lived in §1 and the temptation lived in §3. By the time a skill
   reaches the pull section it has read a lot of text, and a parenthetical `*(if configured)*` is a
   weak signal against a concrete, available action. Each conditional surface must carry its own
   **ONLY if** guard.

The asymmetry that justifies the strictness: **skipping a surface knowingly is recoverable; acting
on a fabricated one is not**, because the output is indistinguishable from a real result. This is
sharpest in `send-it`, which pushes and merges on the strength of a pre-flight command — a guessed
command that exits 0 without running anything looks exactly like a passing check.

Skills that write or dispatch unattended (`take-it`, `dispatch-ready`) do not degrade at all; they stop.

## Cloud sessions and routines

A repo carrying these config files must also declare, in its own `.claude/settings.json`, both the
marketplace (`extraKnownMarketplaces` → `sassydog-skills` from `Sassy-Dog/sassydog-skills`) and the
plugin (`enabledPlugins` → `sassy-dog@sassydog-skills`). Plugin skills enabled only in user settings
do not transfer to cloud sessions or scheduled routines — only repo-declared plugins install at
session start, and they install *from the marketplace the repo declares*. `enabledPlugins` alone
references the marketplace by name only; the name resolves locally through user-level registration
(`~/.claude/plugins/known_marketplaces.json`), which never reaches a cloud VM. Without both
declarations a scheduled `dispatch-ready` silently finds no skill, while every local session works fine.
