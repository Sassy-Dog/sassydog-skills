---
name: plate-it
description: >
  Synthesize the full ai-agent-skills work surface — customer pain (GitHub bugs),
  backlog (open GitHub issues + labels), tech debt (TODO/FIXME, skipped tests), dev experience
  (CI duration/flake), and synthesized "next bet" candidates with no GitHub
  issue yet. Dedupes across sources, scores within each category, returns a prioritized inline
  plate. Use when the user says "what's on our plate", "what's on our plate today", "what should
  we work on", "plate it", "what's next", "what should I prioritize", "give me the plate",
  "what hurts customers most", or "triage". ai-agent-skills-specific.
  Read-only — never files issues, never mutates state.
---

<!-- generated-by: ai-agent-skills:refresh-sassydog-skills | template: plate-it | template-version: 1 -->

# ai-agent-skills Plate-It

Synthesize everything we might tackle for ai-agent-skills into one prioritized plate.

The skill is **read-only**. It pulls, dedupes, scores, and reports. It NEVER files GitHub issues or mutates any external state.

## 1. Prerequisites

Run these probes. For each failure, label that surface "skipped — <reason>" in the output and continue. **Never abort the whole plate on one missing precondition.**

```bash
gh auth status && cd "$(git rev-parse --show-toplevel)"
```

## 2. Pull all surfaces in parallel

Issue the independent pulls in a single message with multiple tool calls.

### A. Customer pain

**GitHub bugs** —

```bash
gh issue list --repo Sassy-Dog/ai-agent-skills --state open --label bug \
  --limit 100 --json number,title,labels,createdAt,updatedAt,reactionGroups,comments,url
```

Demand proxy = reactions + comments.

### B. Backlog

No project board for this repo — the backlog is the open issue list with labels.

Open issues + labels — `gh issue list --repo Sassy-Dog/ai-agent-skills --state open --limit 200 --json number,title,labels,updatedAt`, plus `ai-agent-skills:github-issues` stale-issue detection (`REPO=Sassy-Dog/ai-agent-skills`).

### C. Tech debt + dev experience

Invoke `ai-agent-skills:repo-health`:

- tech-debt scan with `SCAN_PATHS="skills agents"`, `EXCLUDE_PATHSPECS=""`
- CI health with `WORKFLOW=ci.yml`

Its `references/scoring.md` thresholds apply unless overridden below.

**MEMORY signals** — scan the project memory index for recurring friction (`feedback_*`/`project_*` entries); each derived suggestion cites its memory file.

<!-- BEGIN PROJECT-SPECIFIC: extra-surfaces -->
<!-- Additional product-specific surfaces (in-app feedback tables, funnel health, infra drift, deprecation scans) go here and survive template updates. -->
<!-- END PROJECT-SPECIFIC -->

### D. (synthesized) Next bets

Cluster feedback/error items that lack a GitHub issue into candidate "next bets" — themes with ≥2 independent signals. Recommendation-only; never auto-filed.

## 3. Dedupe across sources

Correlation keys: auto-file marker ↔ GH body (`<source>-source: <ID>`); bug-labeled issue ↔ board item ("also on board"); TODO containing `#NNN` ↔ that issue; merged items retain ALL source links — cross-source overlap boosts score (§4).

## 4. Score within each category

Score each category independently; surface a cross-category top-5 by relative rank at the end.

**Customer pain**: `impact = severity × log10(1+occurrences) × log10(1+distinct_users) × recency_decay × source_overlap_boost` — severity: crash=10, error=6, bug-label=4, feedback=2, suggestion=1; recency_decay 1.0/0.7/0.4/0.1 for ≤2d/≤7d/≤30d/older; overlap boost 1.0/1.5/2.0 for 1/2/3 sources.

**Backlog**: lead with the issue's own priority label (no P0–P3 taxonomy in this repo — default GitHub labels; treat `bug` > `enhancement` > `documentation`), tie-break by reactions + comments. Don't re-derive a priority the maintainer already assigned.

**Tech debt + dev experience**: `ai-agent-skills:repo-health` scoring defaults.

<!-- BEGIN PROJECT-SPECIFIC: scoring-overrides -->
Marker-scan false positives: this repo's skills *document* TODO/FIXME/HACK scanning (e.g. `repo-health`, `assess-it`), so the tech-debt scan will match prose that talks about markers rather than real debt. Discount hits inside `references/` docs and quoted examples; count only markers annotating this repo's own scripts or genuinely unfinished sections.
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
  - Sources: [GH #123](url)
  - Why this matters: <one line>
### P2 (count + 3 sample titles, collapsed)

## 🎯 Backlog priorities
- **#NNN <title>** — `<label>` — <one-line why>

## 🧹 Tech debt
## 🛠 Dev experience
## 💡 Next bet candidates (synthesized — not yet on the backlog)
## ✅ Already in flight

## 👉 Today's recommendations (cross-category top 5)
1. **<title>** — <category> · <one-line why>

_To ship: `take #<N> #<M>`_
```

## 6. Read-only contract

This skill NEVER files GitHub issues, changes Sentry status, or mutates anything. If an unfiled signal deserves an issue, the plate says so and the human files it (or runs the filing flow explicitly).

<!-- BEGIN PROJECT-SPECIFIC: extra-guardrails -->
<!-- END PROJECT-SPECIFIC -->
