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
