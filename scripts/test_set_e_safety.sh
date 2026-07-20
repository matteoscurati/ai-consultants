#!/bin/bash
# test_set_e_safety.sh - Regression test for the ((var++)) abort class of bug
#
# Background: under `set -e` on bash 4+, a bare `((var++))` where var was 0
# returns exit 1 (post-increment yields the old value 0 → "false") and aborts
# the script. The codebase convention is `((var++)) || true`. v2.8.1, v2.10.1,
# and v2.10.9 each fixed regressions of this bug. This test prevents the next
# one.
#
# Two checks:
#   1. Static lint: no unprotected `((var++))` outside the deprecated wrapper.
#   2. Dynamic check (only if bash 4+ available): a synthetic script that
#      uses `set -euo pipefail` + bare `((x++))` where x=0 must abort, while
#      the same with `|| true` must succeed. Confirms the runtime semantics.
#
# Usage: ./scripts/test_set_e_safety.sh
# Exit:  0 if all checks pass, 1 otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"

failed=0

# -----------------------------------------------------------------------------
# Check 1: static lint
# -----------------------------------------------------------------------------
echo "Check 1: static lint for unprotected ((var++))"

# Find any standalone arithmetic increment that aborts under set -e when the
# expression evaluates to 0. Covers:
#   - Post-increment / decrement: ((var++)) ((var--))
#   - Compound assignments resulting in 0: ((var+=1)) ((var-=1)) (when sum=0)
#   - The legacy `let var++` form
# Excludes (safe pre-increment yields the new value, never 0 from a counter):
#   - ((++var)) ((--var)) — pre-ops; safe when initial >= 0
# Path exclusions:
#   - preflight_check.sh (deprecated thin wrapper, no counters)
#   - this test file (intentionally documents the patterns above)
post_pattern='\(\([[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(\+\+|--)[[:space:]]*\)\)'
let_pattern='let[[:space:]]+[^|&;]*[[:space:]]*(\+\+|--)'
unprotected=$( { \
    grep -rnE "$post_pattern" "$PROJECT_ROOT/scripts/" --include='*.sh' || true; \
    grep -rnE "$let_pattern"  "$PROJECT_ROOT/scripts/" --include='*.sh' || true; \
    } | grep -v '|| true' \
      | grep -v '/preflight_check.sh:' \
      | grep -v '/test_set_e_safety.sh:' \
      || true)

# A lint that scans nothing reports "zero occurrences" and passes. If the glob,
# the path, or the --include ever breaks, this suite would go permanently green
# while checking no files at all — the lint equivalent of a suite that runs no
# assertions. Prove the corpus is non-empty before trusting an empty result.
scanned=$(grep -rlE '.' "$PROJECT_ROOT/scripts/" --include='*.sh' 2>/dev/null | wc -l | tr -d ' ')
if [[ "${scanned:-0}" -lt 10 ]]; then
    echo -e "  ${C_RED}FAIL${C_RESET}: the lint corpus is only ${scanned:-0} file(s) — the scan is broken, not clean"
    failed=1
elif [[ -z "$unprotected" ]]; then
    echo -e "  ${C_GREEN}PASS${C_RESET}: zero unprotected ((var++)) occurrences across $scanned scripts"
else
    echo -e "  ${C_RED}FAIL${C_RESET}: found unprotected ((var++)) — must be suffixed with ' || true':"
    # shellcheck disable=SC2001  # multi-line indent via sed; param expansion is awkward
    echo "$unprotected" | sed 's/^/    /'
    failed=1
fi

# -----------------------------------------------------------------------------
# Check 2: dynamic semantics (bash 4+ only)
# -----------------------------------------------------------------------------
echo ""
echo "Check 2: runtime semantics under set -e"

# Locate a bash 4+ binary if available. macOS ships with bash 3.2 which does
# not exhibit the bug; we explicitly verify against bash 4+ when present.
bash4=""
for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash bash; do
    if command -v "$candidate" >/dev/null 2>&1; then
        # shellcheck disable=SC2016  # ${BASH_VERSION} resolved by the inner bash
        version=$("$candidate" -c 'echo "${BASH_VERSION%%.*}"' 2>/dev/null || echo "0")
        if (( version >= 4 )); then
            bash4="$candidate"
            break
        fi
    fi
done

if [[ -z "$bash4" ]]; then
    echo -e "  ${C_YELLOW}SKIP${C_RESET}: no bash 4+ available (current: $BASH_VERSION) — bash 3.2 does not exhibit the bug, so dynamic check would be vacuous"
else
    # shellcheck disable=SC2016  # $BASH_VERSION resolved by the inner bash
    bash4_version=$("$bash4" -c 'echo "$BASH_VERSION"')

    # Sub-check 2a: bare ((x++)) when x=0 SHOULD abort under set -e
    if "$bash4" -c 'set -euo pipefail; x=0; ((x++)); echo "after"' >/dev/null 2>&1; then
        echo -e "  ${C_RED}FAIL${C_RESET}: bash $bash4_version did not abort on bare ((x++)) — assumption invalid"
        failed=1
    else
        echo -e "  ${C_GREEN}PASS${C_RESET}: bash $bash4_version aborts on unprotected ((x++)) (as expected)"
    fi

    # Sub-check 2b: ((x++)) || true MUST NOT abort
    if "$bash4" -c 'set -euo pipefail; x=0; ((x++)) || true; echo "after"' >/dev/null 2>&1; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: bash $bash4_version succeeds on protected ((x++)) || true"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: bash $bash4_version aborted even with || true — convention is broken"
        failed=1
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${C_GREEN}set -e safety: OK${C_RESET}"
    exit 0
else
    echo -e "${C_RED}set -e safety: FAILED${C_RESET}"
    exit 1
fi
