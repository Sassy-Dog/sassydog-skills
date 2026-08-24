#!/usr/bin/env bash
# Every allowlisted writer shape the tree actually uses. If any of these were
# flagged the gate would be unusable, and an unusable gate is turned off — the
# same outcome as never having built it.
set -o pipefail

# bare printf
if printf '%s' "$ROW" | grep -qi 'lifetime'; then echo hit; fi

# guarded by &&
if [ -n "$ROW" ] && printf '%s' "$ROW" | grep -q 'any tier'; then echo hit; fi

# negated, and behind `if !`
if ! echo "$CANDIDATE" | grep -qE "$CALVER_RE"; then echo no; fi

# inside a case arm, where the label's `)` is not a command separator
case "$row" in
    *'sentry: none'*) printf '%s' "$row" | grep -qi 'blind spot' && n=1 ;;
esac

# after a `||`, which is a fallback and not a pipe
test -n "$X" || echo "$Y" | grep -q z

# a quoted `|` inside the printf payload
printf '%s|%s\n' "$A" "$B" | grep -q sep

# the writer on the line ABOVE, across a `\` continuation. Without logical-line
# joining the scanner sees an orphan `| grep -q` with nothing in front of it and
# flags a perfectly bounded writer — which is how a usable gate becomes noise.
if printf '%s' "$ROW" \
     | grep -q 'continued'; then
    echo hit
fi
