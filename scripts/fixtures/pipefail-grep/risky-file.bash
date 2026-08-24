#!/usr/bin/env bash
# A file reader as the writer — the shape test-visibility-preconditions.sh had.
set -euo pipefail
if grep -iE 'public' "$FILE" | grep -qiE 'do not render|never render'; then
    echo hit
fi
