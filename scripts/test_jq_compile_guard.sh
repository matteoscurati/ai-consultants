#!/bin/bash
# test_jq_compile_guard.sh - The jq shim test_all.sh puts on PATH must be
# transparent to callers and must record exactly the errors in a filter.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_jq_compile_guard.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

GUARD="$SCRIPT_DIR/test_fixtures/jq_compile_guard.sh"
# test_all.sh may already have put the guard first on PATH; use the real jq.
REAL_JQ="${JQ_GUARD_REAL:-$(command -v jq)}"
LOG="$TMP_ROOT/compile-errors.log"

guard() { JQ_GUARD_REAL="$REAL_JQ" JQ_GUARD_LOG="$LOG" "$GUARD" "$@"; }

test_guard_is_transparent() {
    : > "$LOG"
    assert_eq '[1,2]' "$(printf '%s' '{"a":[1,2]}' | guard -c '.a')" "stdin and stdout pass through unchanged"
    printf '%s' '{"a":1}' | guard -e '.b' >/dev/null
    assert_eq 1 "$?" "the exit status of jq -e is kept"
    assert_eq "" "$(cat "$LOG")" "a working filter records nothing"
}

test_guard_ignores_runtime_errors() {
    : > "$LOG"
    printf '%s' '{"x":' | guard . >/dev/null 2>&1
    assert_eq 5 "$?" "invalid JSON input keeps jq's exit status"
    printf '%s' '"text"' | guard '.[]' >/dev/null 2>&1
    assert_eq "" "$(cat "$LOG")" "runtime errors are left to the caller"
}

test_guard_records_compile_errors() {
    : > "$LOG"
    # The exact pre-5.3.1 Coverage Union quoting.
    guard -n '"\(.kind // \"consideration\")"' >/dev/null 2>&1
    assert_eq 3 "$?" "a compile error keeps jq's exit status"
    guard -n 'not_a_function(1)' 2>/dev/null
    assert_eq 2 "$(grep -c '^--- rc=' "$LOG")" "syntax errors and undefined functions are both recorded"
    assert_contains 'consideration' "$(cat "$LOG")" "the record names the failing filter"
}

run_test "Guard is transparent to callers" test_guard_is_transparent
run_test "Guard ignores runtime errors" test_guard_ignores_runtime_errors
run_test "Guard records compile errors" test_guard_records_compile_errors

test_summary "jq_compile_guard"
