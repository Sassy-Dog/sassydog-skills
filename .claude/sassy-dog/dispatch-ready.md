---
max_in_flight: 3
merge_queue: true
claim_label: in-progress
review_site: coordinator
---

## extra-sequencing

<!-- Additional §4 selection filters specific to this repo go here. -->

## review-site rationale

`review_site: coordinator` is a **deliberate override** of the PUBLIC → `agent` seed rule
(#248/#255). Set 2026-08-28 after measuring the cost on this repo: under `agent`, each dispatched
sub-agent re-runs the full `pr-review-orchestrator` fan-out (up to nine reviewers) after every fix
round, and agents were observed doing 3-5 rounds — roughly 30-45 agent invocations to ship one
issue, against an output of 2 merged PRs and two rate limits hit in a day.

The accepted cost is the one the seed rule exists to avoid: this repo is PUBLIC, so between a PR
opening and the coordinator reviewing it, an unreviewed diff is publicly visible. It is still
reviewed before it merges. Do not "restore" this to `agent` as an alignment sweep without
re-measuring the fan-out cost.
