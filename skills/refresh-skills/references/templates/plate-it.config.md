<!--
CONFIG TEMPLATE: plate-it
Rendered into a consumer repo as .claude/sassy-dog/plate-it.md
  {{FACT}}          -> the detected + LIVE-VERIFIED value
  optional: blocks  -> omit the whole block when the repo lacks that surface.
                       Presence is the toggle; there is no `sentry: false`.
  ## sections       -> carried across verbatim on refresh, never rewritten.
Drop this comment block from the rendered output. `---` must be line 1.
-->
---
scan_paths: {{SCAN_PATHS}}
exclude_pathspecs: "{{EXCLUDE_PATHSPECS}}"
ci_workflow: {{CI_WORKFLOW}}
priority_labels: {{PRIORITY_LABELS}}
write_policy: {{WRITE_POLICY}}

# optional — omit any block this repo does not have

sentry:
  org: {{SENTRY_ORG}}
  projects: {{SENTRY_PROJECTS}}
  gate: {{SENTRY_GATE}}
board:
  number: {{BOARD_NUMBER}}
  owner: {{BOARD_OWNER}}
  project_id: {{BOARD_PROJECT_ID}}
  status_field_id: {{BOARD_STATUS_FIELD_ID}}
  backlog_option_id: {{BOARD_BACKLOG_OPTION_ID}}
testflight:
  bundle_id: {{BUNDLE_ID}}
mobile:
  release_workflow: {{RELEASE_WORKFLOW}}
  path_prefix: {{MOBILE_PATH_PREFIX}}
posthog: {{POSTHOG}}
secret_bootstrap: {{SECRET_BOOTSTRAP_CMD}}
---

## extra-surfaces

## scoring-overrides

## extra-guardrails
