#!/usr/bin/env bash
# test-versioning.sh — the spec-mandated versioning tests (org Versioning
# spec v1.0 §3: floor, month-roll reset, collision replay, idempotent re-run),
# adapted to this repo's committed-manifest model (§7).
#
# Runs against a throwaway fixture git repo in mktemp so results never depend
# on this repo's live history. Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-versioning.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-versioning: not in a git repo" >&2; exit 1; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP  versioning tests (jq not installed — CI still enforces)" >&2
    exit 0
fi

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

fail=0
ok() { echo "  ok    $1" >&2; }
bad() { echo "  FAIL  $1" >&2; fail=1; }

# assert_eq <label> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — expected '$2', got '$3'"; fi
}

# --- fixture: scripts + manifests + dated commits ----------------------------
mkdir -p "$FIXTURE/scripts" "$FIXTURE/.claude-plugin"
cp "$REPO_ROOT/scripts/get-version-info.sh" "$REPO_ROOT/scripts/stamp-version.sh" "$FIXTURE/scripts/"
cat > "$FIXTURE/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "fixture-plugin",
  "version": "0.11.0"
}
EOF
cat > "$FIXTURE/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "fixture-marketplace",
  "plugins": [
    { "name": "fixture-plugin", "version": "0.11.0" },
    { "name": "versionless-plugin" }
  ]
}
EOF

git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config commit.gpgsign false
commit() { # commit <iso-date> <msg>
    GIT_AUTHOR_DATE="$1T12:00:00Z" GIT_COMMITTER_DATE="$1T12:00:00Z" \
        git -C "$FIXTURE" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"
}
git -C "$FIXTURE" add -A
commit 2026-06-15 "june commit"
commit 2026-07-03 "july commit 1"
commit 2026-07-05 "july commit 2"

gvi() { (cd "$FIXTURE" && bash scripts/get-version-info.sh); }
stamp() { (cd "$FIXTURE" && bash scripts/stamp-version.sh "$@"); }
manifest_version() { jq -r '.version' "$FIXTURE/.claude-plugin/plugin.json"; }
set_manifest_version() {
    jq --arg v "$1" '.version = $v' "$FIXTURE/.claude-plugin/plugin.json" \
        > "$FIXTURE/.claude-plugin/plugin.json.tmp"
    mv "$FIXTURE/.claude-plugin/plugin.json.tmp" "$FIXTURE/.claude-plugin/plugin.json"
}

echo "versioning tests (fixture: $FIXTURE)" >&2

# --- get-version-info.sh ------------------------------------------------------
assert_eq "monthly patch counts this month's commits (non-padded month)" \
    "2026.7.2" "$(VERSION_DATE_OVERRIDE=2026-07-10 gvi)"

assert_eq "month-roll reset + floor: new month with no commits -> .1" \
    "2026.8.1" "$(VERSION_DATE_OVERRIDE=2026-08-02 gvi)"

assert_eq "idempotent re-run: same inputs -> same version" \
    "$(VERSION_DATE_OVERRIDE=2026-07-10 gvi)" "$(VERSION_DATE_OVERRIDE=2026-07-10 gvi)"

assert_eq "MARKETING_VERSION pin is emitted verbatim" \
    "2026.9.5" "$(MARKETING_VERSION=2026.9.5 gvi)"

assert_eq "VERSION_PATCH_OVERRIDE test seam" \
    "2026.7.7" "$(VERSION_DATE_OVERRIDE=2026-07-10 VERSION_PATCH_OVERRIDE=7 gvi)"

# --- stamp-version.sh: the §4 ladder against the committed manifest ----------
out=$(VERSION_DATE_OVERRIDE=2026-07-10 stamp)
assert_eq "first stamp (the semver->CalVer ratchet): action" \
    "version=2026.7.2
action=stamp" "$out"
assert_eq "first stamp wrote plugin.json" "2026.7.2" "$(manifest_version)"
assert_eq "first stamp wrote marketplace.json plugins[].version identically" \
    "2026.7.2" \
    "$(jq -r '.plugins[0].version' "$FIXTURE/.claude-plugin/marketplace.json")"
assert_eq "versionless marketplace entry left untouched" \
    "false" \
    "$(jq '.plugins[1] | has("version")' "$FIXTURE/.claude-plugin/marketplace.json")"

out=$(VERSION_DATE_OVERRIDE=2026-07-10 stamp)
assert_eq "re-stamp same state: reuse, no write" \
    "version=2026.7.2
action=reuse" "$out"

# Collision replay (§3/§4): committed value already at-or-above the computed
# candidate in the same train (stale checkout / floor collision) -> bump.
set_manifest_version "2026.7.5"
out=$(VERSION_DATE_OVERRIDE=2026-07-10 VERSION_PATCH_OVERRIDE=2 stamp)
assert_eq "collision: committed 2026.7.5 vs computed 2026.7.2 -> bump to .6" \
    "version=2026.7.6
action=stamp" "$out"
assert_eq "collision bump written to plugin.json" "2026.7.6" "$(manifest_version)"

# Backwards month: committed manifest from a later month -> fail closed.
set_manifest_version "2026.9.1"
if out=$(VERSION_DATE_OVERRIDE=2026-07-10 stamp 2>/dev/null); then
    bad "backwards-month stamp should fail closed (got: $out)"
else
    ok "backwards-month stamp fails closed"
fi
assert_eq "failed stamp leaves the manifest untouched" "2026.9.1" "$(manifest_version)"

# Ratchet: a non-CalVer pin is refused.
set_manifest_version "2026.7.6"
if out=$(MARKETING_VERSION=1.2.3 stamp 2>/dev/null); then
    bad "non-CalVer pin should be refused (ratchet) (got: $out)"
else
    ok "non-CalVer pin refused (ratchet)"
fi

# Pins are never auto-bumped: a pin at/below the committed value fails.
if out=$(MARKETING_VERSION=2026.7.4 stamp 2>/dev/null); then
    bad "pin below committed value should fail, never auto-bump (got: $out)"
else
    ok "pin below committed value fails (never auto-bumped)"
fi

# Dry run: reports but never writes.
out=$(VERSION_DATE_OVERRIDE=2026-08-02 stamp --dry-run)
assert_eq "dry run resolves (month-roll floor)" \
    "version=2026.8.1
action=stamp" "$out"
assert_eq "dry run does not write" "2026.7.6" "$(manifest_version)"

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "versioning tests: all green" >&2
    exit 0
else
    echo "versioning tests: FAILURES above" >&2
    exit 1
fi
