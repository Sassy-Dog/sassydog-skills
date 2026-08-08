<!--
CONFIG TEMPLATE: take-it — see survey-work.config.md header for render rules.
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

## extra-guardrails
