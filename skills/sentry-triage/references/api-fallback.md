# API fallback (no Sentry MCP connected)

Prefer the connected Sentry MCP server's tools. When they're absent (headless runs, MCP not installed), fall back to the REST API or sentry-cli.

## REST API

Auth: `SENTRY_AUTH_TOKEN` (org-scoped, `project:read` + `event:read`). Typically in Doppler; surface a missing-token error rather than prompting for a paste.

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

## sentry-cli

`sentry-cli` is geared to releases/sourcemaps, not issue search — the REST API is the better fallback for triage. Use sentry-cli only if it's already installed and the task is release-centric (`sentry-cli releases list`).

## MCP tool naming caveat

MCP tool IDs vary by installation (different server prefixes per host app). Never hardcode a `mcp__...` tool ID in a skill or script — describe the tools by capability ("the connected Sentry MCP server's find_projects / search_issues tools") and let the session resolve them.
