---
name: github-secrets
description: >
  This skill should be used when the user asks to "set a GitHub secret", "add a GitHub variable",
  "configure secrets for a workflow", "list GitHub secrets", "fix missing secrets in CI",
  "set up environment secrets", "add org secrets", "debug empty secret values in GitHub Actions",
  or any task involving GitHub Actions secrets, variables, or environment configuration.
  Also triggers when editing .github/workflows/ files that reference secrets.* or vars.* contexts.
---

# GitHub Secrets & Variables

GitHub secrets and variables exist at three scopes with strict precedence rules. Getting the scope wrong causes silent failures — empty values with no error.

## Scope Hierarchy

```
Organization  →  Repository  →  Environment
(broadest)                      (most specific, wins ties)
```

- **Organization**: shared across repos, set with `--org`
- **Repository**: default scope, no flag needed inside a repo
- **Environment**: requires `--env` flag AND `environment:` in the workflow job

Environment > Repository > Organization when names collide.

## Secrets vs Variables — Quick Reference

| | Secrets (`secrets.*`) | Variables (`vars.*`) |
|---|---|---|
| CLI | `gh secret` | `gh variable` |
| Workflow | `${{ secrets.NAME }}` | `${{ vars.NAME }}` |
| Encrypted | Yes | No |
| Readable after set | No (write-only) | Yes |
| Use for | Tokens, passwords, keys | URLs, flags, config |

These are different namespaces. `secrets.X` and `vars.X` are not interchangeable.

## Critical Rules

### Always check before setting

```bash
# Secrets — can only check existence, not value
gh secret list [--org ORG] [--env ENV] | grep -q "^NAME"

# Variables — can check existence AND value
gh variable list [--org ORG] [--env ENV] --json name,value
```

### Never try to read secret values

There is no `gh secret get`. Secrets are write-only. `gh secret list` shows names only. To update, re-set from the source of truth.

### Environment secrets require `environment:` in the job

```yaml
jobs:
  deploy:
    environment: production    # WITHOUT THIS, environment secrets are invisible
    steps:
      - run: echo "${{ secrets.PROD_SECRET }}"
```

This is the single most common mistake. Missing `environment:` produces empty values with zero warnings.

### Scope flags are required and specific

```bash
gh secret set X --body "v"                    # repo (default)
gh secret set X --org my-org --body "v"       # org
gh secret set X --env production --body "v"   # environment
```

Omitting `--org` or `--env` silently creates at the wrong scope.

## Workflow Contexts — Do Not Confuse

```yaml
${{ secrets.NAME }}    # GitHub-managed encrypted secrets
${{ vars.NAME }}       # GitHub-managed plaintext variables
${{ env.NAME }}        # Workflow-defined env vars (env: blocks)
${{ github.token }}    # Auto-generated GITHUB_TOKEN
```

`env.X` is set in the workflow YAML with `env:` blocks. `secrets.X` and `vars.X` are set via `gh` CLI or the GitHub UI. These are completely separate systems.

## Diagnostic Workflow

When a secret/variable appears missing in CI:

1. Verify existence: `gh secret list` / `gh variable list` with correct scope flags
2. Check scope: org vs repo vs environment
3. Check job: does it declare `environment:` if using environment secrets?
4. Check shadowing: same name at multiple scopes?
5. Check org visibility: if org-level, is repo in the allow list?
6. Check context: `secrets.X` vs `vars.X` vs `env.X`?
7. Check forks: secrets are NOT available to fork PRs (by design)

## Additional Resources

### Reference Files

For full CLI examples, API details, and extended patterns:

- **`references/scope-hierarchy.md`** — Complete CLI syntax for all scopes, Dependabot/Codespaces secrets, Doppler sync patterns, shadowing rules
- **`references/common-mistakes.md`** — Detailed mistake catalog with wrong/correct examples, diagnostic checklist
