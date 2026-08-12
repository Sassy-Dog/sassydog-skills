# Security Policy

## Reporting a vulnerability

**Use GitHub's private vulnerability reporting**: [open a draft advisory](https://github.com/Sassy-Dog/sassydog-skills/security/advisories/new). It is enabled on this repository and is the only channel that stays private while we work.

Please do **not** open a public issue for a security problem. Everything else in this repo is fine to file publicly.

This is a small, single-maintainer project. There is no bug bounty, and no paid support tier. Expect a first response within a week; if a report is credible and reproducible, expect the fix to be prioritised over feature work.

## What this project is, and what that means for its threat model

This repository is a **Claude Code plugin**: Markdown skill definitions, reviewer-agent prompts, and Bash scripts. There is no service, no database, and nothing deployed. It runs on a developer's machine, inside an AI coding agent, with that developer's credentials and shell.

That shape is the whole threat model. The interesting classes are:

- **Instruction injection into skill text.** A skill body is read by an agent and followed. Text that causes an agent to exfiltrate secrets, mutate a repository beyond the user's intent, or bypass a documented confirmation step is a vulnerability here, not a documentation bug.
- **Shell injection or unsafe expansion in bundled scripts.** Everything under `skills/*/scripts/` and `scripts/` runs with the invoking user's privileges. Unquoted expansions, `eval` on untrusted input, and path traversal all qualify.
- **Weakened destructive-action gates.** Several scripts are deliberately gated — `scripts/align-labels.sh --migrate` deletes labels only through a single call site that re-verifies immediately beforehand, and `skills/github-issues/scripts/file-or-link-issue.sh` is the only issue-creation path. A change that lets a destructive action run without its gate is a security issue even if nothing is exploited yet.
- **Supply-chain drift in pinned tooling.** GitHub Actions are pinned to commit SHAs, and CI's tool downloads are pinned to an exact version and sha256-verified before unpacking. An unpinned fetch, an unverified one, or a version bumped without its checksum is in scope. Note the two verifications differ in strength: actionlint's checksum is the vendor's published value, while shellcheck publishes none, so its pin was computed locally and attests only that the artifact has not changed since it was pinned.

## What is not in scope

- **Infrastructure names appearing in reviewer-agent calibration blocks.** Strings such as the `kv-sassydog` Key Vault name or Doppler project layout are identifiers, not credentials. They exist so the reviewers can flag org-specific misconfiguration, and knowing a vault's name grants no access to it.
- **Prompts that produce bad engineering advice.** A reviewer agent giving a wrong or unhelpful review is a quality bug — file it as a normal issue.
- **Anything in a repository that consumes this plugin.** Report those to that repository.

## Supported versions

The plugin is versioned as monthly-rolling CalVer (`YYYY.M.<commits-this-month>`) and only the latest release on `main` is supported. There are no maintenance branches. See [`docs/VERSIONING.md`](docs/VERSIONING.md).

Consumers do not auto-update. If a fix ships, updating is:

```bash
claude plugin update sassy-dog@sassydog-skills
```
