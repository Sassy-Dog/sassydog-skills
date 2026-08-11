# Scheduled routines — checking load state out of band

Two scheduled cloud routines invoke plugin skills from this repo. Each carries the skill-load
fallback clause required by [`CLAUDE.md`](../CLAUDE.md) so that a plugin-loading gap produces a
degraded run rather than a silent no-op (#97, #98).

| Routine | Trigger ID | Invokes | Fallback body |
| --- | --- | --- | --- |
| daily fire-watch | `trig_01BZd6qJYpoJyKWfzc9MCuyq` | `sassy-dog:whats-on-fire` | `skills/whats-on-fire/SKILL.md` |
| weekly portfolio currency | `trig_01ABuVDmbF216gCSwcNQczpF` | `sassy-dog:whats-behind` | `skills/whats-behind/SKILL.md` |

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

1. Get the run's session id (`cse_…`) from the routine's run history, keyed by trigger ID above.
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
