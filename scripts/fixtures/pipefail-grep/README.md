# pipefail-grep fixtures

Inputs for `scripts/test-pipefail-grep.sh` (issue #256).

They are deliberately **not** named `*.sh`. That keeps them out of preflight's
shellcheck pathspec (`git ls-files '*.sh'`) and out of the guard's own scan
globs, so the risky shapes below stay data the scanner is pointed at rather
than code it trips over.

Keeping them here instead of writing them from the guard is not cosmetic. The
scanner is line-oriented and quote-blind — ambiguity resolves toward flagging —
so a fixture built with a multi-line `printf` puts the shape on a *live* line
of the guard, and the guard flags itself. Measured, not assumed: that is
exactly what the first draft did.

| file | what it pins |
| --- | --- |
| `risky-tree.bash` | the #172 shape verbatim — `git ls-files` into `head` into `grep -q` |
| `risky-file.bash` | a file reader (`grep … "$FILE"`) as the writer |
| `risky-continued.bash` | the writer on the line *above* the `grep -q`, across a `\` continuation |
| `risky-trailing-pipe.bash` | the other continuation spelling — a line ending in a bare pipe character |
| `safe-allowlisted.bash` | every allowlisted `printf`/`echo` writer shape found in the tree |
| `comment-only.bash` | the shape described in prose, which is not a finding |
| `no-pipefail.bash` | the shape in a script with no `pipefail` — out of scope |
