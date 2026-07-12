# Independent mode — vendored, plugin-free consumer repos

Read this when the delegation-mode interview answer is **independent**, or when Phase 0 detects an
independent repo (any `vendored-by:` marker under `.claude/skills/*/SKILL.md`).

In plugin-backed repos, generated skills delegate to `ai-agent-skills:<capability>` and the plugin's
scripts resolve via `${CLAUDE_PLUGIN_ROOT}`. A clone on a machine without the plugin gets
non-functional shells that STOP at delegation. Independent mode removes that dependency: the needed
capability skills are **vendored into the repo's own `.claude/skills/`**, delegation drops the
namespace (`{{CAP_NS}}` renders empty → `Skill: pr-shepherd`), and a fresh clone works with no
plugin install. The refresh skill itself always runs from the plugin — that invariant is what makes
re-sync possible.

## Vendor bundle (transitive closure)

| Capability | Vendored | Why |
|---|---|---|
| `pr-shepherd` | always (the mandatory root) | send-it/take-it/drain-it delegate to it; `repo-cleanup` calls its `teardown.sh`; `github-issues` calls its `gh-retry.sh` (from `issue-claim.sh` and doc'd board flows) |
| `github-issues` | always | plate-it/fill-it/take-it/drain-it board+issue mechanics, incl. `issue-claim.sh` label-state claims and `queue-snapshot.sh` queue reads; sentry-triage's escalation path |
| `repo-cleanup` | always | the clean-it (core) engine — ships no scripts of its own, hence pr-shepherd above |
| `repo-health` | always | plate-it (core) signal scans |
| `sentry-triage` | only when `IF:SENTRY` | plate-it Sentry surface |
| `testflight` | only when `IF:TESTFLIGHT` | plate-it TestFlight surface |

Never vendored: `github-secrets`, `assess-it`, `refresh-sassydog-skills` itself, and `agents/` —
none are runtime dependencies of the generated family, and vendoring the refresher would break the
"refresh always runs from the plugin" invariant.

## Copy + rewrite rule

For each bundled capability, copy the entire `${CLAUDE_PLUGIN_ROOT}/skills/<cap>/` tree to
`.claude/skills/<cap>/` — SKILL.md, `references/`, `scripts/` — preserving execute bits. Then apply
exactly **one** deterministic rewrite to every copied file:

```
${CLAUDE_PLUGIN_ROOT}/skills/  →  .claude/skills/
```

Paths become repo-root-relative, which is where the generated skills already operate from.
(`testflight` uses `${SKILL_DIR}`, which resolves from the skill's own location — the rewrite
safely no-ops there.) Copied files are otherwise **byte-identical to source**: re-sync is a
recompute-and-diff, and idempotency is trivially checkable — a second refresh with an unchanged
plugin must report no changes.

## Vendored marker

Insert into each vendored SKILL.md only — on the first non-blank line after the closing `---`, blank
line each side (frontmatter `---` must stay line 1 or the loader won't parse it):

```
<!-- vendored-by: ai-agent-skills:refresh-sassydog-skills | capability: <cap> | plugin-version: X.Y.Z -->
```

`plugin-version` comes from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` `.version` at vendor
time. No provenance lines in scripts or references — the SKILL.md marker marks the whole directory
as one vendored unit, and keeping the other files byte-identical to source is worth more than
per-file stamps. Frontmatter `name:` stays the capability name (matches the directory — loader
requirement); descriptions ride along unchanged (the repo-cleanup-vs-clean-it naming trap already
guarantees no trigger collision with the generated skills).

## Mode persistence — repo state, no config file

Any `vendored-by:` marker under `.claude/skills/*/SKILL.md` → the repo is **independent**; none →
**plugin-backed**. This is authoritative and cannot drift: the vendored directories are the very
thing that makes `Skill: pr-shepherd` resolvable. The un-namespaced delegation form in the generated
skills is a secondary tell. Do not additionally record the mode as a rendered fact — duplicated
state that can disagree.

## Re-sync (update mode in an independent repo)

1. Re-render the generated skills from current templates with `{{CAP_NS}}` empty and
   `IF:INDEPENDENT` on — normal splice/diff/approve per update-mode.md.
2. Recompute the bundle from fresh detection (Sentry newly detected → `sentry-triage` joins;
   a capability dropped from the bundle is flagged, not silently deleted).
3. Recopy + rewrite each bundled capability from the live plugin; refresh markers to the current
   plugin-version; delete vendored files that no longer exist at source.
4. Show a per-capability changed-file summary (full diff on request); apply only on approval —
   the same preview-then-approve gate as generated files.

**Hand-edits to vendored files are overwritten on re-sync.** Say so in the preview. Durable
customization belongs in the generated skills' PROJECT-SPECIFIC fences, or upstream in the plugin.

## Mode switching (user-raised, never automatic)

- **plugin-backed → independent** ("set this repo up independently", "make this repo independent"):
  vendor the bundle + re-render the generated skills with `{{CAP_NS}}` empty. Normal previews.
- **independent → plugin-backed** ("switch back to plugin mode"): re-render namespaced, then offer
  to delete the `vendored-by`-marked directories — **only** marked ones, previewed first. Never
  touch an unmarked `.claude/skills/` directory; it isn't yours.

## Consumer-repo lint note

Vendored markdown/scripts may trip the consumer repo's own markdownlint/shellcheck globs. If that
happens, suggest excluding `.claude/skills/` from those linters rather than editing vendored files
(edits are lost on the next re-sync).
