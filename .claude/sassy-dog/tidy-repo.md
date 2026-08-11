---
dep_version_globs: []
noise_allowlist: [".claude/worktrees/"]
never_discard: [".env*", "*.pem", "*.key"]
claim_label: in-progress
---

## extra-cleanup

<!-- Repo-unique cleanup steps repo-cleanup doesn't cover go here. -->

## extra-guardrails

`.claude/worktrees/` is in `noise_allowlist` deliberately: it is the Agent runtime's own managed
directory, gitignored, and recreated on the next dispatch — after a drain it is left behind empty,
so auto-clearing it is safe and keeps the sweep's residual report meaningful.

**`.claude/scheduled_tasks.lock` is NOT noise — never add it, or anything matching
`.claude/*.lock`, to the allowlist.** It is live scheduler state holding the running session's id
and pid; discarding it yanks state out from under an active session. It became visible to the sweep
only once #141 switched enumeration to `git clean -ndx`, which is exactly the case that issue's
never-discard guard was written for: before `-x`, nothing the sweep could see was ever precious.
It survives today because an unlisted file is enumerated and asked about rather than discarded —
that fallback is load-bearing here, not a formality.
