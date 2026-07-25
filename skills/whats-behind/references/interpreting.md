# Interpreting drift

Ranking rules for `pull-version-drift.sh` output. The script reports raw observations on purpose;
the judgement lives here so the rubric can change without touching parsing.

## The fleet standard

For each item (an action, a toolchain pin), the **fleet standard is the mode** — the version the
most repos run — with ties broken toward the higher version.

Mode, not maximum. One eager repo on a brand-new major does not put everyone else "behind"; that
would generate a report that is loudest exactly when one team is experimenting. The mode tracks what
the portfolio has actually converged on, which is the thing a laggard is failing to keep up with.

## Tiers

| Tier | Condition | Why it ranks here |
|---|---|---|
| **T1** | Internally inconsistent — one repo pinning two versions of the same item | The repo has no single source of truth. Any bump is already partial, and the next one will miss a spot. Worse than being uniformly old. |
| **T2** | Major-version gap below the fleet mode | Real capability and support gap; upgrades get harder the longer they wait. |
| **T3** | Minor/patch gap below the fleet mode | Routine currency. |
| **T4** | Matches or leads the fleet mode | Not reported except as the `✓ Current:` line. |

A repo that is *ahead* of the mode is never a finding. It may be worth a note if it is ahead by a
major and nobody else has followed — that is a migration nobody finished — but it is not lag.

## Cause classification

Every T1–T3 finding gets one of these, and the classification changes the prescription entirely:

- **UNMANAGED** — no `dependabot.yml`, or one that omits the relevant ecosystem. The pin is stale
  because nothing is watching. Prescribe rendering the config; a manual bump here fixes today and
  guarantees the drift returns.
- **MANAGED, not cycled** — config covers the ecosystem but the version is still behind. Usually a
  recently-added config that has not run yet. Prescribe waiting one cycle, then re-checking.
- **MANAGED, PRs not merging** — config covers it and Dependabot has opened PRs that are sitting.
  This is not a drift problem at all; it is a merge-throughput problem. Hand it to `whats-on-fire`,
  which ranks stalled PRs.

That third case is why cause classification matters. Identical symptoms — an old pin — have three
different fixes, and only one of them is "bump it".

## Runner migration

`runners[<repo>]` is a job count, not a percentage of importance. A repo with 40 hosted jobs is not
necessarily worse off than one with 3; weight by whether the repo is actively developed.

Before reporting a repo as lagging on runners, check for a **hard block**. The fleet runs as a
non-root user with no `sudo`, so:

- Toolchains that unpack into `$HOME` (`dtolnay/rust-toolchain`, `setup-go`, `setup-bun`, release
  tarballs) are portable — no blocker.
- **System libraries** (dev headers under `/usr`) cannot be installed at job time. A repo needing
  them is blocked on the runner image, not on anyone's attention. Report it as blocked, and link the
  tracking issue rather than listing it as neglect.
- Dockerized tooling may fail even where `docker` is installed, if the daemon is rootless and cannot
  bind-mount the workspace. Presence of a binary does not imply it is usable.

## Anti-patterns

- **Don't report every action.** A portfolio pins dozens; most are uniform. Report only items where
  repos actually disagree — uniform pins are noise.
- **Don't rank archived repos.** They linger in local checkouts long after they stop mattering.
- **Don't prescribe a bump without naming the cause.** "Six repos are on v4" is a symptom. "Six
  repos are on v4 because none of them has a Dependabot config" is the finding.
