# The qualifying gate: Sentry hit → GitHub issue candidate

Default gate, tuned in production across Sassy Dog repos. A project skill may override thresholds in its project-specific section; absent that, these apply. A Sentry issue qualifies ONLY when **ALL** of:

1. `status == "unresolved"` — never escalate `ignored` (a human chose to ignore it).
2. `lastSeen ≤ 7 days` — older fingerprints that haven't re-fired aren't actionable.
3. Severity threshold: `userCount ≥ 2` **OR** `events ≥ 5` **OR** (`level == "error"` AND `events ≥ 2`).
4. No existing GitHub peer: no `sentry-source: <SHORT_ID>` marker in any issue, open or closed (`gh issue list --search '"sentry-source: <SHORT_ID>" in:body' --state all`). The filing script re-checks this internally; checking here too keeps the preview honest.
5. Not parked: the SHORT_ID does not appear in any `*_park.md` / parked-override memory entry. Parked = a permanent human override; respect it without re-litigating.
6. **Not exclusively non-production.** An issue whose events all land in a non-production environment (`e2e`, `test`, `ci`, `dev`, `local`, `preview` — match case-insensitively, and treat anything not recognizably production as *unknown*, not as non-production) is tagged `skip-nonprod`. Any single event in a production environment (`production`, `prod`, `prd`) keeps it in the gate.

Issues failing the gate are tagged in working data as `skip-noise` / `skip-stale` / `skip-parked` / `skip-nonprod` / `already-linked` and reported as such — they never reach the filing step.

## Why rule 6 exists

Rule 3 counts `userCount`, and **a CI environment manufactures users**. Every Maestro gate run is a fresh simulator install, which Sentry counts as a new user, so an ambient 2-4s main-thread stall on a loaded CI host accumulates "users impacted" at the rate the pipeline runs — not at the rate anything is wrong.

On 2026-08-03 that put `QRNINJA-MOBILE-5/-6` (19 events, **100% `environment:e2e`**, every one from `build_type: simulator`) at the top of a portfolio sweep as a customer-facing P1, framed as shipping with an App Store submission. qr-ninja#751 had already diagnosed and fixed the source a day earlier — it disabled `enableAppHangTracking` outside production and its commit message named this exact failure: *"17 phantom 'users impacted' made QRNINJA-MOBILE-5/-6 rank as a production fire in portfolio triage."* The gate re-made the mistake the fix was written to prevent, because the gate could not see `environment` at all.

Two properties this rule must keep:

- **Never silently drop.** `skip-nonprod` is reported like every other skip. A flood of e2e hangs is real signal about the *test environment*; it is just not a production fire, and hiding it would trade one blindness for another.
- **Unknown is not non-production.** Environment names vary across projects (this org uses `prd` in some, `production` in others). Only tag `skip-nonprod` on a positive match against the non-production list — an unrecognized name stays in the gate, so a new production environment name can never be silently suppressed.

## Burst rail

The gate is the only ceiling, so a pathologically noisy deploy (many distinct over-threshold fingerprints at once) could justify a mass-file. **If more than 5 issues would pass the gate in one run, STOP: summarize the candidates and ask before filing any.** A burst that size usually has one root cause — one umbrella issue beats N auto-filed duplicates.

## Dry-run first

Always preview with the filing script's `--dry-run` (returns `would-file` without writing) after any gate change, and as the standard preview step before confirming a batch.

## Hard prohibitions

- **Never mutate Sentry**: no resolve, no ignore, no assignment. Triage reads; humans resolve.
- **Never edit or comment on existing GitHub issues from this gate** — except the signal-escalation comment pattern defined in github-issues' `dedupe-and-file.md`, which is its own explicit step.
- Escalation goes through `ai-agent-skills:github-issues`' `file-or-link-issue.sh` — never raw `gh issue create` (that's how markers and idempotency drift).
