# GitHub Secrets & Variables — Common Mistakes

## Mistake 1: Missing `environment:` on Jobs That Need Environment Secrets

**Symptom:** Secret is set at the environment level but the workflow step gets an empty string.

**Wrong:**

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ secrets.PROD_DB_PASSWORD }}"  # empty!
```

**Correct:**

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production          # <-- this unlocks environment secrets
    steps:
      - run: echo "${{ secrets.PROD_DB_PASSWORD }}"
```

## Mistake 2: Using `vars.X` When You Mean `secrets.X` (or Vice Versa)

Secrets and variables are different namespaces with different CLI subcommands.

```bash
gh secret set DB_PASSWORD --body "hunter2"     # → secrets.DB_PASSWORD
gh variable set API_URL --body "https://..."   # → vars.API_URL
```

In the workflow:

```yaml
- run: curl "${{ vars.API_URL }}"              # variable — plaintext, not masked
- run: psql "${{ secrets.DB_PASSWORD }}"       # secret — encrypted, masked
```

Mixing these up causes empty values with no error.

## Mistake 3: Trying to Read Secret Values

Secrets are write-only after creation. There is no way to retrieve the value.

**Wrong:**

```bash
gh secret get SECRET_NAME        # command does not exist
gh secret list                   # shows names only, never values
gh api repos/{owner}/{repo}/actions/secrets/SECRET_NAME  # returns name + dates, not value
```

**Correct approach:** If the value is unknown, re-set it from the source of truth (e.g., Doppler, Azure Key Vault).

## Mistake 4: Creating Duplicates Without Checking

Before setting a secret or variable, check if it already exists.

**Wrong:**

```bash
gh secret set NEW_SECRET --body "value"   # might already exist — overwrites silently
```

**Correct:**

```bash
# Check first
if gh secret list | grep -q "^NEW_SECRET"; then
  echo "Secret NEW_SECRET already exists. Overwrite? (re-set to update)"
else
  gh secret set NEW_SECRET --body "value"
fi

# For variables (values are readable)
existing=$(gh variable list --json name,value -q '.[] | select(.name=="VAR_NAME") | .value')
if [ -n "$existing" ]; then
  echo "Variable VAR_NAME already exists with value: $existing"
fi
```

Note: `gh secret set` and `gh variable set` are idempotent — they overwrite without error. The risk is not a crash but an unintended overwrite or failing to realize a value already exists at a different scope.

## Mistake 5: Wrong Scope Flags

Each scope requires specific CLI flags:

```bash
# REPO level (default, no flags needed when inside a repo)
gh secret set X --body "v"

# ORG level (must specify --org)
gh secret set X --org my-org --body "v"

# ENVIRONMENT level (must specify --env)
gh secret set X --env production --body "v"
```

Forgetting `--env` or `--org` silently creates the secret at the wrong scope.

## Mistake 6: Org Secrets Not Visible to Repo

Org secrets have a `visibility` setting. If set to `selected`, the repo must be in the allow list.

```bash
# Check visibility
gh api orgs/ORG/actions/secrets/SECRET_NAME --jq '.visibility'

# If "selected", check which repos have access
gh api orgs/ORG/actions/secrets/SECRET_NAME/repositories --jq '.repositories[].full_name'

# Grant access to a specific repo
gh api --method PUT orgs/ORG/actions/secrets/SECRET_NAME/repositories/REPO_ID
```

## Mistake 7: Assuming GITHUB_TOKEN Has Full Permissions

`GITHUB_TOKEN` (the auto-generated token) has limited default permissions in newer repos. Workflows may need explicit `permissions:` blocks:

```yaml
permissions:
  contents: read
  packages: write
  issues: write
```

This is not a secret management issue per se, but agents frequently confuse `GITHUB_TOKEN` permissions with missing secrets.

## Mistake 8: Not Accounting for Forks

Secrets are NOT passed to workflows triggered by pull requests from forks. This is a security feature. If a workflow fails on fork PRs with empty secrets, this is expected behavior — not a configuration error.

## Diagnostic Checklist

When a secret or variable appears missing in a workflow:

1. **Verify it exists** — `gh secret list` / `gh variable list` (with correct `--org`/`--env` flags)
2. **Check the scope** — Is it at org, repo, or environment level?
3. **Check the workflow job** — Does it declare `environment:` if using environment-level secrets?
4. **Check for shadowing** — Is a repo-level secret overriding an org-level one (or vice versa)?
5. **Check visibility** — If org-level, is the repo in the allow list?
6. **Check the context** — `secrets.X` vs `vars.X` vs `env.X`?
7. **Check for forks** — Is this a PR from a fork?
8. **Check the app** — Actions vs Dependabot vs Codespaces?
