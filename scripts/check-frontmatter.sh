#!/usr/bin/env bash
# Validate skill/agent frontmatter. Claude Code's skill parser requires the
# opening `---` on line 1 (issue #6 — a leading comment breaks registration),
# so that check is the load-bearing one.
set -euo pipefail

fail=0
problem() { echo "FAIL $1: $2" >&2; fail=1; }

count=0
while IFS= read -r f; do
  count=$((count + 1))
  [ "$(head -n1 "$f")" = "---" ] || problem "$f" "opening '---' must be line 1"
  awk '/^---$/{c++} END{exit c<2}' "$f" || problem "$f" "missing closing frontmatter fence"
  grep -q '^name:' "$f" || problem "$f" "missing name:"
  grep -q '^description:' "$f" || problem "$f" "missing description:"
  case "$f" in
    */SKILL.md) expected=$(basename "$(dirname "$f")") ;;
    agents/*)   expected=$(basename "$f" .md) ;;
  esac
  grep -Eq "^name: *${expected} *$" "$f" || problem "$f" "name does not match '${expected}'"
done < <(git ls-files 'skills/*/SKILL.md' 'agents/*.md' '.claude/skills/*/SKILL.md')

if [ "$fail" -eq 0 ]; then
  echo "frontmatter ok (${count} files)"
else
  exit 1
fi
