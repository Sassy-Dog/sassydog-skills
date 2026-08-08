# Cloud fallback — section 2B without `gh`

How to pull stuck shipping, backlog heat, and workflow health when `gh` is not on PATH. Cloud (CCR)
routine sessions ship no GitHub CLI, so both bundled scripts exit 10 with `skipped: gh not on PATH`
— but everything they pull except one surface is still reachable through the session's GitHub MCP
tools. Accepting the skip would drop the PR, issue, and workflow surfaces AND every blind spot
assembled from them; this recipe keeps all of that and skips only what is genuinely unreachable.

This is a promotion, not an invention. The 2026-08-08 verification run (session
`cse_01TtAVPyUMLKmAk4h1ZXd2t9`) improvised exactly this shape — 14 active repos discovered via
list-repos, each attached with `add_repo`, per-repo pulls fanned out to 5 parallel subagents, the
Dependabot gap named on the coverage line — at subagent cost and with per-run variance. Follow this
recipe instead of re-deriving it per run.

The scripts stay the primary path: whenever `gh` IS on PATH, run them. #98 tracks provisioning `gh`
into the cloud environment; once that lands, this recipe becomes the degraded path rather than the
only one.

## Resolve tools by capability, never by id

MCP tool ids vary by installation — different server prefixes per host app — so a hardcoded
`mcp__...` id is a recipe that breaks on the next session. Same convention the Sentry cron surface
already follows: describe the connected GitHub MCP server's tools by what they do and let the
session resolve them. The capabilities this recipe needs:

- **List repositories for an owner** — the roster.
- **Widen repo scope** — `add_repo` in current sessions. GitHub MCP tools typically start scoped to
  the repo the session opened in (the verification run started scoped to `sassydog-skills` alone);
  every other repo must be attached before its PRs, issues, or runs can be read.
- **List or search pull requests** and **issues** — per repo, or org-wide if the server offers it.
- **List workflow runs** — per repo.

No GitHub MCP server connected at all → there is no fallback to the fallback: all of section 2B is
`skipped — <reason>` per section 1. Never turn "could not check" into silence.

## Order of operations

1. **Roster first.** List the org's repositories and capture per repo: name, archived flag, last
   push timestamp, default branch. The roster is the org, not the local directory (section 3), and
   it is the one hard prerequisite — every later step filters against it.
2. **Widen scope.** Attach each active repo with the scope-widening tool before any per-repo pull.
   Skipping this step does not fail loudly — an unattached repo simply comes back empty, which
   reads as "healthy" and is exactly the silent gap this skill exists to prevent.
3. **Fan out.** The per-repo pulls are chatty — dozens of raw workflow-run payloads would swamp the
   coordinating context. Dispatch parallel subagents, each owning a batch of repos (the
   verification run used 5 across 14 repos), each returning ONLY the compact per-repo JSON mapped
   below. Issue the batch in a single message with multiple Agent calls.
4. **Reassemble.** Merge the subagent outputs into the same two JSON shapes the scripts emit, so
   sections 3–5 consume the report identically. A surface a subagent could not pull degrades the
   way the scripts degrade: empty list plus a named entry in `partial` / on the sources line —
   never a hole.

## Field map — `pull-org-github.sh` equivalent

| Script field | MCP equivalent |
|---|---|
| `repos[]` — `name`, `archived`, `pushed_at`, `default_branch` | List-repositories capability for the org; read the same four attributes. |
| `prs[]` — `repo`, `number`, `title`, `url`, `draft`, `author` | Open-PR search or list across the active repos (org-wide search if available, else per-repo inside the fan-out). |
| `prs[].idle_days`, `prs[].age_days` | Not served by any tool — compute `floor((now - updated_at) / 86400)` and the same from `created_at`. Whole days, floored, so every consumer ranks on the same clock. |
| `issues[]` — `repo`, `number`, `title`, `url`, `labels`, `idle_days` | Open-issue search or list, same scoping; flatten `labels` to names; compute `idle_days` as above. |
| `partial[]` | Any surface whose pull failed: emit the empty list and name the surface, exactly as the script does. |

Carry the script's two load-bearing invariants (its header explains both):

- **Archived repos stay in `repos` (flagged) and stay OUT of `prs` and `issues`.** Search happily
  returns hits from archived repos — at Sassy Dog that silently adds dozens of dead lupita issues
  and skews the ranking. Filter both lists against the roster.
- **Precompute the day counts once at assembly.** Raw timestamps left for section 4 to interpret
  produce a different clock per run.

## Field map — `pull-repo-signals.sh` equivalent

Per active repo, from the workflow-runs capability: sample the most recent ~25 runs (the script's
`RUN_LIMIT`), then reduce over **completed** runs only.

| Script field | MCP equivalent |
|---|---|
| `runs_sampled`, `failures`, `failure_rate` | Count completed runs and completed-with-`failure`; rate is failures / sampled × 100, rounded; null when nothing was sampled. |
| `default_branch_ci` | Conclusion of the MOST RECENT completed run on the default branch whose event is `push` or `merge_group`. Never widen to `schedule` — the push/schedule split is load-bearing (section 2B). |
| `scheduled_failing[]` | Group `schedule`-event runs by workflow; a workflow is listed only if its most recent completed run failed. A stale failure already followed by green is not an active fire. |
| `last_failure` | Most recent completed run with conclusion `failure`: workflow, branch, event, url, created_at; null when none. |
| `dependabot` | **No MCP equivalent — do not populate. See below.** |

## Unreachable: the Dependabot surface

There is no MCP tool for the Dependabot alerts endpoint, so everything derived from it goes dark:
`enabled`, `open`, `high_crit`, `oldest_high_crit_age_days`, `vulnerable_packages`, `open_fix_prs`
(the per-package `addresses` match needs the alert list), and `unremediated_packages`. That takes
out section 4's remediation-state table and the two Dependabot blind-spot rows in section 2C.

Render it exactly as `skipped — no gh CLI (Dependabot API unreachable)`, named on the report's
sources line per sections 1 and 5:

```markdown
_Sources: Sentry · Sentry crons · GitHub (MCP fallback) · Dependabot skipped — no gh CLI (Dependabot API unreachable)_
```

Do NOT approximate it. The PR capability can see Dependabot's open fix PRs, which makes a partial
reconstruction tempting — but without the alert list there is no `vulnerable_packages` to match
against, so remediation cannot be judged per package, and section 4 ranks Dependabot exposure by
remediation state, never by count. A half-surface would quietly re-create the exact
any-PR-counts-as-remediation failure the script's header documents. A named skip is the honest
answer.
