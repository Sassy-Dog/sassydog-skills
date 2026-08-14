#!/usr/bin/env bash
# verify-issue-refs.sh — check an issue body's code references against the tree.
#
# Grooming writes issue bodies from plans, memory, and older issues; the tree
# moves underneath them. The result is a body whose TYPES and INVARIANTS are
# right and whose LOCATIONS are fiction, which reads as perfectly dispatchable
# and sends an executor looking for a symbol that is not there. Observed in
# production across one drain: `Store::open_at` (the method is `open_in`), a
# view claimed to live in `repos.rs`/`runners.rs` (both are in `github/mod.rs`),
# `cargo test -p servicestatus` (the package is `solador-servicestatus`).
#
# Two failure modes hide behind identical-looking text, and the distinction
# decides WHERE the gate belongs:
#
#   invented — the reference never existed. Written from a stale plan doc.
#              Catchable the moment the issue is groomed.
#   decayed  — correct when written; a later merge renamed or moved it. NOT
#              catchable at grooming time, because it was true then. Only a
#              re-check at dispatch sees it.
#
# So this runs at BOTH promotion (groom-backlog) and dispatch (dispatch-ready).
# A promotion-only gate cannot see decay; a dispatch-only gate lets invented
# references sit in Ready looking dispatchable.
#
# WHAT IT WILL NOT TELL YOU. It resolves references; it does not read code. An
# issue proposing a helper that duplicates a shipped one under another name has
# no unresolved reference and passes clean. That judgment stays human.
#
# ── Why "unresolved" is not the finding ─────────────────────────────────────
# Every issue legitimately names things that do not exist yet — that is what an
# issue IS. A checker that flags every unresolved reference flags the whole
# backlog and gets ignored within a day. The signal is not absence, it is
# absence WITH A NEIGHBOUR:
#
#   likely-drift — unresolved, and something close exists. Invented references
#                  are usually NEARLY right, which is exactly what makes them
#                  survive review. `open_at` beside `open_in`, `servicestatus`
#                  beside `solador-servicestatus`.
#   likely-new   — unresolved and nothing resembles it. Almost always the thing
#                  the issue is asking someone to create. Reported, never gated.
#
# Paths use a sharper rule than fuzzy distance: a missing file whose PARENT
# DIRECTORY exists is drift (the issue believes a file lives somewhere real and
# it does not), while a missing file under a missing directory is a new subtree.
# That is what catches `app/src-tauri/src/repos.rs` — no near-match by name,
# unambiguous drift by location.
#
# Only backticked tokens, `touches:` entries, and `-p NAME` inside fenced code
# blocks are examined. Unbackticked prose is never checked: the false-positive
# rate is what decides whether a gate survives contact with a real backlog.
#
# Usage:
#   verify-issue-refs.sh <issue-number> [--repo owner/name] [--tree PATH]
#   verify-issue-refs.sh --body-file FILE [--tree PATH]
#   verify-issue-refs.sh <issue-number> --format text
#
# Env:  REPO=owner/name (fallback when --repo absent; else inferred from cwd)
#       TREE=PATH       (fallback when --tree absent; else cwd)
#
# Output (--format json, the default): one JSON object on stdout
#   {"issue":N|null,"tree":"...","counts":{"checked":N,"drift":N,"new":N},
#    "findings":[{"ref":"...","kind":"path|symbol|package",
#                 "tier":"likely-drift|likely-new","suggestion":"..."|null,
#                 "why":"..."}]}
#
# Exit: 0 no likely-drift · 3 likely-drift found · 10 skipped · 64 usage.
# Read-only: never writes, never touches the network beyond one `gh issue view`.
set -euo pipefail

REPO="${REPO:-}"
TREE="${TREE:-}"
BODY_FILE=""
ISSUE=""
FORMAT="json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)      REPO="$2";      shift 2 ;;
        --tree)      TREE="$2";      shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        --format)    FORMAT="$2";    shift 2 ;;
        -h|--help)
            echo "usage: verify-issue-refs.sh <issue-number> [--repo owner/name] [--tree PATH] [--format json|text]" >&2
            echo "       verify-issue-refs.sh --body-file FILE [--tree PATH] [--format json|text]" >&2
            exit 0 ;;
        -*) echo "verify-issue-refs: unknown option $1" >&2; exit 64 ;;
        *)
            [[ -n "$ISSUE" ]] && { echo "verify-issue-refs: one issue number at a time" >&2; exit 64; }
            ISSUE="$1"; shift ;;
    esac
done

case "$FORMAT" in json|text) ;; *) echo "verify-issue-refs: --format must be json or text" >&2; exit 64 ;; esac
if [[ -z "$ISSUE" && -z "$BODY_FILE" ]]; then
    echo "verify-issue-refs: need an issue number or --body-file" >&2; exit 64
fi
if [[ -n "$ISSUE" && -n "$BODY_FILE" ]]; then
    echo "verify-issue-refs: --body-file and an issue number are mutually exclusive" >&2; exit 64
fi
if [[ -n "$ISSUE" ]]; then
    case "$ISSUE" in ''|*[!0-9]*) echo "verify-issue-refs: issue must be a number" >&2; exit 64 ;; esac
fi

command -v python3 >/dev/null 2>&1 || { echo "skipped: python3 not installed" >&2; exit 10; }
command -v git >/dev/null 2>&1     || { echo "skipped: git not installed" >&2; exit 10; }

# The tree is the authority. Resolve it before reading the body, so a bad --tree
# fails before spending a network call.
[[ -z "$TREE" ]] && TREE="$PWD"
[[ -d "$TREE" ]] || { echo "skipped: --tree $TREE is not a directory" >&2; exit 10; }
TREE_ROOT="$(git -C "$TREE" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$TREE_ROOT" ]] && { echo "skipped: --tree $TREE is not inside a git repo" >&2; exit 10; }

# --- the body ---------------------------------------------------------------
if [[ -n "$BODY_FILE" ]]; then
    [[ -r "$BODY_FILE" ]] || { echo "skipped: cannot read $BODY_FILE" >&2; exit 10; }
    BODY="$(cat "$BODY_FILE")"
else
    command -v gh >/dev/null 2>&1 || { echo "skipped: gh not installed" >&2; exit 10; }
    [[ -z "$REPO" ]] && REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
    [[ -z "$REPO" ]] && { echo "skipped: not in a GitHub repo and REPO not set" >&2; exit 10; }
    BODY="$(gh issue view "$ISSUE" --repo "$REPO" --json body --jq .body 2>/dev/null || true)"
    [[ -z "$BODY" ]] && { echo "skipped: could not read issue #$ISSUE from $REPO" >&2; exit 10; }
fi

# --- candidate pools, harvested from the tree once --------------------------
# Defined symbols, for near-match scoring. Definition-shaped patterns only: a
# bare identifier grep would match every call site and every comment, and a
# candidate pool full of call sites makes every near-match plausible.
#
# The word boundary is spelled as an explicit character class, NOT `\b`. git's
# regex engine accepts `\b` in an -E pattern and matches NOTHING with it, so the
# obvious spelling harvests an empty pool, every near-match lookup comes back
# empty, and every unresolved symbol is tiered `likely-new` — the checker keeps
# running and silently stops finding the thing it exists to find. Verified
# against a real tree: `\b` → 0 symbols, this form → ~3000.
SYMBOLS="$(git -C "$TREE_ROOT" grep -hoE \
    '(^|[^A-Za-z0-9_])(fn|def|function|class|struct|enum|trait|type|interface|const)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    -- . 2>/dev/null | awk '{print $NF}' | sort -u | head -5000 || true)"

# Package names. Cargo first (the org's Rust repos), then node workspaces.
PACKAGES=""
if [[ -f "$TREE_ROOT/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
    PACKAGES="$(cargo metadata --no-deps --format-version 1 --manifest-path "$TREE_ROOT/Cargo.toml" 2>/dev/null \
        | python3 -c 'import json,sys
try: print("\n".join(p["name"] for p in json.load(sys.stdin)["packages"]))
except Exception: pass' || true)"
fi
if [[ -z "$PACKAGES" ]]; then
    # Fall back to manifest names on disk — works for cargo without the toolchain
    # installed, and for node/bun workspaces. A package this misses is reported
    # as likely-new rather than asserted absent.
    PACKAGES="$( { git -C "$TREE_ROOT" ls-files '*Cargo.toml' 2>/dev/null | while read -r f; do
                     sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TREE_ROOT/$f" | head -1
                   done
                   git -C "$TREE_ROOT" ls-files '*package.json' 2>/dev/null | while read -r f; do
                     python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("name") or "")
except Exception: pass' "$TREE_ROOT/$f"
                   done; } | grep -v '^$' | sort -u || true)"
fi

export VIR_TREE_ROOT="$TREE_ROOT"

python3 - "$BODY" "$SYMBOLS" "$PACKAGES" "$ISSUE" "$TREE_ROOT" "$FORMAT" <<'PY'
import difflib, json, os, re, subprocess, sys

body, symbols_raw, packages_raw, issue, tree_root, fmt = sys.argv[1:7]
symbols = {s for s in symbols_raw.splitlines() if s}
packages = {p for p in packages_raw.splitlines() if p}

# ── extraction ──────────────────────────────────────────────────────────────
# Backticked spans are the discipline signal: this org writes code references in
# backticks. Fenced blocks are read for `-p NAME` only — their prose is a
# transcript, not a claim about the tree.
FENCE = re.compile(r'```.*?```', re.S)
fenced = FENCE.findall(body)
prose = FENCE.sub('\n', body)

inline = re.findall(r'`([^`\n]+)`', prose)
touches = []
for line in body.splitlines():
    m = re.match(r'^\s*touches:\s*(.+)$', line, re.I)
    if m:
        touches = [t for t in re.split(r'[,\s]+', m.group(1).replace('`', ' ').strip()) if t]
        break

pkg_refs = set()
for blk in fenced + [prose]:
    for m in re.finditer(r'(?:^|\s)-p[=\s]+([A-Za-z0-9_.-]+)', blk):
        pkg_refs.add(m.group(1))

# Tokens that are backticked but are not code references. Kept deliberately
# small: a long denylist is a sign the shape rules below are too loose.
NOISE = re.compile(r'''
      ^-                              # flags: --dry-run, -p
    | ^\d                             # 0.1.0, 200
    | ^https?://                      # URLs
    | ^[A-Z_]+$                       # ENV_VARS
    | ^(true|false|null|none|ok|main|ready|blocked|in-progress)$
''', re.X | re.I)

PATHISH = re.compile(r'^[\w.@-]+(/[\w.*@-]+)+/?\**$')
EXT = re.compile(r'\.(rs|ts|tsx|js|jsx|py|go|swift|kt|java|cs|rb|sh|md|json|toml|yaml|yml|css|html)$')
# A symbol reference: Type::method, mod::fn, name(), or a snake/camel identifier
# with enough shape to not be an English word.
SYMBOLISH = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+(\(\))?$|^[A-Za-z_][A-Za-z0-9_]*\(\)$|^[a-z]+(_[a-z0-9]+)+$')

def classify(tok):
    tok = tok.strip()
    if not tok or NOISE.search(tok) or ' ' in tok:
        return None
    if PATHISH.match(tok) or EXT.search(tok):
        return 'path'
    if SYMBOLISH.match(tok):
        return 'symbol'
    return None

refs = {}   # ref -> kind   (first classification wins; dedup by text)
for t in touches:
    k = classify(t) or 'path'    # a touches entry is a path claim by definition
    refs.setdefault(t, k)
for t in inline:
    k = classify(t)
    if k:
        refs.setdefault(t, k)
for p in pkg_refs:
    refs[p] = 'package'          # a -p arg outranks an inline-code guess

# ── resolution ──────────────────────────────────────────────────────────────
def git_grep(pattern):
    try:
        return subprocess.run(['git', '-C', tree_root, 'grep', '-qE', pattern],
                              capture_output=True, timeout=30).returncode == 0
    except Exception:
        return None            # unknown, never "absent"

def resolve_path(ref):
    p = re.sub(r'/?\*+$', '', ref).rstrip('/')
    full = os.path.join(tree_root, p)
    if os.path.exists(full):
        return True, None
    parent = os.path.dirname(p)
    parent_exists = bool(parent) and os.path.isdir(os.path.join(tree_root, parent))
    if not parent:
        return False, 'top-level path not present'
    if parent_exists:
        return False, 'parent directory %s/ exists but this file does not' % parent
    return False, 'parent directory %s/ does not exist either' % parent

def leaf(ref):
    return re.sub(r'\(\)$', '', ref).split('::')[-1]

def best_match(name, pool, cutoff):
    """Closest candidate, tie-broken by shared prefix rather than raw ratio.

    difflib alone answers `open` for `open_at` (0.727) over the actually-renamed
    `open_in` (0.714) — the shorter candidate wins on ratio precisely because it
    is shorter. A rename keeps its prefix and mutates the tail, so the candidate
    sharing the longest prefix is the better guess whenever both clear the
    cutoff. A wrong suggestion is worse than none: it is the line a reader acts
    on without re-checking.
    """
    cands = difflib.get_close_matches(name, pool, n=5, cutoff=cutoff)
    if not cands:
        return []
    def shared_prefix(c):
        n = 0
        for a, b in zip(name, c):
            if a != b:
                break
            n += 1
        return n
    cands.sort(key=lambda c: (shared_prefix(c),
                              difflib.SequenceMatcher(None, name, c).ratio()),
               reverse=True)
    return cands[:1]

def resolve_symbol(ref):
    name = leaf(ref)
    if name in symbols:
        return True, None
    # Not defined anywhere; is it referenced at all? A ref that appears only as
    # a call site still tells us the body is not inventing it wholesale.
    hit = git_grep(r'\b%s\b' % re.escape(name))
    if hit is None:
        return None, 'git grep failed — treated as unknown, not absent'
    if hit:
        return True, None
    return False, 'no definition and no mention in the tree'

findings = []
unresolved_syms = []

for ref, kind in sorted(refs.items()):
    if kind == 'path':
        ok, why = resolve_path(ref)
        if ok:
            continue
        drift = 'exists but this file does not' in (why or '')
        findings.append({'ref': ref, 'kind': kind,
                         'tier': 'likely-drift' if drift else 'likely-new',
                         'suggestion': None, 'why': why})
    elif kind == 'package':
        if ref in packages:
            continue
        # A dropped workspace prefix (`store` for `solador-store`) is THE
        # package drift, and edit distance is worst precisely where the case is
        # clearest: the longer the prefix, the lower the ratio. `store` scores
        # 0.556 against `solador-store` and would be missed. A hyphen-segment
        # match is exact evidence rather than a guess, so it outranks scoring.
        seg = [p for p in packages if p.endswith('-' + ref) or p.startswith(ref + '-')]
        near = seg[:1] or best_match(ref, packages, cutoff=0.6)
        findings.append({'ref': ref, 'kind': kind,
                         'tier': 'likely-drift' if near else 'likely-new',
                         'suggestion': near[0] if near else None,
                         'why': 'no such package in this workspace'})
    else:
        ok, why = resolve_symbol(ref)
        if ok or ok is None:
            if ok is None:
                findings.append({'ref': ref, 'kind': kind, 'tier': 'unknown',
                                 'suggestion': None, 'why': why})
            continue
        unresolved_syms.append((ref, why))

for ref, why in unresolved_syms:
    # 0.70, not the difflib-idiomatic 0.6 or a tidier 0.75. Measured against the
    # real case this was built for: `open_at` vs the actual `open_in` scores
    # 0.714 — the shared `open_` prefix with a two-letter divergence is the
    # canonical shape of an invented method name, and 0.75 misses it by a
    # hair while 0.6 starts pairing unrelated same-length identifiers.
    near = best_match(leaf(ref), symbols, cutoff=0.70)
    # A qualified reference whose QUALIFIER resolves but whose leaf does not is
    # drift on its own evidence, near-match or not: the body knows a real type
    # and names a member it does not have. Same shape as the path rule — the
    # container exists, the thing inside it does not — and it catches renames
    # too far apart for any distance threshold to pair up.
    qualifier = ref.split('::')[0] if '::' in ref else None
    qualified_drift = bool(qualifier) and qualifier in symbols
    if qualified_drift and not near:
        why += '; %s exists but has no such member' % qualifier
    findings.append({'ref': ref, 'kind': 'symbol',
                     'tier': 'likely-drift' if (near or qualified_drift) else 'likely-new',
                     'suggestion': near[0] if near else None, 'why': why})

drift = [f for f in findings if f['tier'] == 'likely-drift']
new = [f for f in findings if f['tier'] == 'likely-new']

if fmt == 'text':
    if not findings:
        print('verify-issue-refs: %d reference(s) checked, all resolve.' % len(refs))
    else:
        print('verify-issue-refs: %d reference(s) checked in %s' % (len(refs), tree_root))
        for f in drift:
            s = ' — did you mean `%s`?' % f['suggestion'] if f['suggestion'] else ''
            print('  DRIFT  %-40s %s%s' % (f['ref'], f['why'], s))
        for f in new:
            print('  new    %-40s %s' % (f['ref'], f['why']))
        for f in findings:
            if f['tier'] == 'unknown':
                print('  ?      %-40s %s' % (f['ref'], f['why']))
else:
    print(json.dumps({
        'issue': int(issue) if issue else None,
        'tree': tree_root,
        'counts': {'checked': len(refs), 'drift': len(drift), 'new': len(new)},
        'findings': findings,
    }, indent=2))

sys.exit(3 if drift else 0)
PY
