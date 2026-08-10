<!--
CONFIG TEMPLATE: tidy-repo — see survey-work.config.md header for render rules.
never_discard is the safety list. With no config tidy-repo discards NOTHING, so
an empty list here is safe; a WRONG list is not.
-->
---
dep_version_globs: {{DEP_VERSION_GLOBS}}
noise_allowlist: {{NOISE_ALLOWLIST}}
never_discard: {{NEVER_DISCARD}}

# optional

claim_label: {{CLAIM_LABEL}}
---

## extra-cleanup

## extra-guardrails
