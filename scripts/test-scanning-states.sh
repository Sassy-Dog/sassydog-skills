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
SECRET_SCRIPT="skills/repo-health/scripts/pull-secret-scanning.sh"

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
  # The autofix arm MUST precede the alerts arm: an autofix path is
  # .../code-scanning/alerts/<n>/autofix, which the alerts glob also matches,
  # so the reverse order makes this arm unreachable and every probe returns a
  # page of alerts instead of a 404.
  */autofix)
    # Only MOCK_MODE=autofix hands back distinguishable per-alert responses;
    # every other mode's probe (triggered incidentally by a fresh critical/high
    # rule) gets the same generic 404 the real API returns for an unprobed repo.
    if [ "$MOCK_MODE" = "autofix" ]; then
        alert_no="${path%/autofix}"; alert_no="${alert_no##*/}"
        case "$alert_no" in
            50) echo '{"status":"success"}'; exit 0 ;;
            60) echo '{"message":"Not supported for this alert type"}' >&2; exit 1 ;;
        esac
    fi
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
      capped)
        # Every page — including the PAGE_CAP'th — comes back exactly 100. The
        # short-page break condition never fires, so the only way the loop can
        # end is by hitting PAGE_CAP itself: this is the one shape that can
        # actually exercise `truncated=true`.
        jq -nc '[range(100) | {
            number: (. + 1),
            created_at: ((now - (200 * 86400)) | todate),
            rule: {id: "js/xss", security_severity_level: "high"},
            tool: {name: "CodeQL"},
            most_recent_instance: {ref: "refs/heads/main"}
          }]' ;;
      autofix)
        # Three fresh (age <= BOUNDARY) rules, one per severity that matters to
        # the probe gate: critical and high get probed (see the */autofix arm
        # above for alert numbers 50 and 60), medium does not and must stay
        # unprobed — proving the "ONLY critical/high" gate rather than just
        # asserting the docstring's claim about it.
        jq -nc '[
          {number: 50, created_at: ((now - (2 * 86400)) | todate),
           rule: {id: "js/sql-injection", security_severity_level: "critical"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}},
          {number: 60, created_at: ((now - (2 * 86400)) | todate),
           rule: {id: "js/xss", security_severity_level: "high"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}},
          {number: 70, created_at: ((now - (2 * 86400)) | todate),
           rule: {id: "js/weak-hash", security_severity_level: "medium"},
           tool: {name: "CodeQL"},
           most_recent_instance: {ref: "refs/heads/main"}}
        ]' ;;
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
run_secret() { MOCK_MODE="$1" PATH="$WORK/bin:$PATH" REPO="mock-org/mock-repo" bash "$SECRET_SCRIPT"; }

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

out=$(run_code capped)
[ "$(jq -r '.truncated' <<<"$out")" = "true" ] \
    && ok "PAGE_CAP full pages -> truncated:true" \
    || bad "PAGE_CAP full pages -> truncated:true (got $(jq -r '.truncated' <<<"$out"))"
[ "$(jq -r '.open' <<<"$out")" = "500" ] \
    && ok "a capped read reports the floor (open=500), not a guess" \
    || bad "a capped read reports the floor (expected open=500, got $(jq -r '.open' <<<"$out"))"

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

echo "5. autofix probe scoping" >&2

out=$(run_code autofix)
[ "$(jq -r '.new[] | select(.rule=="js/sql-injection") | .autofix' <<<"$out")" = "ready" ] \
    && ok "critical rule, successful autofix probe -> ready" \
    || bad "critical rule, successful autofix probe -> ready (got $(jq -c '.new' <<<"$out"))"
[ "$(jq -r '.new[] | select(.rule=="js/xss") | .autofix' <<<"$out")" = "unsupported" ] \
    && ok "high rule, autofix probe 422s -> unsupported" \
    || bad "high rule, autofix probe 422s -> unsupported (got $(jq -c '.new' <<<"$out"))"
[ "$(jq -r '.new[] | select(.rule=="js/weak-hash") | .autofix' <<<"$out")" = "null" ] \
    && ok "medium rule is never probed -> autofix stays null" \
    || bad "medium rule is never probed -> autofix stays null (got $(jq -c '.new' <<<"$out"))"

echo "6. secret-scanning classification" >&2

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
[ "$(jq -r '[.active[], .unknown_validity[]] | map(.number) | index(4) // "absent"' <<<"$out")" = "absent" ] \
    && ok "the inactive alert (number 4) never appears in active[] or unknown_validity[]" \
    || bad "the inactive alert (number 4) leaked into a listed array"
[ "$(jq -r '.oldest_age_days' <<<"$out")" = "220" ] \
    && ok "oldest_age_days spans every open alert" \
    || bad "oldest_age_days spans every open alert (got $(jq -r '.oldest_age_days' <<<"$out"))"
[ "$(jq -r '[.unknown_validity[] | select(.bypassed)] | length' <<<"$out")" = "1" ] \
    && ok "push_protection_bypassed carried through" \
    || bad "push_protection_bypassed carried through"

echo "7. source-level: the active-credential P0 rule carries no age gate" >&2

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

[ "$fail" -eq 0 ] || { echo "scanning-states tests: FAILED" >&2; exit 1; }
echo "scanning-states tests: all green" >&2
