#!/usr/bin/env bash
# Validate skill/agent frontmatter. Two layers:
#
#   1. LOADER requirements — every tracked skill/agent file. Claude Code's
#      skill parser requires the opening `---` on line 1 (issue #6: a leading
#      comment breaks registration), so that check is the load-bearing one,
#      alongside `name`/`description` presence and `name` matching the
#      directory (skills) or filename (agents).
#
#   2. AGENT SKILLS SPEC constraints (https://agentskills.io/specification) —
#      applied to `SKILL.md` ONLY (issue #118). `gh skill publish` validates
#      against that spec, so an unenforced violation blocks the cross-host
#      distribution channel; this is a distribution gate, not a style
#      preference. Unknown frontmatter keys HARD-FAIL against a strict
#      allowlist, matching what `gh skill publish` itself rejects — warn-only
#      would let CI go green on a file the publish channel refuses, which is
#      the precise gap this layer exists to close. Agents are not skills and
#      legitimately carry `color:`, so the spec layer skips `agents/*.md`.
#
# Two ways to get the measurement wrong, both handled here:
#
#   * COUNT CHARACTERS, NOT BYTES. These descriptions are dense with em dashes
#     (3 bytes each in UTF-8), so `wc -c` and awk's `length()` both over-count
#     — enough to fail a compliant description. char_count() counts UTF-8
#     leading bytes (every character has exactly one), which is locale-free
#     and agrees exactly with Python's len().
#
#   * JOIN FOLDED SCALARS BEFORE MEASURING. Every description in this repo is
#     a YAML `>` block, so the value is the continuation lines joined with
#     single spaces — not the first line, and not the raw bytes of the block.
#
# Every failure is reported in one run (accumulate-and-report, same pattern as
# preflight.sh). Exit 0 = all pass, 1 = any fail.
set -euo pipefail

# --- Agent Skills spec limits -----------------------------------------------
MAX_DESC_CHARS=1024
MAX_NAME_CHARS=64
# Strict allowlist of permitted top-level frontmatter keys in a SKILL.md.
SPEC_KEYS='name description license compatibility allowed-tools metadata'

fail=0
problem() { echo "FAIL $1: $2" >&2; fail=1; }

# Parse YAML frontmatter into tab-separated records on stdout:
#   KEY<TAB><key>              — one per top-level key, in document order
#   VAL<TAB><key><TAB><value>  — the scalar value, folded/plain continuation
#                                lines joined with single spaces
# Block indicators (`>`, `|`, and their chomping variants) are consumed rather
# than measured, and surrounding quotes are stripped, so the value measured is
# the value the loader sees.
FM_PARSE=$(cat <<'AWK'
function flush(   q, n) {
  if (!have) return
  n = length(acc)
  q = substr(acc, 1, 1)
  if (n >= 2 && (q == "\"" || q == "'") && substr(acc, n, 1) == q)
    acc = substr(acc, 2, n - 2)
  print "VAL\t" curkey "\t" acc
  have = 0; acc = ""; curkey = ""
}
NR == 1 { if ($0 != "---") exit; inf = 1; next }
inf && $0 == "---" { exit }
inf {
  if ($0 ~ /^[A-Za-z_][A-Za-z0-9_.-]*[ \t]*:/) {
    flush()
    p = index($0, ":")
    curkey = substr($0, 1, p - 1); sub(/[ \t]+$/, "", curkey)
    val = substr($0, p + 1); sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
    print "KEY\t" curkey
    acc = (val ~ /^[>|][-+0-9]*$/) ? "" : val
    have = 1
  } else if (have) {
    line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
    if (line != "") acc = (acc == "") ? line : acc " " line
  }
}
END { flush() }
AWK
)

# Character count of "$1", locale-free: every UTF-8 character has exactly one
# leading byte, so counting the bytes that are NOT continuation bytes
# (0x80-0xBF) yields the character count.
char_count() {
  printf '%s' "$1" | LC_ALL=C awk '{ n += gsub(/[^\200-\277]/, "") } END { print n + 0 }'
}

# Pull one parsed frontmatter value out of the record stream on stdin.
fm_value() {
  awk -F'\t' -v want="$1" \
    '$1 == "VAL" && $2 == want { print substr($0, length($1) + length($2) + 3) }'
}

# Layer 2 — Agent Skills spec constraints. SKILL.md only.
spec_check() {
  local f="$1" parsed key name desc n over
  parsed=$(awk "$FM_PARSE" "$f")

  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case " $SPEC_KEYS " in
      *" $key "*) ;;
      *) problem "$f" "unknown frontmatter key '$key' — the spec allows only: ${SPEC_KEYS// /, }" ;;
    esac
  done < <(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "KEY" { print $2 }')

  name=$(printf '%s\n' "$parsed" | fm_value name)
  desc=$(printf '%s\n' "$parsed" | fm_value description)

  n=$(char_count "$name")
  if [ "$n" -gt "$MAX_NAME_CHARS" ]; then
    problem "$f" "name is $n characters, $((n - MAX_NAME_CHARS)) over the spec max of $MAX_NAME_CHARS"
  fi
  case "$name" in
    *[!a-z0-9-]*) problem "$f" "name '$name' must be lowercase alphanumeric plus hyphens only" ;;
  esac
  case "$name" in
    -*) problem "$f" "name '$name' must not start with a hyphen" ;;
  esac
  case "$name" in
    *-) problem "$f" "name '$name' must not end with a hyphen" ;;
  esac
  case "$name" in
    *--*) problem "$f" "name '$name' must not contain consecutive hyphens" ;;
  esac

  n=$(char_count "$desc")
  if [ "$n" -gt "$MAX_DESC_CHARS" ]; then
    over=$((n - MAX_DESC_CHARS))
    problem "$f" "description is $n characters, $over over the spec max of $MAX_DESC_CHARS"
  fi
}

count=0
while IFS= read -r f; do
  count=$((count + 1))

  # --- Layer 1: loader requirements ---
  [ "$(head -n1 "$f")" = "---" ] || problem "$f" "opening '---' must be line 1"
  awk '/^---$/{c++} END{exit c<2}' "$f" || problem "$f" "missing closing frontmatter fence"
  grep -q '^name:' "$f" || problem "$f" "missing name:"
  grep -q '^description:' "$f" || problem "$f" "missing description:"

  case "$f" in
    */SKILL.md) expected=$(basename "$(dirname "$f")") ;;
    agents/*)   expected=$(basename "$f" .md) ;;
    *)          problem "$f" "unexpected path — not a SKILL.md or agents/*.md"; continue ;;
  esac
  grep -Eq "^name: *${expected} *$" "$f" || problem "$f" "name does not match '${expected}'"

  # --- Layer 2: Agent Skills spec (SKILL.md only; agents carry color:) ---
  case "$f" in
    */SKILL.md) spec_check "$f" ;;
  esac
done < <(git ls-files 'skills/*/SKILL.md' 'agents/*.md' '.claude/skills/*/SKILL.md')

if [ "$fail" -eq 0 ]; then
  echo "frontmatter ok (${count} files)"
else
  exit 1
fi
