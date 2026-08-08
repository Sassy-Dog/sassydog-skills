---
name: repo-health
description: >
  This skill should be used when the user asks to "list TODO/FIXME/HACK markers", "scan tech debt
  markers", "find skipped tests", "how slow is CI", "CI duration and flake report", "is CI flaky",
  "is the release pipeline lagging", "mobile release lag", "is TestFlight behind main", or wants a
  quick scripted signals scan of code-debt markers, CI workflow health (median/p90 duration, flake
  hints), and release lag — the fast inputs a prioritization pass consumes. Also triggers when a
  project workflow skill (a generated plate-it) invokes sassy-dog:repo-health by name.
  For a full multi-agent engineering audit filed as GitHub Issues, use assess-it instead.
---

# Repo Health

Fast, scripted, read-only signal scans: tech-debt markers, skipped tests, CI duration/flake, mobile release lag. Each scan is one bundled script emitting parseable output. This is the cheap input layer for prioritization (e.g. a project plate-it); it makes no writes and files no issues.

## Scans

### Tech debt markers + skipped tests

```bash
SCAN_PATHS="apps/ packages/" \
EXCLUDE_PATHSPECS="packages/db/src/migrations/** src/generated/**" \
bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-tech-debt.sh
```

- `SCAN_PATHS` defaults to the whole tracked tree; pass source dirs to cut noise.
- `EXCLUDE_PATHSPECS` for generated/migration dirs the caller knows about.
- Output sections: `todo-markers` (capped 200), `skipped-tests` (capped 100), `todo-by-dir` (top 20 directories by marker count).

### CI duration + flake

```bash
WORKFLOW=ci.yml bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-ci-health.sh
```

Emits JSON: `{sample, median_min, p90_min, flake_runs, flake_shas}`. `REPO` defaults to cwd; `LIMIT` defaults to 50 runs. A "flake" is the same (headSha, event) failing then passing — the event key deliberately excludes merge-queue false positives (explained in the script header; don't simplify it away).

### Dependency exposure + remediation

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-dependency-exposure.sh
```

Emits JSON: `{enabled, open, high_crit, oldest_high_crit_age_days, vulnerable_packages, open_fix_prs, unremediated_packages, parked_green}`. `REPO` defaults to cwd.

**Rank by remediation state, never by alert count.** The count is lagging — it falls only when a fix merges, so a same-day CVE batch with fixes already queued is indistinguishable from a year of neglect:

| Condition | Tier |
|---|---|
| `parked_green[]` with `age_days >= 3` | **P0** — green, mergeable, and nobody is merging it. Quote the PR number and the merge command. |
| `unremediated_packages` non-empty, `oldest_high_crit_age_days >= 14` | **P0** — no PR was ever opened; the plumbing is broken. |
| `open_fix_prs[].state` is `BLOCKED`/`DIRTY`/`UNSTABLE` | **P1** — the bot did its job, the repo's CI rejects the fix. Usually a lockfile the updater cannot regenerate. |
| `unremediated_packages` non-empty, age `< 14` | **P1** — check whether a patched version exists upstream before escalating. |
| age `<= 2` and every vulnerable package is covered by an `open_fix_prs[]` entry | **not a finding** — one line on the clean list. The system is working. |

`open_fix_prs` is already filtered to PRs whose head ref names a vulnerable package, so an unrelated actions-group PR is never mistaken for a fix — judge per package, not per repo. `enabled: null` means "this token cannot see alerts", NOT "disabled"; report it as a scope question.

### Mobile release lag

```bash
WORKFLOW=mobile-release.yml MOBILE_PATH_PREFIX=apps/mobile/ \
bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-mobile-release-lag.sh
```

Emits JSON: last green iOS build (run/sha/date), `days_since_ios_success`, `mobile_commits_since`, and the latest run's iOS-leg state (catches a currently-stuck build). Skip this scan entirely for repos with no mobile app.

## Interpreting results

Read `references/scoring.md` for the default severity thresholds (CI p90 > 25/40 min, flake > 5%, lag rules, skipped-test placement). Callers with their own scoring override it; absent that, apply the defaults and report:

- One line per signal with the number and its threshold (e.g. "CI p90: 31 min (target < 25) → P1").
- Empty/clean signals collapse into a single "clean" line — no section per empty surface.
- Never enumerate every TODO marker; surface directory hotspots and anything naming an incident or security concern.

## Degradation

Each script degrades independently: exit 10 with a `skipped: <reason>` line on stderr (not in a git repo, `gh` scope missing, workflow name wrong). Report the surface as "skipped — reason" and continue with the rest; never abort the whole scan over one missing input.
