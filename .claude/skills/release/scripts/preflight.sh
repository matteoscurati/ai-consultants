#!/bin/bash
# preflight.sh - Gate the state of both repos before an ai-consultants release.
#
# Usage:
#   .claude/skills/release/scripts/preflight.sh <new-version>
#
# Verifies that a release of <new-version> can start cleanly: tooling present,
# both repos on main / clean / in sync with origin, the version is a forward
# semver step, and neither the tag nor the release note already exists.
#
# Env overrides:
#   ROOT       - ai-consultants repo root (default: derived from this script)
#   SITE_REPO  - showcase site repo (default: <ROOT>/../aiconsultants.sh)
#
# Exit: 0 when every check passes, 1 otherwise.
#
# Does not touch the working tree, the index, or any branch. It does run
# `git fetch --tags` in both repos, which updates remote-tracking refs and
# materialises remote tags locally — the only thing it writes.
#
# NOTE: this script deliberately does NOT source lib/common.sh. That pulls in
# config.sh -> load_user_config, which exports the maintainer's whole user
# config into the environment — the bug that kept the release gate red between
# v2.22.0 and v2.23.0. Release tooling stays self-contained.

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; DIM=$'\033[2m'; NC=$'\033[0m'

FAILURES=0
WARNINGS=0

pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; WARNINGS=$((WARNINGS + 1)); }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$NC"; }
head2() { printf '\n%s\n' "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
SITE_REPO="${SITE_REPO:-$(cd "$ROOT/.." && pwd)/aiconsultants.sh}"

NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
    printf '%sUsage: %s <new-version>%s\n' "$RED" "$0" "$NC" >&2
    exit 1
fi

printf 'Release preflight for %s\n' "$NEW_VERSION"
note "tool: $ROOT"
note "site: $SITE_REPO"

# --- 1. Tooling ---------------------------------------------------------------
head2 "Tooling"
for tool in git jq npm gh shellcheck; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool present"
    elif [[ "$tool" == "shellcheck" ]]; then
        warn "shellcheck missing — 'npm run lint' will fail locally (CI still lints)"
    else
        fail "$tool not found on PATH"
    fi
done

if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        pass "gh authenticated"
    else
        warn "gh not authenticated — 'gh auth login' needed to inspect releases"
    fi
fi

# --- 2. Version ---------------------------------------------------------------
head2 "Version"
if [[ ! -f "$ROOT/package.json" ]]; then
    fail "package.json not found under $ROOT"
    exit 1
fi

PKG_NAME="$(jq -r '.name // ""' "$ROOT/package.json")"
if [[ "$PKG_NAME" == "ai-consultants" ]]; then
    pass "ROOT is the ai-consultants package"
else
    fail "ROOT does not look like ai-consultants (package name: '$PKG_NAME')"
fi

CURRENT_VERSION="$(jq -r '.version' "$ROOT/package.json")"
note "current: $CURRENT_VERSION"

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "'$NEW_VERSION' is not semver X.Y.Z"
elif [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    fail "$NEW_VERSION is already the current version"
elif [[ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$NEW_VERSION" | sort -V | tail -1)" != "$NEW_VERSION" ]]; then
    fail "$NEW_VERSION is not greater than the current $CURRENT_VERSION"
else
    pass "$CURRENT_VERSION -> $NEW_VERSION is a forward step"
fi

if [[ -f "$ROOT/docs/releases/v${NEW_VERSION}.md" ]]; then
    fail "docs/releases/v${NEW_VERSION}.md already exists"
else
    pass "release note slot is free"
fi

if grep -qF "## [${NEW_VERSION}]" "$ROOT/CHANGELOG.md" 2>/dev/null; then
    fail "CHANGELOG.md already has a [${NEW_VERSION}] entry"
else
    pass "CHANGELOG.md has no [${NEW_VERSION}] entry yet"
fi

# --- 3. Repo state ------------------------------------------------------------
check_repo_state() {
    local label="$1" dir="$2"

    head2 "$label ($dir)"

    # `.git` is a FILE, not a directory, in a linked worktree or a submodule.
    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        fail "$label is not a git checkout"
        return 0
    fi

    local branch
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
    if [[ "$branch" == "main" ]]; then
        pass "on main"
    else
        fail "on '$branch', expected main"
    fi

    if [[ -z "$(git -C "$dir" status --porcelain)" ]]; then
        pass "working tree clean"
    else
        fail "working tree dirty — commit or stash first"
        git -C "$dir" status --short | sed 's/^/      /'
    fi

    if ! git -C "$dir" fetch --quiet --tags origin 2>/dev/null; then
        warn "could not fetch from origin (offline?) — remote checks are stale"
        return 0
    fi

    local local_head remote_head
    local_head="$(git -C "$dir" rev-parse HEAD)"
    remote_head="$(git -C "$dir" rev-parse "origin/$branch" 2>/dev/null || echo "")"
    if [[ -z "$remote_head" ]]; then
        warn "no origin/$branch to compare against"
    elif [[ "$local_head" == "$remote_head" ]]; then
        pass "in sync with origin/$branch"
    elif git -C "$dir" merge-base --is-ancestor "$remote_head" "$local_head"; then
        warn "ahead of origin/$branch by $(git -C "$dir" rev-list --count "$remote_head..$local_head") commit(s) — they will be pushed with the release"
    else
        fail "diverged from origin/$branch — pull/rebase first"
    fi
}

check_repo_state "Tool repo" "$ROOT"
check_repo_state "Site repo" "$SITE_REPO"

# --- 4. Tag -------------------------------------------------------------------
head2 "Tag v$NEW_VERSION"
if git -C "$ROOT" rev-parse -q --verify "refs/tags/v${NEW_VERSION}" >/dev/null 2>&1; then
    fail "tag v${NEW_VERSION} already exists locally"
else
    pass "no local tag v${NEW_VERSION}"
fi

if git -C "$ROOT" ls-remote --exit-code --tags origin "refs/tags/v${NEW_VERSION}" >/dev/null 2>&1; then
    fail "tag v${NEW_VERSION} already exists on origin"
else
    pass "no remote tag v${NEW_VERSION}"
fi

# --- 5. Publish path ----------------------------------------------------------
head2 "Publish path"
if [[ -f "$ROOT/.github/workflows/publish.yml" ]]; then
    pass "publish workflow present"
else
    fail ".github/workflows/publish.yml missing — the tag would publish nothing"
fi

PUBLISHED="$(npm view ai-consultants version 2>/dev/null || echo "")"
if [[ -z "$PUBLISHED" ]]; then
    warn "could not read the published version from npm (offline?)"
elif [[ "$PUBLISHED" == "$CURRENT_VERSION" ]]; then
    pass "npm is at $PUBLISHED — level with the working tree"
else
    warn "npm is at $PUBLISHED but the tree is at $CURRENT_VERSION — a previous release never published"
fi

# --- Summary ------------------------------------------------------------------
printf '\n%s\n' "----------------------------------------------------------------------"
if [[ "$FAILURES" -gt 0 ]]; then
    printf '%sPREFLIGHT FAILED%s — %d blocking issue(s), %d warning(s).\n' "$RED" "$NC" "$FAILURES" "$WARNINGS"
    exit 1
fi
printf '%sPREFLIGHT PASSED%s — %d warning(s). Ready to release %s.\n' "$GREEN" "$NC" "$WARNINGS" "$NEW_VERSION"
