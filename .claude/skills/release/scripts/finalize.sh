#!/bin/bash
# finalize.sh - Verify every release surface, then commit, tag and push.
#
# Usage:
#   .claude/skills/release/scripts/finalize.sh <version> \
#       --message-file <path> --tag-message-file <path> [--no-push] [--dry-run]
#
# Runs after scripts/release.sh has bumped the version surfaces and the
# changelogs / release note have been written. It re-checks that every surface
# actually landed (this is the step that catches a forgotten CHANGELOG entry or
# an unsynced site), re-runs the gate, then commits, creates an annotated tag,
# and pushes both. Pushing the tag is what triggers .github/workflows/publish.yml.
#
# Messages are passed as FILES, never as arguments — release prose contains
# quotes, backticks and newlines that do not survive a command line intact.
#
# Env overrides:
#   ROOT        - ai-consultants repo root (default: derived from this script)
#   SKIP_GATE=1 - skip npm test / npm run lint (use only when just re-run green)
#
# NOTE: like preflight.sh, this deliberately does not source lib/common.sh —
# doing so exports the maintainer's user config into `npm test` (the bug that
# kept the release gate red between v2.22.0 and v2.23.0).

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$1" "$NC" >&2; exit 1; }
step() { printf '\n%s==>%s %s\n' "$BLUE" "$NC" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"

VERSION=""
MESSAGE_FILE=""
TAG_MESSAGE_FILE=""
PUSH=true
DRY_RUN=false
FAILURES=0

need_value() { [[ $# -ge 2 ]] || die "$1 requires a value"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message-file)     need_value "$@"; MESSAGE_FILE="$2"; shift 2 ;;
        --tag-message-file) need_value "$@"; TAG_MESSAGE_FILE="$2"; shift 2 ;;
        --no-push)          PUSH=false; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -h|--help)
            sed -n '2,25p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *)
            if [[ -z "$VERSION" ]]; then VERSION="$1"; shift
            else printf '%sUnexpected argument: %s%s\n' "$RED" "$1" "$NC" >&2; exit 1; fi ;;
    esac
done

if [[ -z "$VERSION" || -z "$MESSAGE_FILE" || -z "$TAG_MESSAGE_FILE" ]]; then
    printf '%sUsage: %s <version> --message-file <path> --tag-message-file <path> [--no-push] [--dry-run]%s\n' \
        "$RED" "$0" "$NC" >&2
    exit 1
fi

for f in "$MESSAGE_FILE" "$TAG_MESSAGE_FILE"; do
    [[ -s "$f" ]] || { printf '%sMessage file missing or empty: %s%s\n' "$RED" "$f" "$NC" >&2; exit 1; }
done

TAG="v${VERSION}"
cd "$ROOT"

# -----------------------------------------------------------------------------
# 1. Surface verification
# -----------------------------------------------------------------------------
step "Verifying release surfaces for $VERSION"

PKG_VERSION="$(jq -r '.version' package.json)"
if [[ "$PKG_VERSION" == "$VERSION" ]]; then
    pass "package.json is at $VERSION"
else
    fail "package.json is at $PKG_VERSION, expected $VERSION — run scripts/release.sh $VERSION first"
fi

# Version-bearing surfaces, mirroring scripts/release.sh's SURFACES list.
check_contains() {
    local file="$1" needle="$2" label="$3"
    if [[ ! -f "$file" ]]; then
        fail "$label — $file not found"
    elif grep -qF -- "$needle" "$file"; then
        pass "$label"
    else
        fail "$label — '$needle' not found in $file"
    fi
}

check_contains "scripts/config.sh"    "AI_CONSULTANTS_VERSION=\"${VERSION}\""      "config.sh: AI_CONSULTANTS_VERSION"
check_contains "SKILL.md"             "  version: ${VERSION}"                      "SKILL.md: frontmatter"
check_contains "SKILL.md"             "# AI Consultants v${VERSION} - AI Expert Panel" "SKILL.md: title"
check_contains "README.md"            "# AI Consultants v${VERSION}"               "README.md: title"
check_contains "README.md"            "version-${VERSION}-blue"                    "README.md: badge"
check_contains "CLAUDE.md"            "**Version**: ${VERSION}"                    "CLAUDE.md: **Version**"
check_contains "docs/cost_rates.json" "\"version\": \"${VERSION}\""                "cost_rates.json: version"
check_contains "docs/COST_RATES.md"   "# Cost Rates - AI Consultants v${VERSION}"  "COST_RATES.md: title"

# Documentation surfaces — the ones scripts/release.sh cannot write, and the
# ones that actually drift (v2.22.0 shipped without a GitHub release).
TODAY="$(date +%Y-%m-%d)"
if grep -qE "^## \[${VERSION//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
    if [[ "$(grep -m1 -E '^## \[' CHANGELOG.md)" == "## [${VERSION}]"* ]]; then
        pass "CHANGELOG.md: [$VERSION] entry is at the top"
    else
        fail "CHANGELOG.md: [$VERSION] exists but is not the newest entry"
    fi
    grep -qF "## [${VERSION}] - ${TODAY}" CHANGELOG.md || warn "CHANGELOG.md: [$VERSION] is not dated today ($TODAY)"
else
    fail "CHANGELOG.md: no '## [${VERSION}] - YYYY-MM-DD' entry"
fi

NOTE="docs/releases/${TAG}.md"
if [[ -f "$NOTE" ]] && [[ "$(wc -l < "$NOTE")" -ge 20 ]]; then
    pass "release note $NOTE ($(wc -l < "$NOTE" | tr -d ' ') lines)"
    grep -q "Upgrade Guide" "$NOTE" || warn "$NOTE has no '## Upgrade Guide' section"
    grep -q "Breaking Changes" "$NOTE" || warn "$NOTE has no '## Breaking Changes' section"
elif [[ -f "$NOTE" ]]; then
    fail "release note $NOTE is only $(wc -l < "$NOTE" | tr -d ' ') lines — looks like a stub"
else
    fail "release note $NOTE is missing"
fi

if grep -qF "### v${VERSION}" CLAUDE.md; then
    pass "CLAUDE.md: '### v${VERSION}' changelog entry"
else
    fail "CLAUDE.md: no '### v${VERSION}' entry under '## Changelog'"
fi

# The workspace guide lives outside this repo and is not version-controlled
# here, so a miss is a warning, not a blocker.
WORKSPACE_GUIDE="$(cd "$ROOT/.." && pwd)/CLAUDE.md"
if [[ -f "$WORKSPACE_GUIDE" ]]; then
    if grep -qF "$VERSION" "$WORKSPACE_GUIDE"; then
        pass "workspace CLAUDE.md mentions $VERSION"
    else
        warn "workspace CLAUDE.md ($WORKSPACE_GUIDE) has no mention of $VERSION"
    fi
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '\n%sSURFACE CHECK FAILED%s — %d issue(s). Nothing was committed.\n' "$RED" "$NC" "$FAILURES"
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Repository safety
#
# preflight.sh made these same checks, but that was before step 4 of the release
# (hand-writing three changelogs, often with a `git checkout <old-tag>` to diff
# against). Re-check here, because THIS is the script that publishes: `git push
# origin main` pushes the local `main` REF, not HEAD, so from a side branch it
# prints "Everything up-to-date" and exits 0 — and the next line would push a tag
# pointing at a commit that is not reachable from main. publish.yml would then
# npm-publish it, and an npm publish cannot be taken back.
# -----------------------------------------------------------------------------
step "Repository safety"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "main" ]]; then
    pass "on main"
else
    die "on '$BRANCH', expected main — a tag pushed from here would publish a commit that is not on main"
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
    die "tag $TAG already exists locally — releases never reuse a version"
fi
pass "no local tag $TAG"

if git fetch --quiet --tags origin 2>/dev/null; then
    if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
        die "tag $TAG already exists on origin"
    fi
    pass "no remote tag $TAG"

    REMOTE_HEAD="$(git rev-parse --verify -q origin/main || true)"
    if [[ -z "$REMOTE_HEAD" ]]; then
        warn "no origin/main to compare against"
    elif git merge-base --is-ancestor "$REMOTE_HEAD" HEAD; then
        pass "HEAD descends from origin/main"
    else
        die "HEAD does not descend from origin/main — pull/rebase before releasing"
    fi
else
    warn "could not fetch from origin (offline?) — remote tag and ancestry unverified"
fi

if [[ -z "$(git status --porcelain)" ]]; then
    die "nothing to commit — the working tree is clean"
fi
pass "working tree has the release changes"

# -----------------------------------------------------------------------------
# 3. Dry run
#
# Deliberately ahead of the gate: --dry-run is documented as a preview, and a
# preview that spends a full `npm test` is not one.
# -----------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
    step "DRY RUN — would run"
    printf '  git add -A\n'
    printf '  git commit -F %s\n' "$MESSAGE_FILE"
    printf '  git tag -a %s -F %s\n' "$TAG" "$TAG_MESSAGE_FILE"
    if [[ "$PUSH" == "true" ]]; then
        printf '  git push origin main && git push origin %s\n' "$TAG"
    fi
    printf '\nThe gate (npm test + npm run lint) is skipped in a dry run.\n'
    printf '\nStaged-file preview:\n'
    git status --short | sed 's/^/  /'
    exit 0
fi

# -----------------------------------------------------------------------------
# 4. Gate
# -----------------------------------------------------------------------------
if [[ "${SKIP_GATE:-}" == "1" ]]; then
    step "Gate skipped (SKIP_GATE=1)"
    warn "publish.yml re-runs the gate on the tag — a red suite fails the publish, not the tag push"
else
    step "Running the gate (npm test + npm run lint)"
    npm test
    npm run lint
    pass "gate green"
fi

# -----------------------------------------------------------------------------
# 5. Commit, tag, push
# -----------------------------------------------------------------------------
step "Commit, tag, push"

git add -A
git commit -F "$MESSAGE_FILE"
pass "committed $(git rev-parse --short HEAD)"

git tag -a "$TAG" -F "$TAG_MESSAGE_FILE"
pass "tagged $TAG"

if [[ "$PUSH" == "false" ]]; then
    printf '\n%s--no-push set.%s Push manually to trigger the publish:\n' "$YELLOW" "$NC"
    printf '  git push origin main && git push origin %s\n' "$TAG"
    exit 0
fi

git push origin main
pass "pushed main"

git push origin "$TAG"
pass "pushed $TAG — publish.yml is now running"

printf '\n%s\n' "----------------------------------------------------------------------"
printf 'Watch it:   gh run watch --exit-status\n'
printf 'Then sync:  .claude/skills/release/scripts/sync_site.sh %s --message-file <path>\n' "$VERSION"
