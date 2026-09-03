---
scan_paths: skills agents
exclude_pathspecs: ""
ci_workflow: ci.yml
priority_labels: [bug, enhancement, documentation]
write_policy: read-only
testflight: none
posthog: none
mobile: none
---

## extra-surfaces

<!-- Additional product-specific surfaces go here. -->

## scoring-overrides

Marker-scan false positives: this repo's skills *document* TODO/FIXME/HACK scanning (e.g.
`repo-health`, `assess-it`), so the tech-debt scan will match prose that talks about markers rather
than real debt. Discount hits inside `references/` docs and quoted examples; count only markers
annotating this repo's own scripts or genuinely unfinished sections.

Backlog priority: this repo has no P0–P3 taxonomy — treat the default GitHub labels as the ranking,
`bug` > `enhancement` > `documentation`.

## extra-guardrails

**The three `none` keys are answered, not stale — and `sentry:` is deliberately not one of them.** This repo is a Markdown plugin marketplace with
no shipped application: no beta channel, no product analytics, no mobile target. `testflight: none`,
`posthog: none` and `mobile: none` record that, so the plate carries `(n/a)` tokens for them instead
of three blind-spot rows nothing could ever clear (issue #261).

**`sentry:` is deliberately absent, not `none`.** Nobody has culprit-verified a Sentry project for
this repo, so "nobody has checked" is the honest state and the blind-spot row is correct. Do not
write `sentry: none` to quiet it — that value is written by a *failed* culprit check, not by a
decision, and it keeps its row anyway. Note `detect-capabilities.sh` returns `sentry=true` here for
the same reason it returns `posthog=true`: the word appears in this repo's own skills and fixtures.

**Expect `posthog` detection to contradict the config, and dismiss it.**
`setup-config/scripts/detect-capabilities.sh` decides `posthog` with a bare tracked-tree grep for the
word, and this repo *documents* PostHog in a dozen-odd tracked files spanning skills, CI gates and
this repo's own guidance — run the grep for the current list rather than trusting a set written
here. So a refresh will find positive evidence against `posthog: none` and, correctly, stop and
surface it rather than rewriting the key. The answer is still `none`: the hits are prose about the
config format, not an analytics integration. Do not "fix" this by flipping the key or by deleting
the word.
**This file is no longer one of those hits** — both greps exclude `.claude/**` since issue #317, so
no repo's own recorded answer counts as evidence against itself any more. Here the contradiction is
real and permanent; in a consumer that merely answered §2c it was manufactured, which is what that
issue removed.

This note lives in prose deliberately. Frontmatter is regenerated on every refresh and `##` sections
are carried across verbatim (`setup-config/references/update-mode.md`), so a rationale written beside
the keys would be gone the first time anyone re-ran the generator — which is exactly when it is
needed.

<!-- Additional survey-work guardrails go here. -->
