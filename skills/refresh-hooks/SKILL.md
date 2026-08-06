---
name: refresh-hooks
description: >
  This skill should be used when the user asks to "refresh the sassydog hooks", "generate hooks
  for this repo", "set up per-repo hooks", "create project hooks for this repo", "add a formatting
  hook here", "make the hooks repo-specific", "regenerate the hooks", "re-sync the project hooks",
  "add a post-edit format hook", or "wire up format-on-edit for this repo". Creates and re-syncs a
  consumer repo's stack-specific Claude Code hooks: generated dispatcher scripts under
  .claude/hooks/sassydog-*.sh plus their .claude/settings.json wiring. Run from inside the target
  repository; re-runnable as the repo's stack evolves.
---

# Refresh Sassydog Hooks

Generator for **per-repo Claude Code hooks**: inspect the repo's actual stack, render a
formatter/linter dispatcher tailored to it, wire it into `.claude/settings.json`, and reconcile all
of it on every re-run. The sibling of `refresh-skills` — same philosophy: the plugin ships
the generator, the repo owns a generated, refreshable artifact.

Why hooks and not instructions: formatting/lint feedback belongs at the harness layer, firing on
every Edit/Write deterministically — not re-taught per session. A repo-specific render beats a
global hook because a global one fires uselessly in repos whose stack it doesn't match.

## What gets generated

1. **`.claude/hooks/sassydog-post-edit.sh`** — a PostToolUse (Edit|Write) dispatcher rendered from
   `references/templates/sassydog-post-edit.template.sh`. It reads the hook event JSON on stdin,
   extracts the edited file path, and routes by extension to the tools the repo actually has.
   Contract: **formatters fix silently (exit 0); linters with unfixable findings exit 2** so the
   harness feeds the findings straight back for an immediate fix — defects surface at edit time,
   not in the PR review loop.
2. **A `hooks.PostToolUse` entry in `.claude/settings.json`** (or `settings.local.json` when the
   user wants personal-only) whose command is
   `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/sassydog-post-edit.sh"`.

## Ownership contract (what a re-run may touch)

- Generated scripts are exactly the files matching `.claude/hooks/sassydog-*.sh`, each carrying a
  `generated-by: ai-agent-skills:refresh-hooks` header comment. **Match on the
  `generated-by: ai-agent-skills:` prefix and accept the legacy `refresh-sassydog-hooks`
  (plugin ≤ 2026.7.21)** — repos rendered before the rename carry the old name, and a strict matcher
  would treat those scripts as hand-written and refuse to refresh them. Normalise on write. (The
  settings-entry marker below is a command *path*, so the rename does not affect it.)
- Settings entries owned by this generator are exactly the hook entries whose command references
  `.claude/hooks/sassydog-`. A refresh regenerates the scripts and adds/removes **only those
  entries** — every other hook (hand-written project hooks, the user's global hooks) is untouched,
  always. Read `references/settings-merge.md` before any settings write.
- Hand-edits inside a `sassydog-*.sh` script are overwritten on refresh — durable customization
  belongs in a separate hand-written hook, never in a generated file.

## Phase 0 — locate & mode

1. Confirm cwd is the target repo root: `git rev-parse --show-toplevel`.
2. Pick the mode: any `.claude/hooks/sassydog-*.sh` with the `generated-by:` header → **refresh
   mode** (re-detect, re-render, reconcile settings entries); none → **create mode**.
3. Read the existing `.claude/settings.json` (and `settings.local.json`) IN FULL before planning
   any change — the merge is additive and surgical, never a rewrite of unrelated keys.

## Phase 1 — detect

Run the read-only probe from the repo root and treat its output as evidence:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/refresh-hooks/scripts/detect-hook-stack.sh
```

It emits one JSON object — per-tool `detected` + `why` (ruff, prettier, markdownlint, shellcheck,
dart, rustfmt, gofmt, dotnet-format) plus `detect_failures`. The probe table (what counts as
evidence per tool, and the traps) is `references/detection.md`. Detection keys on **repo config
presence** (e.g. a `[tool.ruff]` section, a `.prettierrc*`, a `.markdownlint-cli2.jsonc`), not on
what happens to be installed on this machine — the render must hold on a colleague's machine too.

## Phase 2 — interview (short)

Ask only what detection cannot answer:

1. **Settings target** — committed `.claude/settings.json` (default: the whole team gets the
   hooks) or personal `.claude/settings.local.json`?
2. **Lint strictness** — linters exit 2 (findings feed back for immediate fix — default) or
   advisory (log to the user, exit 0)?
3. **Slow tools** — anything detected with a meaningful per-edit cost (`dotnet format`, full
   `cargo fmt`) is opt-in; confirm before including.

## Phase 3 — render + preview-then-approve

Render the dispatcher from `references/templates/sassydog-post-edit.template.sh`: keep each
`# {{IF:<TOOL>}} ... # {{ENDIF}}` block only when that tool was detected (and confirmed, for slow
tools), strip the marker comment lines, keep the `generated-by` header. The template is valid,
shellcheck-clean bash with every block present — rendering only deletes blocks, so the render is
valid by construction.

Then compose the settings change per `references/settings-merge.md` (add the owned entry if
missing; in refresh mode also remove owned entries whose tool set became empty).

**Print the full rendered script AND the settings diff, and write only after the user approves** —
writing into a product repo is an outward-facing action; never write silently. Preserve the
execute bit on the script.

## Phase 4 — verify

1. Shellcheck the rendered script: `shellcheck -S warning .claude/hooks/sassydog-post-edit.sh`.
2. Fire it with a synthetic event for one detected extension and confirm the routing:

   ```bash
   printf '{"tool_input":{"file_path":"<some-real-repo-file>"}}' | bash .claude/hooks/sassydog-post-edit.sh
   ```

3. Validate the settings file still parses: `jq -e . .claude/settings.json`.
4. Remind: hooks load on the next session in that repo (settings changes are not hot-reloaded).

## Guardrails

- Never write or overwrite files in the target repo without showing the full content/diff and
  getting approval.
- Never touch hook entries this generator does not own (anything not referencing
  `.claude/hooks/sassydog-`), and never rewrite unrelated settings keys.
- The dispatcher must stay non-destructive: format-in-place and read-only lint only — never a
  hook that deletes, commits, pushes, or mutates anything beyond the edited file's formatting.
- The refresher itself always runs from the plugin — generated hooks are repo state, the generator
  is not.

## Additional resources

- **`references/detection.md`** — per-tool probe table, evidence rules, traps.
- **`references/settings-merge.md`** — the settings.json ownership/merge/uninstall contract.
- **`references/templates/sassydog-post-edit.template.sh`** — the dispatcher template (valid bash;
  render = delete unmatched blocks).
- **`scripts/detect-hook-stack.sh`** — read-only stack probe, JSON out.
