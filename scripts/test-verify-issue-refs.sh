#!/usr/bin/env bash
# test-verify-issue-refs.sh — proves the grooming-drift checker on the
# reference shapes that actually shipped past review in a production drain,
# and on the false-positive shape that made a correct issue unpromotable (#199).
#
# Provenance: the shapes are real, the fixture tree is synthetic. Each case
# below is a de-identified reduction of a body that reached the Ready column of
# Sassy-Dog/solador and sent a worktree agent looking for something that was not
# there. A real checkout cannot be a fixture here — this repo has no Rust tree,
# and pinning one would couple these tests to another repo's refactors, which is
# the very coupling the checker exists to detect.
#
# The load-bearing assertions are the NEGATIVE ones. A checker that flags
# everything is trivially "correct" on drift and useless in practice, because it
# gets muted within a day. So the clean-body case and the new-subtree case are
# what actually keep this honest: they must stay quiet while the drift cases
# fire.
#
# Guarded here rather than left to review because two of these failure modes are
# SILENT. `\b` in a git -E pattern harvests zero symbols and every lookup then
# returns "no near match", so the checker keeps running, keeps exiting 0, and
# has simply stopped working. Nothing about its output says so.
#
# Wired into scripts/preflight.sh; run directly:
#   bash scripts/test-verify-issue-refs.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$REPO_ROOT" ] && { echo "test-verify-issue-refs: not in a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || exit 1

SCRIPT="skills/github-issues/scripts/verify-issue-refs.sh"
[ -f "$SCRIPT" ] || { echo "test-verify-issue-refs: $SCRIPT missing" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "skipped: python3 not installed" >&2; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# --- the fixture tree -------------------------------------------------------
# Shaped to make each rule distinguishable from the others:
#   crates/store/src/lib.rs   a real file, with a real `open_in` method
#   crates/store/Cargo.toml   a package whose name carries the org prefix
#   app/src-tauri/src/        a real directory holding github.rs and nothing
#                             resembling repos.rs — so a near-match sibling and
#                             a bare "the directory exists" are separable
#   app/ui/                   a real directory holding one `sample-*-stale.json`
#                             fixture, the solador #338 shape: a second one
#                             beside it IS a near match by name and must still
#                             not gate when it arrives via `touches:`
TREE="$WORK/tree"
mkdir -p "$TREE/crates/store/src" "$TREE/app/src-tauri/src" "$TREE/app/ui"
cat > "$TREE/crates/store/src/lib.rs" <<'RS'
pub struct Store {}
impl Store {
    pub fn open() -> Self { Self {} }
    pub fn open_in(dir: &str, flag: bool) -> Self { let _ = (dir, flag); Self {} }
}
RS
cat > "$TREE/crates/store/Cargo.toml" <<'TOML'
[package]
name = "solador-store"
version = "0.1.0"
TOML
cat > "$TREE/app/src-tauri/src/github.rs" <<'RS'
pub fn repos_view() -> u8 { 0 }
pub fn runners_view() -> u8 { 0 }
RS
echo "body { color: #fff; }" > "$TREE/app/ui/app.css"
echo '{"stale": true}' > "$TREE/app/ui/sample-azure-stale.json"
( cd "$TREE" && git init -q . && git add -A && \
  git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

# Sets OUT and RC in the CALLER's scope. Deliberately not `RC=$(run ...)`: a
# command substitution runs in a subshell, so OUT would never escape it — and,
# worse, the EXIT trap above fires when that subshell ends and deletes the
# fixture tree out from under every later case. The first symptom is a run of
# `exit 10` (skipped) results that look like assertion failures and are not.
run() {
    OUT="$(bash "$SCRIPT" --body-file "$1" --tree "$TREE" --format text 2>&1)"
    RC=$?
}

# --- case 1: a bare "the parent directory exists" does NOT gate -------------
# This case used to assert the opposite, and the comment above it argued that
# LOCATION was the only usable signal for a name like `repos.rs`. Issue #199
# reversed that judgement on evidence: the same rule fires on every new file
# added to an existing directory — the ordinary shape of an issue asking
# someone to create something — deterministically, every tick, until the
# operator learns to skim past the gate. The accepted trade-off is written down
# here rather than only in the issue: an invented path with nothing resembling
# it in its directory (exactly `repos.rs`) now goes UNCAUGHT, and that is
# cheaper than a gate nobody reads. Drift still fires on evidence — case 1b.
cat > "$WORK/b1.md" <<'MD'
The per-repo view lives in `app/src-tauri/src/repos.rs`.
MD
run "$WORK/b1.md"; rc=$RC
if [ "$rc" = 0 ] && echo "$OUT" | grep -q 'new .*repos\.rs'; then
    pass "missing file with no similar sibling is new, not gated"
else
    fail "parent-exists alone must not gate (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 1b: a near-match sibling IS evidence, and is suggested -------------
# The half of the old rule worth keeping. `githb.rs` sits beside a real
# `github.rs`: the directory itself supplies the near match, so this tiers
# drift on the same footing as a renamed method — with a suggestion attached,
# which is what makes the finding actionable rather than merely alarming.
cat > "$WORK/b1b.md" <<'MD'
The GitHub client lives in `app/src-tauri/src/githb.rs`.
MD
run "$WORK/b1b.md"; rc=$RC
if [ "$rc" = 3 ] && echo "$OUT" | grep -q 'did you mean `app/src-tauri/src/github\.rs`'; then
    pass "near-match sibling is drift, and the sibling is suggested"
else
    fail "sibling-evidence drift + suggestion (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 1c: a `touches:` path is never drift ------------------------------
# The solador #338 shape, and the reason #199 was filed. `sample-usage-stale.json`
# scores ~0.83 against the real `sample-azure-stale.json` beside it, so case 1b's
# rule would gate it — but `touches:` is a forward-looking declaration of what
# the PR will WRITE, so a file it names is expected to be absent. Origin beats
# similarity here; drop the origin tracking and this case fails.
cat > "$WORK/b1c.md" <<'MD'
Add the stale fixtures beside the existing one.

touches: app/ui/sample-usage-stale.json app/ui/sample-cronmonitors-stale.json
MD
run "$WORK/b1c.md"; rc=$RC
if [ "$rc" = 0 ] && echo "$OUT" | grep -q 'new .*sample-usage-stale\.json' \
   && ! echo "$OUT" | grep -q 'DRIFT'; then
    pass "touches: paths are reported as new even beside a near match"
else
    fail "touches: path must never gate (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 2: new subtree is NOT drift ---------------------------------------
# Same rule, other branch. An issue asking for a brand-new crate names paths
# under a directory that does not exist yet; gating on those would gate every
# greenfield issue in the backlog.
cat > "$WORK/b2.md" <<'MD'
Add the crate at `crates/crashreport/src/lib.rs` and wire it up.
MD
run "$WORK/b2.md"; rc=$RC
if [ "$rc" = 0 ] && echo "$OUT" | grep -q 'new .*crashreport'; then
    pass "path under a missing directory is reported as new, not gated"
else
    fail "new subtree must not gate (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 3: near-miss method name, with the rename suggested ---------------
# `open_at` vs the real `open_in` scores 0.714. This is the case that pins the
# 0.70 cutoff: at difflib's idiomatic 0.6 unrelated identifiers start pairing,
# and at a tidier 0.75 this exact rename slips through as "new".
cat > "$WORK/b3.md" <<'MD'
Open it with `Store::open_at` before reading settings.
MD
run "$WORK/b3.md"; rc=$RC
if [ "$rc" = 3 ] && echo "$OUT" | grep -q 'did you mean `open_in`'; then
    pass "renamed method is drift, and the rename is suggested"
else
    fail "renamed method + suggestion (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# The suggestion must be the RENAME, not the shortest near neighbour. Plain
# difflib ranks `open` (0.727) above `open_in` (0.714) because it is shorter,
# and a confidently wrong suggestion is worse than none — it is the line a
# reader acts on without re-checking.
if echo "$OUT" | grep -q 'did you mean `open`?'; then
    fail "suggestion ranked the shorter neighbour over the rename"
else
    pass "suggestion prefers shared prefix over raw ratio"
fi

# --- case 4: package name missing its workspace prefix ----------------------
# An acceptance command that cannot run. `-p` is read inside fenced blocks
# precisely because that is where acceptance criteria live.
cat > "$WORK/b4.md" <<'MD'
## Done when
```
cargo test -p store
```
MD
run "$WORK/b4.md"; rc=$RC
if [ "$rc" = 3 ] && echo "$OUT" | grep -q 'did you mean `solador-store`'; then
    pass "unprefixed package is drift, and the real name is suggested"
else
    fail "unprefixed package + suggestion (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 5: a correct body stays silent ------------------------------------
# The assertion that decides whether anyone leaves this enabled.
cat > "$WORK/b5.md" <<'MD'
Open the store with `Store::open_in`, defined in `crates/store/src/lib.rs`.

## Done when
```
cargo test -p solador-store
```

touches: crates/store/src/lib.rs app/ui/**
MD
run "$WORK/b5.md"; rc=$RC
if [ "$rc" = 0 ] && ! echo "$OUT" | grep -q 'DRIFT'; then
    pass "a body whose references all resolve exits 0 silently"
else
    fail "clean body must not report drift (exit $rc)"; echo "$OUT" | sed 's/^/       /'
fi

# --- case 6: the symbol pool is actually populated --------------------------
# Directly guards the silent-failure mode. With a `\b` in the harvest regex the
# pool is empty, every case above still "passes" except the suggestions — so
# assert the pool is non-empty on its own terms rather than inferring it.
POOL_COUNT=$(git -C "$TREE" grep -hoE \
    '(^|[^A-Za-z0-9_])(fn|def|function|class|struct|enum|trait|type|interface|const)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    -- . 2>/dev/null | awk '{print $NF}' | sort -u | wc -l | tr -d ' ')
if [ "${POOL_COUNT:-0}" -ge 4 ]; then
    pass "definition harvest finds symbols ($POOL_COUNT in the fixture)"
else
    fail "definition harvest returned $POOL_COUNT — the near-match pool is empty"
fi

# --- case 7: usage errors are distinguishable from findings -----------------
bash "$SCRIPT" --body-file "$WORK/b5.md" --tree "$TREE" --format bogus >/dev/null 2>&1
[ $? = 64 ] && pass "bad --format exits 64, not 3" || fail "bad --format should exit 64"

bash "$SCRIPT" --body-file "$WORK/b5.md" --tree "$WORK/definitely-not-here" >/dev/null 2>&1
[ $? = 10 ] && pass "missing tree exits 10 (skipped), not 3" || fail "missing tree should exit 10"

if [ "$FAILURES" -eq 0 ]; then
    echo "test-verify-issue-refs: all assertions passed"
    exit 0
fi
echo "test-verify-issue-refs: $FAILURES assertion(s) failed" >&2
exit 1
