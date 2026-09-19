---
name: work-fire-watch
description: >
  Work this repo's items from the latest daily-fire-watch post: read the newest "What's on fire"
  report from Slack #daily-fire-watch, keep only the lines routed to the repo you are in, keep the
  report's own order, and ship them through work-recommendations. Use when the user says
  "work the fire watch", "work fire watch", "work today's fire watch", "work the fire-watch items",
  "work our fire-watch items", "work the daily fire watch for this repo", "what's on fire for this
  repo — work it", or "take today's fire watch". Single-repo and Slack-read-only: it never posts to
  Slack and never re-runs the org sweep. Reads the current repo's `.claude/sassy-dog/take-it.md`
  and `survey-work.md`; blocks on NO_CONFIG.
---

# Work-Fire-Watch

The `daily-fire-watch` routine already swept every repo in the org this morning and posted one
report. Re-running `survey-work` in each repo to rediscover the same items burns tokens. This
skill reads that post, keeps the lines that belong to **this** repo, and hands them to
`work-recommendations` in the report's own priority order. It owns fetch, filter and normalize —
nothing else.

**Acting principle:** the report is evidence about the org, not about this repo until a line is
routed here by an exact match. A guess about ownership ships the wrong repo's work.

## 1. Repo config

!`root="$(git rev-parse --show-toplevel 2>/dev/null)"; echo "CONFIG_SOURCE: ${root:-<not a git repo>}"; for f in take-it survey-work; do echo "--- $f ---"; cat "$root/.claude/sassy-dog/$f.md" 2>/dev/null || echo "NO_CONFIG"; done`

**Check `CONFIG_SOURCE` before using any of this.** If it names a repo other than the one you are
working in, discard the block above and read that repo's own `.claude/sassy-dog/take-it.md` and
`survey-work.md` by absolute path.

This skill has **no config file of its own**:

- `take-it.md` reading `NO_CONFIG` → **stop here**, before reading Slack. Nothing found could be
  shipped. Tell the user to run `sassy-dog:setup-config` first; offer once per session.
- `survey-work.md` → `sentry.projects` (routing, §3). Nothing else here reads it.

Derive the slug, and from it the bare name the report uses — **inside the target checkout**,
since `gh repo view` reads the session cwd exactly as the config block does:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
# bare name = the part after the slash; the report never writes the owner
```

## 2. Fetch the latest post

Resolve the Slack tools **by capability** — one that searches channels by name, one that reads a
channel's recent messages. Never hardcode a `mcp__...` tool id; the prefix differs per host.

- Channel: `#daily-fire-watch`, found by name. Its id is expected to be `C0BNNEE59PX`; a different
  id is worth one line in the header, not a stop.
- Read the newest messages, newest first, and stop at the first that is a routine post — one
  whose first line is `# What's on fire (YYYY-MM-DD)` or the `⚠` could-not-run line below. Human
  chatter in between is skipped. The routine posts **one message per run**, so the report is one
  message — never stitch several.
- **No Slack tools connected** → STOP: "Slack MCP is not connected — connect it, or run
  `survey-work` here instead." There is no paste fallback and no re-run of the sweep.

Three posts to recognize before acting on anything:

| The routine post found… | Do |
| --- | --- |
| begins `⚠ **daily-fire-watch could not run.**` | STOP. No sweep happened; today's silence is not a clean bill of health. Do not fall back to running `whats-on-fire` locally — that is a different, un-gated sweep. |
| is dated more than one day before today | Say the age in one line and **ask** before continuing; a two-day-old fire may be out, or worse. |
| says it was **truncated** | Continue, and carry "truncated — items may be missing" into the header. |

Copy the report's `_Load: …_` and `_Coverage: …_` lines **verbatim** — the whole line, `Sources:`
included — into your header. Do not interpret them: the run log, not the report, is the
authority on how the run loaded, and `docs/ROUTINES.md` owns that reading.

Read-only toward Slack: never post, react, thread, or edit.

## 3. Filter to this repo

Every item line is routed by **exact token equality** against the bare repo name — never a
prefix or substring, because `velovate` and `velovate-web` are two repos of one product and a
prefix match ships one repo's work from the other. The report's sections spell ownership three
ways:

| Line shape (section) | Routes here when |
| --- | --- |
| `**<repo>#<N> <title>**` (Stuck shipping, Backlog heat) | `<repo>` equals the bare name |
| `**<product> — <rule>** — <repo>`, `**<repo>**`, `— <affected repos>` (Security, Stale CI, Blind spots) | the `<repo>` token equals the bare name |
| `**<product> — <title>**` (Production fires, Top 5) | any of: a `repo:<name>` token on the line equals the bare name; `<product>` equals the bare name; the item's Sentry link `?project=<slug>` names a slug listed in `sentry.projects`; the user passed a product override in args ("work fire watch as velovate") |

A product-only line that matches none of those is one of two things. If the product token is a
hyphen-separated component of the bare name, or the bare name is a component of it (`velovate`
against `velovate-web`), the line goes into a **routing unconfirmed** list — shown, never worked,
because one product can own several repos and this may be ours. Otherwise it is another
product's line and is dropped with the count. The product→repo map lives as prose in
`whats-on-fire`; do not transcribe it here and do not guess from it. Lines whose repo token names
another repo are dropped the same way.

When a line routes here on product name but its Sentry slug is **not** in `sentry.projects`, it
is still ours — add one header line saying which slug the config is missing, so `setup-config`
can be run to reconcile it.

Top-5 lines duplicate items already listed in their own section; use them only to confirm order,
never as a second item.

## 4. Normalize into the recommendations shape

Order is the report's: first the routed items in the order `## 👉 Today's top 5` lists them,
then every other routed item by section — Production fires and Security by tier (P0, P1, P2),
then Stuck shipping, then Backlog heat — keeping the report's own order within each. Number
them, and give every line its handle inline so `work-recommendations` never has to look it up:

```markdown
1. **<rule>** — Security P0 · <Fix line verbatim> · human-only
2. **<title>** — Production fires P0 · <why> · sentry:<SHORT_ID resolved from the permalink>
3. **<title>** — Stuck shipping · idle 9d · pr:#427
4. **<title>** — Backlog heat · `priority:high` · #398
5. **`<monitor>` missed** — Production fires P1 · <env> · fire-watch:cron/<monitor-slug>
```

Handle kinds, and what `work-recommendations` does with them:

| Handle | Disposition there |
| --- | --- |
| `#<N>` | dispatch via `take-it` |
| `sentry:<SHORT_ID>` | file with marker `sentry-source: <SHORT_ID>`, then dispatch. The permalink carries a numeric id; resolve the short id (`PROJ-123`) with one read-only Sentry lookup, by capability. No Sentry tools → pass `sentry:<numeric id>` and say so in the args |
| `pr:#<N>` (stuck PR, or a Security `Fix: merge PR #N`) | `pr-shepherd` |
| `fire-watch:ci-red/<workflow>` (red default branch) | file with marker `fire-watch-source: ci-red/<workflow>`, then dispatch |
| `fire-watch:cron/<monitor-slug>` (missed / timed-out / erroring monitor) | file with marker `fire-watch-source: cron/<monitor-slug>`, then dispatch |
| `human-only` (secret-scanning alert, `rotate and revoke`) | surfaced first; never filed, never dispatched |

Stale CI verdicts and Blind spots naming this repo are report-only rows; they carry no handle
and are not numbered. A `⏳ Fixed, awaiting scheduled confirmation` cron is not a work item.

## 5. Delegate

One call. `work-recommendations` owns filing (preview-then-confirm), dispatch order, and the
final report:

```text
Skill: sassy-dog:work-recommendations
Args: "From daily-fire-watch (YYYY-MM-DD; Load: <verbatim>; truncated — only when it was) for <owner/name>,
       in this order:
       <the numbered list from §4, handles inline>
       Routing unconfirmed (not worked): <lines, or 'none'>"
```

If `sassy-dog:work-recommendations` is not among your available skills, STOP and tell the user
to install the plugin (`claude plugin install sassy-dog`) — do not improvise the loop here.

## 6. Header

Before the delegate's output, print:

```markdown
# Fire watch → <owner/name> (report YYYY-MM-DD)

_Load: <verbatim> · Coverage: <verbatim>_
_Routed here: N · Routing unconfirmed: M · Other repos: K (dropped) · Report-only: J_
```

Add a `truncated — items may be missing` segment only when the report said so, a channel-id
line only when the id differed, and a `sentry.projects` line only when §3 found a missing slug.

## Guardrails

- **Slack is read-only.** No post, no reaction, no thread — the routine is the channel's only
  writer.
- **Never re-run the sweep.** A missing or unreadable report is a stop, not a reason to invoke
  `whats-on-fire` from a laptop with a different gate and different sources.
- **Exact-name routing only.** No prefix, no substring, no product map from memory. Unconfirmed
  is a listed outcome, not a failure to hide.
- **Order is the report's.** This skill never rescores; `work-recommendations` never re-ranks.
- **No filing from here.** Every write happens in the delegate, behind its preview.
