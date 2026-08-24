#!/usr/bin/env bash
# The other continuation spelling: the line ends with a bare `|` and the
# `grep -q` starts the next one. This is the shape a line-oriented scanner
# misses OUTRIGHT rather than merely misclassifying — the second line carries no
# pipe at all, so without logical-line joining there is nothing to match on.
set -o pipefail
if git ls-files |
    grep -q foo; then
    echo hit
fi
