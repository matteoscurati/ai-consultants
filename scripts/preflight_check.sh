#!/bin/bash
# preflight_check.sh - DEPRECATED since v2.10.9
#
# This script has been superseded by doctor.sh, which performs the same
# checks plus additional ones (CLI/API mode switching, Ollama, synthesis,
# all 15 consultants, structured fix suggestions).
#
# This wrapper preserves backward compatibility by translating flags and
# delegating to doctor.sh. It will be removed in a future major release.
#
# Migration:
#   ./preflight_check.sh                      ->  ./doctor.sh
#   ./preflight_check.sh --quick              ->  ./doctor.sh --quick
#   ./preflight_check.sh --json               ->  ./doctor.sh --json
#   ./preflight_check.sh --suggest-config     ->  ./doctor.sh --suggest-config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect quiet/no-stderr usage from consult_all.sh: only print deprecation
# notice when stderr is a TTY, to avoid noise in scripted callers.
if [[ -t 2 ]]; then
    echo "WARNING: preflight_check.sh is deprecated since v2.10.9. Use doctor.sh instead." >&2
    echo "         Forwarding to: doctor.sh $*" >&2
    echo "" >&2
fi

exec "$SCRIPT_DIR/doctor.sh" "$@"
