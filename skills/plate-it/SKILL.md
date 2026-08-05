---
name: plate-it
description: >
  Synthesize the full work surface for the current repo — customer pain (Sentry, GitHub bugs,
  TestFlight feedback), backlog (board or open issues + labels), tech debt (TODO/FIXME, skipped
  tests), dev experience (CI duration/flake, dependency exposure), and synthesized "next bet"
  candidates with no GitHub issue yet. Dedupes across sources, scores within each category, returns
  a prioritized inline plate. Use when the user says "what's on our plate", "what's on our plate
  today", "what should we work on", "plate it", "what's next", "what should I prioritize", "give me
  the plate", "what hurts customers most", or "triage". Reads the current repo's settings from
  `.claude/sassy-dog/plate-it.md`. Read-only unless that config sets `write_policy: gated`.
---

# Plate-It

Synthesize everything we might tackle into one prioritized plate.

## 1. Repo config

!`cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/sassy-dog/plate-it.md" 2>/dev/null || echo "NO_CONFIG"`

Frontmatter supplies `scan_paths`, `exclude_pathspecs`, `ci_workflow`, `priority_labels`,
`write_policy`, and the optional `sentry`, `board`, `testflight`, `mobile`, `posthog`, and
`secret_bootstrap` blocks. Contract: `ai-agent-skills:refresh-sassydog-skills` →
`references/config-contract.md`.

**Write posture is decided here.** `write_policy: read-only` (or absent, or `NO_CONFIG`) means this
skill NEVER files issues or mutates anything. Only `write_policy: gated` unlocks §7.

**If it reads `NO_CONFIG`**, run read-only across whatever surfaces are derivable — GitHub bugs,
open issues, and a tech-debt scan over the repo root — mark every configured surface `skipped — not
configured`, and tell the user to run `ai-agent-skills:refresh-sassydog-skills`. A degraded plate is
useful; a wrong one is not.

## 2. Prerequisites

Run these probes. For each failure, label that surface "skipped — <reason>" in the output and
continue. **Never abort the whole plate on one missing precondition.**

```bash
gh auth status && cd "$(git rev-parse --show-toplevel)"
```

**If `secret_bootstrap:` is configured**, run it here — before any presence probe below.
Non-interactive agent shells never fire direnv, so probing a bare environment false-negatives
("missing") on credentials the secret manager actually holds. On bootstrap error, continue; the
probes then report their surfaces per the skip rule above.

Each tool shell starts bare — the bootstrap only loads the shell it runs in. Prefix any later
env-dependent command (such as the §3 TestFlight pull) with the same bootstrap line. Never
presence-check an environment variable this skill hasn't loaded yet.

Probe only the surfaces config enables: Sentry by listing projects for the configured org;
TestFlight by checking that the App Store Connect key is present.

## 3. Pull all surfaces in parallel

Issue the independent pulls in a single message with multiple tool calls.

### A. Customer pain

**Sentry** *(if `sentry:` is configured)* — invoke `ai-agent-skills:sentry-triage` with the
configured org and projects. Gate policy: the configured `sentry.gate` when `write_policy: gated`,
otherwise report-only with no escalation. It handles query syntax, the qualifying gate, and GitHub
cross-referencing.

**GitHub bugs** —

```bash
gh issue list --state open --label bug \
  --limit 100 --json number,title,labels,createdAt,updatedAt,reactionGroups,comments,url
```

Demand proxy = reactions + comments.

**TestFlight** *(if `testflight:` is configured)* — invoke `ai-agent-skills:testflight` with the
configured bundle id, command `feedback`. Parse screenshot submissions (tester comments) and crash
submissions (stack signatures). Tag items `[TestFlight]`.

**PostHog** *(if `posthog: true`, best-effort)* — if a read key is provisioned, pull survey
responses and high-frequency `$exception` events; otherwise render `skipped — PostHog (no read
key)` and move on.

### B. Backlog

**With `board:`** — board snapshot via `ai-agent-skills:github-issues`, using the configured board
number and owner, plus its stale-issue detection.

**Without a board** — open issues and labels:

```bash
gh issue list --state open --limit 200 --json number,title,labels,updatedAt
```

plus `ai-agent-skills:github-issues` stale-issue detection.

### C. Tech debt + dev experience

Invoke `ai-agent-skills:repo-health`:

- tech-debt scan with the configured `scan_paths` and `exclude_pathspecs`
- CI health with the configured `ci_workflow`
- dependency exposure + remediation (no environment needed; defaults to cwd)
- mobile release lag with the configured `mobile.release_workflow` and `mobile.path_prefix`, **if
  `mobile:` is configured**

Its `references/scoring.md` thresholds apply unless overridden by config.

**MEMORY signals** — scan the project memory index for recurring friction (`feedback_*` /
`project_*` entries); each derived suggestion cites its memory file.

Then apply any `## extra-surfaces` section from config — additional product-specific surfaces such
as in-app feedback tables, funnel health, infra drift, or deprecation scans.

### D. Next bets (synthesized)

Cluster feedback and error items that lack a GitHub issue into candidate "next bets" — themes with
≥2 independent signals. Recommendation-only; never auto-filed.

## 4. Dedupe across sources

Correlation keys: auto-file marker ↔ GitHub body (`<source>-source: <ID>`); bug-labeled issue ↔
board item ("also on board"); TODO containing `#NNN` ↔ that issue; TestFlight crash signature ↔
Sentry `culprit` via fuzzy top-frame match.

Merged items retain ALL source links — cross-source overlap boosts score in §5.

## 5. Score within each category

Score each category independently; surface a cross-category top-5 by relative rank at the end.

**Customer pain**:
`impact = severity × log10(1+occurrences) × log10(1+distinct_users) × recency_decay × source_overlap_boost`
— severity: crash=10, error=6, bug-label=4, feedback=2, suggestion=1; recency_decay 1.0/0.7/0.4/0.1
for ≤2d/≤7d/≤30d/older; overlap boost 1.0/1.5/2.0 for 1/2/3 sources.

**Backlog**: lead with the issue's own priority label (the configured `priority_labels`), tie-break
by reactions + comments. Don't re-derive a priority the maintainer already assigned.

**Tech debt + dev experience**: `ai-agent-skills:repo-health` scoring defaults.

**Dependency exposure**: rank by REMEDIATION STATE, never by alert count — a count only falls when
a fix merges, so a fresh CVE batch with fixes already queued looks identical to a year of neglect.
A `parked_green` PR aged ≥3 days is **P0** and belongs under Dev experience with its number and
merge command: the fix exists, it is green, and only a human press is missing.
`unremediated_packages` with an available patch is **P1** (**P0** past 14 days). A `BLOCKED` or
`DIRTY` fix PR is **P1** — name the failing check, since it is usually a lockfile the updater
cannot regenerate. A fresh batch (≤2 days) fully covered by open fix PRs is not a finding; it goes
on the `✓ Clean today:` line.

Then apply any `## scoring-overrides` section from config — project-specific re-weights.

## 6. Output format

Render inline as markdown. Two anti-verbosity rules are non-negotiable: empty surfaces get a single
token on the consolidated `✓ Clean today:` line, never their own section; and within a section,
skip empty P-buckets. Recommendations go LAST.

```markdown
# On the plate (YYYY-MM-DD)

_Sources: <pulled, with any "skipped — reason">_

✓ Clean today: <surface> · <surface> · ...

## 🔥 Customer pain (P0: N · P1: N · P2: N)
### P0
- **<title>** — score X.X
  - Impact: N users, M occurrences, last seen Yh ago
  - Sources: [Sentry](url) · [GH #123](url)
  - Why this matters: <one line>
### P2 (count + 3 sample titles, collapsed)

## 🎯 Backlog priorities
- **#NNN <title>** — `<label>` — <one-line why>

## 🧹 Tech debt
## 🛠 Dev experience
## 💡 Next bet candidates (synthesized — not yet on the backlog)
## ✅ Already in flight
## 🆕 Auto-filed this run   <!-- gated write_policy only; omit entirely when empty -->

## 👉 Today's recommendations (cross-category top 5)
1. **<title>** — <category> · <one-line why>

_To ship: `take #<N> #<M>`_
```

## 7. Write policy

**When `write_policy: read-only`, absent, or `NO_CONFIG`** — this skill NEVER files GitHub issues,
changes Sentry status, or mutates anything. If an unfiled signal deserves an issue, the plate says
so and the human files it, or runs the filing flow explicitly. Stop here.

**When `write_policy: gated`** — the skill writes in exactly ONE place: qualifying Sentry hits
promoted to GitHub issues via `ai-agent-skills:github-issues`' `file-or-link-issue.sh` with
`--marker "sentry-source: <SHORT_ID>"`. Gate and burst rail per `ai-agent-skills:sentry-triage`
(`references/qualifying-gate.md`), using the configured `sentry.gate`. Labels
`bug,sentry-escalation`; when `board:` is configured, file onto its Backlog column.

Hard prohibitions, regardless of policy: never mutate Sentry status; never edit existing issues
from this gate; never file from tech debt, CI, memory, or next-bet surfaces — those stay
recommendations. Dry-run with `DRY_RUN=1` after any gate change.

Apply any `## extra-guardrails` section from config on top of these.
