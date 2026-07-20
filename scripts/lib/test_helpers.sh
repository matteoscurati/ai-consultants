#!/bin/bash
# test_helpers.sh - Shared test framework for the standalone test_*.sh scripts.
#
# Conventions:
#   - Tests run in the outer shell (no subshell), so counters propagate.
#   - Each suite is run in its own process (via test_all.sh forking
#     `bash test_*.sh`), so `failed`/`checked` are per-suite.
#   - Define `_reset_state` in your suite to clear cross-test variables;
#     run_test calls it automatically before each test.
#   - All assertions increment `checked`; failures also increment `failed`.

# Guard against double-sourcing (test_*.sh files may be sourced into the
# same process by master runners).
if [[ -n "${_TEST_HELPERS_SH_SOURCED:-}" ]]; then
    # shellcheck disable=SC2317  # exit fallback for script-mode load
    return 0 2>/dev/null || exit 0
fi
_TEST_HELPERS_SH_SOURCED=1

# Color codes — exported so test scripts can also use them in custom messages.
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"

# Counters — each test suite starts fresh.
failed=0
checked=0

# Assert two values are equal.
# Usage: assert_eq <expected> <actual> <message>
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    ((checked++)) || true
    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: $msg"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: $msg"
        echo "         expected: '$expected'"
        echo "         actual:   '$actual'"
        ((failed++)) || true
    fi
}

# Assert a string matches a regex.
# Usage: assert_match <pattern> <haystack> <message>
assert_match() {
    local pattern="$1" haystack="$2" msg="$3"
    ((checked++)) || true
    if [[ "$haystack" =~ $pattern ]]; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: $msg"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: $msg (no match for /$pattern/)"
        echo "         haystack: '$haystack'"
        ((failed++)) || true
    fi
}

# Run a named test. Calls _reset_state if defined by the suite.
# Usage: run_test "Test 1: description" test_function_name
run_test() {
    local name="$1"
    shift
    echo ""
    echo "$name"
    declare -f _reset_state >/dev/null 2>&1 && _reset_state
    "$@"
}

# Print the suite summary line and exit with the appropriate code.
# Usage: test_summary "<suite_name>"
test_summary() {
    local suite="$1"
    echo ""
    # A suite that asserted nothing is a broken suite, not a passing one.
    # `run_test` takes "<name> <function>"; called with the function alone, the
    # name absorbs it, `shift` empties the list, and `"$@"` runs nothing — the
    # suite then reports OK having executed no test at all. Same family as the
    # v2.23.0 fix to test_functions.sh, one level up.
    if [[ $checked -eq 0 ]]; then
        echo -e "${C_RED}${suite}: FAILED${C_RESET} (no assertions ran — check the run_test calls take \"<name>\" <function>)"
        exit 1
    fi
    if [[ $failed -eq 0 ]]; then
        echo -e "${C_GREEN}${suite}: OK${C_RESET} (${checked} checks passed)"
        exit 0
    else
        echo -e "${C_RED}${suite}: FAILED${C_RESET} (${failed} of ${checked} failed)"
        exit 1
    fi
}
