# Security Scanning Surface (PR 1 — sassydog-skills) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub code-scanning and secret-scanning as a first-class `## 🔒 Security` surface
across `repo-health`, `survey-work`, and `whats-on-fire`, absorbing the existing Dependabot
exposure ranking out of Dev experience.

**Architecture:** Two new read-only bash scripts under `skills/repo-health/scripts/` emit JSON
contracts modelled exactly on the existing `pull-dependency-exposure.sh`. The two workflow skills
consume them as prose instructions; no code couples them. A new preflight gate pins the four
failure modes that are silent by nature.

**Tech Stack:** Bash (`set -uo pipefail`, no `-e`), `gh` CLI, `jq`, shellcheck `-S warning`,
markdownlint-cli2, mock-`gh` test harness.

**Spec:** `docs/superpowers/specs/2026-08-18-security-scanning-surface-design.md`

## Global Constraints

- Every new script: `set -uo pipefail` **without** `-e`; degrade with exit 10 and
  `skipped: <reason>` on stderr; emit exactly one JSON object on stdout; never abort a caller's scan.
- **No bare `$1`–`$9`, `$@`, `$*` in any `SKILL.md` body.** CI greps for them. Use `cut -f1` idioms
  or move the snippet into a bundled script.
- `${CLAUDE_PLUGIN_ROOT}` is substituted **only** in `SKILL.md` at load time — never in
  `references/*.md`, never in the shell environment.
- `SKILL.md` frontmatter `description` is hard-capped at **1024 characters** by
  `scripts/check-frontmatter.sh`. Current usage: `survey-work` 802, `repo-health` 661,
  `whats-on-fire` **933** (91 free).
- New-vs-inherited boundary: **14 days**. Unknown-validity secret escalation: **30 days**.
- Ref filter compares against the repo's resolved default branch — **never** a hardcoded `main`.
- Every gate assertion that a string must NOT exist runs against a **whitespace-flattened** copy of
  the file; this repo hard-wraps prose and a line-scoped grep turns a wrap into a false PASS.
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`).
- `bash scripts/preflight.sh` must be green before every commit that touches a gated file.

---

### Task 1: `pull-code-scanning.sh` and its state gate

**Files:**

- Create: `skills/repo-health/scripts/pull-code-scanning.sh`
- Create: `scripts/test-scanning-states.sh`
- Modify: `scripts/preflight.sh` (new gate 19, after the gate-15 block ending near line 486)
- Modify: `skills/repo-health/SKILL.md` (new `### Code scanning` scan section)

**Interfaces:**

- Produces: `pull-code-scanning.sh` emitting
  `{enabled, analyzed, truncated, open, default_branch, tools[], new[], inherited{}}`.
  `new[]` entries are `{rule, severity, count, oldest_age_days, alerts[], autofix}`.
  `inherited` is `{count, rules, oldest_age_days, by_severity{critical,high,medium,low}}`.
  Task 2 adds a sibling script; Tasks 3–4 consume this shape by name.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-scanning-states.sh`:

```bash
#!/usr/bin/env bash
# test-scanning-states.sh — pins the four silent failure modes of the code- and
# secret-scanning pulls.
#
# Every one of these is silent by construction: each produces a well-formed JSON
# object carrying a plausible number, so nothing downstream can tell a wrong
# answer from a right one.
#
#   1. Code scanning returns 404 for BOTH "Advanced Security is off" and "on,
#      but no analysis has ever run". Both yield open:0. Collapsing them reports
#      a never-scanned repo as clean.
#   2. An un-paginated per_page=100 read reports a capped count as a
#      measurement. Probed live on 2026-08-18: Sassy-Dog/velovate returned
#      exactly 100 against a true 102.
#   3. An alert on a PR ref is not repo debt; counting it inflates the default
#      branch's exposure with work that may never merge.
#   4. The secret-scanning P0 rule for validity:"active" must carry no age gate.
#
# Mock gh only: no repo, no network. jq is real and is fed real JSON.
set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-scanning-states: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

CODE_SCRIPT="skills/repo-health/scripts/pull-code-scanning.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok()  { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

echo "scanning-states tests (work: $WORK)" >&2

# --- the mock gh -------------------------------------------------------------
# Behaviour is driven by MOCK_MODE. Alert pages are generated with jq so
# created_at is always relative to the run, keeping the 14-day split stable
# without depending on GNU vs BSD date.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

jq_expr=""; prev=""
for a in "$@"; do
    [ "$prev" = "-q" ] || [ "$prev" = "--jq" ] && jq_expr="$a"
    prev="$a"
done

cmd="$1"; shift

if [ "$cmd" = "repo" ]; then
    case "${jq_expr}" in
        *defaultBranchRef*) echo "main" ;;
        *) echo "mock-org/mock-repo" ;;
    esac
    exit 0
fi

[ "$cmd" = "api" ] || { echo "mock gh: unhandled command: $cmd" >&2; exit 1; }

path="$1"
page=1
case "$path" in *page=*) page="${path##*page=}"; page="${page%%&*}" ;; esac

case "$path" in
  # The autofix arm MUST precede the alerts arm: an autofix path is
  # .../code-scanning/alerts/<n>/autofix, which the alerts glob also matches,
  # so the reverse order makes this arm unreachable and every probe returns a
  # page of alerts instead of a 404.
  */autofix)
    echo '{"message":"Not Found"}' >&2; exit 1 ;;
  */code-scanning/alerts*)
    case "$MOCK_MODE" in
      disabled)
        echo '{"message":"Advanced Security must be enabled for this repository to use code scanning."}' >&2
        exit 1 ;;
      never-analyzed)
        echo '{"message":"no analysis found"}' >&2
        exit 1 ;;
      no-scope)
        echo '{"message":"Resource not accessible by integration"}' >&2
        exit 1 ;;
      two-pages)
        # 100 alerts on page 1, 2 on page 2 — the live velovate shape.
        if [ "$page" = "1" ]; then n=100; else n=2; fi
        jq -nc --argjson n "$n" '[range($n) | {
            number: (. + 1),
            created_at: ((now - (200 * 86400)) | todate),
            rule: {id: "js/xss", security_severity_level: "high"},
            tool: {name: "CodeQL"},
            most_recent_instance: {ref: "refs/heads/main"}
          }]' ;;
      pr-ref)
        jq -nc '[
          {number: 1, created_at: ((now - (2 * 86400)) | todate),
           rule: {id: "js/sql-injection", security_severity_level: "critical"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/pull/7/merge"}},
          {number: 2, created_at: ((now - (2 * 86400)) | todate),
           rule: {id: "js/sql-injection", security_severity_level: "critical"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}}
        ]' ;;
      split)
        jq -nc '[
          {number: 10, created_at: ((now - (3 * 86400)) | todate),
           rule: {id: "js/xss", security_severity_level: "high"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}},
          {number: 11, created_at: ((now - (90 * 86400)) | todate),
           rule: {id: "js/xss", security_severity_level: "high"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}},
          {number: 12, created_at: ((now - (90 * 86400)) | todate),
           rule: {id: "js/weak-hash", security_severity_level: "medium"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}}
        ]' ;;
      *) echo "mock gh: unknown MOCK_MODE: $MOCK_MODE" >&2; exit 1 ;;
    esac ;;
  *)
    echo "mock gh: unhandled api path: $path" >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/gh"

run_code() { MOCK_MODE="$1" PATH="$WORK/bin:$PATH" REPO="mock-org/mock-repo" bash "$CODE_SCRIPT"; }

echo "1. the four-state disambiguation" >&2

out=$(run_code disabled)
[ "$(jq -r '.enabled' <<<"$out")" = "false" ] \
    && ok "Advanced Security off  -> enabled:false" \
    || bad "Advanced Security off  -> enabled:false (got $(jq -c '{enabled,analyzed}' <<<"$out"))"

out=$(run_code never-analyzed)
[ "$(jq -r '.enabled' <<<"$out")" = "true" ] && [ "$(jq -r '.analyzed' <<<"$out")" = "false" ] \
    && ok "never analyzed       -> enabled:true, analyzed:false" \
    || bad "never analyzed       -> enabled:true, analyzed:false (got $(jq -c '{enabled,analyzed}' <<<"$out"))"

out=$(run_code no-scope)
[ "$(jq -r '.enabled' <<<"$out")" = "null" ] \
    && ok "token cannot see it  -> enabled:null" \
    || bad "token cannot see it  -> enabled:null (got $(jq -c '{enabled,analyzed}' <<<"$out"))"

echo "2. pagination and truncation" >&2

out=$(run_code two-pages)
[ "$(jq -r '.open' <<<"$out")" = "102" ] \
    && ok "paginates past page 1 (open=102, not 100)" \
    || bad "paginates past page 1 (expected open=102, got $(jq -r '.open' <<<"$out"))"

echo "3. the ref filter" >&2

out=$(run_code pr-ref)
[ "$(jq -r '.open' <<<"$out")" = "1" ] \
    && ok "PR-ref alert excluded" \
    || bad "PR-ref alert excluded (expected open=1, got $(jq -r '.open' <<<"$out"))"
[ "$(jq -r '[.new[].alerts[]] | index(1) // "absent"' <<<"$out")" = "absent" ] \
    && ok "PR-ref alert absent from new[]" \
    || bad "PR-ref alert leaked into new[]"

echo "4. the new-vs-inherited split" >&2

out=$(run_code split)
[ "$(jq -r '.new | length' <<<"$out")" = "1" ] \
    && ok "one rule in new[]" \
    || bad "one rule in new[] (got $(jq -c '.new' <<<"$out"))"
[ "$(jq -r '.new[0].count' <<<"$out")" = "1" ] \
    && ok "a rule straddling the boundary counts only its fresh alerts" \
    || bad "a rule straddling the boundary counts only its fresh alerts (got $(jq -r '.new[0].count' <<<"$out"))"
[ "$(jq -r '.inherited.count' <<<"$out")" = "2" ] \
    && ok "its older alerts fall to inherited" \
    || bad "its older alerts fall to inherited (got $(jq -r '.inherited.count' <<<"$out"))"
[ "$(jq -r '.inherited.rules' <<<"$out")" = "2" ] \
    && ok "inherited counts distinct rules" \
    || bad "inherited counts distinct rules (got $(jq -r '.inherited.rules' <<<"$out"))"

[ "$fail" -eq 0 ] || { echo "scanning-states tests: FAILED" >&2; exit 1; }
echo "scanning-states tests: all green" >&2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-scanning-states.sh`
Expected: FAIL — the harness cannot find `skills/repo-health/scripts/pull-code-scanning.sh`, so
every assertion reports FAIL and the script exits 1.

- [ ] **Step 3: Write the implementation**

Create `skills/repo-health/scripts/pull-code-scanning.sh`:

```bash
#!/usr/bin/env bash
# pull-code-scanning.sh — one repo's FIRST-PARTY code-scanning exposure, split
# into what was just shipped and what is settled debt.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   PAGE_CAP   max 100-alert pages to read (default: 5 = 500 alerts)
#   BOUNDARY   new-vs-inherited split in days (default: 14)
#
# Output shape:
#   { "enabled": true|false|null, "analyzed": true|false|null,
#     "truncated": false, "open": N, "default_branch": "main",
#     "tools": ["CodeQL"],
#     "new": [ { "rule", "severity", "count", "oldest_age_days",
#                "alerts": [N], "autofix": "ready"|"none"|"unsupported"|null } ],
#     "inherited": { "count", "rules", "oldest_age_days",
#                    "by_severity": {"critical","high","medium","low"} } }
#
# WHY `analyzed` IS A SEPARATE FIELD: the alerts endpoint answers 404 for BOTH
# "Advanced Security is off" and "on, but no analysis has ever run". Both yield
# open:0, and they are opposite findings — one is a config gap, the other is a
# clean repo. Collapsing them reports a never-scanned repo as clean, which is
# strictly worse than reporting nothing. `enabled` keeps the same three-state
# contract as pull-dependency-exposure.sh: 403-for-scope stays null, never false.
#
# WHY PAGINATION IS NOT OPTIONAL: on 2026-08-18 a single per_page=100 read of
# Sassy-Dog/velovate returned exactly 100 alerts. The true count was 102. A
# capped number is indistinguishable from a measured one, so the cap is reported
# as `truncated: true` and the count is a floor.
#
# WHY THE REF FILTER: most_recent_instance.ref can name a PR merge ref. An alert
# that exists only on someone's branch is not this repo's debt and may never
# merge. The default branch is resolved, never assumed to be "main".
#
# WHY RULE-CLUSTERED: velovate carries 74 medium alerts. Rendered as 74 rows
# that is a wall nobody triages — the same failure that made a bare Dependabot
# count useless (see pull-dependency-exposure.sh). Rendered as "11 rules, oldest
# 214d" it is one honest line, and the handful shipped this week get attention.
#
# Deliberately `set -uo pipefail` WITHOUT `-e`: a repo with scanning disabled
# must still emit a valid JSON object rather than voiding the caller's scan.
set -uo pipefail

PAGE_CAP="${PAGE_CAP:-5}"
BOUNDARY="${BOUNDARY:-14}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[ -z "$REPO" ] && { echo 'skipped: could not determine REPO (set REPO=owner/name)' >&2; exit 10; }

# No default branch means no safe ref filter. Guessing "main" would silently
# count another branch's alerts as this repo's debt, so this degrades instead.
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"
[ -z "$DEFAULT_BRANCH" ] && { echo "skipped: could not resolve default branch for ${REPO}" >&2; exit 10; }

state_json() {
    jq -nc --arg db "$DEFAULT_BRANCH" \
        --argjson en "$1" --argjson an "$2" \
        '{enabled: $en, analyzed: $an, truncated: false, open: null,
          default_branch: $db, tools: [],
          new: [],
          inherited: {count: null, rules: null, oldest_age_days: null,
                      by_severity: {critical: null, high: null, medium: null, low: null}}}'
}

alerts='[]'
truncated=false
page=1
while [ "$page" -le "$PAGE_CAP" ]; do
    if ! resp=$(gh api "repos/${REPO}/code-scanning/alerts?state=open&per_page=100&page=${page}" 2>&1); then
        if grep -qi 'advanced security must be enabled\|code scanning is not enabled' <<<"$resp"; then
            state_json false false; exit 0
        elif grep -qi 'no analysis found' <<<"$resp"; then
            state_json true false; exit 0
        else
            # Could not read: token scope, not a verdict. Stay null.
            state_json null null; exit 0
        fi
    fi
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$resp" || { state_json null null; exit 0; }
    count=$(jq 'length' <<<"$resp")
    alerts=$(jq -c --argjson a "$alerts" --argjson b "$resp" -n '$a + $b')
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
    [ "$page" -gt "$PAGE_CAP" ] && truncated=true
done

base=$(jq -c --arg ref "refs/heads/${DEFAULT_BRANCH}" --arg db "$DEFAULT_BRANCH" \
             --argjson boundary "$BOUNDARY" --argjson trunc "$truncated" '
  ( map(select(.most_recent_instance.ref == $ref))
    | map({rule: .rule.id,
           severity: (.rule.security_severity_level // "none"),
           tool: .tool.name,
           number: .number,
           age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
  | ($a | map(select(.age_days <= $boundary))) as $fresh
  | ($a | map(select(.age_days >  $boundary))) as $old
  | {critical: 4, high: 3, medium: 2, low: 1, none: 0} as $rank
  | { enabled: true, analyzed: true, truncated: $trunc,
      open: ($a | length),
      default_branch: $db,
      tools: ($a | map(.tool) | unique),
      new: ( $fresh | group_by(.rule) | map({
               rule: .[0].rule,
               severity: (max_by($rank[.severity]) | .severity),
               count: length,
               oldest_age_days: (map(.age_days) | max),
               alerts: (map(.number) | sort),
               autofix: null })
             | sort_by(-($rank[.severity])) ),
      inherited: {
        count: ($old | length),
        rules: ($old | map(.rule) | unique | length),
        oldest_age_days: (if ($old | length) == 0 then null else ($old | map(.age_days) | max) end),
        by_severity: {
          critical: ($old | map(select(.severity == "critical")) | length),
          high:     ($old | map(select(.severity == "high"))     | length),
          medium:   ($old | map(select(.severity == "medium"))   | length),
          low:      ($old | map(select(.severity == "low"))      | length) } } }
' <<<"$alerts")

# Autofix is probed ONLY for rules already ranked P0/P1 by severity. It can
# therefore only ever upgrade a P1 to P0; a medium rule is never probed and
# stays null. Probing all of velovate's 102 alerts would cost 102 calls to
# change nothing about how the mediums rank.
probe_rules=$(jq -r '.new[] | select(.severity == "critical" or .severity == "high") | "\(.rule)\t\(.alerts[0])"' <<<"$base")
while IFS=$'\t' read -r rule alert_no; do
    [ -z "$rule" ] && continue
    if fix=$(gh api "repos/${REPO}/code-scanning/alerts/${alert_no}/autofix" 2>&1); then
        status=$(jq -r '.status // "none"' <<<"$fix" 2>/dev/null)
        case "$status" in
            success) verdict="ready" ;;
            *)       verdict="none" ;;
        esac
    elif grep -qi 'not supported\|unprocessable' <<<"$fix"; then
        verdict="unsupported"
    else
        verdict="none"
    fi
    base=$(jq -c --arg r "$rule" --arg v "$verdict" \
        '.new = (.new | map(if .rule == $r then .autofix = $v else . end))' <<<"$base")
done <<<"$probe_rules"

jq -c '.' <<<"$base"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-scanning-states.sh`
Expected: PASS — `scanning-states tests: all green`. Sections 1–4 all report `ok`.

- [ ] **Step 5: Wire the gate into preflight**

In `scripts/preflight.sh`, add to the gate list in the header comment after the gate-18 entry:

```bash
#  19. scanning-states tests (scripts/test-scanning-states.sh) — the code- and
#      secret-scanning pulls' four silent failure modes: the 404 that means
#      BOTH "Advanced Security off" and "never analyzed" (collapsing them
#      reports a never-scanned repo as clean), the un-paginated read that
#      returns a capped 100 as if it were a measurement (live: velovate, true
#      count 102), a PR-ref alert counted as default-branch debt, and the
#      validity:"active" P0 rule acquiring an age gate. Mock gh only.
```

Then add the gate body immediately after the gate-15 `test-teardown-args.sh` block
(`scripts/preflight.sh:482-486`) and before the markdownlint gate:

```bash
# --- 19. scanning-states tests -----------------------------------------------
# Every failure mode here emits well-formed JSON carrying a plausible number, so
# nothing downstream can tell a wrong answer from a right one. Mock gh only: no
# repo, no network.
if bash scripts/test-scanning-states.sh; then
    pass "scanning-states tests (scripts/test-scanning-states.sh)"
else
    failed "scanning-states tests (scripts/test-scanning-states.sh)"
fi
```

- [ ] **Step 6: Document the scan in repo-health**

In `skills/repo-health/SKILL.md`, add after the `### Dependency exposure + remediation` section:

````markdown
### Code scanning (CodeQL and other SARIF uploads)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-code-scanning.sh
```

Emits JSON: `{enabled, analyzed, truncated, open, default_branch, tools, new, inherited}`.
`REPO` defaults to cwd.

**`analyzed` is not `enabled`.** The API answers 404 for both "Advanced Security is off" and "on,
but no analysis has ever run", and both produce `open: 0`. `analyzed: false` with `enabled: true`
is a repo that has never been scanned — a blind spot, not a clean bill of health. `enabled: null`
is a token-scope question, exactly as with Dependabot.

**`truncated: true` makes `open` a floor, not a count.** Report it as "at least N".

Alerts are filtered to the resolved default branch and clustered by rule, then split at 14 days:

| Condition | Tier |
|---|---|
| `new[]` rule, severity `critical` | **P0** — just shipped, fixable while the code is fresh |
| `new[]` rule with `autofix: "ready"` | **P0** — the `parked_green` shape: the fix exists and only a human press is missing |
| `new[]` rule, severity `high` | **P1** |
| `inherited` | **one debt line** — never enumerated, never in a top 5 |
| `analyzed: false` | not a finding — a **blind spot** row |

`autofix` is probed only for critical/high rules, so it can only upgrade a P1 to P0; a medium rule
is never probed and stays `null`.
````

- [ ] **Step 7: Verify the whole gate suite is green**

Run: `bash scripts/preflight.sh`
Expected: `preflight: all gates green`, including
`PASS  scanning-states tests (scripts/test-scanning-states.sh)`.

- [ ] **Step 8: Commit**

```bash
git add skills/repo-health/scripts/pull-code-scanning.sh scripts/test-scanning-states.sh \
        scripts/preflight.sh skills/repo-health/SKILL.md
git commit -m "feat(repo-health): add code-scanning pull with four-state enablement

The alerts API returns 404 for both 'Advanced Security off' and 'never
analyzed', and both produce open:0 — opposite findings. analyzed is a
separate field so a never-scanned repo cannot read as clean.

Paginates: a live probe of velovate returned exactly 100 against a true
102, and a capped count is indistinguishable from a measured one."
```

---

### Task 2: `pull-secret-scanning.sh`

**Files:**

- Create: `skills/repo-health/scripts/pull-secret-scanning.sh`
- Modify: `scripts/test-scanning-states.sh` (extend the mock and add section 5)
- Modify: `skills/repo-health/SKILL.md` (new `### Secret scanning` section)
- Modify: `skills/repo-health/references/scoring.md` (new thresholds section)

**Interfaces:**

- Consumes: nothing from Task 1; the two scripts are independent.
- Produces: `pull-secret-scanning.sh` emitting
  `{enabled, open, oldest_age_days, active[], unknown_validity[], inactive}` where `active[]` and
  `unknown_validity[]` entries are `{number, type, age_days, bypassed}`. Tasks 3–4 consume this
  shape by name.

- [ ] **Step 1: Extend the test with the failing secret-scanning assertions**

In `scripts/test-scanning-states.sh`, add `SECRET_SCRIPT` beside `CODE_SCRIPT` near the top:

```bash
SECRET_SCRIPT="skills/repo-health/scripts/pull-secret-scanning.sh"
```

Add this branch to the mock's `case "$path"` block, immediately before the `*/autofix)` arm:

```bash
  */secret-scanning/alerts*)
    case "$MOCK_MODE" in
      secrets-disabled)
        echo '{"message":"Secret scanning is disabled on this repository."}' >&2
        exit 1 ;;
      secrets-mixed)
        jq -nc '[
          {number: 1, secret_type_display_name: "Google API Key",
           created_at: ((now - (2 * 86400)) | todate),
           validity: "active", push_protection_bypassed: false},
          {number: 2, secret_type_display_name: "Azure Storage Account Access Key",
           created_at: ((now - (220 * 86400)) | todate),
           validity: "unknown", push_protection_bypassed: false},
          {number: 3, secret_type_display_name: "Stripe Webhook Signing Secret",
           created_at: ((now - (3 * 86400)) | todate),
           validity: "unknown", push_protection_bypassed: true},
          {number: 4, secret_type_display_name: "Rotated Token",
           created_at: ((now - (5 * 86400)) | todate),
           validity: "inactive", push_protection_bypassed: false}
        ]' ;;
      *) echo "mock gh: unknown MOCK_MODE: $MOCK_MODE" >&2; exit 1 ;;
    esac ;;
```

Add this runner beside `run_code`:

```bash
run_secret() { MOCK_MODE="$1" PATH="$WORK/bin:$PATH" REPO="mock-org/mock-repo" bash "$SECRET_SCRIPT"; }
```

Add sections 5 and 6 immediately before the final `[ "$fail" -eq 0 ]` line:

```bash
echo "5. secret-scanning classification" >&2

out=$(run_secret secrets-disabled)
[ "$(jq -r '.enabled' <<<"$out")" = "false" ] \
    && ok "secret scanning off  -> enabled:false" \
    || bad "secret scanning off  -> enabled:false (got $(jq -r '.enabled' <<<"$out"))"

out=$(run_secret secrets-mixed)
[ "$(jq -r '.active | length' <<<"$out")" = "1" ] \
    && ok "validity:active isolated into active[]" \
    || bad "validity:active isolated into active[] (got $(jq -c '.active' <<<"$out"))"
[ "$(jq -r '.active[0].age_days' <<<"$out")" = "2" ] \
    && ok "a 2-day-old live credential is still reported (no age floor)" \
    || bad "a 2-day-old live credential is still reported (got $(jq -c '.active' <<<"$out"))"
[ "$(jq -r '.unknown_validity | length' <<<"$out")" = "2" ] \
    && ok "unknown-validity alerts collected" \
    || bad "unknown-validity alerts collected (got $(jq -c '.unknown_validity' <<<"$out"))"
[ "$(jq -r '.inactive' <<<"$out")" = "1" ] \
    && ok "inactive counted, not listed" \
    || bad "inactive counted, not listed (got $(jq -r '.inactive' <<<"$out"))"
[ "$(jq -r '.oldest_age_days' <<<"$out")" = "220" ] \
    && ok "oldest_age_days spans every open alert" \
    || bad "oldest_age_days spans every open alert (got $(jq -r '.oldest_age_days' <<<"$out"))"
[ "$(jq -r '[.unknown_validity[] | select(.bypassed)] | length' <<<"$out")" = "1" ] \
    && ok "push_protection_bypassed carried through" \
    || bad "push_protection_bypassed carried through"

echo "6. source-level: the active-credential P0 rule carries no age gate" >&2

# Flattened, because this repo hard-wraps prose: a line-scoped grep for the
# forbidden shape turns a line wrap into a false PASS, and a must-NOT-exist
# assertion is exactly where that matters.
flat_health="$(tr -s '[:space:]' ' ' < skills/repo-health/SKILL.md)"
grep -qi 'validity == "active"[^|]*| \*\*P0\*\* on day zero' <<<"$flat_health" \
    && ok "SKILL.md states validity:active is P0 on day zero" \
    || bad "SKILL.md must state validity:active is P0 on day zero"
grep -qiE 'validity == "active"[^|]*\|[^|]*(>=|older than|after) *[0-9]+ *d' <<<"$flat_health" \
    && bad "the active-credential rule acquired an age gate — a live credential is P0 immediately" \
    || ok "the active-credential rule carries no age threshold"
```

- [ ] **Step 2: Run test to verify the new sections fail**

Run: `bash scripts/test-scanning-states.sh`
Expected: FAIL — sections 1–4 still pass; section 5 fails because
`skills/repo-health/scripts/pull-secret-scanning.sh` does not exist, and section 6 fails because
`SKILL.md` has no secret-scanning table yet.

- [ ] **Step 3: Write the implementation**

Create `skills/repo-health/scripts/pull-secret-scanning.sh`:

```bash
#!/usr/bin/env bash
# pull-secret-scanning.sh — one repo's committed-credential exposure, split by
# whether GitHub could VALIDATE the credential against its provider.
# Read-only. Emits a single JSON object on stdout.
#
# Env:
#   REPO       owner/name (default: inferred from cwd via gh)
#   PAGE_CAP   max 100-alert pages to read (default: 5)
#
# Output shape:
#   { "enabled": true|false|null, "open": N, "oldest_age_days": N|null,
#     "active": [ { "number", "type", "age_days", "bypassed" } ],
#     "unknown_validity": [ { "number", "type", "age_days", "bypassed" } ],
#     "inactive": N }
#
# WHY VALIDITY IS THE PRIMARY SPLIT AND AGE IS NOT: `validity: "active"` means
# GitHub checked the credential against the issuing provider and it answered.
# That is not a severity estimate, it is a live secret, and it is P0 the moment
# it appears — a two-hour-old active key is worse than a year-old unverified
# one. Ranking these by age, the way stuck work is ranked, would bury the only
# unambiguous finding this endpoint produces. Probed live on 2026-08-18:
# Sassy-Dog/velovate carried two Google API keys at validity "active".
#
# `unknown` is not "probably fine". It usually means GitHub cannot validate that
# provider's format at all, so it stays a finding and escalates once nobody has
# triaged it for a month. `inactive` is already rotated: counted, never listed.
#
# `enabled` is three-state for the same reason as the sibling pulls: a 403 that
# means "this token cannot see it" must never render as "the feature is off".
#
# Deliberately `set -uo pipefail` WITHOUT `-e`.
set -uo pipefail

PAGE_CAP="${PAGE_CAP:-5}"

command -v gh >/dev/null 2>&1 || { echo 'skipped: gh not on PATH' >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo 'skipped: jq not on PATH' >&2; exit 10; }

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
[ -z "$REPO" ] && { echo 'skipped: could not determine REPO (set REPO=owner/name)' >&2; exit 10; }

state_json() {
    jq -nc --argjson en "$1" \
        '{enabled: $en, open: null, oldest_age_days: null,
          active: [], unknown_validity: [], inactive: null}'
}

alerts='[]'
page=1
while [ "$page" -le "$PAGE_CAP" ]; do
    if ! resp=$(gh api "repos/${REPO}/secret-scanning/alerts?state=open&per_page=100&page=${page}" 2>&1); then
        if grep -qi 'secret scanning is disabled\|is disabled on this repository' <<<"$resp"; then
            state_json false; exit 0
        else
            state_json null; exit 0
        fi
    fi
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$resp" || { state_json null; exit 0; }
    count=$(jq 'length' <<<"$resp")
    alerts=$(jq -c --argjson a "$alerts" --argjson b "$resp" -n '$a + $b')
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
done

jq -c '
  ( map({number,
          type: .secret_type_display_name,
          validity: (.validity // "unknown"),
          bypassed: (.push_protection_bypassed // false),
          age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
  | { enabled: true,
      open: ($a | length),
      oldest_age_days: (if ($a | length) == 0 then null else ($a | map(.age_days) | max) end),
      active: ($a | map(select(.validity == "active"))
                  | map({number, type, age_days, bypassed}) | sort_by(.age_days)),
      unknown_validity: ($a | map(select(.validity == "unknown"))
                            | map({number, type, age_days, bypassed}) | sort_by(-.age_days)),
      inactive: ($a | map(select(.validity == "inactive")) | length) }
' <<<"$alerts"
```

- [ ] **Step 4: Document the scan and its ranking**

In `skills/repo-health/SKILL.md`, add after the `### Code scanning` section from Task 1:

````markdown
### Secret scanning

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/repo-health/scripts/pull-secret-scanning.sh
```

Emits JSON: `{enabled, open, oldest_age_days, active, unknown_validity, inactive}`. `REPO` defaults
to cwd.

| Condition | Tier |
|---|---|
| `validity == "active"` | **P0** on day zero — GitHub validated it against the provider; it is a live credential. No age math. |
| `bypassed == true` | **P0** — a human overrode push protection to commit it |
| `unknown_validity[]` entry with `age_days >= 30` | **P0** — unverified and untriaged for a month is itself the finding |
| `unknown_validity[]` entry with `age_days < 30` | **P1** — verify or dismiss |
| `inactive` | not a finding — already rotated; one line on the clean list |
| `enabled: false` | not a finding — a **blind spot** row |

`unknown` is not "probably fine" — it usually means GitHub cannot validate that provider's format
at all. Never rank an active credential by age; that buries the only unambiguous finding this
endpoint produces.
````

Add to `skills/repo-health/references/scoring.md`, after the Tech debt section:

```markdown
## Security scanning (`pull-code-scanning.sh`, `pull-secret-scanning.sh`)

| Signal | Severity |
|---|---|
| `active[]` non-empty, or any `bypassed: true` | P0 — a validated live credential, or push protection deliberately overridden |
| `unknown_validity[]` entry aged >= 30d | P0 — unverified and untriaged for a month |
| `unknown_validity[]` entry aged < 30d | P1 |
| `new[]` rule, severity `critical`, or `autofix: "ready"` | P0 |
| `new[]` rule, severity `high` | P1 |
| `inherited.count > 0` | one debt line; never enumerated, never in a top 5 |
| `analyzed == false`, or either `enabled == false` | blind spot, not a finding |
| `enabled == null` | token-scope question; never report as "disabled" |

`truncated: true` makes `open` a floor. Report it as "at least N", never as a count.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/test-scanning-states.sh`
Expected: PASS — all six sections `ok`, `scanning-states tests: all green`.

- [ ] **Step 6: Verify the whole gate suite**

Run: `bash scripts/preflight.sh`
Expected: `preflight: all gates green`. Shellcheck must be clean on both new scripts.

- [ ] **Step 7: Commit**

```bash
git add skills/repo-health/scripts/pull-secret-scanning.sh scripts/test-scanning-states.sh \
        skills/repo-health/SKILL.md skills/repo-health/references/scoring.md
git commit -m "feat(repo-health): add secret-scanning pull ranked by validity, not age

validity:active means GitHub checked the credential against its provider
and it answered — a live secret, P0 the moment it appears. Ranking these
by age would bury the only unambiguous finding the endpoint produces."
```

---

### Task 3: `survey-work` consumes the Security surface

**Files:**

- Modify: `skills/survey-work/SKILL.md` — frontmatter description; `:150-158` (§3C);
  `:237-239` (§5 dependency block); `:274-275` (§6 template)

**Interfaces:**

- Consumes: both scripts' JSON contracts from Tasks 1–2, by field name, as prose instructions.
- Produces: a `## 🔒 Security` section in the rendered plate.

- [ ] **Step 1: Add the two scans to §3C**

In `skills/survey-work/SKILL.md`, in the `### C. Tech debt + dev experience` bullet list, after the
`dependency exposure + remediation` line (`:158`):

```markdown
- code scanning and secret scanning (no environment needed; both default to cwd). `analyzed: false`
  or `enabled: false` is a **blind spot** row, never a clean line; `enabled: null` is a token-scope
  question. `truncated: true` makes `open` a floor — report "at least N".
```

- [ ] **Step 2: Move the dependency ranking into a Security block in §5**

Replace the sentence at `:239` that reads `A parked_green PR aged ≥3 days is **P0** and belongs
under Dev experience with its number and merge command.` with:

```markdown
A `parked_green` PR aged ≥3 days is **P0** and belongs under **Security** with its number and merge
command.
```

Then rename the `**Dependency exposure**:` lead-in at `:237` to `**Security — dependency
exposure**:` and add immediately after that paragraph:

```markdown
**Security — code scanning**: rank rule-clustered, never per alert. A rule whose newest alert is
≤14 days old is `new[]`: **P0** at `critical` or with `autofix: "ready"` (the fix exists and only a
human press is missing), **P1** at `high`. Everything older is `inherited` — ONE debt line naming
the rule count and the oldest age, never enumerated and never in the top 5. A flat severity ranking
here reproduces exactly the wall-of-findings problem the dependency rule above exists to prevent.

**Security — secret scanning**: `validity: "active"` is **P0 on day zero** — GitHub validated the
credential against its provider, so it is live and no age math applies. A `bypassed: true` alert is
**P0**: a human overrode push protection to commit it. `unknown` validity is **P1**, escalating to
**P0** at 30 days, because unverified and untriaged for a month is itself the finding. `inactive`
is already rotated — one token on the clean line.
```

- [ ] **Step 3: Add the section to the §6 output template**

In the fenced template, insert between the `## 🎯 Backlog priorities` block and `## 🧹 Tech debt`
(`:274`):

```markdown
## 🔒 Security (P0: N · P1: N)
### P0
- **<rule or credential type>** — <one-line why>
  - Evidence: <alert numbers> · <validity or severity> · open <N>d
  - Fix: <merge command, autofix note, or "rotate and revoke">
_Inherited: N alerts across M rules, oldest Dd — debt, not a plate item._
```

Security sits **after Customer pain and before Backlog**: exposure outranks planned work, and does
not outrank a live customer-facing crash. Remove dependency-exposure items from
`## 🛠 Dev experience`, which keeps CI duration and flake only.

- [ ] **Step 4: Extend the frontmatter description**

Change the `dev experience (CI duration/flake, dependency exposure)` fragment to:

```text
security exposure (code scanning, secret scanning, dependency alerts), dev experience (CI
duration/flake)
```

and add these trigger phrases to the quoted list: `"any leaked secrets"`, `"what's our security
exposure"`.

Verify the budget — the cap is 1024 and this file was at 802:

```bash
sed -n '/^---$/,/^---$/p' skills/survey-work/SKILL.md \
  | sed -n '/^description:/,/^[a-z_-]*:/p' | tr -s '[:space:]' ' ' | wc -c
```

Expected: a number below 1024.

- [ ] **Step 5: Verify**

Run: `bash scripts/preflight.sh`
Expected: `preflight: all gates green` — in particular the frontmatter gate (description length)
and the positional-token gate (no bare `$1`–`$9` introduced in the new prose).

- [ ] **Step 6: Commit**

```bash
git add skills/survey-work/SKILL.md
git commit -m "feat(survey-work): give security exposure its own section

Code scanning and secret scanning join the plate, and the Dependabot
remediation ranking moves out of Dev experience to sit with them. Dev
experience keeps CI duration and flake."
```

---

### Task 4: `whats-on-fire` consumes the Security surface org-wide

**Files:**

- Modify: `skills/whats-on-fire/scripts/pull-repo-signals.sh` (output-shape comment, cost comment,
  per-repo pulls, assembly)
- Modify: `skills/whats-on-fire/SKILL.md` — frontmatter description; `### C. Blind spots`;
  `:221` (§5 template)
- Modify: `skills/whats-on-fire/references/scoring.md` (`:44`, `:54`, `:99-100`)
- Modify: `skills/whats-on-fire/references/cloud-fallback.md` (`:189`, `:198`, `:202`)

**Interfaces:**

- Consumes: the same two JSON contracts, reimplemented inline in `pull-repo-signals.sh` for the
  org loop (the per-repo scripts are not called from it — it already inlines the Dependabot pull
  the same way).
- Produces: `repos[].code_scanning` and `repos[].secret_scanning` objects.

- [ ] **Step 1: Extend the script's documented output shape and cost**

In `skills/whats-on-fire/scripts/pull-repo-signals.sh`, add to the `# Output shape:`
block after the `dependabot` line:

```bash
#                  # NOTE: a deliberately REDUCED projection of what
#                  # pull-code-scanning.sh emits. The org sweep routes to a
#                  # repo; it does not triage inside one, so per-alert numbers
#                  # and inherited.by_severity are not carried. Do not assume
#                  # field parity with the per-repo script.
#                  "code_scanning": { "enabled": true|false|null,
#                                     "analyzed": true|false|null, "truncated",
#                                     "open",
#                                     "new": [ { "rule", "severity", "count",
#                                                "oldest_age_days" } ],
#                                     "inherited": { "count", "rules",
#                                                    "oldest_age_days" } },
#                  "secret_scanning": { "enabled": true|false|null, "open",
#                                       "active": [...], "unknown_validity": [...] } } ] }
```

Replace the cost sentence `Cost is 1 + 2N calls, plus ONE extra per repo that actually has
high/critical alerts (for its open Dependabot PRs).` with:

```bash
# Cost is 1 + 4N calls, plus ONE extra per repo with high/critical Dependabot
# alerts (its fix PRs), plus one page per 100 code-scanning alerts beyond the
# first. A healthy org pays nothing for the conditional calls. Keep RUN_LIMIT
# small — this is a triage sweep, not a security analytics pass.
```

- [ ] **Step 2: Add the two per-repo pulls**

In the per-repo loop, after the block that assembles `dependabot`, add:

```bash
  # Code scanning. The 404 is ambiguous by design — see pull-code-scanning.sh.
  code_scanning='{"enabled":null,"analyzed":null,"truncated":false,"open":null,"new":[],"inherited":null}'
  if cs=$(gh api "repos/${ORG}/${repo}/code-scanning/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cs"; then
      code_scanning=$(jq -c --arg ref "refs/heads/${default_branch}" '
        ( map(select(.most_recent_instance.ref == $ref))
          | map({rule: .rule.id,
                 severity: (.rule.security_severity_level // "none"),
                 age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
        | {critical: 4, high: 3, medium: 2, low: 1, none: 0} as $rank
        | { enabled: true, analyzed: true,
            truncated: (($a | length) >= 100),
            open: ($a | length),
            new: ( $a | map(select(.age_days <= 14)) | group_by(.rule)
                   | map({rule: .[0].rule,
                          severity: (max_by($rank[.severity]) | .severity),
                          count: length,
                          oldest_age_days: (map(.age_days) | max)}) ),
            inherited: { count: ($a | map(select(.age_days > 14)) | length),
                         rules: ($a | map(select(.age_days > 14)) | map(.rule) | unique | length),
                         oldest_age_days: (if ($a | length) == 0 then null
                                           else ($a | map(.age_days) | max) end) } }' <<<"$cs")
    fi
  elif grep -qi 'advanced security must be enabled\|code scanning is not enabled' <<<"$cs"; then
    code_scanning='{"enabled":false,"analyzed":false,"truncated":false,"open":null,"new":[],"inherited":null}'
  elif grep -qi 'no analysis found' <<<"$cs"; then
    code_scanning='{"enabled":true,"analyzed":false,"truncated":false,"open":null,"new":[],"inherited":null}'
  fi

  # Secret scanning. validity is the split; age never outranks a live credential.
  secret_scanning='{"enabled":null,"open":null,"active":[],"unknown_validity":[]}'
  if ss=$(gh api "repos/${ORG}/${repo}/secret-scanning/alerts?state=open&per_page=100" 2>&1); then
    if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$ss"; then
      secret_scanning=$(jq -c '
        ( map({number,
               type: .secret_type_display_name,
               validity: (.validity // "unknown"),
               bypassed: (.push_protection_bypassed // false),
               age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}) ) as $a
        | { enabled: true, open: ($a | length),
            active: ($a | map(select(.validity == "active")) | map({number, type, age_days, bypassed})),
            unknown_validity: ($a | map(select(.validity == "unknown"))
                                  | map({number, type, age_days, bypassed})) }' <<<"$ss")
    fi
  elif grep -qi 'secret scanning is disabled\|is disabled on this repository' <<<"$ss"; then
    secret_scanning='{"enabled":false,"open":null,"active":[],"unknown_validity":[]}'
  fi
```

Then add both to the final per-repo `jq -n` assembly, alongside `--argjson dependabot`:

```bash
    --argjson code_scanning "$code_scanning" \
    --argjson secret_scanning "$secret_scanning" \
```

and inside the object, after `dependabot: $dependabot`:

```bash
          code_scanning: $code_scanning,
          secret_scanning: $secret_scanning
```

- [ ] **Step 3: Refuse to count alerts against a GUESSED default branch**

`pull-repo-signals.sh:76` falls back to `default_branch="main"` when the roster lookup fails. That
fallback predates this change and is harmless for the CI fields, but the ref filter added in Step 2
depends on the branch name being *correct*: against a repo whose default branch is `master`, a
guessed `main` matches no alert at all, yielding `open: 0` — a silently clean repo. That is the
exact failure mode this whole surface exists to prevent, arriving through the back door.

Record whether the branch was resolved or guessed, immediately after line 76:

```bash
  # Track provenance: a GUESSED branch cannot support the ref filter below.
  default_branch_resolved=true
  if [ -z "$(jq -r --arg r "$repo" '.[] | select(.name == $r) | .defaultBranchRef.name // empty' <<<"$roster")" ]; then
    default_branch_resolved=false
  fi
```

Then guard the code-scanning pull added in Step 2 by wrapping its assignment:

```bash
  if [ "$default_branch_resolved" != "true" ]; then
    # Unknown branch means an unusable ref filter. Unknown is not clean.
    code_scanning='{"enabled":null,"analyzed":null,"truncated":false,"open":null,"new":[],"inherited":null}'
  elif cs=$(gh api "repos/${ORG}/${repo}/code-scanning/alerts?state=open&per_page=100" 2>&1); then
```

(the remaining arms of the `if` chain from Step 2 are unchanged).

Secret scanning needs no such guard — it carries no ref, so a guessed branch cannot affect it.

- [ ] **Step 4: Add the report section and the blind-spot rows**

In `skills/whats-on-fire/SKILL.md`, in the §5 template, insert before `## 🚧 Stuck shipping`
(`:221`):

```markdown
## 🔒 Security exposure (P0: N · P1: N)
### P0
- **<product> — <credential type or rule>** — <repo>
  - Evidence: <alert numbers> · <validity or severity> · open <N>d
  - Fix: <rotate and revoke | merge PR #N | autofix ready>
_Inherited: <repo> N alerts across M rules, oldest Dd._
```

P0 security items are **not** duplicated into Production fires. The cross-product top 5 is where
urgency gets expressed; this skill's existing rule is that semantically distinct signals stay in
separate fields rather than merging into false alarms.

In `### C. Blind spots`, add after the two Dependabot bullets:

```markdown
- `code_scanning.enabled == false` → code scanning disabled. `analyzed == false` with
  `enabled == true` → **enabled but never analyzed**, which is a different row: the workflow exists
  or the feature is on, and no scan has ever produced a result. Both render `open: 0`, so reporting
  either as clean is the failure this row exists to prevent. `enabled == null` → token scope.
- `secret_scanning.enabled == false` → secret scanning disabled. `enabled == null` → token scope.
```

- [ ] **Step 5: Add the scoring rows**

In `skills/whats-on-fire/references/scoring.md`, add to the P0 table (after `:44`):

```markdown
| Secret scanning | any `active[]` entry, or any `bypassed: true` |
| Secret scanning | `unknown_validity[]` entry aged >= 30d |
| Code scanning | `new[]` rule at `critical` |
```

to the P1 table (after `:54`):

```markdown
| Secret scanning | `unknown_validity[]` entry aged < 30d |
| Code scanning | `new[]` rule at `high` |
```

and to the blind-spot table (after `:100`):

```markdown
| Code scanning disabled | `code_scanning.enabled == false` |
| Code scanning never analyzed | `code_scanning.analyzed == false` with `enabled == true` — a scan has never produced a result; `open: 0` here is not a clean bill of health |
| Code scanning visibility unknown | `code_scanning.enabled == null` — token scope, not a repo setting |
| Secret scanning disabled | `secret_scanning.enabled == false` |
| Secret scanning visibility unknown | `secret_scanning.enabled == null` — token scope, not a repo setting |
```

- [ ] **Step 6: Extend the MCP-fallback skip**

In `skills/whats-on-fire/references/cloud-fallback.md`, add two rows beside the `dependabot` row at
`:189`:

```markdown
| `code_scanning` | **Unverified — see below.** |
| `secret_scanning` | **Unverified — see below.** |
```

and add after the Dependabot "Unreachable" subsection:

```markdown
## Unverified: the code- and secret-scanning surfaces

Whether the session's GitHub MCP surface exposes code-scanning or secret-scanning capabilities has
not been established. Until it is, treat both as unreachable and render them as named skips beside
Dependabot's — an approximation would be worse, because the blind-spot rows these feed are
specifically about distinguishing "no alerts" from "never scanned".

Settle it with `Sassy-Dog/velovate` as the positive control: on 2026-08-18 it carried 102 open
code-scanning alerts and 4 open secret-scanning alerts. An empty result there means the capability
is absent — no other reading survives. Record the answer as a Container fact, not a per-run probe.
```

Update the sources-line example at `:202` to name all three skips.

- [ ] **Step 7: Trim and extend the frontmatter description**

This description is at 933 of 1024 characters — 91 free. Add `"any leaked secrets"` and
`"security exposure"` to the trigger list, and recover the space by condensing the existing
`"what's broken across our products"` / `"are any of our products broken"` pair into
`"what's broken across our products"` alone.

Verify:

```bash
sed -n '/^---$/,/^---$/p' skills/whats-on-fire/SKILL.md \
  | sed -n '/^description:/,/^[a-z_-]*:/p' | tr -s '[:space:]' ' ' | wc -c
```

Expected: below 1024.

- [ ] **Step 8: Verify**

Run: `bash scripts/preflight.sh`
Expected: `preflight: all gates green`. Shellcheck must be clean on the modified
`pull-repo-signals.sh`.

- [ ] **Step 9: Commit**

```bash
git add skills/whats-on-fire/
git commit -m "feat(whats-on-fire): sweep code and secret scanning org-wide

Adds both per-repo pulls, a Security exposure report section, blind-spot
rows that distinguish 'never analyzed' from 'clean', and a named skip for
the MCP fallback until the capability probe settles it."
```

---

### Task 5: Repo documentation and release

**Files:**

- Modify: `CLAUDE.md` (the `repo-health` capability description and the preflight gate list)
- Modify: `.claude-plugin/plugin.json` (via `scripts/stamp-version.sh` — never by hand)

- [ ] **Step 1: Update CLAUDE.md**

In the "Workflow skills are thin and delegate" bullet, change the `repo-health` parenthetical from
`(TODO/CI/lag scans)` to `(TODO/CI/lag scans, and the three security-exposure pulls: Dependabot,
code scanning, secret scanning)`.

Add to the CI gate inventory in the opening paragraph, after the visibility-precondition tests
clause:

```markdown
the scanning-states tests (`scripts/test-scanning-states.sh` — the code- and secret-scanning pulls'
four silent failure modes: the 404 that means BOTH "Advanced Security off" and "never analyzed"
(collapsing them reports a never-scanned repo as clean), the un-paginated read that returns a
capped 100 as though it were a measurement (probed live: `velovate`, true count 102), a PR-ref
alert counted as default-branch debt, and the `validity: "active"` P0 rule acquiring an age gate —
asserted source-level against a whitespace-flattened copy, mock `gh` only, no network),
```

- [ ] **Step 2: Verify the full suite one last time**

Run: `bash scripts/preflight.sh`
Expected: `preflight: all gates green`.

- [ ] **Step 3: Stamp the version**

```bash
bash scripts/stamp-version.sh
```

Expected: `.claude-plugin/plugin.json` gains a CalVer `YYYY.M.<commits-this-month>` version. Never
hand-edit it.

- [ ] **Step 4: Commit and open the PR**

```bash
git add CLAUDE.md .claude-plugin/plugin.json
git commit -m "chore(release): stamp plugin version for the security scanning surface"
git push -u origin HEAD
gh pr create --title "feat: security scanning surface (code + secret scanning)" --body "$(cat <<'BODY'
## What

Adds GitHub code scanning and secret scanning as a first-class `## 🔒 Security`
surface across `repo-health`, `survey-work`, and `whats-on-fire`, and moves the
existing Dependabot remediation ranking out of Dev experience to sit with them.

## Why

Neither prioritization skill consulted either endpoint. A live probe on
2026-08-18 found what the surface would have been reporting: two Google API keys
at `validity: active` in one repo, and seven Azure application secrets open in
another since 2026-01-04.

## Design decisions worth reviewing

- `analyzed` is a **separate field** from `enabled`. The alerts API returns 404
  for both "Advanced Security off" and "never analyzed"; both yield `open: 0`
  and they are opposite findings.
- Reads are **paginated**. An un-paginated `per_page=100` read of `velovate`
  returned exactly 100 against a true 102.
- CodeQL alerts rank **rule-clustered and split at 14 days**, not per alert. A
  flat ranking of 74 mediums is the wall-of-findings problem the Dependabot
  ranking already exists to prevent.
- Secret alerts rank by **validity, never age**. `validity: active` is P0 on day
  zero.

## Not in this PR

Part 3 of the spec (`sassydog-routines`) is deliberately excluded. That repo
carries a separate cloud implementation with no `gh` CLI, and its work is
blocked on a GitHub MCP capability probe that cannot run locally. It lands as
its own plan.

## Verification

`bash scripts/preflight.sh` — all gates green, including new gate 19.
BODY
)"
```

---

## Follow-on work, not in this plan

1. **The MCP capability probe** — cloud environment, `Sassy-Dog/velovate` as positive control.
   Settles Branch A vs B for `sassydog-routines`.
2. **PR 2 (`sassydog-routines`)** — its own plan, written once the probe resolves. Different
   toolchain (Python reducers, bats), different CI, not verifiable locally.
3. **Rollout issues** — one per consumer repo carrying a `## scoring-overrides` section that
   references the old Dev-experience placement of dependency exposure. Filed per repo, never swept.
4. **The reciprocal pointer comments** the spec's risk section commits to — each tier table naming
   its counterpart in the other repo. The `sassydog-skills` half cannot be written until PR 2
   settles what the routines-side table looks like, so both halves land with PR 2. Until then the
   duplication is undocumented in-file, which the spec's risk section records.
5. **The live findings** — `velovate`'s two active Google API keys and `platform`'s seven
   Azure secrets open since 2026-01-04. Those belong in their own repos' issues and are explicitly
   out of scope here.
