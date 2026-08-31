#!/bin/bash
# test_common.sh - Focused tests for shared runtime helpers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1

TMP=$(mktemp -d -t ai_consultants_common_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

test_error_reason_extraction() {
    local err_file="$TMP/consultant.err"

    printf '[INFO] Consulting Example...\n[ERROR] Example CLI not found (command: example)\n' > "$err_file"
    assert_eq "[ERROR] Example CLI not found (command: example)" \
        "$(get_consultant_error_reason "$err_file")" \
        "explicit error line wins"

    printf '[INFO] Consulting GLM...\n[GLM] All 2 attempts failed: 401 Unauthorized\n' > "$err_file"
    assert_eq "[GLM] All 2 attempts failed: 401 Unauthorized" \
        "$(get_consultant_error_reason "$err_file")" \
        "embedded authentication reason is preserved"

    printf '[12:54:32] [ERROR] [Example] All 2 attempts failed: Error: Out of credits\n' > "$err_file"
    assert_eq "Error: Out of credits" "$(get_consultant_error_reason "$err_file")" \
        "logging boilerplate is stripped"

    printf '[12:00:00] [WARN] [Kimi] Timeout after 180s\n[12:03:00] [WARN] [Kimi] Timeout after 180s\n[12:03:00] [ERROR] [Kimi] All 3 attempts failed\n' > "$err_file"
    assert_eq "[12:03:00] [WARN] [Kimi] Timeout after 180s" \
        "$(get_consultant_error_reason "$err_file")" \
        "empty final reason falls back to the latest timeout"

    printf '[07:24:43] [INFO] Consulting Kimi (timeout: 180s, max retry: 2)...\n' > "$err_file"
    assert_eq "" "$(get_consultant_error_reason "$err_file")" \
        "status logging is not reported as a failure reason"

    : > "$err_file"
    assert_eq "" "$(get_consultant_error_reason "$err_file")" \
        "empty error file has no reason"
    assert_eq "" "$(get_consultant_error_reason "$TMP/missing.err")" \
        "missing error file has no reason"
}

test_failure_rendering() {
    assert_eq "  - GLM: 401 Unauthorized" \
        "$(render_diagnosed_failure 'GLM|401 Unauthorized')" \
        "console rendering includes consultant and reason"
    assert_eq "| GLM | 401 Unauthorized |" \
        "$(render_diagnosed_failure 'GLM|401 Unauthorized' table)" \
        "table rendering produces one row"
    assert_eq "| Example | a \\| b failed |" \
        "$(render_diagnosed_failure 'Example|a | b failed' table)" \
        "table rendering escapes pipes"
    assert_eq "  - Example: a | b failed" \
        "$(render_diagnosed_failure 'Example|a | b failed')" \
        "console rendering preserves pipes in the reason"
}

test_quorum_grading() {
    assert_eq "MET" "$(grade_quorum 4 4 2)" "all responses meet quorum"
    assert_eq "DEGRADED" "$(grade_quorum 3 4 2)" "partial panel above minimum is degraded"
    assert_eq "FAILED" "$(grade_quorum 1 4 2)" "panel below minimum fails"
    assert_eq "MET" "$(grade_quorum 2 2 2)" "exact minimum with no failures meets quorum"
    assert_eq "FAILED" "$(grade_quorum 0 3 2)" "zero responses fail quorum"
}

test_run_query_diagnostics() {
    local output logs rc=0
    output="$TMP/run-query-output"

    logs=$(MAX_RETRIES=1 RETRY_DELAY_SECONDS=0 run_query \
        "Probe" "$output" 5 bash -c 'echo "401 invalid key" >&2; exit 7' \
        </dev/null 2>&1) || rc=$?

    assert_eq "1" "$rc" "failed command remains a failure after retries"
    assert_match 'Error \(code: 7\): 401 invalid key' "$logs" \
        "underlying CLI error is logged"
    assert_match 'All 1 attempts failed: 401 invalid key' "$logs" \
        "final diagnostic preserves the cause"
}

test_ping_consultant() {
    local adapter_dir="$TMP/adapters" rc
    mkdir -p "$adapter_dir"

    printf '%s\n' '#!/bin/bash' 'echo '\''{"response":{"summary":"ok"}}'\'' > "$3"' \
        > "$adapter_dir/query_okagent.sh"
    printf '%s\n' '#!/bin/bash' 'echo "boom: not authenticated" >&2' \
        > "$adapter_dir/query_badagent.sh"
    chmod +x "$adapter_dir/query_okagent.sh" "$adapter_dir/query_badagent.sh"

    rc=0
    ping_consultant okagent "$adapter_dir" 10 "$TMP/ok.json" "$TMP/ok.err" || rc=$?
    assert_eq "0" "$rc" "valid adapter response is healthy"

    rc=0
    ping_consultant badagent "$adapter_dir" 10 "$TMP/bad.json" "$TMP/bad.err" || rc=$?
    assert_eq "1" "$rc" "empty adapter response is unhealthy"

    rc=0
    ping_consultant noscriptagent "$adapter_dir" 10 "$TMP/none.json" "$TMP/none.err" || rc=$?
    assert_eq "2" "$rc" "missing adapter remains not probeable"
}

test_known_feature_flags_in_sync() {
    local declared agents registry missing stale unrecognized feature
    declared=$(grep -oE '^ENABLE_[A-Z0-9_]+' "$SCRIPT_DIR/config.sh" | sed 's/^ENABLE_//' | sort -u)
    agents=$(printf '%s\n' $KNOWN_CLI_AGENTS $KNOWN_API_AGENTS | sort -u)
    declared=$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$agents"))
    registry=$(printf '%s\n' $KNOWN_FEATURE_FLAGS | sort -u)
    missing=$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$registry") | tr '\n' ' ' | sed 's/ *$//')
    stale=$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$registry") | tr '\n' ' ' | sed 's/ *$//')

    unrecognized=""
    while IFS= read -r feature; do
        [[ -n "$feature" ]] || continue
        is_known_agent "$feature" || unrecognized+="$feature "
    done <<< "$declared"
    unrecognized="${unrecognized% }"

    assert_eq "" "$missing" "every ENABLE_* feature is excluded from custom-agent discovery"
    assert_eq "" "$stale" "feature registry contains no removed ENABLE_* values"
    assert_eq "" "$unrecognized" "is_known_agent recognizes every declared feature flag"
}

test_kimi_content_extraction() {
    local stream="$TMP/kimi-stream.jsonl"

    printf '%s\n' '{"role":"assistant","content":"{\"a\":1}"}' \
        '{"role":"meta","content":"resume hint"}' > "$stream"
    assert_eq '{"a":1}' "$(_kimi_extract_content "$stream")" \
        "assistant string content is extracted and metadata is ignored"

    printf '%s\n' '{"role":"assistant","content":[{"type":"text","text":"HELLO"}]}' > "$stream"
    assert_eq "HELLO" "$(_kimi_extract_content "$stream")" \
        "assistant block-array content is flattened"

    printf '%s\n' '{"role":"assistant","content":"first"}' \
        '{"role":"assistant","content":"LAST"}' > "$stream"
    assert_eq "LAST" "$(_kimi_extract_content "$stream")" \
        "last assistant message wins"

    printf '%s\n' '{"role":"meta","content":"only meta"}' > "$stream"
    assert_eq "" "$(_kimi_extract_content "$stream")" \
        "stream without an assistant message is empty"
}

test_response_fence_normalization() {
    local input="$TMP/fenced-input" output="$TMP/fenced-output.json" rc=0
    printf '```json\n{"response":{"summary":"fenced ok"},"confidence":{"score":8}}\n```\n' > "$input"

    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?

    assert_eq "0" "$rc" "fenced structured response succeeds"
    assert_eq "fenced ok" "$(jq -r '.response.summary' "$output")" \
        "markdown fence is removed before JSON parsing"
    assert_eq "8" "$(jq -r '.confidence.score' "$output")" \
        "fenced response preserves confidence"
    assert_eq "structured" "$(jq -r '.metadata.response_quality' "$output")" \
        "fenced response retains structured quality"

    printf '{"response":{"summary":"bare ok"},"confidence":{"score":9}}\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "0" "$rc" "bare structured response still succeeds"
    assert_eq "bare ok" "$(jq -r '.response.summary' "$output")" \
        "bare structured response remains unchanged"
    assert_eq "9" "$(jq -r '.confidence.score' "$output")" \
        "bare structured response preserves confidence"
}

run_test "Test 1: consultant error extraction" test_error_reason_extraction
run_test "Test 2: diagnosed failure rendering" test_failure_rendering
run_test "Test 3: quorum grading" test_quorum_grading
run_test "Test 4: run_query diagnostics" test_run_query_diagnostics
run_test "Test 5: consultant health probe" test_ping_consultant
run_test "Test 6: feature registry parity" test_known_feature_flags_in_sync
run_test "Test 7: Kimi stream content extraction" test_kimi_content_extraction
run_test "Test 8: fenced response normalization" test_response_fence_normalization

test_summary "common"