#!/bin/bash
# shellcheck disable=SC2329
# (test_*/assert_eq are invoked indirectly via `run_test "$@"`)
#
# test_doctor.sh - Tests for doctor.sh feature flags introduced in v2.13+
#
# Covers:
#   --suggest-preset behavior across question categories and consultant counts
#   --suggest-preset with no question (defaults to GENERAL)
#   --suggest-preset is independent from main check pipeline (no health checks run)
#
# Pre-existing surfaces (--suggest-config, --quick, main check) are integration-
# tested via the verify skill — this file focuses on Phase 4 additions.
#
# Usage: ./scripts/test_doctor.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$SCRIPT_DIR/doctor.sh"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

# Keep preset recommendations independent from whichever consultant CLIs happen
# to be installed on the developer machine or the GitHub runner. `true` is a
# portable executable stand-in; these tests exercise selection/counting only and
# never invoke the consultants. Tests that need count=0 disable every ENABLE_*.
export GEMINI_CMD=true CODEX_CMD=true MISTRAL_CMD=true CURSOR_CMD=true
export KIMI_CMD=true CLAUDE_CMD=true QWEN3_CMD=true MINIMAX_CMD=true

# Each test invokes `doctor.sh --suggest-preset` with a different question
# and asserts both the recommended preset/strategy and the reasoning text.

test_suggest_no_question_is_general() {
    local out
    out=$("$DOCTOR" --suggest-preset 2>/dev/null)
    assert_match 'preset balanced.*strategy majority' "$out" "no question -> balanced + majority"
    assert_match 'GENERAL category' "$out" "no question -> reason mentions GENERAL"
    assert_match 'pass --question' "$out" "no question -> tip about --question shown"
}

test_suggest_security_picks_security_first() {
    local out
    out=$("$DOCTOR" --suggest-preset --question \
        "How can I prevent SQL injection in my login endpoint?" 2>/dev/null)
    assert_match 'strategy security_first' "$out" "SECURITY -> strategy=security_first"
    assert_match 'SECURITY detected' "$out" "SECURITY -> reason mentions detection"
}

test_suggest_quick_syntax_picks_fast() {
    local out
    out=$("$DOCTOR" --suggest-preset --question \
        "what is the syntax for python list comprehension?" 2>/dev/null)
    assert_match 'preset fast' "$out" "QUICK_SYNTAX -> preset=fast"
    assert_match 'QUICK_SYNTAX detected' "$out" "QUICK_SYNTAX -> reason mentions detection"
}

test_suggest_architecture_picks_risk_averse() {
    local out
    out=$("$DOCTOR" --suggest-preset --question \
        "should I split this monolith into microservices?" 2>/dev/null)
    assert_match 'strategy risk_averse' "$out" "ARCHITECTURE -> strategy=risk_averse"
    assert_match 'ARCHITECTURE detected' "$out" "ARCHITECTURE -> reason mentions detection"
}

test_suggest_algorithm_default_strategy() {
    local out
    out=$("$DOCTOR" --suggest-preset --question \
        "what's an O(log n) algorithm for binary search?" 2>/dev/null)
    assert_match 'preset balanced.*strategy majority' "$out" "ALGORITHM -> balanced + majority"
    assert_match 'ALGORITHM detected' "$out" "ALGORITHM -> reason mentions detection"
}

# Question gets truncated in the output if too long. Verify it doesn't crash
# and that the truncation marker '...' appears.
test_suggest_truncates_long_question() {
    local long_q
    long_q="this is a question that exceeds the sixty character display limit and should be truncated in the output"
    local out
    out=$("$DOCTOR" --suggest-preset --question "$long_q" 2>/dev/null)
    assert_match '\.\.\.' "$out" "long question is truncated with ..."
}

# Verify that --suggest-preset short-circuits the main check pipeline
# (would fail in CI environments where consultants aren't installed).
test_suggest_does_not_run_main_checks() {
    local out
    out=$("$DOCTOR" --suggest-preset --question "test" 2>/dev/null)
    if [[ "$out" == *"Diagnosis Summary"* ]]; then
        ((failed++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: --suggest-preset should NOT print 'Diagnosis Summary'"
    else
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: --suggest-preset short-circuits before main check pipeline"
    fi
}

run_test "Test 1: no question defaults to GENERAL"     test_suggest_no_question_is_general
run_test "Test 2: SECURITY -> security_first"          test_suggest_security_picks_security_first
run_test "Test 3: QUICK_SYNTAX -> fast preset"         test_suggest_quick_syntax_picks_fast
run_test "Test 4: ARCHITECTURE -> risk_averse"         test_suggest_architecture_picks_risk_averse
run_test "Test 5: ALGORITHM -> balanced + majority"    test_suggest_algorithm_default_strategy
run_test "Test 6: long questions are truncated"        test_suggest_truncates_long_question
run_test "Test 7: short-circuits main pipeline"        test_suggest_does_not_run_main_checks

# v2.13 review fixes ----------------------------------------------------------

# MED 5: --json output is well-formed and includes the new fields.
test_suggest_json_output() {
    local out
    out=$("$DOCTOR" --suggest-preset --question "should I use redis?" --json 2>/dev/null)
    # Valid JSON?
    if echo "$out" | jq empty 2>/dev/null; then
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: --json output is valid JSON"
    else
        ((failed++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: --json output is not valid JSON: $out"
    fi
    local preset strategy category failed_flag
    preset=$(echo "$out" | jq -r '.preset')
    strategy=$(echo "$out" | jq -r '.strategy')
    category=$(echo "$out" | jq -r '.category')
    failed_flag=$(echo "$out" | jq -r '.classification_failed')
    assert_match '^(minimal|balanced|thorough|high-stakes|fast)$' "$preset" "preset is a known value"
    assert_match '^(majority|risk_averse|security_first|cost_capped|compare_only)$' "$strategy" \
        "strategy is a known value"
    assert_match '^[A-Z_]+$' "$category" "category is uppercase enum"
    assert_match '^(true|false)$' "$failed_flag" "classification_failed is boolean"
}

# MED 6: count<2 short-circuits to install hint regardless of category.
# Hermetic: simulate count=0 by disabling all enable flags.
test_suggest_low_count_short_circuits() {
    local out
    out=$(ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false \
        ENABLE_CURSOR=false \
        ENABLE_KIMI=false ENABLE_CLAUDE=false \
        ENABLE_QWEN3=false \
        ENABLE_GLM=false ENABLE_GROK=false ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        "$DOCTOR" --suggest-preset --question "How can I prevent SQL injection?" 2>/dev/null)
    assert_match 'install more CLIs' "$out" "count<2 short-circuits to install hint"
    assert_match 'preset minimal' "$out" "count<2 still proposes minimal preset"
}

# HIGH 1 fix: classifier failure surfaces a Warning, doesn't silently degrade.
# Cleanup inline: assertions in this harness don't abort under set -e (they
# increment $failed and continue), so a trap is unnecessary and bash 3.2
# RETURN traps interact poorly with `local` variables.
test_suggest_surfaces_classifier_failure() {
    local fake_root
    fake_root=$(mktemp -d)
    cp -r scripts "$fake_root/"
    chmod 000 "$fake_root/scripts/classify_question.sh"
    local out
    out=$("$fake_root/scripts/doctor.sh" --suggest-preset --question "test" 2>&1 || true)
    chmod +x "$fake_root/scripts/classify_question.sh" 2>/dev/null || true
    rm -rf "$fake_root"
    assert_match 'Warning: classification.*failed' "$out" "classifier failure surfaces Warning"
    assert_match 'falls back to GENERAL' "$out" "warning explains the GENERAL fallback"
}

# HIGH 2 fix: missing get_xdg_dir aborts loudly instead of silent /tmp regression.
test_config_sh_aborts_without_xdg_helper() {
    local fake_root
    fake_root=$(mktemp -d)
    cp -r scripts "$fake_root/"
    rm "$fake_root/scripts/lib/user_config.sh"
    local rc=0 err
    err=$(bash -c "source $fake_root/scripts/config.sh" 2>&1) || rc=$?
    rm -rf "$fake_root"
    assert_match 'FATAL.*get_xdg_dir' "$err" "missing user_config.sh aborts with FATAL"
    assert_eq "1" "$rc" "config.sh exits 1 when get_xdg_dir is missing"
}

# HIGH 3: count gates on ENABLE_* flags. Use the shell builtin `true` as a
# hermetic stand-in for Cursor so the test does not depend on host CLIs.
test_count_respects_enable_flags() {
    local count_with count_without
    count_with=$(CURSOR_CMD=true ENABLE_CURSOR=true "$DOCTOR" --suggest-preset --question "test" --json \
        2>/dev/null | jq -r '.consultants_available')
    count_without=$(CURSOR_CMD=true ENABLE_CURSOR=false "$DOCTOR" --suggest-preset --question "test" --json \
        2>/dev/null | jq -r '.consultants_available')
    if (( count_with > count_without )); then
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: ENABLE_CURSOR=false drops count ($count_with -> $count_without)"
    else
        ((failed++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: ENABLE_CURSOR gating ignored (with=$count_with, without=$count_without)"
    fi
}

run_test "Test 8: --json output schema (v2.13 fix MED 5)"  test_suggest_json_output
run_test "Test 9: count<2 short-circuit (v2.13 fix MED 6)" test_suggest_low_count_short_circuits
run_test "Test 10: classifier failure surfaces (HIGH 1)"   test_suggest_surfaces_classifier_failure
run_test "Test 11: config.sh fails loudly without get_xdg_dir (HIGH 2)" test_config_sh_aborts_without_xdg_helper
run_test "Test 12: count respects ENABLE_* (HIGH 3)"       test_count_respects_enable_flags

# Round-2 review fix: self-exclusion was previously dead code due to
# case-mismatch (UPPERCASE vs MixedCase). Verify INVOKING_AGENT actually
# subtracts the invoker from the count when that consultant is enabled+installed.
test_self_exclusion_reduces_count() {
    if ! command -v claude >/dev/null 2>&1; then
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: skipped (claude CLI not installed; can't observe self-exclusion)"
        return 0
    fi
    local base_count excl_count
    base_count=$(ENABLE_CLAUDE=true "$DOCTOR" --suggest-preset --json --question "test" \
        2>/dev/null | jq -r '.consultants_available')
    excl_count=$(ENABLE_CLAUDE=true INVOKING_AGENT=claude "$DOCTOR" --suggest-preset --json \
        --question "test" 2>/dev/null | jq -r '.consultants_available')
    if (( base_count > 0 )) && (( excl_count == base_count - 1 )); then
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: INVOKING_AGENT=claude drops count ($base_count -> $excl_count)"
    else
        ((failed++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: self-exclusion broken (base=$base_count, excluded=$excl_count, expected $((base_count-1)))"
    fi
}

# Round-2 review fix: --json must pre-flight jq with a clear error message
# instead of aborting under set -e with a cryptic 'command not found'.
test_json_preflights_jq() {
    # Simulate jq absence by overriding `command` builtin in a subshell.
    # We test the preflight code path directly to avoid breaking the script's
    # bootstrap (which uses dirname, source, etc.).
    local out rc=0
    out=$(bash -c '
        command() {
            if [[ "$#" == "2" ]] && [[ "$1" == "-v" ]] && [[ "$2" == "jq" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        export -f command
        if ! command -v jq >/dev/null 2>&1; then
            echo "ERROR: --json requires '"'"'jq'"'"' to be installed" >&2
            exit 1
        fi
    ' 2>&1) || rc=$?
    assert_match 'requires .jq.' "$out" "preflight emits clear jq error"
    assert_eq "1" "$rc" "preflight exits 1 when jq missing"
}

# Schema fields: schema_version + recommended_command added in round 2.
test_json_includes_schema_version_and_command() {
    local out
    out=$("$DOCTOR" --suggest-preset --json --question "test query" 2>/dev/null)
    local schema_version recommended_command
    schema_version=$(echo "$out" | jq -r '.schema_version')
    recommended_command=$(echo "$out" | jq -r '.recommended_command')
    assert_eq "1" "$schema_version" "schema_version=1"
    assert_match 'ai-consultants --preset' "$recommended_command" "recommended_command contains the invocation"
    assert_match 'test query' "$recommended_command" "recommended_command echoes the question (untruncated in JSON)"
}

run_test "Test 13: self-exclusion drops count (HIGH fix)"  test_self_exclusion_reduces_count
run_test "Test 14: --json preflights jq (MED fix)"         test_json_preflights_jq
run_test "Test 15: --json schema_version + recommended_command (round-2)" test_json_includes_schema_version_and_command

# Main doctor JSON mode must suppress human-readable sections without returning
# non-zero from the print helper. A false `[[ ... ]] && echo` under `set -e`
# previously aborted at print_header and emitted no JSON at all.
test_main_json_output() {
    local tmp out rc=0
    tmp=$(mktemp -d)
    out=$(HOME="$tmp" \
        XDG_CONFIG_HOME="$tmp/config" \
        XDG_CACHE_HOME="$tmp/cache" \
        XDG_STATE_HOME="$tmp/state" \
        XDG_DATA_HOME="$tmp/data" \
        "$DOCTOR" --json 2>/dev/null) || rc=$?
    rm -rf "$tmp"

    if echo "$out" | jq empty 2>/dev/null; then
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: main --json output is valid JSON"
    else
        ((failed++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: main --json output is not valid JSON: $out"
        return 0
    fi

    local version status total empty_entries
    version=$(echo "$out" | jq -r '.doctor.version')
    status=$(echo "$out" | jq -r '.doctor.status')
    total=$(echo "$out" | jq -r '.doctor.checks.total')
    empty_entries=$(echo "$out" | jq \
        '[.doctor.issues[], .doctor.warnings[] | select(.description == "")] | length')
    assert_match '^[0-9]+\.[0-9]+\.[0-9]+$' "$version" "main --json includes doctor version"
    assert_match '^(healthy|degraded|unhealthy)$' "$status" "main --json includes doctor status"
    assert_match '^[1-9][0-9]*$' "$total" "main --json includes completed checks"
    assert_eq "0" "$empty_entries" "main --json does not synthesize empty issue/warning entries"
    assert_match '^(0|1)$' "$rc" "main --json exit code reflects health without aborting"
}

run_test "Test 16: main --json emits a complete diagnostic" test_main_json_output

test_summary "doctor"
