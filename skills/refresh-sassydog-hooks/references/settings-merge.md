# Settings merge — ownership, wiring, uninstall

The generator's entire settings footprint is hook entries whose `command` references
`.claude/hooks/sassydog-`. That substring is the ownership marker — JSON has no comments, so
ownership lives in the command path, and the marker survives any hand-reformatting of the file.

## The entry to add

Into the chosen target file (`.claude/settings.json` committed, or `.claude/settings.local.json`
personal — Phase 2 question 1):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/sassydog-post-edit.sh\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

`$CLAUDE_PROJECT_DIR` (expanded by the harness at hook time) keeps the entry correct regardless of
the shell's cwd when the hook fires. The 30s timeout covers `npx` cold starts; per-edit tools are
otherwise sub-second.

## Merge rules (surgical, never a rewrite)

1. Read the target file IN FULL first. No target file → create it with exactly the object above.
2. File exists → deep-merge ONLY the ownership-marked entry:
   - `hooks` key absent → add it.
   - `hooks.PostToolUse` absent → add the array.
   - An `Edit|Write` matcher group already exists → append the command object to ITS `hooks`
     array (do not create a duplicate matcher group) — unless an entry referencing
     `.claude/hooks/sassydog-` is already there (idempotent: nothing to do).
3. Never reorder, reformat, or touch any other key (`permissions`, `env`, other hooks, other
   matchers). The diff shown for approval must contain only the added/removed owned entry.
4. Refresh mode with an empty rendered tool set (repo dropped every detected stack): remove the
   owned entry and the `sassydog-post-edit.sh` script, and say so. Leave empty matcher groups the
   removal creates — deleting a group another tool might share is not surgical.

## Uninstall

"Remove the sassydog hooks" = delete `.claude/hooks/sassydog-*.sh` + remove every settings entry
referencing `.claude/hooks/sassydog-` from BOTH settings files, with the same preview-then-approve
gate. Nothing else changes.

## Precedence notes worth telling the user

- Project `.claude/settings.json` hooks run in addition to (not instead of) the user's global
  `~/.claude/settings.json` hooks — generating here never conflicts with a global SessionStart or
  statusline setup.
- `settings.local.json` is git-ignored by Claude Code convention; choosing it means teammates do
  NOT get the hooks — the right choice for personal experimentation, the wrong one for a team
  formatting standard.
- Hooks are read at session start — a refresh takes effect on the NEXT session in that repo.
