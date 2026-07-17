#!/usr/bin/env bash
# Backward-compatible entry point. The maintained wizard is configure.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Note: setup_wizard.sh is deprecated; use 'ai-consultants configure --interactive'." >&2
exec "$SCRIPT_DIR/configure.sh" --interactive "$@"
