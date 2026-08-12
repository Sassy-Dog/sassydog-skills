# Contributing

Thanks for looking. This repo has a few conventions that are enforced by CI and are not obvious from the file tree — reading this first will save you a red build.

## The short version

```bash
git clone https://github.com/Sassy-Dog/sassydog-skills
cd sassydog-skills
bash scripts/preflight.sh        # the whole gate, ~25s
```

There is **no build step**. The entire repo is Markdown (skills and agents) plus the Bash scripts bundled inside them. `scripts/preflight.sh` is the single source of truth for every check CI runs — if it is green locally, CI will be green, with the exception of a separate `actionlint` step.

Run it before every PR. `--fix` auto-fixes markdownlint findings.

## Testing a change for real

Preflight is necessary but **not sufficient**. It cannot tell you whether a skill's trigger phrases match the things people actually say, or whether its instructions work when an agent follows them. Load the plugin from your working tree and invoke it:

```bash
claude --plugin-dir /path/to/sassydog-skills
```

Then use the skill the way a user would. A skill that parses cleanly and never triggers is broken.

## Conventions that will fail CI if you miss them

**A skill `description` is a trigger spec, not a summary.** It is dense with quoted user phrases ("set a GitHub secret", "check TestFlight feedback") because matching those phrases is what activates the skill. Write it as the list of utterances that should trigger it, not as a description of what the skill does.

**No bare `$1`–`$9`, `$@`, or `$*` in a `SKILL.md` body.** Skill bodies are an argument-substitution surface: when a skill is invoked with args, positional tokens in the rendered body get replaced, corrupting any embedded command. CI greps for them. Use `cut -f1` / `--format` idioms instead, or move the snippet into a `references/` doc or a bundled script — neither is substituted.

**Progressive disclosure.** `SKILL.md` stays thin and actionable; depth belongs in `references/*.md` that the skill tells the reader to open "when you reach that phase". Don't inline reference-doc detail into `SKILL.md`.

**Never hand-edit the version.** `.claude-plugin/plugin.json`'s `version` is monthly-rolling CalVer and is stamped, never typed:

```bash
bash scripts/stamp-version.sh
```

It is a one-way ratchet — see [`docs/VERSIONING.md`](docs/VERSIONING.md). CI validates it.

**Adding or removing a skill or agent?** Update `README.md`'s plugin/skill table and agent list in the same PR.

**Conventional commits** — `feat:`, `fix:`, `chore:`, `docs:`. PRs to `main`, which has a merge queue.

## Where the tricky parts are

Two architectures in this repo are easy to break from the outside, and both are documented at length in [`CLAUDE.md`](CLAUDE.md):

- **Generator + capability skills.** The workflow skills (`survey-work`, `take-it`, `send-it`, …) are generic and ship once; per-repo behaviour lives in each consumer repo's `.claude/sassy-dog/*.md` config. Shared mechanics live in capability skills (`github-issues`, `pr-shepherd`, `repo-cleanup`, …). **Fix mechanics in the capability skill, never in a workflow skill.**
- **Ownership markers must keep recognising historical names.** Generated files in consumer repos carry a `generated-by:` marker, and the producer name has changed more than once. Matchers accept every name this generator has emitted, across both marker namespaces. Narrowing a matcher to the current name makes every pre-rename consumer file look hand-written and get skipped **silently** — the contract is report-and-skip, not error. `scripts/test-ownership-matchers.sh` pins this against real committed artifacts; if it fails, that is the reason.

Several tests exist to pin invariants that live in prose rather than code (`scripts/test-label-migrate.sh`, `scripts/test-auto-merge-visibility.sh`). If one fails on a wording change, the wording was load-bearing — read the test's header comment, which explains what it is protecting and why.

## Filing issues

Public issues are welcome for bugs, unclear instructions, and skills that don't trigger when they should. For anything security-relevant, use [private reporting](SECURITY.md) instead.

Useful in a bug report: the skill you invoked, what you said to trigger it, what happened, and what you expected. If a skill did not trigger at all, the exact phrasing you used is the single most useful detail.

## Licence

Contributions are accepted under [Apache-2.0](LICENSE), the licence this project ships under.
