# Sentry query syntax — the working subset

## The one query that matters

```
!is:resolved
```

A single negated-status query captures both `is:unresolved` AND `is:ignored`, because Sentry issue status is exclusive (exactly one of resolved/unresolved/ignored). This is the canonical triage pull: everything not explicitly resolved.

## No boolean operators

**Sentry issue search does NOT support `OR`/`AND`** — `is:unresolved OR is:ignored` returns HTTP 400, not a parse warning. Use negation (`!is:`, `!level:`) and multiple space-separated terms (implicit AND) instead.

Useful refinements (combine by space):

| Term | Meaning |
|---|---|
| `!is:resolved` | unresolved + ignored |
| `level:error` | errors only |
| `firstSeen:-7d` | new fingerprints this week |
| `lastSeen:-24h` | actively firing |
| `release:<version>` | scoped to a release |

## Fields to pull per issue

`shortId, title, count, userCount, lastSeen, firstSeen, level, culprit, permalink, status`

- `shortId` (e.g. `QRNINJA-WEB-3`) is the stable fingerprint ID — it's the dedupe marker key for GitHub filing.
- `count` = events; `userCount` = distinct users. **Neither goes to the gate as returned.** What
  search hands back is transport-dependent — windowed on the MCP path, lifetime on REST, under
  identical labels — so gate rule 0 re-fetches both per issue before rule 3 reads them. The
  count-semantics table in `api-fallback.md` is the authority.
- `firstSeen` from an MCP search is windowed too, and it is the field most likely to be
  believed: a 57-day-old fingerprint came back as *2 days ago*. Re-fetch it with the counts.
  This does not impugn the `firstSeen:-7d` **query term** above — filtering server-side and
  reading the returned field are different operations, and only the second is known bad.
- `culprit` is the best fuzzy-merge key against TestFlight crash stacks (same crash often appears in both surfaces — merge before reporting, don't double-count).

## Status semantics for escalation

- Only `unresolved` ever escalates to a GitHub issue.
- `ignored` is reported (it's in the `!is:resolved` pull) but **never escalated** — ignoring was a human decision.
- Don't hunt for phantom projects: a platform that inits Sentry (e.g. a worker sharing the web DSN) doesn't necessarily appear as its own project. Note it; don't error on it.
