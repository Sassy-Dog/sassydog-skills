#!/usr/bin/env bash
# The #172 shape, verbatim: the writer walks the whole tree.
set -o pipefail
if git ls-files | head -1 | grep -q .; then
    echo hit
fi
