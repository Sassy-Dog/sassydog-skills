<!--
CONFIG TEMPLATE: dispatch-ready — see survey-work.config.md header for render rules.
dispatch-ready STOPS on NO_CONFIG (it dispatches and merges unattended), so this file
is required for any repo that runs it.
-->
---
max_in_flight: {{MAX_IN_FLIGHT}}
merge_queue: {{MERGE_QUEUE}}
claim_label: {{CLAIM_LABEL}}

# optional

board:
  number: {{BOARD_NUMBER}}
migrations:
  dirs: {{MIGRATION_DIRS}}
  regen_command: {{MIGRATION_REGEN_COMMAND}}
codegen:
  hint: {{CODEGEN_HINT}}
---

## extra-sequencing
