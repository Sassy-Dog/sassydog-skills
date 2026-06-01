# Assessment Rubric

The substance of a Staff+ engineering audit, distilled into reference the review agents consult and the main agent uses for the Epic summary. **Evidence-based, not a linting pass.** Cite concrete files/lines. Explain *why it matters*. Distinguish preference vs. convention vs. genuine risk. Avoid cargo-cult "best practices" with no demonstrated harm in *this* repo.

## Scoring (for the Epic executive summary)

Score each 1–10 (10 = excellent). Include a one-line justification per score.

| Score | Meaning | Health / Security / DX / Maintainability / Architecture coherence |
|---|---|---|
| 9–10 | Exemplary | Few-to-no genuine risks; strong patterns; would onboard fast |
| 6–8 | Solid | Healthy with addressable gaps |
| 3–5 | At risk | Real liabilities; velocity or incidents likely |
| 1–2 | Critical | Systemic problems; urgent remediation |

## Severity × Likelihood (per finding)

**Severity** = blast radius if it goes wrong:
- **critical** — data loss, auth bypass, secret exposure, prod outage, supply-chain compromise
- **high** — security weakness, broken core flow, release-blocking fragility
- **medium** — maintainability/perf/test-gap risk that will bite under change
- **low** — papercut, inconsistency, minor cleanup

**Likelihood** = how probable it is to actually cause harm: `high` / `medium` / `low`.
Prioritise **realistic** threats over theoretical ones. A low-likelihood low-severity item is usually *not* worth an issue.

## The 15 Assessment Areas

Each review agent owns a subset (see `orchestration.md`). Look for *evidence*, not vibes.

1. **Executive summary** — (main agent only) the scores above + biggest strengths/risks + "If I inherited this repo tomorrow…" + top-10 actions ranked by ROI.
2. **Repository & solution structure** — organization, monorepo/polyrepo fitness, module boundaries, dependency direction, domain isolation, shared-lib sprawl, circular deps, dead modules, duplicated utilities, naming consistency, onboarding discoverability, scales-with-team.
3. **Architecture** — style consistency, bounded contexts, layering, service/API boundaries, eventing, state management, FE/BE contracts, data ownership, transactional boundaries. Look for drift, distributed-monolith, hidden shared state, over/under-engineering, premature abstractions, leaky abstractions, where it breaks at scale.
4. **Code quality** — readability, complexity, abstraction quality, duplication, function/class sizing, error handling, async/concurrency correctness, config management, DI patterns. Identify fragile/high-risk modules, hidden side effects, implicit contracts, likely bug factories.
5. **Security** — auth/authz, token & session handling, secret management, API exposure, injection/SSRF/XSS/CSRF/deserialization, unsafe reflection/file handling/uploads, insecure defaults. **Supply chain**: dep health, stale/vulnerable packages, transitive risk, lockfile hygiene, pinning, provenance. **Pipeline/IaC**: CI secret handling, credential exposure, excessive permissions, identity boundaries, GitHub Actions hardening, branch protection. **Operational**: auditability, log sensitivity/PII, rotation, env isolation. Give exploitability + blast radius + remediation.
6. **Developer experience** — onboarding, local dev loop, env setup, dependency install reliability, dev containers, debugging, hot reload, test speed, CI feedback quality, error clarity, tooling consistency. Name the top friction points and highest-leverage fixes.
7. **Testing strategy** — unit/integration/E2E balance (pyramid), mocking strategy, flakiness, coverage *quality* vs theater, fixture quality, determinism, untestable architecture, missing critical-path coverage, deployment confidence.
8. **CI/CD & release engineering** — pipeline architecture, deploy strategy, rollback, env promotion, caching, build reproducibility, artifact management, versioning, branch strategy, preview envs, pipeline reliability/duration/failure-clarity. Look for hidden manual steps, tribal knowledge, unsafe deploys, snowflake envs.
9. **Infrastructure & platform** — Terraform/Bicep quality, state management, module structure, env strategy, secret handling, networking, identity/RBAC, container quality, reproducibility, drift resistance, blast radius, cost awareness, dangerous defaults.
10. **Observability & operations** — logging quality/structure, metrics, tracing, alerting, dashboards, health checks, SLO/SLA awareness, incident readiness, MTTR, debuggability. Look for noisy/unstructured logs, missing telemetry, alert fatigue, poor correlation.
11. **Documentation & knowledge** — README, onboarding/architecture docs, ADRs, runbooks, troubleshooting, API docs, code comments; freshness, discoverability, knowledge-concentration risk.
12. **Technical debt** — categorize (intentional/accidental/operational/architectural/scaling/testing/security/platform); per item: impact, urgency, cost of delay, remediation complexity. Separate harmless imperfections from strategic liabilities.
13. **Team & scaling** — likely pain points, ownership risks, coordination/review/deploy bottlenecks; does the repo support 5 / 20 / 100 engineers; where scaling breaks first.
14. **Modernization** — architecture/tooling/dependency/testing/DX/security/CI/observability improvements; separate "do now" / "do next" / "future".
15. **Deliverables** — collapse into: one GitHub Issue per PR-sized work item + one Epic whose body is the executive report (scores, strengths, risks, top-10 ROI, 30/90/180-day roadmap).

## Output discipline

- One excellent, specific finding beats ten generic ones.
- Every finding: title, area, severity, likelihood, `file:line` evidence, why it matters, proposed fix, acceptance criteria, rough PR size, suggested labels (see `orchestration.md` schema).
- No filler, no platitudes, no multi-paragraph restatements of "best practice".
