---
name: release
description: Ship an ai-consultants release end to end — version bump, all three changelog surfaces, release note, commit, annotated tag, push (which publishes to npm via GitHub Actions), then sync the showcase site once npm serves it.
disable-model-invocation: true
---

# Release

Ships a full ai-consultants release. The user gives the new version in `$ARGUMENTS`
(e.g. `/release 2.24.0`). If they didn't, derive it from the change set and confirm
before starting.

**What is automated where.** The mechanical parts are scripts — do not hand-edit
what they own. The prose is yours.

| Step | Owner |
|---|---|
| Preflight (repo state, version, tags) | `.claude/skills/release/scripts/preflight.sh` |
| Version bump across 9 surfaces | `scripts/release.sh` |
| CHANGELOG.md / CLAUDE.md / release note / site copy | **you** |
| Surface verification, gate, commit, tag, push | `.claude/skills/release/scripts/finalize.sh` |
| npm publish + GitHub release | `.github/workflows/publish.yml` (on tag push) |
| Site version bump, commit, push | `.claude/skills/release/scripts/sync_site.sh` |

All paths below are relative to the `ai-consultants/` repo root. `cd` there first.

---

## 1. Preflight

```bash
.claude/skills/release/scripts/preflight.sh <VERSION>
```

Read-only. It fails the release before anything is touched if: a repo is dirty,
off `main`, or diverged from origin; the version isn't a forward semver step; the
tag or release note already exists; or a required tool is missing. **Stop and
report if it fails** — do not work around it.

Note its warnings too. "npm is at X but the tree is at Y" means a previous
release never published; say so before adding another version on top.

## 2. Gather the material

Read the actual change set — never write release prose from memory:

```bash
git log --oneline "v$(git describe --tags --abbrev=0 | sed 's/^v//')"..HEAD
git diff --stat "$(git describe --tags --abbrev=0)"..HEAD
```

Read the full diff for anything you'll describe. If the range is large, delegate
the summarisation (`sonnet-clerk`) but read the diffs for anything you assert as
a fix. Ask the user for the framing — what they consider the headline — rather
than inferring it from commit subjects alone.

## 3. Bump the version

```bash
scripts/release.sh <VERSION> --dry-run   # preview
scripts/release.sh <VERSION>             # apply
```

It rewrites 9 anchored surfaces across 7 files, validates that no stray old
version survives on those lines, and runs `npm test` + `npm run lint`. It never
commits, tags, or publishes. If a surface doesn't match, it refuses — fix the
anchor rather than editing the file by hand, or the same release will break next
time.

## 4. Write the three changelogs

Three surfaces, three audiences, and drift between them is this project's most
common release bug. See `references/surfaces.md` for the exact format,
placement, and templates of each.

1. **`CHANGELOG.md`** — new `## [VERSION] - YYYY-MM-DD` at the top, Keep a
   Changelog subsections. User-facing, one line per bullet.
2. **`CLAUDE.md`**, under `## Changelog` — new `### vVERSION` as the first entry.
   Developer-facing, long-form: rationale, file:line references, latent bugs
   uncovered, what was deliberately *not* done.
3. **`docs/releases/vVERSION.md`** — the upgrade-decision document. Highlights,
   what's new, breaking changes, upgrade guide. `publish.yml` uses this file
   verbatim as the GitHub release body, so it must stand alone.

Then update the workspace guide at `../CLAUDE.md`: bump "Latest at time of last
sync" and add a bullet to the "Recent release line".

## 5. Finalize

Show the user `git status --short` and a diff of the changelogs, and get an
explicit go-ahead — the next command pushes a tag, and a pushed tag publishes to
npm, which cannot be undone (npm unpublish is restricted to the first 72 hours,
and republishing the same version is never allowed).

Write both messages to files — release prose has quotes, backticks and newlines
that do not survive a command line:

```bash
tmp=$(mktemp -d)
cat > "$tmp/commit.txt" <<'EOF'
release: <VERSION> — <one-line summary>

<Body: what changed and why. Match the house style — recent commits carry the
reasoning, not just the file list. Verified claims only.>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF

cat > "$tmp/tag.txt" <<'EOF'
v<VERSION> — <one-line summary, becomes the GitHub release title>

- <3-5 highlight bullets, mirroring the release note>
EOF

.claude/skills/release/scripts/finalize.sh <VERSION> \
    --message-file "$tmp/commit.txt" \
    --tag-message-file "$tmp/tag.txt"
```

`finalize.sh` re-verifies all 9 version surfaces *and* the three doc surfaces,
re-runs the gate, then commits, tags, and pushes. Add `--dry-run` to preview or
`--no-push` to stop at the local tag.

**The tag's subject line becomes the GitHub release title** — write it as a
title, not as a commit subject.

## 6. Watch the publish

Pushing the tag triggers `publish.yml`: it re-runs the gate, checks the tag
matches `package.json`, publishes to npm with OIDC provenance, and creates the
GitHub release from `docs/releases/vVERSION.md`.

```bash
gh run watch --exit-status
```

If it fails, fix forward and re-run the workflow — **never move or delete the
tag**. The publish step is idempotent (it skips a version already on npm), so a
re-run after a fix is safe.

## 7. Sync the showcase site

Only after npm actually serves the version:

```bash
cat > "$tmp/site.txt" <<'EOF'
sync: v<VERSION> — <what changed on the site>
EOF

.claude/skills/release/scripts/sync_site.sh <VERSION> --message-file "$tmp/site.txt"
```

The script waits for npm, bumps `softwareVersion` and the badge, then commits and
pushes. **Editorial copy is yours** — edit `../aiconsultants.sh/index.html` before
running it and the same commit carries both. Check whether the release changed
anything the site asserts: the 11-consultant roster, the feature cards, the
presets table, the install commands, the model-tier names.

It refuses to run if the site repo has untracked files. That repo has no
`.gitignore` and GitHub Pages serves its root, so anything stray there would be
publicly fetchable at `https://aiconsultants.sh/<path>` on the next push. Remove
them, or pass `--allow-untracked` if they genuinely belong on the site.

The wait is not ceremony. The site advertises `npx ai-consultants <subcommand>`,
npx resolves against the *published* package, and this package's `bin` routes an
unknown argument straight to `consult_all.sh` — so a subcommand documented before
it ships doesn't error, it starts a real **billable** consultation with the
subcommand name as the question. Early costs users money; late costs nothing.

## 8. Report

Tell the user, with evidence rather than assertion:

- `npm view ai-consultants version` — the published version
- `gh release view v<VERSION> --json url -q .url` — the release URL
- the two commit SHAs (tool + site)
- anything skipped, degraded, or left for them to do

---

## Notes

- **Never** `npm publish` from your machine. The workflow holds the publishing
  identity; a local publish produces an unattested package and desyncs the tag.
- If `preflight.sh` reports npm behind the working tree, an earlier release was
  bumped and tagged but never published. Resolve that first — the fix is usually
  re-running `publish.yml` on the existing tag, not a new version.
- Hotfix on a released version: bump the patch and run the same flow. There is
  no path that rewrites a published version.
- The three-changelog split is deliberate (see `references/surfaces.md`). Do not
  collapse it, and do not paste the same text into all three.
