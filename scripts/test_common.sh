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
    assert_eq "Timeout after 180s" \
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

test_failure_reasons_skip_warnings_and_frames() {
    local logs rc output="$TMP/warning-first-output" err_file="$TMP/warning-first.err"
    # Kimi printed a config deprecation warning before the real error; the
    # warning used to be reported as the reason.
    rc=0
    logs=$(MAX_RETRIES=1 RETRY_DELAY_SECONDS=0 run_query "Probe" "$output" 0 bash -c \
        "echo \"Warning: [loop_control] 'max_retries_per_step' is deprecated; rename it\" >&2; echo 'error: failed to run prompt: getaddrinfo ENOTFOUND auth.example' >&2; exit 1" \
        </dev/null 2>&1) || rc=$?
    assert_match 'All 1 attempts failed: error: failed to run prompt: getaddrinfo ENOTFOUND' "$logs" \
        "the error line wins over a warning printed before it"
    printf '%s\n' "$logs" > "$err_file"
    assert_eq "error: failed to run prompt: getaddrinfo ENOTFOUND auth.example" \
        "$(get_consultant_error_reason "$err_file")" "the report reason is the error, without our log prefix"

    logs=$(MAX_RETRIES=1 RETRY_DELAY_SECONDS=0 run_query "Probe" "$output" 0 bash -c \
        "echo 'Warning: option x is deprecated' >&2; exit 1" </dev/null 2>&1) || true
    assert_match 'All 1 attempts failed: no error message \(stderr only said: Warning: option x is deprecated\)' "$logs" \
        "a warning alone is not presented as the cause"

    assert_eq "Failed to start: listen tcp 127.0.0.1:0: bind: operation not permitted" \
        "$(printf '%s\n' 'error starting server' '  | google3/third_party/jetski/server.go:1777' \
            'Wraps: (4) operation not permitted' 'Error types: (1) *withstack.withStack' \
            '    third_party/go/src/runtime/asm_arm64.s:1039' \
            'Failed to start: listen tcp 127.0.0.1:0: bind: operation not permitted' | pick_error_line)" \
        "Go stack details are skipped for the final cause"
    assert_eq "TypeError: fetch failed" \
        "$(printf '%s\n' 'TypeError: fetch failed' '    at node:internal/deps/undici:13510:13' '    at async runError (file:///cli.js:1:1)' | pick_error_line)" \
        "JavaScript stack frames are skipped"
    assert_eq "" "$(printf '%s\n' 'Warning: something is deprecated' | pick_error_line)" \
        "only warnings yield no cause"

    assert_eq "could not resolve the host (DNS)" "$(describe_curl_exit 6)" "curl exit 6 is described"
    assert_eq "curl exit 99" "$(describe_curl_exit 99)" "unknown curl exits keep the number"

    assert_match "network error" "$(diagnosed_failures_network_hint \
        'Gemini|Antigravity model inventory failed: Failed to start: listen tcp 127.0.0.1:0: bind: operation not permitted' \
        'Kimi|error: getaddrinfo ENOTFOUND auth.kimi.com' \
        'Mistral|network error: could not resolve the host (DNS) (curl exit 6)' \
        'Codex|stopped by the host after 9s, before it answered')" "all-network failures get the sandbox hint"
    assert_eq "" "$(diagnosed_failures_network_hint 'Kimi|error: getaddrinfo ENOTFOUND auth.kimi.com' 'GLM|Client error (HTTP 401)')" \
        "a non-network failure suppresses the hint"
    assert_eq "" "$(diagnosed_failures_network_hint 'Codex|stopped by the host after 9s')" \
        "stopped consultants alone get no hint"
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

    # Observed live with GLM 5.3 Flash: confidence nested inside response.
    printf '{"response":{"summary":"nested ok","pros":["p"],"confidence":{"score":9,"reasoning":"r"}}}\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "0" "$rc" "nested confidence is accepted"
    assert_eq "9|null|structured" \
        "$(jq -r '"\(.confidence.score)|\(.response.confidence)|\(.metadata.response_quality)"' "$output")" \
        "nested confidence is lifted to the top level"

    # Observed live with GLM 5.3 Flash: "confidence" opened inside "response"
    # and the outer object left one brace short.
    printf '{"response":{"summary":"short ok","pros":["p"],"confidence":{"score":8,"reasoning":"r"}}\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "0|8" "$rc|$(jq -r '.confidence.score' "$output")" \
        "one-brace-short nested confidence is repaired and lifted"

    # A genuinely truncated answer is not "repaired".
    printf '{"response":{"summary":"cut mid-str\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "a truncated answer still fails closed"

    # Models usually pretty-print: a truncated multi-line answer must fail
    # closed too, not pass as fallback prose.
    printf '{\n  "response": {\n    "summary": "cut",\n    "detailed": "mid-str\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "1|error" "$rc|$(jq -r '.metadata.response_quality' "$output")" \
        "a truncated multi-line answer still fails closed"

    # A response without any confidence object stays schema-invalid.
    printf '{"response":{"summary":"no confidence"}}\n' > "$input"
    rc=0
    process_consultant_response "TestC" "test-model" "Tester" \
        "$input" "$output" 0 100 >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "missing confidence still fails closed"
}

test_detailed_summary_rejects_invalid_gates() {
    local rc=0
    ( checked=0; failed=0; skipped=0; test_summary_detailed "empty" 0 >/dev/null ) || rc=$?
    assert_eq "1" "$rc" "detailed summary rejects a suite with no assertions"

    rc=0
    ( checked=1; failed=1; skipped=0; test_summary_detailed "failed" 0 >/dev/null ) || rc=$?
    assert_eq "1" "$rc" "detailed summary rejects a suite with failed assertions"
}

# A timeout of 0 means no limit; a positive value still enforces one.
test_timeouts_and_process_tree() {
    local out rc
    out=$(run_with_timeout 0 bash -c 'sleep 1.2; printf ok')
    assert_eq ok "$out" "timeout 0 runs the command with no limit"
    rc=0; run_with_timeout 1 sleep 5 || rc=$?
    assert_eq 124 "$rc" "a positive timeout still stops the command"
    assert_eq none "$(format_timeout_label 0)" "0 is logged as no timeout"
    assert_eq 90s "$(format_timeout_label 90)" "a limit is logged in seconds"

    # The adapter shell, its child and the grandchild sleep all stop.
    local pid_file parent p alive=0
    pid_file=$(mktemp "${TMPDIR:-/tmp}/ai_consultants_tree.XXXXXX")
    bash -c 'bash -c "sleep 300 & echo \$! >> \"$1\"; wait" _ "$1" & echo $! >> "$1"; wait' _ "$pid_file" &
    parent=$!
    local tries=0
    while [[ $(wc -l < "$pid_file" 2>/dev/null || echo 0) -lt 2 && $tries -lt 50 ]]; do
        sleep 0.1; tries=$((tries + 1))
    done
    kill_process_tree "$parent"
    wait "$parent" 2>/dev/null || true
    for p in $parent $(cat "$pid_file"); do
        kill -0 "$p" 2>/dev/null && alive=$((alive + 1))
    done
    assert_eq 3 "$(( $(wc -l < "$pid_file") + 1 ))" "the fixture started a child and a grandchild"
    assert_eq 0 "$alive" "kill_process_tree stops every descendant"
    rm -f "$pid_file"
}

run_test "Test 1: consultant error extraction" test_error_reason_extraction
run_test "Test 2: diagnosed failure rendering" test_failure_rendering
run_test "Test 3: quorum grading" test_quorum_grading
run_test "Test 4: run_query diagnostics" test_run_query_diagnostics
run_test "Test 5: consultant health probe" test_ping_consultant
run_test "Test 6: feature registry parity" test_known_feature_flags_in_sync
run_test "Test 7: Kimi stream content extraction" test_kimi_content_extraction
# Documented persona overrides: custom text and display name must win over
# the catalog default; an explicit persona ID wins over both.
test_persona_overrides_are_reachable() {
    local out
    out=$(AI_CONSULTANTS_CONFIG_DIR="$TMP/empty" GEMINI_PERSONA="CUSTOM_PERSONA_TEXT" \
        GEMINI_PERSONA_NAME="Custom Name" bash -c '
        source "$1/lib/common.sh" >/dev/null 2>&1; source "$1/lib/personas.sh"
        printf "%s|%s|%s" "$(get_persona Gemini)" "$(get_persona_name Gemini)" "$(GEMINI_PERSONA_ID=3 get_persona_name Gemini)"' _ "$SCRIPT_DIR")
    assert_eq "CUSTOM_PERSONA_TEXT|Custom Name|The Devil's Advocate" "$out" \
        "custom persona text/name apply and an explicit ID wins"
}

# cost-capped lowers only the stock budget; an explicit cap is kept.
test_cost_capped_keeps_explicit_budget() {
    local out
    out=$(AI_CONSULTANTS_CONFIG_DIR="$TMP/empty" bash -c '
        source "$1/config.sh" >/dev/null 2>&1
        MAX_SESSION_COST=1.00; apply_preset cost-capped >/dev/null 2>&1; a=$MAX_SESSION_COST
        MAX_SESSION_COST=0.50; apply_preset cost-capped >/dev/null 2>&1; b=$MAX_SESSION_COST
        printf "%s|%s" "$a" "$b"' _ "$SCRIPT_DIR")
    assert_eq "0.10|0.50" "$out" "cost-capped lowers the default cap but keeps an explicit one"
}

# Every consultant answer goes through lib/response_canonicalize.jq. Each row:
# <expected rc> @@ <jq check on the normalized output> @@ <raw provider text>
test_response_canonicalization_matrix() {
    local rows="$TMP/canonical-rows" row expected check raw out rc
    # A plain heredoc (not inside $(...)): one row deliberately contains an
    # unbalanced quote, which bash cannot parse inside a command substitution.
    cat > "$rows" <<'ROWS'
0@@.confidence.score == 8 and .response.approach == "unspecified" and .response.detailed == ""@@{"response":{"summary":"minimal"},"confidence":{"score":8}}
0@@.response.summary == "flat" and .confidence.score == 7@@{"summary":"flat","detailed":"d","approach":"a","confidence":{"score":7,"reasoning":"r"}}
0@@.response.summary == "wrapped" and .confidence.score == 6@@{"answer":{"response":{"summary":"wrapped"},"confidence":{"score":6}}}
0@@.confidence.score == 9 and .confidence.reasoning == ""@@{"response":{"summary":"bare score"},"confidence":9}
0@@.confidence.score == 8@@{"response":{"summary":"string score"},"confidence":{"score":"8/10"}}
0@@.confidence.score == 8@@{"response":{"summary":"fraction"},"confidence":{"score":0.8}}
0@@.confidence.score == 1@@{"response":{"summary":"tiny fraction"},"confidence":{"score":0.04}}
0@@.confidence.score == 8@@{"response":{"summary":"word"},"confidence":{"score":"High"}}
2@@true@@{"response":{"summary":"unusable score"},"confidence":{"score":"sure"}}
0@@.confidence.score == 9@@{"response":{"summary":"percent"},"confidence":{"score":85}}
0@@.response.pros == ["one"] and .response.cons == ["2"]@@{"response":{"summary":"lists","pros":"one","cons":[2,null,""]},"confidence":{"score":7}}
2@@true@@{"response":{"detailed":"only detailed text"},"confidence":{"score":7}}
1@@true@@{"response":"as string","confidence":{"score":7}}
0@@.response.summary == "in prose"@@Here is my analysis: {"response":{"summary":"in prose"},"confidence":{"score":7}} Hope it helps.
0@@.response.summary == "inline fence"@@Sure! ```json {"response":{"summary":"inline fence"},"confidence":{"score":7}} ```
0@@.confidence.score == 8 and (.response | has("confidence") | not)@@{"response":{"summary":"nested","confidence":{"score":8,"reasoning":"r"}}}
2@@true@@{"response":{"summary":"no confidence at all"}}
2@@true@@{"response":{"summary":"cut mid-str
2@@true@@{"unrelated":"object"}
2@@true@@{"response":{"summary":"one"},"confidence":{"score":8}} {"response":{"summary":"two"},"confidence":{"score":9}}
1@@true@@Use a config file such as {"timeout": 30} instead of flags.
1@@true@@Plain prose answer without any JSON.
ROWS
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        expected="${row%%@@*}"; row="${row#*@@}"
        check="${row%%@@*}"; raw="${row#*@@}"
        rc=0
        out=$(normalize_consultant_response_text "$raw") || rc=$?
        assert_eq "$expected" "$rc" "canonicalization rc for: ${raw:0:50}"
        if [[ "$expected" == 0 ]]; then
            assert_eq true "$(printf '%s' "$out" | jq -r "$check" 2>/dev/null)" \
                "canonical output satisfies: $check"
        fi
    done < "$rows"
}

# Every envelope shape the builders and the normalizer can write must conform
# to scripts/lib/schema.json; the checker must also reject a broken envelope.
test_envelopes_conform_to_schema() {
    local input="$TMP/schema-input" out="$TMP/schema-out.json" rc
    printf '%s\n' '{"summary":"flat","pros":"one","confidence":{"score":"8/10"}}' > "$input"
    process_consultant_response "Gemini" "m" "The Architect" "$input" "$out" 0 5 "" "prompt" >/dev/null 2>&1
    assert_schema_valid "$out" "" "structured envelope conforms to the schema"

    printf '%s\n' 'Plain prose answer.' > "$input"
    process_consultant_response "Gemini" "m" "The Architect" "$input" "$out" 0 5 "" "prompt" >/dev/null 2>&1
    assert_schema_valid "$out" "" "fallback envelope conforms to the schema"

    printf '%s\n' '{"response":{"summary":"cut' > "$input"
    rc=0
    process_consultant_response "Gemini" "m" "The Architect" "$input" "$out" 0 5 "" "prompt" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "malformed answer is rejected"
    assert_schema_valid "$out" "" "error envelope (with raw_excerpt) conforms to the schema"

    process_consultant_response "Gemini" "m" "The Architect" "$TMP/missing-output" "$out" 7 5 >/dev/null 2>&1 || true
    assert_schema_valid "$out" "" "failed-query envelope conforms to the schema"

    jq '.cache_metadata = {cached_at: "t", fingerprint: "f", from_cache: true}' "$out" > "$TMP/cached.json"
    assert_schema_valid "$TMP/cached.json" "" "cached envelope conforms to the schema"

    jq 'del(.response) | .confidence.score = 11' "$out" > "$TMP/broken.json"
    local errors
    errors=$(jq -n --slurpfile schema "$SCRIPT_DIR/lib/schema.json" --slurpfile doc "$TMP/broken.json" \
        -f "$SCRIPT_DIR/lib/json_schema_check.jq" | jq -r 'join(";")')
    assert_match "missing required response" "$errors" "schema checker reports a missing required field"
    assert_match "11 > maximum 10" "$errors" "schema checker reports an out-of-range score"

    # A mistyped definition must fail the check, not validate vacuously.
    errors=$(jq -n --slurpfile schema "$SCRIPT_DIR/lib/schema.json" --slurpfile doc "$out" \
        --arg definition synthesis_artifcat -f "$SCRIPT_DIR/lib/json_schema_check.jq" | jq -r 'join(";")')
    assert_match "unknown schema definition: synthesis_artifcat" "$errors" \
        "schema checker rejects an unknown definition"
}

# SECURITY is matched first, so design-pattern and testing terms must not
# trip it: dependency/constructor/field injection is not an injection attack.
test_pattern_classifier_security_boundary() {
    local expected question actual
    while IFS='|' read -r expected question; do
        actual=$(printf '%s' "$question" | AI_CONSULTANTS_CONFIG_DIR="$TMP/empty" CLASSIFICATION_MODE=pattern \
            "$SCRIPT_DIR/classify_question.sh" - 2>/dev/null)
        if [[ "$expected" == SECURITY ]]; then
            assert_eq SECURITY "$actual" "SECURITY: $question"
        else
            assert_ne SECURITY "$actual" "not SECURITY: $question"
        fi
    done <<'ROWS'
SECURITY|Fix the SQL injection in this query
SECURITY|Is our dependency injection container secure against tampering?
OTHER|How do I set up dependency injection in NestJS?
OTHER|Should I prefer constructor injection or field injection?
OTHER|How many tokens per second can this model generate?
ROWS
}

# Pre-run estimates price the models the run will use (tier + transport).
test_estimate_uses_configured_models() {
    local out
    out=$(AI_CONSULTANTS_CONFIG_DIR="$TMP/empty" bash -c '
        source "$1/lib/common.sh" >/dev/null 2>&1; source "$1/lib/costs.sh"
        premium=$(estimate_consultation_cost 2 40000 Gemini,Codex)
        apply_preset fast >/dev/null 2>&1
        economy=$(estimate_consultation_cost 2 40000 Gemini,Codex)
        echo "$(echo "$economy < $premium" | bc)"' _ "$SCRIPT_DIR")
    assert_eq 1 "$out" "an economy preset lowers the pre-run estimate"
}

run_test "Test 8: fenced response normalization" test_response_fence_normalization
run_test "Test 9: detailed summary guard" test_detailed_summary_rejects_invalid_gates
run_test "Test 10: persona overrides are reachable" test_persona_overrides_are_reachable
run_test "Test 11: cost-capped keeps an explicit budget" test_cost_capped_keeps_explicit_budget
run_test "Test 12: response canonicalization matrix" test_response_canonicalization_matrix
run_test "Test 13: envelopes conform to the schema" test_envelopes_conform_to_schema
run_test "Test 14: estimates use configured models" test_estimate_uses_configured_models
run_test "Test 15: no-limit timeouts and process-tree stop" test_timeouts_and_process_tree
run_test "Test 16: pattern classifier security boundary" test_pattern_classifier_security_boundary
run_test "Test 17: failure reasons skip warnings and stack frames" test_failure_reasons_skip_warnings_and_frames

test_summary "common"