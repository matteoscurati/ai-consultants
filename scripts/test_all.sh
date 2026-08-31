#!/bin/bash
# test_all.sh - Master runner for the standalone test_*.sh scripts (v2.13+)
#
# Discovers every standalone test_*.sh suite, including test_suite.sh, so a
# single command exercises the full regression gate.
#
# Usage: ./scripts/test_all.sh
# Exit:  0 if all suites pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_BLUE="\033[34m"
C_DIM="\033[2m"

# Discover all test_*.sh scripts. Each runs in its own subprocess (via the
# loop below executing the script), so frameworks with different assert
# naming conventions don't collide.
# Excluded: test_all.sh itself.
suites=()
while IFS= read -r f; do
    suites+=("$f")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'test_*.sh' -type f \
    ! -name 'test_all.sh' \
    | sort)

failed_suites=()
total_pass=0
total_fail=0

echo -e "${C_BLUE}AI Consultants test suite${C_RESET}"
echo -e "${C_DIM}$(date)${C_RESET}"
echo ""

for suite in "${suites[@]}"; do
    name=$(basename "$suite")
    echo -e "─── ${C_BLUE}$name${C_RESET} ───────────────────────────────────────"
    if "$suite"; then
        ((total_pass++)) || true
    else
        ((total_fail++)) || true
        failed_suites+=("$name")
    fi
    echo ""
done

echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "Suites passed: ${C_GREEN}$total_pass${C_RESET} / ${#suites[@]}"
if (( total_fail > 0 )); then
    echo -e "Suites failed: ${C_RED}$total_fail${C_RESET}"
    for s in "${failed_suites[@]}"; do
        echo -e "  ${C_RED}✗${C_RESET} $s"
    done
    exit 1
fi
echo -e "${C_GREEN}All test suites passed.${C_RESET}"
exit 0
