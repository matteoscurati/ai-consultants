# Release surfaces

Every place a release has to touch, who owns it, and what "correct" looks like.
Loaded on demand by the `release` skill — the skill body has the flow, this file
has the detail.

## Version surfaces (owned by `scripts/release.sh`)

Nine anchored edits across seven files. Never hand-edit these; if an anchor stops
matching, `release.sh` refuses and the fix belongs in its `SURFACES` array.

| File | Anchor |
|---|---|
| `package.json` | `"version": "X.Y.Z"` |
| `scripts/config.sh` | `AI_CONSULTANTS_VERSION="X.Y.Z"` |
| `SKILL.md` | frontmatter `  version: X.Y.Z` |
| `SKILL.md` | `# AI Consultants vX.Y.Z - AI Expert Panel` |
| `README.md` | `# AI Consultants vX.Y.Z` |
| `README.md` | `version-X.Y.Z-blue` (badge) |
| `CLAUDE.md` | `**Version**: X.Y.Z` |
| `docs/cost_rates.json` | `"version": "X.Y.Z"` |
| `docs/COST_RATES.md` | `# Cost Rates - AI Consultants vX.Y.Z` |

`bin/ai-consultants` is **not** on this list. It reads `AI_CONSULTANTS_VERSION`
out of `scripts/config.sh` at runtime (since v2.12.0) — a hardcoded `VERSION=`
there is exactly the bug that pinned the CLI at 2.10.0 for two releases.

`finalize.sh` re-checks all nine before it commits.

## Documentation surfaces (owned by you)

### 1. `CHANGELOG.md` — for users on a specific version

Newest first. Keep a Changelog format. Concise, categorized, scannable.

```markdown
## [2.24.0] - 2026-07-25

### Added
- One line per change, user-facing outcome first.

### Changed
### Fixed
### Removed
### Deprecated
### Security
```

Only include subsections that have content. Lead a bullet with what the user
observes, not the implementation: "Debate rounds no longer crash on Linux" beats
"Added `|| true` to `((count++))` in debate_round.sh".

### 2. `CLAUDE.md` → `## Changelog` → `### vX.Y.Z` — for the next maintainer

Insert as the first entry under `## Changelog`. This is the long-form one: bold
lead-in per item, then the reasoning. Include what the shorter surfaces can't
carry:

- `file:line` references for anything non-obvious
- why the fix is at this altitude and not another
- latent bugs the work uncovered, and whether they were pre-existing (say how you
  verified — "the same assertion fails at `2ac18d4`" beats "seems pre-existing")
- what was deliberately **not** done, and why
- corrections of earlier mis-diagnoses, on the record

### 3. `docs/releases/vX.Y.Z.md` — for someone deciding whether to upgrade

`publish.yml` passes this file to `gh release create --notes-file`, so it is the
GitHub release body verbatim. It must read standalone, with no repo context.

```markdown
# Release vX.Y.Z

**Date:** YYYY-MM-DD
**Type:** Major | Minor | Patch — one-line summary
**Previous:** vA.B.C

## Highlights

- 3-5 bullets, impact first

## What's New

### <Area>

<What changed and why. Tables for multi-item changes.>

## Breaking Changes

<List them, or "None — this release is backwards-compatible.">

## Upgrade Guide

```bash
# npx (no install)
npx ai-consultants "question"

# git clone install
cd ~/.claude/skills/ai-consultants && git pull

# curl | bash install
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

<Configuration changes required, or "No configuration changes required.">

## Commits

- `<hash>` <subject>
```

Breaking changes get their own section — never buried in a bullet list.
`finalize.sh` warns if the `## Breaking Changes` or `## Upgrade Guide` headings
are missing.

## Workspace surfaces (outside both repos)

`../CLAUDE.md` — the workspace guide covering both projects. Two spots:

- "Latest at time of last sync: **vX.Y.Z**" in the sync table
- a new bullet at the top of the "Recent release line" list

Not version-controlled from this repo, so `finalize.sh` only warns.

## Site surfaces (`../aiconsultants.sh/index.html`)

Mechanical, owned by `sync_site.sh`:

| Surface | Shape |
|---|---|
| JSON-LD schema | `"softwareVersion": "X.Y.Z",` |
| Hero badge | `<span class="badge">vX.Y.Z</span>` |

Editorial, owned by you — check each against the release:

- **Consultant roster** — currently 11; a roster change means updating the count,
  the cards, and any prose that names the retired/added models
- **Feature cards** — a headline feature usually earns one
- **Presets / strategies table** — it has claimed behaviour the code stopped
  enforcing before (the v2.16 planner made the fixed debate/peer-review depths
  obsolete, and the table said otherwise until v2.23.0)
- **Model-tier names** — a model catalog refresh changes these
- **Install commands** — including any `npx ai-consultants <subcommand>`

Prose that names an *older* version on purpose (e.g. "Version 2.21.1 retires
Kilo, Aider, Amp, and Ollama") is history and must survive the bump. That's why
`sync_site.sh` rewrites anchored surfaces only, never a blanket version replace.

### The npx timing rule

A new subcommand must not appear on the site as `npx ai-consultants <cmd>` until
that version is **published to npm** — not tagged, not released, published.
`npx` resolves against the published package, and `bin/ai-consultants` routes an
unknown argument to `consult_all.sh`, so an unpublished subcommand doesn't error:
it starts a real, billable consultation with the subcommand name as the question.

The risk is asymmetric — early bills users, late is merely conservative docs — so
flip late. `sync_site.sh` enforces this by polling `npm view` before it commits.

Nothing in either repo couples them structurally: they are separate repos, and
whoever publishes has no reason to open the HTML. The coupling is this document
and that poll.

## Publish surfaces (owned by `.github/workflows/publish.yml`)

Triggered by pushing a `v*` tag. In order: verify `package.json` holds a valid
semver that matches the tag and that the release note and CHANGELOG entry exist
→ verify the tagged commit is an ancestor of `origin/main` → gate (syntax,
shellcheck, `npm test`) → `npm publish` → `gh release create`.

The ancestry check is deliberate redundancy with `finalize.sh`'s branch guard.
`git push origin main` pushes the local `main` ref, not `HEAD`, so a tag created
off a side branch pushes cleanly and exits 0 — and npm publish is irreversible.
Two independent guards for the one action that cannot be undone.

Both terminal steps are idempotent: publish skips a version already on npm, and
the release step leaves an existing release alone. A failed run can be re-run
after a fix without moving the tag.

Auth is npm Trusted Publishing (OIDC) — no `NPM_TOKEN` anywhere. See the header
comment in `publish.yml` for the one-time npmjs.com configuration.
