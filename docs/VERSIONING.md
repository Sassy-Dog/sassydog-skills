# Versioning — sassy-dog plugin instance

This repo's instance of the org **Versioning spec v1.0** (frozen 2026-07-11).
When this doc and the spec conflict, the spec wins, and changes go through the
spec rather than a local fork.

> **Note for readers outside Sassy Dog:** the spec itself is internal, so the
> two pointers below resolve only for maintainers — an internal knowledge base
> (`Sassy Dog/Architecture/Development/Versioning.md`) and its mirror on
> `Sassy-Dog/platform#397`. Nothing here depends on reading them: this document
> is self-contained, and `scripts/test-versioning.sh` is the executable copy of
> every rule it states. Where you want the authority for a rule, read the test.

Adopted 2026-07-11 via issue #31. Per spec §9, this doc is validated against the
scripts at adoption and whenever either changes — the validation is automated as
`scripts/test-versioning.sh`, run by `scripts/preflight.sh` (CI).

## Repo classification (spec §7)

**Library / plugin (committed manifest)** — a Claude Code plugin marketplace.
The artifact that leaves this repo is the plugin itself, consumed by Claude
Code's marketplace install/update flow, which reads the committed manifest.

## The model

- **Marketing version — monthly-rolling CalVer**: `YYYY.M.<commits-this-month>`
  (non-padded month, UTC, patch floored at 1), e.g. `2026.7.16`. CalVer is
  valid semver, so version-ordering consumers keep working.
- **Version-of-record**: the committed `version` in
  `.claude-plugin/plugin.json`. The scripts *emit* it at release time
  (`scripts/stamp-version.sh`); consumers read the manifest, never git.
  Any `v*` tag, if minted, must equal it.
- **Build number: N/A** (declared per §7) — this repo has no store, appcast,
  or force-update surface; nothing consumes a monotonic integer.
  `scripts/get-build-number.sh` intentionally does not exist.
- **Tags: optional** (declared stance) — releases are marked by the stamping
  commit itself; `v*` tags may be minted as changelog anchors only, and must
  equal the committed manifest value.
- **One repo-wide CalVer**: the marketplace hosts a single plugin today. If
  more plugins are ever added, every manifest `version` field gets the
  identical repo-wide value, stamped by the same script (per-plugin drift is
  forbidden). Per-plugin trains with path-scoped counts would be a declared
  change via platform#397, not a local decision.
- **§2 idempotency waiver** (the documented self-reference): the stamping
  commit changes the commit count that produced the stamped value, so §2's
  re-run idempotency is formally unsatisfiable for a committed manifest. It
  is waived per §7 — the manifest is authoritative. In practice the stamping
  commit also pushes the monthly count past the value it stamped, so the next
  release always resolves strictly higher within the month.

## ⚠️ One-way ratchet (irreversible)

Publishing CalVer-as-semver is **permanent**. The adoption stamp was
`0.11.0 → 2026.7.16` (2026-07-11, issue #31): no `0.x`/`1.x`/`2.x` semver may
**ever** follow, because version-ordering consumers (the plugin update flow)
would read it as a permanent downgrade and silently freeze every consumer at
the last CalVer. Enforced twice:

1. `scripts/stamp-version.sh` refuses to write any non-CalVer value, pinned
   or computed.
2. The CI preflight gate (`scripts/preflight.sh`, manifests gate) fails on a
   non-CalVer manifest version, so a hand-rolled semver can't merge.

## Interface contract (spec §3)

| Capability | Owner |
|---|---|
| Marketing-version command | `scripts/get-version-info.sh` (the §2 algorithm exists exactly once, here; `stamp-version.sh` delegates) |
| Build-number command | N/A — declared above |
| Mint-probe owner | `scripts/stamp-version.sh` — the §4 probe/reuse/bump ladder expressed against the committed manifest instead of tags: equal → reuse; same-train at-or-below committed → bump past it; earlier-month than committed → fail closed |
| Replay pin | `MARKETING_VERSION` (verbatim, never auto-bumped — a pin at/below the committed value fails loudly); `VERSION_DATE_OVERRIDE` / `VERSION_PATCH_OVERRIDE` as test seams |

## Releasing

```bash
bash scripts/stamp-version.sh            # resolve CalVer + write plugin.json
bash scripts/stamp-version.sh --dry-run  # preview without writing
```

Commit the stamped manifest in the release PR — the committed value **is**
the release. Never hand-edit `version`. After the merge, consumer machines
still update manually (`claude plugin update sassy-dog@sassydog-skills`
— see README "Updating / Troubleshooting").

Migration note (spec §6): the semver → CalVer switch needed no cutover gate —
`2026.M.P` strictly exceeds the pre-adoption `0.x` train, and this repo has no
store tier, so the mid-month switch was monotonic-safe.

## CI (spec §8)

Nothing in CI computes a version — the preflight gate only shape-checks the
committed manifest (`^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$`) and cross-checks any
`marketplace.json` `plugins[].version` against it, so no `fetch-depth: 0` is
needed today. If a CI job ever *computes* the version (e.g. a future
auto-stamp workflow), that job needs full history (`fetch-depth: 0`).
