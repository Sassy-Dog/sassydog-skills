<!--
CONFIG TEMPLATE: send-it — see plate-it.config.md header for render rules.
merge_queue MUST come from live GraphQL, never from a previous render:
  gh api graphql -f query='{repository(owner:"O",name:"N"){mergeQueue(branch:"B"){id}}}'
-->
---
pr_template_path: "{{PR_TEMPLATE_PATH}}"
pr_template_sections: {{PR_TEMPLATE_SECTIONS}}
preflight_commands: |
  {{PREFLIGHT_COMMANDS}}
coauthor: {{COAUTHOR_LINE}}
merge_queue: {{MERGE_QUEUE}}

# optional

migrations:
  schema_dir: {{SCHEMA_DIR}}
  dirs: {{MIGRATION_DIRS}}
  regen_command: {{MIGRATION_REGEN_COMMAND}}
codegen:
  command: {{CODEGEN_COMMAND}}
  output_dirs: {{CODEGEN_OUTPUT_DIRS}}
review_agent: {{REVIEW_ORCHESTRATOR_AGENT}}
---

## extra-gates

## extra-guardrails
