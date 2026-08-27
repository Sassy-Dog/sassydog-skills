#!/usr/bin/env bash
# preflight.sh — this repo's CI gates, runnable locally. CI's `ci` job calls
# THIS script for every gate except actionlint, which CI runs as a separate step
# from a pinned native binary (ci.yml explains why it is not the dockerized
# action); this script runs actionlint too when a local binary or docker is
# available, and reports a skip when neither is.
#
# Guard regexes live here and only here. Tool VERSIONS do not: markdownlint-cli2
# is pinned below, but shellcheck is whatever is on PATH locally versus an exact
# pin in ci.yml. That gap is real and documented in CONTRIBUTING.md — a local
# pass on a different shellcheck is not proof of a green build.
#
# Run it before every PR; `--fix` lets markdownlint auto-fix first.
#
# Usage: bash scripts/preflight.sh [--fix]
#
# Gates, in CI order:
#   1. shellcheck -S warning over every tracked *.sh, PLUS a second pass for
#      SC2006 alone. SC2006 is `style`, so the first pass cannot see it, and the
#      gap shipped a real defect twice: an unescaped backtick in a double-quoted
#      test label is command substitution, and three labels in
#      test-sentry-verification.sh were executing `which`, `that` and `where`.
#   2. frontmatter sanity (scripts/check-frontmatter.sh) — two layers. LOADER
#      requirements on every tracked skill/agent file: opening `---` on line 1,
#      `name`/`description` present, `name` matching the directory (skills) or
#      filename (agents). AGENT SKILLS SPEC constraints on `SKILL.md` ONLY
#      (issue #118): `description` <= 1024 characters, `name` <= 64 characters
#      with charset and hyphen rules, and a strict frontmatter key allowlist
#      (name, description, license, compatibility, allowed-tools, metadata)
#      whose unknown keys HARD-fail, matching what `gh skill publish` rejects.
#      `agents/*.md` are deliberately exempt from the spec layer — an agent is
#      not a skill and legitimately carries `color:`.
#   3. no bare positional tokens in Skill-args substitution surfaces (issue #39)
#   4. no legacy name residue outside the per-name sanctioned back-compat
#      files, in three groups (all enforced under this one gate): the renamed
#      generator family — 'create-dev-workflows', 'refresh-sassydog-',
#      'refresh-skills', 'refresh-hooks', 'refresh-deps' (issue #120); the
#      plugin and marketplace renames — 'ai-agent-skills', 'sassy-dog-skills'
#      (issue #71); and the workflow-skill naming sweep — 'plate-it',
#      'groom-it', 'drain-it', 'clean-it'
#   5. plugin manifests are valid JSON, the plugin version is CalVer
#      (YYYY.M.P — the one-way ratchet, docs/VERSIONING.md), and any
#      marketplace.json plugins[].version equals it (issue #31)
#   6. versioning tests (scripts/test-versioning.sh)
#   7. ownership-matcher tests (scripts/test-ownership-matchers.sh) — the
#      setup-hooks / setup-deps `generated-by:` matchers, extracted from the
#      shipped SKILL.md files and run against real pre-rename consumer
#      artifacts committed under scripts/fixtures/legacy-markers/ (issue #133)
#   8. label-taxonomy tests (scripts/test-label-taxonomy.sh) — the two label
#      taxonomies stay disjoint AND perceptually separated (cross-set CIEDE2000
#      check), issue-claim.sh's label reconcile still CORRECTS a drifted label
#      instead of silently skipping it (issue #161), and there is no THIRD copy
#      of either table: every colour from both emitters is searched for across
#      the tracked tree and any hit outside its own home fails (issue #167 —
#      the cross-set check scores two taxonomies, so a copy anywhere else is
#      invisible to it). Definitions and a mock gh only: no repo, no network.
#   9. label-migrate tests (scripts/test-label-migrate.sh) — align-labels.sh's
#      relabel-then-delete migrate mode cannot delete a label whose relabel has
#      not been verified by re-query (issue #163). Mock gh only; the MODE
#      itself is never run in CI, because it mutates other repos' issues.
#  10. dependabot-render tests (scripts/test-dependabot-render.sh) — setup-deps
#      renders one lane per (ecosystem, DIRECTORY) and every lane is backed by a
#      manifest in the directory it names, against three recorded consumer
#      layouts; the collapsed-to-"/" v2 shape must be REJECTED (issue #169).
#      Recorded file lists only: no repo, no network.
#  11. detect-hook-stack tests (scripts/test-detect-hook-stack.sh) —
#      setup-hooks' has_tracked probe still answers correctly when the match
#      list is LARGE. Under pipefail a `| head -1 | grep -q .` returns the
#      writer's SIGPIPE 141 once the output outruns the ~64KB pipe buffer, so a
#      MATCH read as a miss and the render silently dropped that tool's route
#      (issue #172). Needs a 20k-path fixture, because a small one passes
#      either way; the gate fails loudly if that fixture ever stops tripping
#      the pre-fix shape. Index-only temp repos: no real repo, no network.
#  12. visibility precondition tests (scripts/test-visibility-preconditions.sh)
#      — setup-deps' App-token renders have TWO preconditions, not one: a merge
#      gate AND a non-public repo. Its org secrets are `private`-visibility,
#      which excludes public repos in both the Actions and Dependabot stores, so
#      a render into one produces a workflow whose `secrets.*` are empty and
#      which fails weeks later on that repo's next Dependabot PR, as an auth
#      error that looks unrelated (issue #178). The precondition belongs to the
#      CREDENTIAL, not to one workflow: three templates mint it, #178 gated only
#      auto-merge, and the two it missed are the two that check out PR head
#      (issue #186) — hence the rename from test-auto-merge-visibility.sh. The
#      decision is SKILL.md prose, not script, so this pins the instruction —
#      same shape as the label-migrate single-call-site guard. Must-not-exist
#      assertions run against a whitespace-flattened copy, because this repo
#      hard-wraps prose and a line-scoped grep for forbidden wording turns a
#      wrap into a false PASS. Reads two tracked files: no gh, no network.
#  13. verify-issue-refs tests (scripts/test-verify-issue-refs.sh) — the
#      grooming-drift checker. THREE of its failure modes are SILENT and none
#      changes an exit code. (a) `\b` in a git -E harvest pattern empties the
#      near-match pool, so every unresolved reference tiers `likely-new` and the
#      checker quietly stops finding drift — and that measurement is PLATFORM-
#      SPECIFIC: `\b` matches nothing on macOS (git 2.55) and matches normally
#      on the Linux git that runs this gate (2.54/musl, 2.47/glibc), so the
#      wrong spelling would be green here and broken on the machine doing the
#      grooming. (b) A suggestion ranked on raw edit distance answers the
#      shortest neighbour (`open`) instead of the actual rename (`open_in`),
#      which is worse than no suggestion because it is the line a reader acts on
#      without re-checking. (c) A pool full of the WRONG LANGUAGES (issue #263):
#      the harvest was keyword-led and POSIX shell functions carry no keyword, so
#      on a bash repo a correct `read_monitors()` drew a confident TypeScript
#      suggestion while real drift tiered `likely-new` and passed. Also pins the
#      NEGATIVE cases — a clean body and a new-subtree body must stay quiet —
#      since a checker that fires on everything is muted within a day and then
#      gates nothing at all. THREE synthetic trees now — non-shell,
#      shell-majority, and one real script beside three hostile FILENAMES —
#      because a shell-blind harvest is invisible to every case in the first,
#      and a pathspec-magic name empties the pool with nothing else to show for
#      it. Ten mutants, each proved applied before its proofs run,
#      plus source-level assertions for the three rules no Linux run can
#      observe: the `\b` spelling itself, which is green on Linux and empties
#      the KEYWORD half on macOS so CI cannot see it go wrong; the empty-array
#      test; and the process-substitution comment trap.
#      Built in a tmpdir: no gh, no network.
#  14. stale-issues tests (scripts/test-stale-issues.sh) — the
#      tracking-parent-complete detector (issue #198). An epic that splits into
#      children can never close itself: GitHub moves an issue only on a merged
#      PR's closing keyword, and a tracking parent is the issue no PR ever
#      names. All three of this detector's wrong answers are silent — a missed
#      parent is indistinguishable from a clean repo, a PREFIX COLLISION
#      (#28 claiming #283's children) tells a human to close live work, and a
#      TRUNCATED pull returns the same empty list a clean one does. The prefix
#      fixture is mutation-proved: a copy of the script whose regex has lost
#      its non-digit guard MUST report #28, or the decoy has gone vacuous.
#      Mock gh serving recorded JSON: no repo, no network, and the run is
#      asserted to issue zero non-read calls.
#  15. teardown-args tests (scripts/test-teardown-args.sh) — teardown.sh parses
#      flags anywhere in its argument list and rejects an unrecognised -* one
#      BEFORE any teardown runs (issue #200). The bug it pins reads as success:
#      `teardown.sh <p1> <p2> --sweep` tore both worktrees down, took --sweep
#      for a third path, and never swept — a tool-level usage dump buried under
#      successful teardown lines, and a skipped phase leaves nothing behind to
#      notice. Assertions read teardown's OWN output, never basename's, whose
#      BSD/GNU wording differs (that is why it surfaced on macOS only). Scratch
#      repos with a LOCAL bare origin plus a mock gh: no real repo, no network.
#  16. markdownlint (pinned markdownlint-cli2 version)
#  17. actionlint — best-effort locally (binary, else docker); SKIPPED in CI
#      (CI=true) because the workflow runs it as its own step
#  18. config-source guard — every `!` block that inlines a repo's
#      .claude/sassy-dog/<skill>.md MUST also echo CONFIG_SOURCE. Same
#      source-level class as gates 3 and 4. The block resolves against the
#      SESSION's cwd, not the repo being acted on, and cwd resets between Bash
#      calls — so a sub-agent working in another repo is silently handed the
#      session repo's config. That is only wrong when the session repo IS
#      configured: NO_CONFIG already fails honestly, but a populated config from
#      the wrong repo is indistinguishable from the right one (2026-08-18 — two
#      agents were each handed platform's Terraform gates). Announcing the path
#      is what makes the mismatch visible. The check is LINE-scoped on purpose:
#      the reconciliation prose in each §1 also says CONFIG_SOURCE, so a
#      file-scoped grep would pass a block that had lost it.
#  19. scanning-states tests (scripts/test-scanning-states.sh) — the code- and
#      secret-scanning pulls' four silent failure modes: the 404 that means
#      BOTH "Advanced Security off" and "never analyzed" (collapsing them
#      reports a never-scanned repo as clean), the un-paginated read that
#      returns a capped 100 as if it were a measurement (live: velovate, true
#      count 102), a PR-ref alert counted as default-branch debt, and the
#      validity:"active" P0 rule acquiring an age gate. Mock gh only.
#  20. sentry-verification tests (scripts/test-sentry-verification.sh) —
#      setup-config may only write a `sentry:` block for a project VERIFIED by
#      culprit against this repo's own code, and records a failed verification
#      as `sentry: none` (issue #213). Name similarity is the evidence an agent
#      reaches for first and it is wrong invisibly: the wrong repo claims
#      another codebase's P0s while BOTH plates still render complete. Also pins
#      `sentry: none` as the config contract's first documented exception to
#      "presence is the toggle" — prose a later consistency sweep reads as drift
#      and deletes — and keeps the sibling prior-claim scan SECONDARY, since a
#      cloud session has no sibling checkouts and would lose the guard silently.
#      The `none` form now spans FOUR keys and is deliberately ASYMMETRIC across
#      them (issue #261): `sentry: none` keeps its blind-spot row, while
#      `testflight`/`posthog`/`mobile: none` take one `(n/a)` token on the clean
#      line and no row. A four-key form with one key behaving differently reads
#      as a plain inconsistency, so a tidying sweep breaks it in either
#      direction and both are silent — collapsing sentry onto the clean line
#      restores #213's gap, promoting the other three restores #261, where an
#      infra repo carried three permanently unclearable rows on every plate and
#      trained its reader to skim the heading a dark Sentry lives under. The
#      four-key table is checked by COUNTING rows, not by looking the four names
#      up: a lookup passes just as happily on a table that grew a fifth key.
#      Its own assertions have been the hard part: every review round so far has
#      found some of them passing on sources stating the inverse, and the
#      author's mutation set kept reporting "all detected" because every mutation
#      deleted the exact literal its assertion grepped for — tautologically
#      caught. The lesson generalises to every prose gate here: mutate the
#      MEANING, worded as a tidying editor would word it. Re-measured that way,
#      the mutually-exclusive-vocabularies rule still governs the PROSE — each
#      rule must speak exactly one outcome's vocabulary — but it is NOT
#      sufficient on its own, and that distinction is the one a later reader will
#      collapse. What cannot be enumerated is how negation is PHRASED ("never
#      given", "is exempt from", "no longer keeps", "aligned with the other
#      three"): an open semantic class English extends faster than any list
#      absorbs it, which is what the six-verb affirmative kept losing to. What
#      the classifier enumerates instead is NEGATORS — a closed grammatical core
#      (no, not, never, neither, nor, without, nothing) plus a deliberately short
#      set of lexical ones this repo's prose actually uses (exempt, excluded,
#      omitted, instead, rather). Only the first is truly closed; the second is
#      the part that can drift, so it stays short and each addition must be
#      justified by prose in the tree. Neither substitutes for POLARITY, which is
#      what handles composition ("not exempt") that a list of any length cannot.
#      All three of its scans stop at ONE shared clause boundary (issue #270),
#      and since #271 that boundary is their only BOUND as well. Two checked it
#      and `cancelled` did not, which reads as deliberate and was not: a negator
#      in a PREVIOUS clause cancelled a real negation, so the sentence read
#      AFFIRMED and could satisfy the very must-affirm veto meant to catch it.
#      The count bound all three carried is gone — four content words in the two
#      look-around scans, four POSITIONS in the cancellation scan, a real
#      difference and not a wording slip — because the unit was wrong in both
#      directions at once and no value of it works: too short let a
#      qualifier-heavy negator escape and read AFFIRMED, too long reached
#      negators in OTHER clauses, and raising it from four to six reddened the
#      PRE-#271 gate (no count of reddened assertions is quoted anywhere, and
#      after merge there is no bound left to raise — the live proof is that
#      restoring a count bound to any one scan reddens that scan's own case).
#      Dropping the counts is what made the three dead dash arms have to work,
#      an unfired boundary now costing the whole previous clause rather than a
#      word of window; it is what dissolved the `:` arm cost PR #272 accepted,
#      by giving the cancellation scan the parenthetical skip the left-context
#      one always had; and it removed three guards the distance had been
#      supplying by accident, every one of them failing QUIETLY. A skip region
#      now honours `hard_break`, the subset of the boundary set an aside cannot
#      contain (`.` and `;`), written as an expression of `clause_break` rather
#      than beside it and asserted at SOURCE level, since nothing behavioural
#      can tell a shared subset from two matching transcriptions. The
#      comma-bearing token is tested before it opens a skip, an odd comma having
#      otherwise consumed the negator itself — wrong on the pre-#271 source too.
#      And `post_negated` performs the same polarity flip `governed` does,
#      stops at a RELATIVIZER — and that class SPLITS: a possessive (`whose`),
#      locative (`where`) or temporal (`when`) names a new subject in its own
#      right and stops unconditionally, while the subject relatives
#      (`which|that|who|whom`) carry the antecedent forward and are exempt when
#      one heads the destination directly. A single whole-class exemption is
#      wrong exactly where a restrictive relative is most natural, immediately
#      after the destination, and each member that can fire has its own case;
#      the split was mis-drawn twice before it was right, so sort members by
#      what they DO and not by how the rule reads. It also
#      counts a participle only once a PASSIVE AUXILIARY or COPULAR verb has
#      re-attached it. That set is TWO-TIER, on the split the negator set
#      already uses: tier 1 is the two closed passive paradigms (`be` and the
#      get-passive), enumerated on the terminating argument; tier 2 is copular
#      and aspectual verbs, admitted only on the file's other rule — a lexical
#      addition justified by prose in the tree — with the wider copular class
#      (`seem|appear|look|…`) stated as a known limit rather than enumerated.
#      Every member carries its own case and NO COUNT IS WRITTEN DOWN: the set
#      has changed size twice under review and the prose stating its old size
#      survived both times. Trimming is the unsafe direction — removing any
#      member flips its own ordinary sentence to AFFIRMED, quietly — since
#      with no ceiling it otherwise fired on any participle in its clause and
#      read the #261 rule and its inverse alike. A PREPOSITION is deliberately
#      not a stop there, and a case pins why: it is the copula after it that
#      decides. The gate has a SECOND AXIS besides which verbs count: a
#      participle with NO auxiliary. A comma- or dash-set-off APPOSITIVE is
#      predicated of the destination and is admitted, but only when it opens
#      immediately after it — that position is the whole of what separates it
#      from a reduced relative modifying the nearer noun, and a looser rule
#      re-opens what the copula gate closes. `clause_break` also gained the two separators this repo's own
#      prose writes, the rule arrow and the markdown cell wall `|`; without them
#      the scan crosses live tracked text in two of the eight files, and since
#      neither drift reddens anything both arms are pinned by fixed strings
#      alone. The negator sets are factored core-and-full, the full one an
#      expression of the core, because a comma-bearing token is tested against
#      the CORE only — an adverb scopes over what follows it, a participle
#      predicates on the subject to its left. ONE limit is STATED rather than
#      fixed, in a known-limit block, and it has two faces: comma parity is a
#      guess, so a comma-joined subordinate clause is unbounded and a third
#      comma inverts the aside pairing. The block also records the fix that does
#      NOT work, measured — subordinators in `clause_break` change neither
#      string, the subordinator sitting left of the negator where a backward
#      scan meets the negator first. `hard_break` bounds both at the nearest
#      sentence, which is why it is a limit and not a hole. No count beyond that
#      is written down: two copies of this paragraph once disagreed about one,
#      which is the failure this gate refuses everywhere else. The
#      classifier carries a battery of its own — fixed strings, both directions,
#      every arm of the boundary set and every scan's bound and guard proved
#      load-bearing by a mutation — because until then its behaviour lived only
#      in comments, and a comment does not redden.
#      Windows need structural bounds rather than byte
#      counts; a veto over a rule that STATES a negative must require the
#      negation, since silence satisfies "nothing affirmed"; and every table row
#      must be classified rather than tallied. Source-level, must-not-exist
#      checks run on flattened and emphasis-stripped copies. The run prints its
#      own assertion count. No gh, no network: eight tracked files.
#  21. sentry-counts tests (scripts/test-sentry-counts.sh) — sentry-triage may
#      only gate on counts it CONFIRMED as lifetime (issue #218). `count`/
#      `userCount` mean different things per transport under identical labels:
#      REST is lifetime, the MCP's search_issues rescales to its `period`, and
#      neither says which it returned — velovate's VELOVATE-WORKERS-2 came back
#      1/1 against a true 30/3, and a 30d pull returned 1 event too, so a wider
#      window is not the fix. It went unnoticed because the REST-based routine
#      under daily review was accidentally CORRECT while the interactive run
#      called the surface clean. Pins the discovery/scoring split, the confirm
#      step's position BEFORE the gate, the ban on choosing what to confirm by
#      windowed count (which reads as a missing optimization and re-creates the
#      bug one step earlier), and both halves of `skip-unconfirmed` — never
#      qualifies, always reported. Source-level, flattened must-not-exist
#      checks. No gh, no network, no Sentry call: four tracked files.
#  22. security-listing tests (scripts/test-security-listing.sh) — a
#      security-labelled issue is never collapsed into a bare count (issue
#      #219). The label map used to reach security only via (`bug` AND
#      `security`), so visibility depended on whether the issue happened to be
#      phrased as a defect — and most security work is not (hardening, a
#      missing control, a policy decision). On velovate, two security issues
#      filed the same day at the same severity split P1/P2 on one label, and
#      the P2 one — 72 CodeQL alerts, 10 sites logging raw rider coordinates on
#      a live product — was invisible in every daily-fire-watch post since it
#      was filed. The fix is a LISTING rule, not a promotion, and that is the
#      fragile part: #219 itself proposed promoting security to P1, so a reader
#      arrives pre-loaded with the rejected option, and promotion would
#      re-derive a priority the same file forbids re-deriving. The gate pins
#      the tier-untouched wording, the `unranked` case, and the survival of the
#      re-derive principle itself. Source-level, flattened must-not-exist
#      checks; no gh, no network: two tracked files.
#  23. artifact-guard tests (scripts/test-artifact-guard.sh) — setup-hooks'
#      stray-artifact guard, whose failure mode is SILENCE: every degraded
#      input is deliberately fail-open, so a guard that has stopped firing is
#      indistinguishable from a clean repo and the artifacts quietly resume
#      piling up in the root. Pins the loud cases (exit 2 naming the file; the
#      Stop block JSON) as hard as the quiet ones, all three path-parameter
#      spellings, the deliberate .svg exclusion, and the `stop_hook_active`
#      recursion guard — the one regression that would wedge a session rather
#      than merely miss a file. Caught a real symlink bug on its first run
#      (physical vs logical repo root). Scratch git repos and empty files: no
#      gh, no network, no binaries.
#  24. doc-reconciliation tests (scripts/test-doc-reconciliation.sh) — all
#      THREE shipping paths must tell the agent to fix docs its change made
#      untrue, before the PR body is drafted (issue #220). Docs are an input
#      to no other gate, so lint, type, test and the review agent all pass on
#      a PR whose CLAUDE.md now says the opposite of what the repo does. This
#      gates the INSTRUCTION, never staleness itself: #220 rules that out,
#      because staleness is a semantic judgement with nothing to grep for and
#      a script pretending otherwise reproduces the skimmed-past output of
#      #199. take-it and dispatch-ready matter most — they dispatch sub-agents
#      that open PRs from a cold worktree and never see an interactive
#      session's CLAUDE.md, so a rule living only in send-it never runs for
#      them. Pins both traps in both directions (a closed issue does not prove
#      the behaviour landed; an OPEN one does not prove it did not) and the
#      scope limiter, since an unbounded doc step is one nobody runs.
#      Source-level; its flatten strips blockquote markers, because take-it's
#      rule lives inside a `>` prompt template where a wrap otherwise reads as
#      a missing phrase. Three tracked files, no gh, no network.
#  25. poll-queue-eject tests (scripts/test-poll-queue-eject.sh) — poll-queue.sh
#      may only call `ejected` on evidence it actually has (issue #234). #60's
#      race guard anticipates the PR-STATE flip lagging the queue-entry
#      removal; the removal EVENT lags too, and an empty timeline does not
#      distinguish "never enqueued" from "not visible yet". A tick landing in
#      that window reported qr-ninja#847 — merged cleanly the same second — as
#      EJECTED, wrong in both directions at once: a loud verdict pointing a
#      human at eject recovery, and a silent `"result":"ejected"` in the final
#      JSON that a coordinator branches on. The disproof was already in the
#      script (QSTATES, printed in the failing line). The lag case is now
#      non-terminal, bounded ONLY by the global POLL_MAX_TICKS/exit 124
#      ceiling — no per-PR counter, whose fall-through verdict would re-create
#      the same false eject — so the gate asserts the run reaches that ceiling
#      rather than resolving early, and pins the two cases that must stay
#      terminal (a real eject, a PR that never enqueued) so the fix cannot
#      swallow them. Its prose checks are flattened, both call sites being
#      hard-wrapped. Mock gh serving recorded payloads: no repo, no network.
#  26. template-actionlint tests (scripts/test-template-actionlint.sh) — the
#      three setup-deps WORKFLOW templates are linted by actionlint, in a
#      RENDER (issue #245). Bare actionlint lints `.github/workflows/*`, which
#      here is ci.yml and nothing else, so the highest-consequence YAML in the
#      repo — `pull_request_target`, a minted PLATFORM_WRITER_APP_* token, a
#      push to a PR head ref — was checked by nothing, and a defect there
#      never reddens this repo: it ships to consumers, where Dependabot
#      answers a broken workflow by silently doing nothing. The templates
#      cannot be linted directly (render-time `# {{IF:FLAG}}` blocks and
#      `{{TOKEN}}` substitutions parse as errors that are not defects), so the
#      gate renders each one in every documented shape first — the manual step
#      #232's agent performed by hand. `sassy-dog` is DECLARED to actionlint
#      as a self-hosted label rather than muted with -ignore, so every other
#      unknown label still fails. Four vacuous-green guards (an uncovered
#      template, an IF-arm that is OFF in every variant, a leftover token, and
#      a missing actionlint under CI) plus three mutations. SKIPPED here under
#      CI=true — ci.yml runs it as its own step, after the pinned actionlint
#      install, because $GITHUB_PATH reaches only LATER steps and preflight
#      runs before it. Renders into a tmpdir: no repo, no network.
#  27. review-orchestrator allowlist tests
#      (scripts/test-review-orchestrator-allowlist.sh) — the orchestrator may
#      only dispatch agents this plugin actually ships, and the defect is
#      invisible to the author who ships it: `react-typescript-engineer` and
#      `iac-cloud-architect` exist as USER-LEVEL agents on a typical
#      developer's machine, so a dispatch (or a `review_surfaces:` example)
#      naming one passes every other gate, works when its author tests it, and
#      fails only in a consumer repo. A file-listing comparison against
#      `agents/`, in the shape of gate 8's no-third-copy guard. No gh, no
#      network.
#  28. gotcha-claims tests (scripts/test-gotcha-claims.sh) — a `gotcha_summary`
#      claim about issue state may not reach an issue body unless it has been
#      CONFIRMED against that issue (issue #249). The field is prose in a
#      frontmatter slot, so it is neither derived nor in the `##` lane a human
#      curates: nothing revisits it, and groom-backlog copies it verbatim to a
#      cold worktree agent with no way to check it. solador's asserted three
#      issues were open for nine days after all three closed. The load-bearing
#      case is the KNOWN-STALE fixture — a verifier that accepts everything
#      passes every clean config, so only a config the mock gh contradicts
#      distinguishes one that works — and the second is DEGRADATION: no gh, no
#      repo, a failed lookup must still drop, because a skip here is a silent
#      pass on exactly the input the gate exists for. Its no-gh PATH is a
#      symlink sandbox rather than /usr/bin:/bin, which on a GitHub-hosted
#      runner would quietly mean "gh present". The THIRD failure mode is
#      upstream of the classifier (issue #262): the sentence splitter could not
#      see backticks, so the `;` in `code=0; cmd || code=$?` cut a claim
#      mid-span and the truncated HEAD — citing no #N — was certified an
#      invariant into the SAFE block a caller copies verbatim. Spans are now
#      paired by backtick RUN (a ``…`` delimiter otherwise pairs with itself,
#      leaving the body exposed), and an unpaired run quarantines the WHOLE
#      field, because greedy pairing can mis-bind BEFORE the stray tick. But
#      the guard that BOUNDS the family is GROUP LINKAGE: three narrower fixes
#      each decided where the cut lands and each had a next input, so the
#      fragments of a sentence are now tagged, resolved individually and
#      COMMITTED TOGETHER — a mis-parse costs a drop, never a half-sentence
#      certified. Parity and a padded-span heuristic were both tried and both
#      deleted (the header records why). The root case carries no backtick at
#      all: `;` matched the boundary regex, so a clause dropped and the
#      survivors were welded into an inverted sentence. Seven mutations
#      (neuter the state comparison; treat unresolvable as open; remove group
#      linkage; unmask the span body; pair tick-wise; drop the unpaired
#      quarantine; break the splitter), plus a coverage MATRIX that measures
#      which rule is each fixture's sole protection and fails when that moves,
#      so narrow mutation scoping cannot rot into proving nothing. The
#      sentence-start default is INVERTED (a split needs positive evidence),
#      whose accepted cost is over-linking: a neighbour can be dropped for a
#      citation that is not its own. The class is bounded, not closed —
#      anaphora is out of scope,
#      each reproducing a real fabrication rather than perturbing output; a
#      source guard bans any skip exit; three prose gates pin the contract
#      rule, the injection step, and the template slot — flattened, this repo
#      hard-wraps. Mock gh: no repo, no network.
#  29. review-gate decision tests (scripts/test-review-gate-decisions.sh) — the
#      seven decisions settled about the review gate, all prose and every one of
#      them reading like drift to an "align with the governing principle" sweep
#      (three from #237, issue #247; two from #248, issue #255; one from #273;
#      one from #280).
#      (a) The gate is UNCONDITIONAL: an absent
#      `review_agent:` resolves the shipped `sassy-dog:pr-review-orchestrator`,
#      and #235's verbatim `review: SKIPPED` line survives that default as the
#      backstop for *resolution* failure — deleting it as unreachable restores
#      the original silent-no-review bug wearing a default, since a run that
#      printed nothing is indistinguishable from one that reviewed cleanly.
#      (b) `review_agent` is deliberately NOT presence-is-the-toggle — it has a
#      default, so it was moved OUT of that key list while `review_surfaces` (no
#      default) was moved IN, and "restoring" it turns the absent key back into
#      an off switch for every consumer repo at once. (c) The opt-out is
#      `review_agent: skip`, not `none`: `none` belongs to the `sentry: none`
#      exception, which records an absence somebody went and CHECKED for, and
#      that justification does not apply to a key that merely overrides a
#      default — the missing symmetry is precisely what a tidying sweep closes.
#      (d) `review_site` is CONFIGURED, not derived, deliberately: visibility IS
#      derivable, so a literal reading of "configure only what cannot be
#      derived" deletes the key — and deriving it live means a visibility change
#      silently rewrites a repo's review architecture, downgrading pre-PR review
#      to after-the-fact review with no diff, prompt or output line (the #187
#      failure class). `setup-config` seeds it once and records the value, and
#      the Phase 4 carve-out exempting it from update mode's re-verify-every-
#      fact rule — the half that survives a REFRESH, and the half that lives in
#      another file — is pinned scoped to that phase. (e) A Blocking finding
#      blocks the merge with exactly ONE redispatch, then `blocked`; never
#      merged past, never parked back in Ready. The rationale for the number is
#      pinned with it, since "one" alone reads as an arbitrary retry count.
#      (f) A review report is DELIVERED as the reviewing agent's final text —
#      its return value — and the message tool is not a delivery mechanism for
#      one, since sending needs an address the reviewer cannot reliably resolve:
#      on 2026-08-25, five occurrences across three issues and not one reaching
#      the session that dispatched it — three landed in a coordinator's session,
#      one round lost 2 of 5 dispatches that never returned, and one was
#      addressed to an agent TYPE rather than an address (#273). The dispatching
#      side is pinned in all three shipping paths, because a rule living only in
#      send-it never runs for take-it or dispatch-ready: no path may block, poll
#      or idle while a review it dispatched is outstanding — an implementing
#      agent deadlocked on a report already delivered elsewhere and lost a
#      completed review cycle — and a dispatch that SUCCEEDED whose report never
#      arrived is a THIRD outcome with its own verbatim `review: NO REPORT`
#      line, never #235's SKIPPED line, which says no agent ran at all. THREE
#      parts, pinned separately: RETURNED, never BLOCKED on, and the PR HELD
#      rather than merged. The return-value rule alone still permits a
#      dispatcher that waits forever, and the first two together still permit
#      merging the PR whose review reached nobody — which is the harm itself,
#      so the hold is pinned in both dispatching paths and on the DEFAULT
#      `review_site: agent`, not only inside the coordinator-only sections.
#      (g) The reviewer -> orchestrator hop is bound the SAME way, and the
#      fan-out brief has a slot for it (#280). That hop carries the most
#      traffic — every diff-scoped review fans out to as many as nine — and it
#      was UNBINDABLE, not merely unbound: the brief said it "contains, and
#      contains only" an enumerated set with no delivery rule in it, so an
#      orchestrator following it literally could not pass the contract down,
#      while the nine carried only `Return ONLY a list of findings` — the right
#      verb, never stated to be the only one. Each of the nine now states the
#      full rule, `Return ONLY` is STRENGTHENED rather than swapped, and the
#      delivery rule joins the brief as a MEMBER: the list stays closed,
#      because closedness is what stops a brief re-authoring a reviewer's
#      checklist. The lost-reviewer REPORTING bullet survives unchanged and is
#      pinned as its own bullet — it is the backstop that made this visible on
#      #273's own PR, where round 4 lost three of four surfaces, two of them
#      carrying Blocking findings, and folding the two rules together is the
#      specific tidy #280 refuses. The nine are spelled out and then checked
#      against the tree, so a tenth reviewer cannot ship pinned by nothing —
#      and checked again against the agents the ORCHESTRATOR DISPATCHES,
#      harvested by whether `agents/<name>.md` resolves rather than by name
#      shape (the bare unprefixed form is legal, and `performance-review`
#      matches no `*-reviewer` glob). That verdict is an EQUALITY, which is
#      its vacuity floor: a membership test cannot tell nothing-to-report
#      from nothing-measured, and a neutered harvest was measured printing
#      `ok` with a real tenth target present.
#      Three scoping decisions are load-bearing, each measured: the nine copies
#      are bounded by a CANONICAL LITERAL held in the gate rather than by the
#      phrases named (deleting the paragraph's last sentence from one reviewer
#      left the gate green) — comparing the nine to EACH OTHER was tried first
#      and bounds divergence rather than content, since a uniform edit across
#      all nine stays identical and passes, so each copy is compared against
#      text held outside the files under test, as decision 6 does for the
#      NO REPORT line;
#      each reviewer's assertions are cut to its `## Output` section, the
#      MODE-AGNOSTIC contract, since a whole-file window let the paragraph be
#      relocated into the conditional `## Diff-scoped mode` section — retiring
#      it for every audit-mode run — with the gate still green; and the two
#      TOKEN COUNTS are scoped DIFFERENTLY on purpose, which is the asymmetry a
#      later tidy will collapse. `SendMessage` counts FILE-WIDE, as the
#      orchestrator's own probe does, because a fallback readmitting it is
#      written a section up rather than inside the sentence forbidding it
#      (measured: a bullet in `## Diff-scoped mode` exited 0 when both tokens
#      were paragraph-scoped). `relay` counts over `## Output` PLUS
#      `## Diff-scoped mode` — the two sections a reviewer reads as binding —
#      because it
#      is the one token that could legitimately appear as domain vocabulary (a
#      collector relaying traces, a webhook relay) and a file-wide bound would
#      redden CI on such a calibration bullet, which lives under
#      `## Sassy Dog calibration`, outside BOTH sections. Counting is not a
#      sufficient bound either way: decision 6's known limit governs this hop
#      too, and the CANONICAL LITERAL is what bounds the paragraph.
#      Source-level like gates 12, 20, 21, 22 and 24; its must-not-exist checks
#      run flattened (proved: the same forbidden wording, hard-wrapped between
#      `codegen` and `review_agent`, is invisible to a line-scoped grep and
#      caught by the flattened one), the flatten also stripping blockquote
#      markers because take-it's step-6 rule lives inside a `>` prompt template,
#      and it uses no `| grep -q` pipeline, whose SIGPIPE-plus-pipefail 141
#      reports a caught mutation as a miss (#172). Its own two summary counts —
#      the decision count and the tracked-file count — are RE-DERIVED by the
#      gate rather than transcribed (issue #276), because they were restated in
#      several places and recomputed by nothing. The decisions are counted
#      twice, from the header's enumerated list and from the body banners that
#      carry a `(decision N)` suffix, and the two must agree: a bare count of
#      numbered banners answers a different question (it runs past the
#      decisions into the trailing sweeps) and a discriminator that silently
#      matches nothing re-derives 0 and would pass every count vacuously. The
#      file count is the length of the array the existence loop iterates. A
#      stale restatement in the gate's header, in this list or in CLAUDE.md
#      fails the gate — in the SPELLED forms those sites use; a digit form is a
#      stated blind spot, as it is for the free-floating-count probe in
#      scripts/test-sentry-verification.sh. Its count-re-derivation section
#      carries its own mutation battery in the PR that added it. Every decision here is
#      mutation-proved, each battery living in the PR that added it rather than
#      as a total transcribed here to go stale. Twenty tracked files plus a
#      tracked-source sweep for a fourth site, no gh, no network.
#  30. pipefail-grep guard (scripts/test-pipefail-grep.sh) — no script under
#      `pipefail` may feed an UNBOUNDED writer into `grep -q` (issue #256,
#      generalising #172). grep -q closes the pipe on its first match, the
#      writer takes SIGPIPE, pipefail promotes the 141 — so the pipeline reports
#      failure precisely WHEN IT MATCHED, but only once the output outruns the
#      ~64KB pipe buffer. Nothing generalised #172: gate 11 pins one function by
#      name, and the shape recurred in PR #252, where a `scan … | grep -q` made
#      three of that gate's four mutation proofs report `undetected`. The RULE
#      is deliberately narrow and must not be "simplified": flag every pipeline
#      into `grep -q` whose SOURCE stage is not `printf` or `echo` — purely
#      syntactic, ~12 sites on the tree it landed on, all fixed in that PR. Both
#      wider options were rejected on #256 (a per-site opt-out marker: ~128
#      annotations that degrade into paste; a blanket ban: a ~131-line rewrite
#      of the scripts this repo relies on to catch its own regressions). Its
#      known limitation is stated in its own header: a huge variable through
#      `printf` slips past, because no syntactic check knows a variable's size.
#      The linter does NOT cover this — verified against shellcheck 0.11.0,
#      which says nothing about the shape and whose SC2143 actively RECOMMENDS
#      `grep -q`.
#      Exemptions are a central table in the guard keyed by (file, substring),
#      never an inline marker, and a stale one FAILS; there is exactly one, the
#      pre-#172 shape gate 11 transcribes verbatim. Fixtures are tracked under
#      scripts/fixtures/pipefail-grep/ and deliberately not `*.sh`, because the
#      guard is in its own scan scope and a printf-built fixture makes it flag
#      itself (measured — the first draft did). No gh, no network.
#  31. claim-lifecycle tests (scripts/test-claim-lifecycle.sh) — issue-claim.sh
#      writes a claim as TWO things (assignee @me + in-progress, one edit) and
#      clears it as ONE (in-progress), and `promote` may only clear the half
#      that is residue BY CONSTRUCTION (issue #281). On a CLOSED issue the
#      leftover assignee is correct — it records who shipped it — so the defect
#      is reachable only on REOPEN, where dispatch-ready §4 skips on "assignee
#      set OR label state" (a disjunction) while §3 defines in-flight as
#      assignee AND label (a conjunction): a reopened, re-promoted issue lands
#      in ready[] still assigned and is skipped as "another session got it",
#      which is false, silent, and never dispatches. BOTH obvious fixes were
#      rejected on #281 and are pinned here as NEGATIVES, because each is what a
#      later "make this symmetric" sweep reaches for: making `release` clear the
#      assignee destroys the who-shipped-it record on every closed issue, and
#      aligning §4's disjunction to §3's conjunction discards the guard for a
#      human who self-assigned without setting in-progress — so this gate never
#      reads dispatch-ready/SKILL.md and nothing in it licenses that edit.
#      THE PREMISE IS ASSERTED, NOT ASSUMED: "@me AND no in-progress -> residue"
#      holds only because `claim` writes both halves together, so a `claim` that
#      split them would turn the discriminator into a guess with every promote
#      case still green — the pairing is therefore pinned on its own. Every
#      assertion about the guard's BEHAVIOUR is behavioural, against a mock gh
#      that records writes, since a source-level grep for the guard's wording is
#      satisfied by a guard that no longer runs, and the harm being prevented is
#      a WRITE; exactly ONE check is source-level and it reads SKILL.md rather
#      than the guard, cut at the `promote` bullet. THE PROBE'S TRANSPORT is its
#      own failure mode: TAB is IFS whitespace, so `@tsv` through `read`
#      collapses the leading empty field and an unassigned issue reads its own
#      LABELS as its assignees. With `state` as a third field the broken idiom
#      shifts EVERY unassigned shape, but it was invisible in the two-field
#      draft this replaced, where an unassigned issue with NO labels was the one
#      shape it read correctly — which is exactly how that draft's fixture
#      missed it. The gate now carries an unassigned-WITH-labels fixture and
#      proves adequacy by RUNNING the pre-fix idiom against the fixture store
#      itself (the #263 posture; gate 11 does the same for its own fixture). The mutant
#      inventory is an ARRAY whose length the run prints and whose every member
#      it asserts ran, so no count here can go stale (#276); each is applied by
#      exact whole-line awk match that fails unless it hit exactly once (the
#      #262 lesson: `cmp -s` exits 2 on a missing file, which an `if` reads as
#      "differs"), and each is caught by the edit it causes rather than by a
#      literal an assertion greps for. STATED LIMIT: `@me` is the operator's
#      login, not a loop identity, so the operator's own self-assignment is
#      byte-identical to the residue; narrowing that needs a fourth conjunct
#      #281 does not sanction, filed as issue #287 (where reopen evidence alone
#      is recorded as insufficient — `block` leaves an assignee with no close in
#      the history). A CLOSED issue is refused in the gate's own body, not left
#      to the caller. No taxonomy colour is transcribed —
#      the mock's label store is seeded from the `taxonomy` emitter, gate 8's
#      no-third-copy rule. Mock gh only: no repo, no network.
#  32. drain terminal-state tests (scripts/test-drain-terminal-states.sh) —
#      `dispatch-ready` §7's two terminal states must COVER the state where
#      Ready is empty, in-flight is zero, and an open unmerged PR sits there
#      that this loop is not permitted to advance (issue #282). They did not:
#      COMPLETE is vetoed by the open PR and STALLED required Ready non-empty,
#      so neither branch was reachable and the loop ticked forever — accurately
#      reporting the state and doing nothing, unable to self-cancel. The stall
#      record could not help, being written only INSIDE the STALLED branch, so
#      the two-tick clock never started. THE ACTION THAT CREATES THE STATE IS
#      THE ACTION THAT HIDES IT: `issue-claim.sh block` strips `ready` and
#      `in-progress` together, so recording "a human must decide this" removes
#      the issue from the one set the old conjunct consulted (observed
#      2026-08-26 on #273 / PR #279; cancelled by hand).
#      THE ENUMERATION IS PART OF THE FIX, not a detail of it, and the first
#      edition of that fix omitted it and was WORSE THAN THE BUG: §2's only PR
#      discovery was the branches of IN-FLIGHT issues, and `block` strips
#      `in-progress`, so in #282's own state the tick enumerated zero PRs. A
#      held set empty because nothing was looked at is indistinguishable from
#      one empty because nothing is held — STALLED is then forbidden by the
#      non-empty rule while COMPLETE is admitted, and the loop announces DRAIN
#      COMPLETE and self-cancels with a human-gated PR still open. The
#      forever-tick at least never claimed to be finished.
#      THE SET HAS TO BE ONE SET: COMPLETE's veto and §7's held set must range
#      over the SAME PRs, since any PR that vetoes COMPLETE but can never enter
#      the held set gives Ready-empty + in-flight-zero + held-empty — #282 one
#      shape over, which an unqualified "any open PR vetoes COMPLETE" produces
#      the moment a Dependabot or hand-opened PR is sitting there. And BOTH
#      HALVES SPAN BOTH PATHS, because the blocked set is `blocked[]` only
#      without a board and a bullet written for one path is invisible on the
#      other — which is how a board repo would have kept the bug with every
#      assertion green.
#      THE FIX IS A DISCRIMINATOR, NOT A DELETED CONJUNCT, and the deletion is
#      what a later "this conjunct does nothing" sweep re-derives: an open PR is
#      not automatically a human gate — one whose checks are running or red can
#      still advance on its own. So the third conjunct is "nothing this loop is
#      permitted to advance" and a table decides which side an open PR falls on,
#      hinged on §2's ONE redispatch. ITS LAST ROW IS A DEFAULT and is pinned as
#      one, since §2 holds a PR for more reasons than the rows enumerate and a
#      table that silently answers "alive" for a shape it does not know
#      re-creates #282 one shape at a time; `CONFLICTING` is the measured case,
#      stopping CI from firing at all so that `no checks reported` reads exactly
#      like `CI hasn't started`. Rows 2-6 cannot fire at the moment STALLED is
#      decided — in-flight zero empties the branch half of the union — and §7
#      SAYS so, because a reader who works it out will otherwise trust them as
#      live or delete them as dead.
#      HOW IT IS BOUND, IN THREE LAYERS, each added after a review defeated the
#      one before it, and layer 1 now covers §7 WHOLE — FENCES INCLUDED.
#      Presence-only assertions were measured passing rewrites that KEPT the
#      sentence and QUALIFIED it; whole-paragraph equality was defeated by
#      INSERTING A SIBLING PARAGRAPH; a hand-picked SUBSET of paragraphs was
#      then defeated five rounds running, each time by a paragraph no key held
#      that inverted one a key did — including the API-failure rule a pinned
#      paragraph merely DELEGATES to. So: (1) CANON, every blank-line block of
#      §7 compared for equality after flattening, so a bullet body and a table
#      cell are as pinned as a paragraph, PLUS every fenced block with `#N`
#      normalised — the fences are the text the loop PRINTS, and a parenthetical
#      added inside the DRAIN COMPLETE fence was measured restoring #282 at exit
#      0 with markdownlint clean; (2) INVENTORY, the ordered lists of block
#      openers, list markers, table rows and headings for §7 AND for §2, §4, §6
#      and the top-level Guardrails list — Guardrails already restates a
#      §7-adjacent rule today, so hoisting one there has precedent in that very
#      file. §3 is pinned by TEXT rather than inventoried, being the file's only
#      "in-flight is" sentence, which §2, §4 and §7 all read: re-including
#      `blocked` there, or inverting "a green PR in the merge queue still counts
#      as in-flight", were each measured at exit 0 while §3 sat outside every
#      window. §5 and §1 are still unread, which is stated limit (6); (3)
#      CONSUMPTION, every canon key consumed by exactly one assertion. The claim
#      is "identical after flattening", NOT "byte-identical", and the inventory
#      keeps each opener's first words only. Must-not-exist checks run against a
#      flattened AND an emphasis-stripped copy, and FAIL CLOSED on a malformed
#      pattern — grep exits 2 on an invalid ERE, which an `if grep … || grep …`
#      reads as "not found", so every must-not-exist check was failing open,
#      three of them carrying #282's own decision. Every
#      line-scoped check runs against a resolved window; table-row patterns are
#      anchored `^[[:space:]]*\|`; example identifiers are matched by SHAPE.
#      ITS VACUITY FLOOR IS A SECTION REGISTRY WITH PER-SECTION MINIMUMS —
#      `name:count`, members enumerated beside their counts, the floor DERIVED
#      as their sum — because a bare number was measured not binding three times
#      over. The registry block's OWN minimum is held apart from that array
#      (`REGISTRY_MIN`), since while it was a summand, deleting the block and
#      its entry shrank the floor by exactly what the deletion removed. FIVE
#      known limits are stated in its header rather than patched, and that
#      enumeration and this one must agree: §2, §6 and Guardrails are
#      inventoried but not content-pinned, so rewriting the BODY of an existing
#      bullet there can invert §7 from outside it; removing a section quietly
#      takes two to three coordinated edits; canon values are regenerated by
#      hand; a gate cannot verify its own guard from inside it; markdownlint
#      remains load-bearing for a malformed table; and §5 and §1 are unread. THE
#      FLOOR VALIDATES ITS OWN INPUTS, after one deleted digit was measured
#      voiding it at exit 0 on bash 3.2 — the arithmetic aborted mid-loop and
#      dropped every later summand, and an unset `REGISTRY_MIN` ran ZERO
#      assertions and still exited 0. THE PREMISE IS ASSERTED, NOT ASSUMED:
#      `issue-claim.sh`'s `block` case is read for the one fact everything rests
#      on — that it strips BOTH labels — since if it stripped only `ready` the
#      whole account of the bug would be wrong with every prose assertion still
#      green. Its header records why it carries no `-ef` precondition and what
#      that costs a mutation harness. The assertion count is printed, never
#      transcribed. Two tracked files, no gh, no network.
#  33. audit lost-reviewer tests (scripts/test-audit-lost-reviewer.sh) — the
#      nine `*-reviewer` agents serve TWO orchestrators and only one of them
#      scored a reviewer that came back with nothing. `pr-review-orchestrator`
#      Step 5 marks such a surface `!` and names it on every run; `assess-it`
#      had no equivalent, so a reviewer that returned nothing was
#      indistinguishable from one that found nothing (issue #284). AUDIT MODE IS
#      THE WORSE PLACE FOR IT because it WRITES: the artefact is a filed Epic
#      and its child issues, so a lost `security-reviewer` yields a backlog that
#      omits a whole domain and READS COMPLETE to everyone who finds it later.
#      THE HARM LANDS AT THE PREVIEW, NOT AT THE REPORT — `assess-it` already
#      previews before it files, so the requirement is POSITIONAL: the dark
#      domains are named IN the preview and BEFORE the approval prompt, and a
#      rule landing after the ask, or in Phase 5, documents a backlog already
#      filed. AND IT IS NOT A VETO: filing still proceeds on approval, so both
#      halves are pinned because either alone is wrong. Bound the way gate 32
#      is, and for its reasons: (1) CANON over BOTH FILES WHOLE, every
#      blank-line block AND every FENCE compared for equality after flattening —
#      Phase 4's ```text fence IS the coverage block the run prints, so
#      excluding it would leave the one artefact #284 is about writable. It
#      covered seven TARGETED windows for one review round, until six
#      meaning-inverting rewrites were measured passing at 79/79, every one of
#      them in a block OUTSIDE those windows where nothing bound an existing
#      block's BODY — including a seventh item appended to orchestration.md's
#      Phase-2 ordered list reading "Drop dark domains … remove it from the
#      ledger before Phase 3". THE SUBSET WAS THE DEFECT, NOT THE CHOICE OF
#      SUBSET, which is gate 32's lesson relearned here; (2) INVENTORY,
#      openers, bullets, ORDERED-LIST items, table rows and headings for both
#      files whole, the ordered list being the one carrying #284's own decision
#      since Phase 4's ITEM ORDER is the fix — and it was missing on
#      orchestration.md entirely in that first edition, which is how the list
#      above went unseen; (3) CONSUMPTION, every canon key consumed and every
#      window's block and fence counts equal to its canon entry counts. THERE IS
#      DELIBERATELY NO PROSE VETO, the asymmetry with the prose-veto gates
#      (test-sentry-verification.sh, test-review-gate-decisions.sh) that a later
#      sweep will try to close: both veto editions built for the latter reported
#      clean on inverted sources, canon plus inventory already answers what a
#      veto would ask, and the only must-not-exist checks are for the #283
#      residue note's own literals — a literal deletion verified, not a polarity
#      judgement — run flattened AND emphasis-stripped. THE PREMISE IS ASSERTED: the ledger says
#      "every domain in the table above", so the map's rows are compared to
#      `agents/*-reviewer.md` as an EQUALITY over a count floor, since a stale
#      map would leave a whole domain with no row to be dark in while every
#      prose assertion stayed green. `agents/pr-review-orchestrator.md` is read
#      for exactly ONE fact — that its own `!` bullet survives — and nothing
#      else about it is pinned here; gate 29 owns that file. Its floor is a
#      section registry with per-section minimums whose sum is DERIVED, every
#      token validated before arithmetic touches it, and `REGISTRY_MIN` held
#      apart from the array. Three tracked files plus a listing of `agents/`,
#      no gh, no network.
#
# All gates run even after a failure (accumulate-and-report, same pattern as
# check-frontmatter.sh). Exit 0 = all pass, 1 = any fail. Tools that are not
# installed locally SKIP with a note — CI still enforces them.
set -uo pipefail

MARKDOWNLINT_PKG="markdownlint-cli2@0.18.1"
ACTIONLINT_IMAGE="rhysd/actionlint:1.7.7"

FIX=0
case "${1:-}" in
    --fix) FIX=1 ;;
    "") ;;
    *) echo "usage: bash scripts/preflight.sh [--fix]" >&2; exit 64 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && { echo "preflight: not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

fail=0
pass() { echo "PASS  $1" >&2; }
# Gates are non-interactive by contract, and one of them harvests with `awk`,
# which reads STDIN when it is handed no file operands. A regression there should
# redden this run rather than hang it — measured: exactly that hung a run for ten
# minutes before the gate grew its own `</dev/null` (issue #263).
exec </dev/null
failed() { echo "FAIL  $1" >&2; fail=1; }
skip() { echo "SKIP  $1" >&2; }

# --- 1. shellcheck ----------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    sh_files=$(git ls-files '*.sh')
    if [ -z "$sh_files" ]; then
        pass "shellcheck (no *.sh files)"
    elif echo "$sh_files" | xargs shellcheck -S warning; then
        pass "shellcheck -S warning"
    else
        failed "shellcheck -S warning"
    fi
    # SC2006 IS A SEPARATE PASS BECAUSE IT IS `style`, AND THE ONE ABOVE STOPS
    # AT `warning`. That severity gap is the whole reason a real defect shipped
    # twice: an UNESCAPED backtick inside a double-quoted test label is command
    # substitution, so `dest_case "a `which` clause …"` runs `which` and prints
    # the label with its identifying word eaten. It happened in
    # test-sentry-verification.sh, was documented in CLAUDE.md, and then
    # happened again in the same file — three labels, executing `which`, `that`
    # and `where`, which is how a mutation of one rule produced three
    # indistinguishable FAIL lines in the gate that exists to say which rule
    # broke. Prose did not stop the recurrence; this does.
    #
    # A BESPOKE GREP WAS TRIED AND REJECTED: distinguishing a backtick inside a
    # double-quoted argument from one inside a single-quoted string is a
    # quoting-context question, and a hand-rolled scan of this repo produced 3
    # true positives against 7 false ones. shellcheck already parses the shell,
    # so it answers exactly that question — measured on a two-line fixture, the
    # unescaped form is flagged and the escaped form is not.
    #
    # NEITHER ONE-PASS SHORTCUT WORKS, both measured, so that the next person
    # weighing this does not re-derive them. Adding `--include=SC2006` to the
    # pass above reports NOTHING: the severity filter still applies to an
    # included check, so `-S warning` suppresses a `style` rule even when it is
    # named. And dropping the tree-wide run to `-S style` yields 208 findings
    # across 11 rules on this tree, which is not adoptable today. Two passes is
    # the cheap option, not the lazy one.
    #
    # COST, measured: the SC2006 pass is ~5s against a ~48s preflight, about
    # 11%. It re-parses every tracked *.sh, which is the price of shellcheck
    # having no way to ask one question of an existing parse.
    #
    # Bare `xargs` here and in the pass above ASSUMES no tracked `*.sh` path
    # contains whitespace — verified, none today. (A count was written here and
    # went stale the next time a script was added; the assumption is what
    # matters, and it is re-checked by the run itself failing loudly.) If that
    # ever changes both call sites need `-0` with `git ls-files -z`.
    if [ -n "$sh_files" ]; then
        if echo "$sh_files" | xargs shellcheck --include=SC2006; then
            pass "shellcheck SC2006 (unescaped backticks in strings)"
        else
            failed "shellcheck SC2006 (unescaped backticks in strings)"
        fi
    fi
else
    skip "shellcheck (not installed — CI still enforces)"
fi

# --- 2. frontmatter ---------------------------------------------------------
if bash scripts/check-frontmatter.sh; then
    pass "frontmatter sanity"
else
    failed "frontmatter sanity"
fi

# --- 3. no bare positional tokens in Skill-args substitution surfaces -------
# SKILL.md bodies (and the config templates that render into consumer repos)
# get $1-$9/$ARGUMENTS substituted when the skill is invoked with args — a
# literal $1 in a snippet is corrupted at render time. references/ docs and
# scripts/ (including this one) are not substituted.
#
# The template pathspec is asserted non-empty FIRST. A pathspec that matches
# nothing makes `git ls-files` emit no paths, so the guard would still pass
# while silently covering nothing — which is exactly what a rename of the
# generator directory used to cause. Fail loudly instead.
POSITIONAL_TEMPLATE_GLOB='skills/setup-config/references/templates/*'
if [ -z "$(git ls-files "$POSITIONAL_TEMPLATE_GLOB")" ]; then
    failed "positional-token guard — template pathspec '$POSITIONAL_TEMPLATE_GLOB' matched no tracked files (renamed or moved? the guard would silently cover nothing)"
else
    # shellcheck disable=SC2016  # the regex is a literal, not a missed expansion
    if git ls-files 'skills/*/SKILL.md' '.claude/skills/*/SKILL.md' "$POSITIONAL_TEMPLATE_GLOB" \
        | xargs grep -nE '\$([0-9]|@|\*)'; then
        failed "positional-token guard — use cut -f1/%(format) idioms or move the snippet to references/ or scripts/ (issue #39)"
    else
        pass "positional-token guard"
    fi
fi

# --- 4. no legacy skill-name residue -----------------------------------------
# The whole generator family was renamed to setup-* in issue #120:
#   create-dev-workflows -> refresh-sassydog-skills (0.9.0)
#   refresh-sassydog-skills -> refresh-skills (2026.7.22)
#   refresh-skills -> setup-config (issue #121)
#   refresh-hooks -> setup-hooks (issue #122)
#   refresh-deps  -> setup-deps  (issue #123)
# Every superseded name may appear only in the sanctioned backward-compat
# mentions — the ownership matchers still have to RECOGNISE artifacts produced
# under the older names, and those markers are committed inside every consumer
# repo. Anything else is a stale reference that would confuse a render or send
# a reader to a dead path.
#
# Exclusions are PER NAME, not one shared union: a name is sanctioned in
# exactly the files that must still spell it out. A union list would let a
# stale `refresh-deps` hide in a file sanctioned only for `refresh-skills`,
# which is the residue this guard exists to catch.
legacy_residue=0
for legacy in 'create-dev-workflows' 'refresh-sassydog-' 'refresh-skills' 'refresh-hooks' 'refresh-deps'; do
    case "$legacy" in
        refresh-skills)
            # setup-config's marker recognizer, the adopt/update walkthrough
            # that names the superseded producer, and CLAUDE.md's statement of
            # the same recognition rule.
            allow=(
                ':!skills/setup-config/SKILL.md'
                ':!skills/setup-config/references/update-mode.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
            ) ;;
        refresh-hooks)
            # setup-hooks' generated-by ownership matcher + CLAUDE.md's
            # statement of it, plus the committed consumer artifacts that
            # PROVE the matcher still accepts this producer name (issue #133 —
            # the fixtures are verbatim upstream bytes; sanitising the name out
            # of them would defeat their entire purpose).
            allow=(
                ':!skills/setup-hooks/SKILL.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
        refresh-deps)
            # setup-deps' generated-by ownership matcher + the committed
            # consumer artifacts proving the matcher accepts it (issue #133).
            allow=(
                ':!skills/setup-deps/SKILL.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
        *)
            # 'refresh-sassydog-' also appears verbatim inside the committed
            # consumer hook fixtures (issue #133).
            allow=(
                ':!skills/setup-config/references/update-mode.md'
                ':!skills/setup-config/references/migrate-mode.md'
                ':!skills/setup-config/SKILL.md'
                ':!skills/setup-deps/SKILL.md'
                ':!skills/setup-hooks/SKILL.md'
                ':!CLAUDE.md'
                ':!scripts/preflight.sh'
                ':!scripts/fixtures/legacy-markers/'
            ) ;;
    esac
    if git grep -l "$legacy" -- "${allow[@]}"; then
        failed "legacy-name guard — '$legacy' outside the sanctioned back-compat files"
        legacy_residue=1
    fi
done

# The plugin itself renamed too: ai-agent-skills -> sassy-dog, the marketplace
# sassy-dog-skills -> sassydog-skills (issue #71), and the GitHub repo
# ai-agent-skills -> sassydog-skills (issue #72). The old plugin name may
# appear ONLY where it is still load-bearing:
#   - README.md — the one historical line recording the #71 rename
#   - CLAUDE.md — the marker-recognition rule: recognizers must accept
#     pre-rename 'generated-by: ai-agent-skills:*' markers
#   - skills/setup-deps/SKILL.md, skills/setup-hooks/SKILL.md — those
#     generated-by recognizers themselves. Their markers are committed inside
#     every consumer repo, so each must also keep naming its own superseded
#     producers (setup-hooks accepts refresh-hooks and refresh-sassydog-hooks,
#     see issue #122; setup-deps accepts refresh-deps and refresh-sassydog-deps,
#     see issue #123) — a narrower matcher would silently treat a pre-rename
#     consumer file as hand-written.
#   - scripts/fixtures/legacy-markers/ — real consumer artifacts still stamped
#     with the pre-rename namespace, committed verbatim so the matchers are
#     proven against a genuine older-plugin file rather than a synthetic
#     pattern we wrote ourselves (issue #133)
#   - this script (the guard itself)
if git grep -l 'ai-agent-skills' -- \
    ':!README.md' \
    ':!CLAUDE.md' \
    ':!skills/setup-deps/SKILL.md' \
    ':!skills/setup-hooks/SKILL.md' \
    ':!scripts/preflight.sh' \
    ':!scripts/fixtures/legacy-markers/'; then
    failed "legacy-name guard — 'ai-agent-skills' outside the sanctioned files (plugin renamed to sassy-dog, issue #71)"
    legacy_residue=1
fi

# The old marketplace name may appear only in the one-time re-add
# instructions (which must name it to remove it) and this script.
if git grep -l 'sassy-dog-skills' -- \
    ':!README.md' \
    ':!scripts/preflight.sh'; then
    failed "legacy-name guard — 'sassy-dog-skills' outside the sanctioned files (marketplace renamed to sassydog-skills, issue #71)"
    legacy_residue=1
fi

# Four workflow skills lost the -it suffix in the collection-scope naming
# sweep: plate-it -> survey-work, groom-it -> groom-backlog (nee fill-it),
# drain-it -> dispatch-ready, clean-it -> tidy-repo. Each legacy name may
# appear ONLY where it is still load-bearing:
#   - the renamed skill's own SKILL.md — legacy trigger phrases, the
#     "Formerly" note, and the stranded-pre-rename-config detection
#   - skills/setup-config/SKILL.md + references/{migrate,update}-mode.md —
#     the rename map and legacy-artifact recognition (generated dirs and
#     pre-rename config filenames keep their old names in consumer repos)
#   - skills/whats-on-fire/SKILL.md — the blind-spot probe distinguishes a
#     legacy-named survey-work config from a missing one
#   - README.md — the "(formerly ...)" annotations
#   - this script (the guard itself)
for legacy in 'plate-it' 'groom-it' 'drain-it' 'clean-it'; do
    if git grep -l "$legacy" -- \
        ':!skills/survey-work/SKILL.md' \
        ':!skills/groom-backlog/SKILL.md' \
        ':!skills/dispatch-ready/SKILL.md' \
        ':!skills/tidy-repo/SKILL.md' \
        ':!skills/setup-config/SKILL.md' \
        ':!skills/setup-config/references/migrate-mode.md' \
        ':!skills/setup-config/references/update-mode.md' \
        ':!skills/whats-on-fire/SKILL.md' \
        ':!README.md' \
        ':!scripts/preflight.sh'; then
        failed "legacy-name guard — '$legacy' outside the sanctioned back-compat files (naming sweep: collection-scoped skills lost -it)"
        legacy_residue=1
    fi
done

[ "$legacy_residue" -eq 0 ] && pass "legacy-name guard"

# --- 5. plugin manifests -----------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    if jq -e . .claude-plugin/plugin.json .claude-plugin/marketplace.json >/dev/null; then
        pass "plugin manifests valid JSON"

        # Version-of-record guard (issue #31; docs/VERSIONING.md; org
        # Versioning spec §7 committed-manifest row). CalVer adoption is a
        # ONE-WAY RATCHET: a hand-rolled 0.x/1.x here reads as a permanent
        # downgrade to version-ordering consumers. Stamp via
        # scripts/stamp-version.sh, never by hand.
        plugin_version=$(jq -r '.version // empty' .claude-plugin/plugin.json)
        if echo "$plugin_version" | grep -qE '^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$'; then
            pass "plugin version is CalVer ($plugin_version)"
        else
            failed "plugin version '$plugin_version' is not CalVer (YYYY.M.P) — stamp via scripts/stamp-version.sh (docs/VERSIONING.md)"
        fi

        # One repo-wide CalVer: any plugins[].version in marketplace.json
        # must equal the version-of-record (per-plugin drift forbidden).
        if jq -e --arg v "$plugin_version" \
            '[.plugins[]? | select(has("version")) | .version == $v] | all' \
            .claude-plugin/marketplace.json >/dev/null; then
            pass "marketplace plugins[].version matches version-of-record"
        else
            failed "marketplace.json plugins[].version differs from plugin.json — one repo-wide CalVer; stamp via scripts/stamp-version.sh"
        fi
    else
        failed "plugin manifests valid JSON"
    fi
else
    skip "plugin manifests (jq not installed — CI still enforces)"
fi

# --- 6. versioning tests -------------------------------------------------------
if bash scripts/test-versioning.sh; then
    pass "versioning tests (scripts/test-versioning.sh)"
else
    failed "versioning tests (scripts/test-versioning.sh)"
fi

# --- 7. ownership-matcher tests -----------------------------------------------
if bash scripts/test-ownership-matchers.sh; then
    pass "ownership-matcher tests (scripts/test-ownership-matchers.sh)"
else
    failed "ownership-matcher tests (scripts/test-ownership-matchers.sh)"
fi

# --- 8. label-taxonomy tests ---------------------------------------------------
# Definitions + a mock gh. #158 deliberately kept align-labels.sh out of CI
# because it MUTATES other repos — this gate runs neither applying mode, only
# the cross-set colour check (`--collisions`, which needs no repo and no
# network) and issue-claim.sh's reconcile logic against a recorded mock.
if bash scripts/test-label-taxonomy.sh; then
    pass "label-taxonomy tests (scripts/test-label-taxonomy.sh)"
else
    failed "label-taxonomy tests (scripts/test-label-taxonomy.sh)"
fi

# --- 9. label-migrate tests ----------------------------------------------------
# Same rule as gate 8, one notch more dangerous: align-labels.sh's migrate mode
# DELETES labels in other repos, and a delete strips the label from every issue
# carrying it unrecoverably. So CI runs the mode's PROOF, never the mode — a
# mock gh that records writes, plus a source-level invariant (one delete call
# site, inside the gate, downstream of the re-query) and a mutation that
# neuters the gate to show the withheld delete was withheld BY it (issue #163).
if bash scripts/test-label-migrate.sh; then
    pass "label-migrate tests (scripts/test-label-migrate.sh)"
else
    failed "label-migrate tests (scripts/test-label-migrate.sh)"
fi

# --- 10. dependabot-render tests -----------------------------------------------
# setup-deps stopped being valid-by-construction when its template gained a
# per-(ecosystem, directory) repeat (issue #169), so the render is checked
# dynamically instead — here against recorded consumer file lists, and at run
# time by validate-dependabot.sh against the repo being written into. The gate
# also asserts the OLD shape fails: a validator that accepts every lane
# collapsed onto "/" proves nothing.
if bash scripts/test-dependabot-render.sh; then
    pass "dependabot-render tests (scripts/test-dependabot-render.sh)"
else
    failed "dependabot-render tests (scripts/test-dependabot-render.sh)"
fi

# --- 11. detect-hook-stack tests -----------------------------------------------
# The bug this pins (issue #172) is size-dependent: `has_tracked` returned the
# writer's SIGPIPE 141 rather than "match" once the match list overran the pipe
# buffer, so the five affected detections under-reported on exactly the largest
# repos and the render dropped a route with nothing in the output to say so. A
# small fixture proves nothing here, so the test builds a 20k-path index-only
# repo and asserts BOTH that the pre-fix shape still fails on it (else the test
# has gone vacuous) and that the shipped probe does not.
if bash scripts/test-detect-hook-stack.sh; then
    pass "detect-hook-stack tests (scripts/test-detect-hook-stack.sh)"
else
    failed "detect-hook-stack tests (scripts/test-detect-hook-stack.sh)"
fi

# --- 12. visibility preconditions -------------------------------------------
# sassydog-skills went public on 2026-08-12 and its auto-merge workflow was
# deleted rather than re-credentialed (#177). Without this gate the next
# setup-deps run would put it straight back: a merge gate is present, and the
# gate was the only precondition the skill checked. The failure it reintroduces
# is invisible at render time and surfaces elsewhere, later, looking unrelated.
# #186 widened this from the auto-merge workflow to every template that mints
# the App token, after the same failure was found open through two other doors.
if bash scripts/test-visibility-preconditions.sh; then
    pass "visibility precondition tests (scripts/test-visibility-preconditions.sh)"
else
    failed "visibility precondition tests (scripts/test-visibility-preconditions.sh)"
fi

# --- 13. verify-issue-refs tests ---------------------------------------------
if bash scripts/test-verify-issue-refs.sh; then
    pass "verify-issue-refs tests (scripts/test-verify-issue-refs.sh)"
else
    failed "verify-issue-refs tests (scripts/test-verify-issue-refs.sh)"
fi

# --- 14. stale-issues tests ---------------------------------------------------
# The tracking-parent-complete detector is the only thing that notices a
# finished epic, so every way it can be wrong is silent: a miss looks like a
# clean repo, a prefix collision points a human at live work, and a truncated
# pull returns the empty list a clean pull returns. The prefix fixture is
# mutation-proved live rather than trusted. Mock gh only: no repo, no network.
if bash scripts/test-stale-issues.sh; then
    pass "stale-issues tests (scripts/test-stale-issues.sh)"
else
    failed "stale-issues tests (scripts/test-stale-issues.sh)"
fi

# --- 15. teardown-args tests ---------------------------------------------------
# Every wrong answer here is quiet: a flag taken for a worktree path fails in
# the middle of a run whose visible output is dominated by successful teardown
# lines, and the phase that never ran leaves no trace. So the gate asserts the
# phases are REACHED and that they did their work, and that a rejected argument
# list mutates nothing at all. Scratch repos + a mock gh: no real repo, no
# network, and the fixture is verified to be its own git root before teardown
# runs in it (teardown resolves its target by walking up from cwd).
if bash scripts/test-teardown-args.sh; then
    pass "teardown-args tests (scripts/test-teardown-args.sh)"
else
    failed "teardown-args tests (scripts/test-teardown-args.sh)"
fi

# --- 19. scanning-states tests -----------------------------------------------
# Every failure mode here emits well-formed JSON carrying a plausible number, so
# nothing downstream can tell a wrong answer from a right one. Mock gh only: no
# repo, no network.
if bash scripts/test-scanning-states.sh; then
    pass "scanning-states tests (scripts/test-scanning-states.sh)"
else
    failed "scanning-states tests (scripts/test-scanning-states.sh)"
fi

# --- 20. sentry-verification tests -------------------------------------------
# The decisions under test are prose an agent follows, not code a script runs, so
# the gate reads the instructions themselves. Every failure it guards is silent by
# construction — a mis-configured Sentry project produces a plate that looks
# complete in both repos, and a `none` form flattened to symmetry produces a plate
# that looks complete on a repo whose Sentry nothing is watching. Four decisions:
# #213's culprit verification, `sentry: none` as the contract's first documented
# exception, #261's deliberately ASYMMETRIC four-key `none`, and #268's
# carry-forward split — the `none` carve-out covers three keys and NOT `sentry:`,
# asserted at all four sites that state it. The run prints its own assertion
# count, so no inventory number here can go stale.
# Eight tracked files: no gh, no network.
if bash scripts/test-sentry-verification.sh; then
    pass "sentry-verification tests (scripts/test-sentry-verification.sh)"
else
    failed "sentry-verification tests (scripts/test-sentry-verification.sh)"
fi

# --- 21. sentry-counts tests -------------------------------------------------
# Also prose, and the failure it guards is a false CLEAN rather than a false
# alarm: an under-reported count does not look wrong, it looks quiet. Reads four
# tracked files; no gh, no network, no Sentry call.
if bash scripts/test-sentry-counts.sh; then
    pass "sentry-counts tests (scripts/test-sentry-counts.sh)"
else
    failed "sentry-counts tests (scripts/test-sentry-counts.sh)"
fi

# --- 22. security-listing tests ----------------------------------------------
# Also prose, and also a false CLEAN rather than a false alarm: the issue was
# counted, so the report looked complete while naming nothing. Two tracked
# files; no gh, no network.
if bash scripts/test-security-listing.sh; then
    pass "security-listing tests (scripts/test-security-listing.sh)"
else
    failed "security-listing tests (scripts/test-security-listing.sh)"
fi

# --- 16. markdownlint --------------------------------------------------------
if command -v npx >/dev/null 2>&1; then
    if [ "$FIX" = "1" ]; then
        npx -y "$MARKDOWNLINT_PKG" --fix "**/*.md" >/dev/null 2>&1 || true
    fi
    if md_out=$(npx -y "$MARKDOWNLINT_PKG" "**/*.md" 2>&1); then
        pass "markdownlint ($MARKDOWNLINT_PKG)"
    else
        echo "$md_out" | grep -v '^npm' | tail -30 >&2
        failed "markdownlint ($MARKDOWNLINT_PKG)"
    fi
else
    skip "markdownlint (npx not installed — CI still enforces)"
fi

# --- 17. actionlint (best-effort locally; CI runs its own dockerized step) ---
if [ "${CI:-}" = "true" ]; then
    skip "actionlint (separate CI step)"
elif command -v actionlint >/dev/null 2>&1; then
    if actionlint -color; then pass "actionlint"; else failed "actionlint"; fi
elif docker info >/dev/null 2>&1; then
    if docker run --rm -v "$PWD:/repo" --workdir /repo "$ACTIONLINT_IMAGE" -color; then
        pass "actionlint (docker)"
    else
        failed "actionlint (docker)"
    fi
else
    skip "actionlint (no binary or docker — CI still enforces)"
fi

# --- 18. config-injection blocks must announce CONFIG_SOURCE ------------------
# Two vacuous-green guards, because this gate's whole output is an absence and
# both ways of covering nothing look identical to a pass: the pathspec matching
# no tracked files (a directory rename), and no file carrying an injection block
# at all (the block reworded out from under the regex).
CONFIG_SOURCE_PATHSPEC=('skills/*/SKILL.md' 'skills/setup-config/references/config-contract.md')
CONFIG_INJECT_RE='^!`.*\.claude/sassy-dog/'
config_source_files=$(git ls-files "${CONFIG_SOURCE_PATHSPEC[@]}")
if [ -z "$config_source_files" ]; then
    failed "config-source guard — pathspec '${CONFIG_SOURCE_PATHSPEC[*]}' matched no tracked files (renamed or moved? the guard would silently cover nothing)"
else
    config_inject_files=$(echo "$config_source_files" | xargs grep -l "$CONFIG_INJECT_RE" 2>/dev/null)
    if [ -z "$config_inject_files" ]; then
        failed "config-source guard — no tracked file carries a .claude/sassy-dog injection block (reworded? the guard would silently cover nothing)"
    else
        # Line-scoped: the §1 reconciliation prose also mentions CONFIG_SOURCE,
        # so only the injection LINE itself is evidence that it still announces.
        config_source_bad=$(echo "$config_inject_files" | xargs grep -n "$CONFIG_INJECT_RE" | grep -v 'CONFIG_SOURCE')
        if [ -n "$config_source_bad" ]; then
            echo "$config_source_bad" >&2
            failed "config-source guard — the injection blocks above do not echo CONFIG_SOURCE, so a consumer cannot tell whose config it was handed (see setup-config/references/config-contract.md)"
        else
            pass "config-source guard ($(echo "$config_inject_files" | wc -l | tr -d ' ') injection blocks)"
        fi
    fi
fi

# --- 23. artifact-guard tests -------------------------------------------------
if bash scripts/test-artifact-guard.sh; then
    pass "artifact-guard tests (scripts/test-artifact-guard.sh)"
else
    failed "artifact-guard tests (scripts/test-artifact-guard.sh)"
fi

# --- 24. doc-reconciliation tests --------------------------------------------
# Gates the instruction, not staleness — see the header note. The sub-agent
# briefs are the half that gets missed. Three tracked files; no gh, no network.
if bash scripts/test-doc-reconciliation.sh; then
    pass "doc-reconciliation tests (scripts/test-doc-reconciliation.sh)"
else
    failed "doc-reconciliation tests (scripts/test-doc-reconciliation.sh)"
fi

# --- 25. poll-queue-eject tests ----------------------------------------------
# The verdict under test is terminal and loud, and its JSON twin is silent — a
# false `ejected` on a merged PR sends a human to eject recovery and a
# coordinator down the recovery branch with no warning at all. Section 1 also
# carries the "no per-PR counter" decision: the run must reach the global
# ceiling rather than resolve early. Mock gh: no repo, no network.
if bash scripts/test-poll-queue-eject.sh; then
    pass "poll-queue-eject tests (scripts/test-poll-queue-eject.sh)"
else
    failed "poll-queue-eject tests (scripts/test-poll-queue-eject.sh)"
fi

# --- 26. template-actionlint tests -------------------------------------------
# Same CI split as gate 17, for a mechanical reason: ci.yml puts the pinned
# actionlint on $GITHUB_PATH, which reaches only the steps AFTER the install —
# and this script runs before it. So CI owns this gate as its own step; here it
# is the local half. The script itself hard-FAILS rather than skips when
# CI=true and actionlint is missing, so the CI step cannot quietly no-op.
if [ "${CI:-}" = "true" ]; then
    skip "template-actionlint (separate CI step)"
elif bash scripts/test-template-actionlint.sh; then
    pass "template-actionlint tests (scripts/test-template-actionlint.sh)"
else
    failed "template-actionlint tests (scripts/test-template-actionlint.sh)"
fi

# --- 27. review-orchestrator allowlist tests ---------------------------------
# The defect this catches is invisible to the author who ships it: `react-typescript-engineer`
# and `iac-cloud-architect` exist as USER-LEVEL agents on a typical developer's
# machine, so an orchestrator dispatch (or a `review_surfaces:` example) naming
# one passes every other gate, works when its author tests it, and fails only in
# a consumer repo. A file-listing comparison against agents/, in the shape of
# gate 8's no-third-copy guard. No gh, no network.
if bash scripts/test-review-orchestrator-allowlist.sh; then
    pass "review-orchestrator allowlist tests (scripts/test-review-orchestrator-allowlist.sh)"
else
    failed "review-orchestrator allowlist tests (scripts/test-review-orchestrator-allowlist.sh)"
fi

# --- 28. gotcha-claims tests --------------------------------------------------
# The verifier's whole contract is "unknown is held": a claim citing #N reaches
# an issue body only when its asserted state was confirmed. So the fixture that
# matters is the stale one, and the failure mode that matters is degrading to a
# skip when gh is missing. Mock gh, symlink-sandboxed PATH: no repo, no network.
if bash scripts/test-gotcha-claims.sh; then
    pass "gotcha-claims tests (scripts/test-gotcha-claims.sh)"
else
    failed "gotcha-claims tests (scripts/test-gotcha-claims.sh)"
fi

# --- 29. review-gate decision tests -------------------------------------------
# The prose decisions from #237, #248, #273 and #280 that each read as drift:
# the gate is unconditional (and the SKIPPED line survives the default),
# `review_agent` is deliberately not presence-is-the-toggle, the opt-out is
# `skip` and not `none`, `review_site` is configured rather than derived, a
# Blocking finding blocks the merge with exactly one redispatch, a review report
# is RETURNED as the agent's final text — with a lost one held as its own
# outcome rather than merged past or folded into the SKIPPED line — and the
# reviewer -> orchestrator hop is bound the same way, with the fan-out brief
# carrying a slot to pass the contract down. Must-not-exist checks run
# flattened — this repo hard-wraps. This banner deliberately carries NO counts:
# it is out of reach of both windows the count re-derivation checks, so a count
# here is one
# nothing holds. The counts live in the gate list above, where the gate
# re-derives them.
if bash scripts/test-review-gate-decisions.sh; then
    pass "review-gate decision tests (scripts/test-review-gate-decisions.sh)"
else
    failed "review-gate decision tests (scripts/test-review-gate-decisions.sh)"
fi

# --- 30. pipefail-grep guard --------------------------------------------------
# Source-level, and the one gate whose subject is the OTHER gates: a `| grep -q`
# under pipefail reports a match as a miss once the writer outruns the pipe
# buffer, which is how PR #252's mutation proofs came back `undetected`. The
# printf/echo allowlist is the settled rule (#256) and the guard's header
# carries both its rationale and its known limitation — read that before
# widening or narrowing it. Tracked fixtures, no gh, no network.
if bash scripts/test-pipefail-grep.sh; then
    pass "pipefail-grep guard (scripts/test-pipefail-grep.sh)"
else
    failed "pipefail-grep guard (scripts/test-pipefail-grep.sh)"
fi

# --- 31. claim-lifecycle tests -----------------------------------------------
# The failure it guards is a write on somebody else's issue, so the gate
# measures writes: a mock gh records every mutating call and each case is judged
# on whether a --remove-assignee appeared. Its two negatives are the fixes #281
# rejected — a symmetric `release`, and aligning dispatch-ready's §3/§4 — and
# both read as tidying, which is why they are asserted rather than described.
# Mock gh only: no repo, no network.
if bash scripts/test-claim-lifecycle.sh; then
    pass "claim-lifecycle tests (scripts/test-claim-lifecycle.sh)"
else
    failed "claim-lifecycle tests (scripts/test-claim-lifecycle.sh)"
fi

# --- 32. drain terminal-state tests -------------------------------------------
# Source-level: §7 IS the instruction the loop follows, so there is nothing to
# run. It pins the state neither terminal state covered (#282), the §2
# enumeration the held set depends on — on BOTH the board and boardless paths,
# and without which the tick sees no PR at all and announces a false DRAIN
# COMPLETE — the one-set invariant tying COMPLETE's veto to that same set, the
# discriminator and its held-by-default last row, the non-empty held set that
# stops STALLED being satisfied vacuously, and the four things the fix must NOT
# have moved: both carve-outs, COMPLETE and its veto, the two-tick confirmation,
# and the single stop path. Bound in three layers — canon, inventory,
# consumption — each added after a review defeated the one before it. Two
# tracked files, no gh, no network.
if bash scripts/test-drain-terminal-states.sh; then
    pass "drain terminal-state tests (scripts/test-drain-terminal-states.sh)"
else
    failed "drain terminal-state tests (scripts/test-drain-terminal-states.sh)"
fi

# --- 33. audit lost-reviewer tests --------------------------------------------
# Source-level: the two assess-it documents ARE the instruction an audit run
# follows, so there is nothing to execute. It pins the per-domain outcome ledger
# (#284), the rule that a domain which did not return is never scored clean, the
# ledger's POSITION before the approval prompt — the harm lands at the preview,
# not at the report — and the half that stops the fix overshooting: a dark
# domain is surfaced, never a veto on filing. Bound like gate 32 in three layers
# (canon, inventory, consumption) over both files whole, with the fences
# included because Phase 4's ```text fence is the coverage block the run prints.
# No prose veto, deliberately; the only must-not-exist checks are the #283
# residue note's own literals. `agents/pr-review-orchestrator.md` is read for
# one fact only — gate 29 owns that file, and that double-pin is deliberate,
# "the sibling survives untouched" being an acceptance item of #284 itself.
# It pins the PREVIEW half only: the coverage record does not yet reach the
# filed Epic, which is issue #294 and is stated rather than claimed. Three
# tracked files, no gh, no network.
if bash scripts/test-audit-lost-reviewer.sh; then
    pass "audit lost-reviewer tests (scripts/test-audit-lost-reviewer.sh)"
else
    failed "audit lost-reviewer tests (scripts/test-audit-lost-reviewer.sh)"
fi

# ------------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
    echo "preflight: all gates green" >&2
    exit 0
else
    echo "preflight: FAILURES above" >&2
    exit 1
fi
