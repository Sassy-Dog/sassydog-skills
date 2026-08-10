# Detection — probe table and evidence rules

`scripts/detect-hook-stack.sh` implements this table; run it rather than probing by hand. Output is
evidence, not truth — anything surprising gets confirmed with the user in Phase 2.

## The evidence rule

A tool is detected only on **repo evidence** — a config file, a manifest section, or tracked file
types — never on what is installed on the current machine. Committed hooks
(`.claude/settings.json`) execute on every teammate's machine; "ruff happens to be on this laptop's
PATH" is not evidence the repo wants ruff. The rendered dispatcher still self-guards every route
with `command -v <tool> || exit 0`, so a machine without the tool degrades to a no-op instead of a
hook error.

## Probe table

| Tool | Detected when | Routes | Trap |
|------|---------------|--------|------|
| `ruff` | `ruff.toml` / `.ruff.toml`, or `pyproject.toml` with a `[tool.ruff` section — AND tracked `*.py` | `*.py` → `ruff format` + `ruff check --fix`; unfixable findings exit 2 | Tracked `*.py` with no ruff config is reported but NOT detected — generating ruff for a repo that never adopted it imposes a formatter the team didn't choose. Say so and let the user opt in by adding config. |
| `prettier` | A `.prettierrc*` / `prettier.config.*` file, or a `prettier` key in `package.json` | `*.ts,tsx,js,jsx,mjs,cjs,css,scss,json` → `npx --no-install prettier --write` | `--no-install` on purpose: prettier must come from the repo's own `node_modules` (the repo pins its version); a bare `npx -y` would fetch latest and fight the pin. |
| `markdownlint` | A `.markdownlint-cli2.*` / `.markdownlint.*` config AND tracked `*.md` | `*.md` → `markdownlint-cli2 --fix`, then re-check; unfixable exit 2 | The version pin is **not optional** — see below. An unpinned `npx -y` resolves to latest and blocks on rules CI does not run. |
| `shellcheck` | Tracked `*.sh` (shellcheck in a CI workflow strengthens the evidence and is reported in `why`) | `*.sh` → `shellcheck -S warning`; findings exit 2 | Lint-only — never rewrites. There is no standard shellcheck config file, so tracked shell IS the evidence. |
| `dart` | `pubspec.yaml` | `*.dart` → `dart format` | Format-only; `dart analyze` is too slow per-edit. |
| `rustfmt` | `Cargo.toml` | `*.rs` → `rustfmt` | Format-only; `cargo clippy` per edit is far too slow. |
| `gofmt` | `go.mod` | `*.go` → `gofmt -w` | — |
| `dotnet_format` | Tracked `*.sln` / `*.csproj` | `*.cs` → `dotnet format --include <file>` | **SLOW** (solution load per invocation) — always opt-in via the Phase 2 interview, never auto-included. |

## The markdownlint version pin (`pin` / `pin_source`)

`tools.markdownlint` carries two extra probe fields beyond `detected` / `why`:

| Field | Value |
|-------|-------|
| `pin` | The discovered markdownlint-cli2 spec — a version (`0.18.1`) or a range (`^0.18.1`). Empty string when nothing was discoverable. |
| `pin_source` | The file the pin came from, e.g. `scripts/preflight.sh`, or `package.json (dependency range)`. Empty when `pin` is empty. |

**Why it exists.** `npx -y markdownlint-cli2` resolves to **latest at hook time**. A repo whose CI
pins an older release gets a hook that blocks on rules CI does not have — measured: CI on `0.18.1`,
hook resolving `0.23.2`, `MD060` (which does not exist in `0.18.1`) flagging six errors on a README
CI calls clean. The exit-2 contract is the whole value of the hook; a hook that fires on rules
nobody enforces trains the user to ignore exactly that signal, and it fails *silently* — nothing
else compares the hook's resolved version against CI's.

**Search order** (first explicit `markdownlint-cli2@<spec>` wins):

1. `.github/workflows/*.yml` / `*.yaml`
2. The shell scripts those workflows invoke — **one hop**, matching `*.sh` paths in the workflow
   text and keeping the ones that exist. This catches the common "CI calls `scripts/preflight.sh`"
   shape, where the workflow itself never names a version. (This repo is exactly that case:
   `MARKDOWNLINT_PKG="markdownlint-cli2@0.18.1"` lives in `scripts/preflight.sh`.)
3. `Makefile` / `makefile` / `GNUmakefile`, then `justfile` / `Justfile` / `.justfile`
4. `package.json` — an explicit `markdownlint-cli2@<spec>` anywhere in it (typically an npm script)
5. Fallback: the `package.json` dependency range —
   `devDependencies["markdownlint-cli2"]`, else `dependencies["markdownlint-cli2"]`

**No pin discoverable → render fix-only.** The probe appends a `detect_failures` note and the render
drops the blocking half (see `templates/sassydog-post-edit.template.sh`, the nested
`MARKDOWNLINT_BLOCKING` block). Fixing silently is always safe; blocking on rules CI does not run is
not. Say so in the Phase 3 preview so the downgrade is visible, not silent — the fix is for the repo
to pin its own version, after which a refresh renders the blocking half back in.

Prettier needs no equivalent field: it renders `npx --no-install`, so the repo's own lockfile is
already the pin.

## Refresh-mode signal

`existing_generated_hooks` in the probe output lists `.claude/hooks/sassydog-*.sh` files already
present — non-empty means refresh mode (re-render + reconcile), empty means create mode.

## Multi-stack repos

A repo detecting several tools still gets ONE dispatcher with several routes — never one hook entry
per tool. One settings entry, one script, extension routing inside; that keeps the ownership
contract trivial (everything the generator owns references `sassydog-`).
