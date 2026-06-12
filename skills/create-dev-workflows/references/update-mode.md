# Phase 3b — update mode & adopt mode

## File contract for generated skills

Every generated SKILL.md carries, in order:

1. **YAML frontmatter starting on line 1.** The opening `---` MUST be the first line of the file —
   Claude Code's skill loader only parses frontmatter that starts on line 1. Nothing (not even an
   HTML comment) may precede it.
2. **Generated-by marker** on the first non-blank line after the closing `---` of the frontmatter,
   with a blank line on each side:
   `<!-- generated-by: ai-agent-skills:create-dev-workflows | template: <plate-it|fill-it|take-it|drain-it|send-it> | template-version: N -->`
3. **Project-specific fences** at the slots the template defines:
   `<!-- BEGIN PROJECT-SPECIFIC: <slot> --> ... <!-- END PROJECT-SPECIFIC -->`
   Slots: `extra-surfaces`, `scoring-overrides`, `subagent-rules`, `extra-gates`, `extra-guardrails`. Fence markers stay in the generated file forever — they're the splice anchors.

Everything outside the fences is **template-owned**: hand-edits there are legal but will be flagged (and may be replaced) on the next update. Durable project customization belongs inside a fence.

When detecting update-mode candidates or splicing, match the generated-by marker **anywhere in the
file** — not just at a fixed line. Files rendered before this contract placed the marker on line 1
(a broken layout the loader can't parse), and hand-fixed files may have moved it; both must still
be recognized as generated. On update, normalize the output to this contract (frontmatter on line 1,
marker right after it).

## Update mode (generated-by marker present)

1. Re-run Phase 1 detection; re-confirm only facts that changed (don't re-interview settled policy — read current policy from the existing file's rendered conditionals, e.g. presence of the §6 write gate).
2. Render fresh output from the **current** template with those facts/policies.
3. **Splice**: copy each fenced block from the existing file into the matching slot of the new render. A fence in the old file with no slot in the new template → append under a `<!-- PROJECT-SPECIFIC (orphaned slot: X) -->` marker and tell the user.
4. **Diff**: show a unified diff per skill (old file vs spliced render). Highlight any template-owned hand-edits being replaced — offer to move them into a fence instead.
5. Apply only on approval, per file.

`template-version` bumps when a template changes incompatibly (renamed slots, restructured sections); on a version jump, walk the diff section-by-section rather than assuming a clean splice.

## Adopt mode (no marker — hand-written skills, e.g. the legacy `<prefix>-plate-it` trios)

Never silently overwrite or delete a hand-written skill.

1. Identify legacy skills: `.claude/skills/*plate-it*`, `*get-it*`, `*take-it*`, `*send-it*` without the generated-by marker (anywhere in the file).
2. Run create mode (detect + interview) — but pre-answer the interview from the legacy files where possible (write gates, merge policy, preflight commands are usually stated in them).
3. Render the new plain-named skills (`plate-it`, `take-it`, `send-it`; fill-it/drain-it only if asked).
4. **Side-by-side review per skill**: list every hand-written section that has no equivalent in the render (repo-specific traps, war stories, special recipes). For each, the user picks: move into a PROJECT-SPECIFIC fence / promote upstream (note it as plugin-improvement feedback) / drop.
5. On approval: write the new skills, then **delete the legacy prefixed directories** (they'd otherwise compete for the same trigger phrases). Remind the user the rename also frees the old names: anything else referencing `<prefix>-send-it` (hooks, docs, other skills) needs updating — grep the repo for the old names before finishing.
6. The legacy skills' `scripts/` are superseded by the plugin capability skills' scripts; delete with the directory unless a script is project-unique (then it moves to a path the fenced content references).

## Naming guard

Generated skills use plain names (`plate-it`, `fill-it`, `take-it`, `drain-it`, `send-it`). Before writing, check for shadowing collisions: a **personal** skill (`~/.claude/skills/<same-name>`) hard-shadows a project skill of the same name. If one exists, STOP and tell the user to remove/rename it — the generated skill would be invisible.
