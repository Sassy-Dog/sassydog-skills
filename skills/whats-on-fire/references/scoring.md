# Portfolio scoring

Severity tiers for the portfolio sweep. These are **not** the per-repo `survey-work` rules — read the
inversion below before reusing anything from `repo-health/references/scoring.md`.

## The staleness inversion

Per-repo `survey-work` applies a `recency_decay` so old signals matter less. That is right for customer
pain: a crash nobody has hit in a month is less urgent than one from this morning.

It is exactly wrong for stuck work. A PR idle 123 days is **more** urgent than one idle 3 days — the
staleness *is* the defect. Applying decay here would systematically bury the worst findings in the
portfolio, which is how a 123-day-old dependency PR survives 123 days.

So: **customer pain decays with age; stuck work escalates with age.** Never share one curve.

## Tiers

### P0 — production is degraded, or the pipeline is dead

| Signal | Source |
|---|---|
| Sentry issue passing the qualifying gate, `lastSeen` ≤ 48h | `sentry-triage` |
| Cron monitor environment `missed` or `timeout` — always, a dispatch can never vouch for these | `find_monitors` |
| Cron monitor environment `error` with **no** qualifying green dispatch after its last failing check-in | `find_monitors` + `cron-recovery.md` |
| `default_branch_ci` is `failure` | `pull-repo-signals.sh` |
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

### P1 — shipping is blocked or exposure is real

| Signal | Threshold |
|---|---|
| PR idle | > 7 days |
| Workflow failure rate | > 20% of `runs_sampled` |
| Dependabot | any `high_crit` > 0 |
| `scheduled_failing` | non-empty — an ops job whose most recent run failed |
| `default_branch_ci` | `cancelled` or `timed_out` (ambiguous — verify before ranking P0) |
| Secret scanning | `unknown_validity[]` entry aged < 30d |
| Code scanning | `new[]` rule at `high` |

### P2 — heat worth knowing about

| Signal | Threshold |
|---|---|
| PR idle | 3–7 days |
| Normalized-P1 backlog issues | see the map below |
| Dependabot | `open` > 0 with no high/critical |

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

### Not ranked — blind spots

Structural gaps are reported in their own section and never assigned a P-tier. They are conditions,
not incidents; ranking them alongside a live outage makes both harder to read. They also persist
unchanged across runs, so a tier would just add recurring noise at a fixed severity.

## Label normalization

The priority taxonomy drifted across repos — some use `priority:*`, some `sev:*`, some bare labels,
and several carry both a namespaced and an un-namespaced form of the same concept (`security` and
`area:security` coexist). Normalize before ranking, and prefer the highest match when an issue
carries several:

| Tier | Matches |
|---|---|
| P1 | `priority:critical`, `priority:high`, `sev:critical`, `sev:high`, or (`bug` **and** `area:security`\|`security`) |
| P2 | `priority:medium`, `sev:medium` |
| P3 | `priority:low`, `sev:low`, `enhancement` |
| unranked | everything else — count them, don't list them |

Do **not** re-derive a priority a maintainer already assigned; this map only makes differing
vocabularies comparable across repos. An unlabeled issue is unranked, not P3 — absence of a label is
absence of information, not a judgment of low priority.

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
