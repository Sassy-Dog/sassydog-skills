# The qualifying gate: Sentry hit → GitHub issue candidate

Default gate, tuned in production across Sassy Dog repos. A project skill may override thresholds in its project-specific section; absent that, these apply. A Sentry issue qualifies ONLY when **ALL** of:

0. **Counts confirmed as lifetime.** `events` and `userCount` used by rule 3 are the issue's true `Occurrences` / `Users Impacted`, fetched per issue via the resource-fetch capability — never the figures returned by issue search. The same fetch supplies `firstSeen`, which search rescales identically. An issue whose counts could not be confirmed is tagged `skip-unconfirmed` and cannot qualify.
1. `status == "unresolved"` — never escalate `ignored` (a human chose to ignore it).
2. `lastSeen ≤ 7 days` — older fingerprints that haven't re-fired aren't actionable.
3. Severity threshold: `userCount ≥ 2` **OR** `events ≥ 5` **OR** (`level == "error"` AND `events ≥ 2`).
4. No existing GitHub peer: no `sentry-source: <SHORT_ID>` marker in any issue, open or closed (`gh issue list --search '"sentry-source: <SHORT_ID>" in:body' --state all`). The filing script re-checks this internally; checking here too keeps the preview honest.
5. Not parked: the SHORT_ID does not appear in any `*_park.md` / parked-override memory entry. Parked = a permanent human override; respect it without re-litigating.
6. **Not exclusively non-production.** An issue whose events all land in a non-production environment (`e2e`, `test`, `ci`, `dev`, `local`, `preview` — match case-insensitively, and treat anything not recognizably production as *unknown*, not as non-production) is tagged `skip-nonprod`. Any single event in a production environment (`production`, `prod`, `prd`) keeps it in the gate.

**Evaluation order is part of the gate, not an optimization.** Apply the count-independent rules (1, 2, 5, 6) first, confirm counts on the survivors, then apply rules 0 and 3. Confirming only the issues that already look severe is the defect wearing a fix: the search count is what under-reports, so any pre-filter derived from it re-creates the bug one step earlier.

Issues failing the gate are tagged in working data as `skip-noise` / `skip-stale` / `skip-parked` / `skip-nonprod` / `skip-unconfirmed` / `already-linked` and reported as such — they never reach the filing step.

## Why rule 0 exists

Rule 3 is the only rule that reads a number, and **the number it reads is transport-dependent**. The MCP's `search_issues` renders Events and Users scoped to its `period` argument; the REST `/issues/` endpoint returns lifetime `count` / `userCount` regardless of `statsPeriod`. Both surface under the same names, and neither marks which it gave you.

Measured on `Sassy-Dog/velovate`, 2026-08-20 (issue #218):

| Issue | via `search_issues` | true lifetime | First seen |
|---|---|---|---|
| `VELOVATE-WORKERS-2` | 1 event / 1 user | **30 occurrences / 3 users** | 2026-06-25 |
| `VELOVATE-WEB-K` | 1 event / 1 user | 3 occurrences / 1 user | 2026-06-15 |

The 30d pull also returned 1 event, so this is not "the window was too short" — widening `period` does not fix it.

**Re-verified live 2026-08-21, and `firstSeen` is rescaled too.** Search reported `VELOVATE-WORKERS-2` as first seen *2 days ago*; its true first-seen is 2026-06-25, 57 days earlier. That is the same defect wearing a different field, and it is the more persuasive one: a 57-day-old recurring fault presented as new invites exactly the wrong triage call — blame the latest deploy. Confirm `firstSeen` from the same fetch that confirms the counts.

The gate outcome inverts on this one issue. True numbers: `environment: prd`, 3 users, so rule 6 keeps it and rule 3 passes on `userCount ≥ 2` — it qualifies. Windowed numbers: 1 event, 1 user, `level: warning`, so every clause of rule 3 fails and it never reaches the report. Nothing in either rendering marks which one you are looking at.

That morning an interactive `survey-work` run on velovate reported *"nothing clears the Sentry gate — max 4 events"* and put the whole surface on the clean line, while the same day's `daily-fire-watch` — REST-based, because the routine container has no Sentry MCP — correctly ranked `VELOVATE-WORKERS-2` a P0. **The scheduled run that gets reviewed daily was accidentally correct and the ad-hoc run a human trusts in the moment was wrong**, which is why this went unnoticed: the defect cannot manifest in the edition anyone audits.

The REST evidence is what makes the diagnosis specific rather than a guess about windows: that pull carries `statsPeriod=14d` and still returned 30 occurrences for a fingerprint first seen 2026-06-25, well outside 14 days. So the MCP is not applying a window the REST path also applies — it is *rescaling counts* on results it did return, which no parameter on either side announces.

Two properties this rule must keep:

- **`skip-unconfirmed` is reported, never dropped.** A count this skill declined to trust is not the same as a count below threshold, and collapsing the two hides the failure exactly where rule 6's `skip-nonprod` would have hidden it.
- **Unconfirmed can never qualify.** Failing open — gating on the windowed number while noting it is windowed — reinstates the 30× undercount and adds a footnote to it.

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
- Escalation goes through `sassy-dog:github-issues`' `file-or-link-issue.sh` — never raw `gh issue create` (that's how markers and idempotency drift).
