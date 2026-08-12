# Scheduled routines — checking load state out of band

Two scheduled cloud routines invoke plugin skills from this repo. Each carries the skill-load
fallback clause required by [`CLAUDE.md`](../CLAUDE.md) so that a plugin-loading gap produces a
degraded run rather than a silent no-op (#97, #98).

| Routine | Invokes | Fallback body |
| --- | --- | --- |
| `daily-fire-watch` | `sassy-dog:whats-on-fire` | `skills/whats-on-fire/SKILL.md` |
| `weekly-portfolio-currency` | `sassy-dog:whats-behind` | `skills/whats-behind/SKILL.md` |

Routines are keyed by name here rather than by `trig_…` id. Two reasons: this repo is public, and
ids are **mutable** — the routines API has no delete, so replacing a routine mints a new id and any
id committed here goes quietly wrong. Resolve the current id by name when you need it, from the
Routines list in claude.ai or the triggers API.

The routine prompts themselves are untracked config living behind the routines API, outside this
repo. This doc covers the one thing that *is* durable about a run: its log.

## The precedence rule

**Where the report and the run log disagree, the run log wins.**

There are two signals for whether a routine run loaded the plugin, and they are not equal:

- **The `Load:` field in the delivered report** (`plugin` / `fallback (degraded)`) is the run
  reporting on itself. It is cheap, it is visible in the artifact people actually read, and it is
  right almost always — but a run that is wrong about its own state will render it wrong, and a run
  under output pressure can drop it. Treat it as a convenience, never as proof.
- **The run log** is written by the harness, not by the model. It records what the Skill tool
  actually did. This is the authoritative signal, and the only one that survives a run being wrong
  about itself.

This is not a hypothetical ordering. On 2026-08-11 the weekly run
(`cse_01155VeBrfvMevpqUUuJLSSV`) delivered a complete, accurate-looking report with **no** degraded
note, while its own log showed the skill had failed to load. "No degraded note" was then briefly
taken as evidence that the plugin had loaded, which is exactly backwards — see #144 and #146.

**So: never date a regression, close a loading issue, or claim a fix landed from the report alone.
Read the log.**

## The out-of-band check

### The signature

A cloud session that could not resolve the plugin skill emits a `Skill` tool call that errors. The
literal pair, from run `cse_01155VeBrfvMevpqUUuJLSSV` (weekly, 2026-08-11):

```text
[15:03:03] tool_use Skill: {"skill":"sassy-dog:whats-behind"}
[15:03:03] tool_result ERROR: <tool_use_error>Unknown skill: sassy-dog:whats-behind</tool_use_error>
```

The load-bearing string is `Unknown skill: sassy-dog:` followed by the skill name. It is emitted by
the harness as a tool error, so it appears in the log whether or not the model ever mentions it.

### Where it appears

Near the **start** of the run, at the first `Skill` tool call — the routine prompts invoke the skill
before doing any work, so the `tool_use` / `tool_result` pair sits within the first few entries,
right after the prompt. A degraded run then continues: the fallback clause sends it to read
`skills/<name>/SKILL.md` with the Read tool, and every entry after that looks like a normal run.
That is why the tail of a degraded log is indistinguishable from a healthy one, and why the check
has to target the first Skill call rather than skimming for anything unusual.

### The recipe

1. Resolve the routine's current trigger id by name (table above), then get the run's session id
   (`cse_…`) from that routine's run history.
2. Open that session's log and search it for the literal `Unknown skill: sassy-dog:`. With the log
   saved to a file, that is `grep -n 'Unknown skill: sassy-dog:' <logfile>`.
3. Confirm the *first* `Skill` tool call in the run either succeeded or produced that error — a hit
   anywhere is conclusive for degraded, but a clean grep is only meaningful over the whole log.

### Reading the result

| Log | Report `Load:` | Verdict |
| --- | --- | --- |
| `Unknown skill: sassy-dog:<name>` present | `fallback (degraded)` | Degraded, correctly reported. |
| `Unknown skill: sassy-dog:<name>` present | `plugin`, or field absent | **Degraded.** The log wins; the report is wrong about itself — this is the 2026-08-11 failure. |
| Skill call succeeded, no such error | `plugin` | Loaded natively. |
| Skill call succeeded, no such error | `fallback (degraded)` | Loaded; the report is wrong. Log wins, but investigate — a run misreporting in this direction is still a bug. |
| Log unavailable | anything | **Unknown, not healthy.** Say so; do not promote the report to evidence. |

A missing log is not a passing check. The routine that produced no report at all in #97 is the
reminder: absence of a signal and a healthy signal are different states, and only one of them is
good news.

## Ruled out: the published artifact is not the fault (#162)

When a load gap turns up, the first instinct is to suspect the plugin — a bad manifest, a rename that
broke a path, a skill the publisher would refuse. **That was tested directly on 2026-08-11 and it is
not the cause.** Do not re-run this bisect; re-run the *install*, below, only if the manifest has
changed since.

Both sides of the suspected regression boundary install cleanly, tested through the same harness with
each tree exported by `git archive` into a throwaway
`CLAUDE_CONFIG_DIR` sandbox:

| Version | Commit | `marketplace add` | `install` | Inventory |
| --- | --- | --- | --- | --- |
| `2026.8.33` (pre-rename) | `15d60ee` | exit 0 | exit 0 | 20 skills, 9 agents |
| `2026.8.41` (post-rename) | `b5e0681` | exit 0 | exit 0 | 21 skills, 9 agents |

A clean `claude plugin marketplace add Sassy-Dog/sassydog-skills` + `claude plugin install` against
the real GitHub marketplace at `main` also succeeds, and resolves the full inventory — including both
skills the routines invoke. The 20→21 delta is exactly epic #120 (`refresh-*` → `setup-*`, plus
`setup-repo`), not a loss.

**The local cache stalling at `2026.8.33` is a coincidence, not a signal.** There is no marketplace
auto-refresh — `lastUpdated` across registered marketplaces is scattered over months, each stamp a
manual action. `sassydog-skills` last refreshed 2026-08-09, a day *before* the rename commits landed,
so it never saw a post-rename version to reject. It is stale because nobody ran
`claude plugin update`.

So a degraded run pointed at **cloud-side resolution**, not at the artifact. That line of inquiry is
now **closed** — see [#175](https://github.com/Sassy-Dog/sassydog-skills/issues/175) for the full
ruled-out table. The short version, because it changes how you read every degraded run below:

- **There is no supported way to load a plugin skill in a routine session.** The routine-scoped
  `enabled_plugins` / `extra_marketplaces` fields accept correctly-typed API writes, return HTTP 200,
  bump `updated_at`, and persist nothing — at `create` as well as `update`. The routine edit UI has no
  plugins control at all. An account-level plugin install reaches interactive claude.ai sessions only:
  two verification runs, 20s and 5min after a confirmed install, were both degraded.
- **A degraded run is therefore the expected state, not an incident.** Do not open an issue for one.
  The fallback clause is permanent contract, and `Load: fallback (degraded)` on every run is correct
  output. What still deserves investigation is a run that produces *no* report, or one whose `Load:`
  field disagrees with its log.
- **Repo visibility was a real cause, of a different problem.** While this repo was `INTERNAL` the
  claude.ai account marketplace could not sync it at all (`Marketplace sync failed`), despite the
  `claude` GitHub App being installed org-wide for **All repositories** and an active SAML session for
  `Sassy-Dog`. Flipping the repo to `PUBLIC` fixed the sync on the first attempt. Neither SSO nor app
  scope was ever implicated — do not re-test those.

## What the in-report field is for

The `Load:` field is not redundant with this check — it covers the case nobody is investigating.
Most runs are read by a human glancing at Slack who will never open a session log, and for them a
degraded run needs to announce itself on the line they already read. The out-of-band check covers
the case where load state is being used as *evidence*: dating a regression, verifying a fix,
closing an issue. Use the field to notice; use the log to conclude.

Both report skills render the field on their header line:

- `skills/whats-on-fire/SKILL.md` §5 — `_Load: <plugin|fallback (degraded)> · Sources: …_`
- `skills/whats-behind/SKILL.md` §5 — `_Load: <plugin|fallback (degraded)> · Scanned: …_`

When either skill's output format changes, keep the field on the header line and keep the
precedence rule stated in both places — this doc and `CLAUDE.md`. Dropping it from one leaves the
other reading like the whole contract.
