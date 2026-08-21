#!/usr/bin/env bash
# generated-by: sassy-dog:setup-hooks | template: sassydog-artifact-guard | template-version: 1
#
# Stray-artifact guard. Keeps screenshots, HAR dumps and other throwaway binaries
# out of the repo ROOT, where they accumulate unnoticed: they are invisible to
# `git diff`, nothing fails because of them, and the next person to look cannot
# tell a two-day-old debug capture from a deliberate asset.
#
# The cause is mundane and repeatable: screenshot and download tools resolve a
# BARE FILENAME against cwd, and cwd is the repo root. `tmp/` is the sanctioned
# destination — gitignored, and already a universal auto-discard pattern in
# sassy-dog:repo-cleanup, so `tidy-repo` sweeps it with no per-repo config.
#
# TWO EVENTS, ONE SCRIPT (dispatched on .hook_event_name):
#
#   PostToolUse  the moment a tool writes an artifact to the root. Exits 2, so
#                the harness feeds the message back and Claude relocates it
#                immediately. This is the common case.
#   Stop         one `git ls-files --others` scan as a catch-all for artifacts
#                no tool call reveals — `curl -o`, build output, a dragged file.
#
# CONTRACT — this hook REPORTS, it never moves or deletes. Relocating a file the
# user is about to open is worse than naming it, and the generator's other
# script is bound by the same non-destructive rule.
#
# Stop uses `{"decision":"block","reason":...}` on stdout rather than exit 2,
# and guards on `stop_hook_active` FIRST. Claude Code sets that flag while a
# stop-hook continuation is in flight; without the guard a stray the model
# chooses not to remove would block Stop forever. Exit 2 on Stop is the same
# trap with a worse failure mode.
#
# Fail-open everywhere: no stdin, no jq, no git, unknown event, unreadable
# payload -> exit 0. A guard that breaks a session is worse than a stray PNG.
#
# TEMPLATE NOTE (stripped on render): this template is stack-agnostic and has NO
# conditional blocks — it renders verbatim apart from this note. Hand-edits to a
# rendered copy are overwritten on refresh.
set -uo pipefail

payload=$(cat)
[ -z "$payload" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Extensions treated as throwaway artifacts. Deliberately NOT svg: it is
# legitimate committed source in several repos, and a false positive here
# trains people to ignore the hook.
ARTIFACT_RE='\.(png|jpe?g|gif|webp|pdf|mp4|mov|har)$'

jqr() { printf '%s' "$payload" | jq -r "$1" 2>/dev/null; }

event=$(jqr '.hook_event_name // empty')
[ -n "$event" ] || exit 0

# The hook's own cwd is not guaranteed to be the repo root; the payload's is.
cwd=$(jqr '.cwd // empty')
[ -n "$cwd" ] || cwd=$PWD
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

# Canonicalise. `git rev-parse --show-toplevel` reports the PHYSICAL path while
# the payload's cwd is whatever logical path the session was started from, so on
# any repo reached through a symlink (macOS /tmp -> /private/tmp, symlinked work
# dirs) the two never compare equal and every root artifact would slip through.
# That failure is silent — the guard just exits 0 forever.
root=$(cd "$root" 2>/dev/null && pwd -P) || exit 0

case "$event" in
PostToolUse)
  # Param name differs per tool: file_path (Write), path / filename (the
  # browser-automation screenshot tools). Take whichever is present.
  file=$(jqr '.tool_input.file_path // .tool_input.path // .tool_input.filename // empty')
  [ -n "$file" ] || exit 0

  case "$file" in
  /*) abs=$file ;;
  *) abs="$cwd/$file" ;;
  esac

  # Only a real file sitting DIRECTLY in the root is a stray. Anything nested
  # is someone's deliberate asset path.
  [ -f "$abs" ] || exit 0
  dir=$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P) || exit 0
  [ "$dir" = "$root" ] || exit 0
  basename "$abs" | grep -qiE "$ARTIFACT_RE" || exit 0

  cat >&2 <<EOF
Stray artifact written to the repo root: $(basename "$abs")

Throwaway artifacts belong in tmp/ — gitignored, and swept automatically by
tidy-repo. The repo root is not.

Move it and re-point anything referencing it:
  mv "$abs" "$root/tmp/$(basename "$abs")"

Screenshot and download tools resolve a bare filename against cwd, so pass an
explicit tmp/ path next time rather than relying on the default.
EOF
  exit 2
  ;;

Stop)
  # Recursion guard FIRST. Set session-wide while a stop continuation is in
  # flight; re-blocking here is how a Stop hook wedges a session.
  [ "$(jqr '.stop_hook_active // false')" = "true" ] && exit 0

  # --exclude-standard means a gitignored tmp/ is already invisible here, so
  # this reports only what actually escaped into the root.
  strays=$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null |
    grep -v '/' | grep -iE "$ARTIFACT_RE") || exit 0
  [ -n "$strays" ] || exit 0

  list=$(printf '%s' "$strays" | tr '\n' ' ')
  jq -n --arg list "$list" '{
      decision: "block",
      reason: ("Untracked artifacts left in the repo root: " + $list
        + "\nMove them into tmp/ (gitignored, swept by tidy-repo) or delete them, "
        + "then confirm what you did. Do not leave them in the root.")
    }'
  exit 0
  ;;

*)
  exit 0
  ;;
esac
