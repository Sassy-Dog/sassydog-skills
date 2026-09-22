---
scan_paths: skills agents
exclude_pathspecs: ""
ci_workflow: ci.yml
priority_labels: [bug, enhancement, documentation]
write_policy: read-only
sentry: none
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

**The three product-fact `none` keys are answered, not stale.** This repo is a Markdown plugin marketplace with
no shipped application: no beta channel, no product analytics, no mobile target. `testflight: none`,
`posthog: none` and `mobile: none` record that, so the plate carries `(n/a)` tokens for them instead
of three blind-spot rows nothing could ever clear (issue #261).

**`sentry: none` is recorded, not absent.** `setup-config` writes it as the outcome of the culprit
check in `references/detection.md`, and that check has been run here: no candidate project in the
`sassy-dog` org has culprits resolving to a path in this repo — the nearest-named candidate,
`platform`, reports culprits such as `root-disk-usage` that belong to `Sassy-Dog/platform`. That is
the whole of what the key records — **no project is verified for this repo** — and never the wider
claim that this repo has no error monitoring, which `config-contract.md` and `survey-work` §6 both
forbid in as many words. The key is re-derived on every refresh, and it is also what a check that
merely *could not run* writes, so read this paragraph as why the value was written once, not as a
standing certificate that a sweep completed.

**The blind-spot row still renders, and that is correct.** `sentry: none` keeps its row while the
three siblings lose theirs (`config-contract.md`, "The one exception"). Do not delete the key to
quiet the row: an absent key means *nobody checked*, a different and now-inaccurate claim. Nothing
enforces that — no gate reads this file's keys — so it holds only as far as it is read.

Note `detect-capabilities.sh` returns `sentry=true` here, but **not** for the reason it returns
`posthog=true`. The posthog probe is a bare-word grep; the sentry probe greps SDK literals
(`@sentry/`, `sentry.init`, and siblings), which this repo's own detector, that detector's gate and
a Dependabot fixture happen to carry. Both are artefacts of a repo that *documents* these tools,
and neither is evidence against the recorded key — run the greps for the current hits rather than
trusting a list written here.

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
