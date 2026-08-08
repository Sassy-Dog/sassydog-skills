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
`refresh-skills` and `refresh-hooks`: detect the stack, render from templates,
reconcile only what this generator owns.

It renders up to three things:

| File | When |
|---|---|
| `.github/dependabot.yml` | always — grouped, per detected ecosystem |
| `.github/workflows/dependabot-auto-merge.yml` | when the repo has a merge gate |
| `.github/workflows/dependabot-bun-lockfile.yml` | when npm has `lockfile_risk` (tracked `bun.lock`) |
| `.github/workflows/dependabot-pod-lockfile.yml` | when cocoapods is detected |

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
valid by construction — the same guarantee `refresh-hooks` relies on. Never hand-edit a
rendered file to fix a bug; fix the template and re-render.

Facts: `{{RUNNER}}`, `{{PUBSPEC_PATH}}`, `{{IOS_DIR}}`, `{{FLUTTER_VERSION}}` (keep in lockstep
with the release workflow).

`{{RUNNER}}` defaults to the Sassy Dog self-hosted fleet — `[self-hosted, linux, sassy-dog]`, or
`[self-hosted, macOS, sassy-dog]` for the pod template, which **must** have macOS to run
`pod install`. Both org runner groups are `visibility=all`, so every repo can reach the fleet.
Prefer those label forms over the legacy product-scoped ones (`velovate`, `qr-ninja`): the runners
still carry those labels, but scoping by product is a leftover, not a constraint.

**The lockfile trap — the single most important thing this skill exists for.** Dependabot updates a
manifest but writes only the lockfile formats it supports. It cannot write `bun.lock`, and it has no
cocoapods ecosystem at all. CI running a frozen-lockfile install then rejects every PR Dependabot
opens. One repo in this org merged **0 of 20** npm PRs before deleting the ecosystem to stop the
noise. Security updates cannot be opted out that way — they fire on any vulnerable dependency — so
in a Bun or CocoaPods repo the sync workflow is not optional polish; without it the security PRs are
dead on arrival and the alerts stay open.

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
package) and that a bun/pod repo's PR carries a follow-up lockfile commit. An ungrouped flood means
a group is missing `applies-to: security-updates` — a group without it covers version updates only,
silently leaving security PRs ungrouped, and the mistake is invisible until the flood arrives.

## Guardrails

- Never render the auto-merge workflow into a repo with no required check.
- Never auto-merge semver-major. A green build does not disprove an API break.
- Never widen the `dependabot[bot]` actor gate on a `pull_request_target` workflow — that gate is
  what keeps contributor code out of a write-capable context.
- Never inline `github.event.pull_request.head.ref` into a `run:` shell; funnel it through `env:`.
- Never overwrite a `dependabot.yml` lacking this generator's marker; report it and stop.
