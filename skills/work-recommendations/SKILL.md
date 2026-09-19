---
name: work-recommendations
description: >
  Work the ordered recommendations from a survey-work plate: resolve each item to a GitHub issue
  (filing one, preview-then-confirm, where the plate item has none), then ship them in plate order
  through take-it. Use when the user says "work the recommendations", "work the recommendations in
  order", "work the plate", "work today's recommendations", "ship the recommendations", "work what's
  on the plate", "do the top 5", "take the recommendations", or hands over an ordered list of plate
  items to ship. Also the delegate that work-fire-watch invokes with an explicit item list. Reads
  the current repo's `.claude/sassy-dog/take-it.md` and `survey-work.md`; blocks on NO_CONFIG.
---

# Work-Recommendations

The plate already decided *what* and *in which order*. This skill turns that ordered list into
shipped PRs without re-ranking it: every item gets exactly one of five dispositions, the
issue-less ones are filed behind one preview, and the issues go to `take-it` in plate order.

**Acting principle:** the list is the contract. Never re-prioritize, never drop an item silently,
and never turn "in order" into "the ones that were easy".

## 1. Repo config

!`root="$(git rev-parse --show-toplevel 2>/dev/null)"; echo "CONFIG_SOURCE: ${root:-<not a git repo>}"; for f in take-it survey-work; do echo "--- $f ---"; cat "$root/.claude/sassy-dog/$f.md" 2>/dev/null || echo "NO_CONFIG"; done`

**Check `CONFIG_SOURCE` before using any of this.** It is the repo root resolved from the
**session's** working directory at skill-load time, not necessarily the repo you are about to act
on. If it names a different repo, discard the block above and read that repo's own
`.claude/sassy-dog/take-it.md` and `survey-work.md` by absolute path.

This skill has **no config file of its own**. It reads two that already exist:

- `take-it.md` — whether dispatch is possible at all. **If it reads `NO_CONFIG`, stop before
  filing anything**: an issue filed here that `take-it` then refuses to dispatch is the wrong half
  of the job done. Tell the user to run `sassy-dog:setup-config` first and offer it once per
  session, exactly as `take-it` does.
- `survey-work.md` — `execution_site` (the site rule below), `sentry.projects`, and the optional
  `board:` block (filed issues land on its Backlog column when present).

Repo slug and default branch are derived, never configured — run this **inside the target
checkout**, since it reads the session cwd exactly as the config block does:

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '"repo=\(.nameWithOwner) branch=\(.defaultBranchRef.name)"'
```

## 2. Find the list

Three sources, in precedence order. Use the first that applies and say which one you used:

1. **An explicit item list in this invocation's args** (this is how `work-fire-watch` calls in).
   The list is authoritative: its order is the order, and each line carries its own handle.
2. **The most recent `## 👉 Today's recommendations` block in this conversation**, rendered by
   `survey-work`. Items are `**<title>** — <category> · <why>`; the closing `_To ship:_` line names
   the issues this checkout can take.
3. **Neither present** → run `Skill: sassy-dog:survey-work` first (it is read-only), then use its
   block. Do not build a list from memory or from `gh issue list` — a list without the plate's
   scoring is not "the recommendations".

Echo the resolved, numbered list before doing anything else.

## 3. Resolve every item to a handle

Walk the list **in order** and give each item exactly one disposition. An item's handle comes from
the plate section it was drawn from — look the title up there; the recommendations line itself
carries no issue number.

| Where the item came from | Handle | Disposition |
| --- | --- | --- |
| Backlog line `#NNN`, or a `[GH #N]` on a Customer-pain Sources line | issue | **DISPATCH** |
| Any issue rendered with `(not this checkout)`, or one the site rule refuses | issue, off-site | **HOLD** — list it with its `site:` tokens; never claim it |
| Customer pain with a Sentry link and no `[GH #N]` | `sentry:<SHORT_ID>` | **FILE** with marker `sentry-source: <SHORT_ID>`, then DISPATCH. The short id (`PROJ-123`) is what `survey-work` and `sentry-triage` key on; a numeric id from a permalink is resolved to it with one read-only Sentry lookup first, and a handle that arrives numeric (the caller could not resolve it) is filed as `sentry-source: <numeric id>` and flagged, since it will not dedupe against theirs |
| Next bet, tech debt, or dev-experience item with no issue | none | **FILE** with marker `plate-source: <category>/<slug>`, then DISPATCH |
| Security `Fix: merge PR #N` (a Dependabot PR) | PR | **SHEPHERD** |
| Security `rotate and revoke`, any secret-scanning alert | none | **HUMAN-ONLY** — surface first, with the Fix line; never filed, never dispatched |
| Already in flight `PR #N` | PR | **SHEPHERD** |
| Already in flight bare branch (no PR) | branch | report "a `send it` away" and stop there — `send-it` is operator-facing |
| Blind spot, inherited debt, `Suspected complete` epic | none | not a work item; one line saying so |

A list that arrived through args (§2 source 1) carries its handles inline, and they map
directly: `#N` → DISPATCH (site rule still applies), `sentry:<id>` → FILE, `pr:#N` → SHEPHERD,
`human-only` → HUMAN-ONLY, and `fire-watch:<kind>/<id>` → FILE with marker
`fire-watch-source: <kind>/<id>` and the label `ci-cd` for `ci-red` or `observability` for
`cron`, both read from the taxonomy emitter below.

The site rule is the one `survey-work` applies to its `_To ship:_` line: with `execution_site`
configured, an issue whose `site:` labels do not include this checkout is HOLD. Resolve labels
with `sassy-dog:github-issues`' `queue-snapshot.sh --sites-of` rather than reading them by eye.

**Why the secret alert is human-only:** the fix is minutes of a human's time in a vendor console,
rotation of a shared credential is irreversible and cross-product, and an issue describing an
active leak is itself a disclosure surface. Surfacing it first is the whole job.

## 4. File the issue-less items — one preview, one approval

Filing goes through the single creation path, never `gh issue create`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/file-or-link-issue.sh \
  --repo <owner/name> \
  --marker "<marker from the table above>" \
  --title "<title>" --body-file <path> \
  --labels "<labels>" \
  --dry-run
```

- `sentry:` handles use labels `bug,sentry-escalation` — the same marker and labels
  `survey-work`'s gated write path uses, so the two never double-file the same signal. Build the
  `--ensure-label` value from the label's owner, never from a transcribed colour:
  `bash ${CLAUDE_PLUGIN_ROOT}/skills/github-issues/scripts/issue-claim.sh taxonomy | grep '^sentry-escalation|'`
  emits `name|color|description`, which is the `--ensure-label` shape with `|` swapped for `:`.
- `plate-source:` handles use the plate category's own label: `tech-debt` or `dx`, read the same
  way from `${CLAUDE_PLUGIN_ROOT}/scripts/align-labels.sh taxonomy`; a next bet takes GitHub's
  default `enhancement`, which is not in the taxonomy — pass it in `--labels` with no
  `--ensure-label`, and if `gh label list` shows the repo lacks it, say so in the preview rather
  than inventing a colour.
- When `board:` is configured, pass `--project-id`, `--status-field-id` and
  `--status-option-id <backlog_option_id>` so the issue lands on the Backlog column.

**The body must be dispatchable**, or `take-it` refuses it on arrival: well over 80 characters,
a `## Evidence` section (the Sentry permalink and counts, or the plate's signals verbatim), and a
`## Acceptance` section stating what done looks like. A next-bet item's scope is written here —
and it is the preview that lets the user correct it. Never title it `Investigate:`, `Spike:` or
`Assess:`; those are research docs and `take-it` flags them.

Then, exactly once per run:

1. Dry-run **every** candidate and print the full `would-file` / `already-linked` set together
   with each proposed body.
2. More than 5 would-file → stop and show the list; ask whether an umbrella issue fits.
3. File only after the user approves. **"Don't bother me with questions" is not approval.**
   Approval for one batch never carries over to the next run.
4. Capture each result's issue number; an `already-linked` number is used as-is.

## 5. Dispatch, in order

One `take-it` call carrying every DISPATCH handle in plate order — the first five get this
round's slots, the rest queue, and the order is what decides who waits:

```text
Skill: sassy-dog:take-it
Args: "take #<N> #<M> #<K> — in this order; from work-recommendations."
```

One `pr-shepherd` call for every SHEPHERD handle, with the repo's merge policy from `take-it.md`:

```text
Skill: sassy-dog:pr-shepherd
Args: "Watch PRs <numbers> in <owner/name>. Merge policy: <from merge_queue>. Report why any
       stuck PR is stuck; do not close/reopen to retrigger."
```

If `sassy-dog:take-it` is not among your available skills, STOP and tell the user to install the
plugin (`claude plugin install sassy-dog`) — do not improvise the dispatch from memory.

## 6. Report

After the dispatch returns, render one table in plate order, then the held and human-only lists:

```markdown
# Worked the recommendations (YYYY-MM-DD)

| # | Item | Handle | Disposition | Outcome |
| --- | --- | --- | --- | --- |
| 1 | <title> | — | HUMAN-ONLY | rotate and revoke — alert #7 |
| 2 | <title> | #<filed> | FILE → DISPATCH | PR #<P> merged |
| 3 | <title> | #398 | DISPATCH | PR #<P> held — Blocking review finding |
| 4 | <title> | #402 | HOLD | `site:mac` — run `take #402` from that checkout |

_Human-only: <one line per item, Fix line verbatim>_
_Held: <one line per item, with the site it waits for>_
```

Every list item appears exactly once. An outcome that is not yet terminal says so
("queued — slot 6", "PR open, checks running") rather than reading as done.

## Guardrails

- **Never re-rank.** The plate scored; `take-it` executes; this skill only translates.
- **Every outward write is preview-then-confirm** — filing (§4) and, through `take-it`, claiming
  and dispatching. Nothing here mutates Sentry, edits an existing issue, or closes anything.
- **Never `gh issue create` directly.** The markers are what make a re-run idempotent, and only
  the script writes them.
- **No new markers.** `sentry-source:` and `plate-source:` are the two this skill writes.
  `work-fire-watch` adds `fire-watch-source:` for its own item kinds; the list is closed.
