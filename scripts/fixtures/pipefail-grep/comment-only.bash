#!/usr/bin/env bash
# Six in-scope files DISCUSS this pattern in prose, the guard included. A gate
# that flagged its own documentation would be deleted within a day.
set -o pipefail
# `git ls-files | head -1 | grep -q .` inverts its own result under pipefail.
echo nothing-to-see
