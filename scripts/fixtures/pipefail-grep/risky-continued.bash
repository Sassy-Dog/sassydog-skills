#!/usr/bin/env bash
# The writer sits on the line ABOVE the grep -q, across a `\` continuation, and
# the jq program carries a quoted `|` of its own. Five real sites in
# test-label-migrate.sh looked exactly like this — a line-scoped scanner sees
# `| grep -q` with nothing in front of it and reports nothing.
set -uo pipefail
if jq -e -r 'select(.old == "p1") | .detail' <"$OUT" \
     | grep -q "held back"; then
    echo hit
fi
