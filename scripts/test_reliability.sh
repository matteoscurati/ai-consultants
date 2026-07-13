#!/bin/bash
# shellcheck disable=SC2329
# (test_*/assert_* are invoked indirectly via `run_test "$@"`)
#
# test_reliability.sh - Tests for lib/reliability.sh (per-consultant persistence)
#
# Mirrors scripts/test_suite.sh::test_cost_tracking_resilience: fresh-install
# path (missing nested parent dir), corrupt-file self-heal (with .corrupt
# backup), and correct accumulation across multiple consultants.
#
# Usage: ./scripts/test_reliability.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
# shellcheck source=lib/reliability.sh
source "$SCRIPT_DIR/lib/reliability.sh"

TMP=$(mktemp -d -t ai_consultants_reliability_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# -----------------------------------------------------------------------------
# Fresh-install + accumulation + corrupt-file self-heal
# -----------------------------------------------------------------------------
test_fresh_install_and_accumulation() {
    RELIABILITY_FILE="$TMP/reliability/nonexistent/nested/reliability.json"

    # Calls are guarded with || true: a recurrence of the guarded bugs must
    # surface as FAIL assertions below, not abort the suite under set -e
    record_consultant_outcome "A" success 2>/dev/null || true
    assert_eq "1" "$(test -f "$RELIABILITY_FILE" && echo 1 || echo 0)" \
        "reliability.json created under a missing parent dir"

    record_consultant_outcome "A" success 2>/dev/null || true
    record_consultant_outcome "A" fail 2>/dev/null || true

    assert_eq "66" "$(get_consultant_reliability "A")" \
        "A: 2 success + 1 fail -> 66% (200/3=66)"
}

test_corrupt_file_self_heal() {
    RELIABILITY_FILE="$TMP/reliability_corrupt/reliability.json"
    mkdir -p "$(dirname "$RELIABILITY_FILE")"
    echo '{"consultants": [' > "$RELIABILITY_FILE"

    record_consultant_outcome "B" success 2>/dev/null || true

    assert_eq "100" "$(get_consultant_reliability "B")" \
        "corrupt reliability.json is reset and the new outcome recorded"
    assert_eq "1" "$(test -f "${RELIABILITY_FILE}.corrupt" && echo 1 || echo 0)" \
        "corrupt file preserved as .corrupt backup"
}

test_second_consultant_independent() {
    RELIABILITY_FILE="$TMP/reliability_multi/reliability.json"

    record_consultant_outcome "A" success 2>/dev/null || true
    record_consultant_outcome "A" fail 2>/dev/null || true
    record_consultant_outcome "B" success 2>/dev/null || true
    record_consultant_outcome "B" success 2>/dev/null || true

    assert_eq "50" "$(get_consultant_reliability "A")" "A: 1/2 -> 50%"
    assert_eq "100" "$(get_consultant_reliability "B")" "B: 2/2 -> 100% (independent of A)"
}

test_no_attempts_recorded() {
    RELIABILITY_FILE="$TMP/reliability_none/reliability.json"
    assert_eq "-1" "$(get_consultant_reliability "Nobody")" \
        "no attempts recorded -> -1"
}

run_test "Test 1: fresh install + accumulation"     test_fresh_install_and_accumulation
run_test "Test 2: corrupt file self-heal"           test_corrupt_file_self_heal
run_test "Test 3: second consultant accumulates independently" test_second_consultant_independent
run_test "Test 4: no attempts recorded -> -1"       test_no_attempts_recorded

test_summary "reliability"
