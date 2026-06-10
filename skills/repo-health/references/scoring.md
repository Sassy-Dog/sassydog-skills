# Scoring thresholds

Default severity mapping for repo-health signals. Project skills may override these in their project-specific sections; absent an override, use these.

## CI health (`pull-ci-health.sh`)

| Signal | Severity |
|---|---|
| `p90_min > 40` | P0 — dev loop is broken; everything else ships slower |
| `p90_min > 25` | P1 |
| `flake_runs` > 5% of `sample` | P1 — flake erodes trust in red checks |
| `flake_runs > 0` but ≤ 5% | P2, name the flaky SHAs |

The flake metric counts a SHA that failed then passed **within the same event context** — re-read the script header before "improving" it; the (headSha, event) key exists to exclude merge_group-vs-push false positives.

## Mobile release lag (`pull-mobile-release-lag.sh`)

| Signal | Severity |
|---|---|
| `latest_release_ios_leg` is `queued`/`cancelled`/`*/failure` AND `mobile_commits_since > 0` | P0 — release pipeline stalled; testers aren't getting fixes |
| `days_since_ios_success > 3` AND `mobile_commits_since > 0` | P1 |
| otherwise | not surfaced (contributes to the "clean" line) |

## Tech debt (`pull-tech-debt.sh`)

| Signal | Severity |
|---|---|
| Skipped test on a critical-path file (auth, payments, routing — caller defines the critical paths) | P1 |
| Skipped test elsewhere | P2 |
| High-churn × high-TODO directory (cross-reference `todo-by-dir` against `git log --since` churn) | P1 |
| Isolated TODO/FIXME markers | report counts only; not individually actionable |

Markers are a *density* signal, not a backlog — never enumerate all 200 in a report. Surface the top directories and any marker that names a known incident or security concern.
