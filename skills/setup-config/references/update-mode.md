# Update mode and adopt mode

Migrate mode has its own doc: `references/migrate-mode.md`. This one covers the two modes that
operate on a repo which is **already** on config, or has never been generated at all.

## File contract for config

Every `.claude/sassy-dog/<skill>.md` carries, in order:

1. **YAML frontmatter starting on line 1.** Nothing may precede the opening `---`.
2. **`##` prose sections** at the slots the config contract defines.

The split is the whole design:

| Part | Owner | On refresh |
| --- | --- | --- |
| Frontmatter | the generator | **regenerated** from live detection |
| `##` sections | the user | **carried across verbatim** |

Prose is never rewritten, reformatted, or summarised by a refresh. If it looks wrong, say so; do
not fix it.

The eight prose slots: `extra-surfaces`, `scoring-overrides` (survey-work); `extra-rubric`
(groom-backlog); `subagent-rules` (take-it); `extra-sequencing` (dispatch-ready); `extra-gates`
(send-it); `extra-cleanup` (tidy-repo); and `extra-guardrails`, which appears in four files. An
earlier version of this list
omitted `extra-rubric` and `extra-sequencing` while the templates emitted them — a migration written
from the short list silently drops two slots.

## Update mode (config already present)

1. **Rename step first — pre-rename config filenames.** Four skills were renamed after the config
   era began (the legacy → current map is in `migrate-mode.md` Step 3): a repo may carry
   `.claude/sassy-dog/plate-it.md`, `groom-it.md`, `drain-it.md`, or `clean-it.md`. For each such
   file whose current-name counterpart (`survey-work.md`, `groom-backlog.md`,
   `dispatch-ready.md`, `tidy-repo.md`) does **not** exist: `git mv` it to the current name, prose
   carried verbatim — this is a rename, not a regeneration. If BOTH names exist, stop and surface
   it; never merge or pick silently. Mention every rename in the preview.
2. Re-run Phase 1 detection.
3. **Re-verify every fact against live state.** An existing config value is evidence of what was
   true when it was written, not of what is true now. `merge_queue` especially: read it from the
   `mergeQueue(branch:)` GraphQL field, never from the file you are about to overwrite.
4. Regenerate frontmatter; carry every `##` section across untouched.
5. Diff per file, showing changed facts as old → new with how each was verified.
6. Apply on approval, per file.

A fact that cannot be verified is surfaced to the user, never carried forward silently.

**A `none` is an answer already given — carry it forward, never re-ask.** This covers exactly three
values: `testflight: none`, `posthog: none`, and `mobile: none`. Each records a human's confirmation
that this product has no such surface (`config-contract.md`, "The one exception"). What step 3
cannot re-derive is the **confirmation**, and that is the precise claim — detection reads this tree,
so it can find evidence a surface is *present*, and it can never produce evidence that somebody
looked and concluded it is absent. A quiet tree is not an answer. So step 3's *re-verify every fact
against live state* does not reach these three values; the carve-out is scoped to them and to nothing
else in the frontmatter. Re-asking on every refresh reopens exactly what the form closed: a finished
check made indistinguishable from one that never ran.

**`sentry: none` is NOT in that carve-out — it is re-derived on every refresh, as it always was.**
The four `none` values look interchangeable and are not, and this is the second place that matters
(the first is which of them an interview writes). `references/detection.md` writes `sentry: none`
when the culprit check fails **or could not run at all** — no MCP server connected, no recent issues
to sample. Those are conditions of the *session*, not facts about the repo. Freezing the value would
let one unlucky `setup-config` run permanently retire the highest-signal surface on the plate, and
there would be no way back: the only evidence that could contradict it is the culprit check that the
carve-out just excluded. So re-run it, exactly as step 3 says, and treat a newly verified project as
the ordinary old → new fact it is.

**Do not read that as "detection says nothing about these keys" — it says plenty, and the tree is
what you check against.** `scripts/detect-capabilities.sh` derives `posthog` outright (a tracked-tree
grep) and `testflight_bundle_id` when an `ios/` path or an `app.json` is tracked. There is no
"has a mobile target" field at all, so a `mobile: none` is checked against the tree directly — the
same `ios/` / `app.json` test, plus `pubspec.yaml` and `android/`. Do the grep; do not infer from a
missing field that there was nothing to look for.

**Positive evidence against a `none` is a stop and surface, never a rewrite.** If the tree now
carries the surface the config says is absent — an iOS target under a `mobile: none`, a PostHog SDK
under a `posthog: none` — report both sides and let the user decide, exactly as a `merge_queue`
disagreement is handled. Never silently rewrite a `none` into a block, and never silently keep one
the tree contradicts. Note `posthog`'s derivation is a bare substring grep, so a repo that merely
*documents* PostHog trips it; say which file matched, so the user can dismiss it.

**An ABSENT one of these keys is the rollout path, and it is the half a refresh must not skip.**
Every consumer repo was configured before this form existed, so on the first refresh after it lands
each of the three keys is simply missing — and missing means "nobody has checked", which is what
renders the blind-spot row this form exists to clear. A key carrying `posthog: false` counts as
missing for this purpose: it is a detection result the contract does not define as a config value, so
regeneration drops it, and an absent-only rule would never ask about it. A refresh that only carries existing values
forward therefore changes nothing anywhere. So: **whenever one of `testflight:`, `posthog:` or
`mobile:` is absent, put interview §2c to the user for that key** and record the answer, naming it in
the preview like any other addition. Do not gate that on the tree being quiet — the case this repo's
own config demonstrates is a detection *hit* the user dismisses (`posthog`'s bare grep matches a repo
that merely documents PostHog), and gating on silence skips exactly it. "Not sure" is a valid answer
and leaves the key absent. This mirrors `review_site:`, which is likewise proposed as an addition
when a config predates it.

**`stacked_prs` is policy, not a detected fact — never add it on a refresh.** Absent means the repo
has not opted in, which is the correct state for every repo that has not asked for it, and an update
must leave it absent. Carry an existing block across verbatim; do not "helpfully" add one because
`stack-probe.sh` reports the repo is now enabled. Enablement is availability; the block is consent.
Raise it as a suggestion if the user asks what is new, and route them through interview §3c.

**Migrate mode inherits all of this, and needs it most.** `references/migrate-mode.md` extracts
config from generated skills, and a legacy generated skill has no way to express a `none` — so a
migrated config arrives with all three keys absent, every time. Run §2c for all three at its
interview step. That instruction also lives in `migrate-mode.md` itself, because this file's own
opening says migrate mode is covered there, and a rule stated only here is a rule that path never
reads.

## Adopt mode (no marker — legacy hand-written skills)

For repos carrying legacy prefixed skills such as `<prefix>-plate-it`, `<prefix>-get-it`,
`<prefix>-send-it`, with no `generated-by:` marker. Never silently overwrite or delete one.

1. Identify them: `.claude/skills/*plate-it*`, `*get-it*`, `*take-it*`, `*send-it*`, `*clean-it*`
   with no marker anywhere in the file. The prefixed `<repo>-clean-it` skills are the most common
   straggler.
2. Run create mode's detect + interview, pre-answered from what the legacy files reveal — write
   gates, merge policy, and pre-flight commands are usually stated in them. Re-verify each against
   live state regardless; a legacy file is the least trustworthy source of a current fact.
3. Render config.
4. **Side-by-side review per skill.** List every hand-written section with no equivalent in the
   config — repo-specific traps, war stories, special recipes. For each the user picks: fold into a
   `##` prose slot / promote upstream as plugin feedback / drop.
5. On approval, write config and delete the legacy directories. Then remind the user the rename
   frees the old names: anything referencing `<prefix>-send-it` — hooks, docs, other skills — needs
   updating. Grep the repo for the old names before finishing.
6. The legacy skills' `scripts/` are superseded by the plugin capability skills' scripts; delete
   them with the directory unless a script is project-unique, in which case it moves to a path the
   prose references.

## Recognising prior producers

When identifying a generated skill for migration, match the `generated-by:` marker **anywhere in
the file** and accept **every** producer name:

- `refresh-skills` — plugin 2026.7.22 until this skill was renamed `setup-config`
- `refresh-sassydog-skills` — plugin 0.9.0 through 2026.7.21
- `create-dev-workflows` — plugin ≤ 0.8.1

This list is frozen history and takes no new entries. `setup-config` writes only
`.claude/sassy-dog/*.md`, which carries no `generated-by:` marker, so there is no `setup-config`
marker for this matcher to ever see.

Older renders placed the marker on line 1, a layout the loader cannot parse, and hand-fixes moved
it. A repo whose marker is not recognised falls through to adopt or create mode, and its extracted
config is silently lost — so this matcher is load-bearing, not a nicety.

## Naming guard

A **personal** skill (`~/.claude/skills/<name>`) hard-shadows a project skill of the same name.
Plugin skills are namespaced and cannot conflict with either — which is precisely why the workflow
skills now live in the plugin rather than being generated per repo.

Before writing, check for a personal skill named `survey-work`, `groom-backlog`, `take-it`,
`dispatch-ready`, `send-it`, `tidy-repo` — or any of the legacy names `plate-it`, `groom-it`,
`fill-it`, `drain-it`, `clean-it`. One will not shadow the namespaced plugin skill, but it will
shadow any project skill of that name and is almost certainly stale — surface it rather than
working around it.
