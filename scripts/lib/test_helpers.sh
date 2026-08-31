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
skipped=0

# Render a named test section.
# Usage: test_section <name>
test_section() {
    echo -e "\n${C_YELLOW}--- $1 ---${C_RESET}"
}

# Record one passing assertion.
# Usage: test_pass <message>
test_pass() {
    ((checked++)) || true
    echo -e "  ${C_GREEN}PASS${C_RESET}: $1"
}

# Record one failed assertion with optional diagnostic lines.
# Usage: test_fail <message> [detail...]
test_fail() {
    local message="$1"
    shift
    ((checked++)) || true
    ((failed++)) || true
    echo -e "  ${C_RED}FAIL${C_RESET}: $message"
    local detail
    for detail in "$@"; do
        echo "         $detail"
    done
}

# Record a skipped assertion.
# Usage: test_skip <message> [reason]
test_skip() {
    local message="$1" reason="${2:-}"
    ((checked++)) || true
    ((skipped++)) || true
    echo -e "  ${C_YELLOW}SKIP${C_RESET}: $message${reason:+ ($reason)}"
}

# Assert two values are equal.
# Usage: assert_eq <expected> <actual> <message>
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$actual" == "$expected" ]]; then
        test_pass "$msg"
    else
        test_fail "$msg" "expected: '$expected'" "actual:   '$actual'"
    fi
}

# Assert a string matches a regex.
# Usage: assert_match <pattern> <haystack> <message>
assert_match() {
    local pattern="$1" haystack="$2" msg="$3"
    if [[ "$haystack" =~ $pattern ]]; then
        test_pass "$msg"
    else
        test_fail "$msg (no match for /$pattern/)" "haystack: '$haystack'"
    fi
}

# Assert two values are not equal.
# Usage: assert_ne <not_expected> <actual> <message>
assert_ne() {
    local not_expected="$1" actual="$2" msg="$3"
    if [[ "$actual" != "$not_expected" ]]; then
        test_pass "$msg"
    else
        test_fail "$msg" "should not be: '$not_expected'" "actual:        '$actual'"
    fi
}

# Assert a string contains a substring.
# Usage: assert_contains <substring> <haystack> <message>
assert_contains() {
    local substring="$1" haystack="$2" msg="$3"
    if [[ "$haystack" == *"$substring"* ]]; then
        test_pass "$msg"
    else
        test_fail "$msg" "expected to contain: '$substring'" "actual: '$haystack'"
    fi
}

# Assert a string does not contain a substring.
# Usage: assert_not_contains <substring> <haystack> <message>
assert_not_contains() {
    local substring="$1" haystack="$2" msg="$3"
    if [[ "$haystack" != *"$substring"* ]]; then
        test_pass "$msg"
    else
        test_fail "$msg" "should not contain: '$substring'" "actual: '$haystack'"
    fi
}

# Assert a command exits successfully.
# Usage: assert_exit_success <message> <command...>
assert_exit_success() {
    local message="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        test_pass "$message"
    else
        test_fail "$message" "command exited non-zero: $*"
    fi
}

# Assert a command exits unsuccessfully.
# Usage: assert_exit_failure <message> <command...>
assert_exit_failure() {
    local message="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        test_fail "$message" "command should have failed: $*"
    else
        test_pass "$message"
    fi
}

# Assert a numeric value is greater than a threshold.
# Usage: assert_gt <threshold> <actual> <message>
assert_gt() {
    local threshold="$1" actual="$2" message="$3"
    if [[ "$actual" -gt "$threshold" ]]; then
        test_pass "$message"
    else
        test_fail "$message" "expected > $threshold" "actual: $actual"
    fi
}

# Assert a numeric value is less than or equal to a threshold.
# Usage: assert_lte <threshold> <actual> <message>
assert_lte() {
    local threshold="$1" actual="$2" message="$3"
    if [[ "$actual" -le "$threshold" ]]; then
        test_pass "$message"
    else
        test_fail "$message" "expected <= $threshold" "actual: $actual"
    fi
}

# Assert a string contains valid JSON.
# Usage: assert_json <json_string> <message>
assert_json() {
    local json="$1" message="$2"
    if printf '%s' "$json" | jq . >/dev/null 2>&1; then
        test_pass "$message"
    else
        test_fail "$message" "not valid JSON: ${json:0:100}..."
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

# Print a detailed summary without exiting, for large suites with direct
# assertion calls instead of run_test wrappers.
# Usage: test_summary_detailed <suite> <duration_seconds>
test_summary_detailed() {
    local suite="$1" duration="$2"
    local passed=$((checked - failed - skipped))

    echo -e "\n${C_YELLOW}============================================${C_RESET}"
    echo -e "${C_YELLOW}  Results${C_RESET}"
    echo -e "${C_YELLOW}============================================${C_RESET}"
    echo "  Total:   $checked"
    echo -e "  ${C_GREEN}Passed:  $passed${C_RESET}"
    echo -e "  ${C_RED}Failed:  $failed${C_RESET}"
    [[ $skipped -gt 0 ]] && echo -e "  ${C_YELLOW}Skipped: $skipped${C_RESET}"
    echo "  Time:    ${duration}s"

    if [[ $checked -eq 0 ]]; then
        echo -e "\n${C_RED}${suite}: FAILED${C_RESET} (no assertions ran)"
        return 1
    fi
    if [[ $failed -gt 0 ]]; then
        echo -e "\n${C_RED}${suite}: FAILED${C_RESET} ($failed test(s) did not pass)"
        return 1
    fi
    echo -e "\n${C_GREEN}${suite}: ALL TESTS PASSED.${C_RESET}"
    return 0
}
