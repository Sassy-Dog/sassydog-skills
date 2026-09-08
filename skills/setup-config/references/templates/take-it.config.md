<!--
CONFIG TEMPLATE: take-it — see survey-work.config.md header for render rules.
Drop THIS block from the rendered output. The comment below `## subagent-rules` is NOT part of it:
that one sits after the frontmatter, is body prose, and RENDERS into the consumer config on
purpose — the same shape as the commented "... go here." placeholders a config carries under its
other prose headings. It is the only place a reader of a generated config learns that a rule list
starting at `4.` is complete (Sassy-Dog/sassydog-skills#373); dropping it puts the defect back.
(Never write a literal comment terminator inside this block: HTML comments do not nest, so it ends
the block early and the `---` below it becomes a setext heading. markdownlint catches that one.)
-->
---
stack_summary: >
  {{STACK_SUMMARY}}
preflight_commands: |
  {{PREFLIGHT_COMMANDS}}
pr_template_sections: {{PR_TEMPLATE_SECTIONS}}
merge_queue: {{MERGE_QUEUE}}
claim_label: {{CLAIM_LABEL}}

# optional

board:
  number: {{BOARD_NUMBER}}
  project_id: {{BOARD_PROJECT_ID}}
  status_field_id: {{BOARD_STATUS_FIELD_ID}}
  in_progress_option_id: {{BOARD_IN_PROGRESS_OPTION_ID}}
codegen:
  hint: {{CODEGEN_HINT}}
---

## subagent-rules

<!--
Repo-specific implementation rules for a take-it sub-agent go here — free text from the interview,
usually a blockquoted numbered list. By convention the first rule is numbered `4.`, not `1.`

Why: take-it hands each sub-agent one self-contained prompt and injects this section at the step of
that prompt which reads it (`skills/take-it/SKILL.md`, "Sub-agent prompt template"). The prompt has
already spent its opening steps — stay inside your worktree · read the issue · implement per
`CLAUDE.md` — before it reaches this section, so these rules continue its numbering rather than
restarting at 1 and reading as a competing list.

**A list here that starts at 4 is COMPLETE.** There are no items 1-3 in this file, and there never
were; nothing is being withheld from the agent reading it. That is the whole reason this comment
exists: a numbered list beginning at 4 reads as truncation, and a dispatching session has already
acted on that misreading — telling two cold worktree agents that items 1-3 were absent from the
config, a mitigation for a gap that did not exist (Sassy-Dog/sassydog-skills#373). Keep this
comment when you add rules; it is what tells the next reader the list is whole.

Two things that keep the above true rather than merely tidy:

- The convention is "continue the prompt's numbering". `4.` is where that lands while the prompt
  opens with three steps ahead of this section; renumber the prompt and the start number here moves
  with it. The reader rule does not move: this section never has items above the one it starts with.
- Nothing parses these numbers. They are prose, carried across verbatim on every config refresh
  (`setup-config/references/update-mode.md`), and the prompt keeps its own step numbers too — so a
  rendered prompt legitimately contains two items numbered 4, and one numbered 5 for each rule that
  reaches that far. Starting at 1, or using bullets, is equally valid; it only loses the continuity.
-->

## extra-guardrails
