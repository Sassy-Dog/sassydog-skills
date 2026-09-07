#!/usr/bin/env bash
# Surface in-code tech-debt signals: TODO/FIXME/HACK/XXX markers and skipped
# tests. Read-only. Run from repo root.
#
# Env:
#   SCAN_PATHS          space-separated pathspecs to scan (default: ".")
#   EXCLUDE_PATHSPECS   space-separated paths to exclude from the scan. The
#                       canonical spelling is BARE — this script supplies the
#                       `:(exclude)` magic itself — e.g.
#                       "packages/db/src/migrations src/generated".
#                       A leading `:(exclude)` is ALSO accepted and stripped,
#                       because setup-config's contract shipped that spelling
#                       and every config written against it carries the prefix
#                       (issue #365). Double-prefixing yields
#                       `:(exclude):(exclude)<path>`, a valid pathspec that
#                       matches nothing, so git excludes nothing and exits 0 —
#                       the exclusion is silently disabled with nothing red
#                       anywhere. At most ONE prefix is stripped: a genuinely
#                       doubled value stays visibly broken rather than being
#                       masked by a greedy strip.
#
# Uses git grep with directory pathspecs (git pathspecs are not shell globs;
# `**` requires :(glob) magic, so we pass directories and accept some noise).
#
# Uses -P (PCRE) for word boundaries: POSIX ERE (-E) silently treats `\b` as a
# literal `b` on some git builds, returning zero matches with no error.
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "skipped: not a git repo" >&2
  exit 10
fi

# shellcheck disable=SC2206  # word-splitting of the env lists is intentional
SCAN=(${SCAN_PATHS:-.})
EXCLUDES=(
  ':(exclude)**/*.lock'
  ':(exclude)**/*.lock.json'
  ':(exclude)**/*-lock.json'
  ':(exclude).claude/**'
)
for p in ${EXCLUDE_PATHSPECS:-}; do
  # `${p#':(exclude)'}` — quoted so the pattern is literal, and `#` not `##`,
  # so at most one prefix comes off. See the header: both spellings must land
  # on the same single-prefixed pathspec, and a doubled input must NOT be
  # silently repaired.
  EXCLUDES+=(":(exclude)${p#':(exclude)'}")
done

# TODO/FIXME/HACK/XXX in tracked source. git grep walks tracked files, so
# .gitignore is naturally respected.
echo "=== todo-markers ==="
git grep --no-color -InP '\b(TODO|FIXME|HACK|XXX)\b' -- \
  "${SCAN[@]}" "${EXCLUDES[@]}" \
  2>/dev/null | head -200 || true

echo "=== skipped-tests ==="
# Covers Vitest/Jest/Playwright/Bun (`.skip`/`.todo`/`xit`), pytest
# (`@pytest.mark.skip`), .NET (`[Skip`/`Skip =`), and Flutter (`skip:`).
git grep --no-color -InP \
  '\b(test|it|describe)\.(skip|todo)\(|\bx(it|describe)\(|@pytest\.mark\.skip|\[Skip|Skip\s*=\s*"|skip:\s*true' \
  -- "${SCAN[@]}" "${EXCLUDES[@]}" \
  2>/dev/null | head -100 || true

echo "=== todo-by-dir ==="
git grep --no-color -IlP '\b(TODO|FIXME|HACK)\b' -- \
  "${SCAN[@]}" "${EXCLUDES[@]}" \
  2>/dev/null \
  | awk -F/ '{ d=""; for(i=1;i<=NF-1;i++) d=d $i "/"; print d }' \
  | sort | uniq -c | sort -rn | head -20 || true
