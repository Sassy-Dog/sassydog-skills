---
gotcha_summary: >
  Frontmatter `---` must be line 1, with `name:`/`description:` present and `name` matching the
  directory. Skill descriptions are trigger specs, not summaries — capability skills never claim a
  workflow skill's trigger phrases. Skill or agent additions and removals must update `README.md`'s
  tables and re-stamp `.claude-plugin/plugin.json`. No bare positional tokens (`$1`–`$9`, `$@`,
  `$*`) in any SKILL.md body. CI gates: shellcheck, frontmatter check, positional-token and
  legacy-name guards, manifest JSON, markdownlint, actionlint.
---

## extra-rubric

<!-- Additional Ready tests specific to this repo go here. -->
