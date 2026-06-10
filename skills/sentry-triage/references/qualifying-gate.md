# The qualifying gate: Sentry hit → GitHub issue candidate

Default gate, tuned in production across Sassy Dog repos. A project skill may override thresholds in its project-specific section; absent that, these apply. A Sentry issue qualifies ONLY when **ALL** of:

1. `status == "unresolved"` — never escalate `ignored` (a human chose to ignore it).
2. `lastSeen ≤ 7 days` — older fingerprints that haven't re-fired aren't actionable.
3. Severity threshold: `userCount ≥ 2` **OR** `events ≥ 5` **OR** (`level == "error"` AND `events ≥ 2`).
4. No existing GitHub peer: no `sentry-source: <SHORT_ID>` marker in any issue, open or closed (`gh issue list --search '"sentry-source: <SHORT_ID>" in:body' --state all`). The filing script re-checks this internally; checking here too keeps the preview honest.
5. Not parked: the SHORT_ID does not appear in any `*_park.md` / parked-override memory entry. Parked = a permanent human override; respect it without re-litigating.

Issues failing the gate are tagged in working data as `skip-noise` / `skip-stale` / `skip-parked` / `already-linked` and reported as such — they never reach the filing step.

## Burst rail

The gate is the only ceiling, so a pathologically noisy deploy (many distinct over-threshold fingerprints at once) could justify a mass-file. **If more than 5 issues would pass the gate in one run, STOP: summarize the candidates and ask before filing any.** A burst that size usually has one root cause — one umbrella issue beats N auto-filed duplicates.

## Dry-run first

Always preview with the filing script's `--dry-run` (returns `would-file` without writing) after any gate change, and as the standard preview step before confirming a batch.

## Hard prohibitions

- **Never mutate Sentry**: no resolve, no ignore, no assignment. Triage reads; humans resolve.
- **Never edit or comment on existing GitHub issues from this gate** — except the signal-escalation comment pattern defined in github-issues' `dedupe-and-file.md`, which is its own explicit step.
- Escalation goes through `ai-agent-skills:github-issues`' `file-or-link-issue.sh` — never raw `gh issue create` (that's how markers and idempotency drift).
