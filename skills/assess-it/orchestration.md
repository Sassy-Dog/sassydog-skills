# Orchestration

How the main agent dispatches review agents, what each returns, and how findings become issues.

## Agent → domain map

Dispatch only the agents with signal for the detected stack. All ship with this plugin and namespace as `sassy-dog:<name>`.

| Agent (`subagent_type`) | Owns rubric areas | Dispatch when |
|---|---|---|
| `sassy-dog:architecture-reviewer` | 2 structure, 3 architecture, 13 team/scaling | always |
| `sassy-dog:code-quality-reviewer` | 4 code quality, 12 tech debt | always |
| `sassy-dog:security-reviewer` | 5 security (app + supply chain + pipeline + ops) | always |
| `sassy-dog:testing-reviewer` | 7 testing | always |
| `sassy-dog:cicd-release-reviewer` | 8 CI/CD & release | `.github/workflows/` or other CI config present |
| `sassy-dog:infra-platform-reviewer` | 9 infrastructure & platform | `*.tf`/`*.bicep`/`Dockerfile`/k8s manifests present |
| `sassy-dog:observability-ops-reviewer` | 10 observability & operations | always (light if app is tiny) |
| `sassy-dog:dx-docs-reviewer` | 6 DX, 11 docs | always |
| `sassy-dog:dependency-supply-chain-reviewer` | 5 supply-chain slice, 12 dep debt | a lockfile/manifest is present |

**Dispatch rule:** issue all selected agents in **one message, multiple Agent calls** (concurrent). Give each: the absolute repo path, the detected stack summary, the dedupe index is *not* needed by agents (you dedupe centrally), and an instruction to return **only** the JSON-ish finding list in the schema below. Tell each agent it is in **audit mode**: find what's wrong, cite evidence, do not propose to write code.

## Finding output schema

Each agent returns a list of findings. Each finding:

```
- title:            imperative, PR-sized ("Pin GitHub Actions to commit SHAs")
  area:             one of the 15 rubric areas
  severity:         critical | high | medium | low
  likelihood:       high | medium | low
  evidence:         one or more "path/to/file.ext:LINE" with a 1-line quote/why
  why_it_matters:   concrete consequence in THIS repo (not generic)
  proposed_fix:     what a PR would do
  acceptance:       how we'd know it's fixed
  pr_size:          xs | s | m | l   (l = consider splitting)
  labels:           suggested labels from the taxonomy
  confidence:       0.0–1.0  (agent's own confidence the finding is real)
```

Agents that find nothing in their domain return an empty list — that is a valid, useful result.

## Adversarial review (Phase 2)

For each finding, in order of severity:

1. **Verify evidence** — open the cited `file:line`. If it doesn't say what the finding claims → drop.
2. **Genuine vs. preference** — is this a real risk, or a style opinion / valid convention? Drop preferences.
3. **Recalibrate** — adjust severity/likelihood to reality; downgrade theoretical threats.
4. **Dedupe vs. existing issues** — compare against the Phase-0 GitHub index (title + body similarity, same file/area). If already tracked → mark `duplicate-of #N` (comment later, don't refile).
5. **Dedupe vs. siblings** — merge near-identical findings from different agents.
6. **Refute pass (high-impact only)** — for `critical`/`high`, optionally dispatch 1–3 skeptic subagents, each told to *try to prove the finding wrong* (distinct lenses: exploitability, does-it-reproduce, is-it-already-mitigated). Keep the finding only if it survives a majority.

Survivors carry a final `confidence`. Drop anything below ~0.6 unless severity is `critical`.

## Grouping into PR-sized issues (Phase 3)

- Cluster survivors that a single PR would naturally fix together (same subsystem, same kind of change). Each cluster → one child issue; list its findings as a checklist in the body.
- A single `l`/`xl` finding may be its own issue with a "split into N PRs" note.
- Keep clusters cohesive: don't bundle unrelated areas just to reduce issue count.
- Order issues by ROI (severity × likelihood ÷ effort) for the Epic's top-10.

Then proceed to `references/github-issue-ops.md` for filing.
