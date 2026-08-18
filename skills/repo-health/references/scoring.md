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

## Security scanning (`pull-code-scanning.sh`, `pull-secret-scanning.sh`)

| Signal | Severity |
|---|---|
| `active[]` non-empty, or any `bypassed: true` | P0 — a validated live credential, or push protection deliberately overridden |
| `unknown_validity[]` entry aged >= 30d | P0 — unverified and untriaged for a month |
| `unknown_validity[]` entry aged < 30d | P1 |
| `new[]` rule, severity `critical`, or `autofix: "ready"` | P0 |
| `new[]` rule, severity `high` | P1 |
| `inherited.count > 0` | one debt line; never enumerated, never in a top 5 |
| `analyzed == false`, or either `enabled == false` | blind spot, not a finding |
| `enabled == null` | token-scope question; never report as "disabled" |

`truncated: true` makes `open` a floor. Report it as "at least N", never as a count.
