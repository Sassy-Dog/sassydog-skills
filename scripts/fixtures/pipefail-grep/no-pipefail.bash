#!/usr/bin/env bash
# The same risky shape, but nothing here promotes the writer's SIGPIPE 141: the
# inversion needs the option this file deliberately does not set, so this is out
# of scope. Flagging it would inflate the gate into noise.
#
# Do not name that option anywhere in this file, comments included — the corpus
# filter greps the whole file for it, and a mention would pull the fixture back
# into scope and invert what it proves.
set -eu
if git ls-files | grep -q foo; then
    echo hit
fi
