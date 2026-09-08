# Portfolio scoring

Severity tiers for the portfolio sweep. These are **not** the per-repo `survey-work` rules — read the
inversion below before reusing anything from `repo-health/references/scoring.md`.

<!-- rule: staleness-inversion -->
## The staleness inversion

Per-repo `survey-work` applies a `recency_decay` so old signals matter less. That is right for customer
pain: a crash nobody has hit in a month is less urgent than one from this morning.

It is exactly wrong for stuck work. A PR idle 123 days is **more** urgent than one idle 3 days — the
staleness *is* the defect. Applying decay here would systematically bury the worst findings in the
portfolio, which is how a 123-day-old dependency PR survives 123 days.

So: **customer pain decays with age; stuck work escalates with age.** Never share one curve.

## Tiers

<!-- rule: tier-p0 -->
### P0 — production is degraded, or the pipeline is dead

| Signal | Source |
|---|---|
| Sentry issue passing the qualifying gate, `lastSeen` ≤ 48h | `sentry-triage` |
| Cron monitor environment `missed` or `timeout` — always, a dispatch can never vouch for these | `find_monitors` |
| Cron monitor environment `error` **and blind** — no auto-managed owner issue (`cron-recovery.md` rule 0) **and** no qualifying green dispatch after its last failing check-in | `find_monitors` + `cron-recovery.md` |
| `default_branch_ci` is `failure` **and `default_branch_ci_age_days` <= 14** | `pull-repo-signals.sh` |
| Any `secret_scanning.active[]` entry, or any `bypassed: true` | `pull-repo-signals.sh` |
| `secret_scanning.unknown_validity[]` entry aged >= 30d | `pull-repo-signals.sh` |
| `code_scanning.new[]` rule at `critical` | `pull-repo-signals.sh` |

A red default branch is P0 regardless of failure rate — a repo can sit at 0% historical failures and
still have main broken right now. Rate answers "is CI trustworthy"; `default_branch_ci` answers "is
it broken", and only the second one blocks shipping.

**`default_branch_ci` is push-class only, and that distinction is load-bearing.** It reads the
latest `push`/`merge_group` run, ignoring `schedule`. A nightly ops job failing on main is a real
problem but it blocks no merges, so it ranks as P1 ops (below), not P0. Ranking them together
produces the exact false alarm this split exists to prevent: reporting "main is red, shipping is
blocked" when the only red thing is a database sweep that will retry in four hours.

<!-- rule: ci-verdict-age-bound -->
**The verdict is NOT bounded by `RUN_LIMIT`, so it must be read with its age.** The puller recovers
a null verdict with a re-query narrowed to the default branch, which reaches back as far as that
branch's newest concluded push — weeks, for a quiet repo. `default_branch_ci_age_days` carries how
far, and `default_branch_ci_url` links the run. **Both directions of a stale verdict are wrong in
the same way and neither may be silent:**

- A `failure` older than 14 days is not "production is degraded right now". It ranks **P1** (below)
  and is reported as `main last built red <N>d ago` with the run linked — a repo nobody has pushed
  to since is not an outage.
- A `success` older than 14 days does not earn `✓ Clean today:`. Report it as
  `CI last green <N>d ago` under **`🕰 Stale CI verdicts`** (SKILL.md section 5) — that section is
  its one destination, named below. It is the newest evidence there is, and it is not evidence
  about today.
- **An age of `null` is not an age of 14 days or less.** `default_branch_ci_age_days` is `null`
  when the run the verdict came from carried no usable `createdAt`; the puller emits that
  deliberately rather than guessing a date. An undated conclusion resolves the way a stale one
  does, in both directions: a `failure` ranks **P1** and reads `main last built red — age unknown`,
  because P0 is a positive claim about *now* that an undated run cannot make; a `success` reads
  `CI last green — age unknown` in the same stale-verdict section. Reading `null` as "recent" is
  the same defect one level down as reading a null verdict as green.

**Why 14 days, and why it is a convention rather than a measurement:** it is the boundary this same
puller already uses to split `code_scanning.new[]` from `code_scanning.inherited` — fresh enough to
act on now, versus background state — so the sweep applies one notion of "recent" rather than
inventing a second. It is deliberately more conservative than the 30-day `unknown_validity` bound
and much less aggressive than Sentry's 48h, because those two measure live user impact and this one
measures how long ago somebody last pushed. Change it here and it changes everywhere.

<!-- rule: tier-p1 -->
### P1 — shipping is blocked or exposure is real

| Signal | Threshold |
|---|---|
| PR idle | > 7 days |
| Workflow failure rate | > 20% of `runs_sampled` |
| Dependabot | any `high_crit` > 0 |
| `scheduled_failing` | non-empty — an ops job whose most recent run failed |
| `default_branch_ci` | `cancelled` or `timed_out` with `default_branch_ci_age_days` <= 14 (ambiguous — verify before ranking P0) |
| `default_branch_ci` | `cancelled`, `timed_out` or `failure` older than 14 days, or with a null age — last known state, not a live outage, and never promoted to P0 |
| Secret scanning | `unknown_validity[]` entry aged < 30d |
| Code scanning | `new[]` rule at `high` |

<!-- rule: tier-p2 -->
### P2 — heat worth knowing about

| Signal | Threshold |
|---|---|
| PR idle | 3–7 days |
| Normalized-P1 backlog issues | see the map below |
| Security-labelled backlog issues | **any tier, including unranked** — always listed, see the map below |
| Dependabot | `open` > 0 with no high/critical |

<!-- rule: state-working-tracked-finding -->
### Not a tier — working, reporting a tracked finding

A cron environment in `error` whose control has an **open auto-managed issue** naming that workflow
is neither broken nor fixed-pending-confirmation: it is working as designed, reporting a standing
finding with a durable owner. A check-in has only `ok` and `error`, so most controls deliberately
map "I found something" onto `error` alongside "I could not look" — the monitor cannot distinguish
them, and this sweep must. Report it as `working — tracked in <issue>`, and rank the **finding** on
its own merits (a CVE backlog is security exposure) — never the monitor.

Unlike the third state below, this one **does not clear**. It persists as long as the finding does,
re-checking in `error` daily. Re-raising it as a fresh outage each morning is the unbounded-nag
failure mode: an alert whose only remedy is "the outstanding work is still outstanding". Skipping
this check ranked a correct CVE scan as a P0 production outage on 2026-08-20
(`Sassy-Dog/platform#735`).

<!-- rule: no-p1-corroborating-p0 -->
**Never corroborate a P0 with a P1 signal.** That same alert cited "today's scheduled CI run also
failed" as supporting evidence — but `scheduled_failing` is P1 in this very file, for the same
push-vs-schedule reason `default_branch_ci` is push-class only. Stacking a P1 under a P0 headline
manufactures confidence instead of adding information.

<!-- rule: state-fixed-awaiting-schedule -->
### Not a tier — fixed, awaiting scheduled confirmation

A cron environment in `error` whose backing workflow shows a green `workflow_dispatch` completed
**after the most recent failing check-in** is verified fixed — the monitor just cannot say so yet,
because check-ins are gated to `schedule` runs and the next one may be a week out. That is a third
state, not a severity: not a P0 (the fix shipped and was proven against live infrastructure), and
not `✓ Clean today:` (the schedule has not yet confirmed it). It gets its own section with the
verifying run linked and `nextCheckIn` named as the confirmation date.

Only `error` is eligible. `missed` and `timeout` stay P0 with any number of green dispatches on
file — a manual re-run must never quiet the dead-cron alarm. When the cross-reference cannot run at
all, the monitor stays P0 **and** the report footer names the repo that could not be read. The full
contract — reference-instant choice, owning-repo resolution, and the 404/403 split — is
`cron-recovery.md`.

### Not a tier — the verdict is real, and it is not about today

A `success` whose `default_branch_ci_age_days` is greater than 14, **or `null`**, is a conclusion
the sweep can read and cannot date to this week. The P0 rules above already forbid it the
`✓ Clean today:` line; this is where it goes instead. Like the two cron states above it is a state
rather than a severity — nothing is known to be broken, so no tier applies — and like them it is
**not dropped and not folded onto `✓ Clean today:`: it gets its own section**, `🕰 Stale CI verdicts`
(SKILL.md section 5), one line per repo reading `CI last green <N>d ago` (or `age unknown`) with
`default_branch_ci_url` linked. That is its only destination.

**Do not send it to the `Coverage:` line instead.** Coverage names repos that produced **no**
verdict, and `coverage-not-assumed` (SKILL.md section 3) exists to keep that line precise. A stale
success has a verdict; folding the two makes one line mean both "never measured" and "measured, but
not recently", which is the distinction a reader is using it to draw.

Only `success` lands here. A stale or undated `failure`, `cancelled` or `timed_out` already ranks
P1 above and reports there — this section is for the verdict that ranks nowhere else, which is the
one that would otherwise be omitted. Omission is the failure mode the age bound was at risk of
trading the false green for ([#375](https://github.com/Sassy-Dog/sassydog-skills/issues/375)).

This section deliberately carries **no parity marker**, and that is a sequencing decision rather
than an oversight: the 14-day bound it renders (P0 above) carries none either, and
`Sassy-Dog/sassydog-routines#58` has split the marking of that whole rule family into its own
cross-repo step. Marking this one alone would fail that repo's parity check for a rule its home has
not received yet. Mark it there and here together, in that sequence, or not at all.

<!-- rule: default-branch-ci-unknown -->
### Not a tier — `default_branch_ci` is `null`

`null` is not a conclusion. It means no concluded push-class run on the default branch was found,
so the repo is neither `✓ Clean today:` (nothing was read) nor P0 (nothing is known to be red).
Rank nothing on it, and report it with the reason `default_branch_runs_seen` gives — it is
**three-state** and each state is a different sentence:

| `default_branch_runs_seen` | Report as | Means |
|---|---|---|
| `0` | `CI unknown — no push has ever run on the default branch` | The recovery query answered, and there is no such run. Not a sampling artefact. |
| non-zero | `CI unknown — all default-branch runs still in flight` | They exist; none has concluded yet. Re-read later. |
| `null` | `CI unknown — could not be read` | The recovery call failed or came back unreadable. Name the repo on the sources line, the same way an unreadable Dependabot surface is named. |

A bare null hides which of the three you have, and `0` is a **positive claim** — never report it for
a call that did not answer. The count itself is bounded by whichever query answered, so read the
split and never the total.

A null from the FIRST, unfiltered sample is the common case, not the rare one. The newest runs in
a busy repo are dominated by `pull_request` and bot events, so a repo with thousands of runs on
file can easily have no `push` to its default branch in the sample — velovate, brewslate,
tailoredtip, what2wear and td3000 on 2026-09-06, all five with a verdict available, tabulated in
[#367](https://github.com/Sassy-Dog/sassydog-skills/issues/367). That is what the recovery is for,
and it is why an unnamed `null` must never quietly read as green. A null that SURVIVES the recovery
is the rare one, and it is the one this section is about.

Recovering the answer with a narrower re-query is the puller's business, not this table's — both
pullers do it, and the tiers below apply to whatever they finally report. What is load-bearing here
is that a `null` never reaches the clean line and never reaches P0, and that a recovered verdict is
read with `default_branch_ci_age_days` beside it (see P0 above).

<!-- rule: blind-spots-unranked -->
### Not ranked — blind spots

Structural gaps are reported in their own section and never assigned a P-tier. They are conditions,
not incidents; ranking them alongside a live outage makes both harder to read. They also persist
unchanged across runs, so a tier would just add recurring noise at a fixed severity.

<!-- rule: label-normalization-map -->
## Label normalization

The priority taxonomy drifted across repos — some use `priority:*`, some `sev:*`, some bare labels,
and several carry both a namespaced and an un-namespaced form of the same concept (`security` and
`area:security` coexist). Normalize before ranking, and prefer the highest match when an issue
carries several:

| Tier | Matches |
|---|---|
| P1 | `priority:critical`, `priority:high`, `sev:critical`, `sev:high` |
| P2 | `priority:medium`, `sev:medium` |
| P3 | `priority:low`, `sev:low`, `enhancement` |
| unranked | everything else — count them, don't list them |

Do **not** re-derive a priority a maintainer already assigned; this map only makes differing
vocabularies comparable across repos. An unlabeled issue is unranked, not P3 — absence of a label is
absence of information, not a judgment of low priority.

<!-- rule: security-always-listed -->
### Security is never collapsed into a count

**An issue carrying `security` or `area:security` is ALWAYS listed by number, at whatever tier the
map gives it — including `unranked`.** Its tier is not adjusted: the rule above still holds, and a
maintainer's `sev:*` is still the severity. What changes is only that a security issue can never
end its life as part of a bare integer. `unranked` matters here as much as P2 does, because an
unlabelled security issue is the *most* likely to be new and the least likely to have been triaged
by anyone yet.

This is a *rendering* rule, deliberately, because the failure was a rendering failure. The map used
to reach security only through (`bug` **and** `security`), so promotion depended on whether the
issue happened to be phrased as a defect — and most real security work is not: hardening, a missing
control, an unmodelled sanitizer, a policy decision. Promoting on `security` alone would have fixed
the symptom by re-deriving priority, which is the one thing the paragraph above forbids. Listing it
regardless of tier fixes the actual harm without touching the maintainer's judgment.

The `bug` conjunction is gone with it. `bug` is a **type**, not a severity multiplier, and it never
belonged in a priority map.

#### Worked example — the exact combination that regressed

`Sassy-Dog/velovate`, two security issues filed the same day (issue #219):

| Issue | Labels | Tier | Rendered |
|---|---|---|---|
| #2181 | `bug`, `security`, `sev:medium` | P2 | **listed** — by number |
| #2186 | `security`, `observability`, `sev:medium` | P2 | **listed** — by number |
| *(hypothetical)* | `security`, `sev:low` | P3 | **listed** — by number |
| *(hypothetical)* | `security`, no priority label | unranked | **listed** — by number |
| #2190 | `enhancement`, `sev:medium` | P2 | counted only |

Under the pre-fix map #2181 normalized to P1 and #2186 to P2 — identical severity, one label apart,
opposite visibility. #2186 covers 72 open CodeQL alerts including **10 sites logging raw rider
coordinates** on a product live with real users' location history, and it was invisible in every
`daily-fire-watch` post from the day it was filed.

Note that both now sit at P2, which is *lower* than #2181's old P1. That is the correction, not a
regression: `sev:medium` is what the maintainer said, and both are listed either way.

**Why this rule carries more weight than its size suggests.** The cloud edition cannot read code-
scanning or secret-scanning alerts at all — settled by probe, recorded as a §0 Container fact
(`Sassy-Dog/sassydog-routines#11`). A CodeQL finding therefore reaches the report **only** if a
human files it as a GitHub issue. This listing rule is the whole of that escape hatch; a label
technicality closing it takes an entire surface offline silently.

## Blind-spot conditions

| Condition | How it's detected |
|---|---|
| Dependabot disabled | `dependabot.enabled == false` |
| Dependabot visibility unknown | `dependabot.enabled == null` — token scope, not a repo setting; do not report as "disabled" |
| Code scanning disabled | `code_scanning.enabled == false` |
| Code scanning never analyzed | `code_scanning.analyzed == false` with `enabled == true` — a scan has never produced a result; `open: 0` here is not a clean bill of health |
| Code scanning visibility unknown | `code_scanning.enabled == null` — token scope, not a repo setting |
| Secret scanning disabled | `secret_scanning.enabled == false` |
| Secret scanning visibility unknown | `secret_scanning.enabled == null` — token scope, not a repo setting |
| No error monitoring | active repo with no matching Sentry project |
| No alerting | `find_alert_rules` returns zero metric rules org-wide |
| Archived but still checked out | `repos[].archived == true` with a local clone present |
| In the org, never cloned | roster entry with no local directory |
| No `survey-work` config | active repo without `.claude/sassy-dog/survey-work.md` (the skill ships in the plugin, so only the config signals a tuned deep-dive) |

The reason this section exists: a repo with no Sentry project reports zero errors, and a per-repo
survey-work will faithfully print `✓ Clean today: Sentry`. That is technically true and completely
wrong. Silence from an uninstrumented product is not health — it is the absence of a sensor, and
only a portfolio-level view can tell the two apart.
