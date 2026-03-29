---
name: release
description: Automate a version bump across all files that track the version, create the release note, and prepare the commit.
disable-model-invocation: true
---

Automate the ai-consultants release process. The user provides the new version as `$ARGUMENTS` (e.g., `/release 2.11.0`).

## Steps

1. **Parse version**: Extract new version from `$ARGUMENTS`. Detect current version from `package.json`. Determine release type (major/minor/patch) by comparing.

2. **Update version in all files** (7 locations):
   - `package.json` — `"version"` field
   - `SKILL.md` — frontmatter `name` line version + title
   - `README.md` — title + badge
   - `CLAUDE.md` — `**Version**:` line
   - `docs/cost_rates.json` — version field if present
   - `docs/COST_RATES.md` — title
   - `bin/ai-consultants` — `VERSION=` variable

3. **Create release note** at `docs/releases/v<VERSION>.md` using the template from CLAUDE.md. Ask the user for highlight bullet points.

4. **Add changelog entry** in CLAUDE.md under `## Changelog`.

5. **Prepare commit** with message: `chore: release v<VERSION>`.

6. **Remind** the user to also update the showcase website (`aiconsultants.sh`) version if needed.
