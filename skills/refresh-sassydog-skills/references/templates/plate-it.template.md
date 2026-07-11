<!--
TEMPLATE: plate-it · version 1
Render rules (applied by refresh-sassydog-skills at generation time):
  {{FACT}}                    → replace with the detected/confirmed value
  IF:FLAG ... ELSE ... ENDIF  → keep one arm based on interview answers, drop the markers
  BEGIN/END PROJECT-SPECIFIC  → KEEP the fence markers in the generated file (update mode splices these)
  Drop this comment block from the generated output. The frontmatter `---` below MUST be line 1
  of the rendered file — Claude Code's skill loader only parses frontmatter that starts on line 1.
  Keep the generated-by marker where it sits: immediately AFTER the closing `---`, never before it.
-->
---
name: plate-it
description: >
  Synthesize the full {{PROJECT_NAME}} work surface — customer pain (<!-- IF:SENTRY -->Sentry, <!-- ENDIF -->GitHub bugs<!-- IF:TESTFLIGHT -->, TestFlight feedback<!-- ENDIF --><!-- IF:POSTHOG -->, PostHog<!-- ENDIF -->),
  backlog ({{BACKLOG_SOURCE_DESCRIPTION}}), tech debt (TODO/FIXME, skipped tests), dev experience
  (CI duration/flake<!-- IF:MOBILE -->, mobile release lag<!-- ENDIF -->), and synthesized "next bet" candidates with no GitHub
  issue yet. Dedupes across sources, scores within each category, returns a prioritized inline
  plate. Use when the user says "what's on our plate", "what's on our plate today", "what should
  we work on", "plate it", "what's next", "what should I prioritize", "give me the plate",
  "what hurts customers most", or "triage". {{PROJECT_NAME}}-specific.
  <!-- IF:WRITE_GATE_SENTRY -->Files GitHub issues only under the tight Sentry→GH gate in §6; every other surface is read-only.<!-- ELSE -->Read-only — never files issues, never mutates state.<!-- ENDIF -->
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: plate-it | template-version: 1 -->

# {{PROJECT_NAME}} Plate-It

Synthesize everything we might tackle for {{PROJECT_NAME}} into one prioritized plate.

<!-- IF:WRITE_GATE_SENTRY -->
The skill is **mostly read-only**, with one exception: it auto-files GitHub issues under the §6 gate for qualifying Sentry hits with no GitHub peer — so the plate (and downstream `take-it`) always reference issue numbers instead of dead links. Read §6 before changing anything here.
<!-- ELSE -->
The skill is **read-only**. It pulls, dedupes, scores, and reports. It NEVER files GitHub issues or mutates any external state.
<!-- ENDIF -->

## 1. Prerequisites

Run these probes. For each failure, label that surface "skipped — <reason>" in the output and continue. **Never abort the whole plate on one missing precondition.**

```bash
gh auth status && cd "$(git rev-parse --show-toplevel)"
<!-- IF:SECRET_BOOTSTRAP -->
# Secret bootstrap — MUST stay before the presence probes below. Non-interactive agent
# shells never fire direnv, so probing a bare env false-negatives ("missing") on
# credentials the secret manager holds. On bootstrap error, continue — the probes
# then report their surfaces per the skip rule above.
{{SECRET_BOOTSTRAP_CMD}}
<!-- ENDIF -->
<!-- IF:SENTRY -->
# Sentry MCP — probe by listing projects for org {{SENTRY_ORG}}; on error, skip Sentry.
<!-- ENDIF -->
<!-- IF:TESTFLIGHT -->
[[ -n "${APPLE_ASC_API_KEY_ID:-}" ]] && echo "asc:ok" || echo "asc:missing"
<!-- ENDIF -->
```
<!-- IF:SECRET_BOOTSTRAP -->

Each tool shell starts bare — the bootstrap only loads the shell it runs in. Prefix any later env-dependent command (e.g. the §2 TestFlight pull) with the same bootstrap line; never presence-check an env this skill hasn't loaded yet.
<!-- ENDIF -->

## 2. Pull all surfaces in parallel

Issue the independent pulls in a single message with multiple tool calls.

### A. Customer pain

<!-- IF:SENTRY -->
**Sentry** — invoke `ai-agent-skills:sentry-triage`: org `{{SENTRY_ORG}}`, project(s) {{SENTRY_PROJECTS}}. Gate policy: <!-- IF:WRITE_GATE_SENTRY -->defaults ({{SENTRY_GATE_SUMMARY}})<!-- ELSE -->report-only, no escalation<!-- ENDIF -->. It handles query syntax, the qualifying gate, and GH cross-referencing.
<!-- ENDIF -->

**GitHub bugs** —

```bash
gh issue list --repo {{REPO_SLUG}} --state open --label bug \
  --limit 100 --json number,title,labels,createdAt,updatedAt,reactionGroups,comments,url
```

Demand proxy = reactions + comments.

<!-- IF:TESTFLIGHT -->
**TestFlight** — invoke `ai-agent-skills:testflight`, bundle id `{{BUNDLE_ID}}`, command `feedback`. Parse screenshot submissions (tester comments) and crash submissions (stack signatures). Tag items `[TestFlight]`.
<!-- ENDIF -->
<!-- IF:POSTHOG -->
**PostHog** *(best-effort)* — if a read key is provisioned, pull survey responses / high-frequency `$exception` events; otherwise render `skipped — PostHog (no read key)` and move on.
<!-- ENDIF -->

### B. Backlog

{{BACKLOG_SOURCE_NOTE}}

<!-- IF:BOARD -->
Board snapshot — invoke `ai-agent-skills:github-issues` (board snapshot, `PROJECT_NUMBER={{BOARD_NUMBER}}`, `OWNER={{ORG}}`), plus its stale-issue detection (`REPO={{REPO_SLUG}}`).
<!-- ELSE -->
Open issues + labels — `gh issue list --repo {{REPO_SLUG}} --state open --limit 200 --json number,title,labels,updatedAt`, plus `ai-agent-skills:github-issues` stale-issue detection (`REPO={{REPO_SLUG}}`).
<!-- ENDIF -->

### C. Tech debt + dev experience

Invoke `ai-agent-skills:repo-health`:

- tech-debt scan with `SCAN_PATHS="{{SCAN_PATHS}}"`, `EXCLUDE_PATHSPECS="{{EXCLUDE_PATHSPECS}}"`
- CI health with `WORKFLOW={{CI_WORKFLOW}}`
<!-- IF:MOBILE -->
- mobile release lag with `WORKFLOW={{RELEASE_WORKFLOW}}`, `MOBILE_PATH_PREFIX={{MOBILE_PATH_PREFIX}}`
<!-- ENDIF -->

Its `references/scoring.md` thresholds apply unless overridden below.

**MEMORY signals** — scan the project memory index for recurring friction (`feedback_*`/`project_*` entries); each derived suggestion cites its memory file.

<!-- BEGIN PROJECT-SPECIFIC: extra-surfaces -->
<!-- Additional product-specific surfaces (in-app feedback tables, funnel health, infra drift, deprecation scans) go here and survive template updates. -->
<!-- END PROJECT-SPECIFIC -->

### D. (synthesized) Next bets

Cluster feedback/error items that lack a GitHub issue into candidate "next bets" — themes with ≥2 independent signals. Recommendation-only; never auto-filed.

## 3. Dedupe across sources

Correlation keys: auto-file marker ↔ GH body (`<source>-source: <ID>`); bug-labeled issue ↔ board item ("also on board"); TODO containing `#NNN` ↔ that issue; <!-- IF:TESTFLIGHT -->TestFlight crash signature ↔ Sentry `culprit` (fuzzy top-frame match);<!-- ENDIF --> merged items retain ALL source links — cross-source overlap boosts score (§4).

## 4. Score within each category

Score each category independently; surface a cross-category top-5 by relative rank at the end.

**Customer pain**: `impact = severity × log10(1+occurrences) × log10(1+distinct_users) × recency_decay × source_overlap_boost` — severity: crash=10, error=6, bug-label=4, feedback=2, suggestion=1; recency_decay 1.0/0.7/0.4/0.1 for ≤2d/≤7d/≤30d/older; overlap boost 1.0/1.5/2.0 for 1/2/3 sources.

**Backlog**: lead with the issue's own priority label ({{PRIORITY_LABELS}}), tie-break by reactions + comments. Don't re-derive a priority the maintainer already assigned.

**Tech debt + dev experience**: `ai-agent-skills:repo-health` scoring defaults.

<!-- BEGIN PROJECT-SPECIFIC: scoring-overrides -->
<!-- Project-specific re-weights (e.g. "funnel drop-off below PRD target overrides the formula → P0") go here. -->
<!-- END PROJECT-SPECIFIC -->

## 5. Output format

Render inline as markdown. Two anti-verbosity rules are non-negotiable: (1) empty surfaces get a single token on the consolidated `✓ Clean today:` line, never their own section; (2) within a section, skip empty P-buckets. Recommendations go LAST.

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
<!-- IF:WRITE_GATE_SENTRY -->
## 🆕 Auto-filed this run   <!-- omit entirely when empty -->
<!-- ENDIF -->

## 👉 Today's recommendations (cross-category top 5)
1. **<title>** — <category> · <one-line why>

_To ship: `take #<N> #<M>`_
```

<!-- IF:WRITE_GATE_SENTRY -->
## 6. Conditional creation policy

The skill writes in exactly ONE place: qualifying Sentry hits promoted to GitHub issues via `ai-agent-skills:github-issues`' `file-or-link-issue.sh` with `--marker "sentry-source: <SHORT_ID>"`. Gate and burst rail per `ai-agent-skills:sentry-triage` (`references/qualifying-gate.md`): {{SENTRY_GATE_SUMMARY}}. Labels `bug,sentry-escalation`<!-- IF:BOARD -->; board {{BOARD_NUMBER}} → Backlog (`--project-id {{BOARD_PROJECT_ID}} --status-field-id {{BOARD_STATUS_FIELD_ID}} --status-option-id {{BOARD_BACKLOG_OPTION_ID}}`)<!-- ENDIF -->.

Hard prohibitions: never mutate Sentry status; never edit existing issues from this gate; never file from tech debt / CI / memory / next-bet surfaces — those stay recommendations. Dry-run with `DRY_RUN=1` after any gate change.
<!-- ELSE -->
## 6. Read-only contract

This skill NEVER files GitHub issues, changes Sentry status, or mutates anything. If an unfiled signal deserves an issue, the plate says so and the human files it (or runs the filing flow explicitly).
<!-- ENDIF -->

<!-- BEGIN PROJECT-SPECIFIC: extra-guardrails -->
<!-- END PROJECT-SPECIFIC -->
