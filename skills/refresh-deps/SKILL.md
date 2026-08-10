---
name: refresh-deps
description: >
  This skill should be used when the user asks to "set up Dependabot for this repo", "refresh the
  dependency automation", "wire up dependabot auto-merge", "group the dependabot PRs", "stop the
  dependabot PR flood", "why do dependabot PRs keep failing CI", "fix the bun.lock dependabot
  problem", "regenerate lockfiles on dependabot PRs", "add dependabot config here", "standardize
  dependency updates across our repos", or "re-sync the dependency workflows". Generates and
  re-syncs a repo's `.github/dependabot.yml` plus its dependency automation workflows
  (auto-merge, bun.lock sync, pod lockfile sync) from detected ecosystems. Run from inside the
  target repository; re-runnable as the stack evolves.
---

<!-- generated-by-companion: templates in references/templates/ -->

# Refresh Sassy Dog Deps

Generator/refresher for a repo's dependency automation, in the same family as
`setup-config` and `setup-hooks`: detect the stack, render from templates,
reconcile only what this generator owns.

It renders up to three things:

| File | When |
|---|---|
| `.github/dependabot.yml` | always — grouped, per detected ecosystem |
| `.github/workflows/dependabot-auto-merge.yml` | when the repo has a merge gate |
| `.github/workflows/dependabot-bun-lockfile.yml` | legacy fallback — only when npm has `lockfile_risk` (binary `bun.lockb`, or a repo deliberately on npm + sync); a text `bun.lock` renders the native `bun` ecosystem instead, no sync workflow |
| `.github/workflows/dependabot-pod-lockfile.yml` | when cocoapods is detected **and** the app's `ios/Podfile.lock` is tracked (see §3) |

Ownership marker: the `generated-by: sassy-dog:refresh-deps` comment on the first
non-blank line after the YAML document start. Re-runs reconcile **only** files carrying that
marker — a hand-written `dependabot.yml` is reported and left alone, never overwritten.

**Match on both marker namespaces — the current `generated-by: sassy-dog:` prefix and the
pre-rename `generated-by: ai-agent-skills:` prefix (plugin ≤ 2026.8.20) — and accept the legacy
producer name `refresh-sassydog-deps` (plugin ≤ 2026.7.21) as well as the current `refresh-deps`.**
Every consumer repo rendered before a rename carries the old form: the plugin rename moved the
namespace *before* the colon, the earlier generator rename moved the name after it. A matcher that
only accepts the current form would treat those files as hand-written and refuse to update them.
Normalise the marker to the current form on write.

## 1. Detect

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/refresh-deps/scripts/detect-ecosystems.sh
```

Emits `{repo, ci_workflow, ecosystems{}, present[], needs_lockfile_sync[], detect_failures[]}`.
Evidence is tracked repo files only, never what is installed locally.

`needs_lockfile_sync` is the field that decides whether this repo's Dependabot PRs can ever merge.
Read §3 before skipping it.

## 2. Confirm the merge gate

Auto-merge is only safe behind a required check. Probe both — legacy branch protection and rulesets
are different APIs, and a repo protected by a ruleset returns 404 from the protection endpoint,
which reads as "unprotected" if you only ask one:

```bash
gh api "repos/${REPO}/branches/${BRANCH}/protection" --jq '.required_status_checks.checks[]?.context'
gh api "repos/${REPO}/rulesets" --jq '.[] | select(.enforcement=="active") | .name'
```

Classify into exactly one:

- **merge queue** → render the `MERGE_QUEUE` arm (plain `--auto`, no method flag).
- **required checks, no queue** → render the `DIRECT_MERGE` arm, and confirm
  `allow_auto_merge` is on (`gh api repos/${REPO} --jq .allow_auto_merge`); enable it if not.
- **no gate at all** → **do not render the auto-merge workflow.** Render `dependabot.yml` and the
  lockfile-sync workflows only, and tell the user the repo needs a gate first. With no required
  check, `--auto` merges immediately and the review gate is imaginary.

## 3. Render

Substitute `{{FACT}}` values and delete the `# {{IF:FLAG}}` / `# {{ENDIF}}` blocks that do not
apply. Rendering only ever DELETES lines, so every template is valid YAML as-is and every render is
valid by construction — the same guarantee `setup-hooks` relies on. Never hand-edit a
rendered file to fix a bug; fix the template and re-render.

Facts: `{{RUNNER}}`, `{{APP_DIR}}`, `{{FLUTTER_VERSION}}` (keep in lockstep with the release
workflow). `{{APP_DIR}}` is the Flutter app directory relative to the repo root — `app` for
tailoredtip, `apps/mobile` for velovate, `.` for a root-level app. It replaces the pod template's
v1 `{{PUBSPEC_PATH}}`/`{{IOS_DIR}}` facts: all three named points on the same directory, and
overlapping facts that must agree will eventually disagree — every pubspec/Podfile path now
derives from the one fact. Render rules are in the template header: a nested app substitutes the
token and deletes only the `# {{IF:NESTED_APP}}` marker comments; a root-level app deletes those
blocks wholesale and collapses each `{{APP_DIR}}/` prefix to nothing (a `./` prefix would break
the `on.paths` filter), which keeps root renders byte-identical to v1 output.

`{{RUNNER}}` defaults to the Sassy Dog self-hosted fleet — `[self-hosted, linux, sassy-dog]`, or
`[self-hosted, macOS, sassy-dog]` for the pod template, which **must** have macOS to run
`pod install`. Both org runner groups are `visibility=all`, so every repo can reach the fleet.
Prefer those label forms over the legacy product-scoped ones (`velovate`, `qr-ninja`): the runners
still carry those labels, but scoping by product is a leftover, not a constraint.

**The lockfile trap — the single most important thing this skill exists for.** Dependabot updates a
manifest but writes only the lockfile formats it supports; CI running a frozen-lockfile install then
rejects every PR it opens. One repo in this org merged **0 of 20** npm PRs that way before deleting
the ecosystem to stop the noise. The bun half of that trap is closed by default now: Dependabot's
native `bun` ecosystem (GA 2025-02) reads and rewrites the text `bun.lock` itself (bun >= 1.1.39),
so a bun repo renders the `bun` block and no sync workflow. The npm + `lockfile-sync-bun` pairing
survives only as the legacy fallback — binary `bun.lockb` (which no ecosystem writes), or a repo
that deliberately stays on grouped npm (qr-ninja#394's workspaces-monorepo stance). One caveat keeps
that fallback relevant: bun security updates are not yet supported upstream (version updates only),
and security PRs fire on any vulnerable dependency regardless of the ecosystem list — one arriving
via the npm path edits the manifest without touching `bun.lock`, and only the sync workflow makes it
mergeable. CocoaPods is the trap in full force: Dependabot has no cocoapods ecosystem at all, so the
pod sync workflow is never optional there — without it the security PRs are dead on arrival and the
alerts stay open.

**Pod-template precondition — a tracked Podfile is necessary but not sufficient.** Render
`lockfile-sync-pod` only when the app's `ios/Podfile.lock` is itself tracked; check with
`git ls-files -- "<app-dir>/ios/Podfile.lock"` (empty output = gitignored or untracked). A repo
that gitignores the lock (tailoredtip: release builds regenerate it every run, so it is a build
artifact there, not a committed version pin) has nothing to sync — and the rendered workflow
hard-fails rather than no-ops: `flutter pub get` still changes the tracked `pubspec.lock`, so the
changed-lockfiles guard falls through to `git add` on an explicitly-ignored path, which exits 1
under `bash -e` — a red job occupying the fleet's single macOS runner on every pub PR (the
tailoredtip#252 field report). Gitignored `Podfile.lock` → **do not render**; record in the run
report why the pod workflow was skipped, so the next refresh skips it deliberately instead of
shipping a red workflow. If the repo later wants a committed pod pin (velovate's posture), tracking
the lock is the prerequisite change — the template becomes renderable the moment it lands.

## 4. Prerequisites the render assumes

- **`PLATFORM_WRITER_APP_ID` / `PLATFORM_WRITER_APP_PRIVATE_KEY` in the DEPENDABOT secrets store**,
  not the Actions store. Dependabot-triggered runs cannot see Actions secrets at all — this is the
  most common reason a copied workflow silently no-ops. Org-level with `private` visibility
  (= private + internal) covers every repo; source of truth is Doppler `_scm/github`.
- **`allow_auto_merge`** on the repo, for the direct-merge arm.
- A **CI workflow** whose check is actually required. If `detect_failures` reports no conventional
  CI workflow, that repo needs one before auto-merge means anything.

## 5. Verify

```bash
gh api "repos/${REPO}/dependabot/alerts?state=open&per_page=100" --jq 'length'
```

After the first Dependabot run, confirm the PRs are **grouped** (one per ecosystem, not one per
package) and that a pod repo's PR — or a legacy npm+sync bun repo's — carries a follow-up lockfile
commit (a native-`bun` PR edits `bun.lock` in the PR itself; no follow-up). An ungrouped flood means
a group is missing `applies-to: security-updates` — a group without it covers version updates only,
silently leaving security PRs ungrouped, and the mistake is invisible until the flood arrives.

## Guardrails

- Never render the auto-merge workflow into a repo with no required check.
- Never auto-merge semver-major. A green build does not disprove an API break.
- Never widen the `dependabot[bot]` actor gate on a `pull_request_target` workflow — that gate is
  what keeps contributor code out of a write-capable context.
- Never inline `github.event.pull_request.head.ref` into a `run:` shell; funnel it through `env:`.
- Never overwrite a `dependabot.yml` lacking this generator's marker; report it and stop.
