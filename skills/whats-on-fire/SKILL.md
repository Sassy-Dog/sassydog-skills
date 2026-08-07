---
name: whats-on-fire
description: >
  This skill should be used when the user asks "what's on fire", "what's on fire today", "what's
  broken", "what's broken across our products", "what's stuck", "what's red", "anything burning",
  "portfolio status", "portfolio health", "how's the portfolio looking", "which product needs
  attention", "cross-product status", "are any of our products broken", or wants one cross-product
  sweep of production failures and stalled work spanning EVERY repo in a GitHub org rather than a
  single repository. Pulls Sentry issues and cron monitors, org-wide open issues and pull requests,
  failing workflows, Dependabot exposure, and structural blind spots (products with no error
  monitoring, no alerting, or no dependency scanning), then ranks them across products and routes
  each one to the owning repo. Read-only — never files issues, never mutates state. For deep
  single-repo prioritization, defer to that repository's own plate-it skill.
---

# What's On Fire

One cross-product sweep of everything currently broken or stalled across a GitHub org, ranked, and
routed to the repo that owns it.

This skill is **read-only**. It pulls, correlates, ranks, and reports. It NEVER files issues, changes
Sentry status, or mutates anything — which is what makes it safe to run on a loop or a schedule.

**Scope boundary.** This decides *which product* deserves attention today. It deliberately does not
decide *what to do inside* that product — no tech-debt scan, no next-bet synthesis, no backlog
grooming. Those don't roll up meaningfully across a dozen products, and each repo's own `plate-it`
already does them with repo-specific knowledge this skill has no business duplicating. Report the
fire, name the repo, hand off.

## 1. Prerequisites

Run these probes. For each failure, label that surface `skipped — <reason>` in the output and
continue. **Never abort the whole sweep on one missing precondition.**

```bash
gh auth status
```

- **Sentry** — probe by listing projects for the Sentry org; on error, skip both Sentry surfaces.
- **Portfolio root** — the local checkout directory (env `PORTFOLIO_ROOT`, default
  `~/Repos/sassy-dog`). Only needed for the two blind spots that compare the org against local
  clones; if it's missing, skip those two rows and keep the rest.

Defaults for Sassy Dog: GitHub org `Sassy-Dog`, Sentry org `sassy-dog`, region
`https://us.sentry.io`. Pass a different `ORG` to the scripts for another org.

## 2. Pull all surfaces in parallel

Issue the independent pulls in a single message with multiple tool calls.

### A. Production fires

**Sentry issues** — invoke `ai-agent-skills:sentry-triage`: org `sassy-dog`, all projects. Gate
policy: **report-only, no escalation** — this skill has no write path, so the gate classifies and
ranks but never files. It already owns the qualifying gate, the `!is:resolved` query shape, and GH
cross-referencing; don't reimplement any of that here.

**Sentry crons** — MCP-first, resolving the tool by capability rather than a hardcoded tool id
(same convention as `sentry-triage`; never a literal `mcp__...` id). No MCP connected → fall back
to REST exactly as the issues surface does: the cron-monitor recipe in `sentry-triage`'s
`references/api-fallback.md` (`SENTRY_AUTH_TOKEN`; the monitors endpoint needs `org:read` or
`alerts:read`, not just the issue scopes). With neither MCP nor a token, or on a failed call, mark
the surface `skipped — <reason>` per section 1 — the fallback must never turn "could not check"
into silence. List cron monitors for the org and read each monitor's per-environment state
(`environments[].status`, not the lifecycle-only monitor `status`). A `missed` or `timeout`
environment is a P0, always — no dispatch can vouch for a schedule that never fired. An `error`
environment is a P0 **unless** the recovery cross-reference in `references/cron-recovery.md`
downgrades it: check-ins are gated to `schedule` runs, so a fix verified green via
`workflow_dispatch` leaves the monitor red until the next scheduled run — up to a week — and
reporting that as a live fire is a false alarm this sweep has produced twice. Run that
cross-reference for every `error` environment before ranking it; a downgraded monitor becomes the
third state "fixed, awaiting scheduled confirmation" (section 5), never a P0 and never `✓ Clean`.
Note which projects own monitors — a product with zero monitors isn't passing, it's unmonitored,
which belongs in blind spots.

### B. Stuck shipping + backlog heat

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/whats-on-fire/scripts/pull-org-github.sh
bash ${CLAUDE_PLUGIN_ROOT}/skills/whats-on-fire/scripts/pull-repo-signals.sh
```

- `pull-org-github.sh` — three org-level calls: the repo roster, every open PR (with `idle_days`
  precomputed), and every open issue. Archived repos are flagged in `repos` but excluded from `prs`
  and `issues`; read the script header for why that filtering is load-bearing.
- `pull-repo-signals.sh` — per-repo workflow failure counts, the **current** default-branch CI
  conclusion, currently-failing scheduled workflows, and Dependabot state — including alert AGE and
  per-package fix-PR state. Slower (1 + 2N calls, plus one more per repo that actually has
  high/critical alerts, so a healthy org pays nothing extra; ~25s for 15 repos); run it concurrently
  with the Sentry pulls, not after them.

`default_branch_ci` and `scheduled_failing` are separate fields and must stay separate in the
report. Push-class red means shipping is blocked (P0); a failing nightly job is an ops problem that
blocks nobody (P1). Merging them manufactures false alarms.

Both honor `ORG`, degrade with exit 10 + `skipped: <reason>` on stderr, and emit one JSON object.

### C. Blind spots

Assemble from data already pulled, plus two local comparisons:

- Dependabot `enabled == false` → disabled. `enabled == null` → **unknown**, report as a token-scope
  question, never as "disabled".
- A repo with `unremediated_packages` non-empty **and no `open_fix_prs` at all** → *Dependabot is
  alerting but not fixing*. This is a structural blind spot, not a backlog item: the usual cause is
  that the repo's `dependabot.yml` dropped the ecosystem to dodge a lockfile its updater cannot
  regenerate (Bun, CocoaPods), while **security** updates keep firing regardless — they cannot be
  opted out of that way. Name the ecosystem and route it; the remedy is a lockfile-sync workflow, not
  a version bump.
- Active repos with no matching Sentry project → no error monitoring.
- Zero metric alert rules org-wide → no alerting. Check once via the alert-rules tool.
- Roster entries with no directory under `PORTFOLIO_ROOT` → never cloned.
- Local directories whose repo is `archived` → archived but still checked out.
- Active repos with no `.claude/sassy-dog/plate-it.md` → no tuned deep-dive to route to. `plate-it`
  itself is a plugin skill present everywhere, so directory existence proves nothing; the **config**
  is what makes it repo-aware. An unconfigured repo still runs `plate-it`, just degraded.

## 3. Roster and rollup

**The roster is the org, not the local directory.** Local checkouts drift: repos get archived while
their clone lingers, and org repos may never have been cloned at all. Take the active set from
`repos[] | select(.archived | not)`, and use the local comparison only to produce blind spots.

Products map to repos many-to-one. Report per repo, then group under the product heading. At Sassy
Dog the non-obvious ones are `velovate` → repos `velovate` + `velovate-web` (the local directory
`velovate-app` maps to the repo named `velovate`), `lupita` → `lupita` + `lupita-web` (both
archived), and `devcanopy` → `devcanopy`. Everything else is one product, one repo.

This same map is what resolves a red cron monitor's **owning repo** for the recovery
cross-reference (`references/cron-recovery.md`): monitor → its Sentry project → the owning product
→ that product's repo(s). It is already load-bearing in the reverse direction — blind spots walk
repo → Sentry project — so keep both walks on this one map; a second, separate mapping would be
one more place to drift.

## 4. Score

Apply `references/scoring.md`. The two rules that matter most:

- **Stuck work escalates with age; customer pain decays with it.** Never share one curve. A PR idle
  123 days outranks one idle 3 days.
- **A red default branch is P0 on its own**, independent of historical failure rate. Rate answers
  "is CI trustworthy"; the current conclusion answers "is it broken right now".
- **Dependabot exposure is ranked by REMEDIATION STATE, never by alert count.** The count is a
  lagging indicator — it falls only when a fix merges, so "we were slow" and "the world just
  changed" produce the identical number. Rank from `dependabot.oldest_high_crit_age_days`,
  `open_fix_prs[].state`, and `unremediated_packages`:

  | Condition | Tier | Why |
  |---|---|---|
  | `open_fix_prs[]` has a `CLEAN` PR with `age_days >= 3` | **P0** | The fix exists, it is green, and nobody is merging it. A pure process failure — the cheapest P0 you will ever close. |
  | `unremediated_packages` non-empty and `oldest_high_crit_age_days >= 14` | **P0** | No PR was ever opened and the exposure is real. Broken plumbing, not a busy week. |
  | `open_fix_prs[]` PR is `BLOCKED`/`DIRTY`/`UNSTABLE` | **P1** | Dependabot did its job; the repo's CI rejects the fix. Name the failing check — this is usually a lockfile the bot cannot regenerate. |
  | `unremediated_packages` non-empty, `oldest_high_crit_age_days < 14` | **P1** | Genuinely unfixed, but young enough that it may simply be unpatched upstream. Check whether a patched version exists before escalating. |
  | `oldest_high_crit_age_days <= 2` **and** every vulnerable package appears in some `open_fix_prs[].addresses` | **not a fire** | A fresh advisory batch with fixes already queued is the system WORKING. One line under `✓ Clean today:`. |

  Judge remediation **per package**, never per repo — `open_fix_prs` is already filtered to PRs whose
  head ref names a vulnerable package, precisely so an unrelated actions-group PR cannot be mistaken
  for a fix. Report `unremediated_packages` by name; "3 high/critical" tells nobody what to do.

Normalize priority labels across the repos' differing taxonomies using the map in the reference —
but never re-derive a priority a maintainer already assigned.

## 5. Output format

Render inline as markdown. Two anti-verbosity rules are non-negotiable: (1) empty surfaces get a
single token on the consolidated `✓ Clean today:` line, never their own section; (2) within a
section, skip empty tiers. Recommendations go LAST.

```markdown
# What's on fire (YYYY-MM-DD)

_Sources: <pulled, with any "skipped — reason">_

✓ Clean today: <surface> · <surface> · ...

## 🔥 Production fires (P0: N · P1: N)
### P0
- **<product> — <title>**
  - Impact: <N users, M events, last seen Yh ago> | <monitor env state> | <branch is red>
  - Sources: [Sentry](url) · [run](url)
  - Why this matters: <one line>

### ⏳ Fixed, awaiting scheduled confirmation
- **<product> — `<monitor>` (<project>/<env>)** — green [dispatch](url) at <time>; awaiting
  scheduled confirmation <nextCheckIn date>

## 🚧 Stuck shipping
- **<repo>#<N> <title>** — idle <D>d · <one-line why>

## 🎯 Backlog heat
- **<repo>#<N> <title>** — `<label>` — <one-line why>

## 🕶 Blind spots (silent, not healthy)
- <condition> — <affected repos>

## 👉 Today's top 5 (cross-product)
1. **<title>** — <product> · <one-line why>

_⚠ Cron recovery cross-reference could not run for: <repo> · <repo> — red monitors there are
shown at full severity._

_To dig in: `cd <product> && /plate-it`_
_To ship: `cd <product> && take #<N>`_
```

Keep the footer. This skill's job ends at naming the product; the per-repo `plate-it` and `take-it`
take it from there, and the footer is what makes that handoff explicit rather than implied.

Two rules for the cron-recovery lines, from `references/cron-recovery.md`:

- **"Fixed, awaiting scheduled confirmation" is a third state** — never folded into P0, never onto
  `✓ Clean today:`. Link the verifying dispatch and name the environment's own `nextCheckIn` as the
  confirmation date (unknown when null — never invent one). Do not lead with the outage duration:
  "`error` for 6d" is true of the monitor and misleading about the world. The section follows the
  skip-empty-tiers rule like any other.
- **The cross-reference footer appears only when a lookup actually failed** (missing `actions:read`,
  network, 5xx — the exit-10 cases), and it names each repo it could not read. A 404 — no such
  workflow in the owning repo — is "not applicable", never a footer entry; a footer that fires on
  every sweep is a footer nobody reads.

## 6. Read-only contract

This skill NEVER files GitHub issues, changes Sentry status, moves board cards, or mutates anything.
If a fire deserves an issue, say so in the report and name the flow that would file it — the human
runs that deliberately, in the owning repo, where the repo's own gates and labels apply.

There is no conditional write gate here, and adding one would be a mistake: a portfolio-level filer
has no principled answer to "which repo does this get filed against" for a cross-product signal, and
the per-repo skills already own filing with better context.
