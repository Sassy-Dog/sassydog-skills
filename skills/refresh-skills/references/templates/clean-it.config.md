<!--
CONFIG TEMPLATE: clean-it — see plate-it.config.md header for render rules.
never_discard is the safety list. With no config clean-it discards NOTHING, so
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
