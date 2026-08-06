# Migrate mode

Converts a repo from the superseded generated-skills architecture to config.

**Before:** `.claude/skills/{plate-it,fill-it,take-it,drain-it,send-it,clean-it}/SKILL.md` — each a
full rendered skill body carrying that repo's facts inline.

**After:** `.claude/sassy-dog/{plate-it,groom-it,take-it,drain-it,send-it,clean-it}.md` — config
only, read by the generic plugin skills.

## The ordering rule

```text
1. Extract    from the generated SKILL.md
2. Re-verify  every fact against live state
3. Write      .claude/sassy-dog/*.md + .claude/settings.json
4. Preview    config + the exact deletion list
5. Delete     the old directories, on approval only
```

**The generated skill is the SOURCE, not merely the thing being replaced.** It holds the only copy
of the repo's Sentry projects, board IDs, scan paths, and project-specific prose. Deleting before
writing destroys the input and leaves nothing to recover from short of git history.

This was verified live: in an un-migrated repo the generic `plate-it` finds no config and routes
the user back to the project skill, because that is still where the real configuration lives. Delete
it early and both paths degrade at once.

## Step 1 — extract

Per generated `SKILL.md`, pull two things.

**Facts**, from the rendered prose. The old templates interpolated these inline, so they appear as
concrete values rather than placeholders:

| Config key | Where it was rendered |
| --- | --- |
| `scan_paths`, `exclude_pathspecs` | plate-it §C `SCAN_PATHS=` / `EXCLUDE_PATHSPECS=` |
| `ci_workflow` | plate-it §C `WORKFLOW=` |
| `sentry.org`, `sentry.projects` | plate-it §A Sentry line |
| `testflight.bundle_id` | plate-it §A TestFlight line |
| `mobile.release_workflow`, `mobile.path_prefix` | plate-it §C mobile release lag |
| `posthog` | presence of the plate-it PostHog paragraph |
| `secret_bootstrap` | plate-it §1 bootstrap command |
| `write_policy` | plate-it — a §6 write gate means `gated`, else `read-only` |
| `board.*` | any board GraphQL ID block (project, status field, option ids) |
| `priority_labels` | plate-it §4 Backlog scoring line |
| `preflight_commands` | send-it pre-flight block |
| `pr_template_path`, `pr_template_sections` | send-it PR-body section |
| `coauthor` | send-it commit trailer |
| `migrations.*`, `codegen.*` | send-it freshness gates |
| `review_agent` | send-it review-orchestrator block |
| `stack_summary` | take-it sub-agent prompt, first line |
| `max_in_flight` | drain-it capacity line |
| `gotcha_summary` | fill-it §3 "Record repo gotchas" |
| `dep_version_globs`, `noise_allowlist`, `never_discard` | clean-it project-facts table |
| `claim_label` | clean-it claim-label row, or take-it's claim step |

**Prose**, from the fences. Copy the content *between* the markers verbatim — never the marker
comments, and never a fence whose body is only an instructional HTML comment (those are empty
placeholders, not content):

| Fence slot | Config section | Destination file |
| --- | --- | --- |
| `extra-surfaces` | `## extra-surfaces` | `plate-it.md` |
| `scoring-overrides` | `## scoring-overrides` | `plate-it.md` |
| `extra-rubric` | `## extra-rubric` | `groom-it.md` |
| `subagent-rules` | `## subagent-rules` | `take-it.md` |
| `extra-sequencing` | `## extra-sequencing` | `drain-it.md` |
| `extra-gates` | `## extra-gates` | `send-it.md` |
| `extra-cleanup` | `## extra-cleanup` | `clean-it.md` |
| `extra-guardrails` | `## extra-guardrails` | whichever file it came from |

All eight slots must round-trip. Earlier docs listed only six — `extra-rubric` and
`extra-sequencing` were omitted while the templates emitted them, so a migration written from that
list would silently drop two repos' worth of prose.

## Step 2 — re-verify, because extracted facts are stale by default

**A rendered fact was true when it was rendered. Nothing has re-checked it since.**

Migrating this plugin's own repo surfaced two wrong facts in its own generated skills: they asserted
`delete_branch_on_merge: false` and "there is no merge queue", while the repo had since enabled
both. The derivable one self-corrected the moment it stopped being configured. `merge_queue` did
not, and only a rejected `gh pr merge --delete-branch` exposed it.

Re-verify at minimum:

```bash
# Derived facts — these never enter config at all
gh repo view --json nameWithOwner,defaultBranchRef,deleteBranchOnMerge

# merge_queue has no `gh repo view` equivalent
gh api graphql -f query='{repository(owner:"OWNER",name:"NAME"){mergeQueue(branch:"BRANCH"){id}}}' \
  --jq '.data.repository.mergeQueue != null'

# Workflows named in ci_workflow / mobile.release_workflow still exist
gh workflow list --json name,path
```

Board option IDs, Sentry project slugs, and label names are equally capable of drifting. Anything
you cannot verify, surface to the user rather than carrying it forward silently.

## Step 3 — `fill-it` → `groom-it`

The skill was renamed. Source `.claude/skills/fill-it/` maps to `.claude/sassy-dog/groom-it.md`,
carrying its `extra-rubric` prose and `gotcha_summary`.

Five repos have a `fill-it`; the rest never adopted it. A repo with no `fill-it` gets no
`groom-it.md`, which is correct — the generic `groom-it` runs fine on `NO_CONFIG`.

Mention the rename in the preview. `/fill-it` will stop appearing, and that surprises people.

## Step 4 — `.claude/settings.json`

Merge, never overwrite. `refresh-hooks` may already own a hooks entry in the same file.

```json
{
  "enabledPlugins": {
    "ai-agent-skills@sassy-dog-skills": true
  }
}
```

Preserve every existing key; add only the `enabledPlugins` entry. If the file already declares the
plugin, leave it alone.

**Why this matters more than it looks:** `enabledPlugins` honors project settings, and plugin skills
enabled only in *user* settings do not transfer to cloud sessions or scheduled routines. Omit this
and a scheduled `drain-it` silently finds no skill while every local session works — a failure mode
local testing cannot reproduce.

## Step 5 — preview

Show, before any write or delete:

1. Each `.claude/sassy-dog/*.md` in full
2. Every fact that **changed** during re-verification, old → new, with how it was checked
3. Every fact that could **not** be verified
4. The exact list of directories to be deleted, each with its `generated-by:` marker quoted
5. Any `.claude/skills/` directory being **kept** because it has no marker

Then write config, verify it, and delete only on explicit approval.

## Step 6 — what must not be touched

Skills without a `generated-by:` marker are hand-written and not yours. Known cases:

- `qr-ninja/.claude/skills/qr-ninja-design/`
- `what2wear/.claude/skills/what2wear-clean-it/` (legacy prefixed, adopt-mode candidate)
- `velovate/velovate-app/.claude/skills/terraform-apply/`

Check for a marker per directory. Never infer from the name.

## Consumer repos

Ten, and a one-level `*/` glob under the portfolio root **misses two** — velovate and devcanopy
nest their app one directory deeper. Scan at depth 4:

```bash
find ~/Repos/sassy-dog -maxdepth 4 -type d -path '*/.claude/skills'
```

francisco, mission-control, platform, qr-ninja, quickshot, sassydog-web, tailoredtip, what2wear,
`velovate/velovate-app`, `devcanopy/devcanopy`. `lupita/lupita` is excluded — legacy prefixed
skills, no markers, and the product is being sunset.
