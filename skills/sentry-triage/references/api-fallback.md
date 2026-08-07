# API fallback (no Sentry MCP connected)

Prefer the connected Sentry MCP server's tools. When they're absent (headless runs, MCP not installed), fall back to the REST API or sentry-cli.

## REST API

Auth: `SENTRY_AUTH_TOKEN` (org-scoped, `project:read` + `event:read`, **plus `org:read` or `alerts:read` for the cron-monitors endpoint below** — a token with only the first two authenticates fine but cannot list monitors, a silent partial failure). Typically in Doppler; surface a missing-token error rather than prompting for a paste.

```bash
# List projects (resolve slugs)
curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://sentry.io/api/0/organizations/<ORG>/projects/" \
  | jq '.[] | {slug, platform}'

# Triage pull: not-resolved issues, last 14 days, sorted by frequency
curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://sentry.io/api/0/projects/<ORG>/<PROJECT>/issues/?query=%21is%3Aresolved&statsPeriod=14d&sort=freq" \
  | jq '.[] | {shortId, title, count, userCount, lastSeen, level, culprit, permalink, status}'
```

Notes:

- `!is:resolved` must be URL-encoded (`%21is%3Aresolved`).
- Same no-OR/AND restriction as the UI/MCP — HTTP 400 on boolean operators.
- Pagination via the `Link` header; the first page (25) is almost always enough for triage — say so if you truncate.

## Cron monitors

Per-environment cron state comes from the org monitors endpoint. Requires `org:read` (or `alerts:read`) — see the scope warning above.

```bash
# List cron monitors with per-environment state (project=-1 = all accessible projects)
curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://sentry.io/api/0/organizations/<ORG>/monitors/?project=-1" \
  | jq '.[] | {slug, name, project: .project.slug, isMuted,
      environments: [.environments[] | {name, status, lastCheckIn, nextCheckIn}]}'
```

Response shape (verified against a live call, 2026-08-07): each monitor carries `id`, `slug`, `name`, `status`, `isMuted`, `owner`, `config`, `project` (an object — use `.project.slug`), and `environments[]`; each environment carries `name`, `status`, `lastCheckIn`, `nextCheckIn`, `nextCheckInLatest`, and `activeIncident`.

Notes:

- **Health is per-environment.** Rank on `environments[].status` (`ok` / `error`), not the monitor-level `status` — that field is lifecycle (`active` / `disabled`), and a lifecycle-`active` monitor can still be failing in every environment.
- Optional query params: `environment` (repeatable), `owner`.
- Pagination via the `Link` header's `rel="next"` cursor (the `cursor` query param, page size 100) — same mechanism as the issues recipe; one page covers most orgs, say so if you truncate.

## sentry-cli

`sentry-cli` is geared to releases/sourcemaps, not issue search — the REST API is the better fallback for triage. Use sentry-cli only if it's already installed and the task is release-centric (`sentry-cli releases list`).

## MCP tool naming caveat

MCP tool IDs vary by installation (different server prefixes per host app). Never hardcode a `mcp__...` tool ID in a skill or script — describe the tools by capability ("the connected Sentry MCP server's find_projects / search_issues tools") and let the session resolve them.
