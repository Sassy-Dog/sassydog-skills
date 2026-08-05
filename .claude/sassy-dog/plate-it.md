---
scan_paths: skills agents
exclude_pathspecs: ""
ci_workflow: ci.yml
priority_labels: [bug, enhancement, documentation]
write_policy: read-only
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

<!-- Additional plate-it guardrails go here. -->
