## Summary

<!-- What changed and why, in a short paragraph. Lead with the problem, not the diff. -->

## Changes

<!-- Bullet the skills / agents / scripts touched. One line each. -->

-

## Verification

<!--
How this was exercised. `bash scripts/preflight.sh` is necessary but not sufficient —
it cannot tell you whether a skill's trigger phrases match real utterances, or whether
its instructions work when an agent follows them. For a skill or agent change, load the
plugin from the working tree and actually invoke it:

    claude --plugin-dir /path/to/sassydog-skills

If something could not be exercised, say which and why. "N/A" with a reason beats a
checkbox that means nothing.
-->

- [ ] `bash scripts/preflight.sh` — all gates green
- [ ] Skill/agent changes invoked via `--plugin-dir`, or a reason they were not

<!--
Closing an issue needs a literal `Closes #123` on its own line, one per issue.
A number in the PR title is a hyperlink, NOT a close trigger — and neither is a
bare #123 elsewhere in the body. Naming an issue without the keyword is the
commonest cause of "shipped but still open".
-->
