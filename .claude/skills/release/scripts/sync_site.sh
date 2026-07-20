#!/bin/bash
# sync_site.sh - Bump the showcase site to a released version, then push it.
#
# Usage:
#   .claude/skills/release/scripts/sync_site.sh <version> --message-file <path> \
#       [--no-wait] [--no-push] [--dry-run] [--timeout <seconds>]
#
# Runs LAST in a release, after publish.yml has put the version on npm. It
# waits for the registry to actually serve <version>, bumps the two mechanical
# surfaces in index.html (the `softwareVersion` schema field and the version
# badge), then commits everything in the site repo — including any editorial
# copy already edited by hand — and pushes. GitHub Pages deploys from that push.
#
# Why it waits: the site advertises `npx ai-consultants <subcommand>`, and npx
# resolves against the PUBLISHED package. This package's bin routes an unknown
# argument straight to consult_all.sh, so a subcommand documented before it is
# published does not error — it starts a real, BILLABLE consultation with the
# subcommand name as the question. Publishing the site early bills users;
# publishing it late is merely conservative. So it waits.
#
# Env overrides:
#   ROOT       - ai-consultants repo root (default: derived from this script)
#   SITE_REPO  - showcase site repo (default: <ROOT>/../aiconsultants.sh)

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$1" "$NC" >&2; exit 1; }
step() { printf '\n%s==>%s %s\n' "$BLUE" "$NC" "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
SITE_REPO="${SITE_REPO:-$(cd "$ROOT/.." && pwd)/aiconsultants.sh}"

VERSION=""
MESSAGE_FILE=""
WAIT=true
PUSH=true
DRY_RUN=false
ALLOW_UNTRACKED=false
TIMEOUT=900

need_value() { [[ $# -ge 2 ]] || die "$1 requires a value"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message-file)    need_value "$@"; MESSAGE_FILE="$2"; shift 2 ;;
        --timeout)         need_value "$@"; TIMEOUT="$2"; shift 2 ;;
        --no-wait)         WAIT=false; shift ;;
        --no-push)         PUSH=false; shift ;;
        --dry-run)         DRY_RUN=true; shift ;;
        --allow-untracked) ALLOW_UNTRACKED=true; shift ;;
        -h|--help)         sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)
            if [[ -z "$VERSION" ]]; then VERSION="$1"; shift
            else die "Unexpected argument: $1"; fi ;;
    esac
done

[[ -n "$VERSION" ]] || die "Usage: $0 <version> --message-file <path> [--no-wait] [--no-push] [--dry-run]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "'$VERSION' is not semver X.Y.Z"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout must be a whole number of seconds (got '$TIMEOUT')"
if [[ "$DRY_RUN" == "false" ]]; then
    [[ -s "${MESSAGE_FILE:-}" ]] || die "--message-file is required and must be non-empty"
fi

INDEX="$SITE_REPO/index.html"
[[ -f "$INDEX" ]] || die "Site index not found: $INDEX"
# `.git` is a FILE, not a directory, in a linked worktree or a submodule.
git -C "$SITE_REPO" rev-parse --git-dir >/dev/null 2>&1 || die "Site repo is not a git checkout: $SITE_REPO"

# Checked before anything is rewritten: a wrong-branch run must not leave the
# site repo dirty.
SITE_BRANCH="$(git -C "$SITE_REPO" rev-parse --abbrev-ref HEAD)"
[[ "$SITE_BRANCH" == "main" ]] || die "Site repo is on '$SITE_BRANCH', expected main"

# -----------------------------------------------------------------------------
# 1. Wait for npm
# -----------------------------------------------------------------------------
if [[ "$WAIT" == "true" ]]; then
    step "Waiting for ai-consultants@$VERSION on npm (timeout ${TIMEOUT}s)"
    deadline=$((SECONDS + TIMEOUT))
    while true; do
        if npm view "ai-consultants@${VERSION}" version >/dev/null 2>&1; then
            pass "npm serves $VERSION"
            break
        fi
        if [[ "$SECONDS" -ge "$deadline" ]]; then
            printf '\n%sTimed out.%s npm still reports: %s\n' "$RED" "$NC" "$(npm view ai-consultants version 2>/dev/null || echo '?')" >&2
            printf 'Check the workflow: gh run list --workflow=publish.yml --limit 3\n' >&2
            printf 'Re-run this script once it goes green, or pass --no-wait to override.\n' >&2
            exit 1
        fi
        printf '  ... not yet (%ds elapsed)\n' "$SECONDS"
        sleep 15
    done
else
    warn "--no-wait: not checking whether npm serves $VERSION"
fi

# -----------------------------------------------------------------------------
# 2. Bump the mechanical surfaces
# -----------------------------------------------------------------------------
step "Bumping index.html"

CURRENT_SITE_VERSION="$(grep -m1 -oE '"softwareVersion": "[0-9]+\.[0-9]+\.[0-9]+"' "$INDEX" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
[[ -n "$CURRENT_SITE_VERSION" ]] || die "Could not read the current \"softwareVersion\" from $INDEX"
printf '  %s -> %s\n' "$CURRENT_SITE_VERSION" "$VERSION"

if [[ "$CURRENT_SITE_VERSION" == "$VERSION" ]]; then
    warn "site already at $VERSION — leaving the version surfaces alone"
else
    esc_current="${CURRENT_SITE_VERSION//./\\.}"

    # Anchored on the surrounding markup, never a blanket version replace: the
    # page legitimately names older versions in prose (e.g. "Version 2.21.1
    # retires Kilo, Aider, Amp, and Ollama"), and those must survive untouched.
    for probe in "\"softwareVersion\": \"${esc_current}\"" "<span class=\"badge\">v${esc_current}</span>"; do
        grep -qE -- "$probe" "$INDEX" || die "Surface not found in index.html: $probe"
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  DRY RUN — would rewrite both version surfaces.\n'
    else
        sed -i.bak \
            -e "s/\"softwareVersion\": \"${esc_current}\"/\"softwareVersion\": \"${VERSION}\"/" \
            -e "s|<span class=\"badge\">v${esc_current}</span>|<span class=\"badge\">v${VERSION}</span>|" \
            "$INDEX"
        rm -f "${INDEX}.bak"

        grep -qF "\"softwareVersion\": \"${VERSION}\"" "$INDEX" || die "softwareVersion did not update"
        grep -qF "<span class=\"badge\">v${VERSION}</span>" "$INDEX" || die "version badge did not update"
        pass "softwareVersion + badge now at $VERSION"
    fi
fi

# -----------------------------------------------------------------------------
# 3. Commit and push
# -----------------------------------------------------------------------------
step "Site repo state"

if [[ -z "$(git -C "$SITE_REPO" status --porcelain)" ]]; then
    warn "nothing changed in the site repo — already in sync"
    exit 0
fi
git -C "$SITE_REPO" status --short | sed 's/^/  /'

if [[ "$DRY_RUN" == "true" ]]; then
    printf '\nDRY RUN — no commit, no push.\n'
    git -C "$SITE_REPO" --no-pager diff --stat | sed 's/^/  /'
    exit 0
fi

# GitHub Pages serves this repo's root, and it carries no .gitignore — so a
# stray file left in that directory during the editorial pass would become
# publicly fetchable at https://aiconsultants.sh/<file> on the next push.
# Untracked paths are therefore an explicit decision, never a side effect of
# `git add -A`.
UNTRACKED="$(git -C "$SITE_REPO" ls-files --others --exclude-standard)"
if [[ -n "$UNTRACKED" ]] && [[ "$ALLOW_UNTRACKED" == "false" ]]; then
    printf '\n%sUntracked files in the site repo:%s\n' "$RED" "$NC" >&2
    printf '%s\n' "$UNTRACKED" | sed 's/^/  /' >&2
    printf '\nGitHub Pages would publish these at https://aiconsultants.sh/<path>.\n' >&2
    printf 'Remove them, or pass --allow-untracked if they belong on the site.\n' >&2
    exit 1
fi

git -C "$SITE_REPO" add -A
git -C "$SITE_REPO" commit -F "$MESSAGE_FILE"
pass "committed $(git -C "$SITE_REPO" rev-parse --short HEAD)"

if [[ "$PUSH" == "false" ]]; then
    printf '\n%s--no-push set.%s Deploy with: git -C %s push origin main\n' "$YELLOW" "$NC" "$SITE_REPO"
    exit 0
fi

git -C "$SITE_REPO" push origin main
pass "pushed — GitHub Pages will deploy aiconsultants.sh shortly"
