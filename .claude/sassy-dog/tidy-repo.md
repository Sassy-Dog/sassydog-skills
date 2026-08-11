---
dep_version_globs: []
noise_allowlist: [".claude/worktrees/"]
never_discard: [".env*", "*.pem", "*.key", ".claude/*.lock"]
claim_label: in-progress
---

## extra-cleanup

<!-- Repo-unique cleanup steps repo-cleanup doesn't cover go here. -->

## extra-guardrails

`.claude/worktrees/` is in `noise_allowlist` deliberately: it is the Agent runtime's own managed
directory, gitignored, and recreated on the next dispatch — after a drain it is left behind empty,
so auto-clearing it is safe and keeps the sweep's residual report meaningful.

**`.claude/*.lock` is in `never_discard`, and `.claude/scheduled_tasks.lock` is why.** That file is
live scheduler state holding the running session's id and pid; discarding it yanks state out from
under an active session. It became visible to the sweep only once #141 switched enumeration to
`git clean -ndx` — exactly the case that issue's never-discard guard was written for: before `-x`,
nothing the sweep could see was ever precious, so the guard protected against something that could
not happen. Within hours of that change landing, something precious became visible.

The pattern is deliberately `.claude/*.lock` rather than the one filename: any lock file the
harness drops in `.claude/` is live runtime state by definition, and naming only today's file
would leave the next one unprotected.

Protection no longer rests on the "an unlisted file is enumerated and asked about" fallback, which
is what covered it initially. That fallback is still the backstop for genuinely unknown files, but
it depends on a human answering a prompt correctly, and this file is not one to get wrong once.
**Never move a `.claude/*.lock` pattern into `noise_allowlist`** — never-discard wins over the
allowlist at the point of use, so the two lists disagreeing would be a silent contradiction rather
than an error.
