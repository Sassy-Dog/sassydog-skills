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
#                       An element that strips to EMPTY (a lone `:(exclude)`),
#                       or whose remainder still starts with `:`, is DROPPED
#                       with a warning on stderr rather than passed to git.
#                       Both are unusable and both fail toward suppression: a
#                       bare `:(exclude)` carries an empty pattern, which git
#                       honours as "exclude the entire tree", so one stray
#                       token reports zero tech debt at exit 0 and the plate
#                       renders that as "no debt". Skipping over-reports
#                       instead, which is the direction a reader notices.
#
# Uses git grep with directory pathspecs. Values reach git LITERALLY: the
# EXCLUDE_PATHSPECS loop runs under `set -f`, so a `**` in a configured value
# is a git pathspec and never a shell glob. Without that fence the bare and
# prefixed spellings diverge — bash pathname-expands `src/generated/**` (which
# skips dotfiles, leaking `src/generated/.hidden.txt`) while it cannot expand
# `:(exclude)src/generated/**`, so git sees the literal.
#
# NOTE, unverified: the line above this one used to assert that `**` requires
# `:(glob)` magic in a git pathspec. That did not reproduce when tested on
# 2026-09-07 and again on the branch for issue #365 — `:(exclude)<dir>/**` and
# `:(exclude)<dir>` returned identical results. It is recorded as needing
# VERIFICATION, not a fix, and nothing in this script depends on it either way.
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
# `set -f` fences the loop's word expansion: split on whitespace, but do NOT
# pathname-expand, so a `**` in a value reaches git literally. See the header —
# without it the two spellings genuinely diverge.
set -f
for p in ${EXCLUDE_PATHSPECS:-}; do
  # The pattern is QUOTED, so it is a glob-free literal and matches exactly one
  # length — that, not the choice of `#` over `##`, is what bounds the strip to
  # a single prefix (`##` behaves identically here). A doubled value must NOT
  # be silently repaired, so the remainder is validated rather than re-stripped.
  q="${p#':(exclude)'}"
  if [ -z "$q" ] || [ "${q#:}" != "$q" ]; then
    echo "pull-tech-debt: ignoring unusable exclude pathspec: '$p'" >&2
    continue
  fi
  EXCLUDES+=(":(exclude)$q")
done
set +f

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
