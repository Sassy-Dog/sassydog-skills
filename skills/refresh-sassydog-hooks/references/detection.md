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
| `markdownlint` | A `.markdownlint-cli2.*` / `.markdownlint.*` config AND tracked `*.md` | `*.md` → `markdownlint-cli2 --fix`, then re-check; unfixable exit 2 | If the repo pins a version in CI (grep its workflows for `markdownlint-cli2@`), render the same pin into the hook instead of the template's unpinned `npx -y markdownlint-cli2`. |
| `shellcheck` | Tracked `*.sh` (shellcheck in a CI workflow strengthens the evidence and is reported in `why`) | `*.sh` → `shellcheck -S warning`; findings exit 2 | Lint-only — never rewrites. There is no standard shellcheck config file, so tracked shell IS the evidence. |
| `dart` | `pubspec.yaml` | `*.dart` → `dart format` | Format-only; `dart analyze` is too slow per-edit. |
| `rustfmt` | `Cargo.toml` | `*.rs` → `rustfmt` | Format-only; `cargo clippy` per edit is far too slow. |
| `gofmt` | `go.mod` | `*.go` → `gofmt -w` | — |
| `dotnet_format` | Tracked `*.sln` / `*.csproj` | `*.cs` → `dotnet format --include <file>` | **SLOW** (solution load per invocation) — always opt-in via the Phase 2 interview, never auto-included. |

## Refresh-mode signal

`existing_generated_hooks` in the probe output lists `.claude/hooks/sassydog-*.sh` files already
present — non-empty means refresh mode (re-render + reconcile), empty means create mode.

## Multi-stack repos

A repo detecting several tools still gets ONE dispatcher with several routes — never one hook entry
per tool. One settings entry, one script, extension routing inside; that keeps the ownership
contract trivial (everything the generator owns references `sassydog-`).
