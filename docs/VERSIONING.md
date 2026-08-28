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

**Cadence: release PRs only — so the committed value lags, by design and by
a wide margin.** Content lands on `main` on every merge; the manifest moves
only when a release PR carries a fresh stamp. Measured 2026-08-27 at
`31e9579`, the committed `2026.8.100` was 23 below what its own formula
resolved, across 22 unstamped merges (issue #296). Two consequences follow,
and both are load-bearing:

- The version string does **not** distinguish trees. Two checkouts with
  different content routinely carry the same `version`, so nothing may key a
  content or cache-freshness decision on it. That is why README's
  stale-cache diagnostic compares files rather than version strings.
- "The committed value **is** the release" stays true as the *definition* of
  what a release is. It is not a claim that the manifest tracks `main`, and
  between releases it does not.

Migration note (spec §6): the semver → CalVer switch needed no cutover gate —
`2026.M.P` strictly exceeds the pre-adoption `0.x` train, and this repo has no
store tier, so the mid-month switch was monotonic-safe.

## CI (spec §8)

Nothing in CI computes a version — the preflight gate only shape-checks the
committed manifest (`^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$`) and cross-checks any
`marketplace.json` `plugins[].version` against it, so no `fetch-depth: 0` is
needed today. If a CI job ever *computes* the version (e.g. a future
auto-stamp workflow), that job needs full history (`fetch-depth: 0`).

**Re-checked 2026-08-28 against the tree** (issue #296): still true.
`scripts/preflight.sh` section 5 reads `.version`, matches it against the
CalVer regex and compares `marketplace.json` against it — and computes
nothing — which is exactly why the manifest measured above, 23 below its own
formula on that date, passed the gate green. (The gap is not a constant: it
widens with every unstamped merge, so quote it only with a date and a SHA.) Gate 6 does *execute* both versioning scripts on every CI run
(`scripts/test-versioning.sh`), but against a `mktemp` fixture repo rather
than this repo's history — which is why the shallow checkout is still safe,
and what a future assertion against live history would change. This is a
*deliberate absence*, not an unfinished item, and the section below records
why; an absence nobody can explain gets re-derived as an oversight and
"fixed" by whoever finds it next.

### Why there is no per-merge auto-stamp

Stamping `main` after every merge — what issue #296 asked for, so that the
version-of-record tracks content 1:1 — needs a job that **writes to `main`**,
and nothing available inside this repo can.

`main` is governed by the repository ruleset `main protection`, read
2026-08-28: `pull_request` (a PR is required), `merge_queue` (that PR merges
through the queue), `required_status_checks: ["ci"]`, `bypass_actors: []`
and `current_user_can_bypass: "never"` — alongside classic protection with
`enforce_admins: true`. So there is no direct push to `main` for any actor,
admins included, and the bypass list is empty *by policy* — one Terraform PR
from non-empty, which is route 1 below, and not a door that can be opened
from here. The only route in today is a pull request carrying a green `ci`.

The only credential a workflow here can reach is its own `GITHUB_TOKEN`.
Measured 2026-08-28, all four stores are empty for this repo:
`actions/organization-secrets` — the org-available endpoint, and the one that
actually answers the question — returns `total_count: 0`, as do
`actions/secrets`, `dependabot/secrets` and `environments`. The cause is that
every org secret is `private`-visibility and public repos are excluded
(issue #178), and this repo is public by exception. (Cite the org-available
endpoint, not the repository store: an org secret re-scoped to `all` leaves
the repository store at 0 as well, so that endpoint alone cannot see the
change.)

A pull request opened with `GITHUB_TOKEN` does not trigger workflow runs, so
a stamp PR gets no `ci` from its own `pull_request` event. The chain closes
under the merge queue too, which is where `ci` actually reports here
(`.github/workflows/ci.yml` declares `merge_group`): a `merge_group` run
suppressed for the same reason means no check ever reports against the queue
entry, and it ages out at the ruleset's `check_response_timeout_minutes: 60`
— delaying every real PR queued behind it. A mechanism whose failure mode is
jamming the merge queue is worse than the drift it fixes.

`skills/setup-deps/SKILL.md` has already ruled on this exact shape
(issue #190), and states it as "ruled out twice over": `GITHUB_TOKEN` is out
because
its writes do not re-trigger CI *and* on a second, Dependabot-specific ground
that does not carry here; re-scoping the org secrets to `all` visibility is
out; and a standing PAT in a public repo is out.

Two routes remain, and neither is takeable from inside this repo:

1. A **bypass actor**, on the ruleset *and* on classic protection, for a
   stamping identity. Both controls are in force — `enforce_admins: true`
   lives on the classic side — so moving one alone changes nothing. Repo
   settings are Terraform-owned and verified in `Sassy-Dog/platform`, so this
   is a PR there, never a setting changed by hand, and the bypass entry needs
   its own scoping conditions rather than a blanket exemption.
2. A **dedicated GitHub App** installed on this repo alone with
   `contents: write`, its credentials held as repo-level secrets — the route
   `setup-deps` sanctions, and only "when a real repo is paying the cost".
   **Import its conditions with it, not just its conclusion.** That ruling was
   written for a credential pushing to a PR head ref in a *consumer* repo;
   here the credential writes to `main` of the plugin marketplace, whose
   content installs and executes on every Sassy Dog machine and cloud session,
   so "blast radius limited to one repo" is false in this repo's terms — the
   radius is every consumer. Any workflow minting it must therefore be
   unreachable from fork-PR-influenced triggers and carry an actor and branch
   guard (this repo is public, `pull_request` fires for fork PRs, and
   `.github/workflows/ci.yml` records that its `ci` job has no actor guard),
   and must carry issue #232's checkout rules forward: never hand the minted
   token to `actions/checkout`, keep `persist-credentials: false`, and bound
   the token's on-disk lifetime to the push step.

A third option needs no write to `main` at all and is listed here because it
is the one a reader re-derives first: **stamp in the PR**. Issue #296 weighed
and rejected it for an unrelated reason — every PR would then touch
`.claude-plugin/plugin.json`, putting that path in every issue's `touches:`
line and permanently serializing `dispatch-ready`'s collision filter at a
throughput of 1. It is rejected on that ground, not on the credential ground
above.

Until one of these lands the version-of-record cannot track content, so the
consequence is handled where it bites instead of being papered over: README's
stale-cache diagnostic is keyed on file content rather than on the version
string. None of the decisions in this section is pinned by a gate — they are
prose, and the paragraph above about `test-versioning.sh` being the executable
copy of this document's rules does not reach them.
