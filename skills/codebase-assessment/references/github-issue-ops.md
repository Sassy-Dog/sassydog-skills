# GitHub Issue Operations

Exact commands for dedupe, labels, issue creation, and native sub-issue linking. Run these **only after the user approves the preview** (Phase 4).

> Assumes `gh` is authenticated with `repo` scope on the target. Set `REPO="owner/name"` (from `gh repo view --json nameWithOwner -q .nameWithOwner`).

## 1. Dedupe index (Phase 0, reused in Phase 2 & 4)

```bash
# Open issues — primary dedupe source
gh issue list --repo "$REPO" --state open --limit 500 \
  --json number,title,labels,body,url > /tmp/assess_open_issues.json

# Recently closed — context (avoid re-filing something just fixed)
gh issue list --repo "$REPO" --state closed --limit 200 \
  --json number,title,closedAt,url > /tmp/assess_closed_issues.json
```

Match on title similarity + same file/area in the body. When a candidate matches an open issue, **comment on it** instead of creating a duplicate:

```bash
gh issue comment <N> --repo "$REPO" \
  --body "Re-surfaced by codebase assessment ($(date +%F)). Still open; evidence: <file:line>."
```

## 2. Labels (idempotent — safe to re-run)

```bash
ensure_label() { gh label create "$1" --repo "$REPO" --color "$2" --description "$3" 2>/dev/null || true; }

ensure_label assessment    5319e7 "Filed by codebase-assessment"
ensure_label epic          0e8a16 "Tracking epic"
ensure_label architecture  1d76db "Architecture & structure"
ensure_label security      b60205 "Security / supply chain"
ensure_label tech-debt     fbca04 "Technical debt"
ensure_label testing       0052cc "Testing & quality"
ensure_label ci-cd         006b75 "CI/CD & release"
ensure_label infra         c5def5 "Infrastructure & platform"
ensure_label dx            bfdadc "Developer experience"
ensure_label dependencies  d4c5f9 "Dependencies & supply chain"
ensure_label observability fef2c0 "Observability & ops"
ensure_label sev:critical  b60205 "Critical severity"
ensure_label sev:high      d93f0b "High severity"
ensure_label sev:medium    fbca04 "Medium severity"
ensure_label sev:low       0e8a16 "Low severity"
```

## 3. Child issue body template

```markdown
## Problem
<one-paragraph statement of the genuine risk>

## Evidence
- `path/to/file.ext:LINE` — <what's there and why it's a problem>
- `path/to/other.ext:LINE` — <…>

## Why it matters
<concrete consequence in this repo>

## Proposed fix
<what this PR should do — scoped to one PR>

## Acceptance criteria
- [ ] <observable condition that proves it's fixed>

---
Severity: **<critical|high|medium|low>** · Likelihood: **<high|medium|low>** · Size: **<xs|s|m|l>**
Filed by `codebase-assessment` on <date>. Part of Epic #<EPIC>.
```

Create it (capture the number):

```bash
CHILD_URL=$(gh issue create --repo "$REPO" \
  --title "<imperative title>" \
  --label assessment --label <area> --label sev:<level> \
  --body-file /tmp/child_body.md)
CHILD_NUM=$(basename "$CHILD_URL")
```

## 4. Epic issue

Body = the executive report from `assessment-rubric.md` (scores, strengths, biggest risks, "if I inherited this repo", top-10 ROI, 30/90/180-day roadmap), followed by the child list. Create the Epic **after** the children so you can list/link them.

```bash
EPIC_URL=$(gh issue create --repo "$REPO" \
  --title "Codebase Assessment — <repo> (<date>)" \
  --label assessment --label epic \
  --body-file /tmp/epic_body.md)
EPIC_NUM=$(basename "$EPIC_URL")
```

## 5. Link children as native sub-issues

GitHub sub-issues link by the child's **issue id** (the REST `id`, *not* the issue number).

```bash
link_sub_issue() {  # $1 = epic number, $2 = child number
  local child_id
  child_id=$(gh api "repos/$REPO/issues/$2" --jq '.id')   # REST integer id, NOT the issue number or node id
  gh api --method POST "repos/$REPO/issues/$1/sub_issues" \
    -F "sub_issue_id=${child_id}" >/dev/null \
    && echo "linked #$2 → epic #$1"   # -F sends sub_issue_id as an integer (required); -f would send a string
}

for n in "${CHILD_NUMS[@]}"; do link_sub_issue "$EPIC_NUM" "$n"; done
```

Verify: `gh issue view "$EPIC_NUM" --repo "$REPO"` should show sub-issue progress.

### Fallback (sub-issues API unavailable)

If `POST .../sub_issues` returns 404/403 (older GHES, missing scope), fall back to a task-list checklist in the Epic body — GitHub renders `- [ ] #N` as tracked items:

```markdown
## Tracked issues
- [ ] #12 Pin GitHub Actions to commit SHAs
- [ ] #13 Add integration tests for checkout flow
```

## Order of operations (Phase 4, after approval)

1. `ensure_label` for every label used.
2. For each PR-sized cluster: re-check dedupe → create child issue → collect `CHILD_NUM`.
3. Create the Epic with the executive report + child list.
4. Link every child as a sub-issue (or task-list fallback).
5. Print Epic URL + child URLs.
