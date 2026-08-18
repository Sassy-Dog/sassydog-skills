# Security scanning surface — design

**Date:** 2026-08-18
**Status:** approved for planning
**Repos touched:** `Sassy-Dog/sassydog-skills`, `Sassy-Dog/sassydog-routines`

## Problem

Neither `survey-work` nor `whats-on-fire` consults GitHub code scanning or secret scanning. The
only alerts API either one reads is `repos/{repo}/dependabot/alerts`, via
`skills/repo-health/scripts/pull-dependency-exposure.sh`. Everything first-party — CodeQL findings
and committed credentials — is invisible to every prioritization surface the org has.

`whats-on-fire` enumerates structural blind spots including "no dependency scanning", but never
asks whether code scanning is on. The blind-spot check is itself blind.

## Evidence

Probed live on 2026-08-18. This is not hypothetical exposure; the surface would be reporting these
on its first run.

| Repo | Code scanning (open) | Secret scanning (open) |
| --- | --- | --- |
| `velovate` | 102 — 1 critical, 25 high, 74 medium, all on `refs/heads/main` | 4 — **2 Google API keys with `validity: active`**, 2 Stripe webhook signing secrets |
| `platform` | 0 | 9 — 7 Azure AD application secrets + 1 Azure Storage account key, open since **2026-01-04** |
| `tailoredtip` | 9 | 0 |
| `qr-ninja` | 7 | 0 |
| `sassydog-web` | 2 | 0 |
| `sassydog-skills` | 0 | 0 |

`validity: active` means GitHub validated the credential against the provider. Those two Google
API keys are live.

A second finding came out of the same probe and constrains the design: the first
`per_page=100` call against `velovate` returned exactly `100`. Paginated, the true count is `102`.
An un-paginated read reports a silently capped number as a measurement.

## Decisions

Taken during brainstorming, recorded so the plan does not relitigate them.

1. **One `## 🔒 Security` section owns all three signals** — code scanning, secret scanning, and
   the Dependabot exposure ranking currently living under Dev experience.
2. **`whats-on-fire` gets full org-wide pulls**, not just a blind-spot boolean. Cost accepted.
3. **CodeQL alerts rank rule-clustered, split new-vs-inherited**, with a bounded Autofix probe.
4. **New-vs-inherited boundary is 14 days**, matching the existing
   `oldest_high_crit_age_days >= 14` rule in the dependency table.
5. **Unknown-validity secrets escalate to P0 at 30 days.** This makes `platform`'s seven Azure
   secrets P0 on day one, which is the intended reading.

## Part 1 — Engine

Two new scripts under `skills/repo-health/scripts/`, built as exact siblings of
`pull-dependency-exposure.sh`: `set -uo pipefail` **without** `-e`, exit 10 with
`skipped: <reason>` on stderr, one JSON object on stdout, never abort the caller's scan.

### `pull-code-scanning.sh`

```json
{ "enabled": true, "analyzed": true, "truncated": false,
  "open": 102, "default_branch": "main", "tools": ["CodeQL"],
  "new": [ { "rule": "js/sql-injection", "severity": "critical", "count": 3,
             "oldest_age_days": 6, "alerts": [109,110,112], "autofix": "ready" } ],
  "inherited": { "count": 91, "rules": 11, "oldest_age_days": 214,
                 "by_severity": {"critical":0,"high":25,"medium":66,"low":0} } }
```

Four properties, three inherited from the sibling and one new:

- **`enabled` is three-state.** `403` means "this token cannot see it", not "off". `null` is
  reported as a scope question, never as disabled. Same rule, same reason as Dependabot.
- **`analyzed` is a fourth state, and it is new.** The code-scanning API returns `404` for *both*
  "Advanced Security is off" and "on, but no analysis has ever run". Both produce `open: 0` and
  they mean opposite things — one is a config gap, the other is a clean repo. Collapsing them
  reports a never-scanned repo as clean, which is worse than reporting nothing.
- **Ref filter.** Only alerts whose `most_recent_instance.ref` equals
  `refs/heads/<default_branch>`, with the default branch resolved from `gh repo view` — never
  hardcoded to `main`. An alert on a feature branch is not repo debt.
- **`truncated` is a field, not a hope.** Paginate to a hard cap; if the cap is reached, the count
  is reported as a floor and `truncated: true`. See the `100` vs `102` finding above.

`new[]` holds rules whose newest alert was created **within 14 days**; everything else collapses
into `inherited`. A rule with alerts on both sides of the boundary appears in `new[]` with only its
recent alerts counted, and its older ones fall to `inherited` — a rule that keeps re-firing is a
live regression, not settled debt.

Autofix is probed only for rules already ranked P0/P1 by severity — roughly 8 calls for
`velovate`, not 102. The probe therefore only ever **upgrades a P1 to P0**; it can never promote a
medium-severity rule, which is never probed and stays `autofix: null`. `autofix` values: `ready`,
`none`, `unsupported`, `null` (not probed).

### `pull-secret-scanning.sh`

```json
{ "enabled": true, "open": 9, "oldest_age_days": 226,
  "active": [ {"number":3,"type":"Google API Key","age_days":6,"bypassed":false} ],
  "unknown_validity": [ ... ], "inactive": 0 }
```

Same three-state `enabled` contract. No `analyzed` equivalent — secret scanning has no
"configured but never ran" state.

### Ranking

| Condition | Tier |
| --- | --- |
| `validity == "active"` | **P0** on day zero — GitHub validated it against the provider; it is a live credential. No age math. |
| `push_protection_bypassed == true` | **P0** — a human overrode the guard to commit it |
| `validity == "unknown"`, open >= 30d | **P0** — unverified and untriaged for a month is itself the finding |
| `validity == "unknown"`, open < 30d | **P1** — verify or dismiss |
| `new[]` rule, severity `critical` | **P0** — just shipped, fixable while the code is fresh |
| `new[]` rule, severity `high` | **P1** |
| `new[]` rule with `autofix: "ready"` | **P0** — the `parked_green` shape: the fix exists and only a human press is missing |
| `inherited` | **one debt line**, never enumerated, never in the top 5 |
| `enabled: false` or `analyzed: false` | not a finding — a **blind spot** row |
| `enabled: null` | not a finding — a token-scope question |
| `validity == "inactive"` | not a finding — clean line |

The rule-clustered, new-vs-inherited split exists because a flat severity ranking reproduces the
exact failure `pull-dependency-exposure.sh` was written to prevent. `velovate`'s 74 mediums
rendered as 74 rows is a wall nobody triages; rendered as "11 rules, oldest 214d, inherited debt"
it is one honest line, and the 3 alerts shipped this week get the attention.

## Part 2 — Consumers in `sassydog-skills`

### `survey-work`

- **§3C** invokes the two new `repo-health` scans alongside the existing dependency pull.
- **§5** loses `"A parked_green PR aged >= 3 days is P0 and belongs under Dev experience"`. The
  whole dependency-exposure ranking block moves into a new Security scoring subsection beside code
  and secret scanning. Dev experience keeps CI duration and flake only.
- **§6** gains `## 🔒 Security`, positioned **after Customer pain, before Backlog**. Exposure
  outranks planned work; it does not outrank a live customer-facing crash.
- Frontmatter `description` gains trigger phrases. Headroom measured: 802 of 1024 characters used.

### `whats-on-fire`

- `scripts/pull-repo-signals.sh` gains `code_scanning` and `secret_scanning` objects per repo,
  same state contracts. Its header documents cost as "1 + 2N calls, plus ONE extra per repo that
  actually has high/critical alerts"; that becomes `1 + 4N` plus conditional extras. **Correct the
  comment rather than leave it stale.**
- New `## 🔒 Security exposure` section in the report template, between Production fires and Stuck
  shipping. P0 security items are **not** duplicated into Production fires — the cross-product top
  5 is where urgency gets expressed, and this skill's existing rule is that semantically distinct
  signals stay in separate fields rather than merging into false alarms.
- `references/scoring.md` gains rows in the P0 table and the blind-spot table.
- `references/cloud-fallback.md` currently hardcodes
  `skipped — no gh CLI (Dependabot API unreachable)`. Whether the MCP surface exposes code and
  secret scanning is **unverified**; see Part 3. Default to a named skip until the probe settles
  it, because "unknown is not verified" is already this repo's rule for `enabled: null`.
- Frontmatter `description` headroom is **91 characters** (933 of 1024 used). New trigger phrases
  will not both fit; existing wording must be trimmed. This is an edit to a live trigger surface,
  not free space.

## Part 3 — `sassydog-routines`

`sassydog-routines/skills/whats-on-fire/SKILL.md` is **not** a copy of the plugin skill. It is a
second implementation for the unattended cloud environment, with its own CI
(`scripts/validate-routines.sh`), its own bats tests, and Python reducers in `scripts/routines/`
instead of `jq`. Its §0 Container facts record **no `gh` CLI, and it cannot be provisioned**.

Consequently the Part 1 engine — two bash scripts calling `gh api` — does not run there at all.
The cloud edition must reach the same data through GitHub MCP tools or declare a named skip,
exactly as it already does for Dependabot.

### Blocking probe

**Does the routine environment's proxied, org-gated GitHub MCP expose code-scanning and
secret-scanning tools?** This cannot be answered from a laptop session; no GitHub MCP server is
connected there. It must be established in the cloud environment and then recorded as a §0
Container fact — a constant established once, never re-derived per run.

**The probe must use `Sassy-Dog/velovate` as a positive control.** Probing an arbitrary repo is
worthless: an empty result is ambiguous between "the tool does not exist here", "it exists but the
org gate blocks it", and "the repo is genuinely clean". `velovate` holds 102 open code-scanning
alerts and 4 open secret-scanning alerts as of 2026-08-18. An empty result there means the
capability is absent; no other reading survives.

### Branch A — MCP exposes them

- §0 gains a Container-facts row.
- §2 gains the pulls, subject to the large-result protocol. The MCP tools return whole objects and
  ignore `per_page` as a size control; 102 alerts **will** exceed the tool-result ceiling and spill
  to a file. Per the protocol, the spill path is the deliverable and must be handed to a committed
  reducer — never hand-parsed.
- New `scripts/routines/reduce-scanning-alerts.py` performs the rule clustering, ref filter, and
  new-vs-inherited split in Python, producing the same shape as Part 1's `new[]` / `inherited`.
- Fixtures under `scripts/tests/fixtures/` including a truncated-page variant, plus bats coverage,
  matching the existing reducer test pattern.
- Report section and sources line updated.
- The reducer path must be written out in full wherever referenced — `validate-routines.sh` greps
  for these paths, so a shell shorthand would make a dangling reference invisible until 12:00 UTC.

### Branch B — MCP lacks them

- One §0 Container-facts row mirroring Dependabot's.
- One sources-line skip token.
- The blind spot is **named**, never silent.

Three edits, no reducer, no fixtures.

## Tests and gates

`scripts/test-scanning-states.sh`, wired into `scripts/preflight.sh` as gate **19** (existing gates
run to 18). Mock `gh` only — no repo, no network — matching every other test in this repo.

Four properties pinned, each mutation-proved against the pre-fix shape so the test cannot go
vacuous:

1. A `404` carrying "no analysis found" renders `analyzed: false`, **not** `enabled: false`.
   Collapsing both to `false` must FAIL.
2. A mock returning exactly 100 items plus a next-page link sets `truncated: true`. The
   un-paginated shape must FAIL. This pins the exact defect the live probe caught.
3. An alert on `refs/pull/7/merge` appears in neither `new[]` nor `inherited`.
4. Source-level: the `validity: "active"` -> P0 rule carries no age gate. Asserted against a
   **whitespace-flattened** copy of the file, per the hard-wrap false-PASS trap documented in
   `CLAUDE.md` — a line-scoped grep for forbidden wording turns a line wrap into a false PASS.

## Risks

**Two copies of the tier table, no gate between them.** The ranking tables will exist in both
`sassydog-skills` and `sassydog-routines`. A cross-repo assertion is not buildable: separate CI,
and the routines CI has no network by design. If they drift, the daily Slack report and the
interactive report rank the same live credential differently. This is the shape of the `#167`
third-copy problem minus any mechanism to catch it.

Accepted mitigation: a reciprocal pointer comment in both files naming the other, and this risk
section. Divergence is a known accepted cost, not a solved problem. Do not let a later change
describe it as gated.

**`whats-on-fire` description headroom.** 91 characters free against a hard CI limit. Trimming live
trigger phrases can silently reduce what activates the skill; verify triggers after editing.

**Consumer `## scoring-overrides` drift.** Moving dependency exposure out of Dev experience changes
a section consumer repos wrote overrides against. That prose is carried verbatim by refreshes and
never rewritten, so nothing breaks, but overrides referencing the old placement will read oddly
until touched. Rolls out as an issue filed per affected repo — never a direct cross-repo sweep.

## Sequencing

1. **PR 1 — `sassydog-skills`**: engine, consumers, gate 19. Fully verifiable locally via
   `bash scripts/preflight.sh`.
2. **Probe** — cloud environment, `velovate` as positive control. Settles Part 3's branch.
3. **PR 2 — `sassydog-routines`**: Branch A or B. Not verifiable locally; verification is a manual
   routine run or the 12:00 UTC firing.
4. **Rollout issues** — one per consumer repo carrying `## scoring-overrides`.

Version stamping follows the normal release flow: `bash scripts/stamp-version.sh` in the release
PR, never a hand-edited manifest.

## Out of scope

- Remediating the live findings above. `velovate`'s active Google API keys and `platform`'s
  seven-month-old Azure secrets are real and urgent, but they are other repos' work and belong in
  their own issues. This design builds the surface that reports them.
- Any write path. All three signals are read-only in every skill touched here. `survey-work`'s
  single gated write (Sentry escalation) is unchanged, and no security finding may be auto-filed.
