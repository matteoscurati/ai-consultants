#!/bin/bash
# install-hooks.sh - Install git pre-commit hooks for ai-consultants development.
#
# Usage:
#   bash scripts/install-hooks.sh        # or: npm run install-hooks
#   FORCE=1 bash scripts/install-hooks.sh   # overwrite without backup
#
# Idempotent: copies scripts/hooks/pre-commit into .git/hooks/pre-commit.
# No-ops cleanly outside a git checkout (e.g. when the package is consumed
# from an npm tarball without the .git/ directory).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -d "$REPO_ROOT/.git" ]]; then
    # Not a git checkout — nothing to install. Silent exit so the script is
    # safe to run from package-manager hooks (npm prepare, etc).
    exit 0
fi

HOOK_SOURCE="$SCRIPT_DIR/hooks/pre-commit"
HOOK_DEST="$REPO_ROOT/.git/hooks/pre-commit"

if [[ ! -f "$HOOK_SOURCE" ]]; then
    echo "error: $HOOK_SOURCE not found" >&2
    exit 1
fi

# If a different hook already lives there, back it up so we don't clobber
# anyone's customization.
if [[ -f "$HOOK_DEST" ]] && ! cmp -s "$HOOK_SOURCE" "$HOOK_DEST"; then
    if [[ "${FORCE:-0}" == "1" ]]; then
        echo "FORCE=1: overwriting existing pre-commit hook without backup"
    else
        backup="$HOOK_DEST.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$HOOK_DEST" "$backup"
        echo "Backed up existing pre-commit hook to $backup"
    fi
fi

cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "Installed pre-commit hook at .git/hooks/pre-commit"
echo "  Source: scripts/hooks/pre-commit"
echo "  Runs:   shellcheck on staged .sh files under scripts/"
echo "  Bypass: git commit --no-verify"
