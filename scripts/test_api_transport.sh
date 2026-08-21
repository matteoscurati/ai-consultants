#!/bin/bash
# test_api_transport.sh - API transport resolution: format selection, request
# body construction, reasoning-effort validation.
#
# The back-compat assertions here are the gate for two shared code paths:
#   - get_api_format() resolves the wire format for all 10 consultants.
#   - build_openai_request() builds the body for six of them (GLM, Grok,
#     DeepSeek, MiniMax, plus Codex/Mistral in API mode).
# Both were widened to be user-configurable; the assertions that matter most
# are the ones proving the DEFAULT output did not move. They were written and
# confirmed green against the unmodified functions before either was touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
# Pin the log level BEFORE sourcing config.sh, which honors an ambient value.
# Several assertions below check that a warning was emitted, and log_warn is
# silent at LOG_LEVEL=ERROR — so an inherited level would fail this suite
# deterministically for that environment while passing everywhere else. That is
# the shape of the v2.23.0 release-gate bug, which read as flaky but was not.
export LOG_LEVEL=INFO

source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/api.sh"    >/dev/null 2>&1
source "$SCRIPT_DIR/lib/api_query.sh" >/dev/null 2>&1

# Every *_FORMAT var must be unset for the back-compat block: config.sh is not
# sourced here, but a caller's environment could still carry one.
_reset_state() {
    unset QWEN3_FORMAT GLM_FORMAT GROK_FORMAT DEEPSEEK_FORMAT MINIMAX_FORMAT
    unset GEMINI_FORMAT CODEX_FORMAT CLAUDE_FORMAT MISTRAL_FORMAT KIMI_FORMAT
}

# --- get_api_format: the default mapping must not move -----------------------

test_format_defaults() {
    assert_eq "google_ai" "$(get_api_format GEMINI)"   "GEMINI -> google_ai"
    assert_eq "anthropic" "$(get_api_format CLAUDE)"   "CLAUDE -> anthropic"
    assert_eq "qwen"      "$(get_api_format QWEN3)"    "QWEN3 -> qwen (DashScope envelope)"
    for a in CODEX MISTRAL GLM GROK DEEPSEEK MINIMAX; do
        assert_eq "openai" "$(get_api_format "$a")"    "$a -> openai"
    done
    # Unknown agents (custom API consultants) fall through to openai.
    assert_eq "openai" "$(get_api_format CUSTOM)"      "custom agent (no explicit arm) -> openai"
    assert_eq "openai" "$(get_api_format NOSUCHAGENT)" "unknown agent -> openai"
    # Case-insensitivity is relied on by run_api_mode_query, which passes the
    # display name ("Qwen3"), not the uppercase id.
    assert_eq "qwen"    "$(get_api_format Qwen3)"      "display-case name resolves"
}

# --- build_openai_request: byte-identical for the six existing consumers -----

test_openai_body_unchanged() {
    local expected
    expected=$(printf '%s\n' \
        '{' \
        '  "model": "gpt-4",' \
        '  "messages": [' \
        '    {' \
        '      "role": "user",' \
        '      "content": "hello"' \
        '    }' \
        '  ],' \
        '  "max_tokens": 4096' \
        '}')
    assert_eq "$expected" "$(build_openai_request "hello" "gpt-4")" \
        "3-arg body is byte-identical (key order and all)"

    assert_eq "$expected" "$(build_openai_request "hello" "gpt-4" 4096)" \
        "explicit default max_tokens is identical"

    # An explicitly empty 4th arg must also be a no-op: run_api_mode_query
    # passes the unset env var straight through rather than branching.
    assert_eq "$expected" "$(build_openai_request "hello" "gpt-4" 4096 "")" \
        "empty effort arg adds no key"

    assert_eq "2048" "$(build_openai_request "hi" "m" 2048 | jq -r '.max_tokens')" \
        "max_tokens still overridable"
}

test_format_override() {
    # The case this whole feature exists for: pointing Qwen at an
    # OpenAI-compatible endpoint (Qwen Cloud Token Plan) instead of DashScope.
    assert_eq "openai" "$(QWEN3_FORMAT=openai get_api_format QWEN3)" \
        "QWEN3_FORMAT=openai overrides the DashScope default"

    # Generic, not Qwen-special-cased.
    assert_eq "anthropic" "$(GLM_FORMAT=anthropic get_api_format GLM)" \
        "GLM_FORMAT is honored too"
    assert_eq "openai" "$(GEMINI_FORMAT=openai get_api_format GEMINI)" \
        "GEMINI_FORMAT is honored too"

    # A typo must degrade to the default, not to a malformed request body.
    assert_eq "qwen" "$(QWEN3_FORMAT=bogus get_api_format QWEN3 2>/dev/null)" \
        "unknown value falls back to the agent default"
    assert_match "not a known API format" \
        "$(QWEN3_FORMAT=bogus get_api_format QWEN3 2>&1 >/dev/null)" \
        "unknown value warns rather than failing silently"

    # An empty value is 'unset', not 'invalid' — .env.example ships the key
    # commented with no value, and configure may write it blank.
    assert_eq "qwen" "$(QWEN3_FORMAT='' get_api_format QWEN3 2>/dev/null)" \
        "empty value is treated as unset (no warning path)"
    assert_eq "" "$(QWEN3_FORMAT='' get_api_format QWEN3 2>&1 >/dev/null)" \
        "empty value emits no warning"

    # Setting the override to the value it already had must not warn.
    assert_eq "" "$(GLM_FORMAT=openai get_api_format GLM 2>&1 >/dev/null)" \
        "override equal to the default is silent"
}

# --- reasoning effort --------------------------------------------------------

test_effort_validation() {
    # The full enum the provider reports in its own 400, verified live against
    # the Token Plan endpoint. 'minimal' and 'medium' are in it despite the
    # public write-ups claiming qwen3.8-max takes only low|high|xhigh.
    for e in none minimal low medium high xhigh max; do
        assert_eq "$e" "$(validate_reasoning_effort "$e" Qwen3)" "accepts '$e'"
    done
    assert_eq "high"  "$(validate_reasoning_effort HIGH Qwen3)"  "normalizes case"

    # Unlike the format override, a bad effort value must FAIL rather than
    # silently fall back — quietly substituting the model's default when the
    # user asked for xhigh is the silent-no-op bug this knob must not have.
    local out
    out=$(validate_reasoning_effort higj Qwen3 2>/dev/null); local rc=$?
    assert_eq "1" "$rc"  "typo returns non-zero"
    assert_eq ""  "$out" "typo emits no value on stdout"

    validate_reasoning_effort "medium-high" Qwen3 >/dev/null 2>&1
    assert_eq "1" "$?" "compound value rejected"

    validate_reasoning_effort "" Qwen3 >/dev/null 2>&1
    assert_eq "1" "$?" "empty value rejected when explicitly validated"
}

test_openai_body_with_effort() {
    local body
    body=$(build_openai_request "hello" "qwen3.8-max" 4096 "xhigh")
    assert_eq "xhigh" "$(jq -r '.reasoning_effort' <<<"$body")" "reasoning_effort present"
    assert_eq "qwen3.8-max" "$(jq -r '.model' <<<"$body")" "model preserved"
    assert_eq "hello" "$(jq -r '.messages[0].content' <<<"$body")" "prompt preserved"
    assert_eq "4096"  "$(jq -r '.max_tokens' <<<"$body")" "max_tokens preserved"
    assert_eq "4" "$(jq -r '. | keys | length' <<<"$body")" "exactly one key added"
}

test_google_ai_body_with_thinking_level() {
    local body
    body=$(build_google_ai_request hello high)
    assert_eq high "$(jq -r '.generationConfig.thinkingConfig.thinkingLevel' <<<"$body")" \
        "Google AI request carries Gemini thinking level"
    body=$(build_google_ai_request hello)
    assert_eq false "$(jq -r 'has("thinkingConfig") or (.generationConfig | has("thinkingConfig"))' <<<"$body")" \
        "unset Gemini effort preserves the legacy request body"
}

test_gemini_api_model_metadata() {
    local td fake_curl output_file
    td=$(mktemp -d "${TMPDIR:-/tmp}/gemini_model.XXXXXX")
    fake_curl="$td/curl"
    output_file="$td/response.json"

    cat > "$fake_curl" <<'EOF'
#!/bin/bash
out=""
headers=""
body=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -D) shift; headers="$1" ;;
        -d) shift; body="$1" ;;
    esac
    shift
done
[[ -z "${REQUEST_BODY_FILE:-}" ]] || printf '%s' "$body" > "$REQUEST_BODY_FILE"
printf '%s\n' '{"candidates":[{"content":{"parts":[{"text":"{\"response\":{\"summary\":\"ok\",\"approach\":\"API\"},\"confidence\":{\"score\":8}}"}]}}],"usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":1000}}' > "$out"
: > "$headers"
printf '200'
EOF
    chmod +x "$fake_curl"

    local body_file="$td/body.json"
    if ! PATH="$td:$PATH" \
        GEMINI_USE_API=true \
        GEMINI_API_KEY=test-key \
        GEMINI_API_MODEL=gemini-api-test-model \
        GEMINI_MODEL="Gemini CLI Display Model" \
        GEMINI_REASONING_EFFORT=high \
        REQUEST_BODY_FILE="$body_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "test API metadata" "" "$output_file" \
        >/dev/null 2>&1; then
        rm -rf "$td"
        assert_eq "0" "1" "Gemini API-mode query completes with the stub transport"
        return
    fi

    assert_eq "gemini-api-test-model" "$(jq -r '.model' "$output_file")" \
        "Gemini API response records the API model used for billing"
    assert_eq "gemini-api-test-model" "$(jq -r '.metadata.requested_model' "$output_file")" \
        "Gemini API metadata records the requested model"
    assert_eq "requested-only" "$(jq -r '.metadata.model_identity_source' "$output_file")" \
        "missing provider model is labeled requested-only"
    assert_eq false "$(jq -r '.generationConfig | has("thinkingConfig")' "$body_file")" \
        "non-3.7 Gemini API model preserves the legacy request body"

    PATH="$td:$PATH" GEMINI_USE_API=true GEMINI_API_KEY=test-key \
        GEMINI_API_MODEL=gemini-3.7-flash GEMINI_REASONING_EFFORT=high \
        REQUEST_BODY_FILE="$body_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "test 3.7 thinking" "" "$output_file" >/dev/null 2>&1
    assert_eq high "$(jq -r '.generationConfig.thinkingConfig.thinkingLevel' "$body_file")" \
        "Gemini 3.7 API request transports the selected thinking level"
    rm -rf "$td"
}

test_api_provider_model_identity_and_glm_failures() {
    local td fake_curl output request request_body rc=0
    td=$(mktemp -d "${TMPDIR:-/tmp}/api_identity.XXXXXX")
    fake_curl="$td/curl"
    output="$td/output.json"
    request="$td/curl-called"
    request_body="$td/request-body.json"

    cat > "$fake_curl" <<'EOF'
#!/bin/bash
out=""; headers=""; body=""
while [[ $# -gt 0 ]]; do
    case "$1" in -o) shift; out="$1" ;; -D) shift; headers="$1" ;; -d) shift; body="$1" ;; esac
    shift
done
[[ -z "${CURL_CALLED_FILE:-}" ]] || printf 'call\n' >> "$CURL_CALLED_FILE"
[[ -z "${REQUEST_BODY_FILE:-}" ]] || printf '%s' "$body" > "$REQUEST_BODY_FILE"
: > "$headers"
case "${CURL_FAKE_MODE:-success}" in
  success)
    printf '%s\n' '{"model":"glm-5.3-202608","choices":[{"message":{"content":"{\"response\":{\"summary\":\"ok\",\"approach\":\"API\"},\"confidence\":{\"score\":8}}"}}],"usage":{"prompt_tokens":3,"completion_tokens":2}}' > "$out"
    printf 200 ;;
  invalid_model)
    printf '%s\n' '{"model":"glm*cheap","choices":[{"message":{"content":"{\"response\":{\"summary\":\"ok\",\"approach\":\"API\"},\"confidence\":{\"score\":8}}"}}],"usage":{"prompt_tokens":3,"completion_tokens":2}}' > "$out"
    printf 200 ;;
  empty) : > "$out"; printf 200 ;;
  server) printf '%s\n' '{"error":{"message":"unavailable"}}' > "$out"; printf 500 ;;
esac
EOF
    chmod +x "$fake_curl"

    if ! PATH="$td:$PATH" GLM_API_KEY=test GLM_MODEL=glm-5.3 GLM_FORMAT=openai \
        GLM_REASONING_EFFORT=max CURL_CALLED_FILE="$request" REQUEST_BODY_FILE="$request_body" \
        RATE_LIMIT_DIR="$td/rate" MAX_RETRIES=1 \
        run_api_consultant GLM test "" "$output" >/dev/null 2>&1; then
        assert_eq success failure "GLM provider-identity query completes"
    else
        assert_eq glm-5.3-202608 "$(jq -r '.model' "$output")" "provider-reported model is the top-level effective identity"
        assert_eq glm-5.3 "$(jq -r '.metadata.requested_model' "$output")" "requested GLM model is preserved"
        assert_eq provider-reported "$(jq -r '.metadata.model_identity_source' "$output")" "GLM API identity is provider-reported"
        assert_eq max "$(jq -r '.reasoning_effort' "$request_body")" "GLM max effort reaches the API request body"
    fi

    rm -f "$request_body"
    PATH="$td:$PATH" DEEPSEEK_API_KEY=test DEEPSEEK_MODEL=deepseek-v4-pro DEEPSEEK_FORMAT=openai \
        DEEPSEEK_REASONING_EFFORT=max REQUEST_BODY_FILE="$request_body" \
        RATE_LIMIT_DIR="$td/rate-deepseek" MAX_RETRIES=1 \
        run_api_consultant DeepSeek test "" "$output" >/dev/null 2>&1
    assert_eq max "$(jq -r '.reasoning_effort' "$request_body")" \
        "DeepSeek max effort reaches the API request body"
    assert_eq deepseek-v4-pro "$(jq -r '.model' "$request_body")" \
        "DeepSeek request-body assertion is non-vacuous"

    rm -f "$request_body"
    PATH="$td:$PATH" GROK_API_KEY=test GROK_MODEL=grok-4.6 GROK_FORMAT=openai \
        GROK_REASONING_EFFORT=xhigh REQUEST_BODY_FILE="$request_body" \
        RATE_LIMIT_DIR="$td/rate-grok-api" MAX_RETRIES=1 \
        run_api_consultant Grok test "" "$output" >/dev/null 2>&1
    assert_eq xhigh "$(jq -r '.reasoning_effort' "$request_body")" \
        "Grok API xhigh effort reaches the request body"
    assert_eq grok-4.6 "$(jq -r '.model' "$request_body")" \
        "Grok API effort assertion is non-vacuous"

    PATH="$td:$PATH" GLM_API_KEY=test GLM_MODEL=glm-5.3 GLM_FORMAT=openai \
        CURL_FAKE_MODE=invalid_model RATE_LIMIT_DIR="$td/rate-invalid" MAX_RETRIES=1 \
        run_api_consultant GLM test "" "$output" >/dev/null 2>&1
    assert_eq glm-5.3 "$(jq -r '.model' "$output")" "invalid provider model identifier cannot replace requested identity"
    assert_eq requested-only "$(jq -r '.metadata.model_identity_source' "$output")" "invalid provider model identifier downgrades identity evidence"

    rm -f "$request"
    rc=0
    PATH="$td:$PATH" GLM_API_KEY=test GLM_MODEL="" CURL_CALLED_FILE="$request" MAX_RETRIES=1 \
        run_api_consultant GLM test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "missing GLM model fails before dispatch"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" "missing GLM model never calls curl"

    rc=0
    PATH="$td:$PATH" GLM_API_KEY="" GLM_MODEL=glm-5.3 MAX_RETRIES=1 \
        run_api_consultant GLM test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "missing GLM auth fails closed"

    for mode in empty server; do
        rc=0
        PATH="$td:$PATH" GLM_API_KEY=test GLM_MODEL=glm-5.3 CURL_FAKE_MODE="$mode" \
            RATE_LIMIT_DIR="$td/rate-$mode" MAX_RETRIES=1 \
            run_api_consultant GLM test "" "$output" >/dev/null 2>&1 || rc=$?
        assert_eq 1 "$rc" "GLM $mode provider response fails closed"
        assert_eq error "$(jq -r '.response.approach' "$output")" "GLM $mode failure writes an error envelope"
    done

    rm -f "$request"
    rc=0
    PATH="$td:$PATH" GLM_API_KEY=test GLM_MODEL=glm-5.3 CURL_FAKE_MODE=empty \
        CURL_CALLED_FILE="$request" RATE_LIMIT_DIR="$td/rate-empty-two" \
        MAX_RETRIES=2 RETRY_DELAY_SECONDS=0 \
        run_api_consultant GLM test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "empty provider response still fails with the shipped retry count"
    assert_eq 2 "$(wc -l < "$request" | tr -d ' ')" "empty provider response consumes exactly two attempts"
    rm -rf "$td"
}

test_anthropic_thinking_blocks_and_budget() {
    local response body
    response='{"content":[{"type":"thinking","thinking":"private"},{"type":"text","text":"first"},{"type":"text","text":"second"}]}'
    assert_eq $'first\nsecond' "$(parse_anthropic_response "$response")" \
        "Anthropic parser skips thinking and joins visible text blocks"

    body=$(build_anthropic_request "hello" "claude-opus-5" 16384)
    assert_eq "16384" "$(jq -r '.max_tokens' <<<"$body")" \
        "Anthropic request accepts the larger shared thinking/output budget"
    assert_eq "16384" "$(build_anthropic_request "hello" "claude-opus-5" | jq -r '.max_tokens')" \
        "Anthropic request helper defaults to the Opus 5 budget"
}

test_anthropic_max_tokens_is_failure() {
    local td fake_curl output rc=0
    td=$(mktemp -d "${TMPDIR:-/tmp}/anthropic_truncation.XXXXXX")
    fake_curl="$td/curl"
    output="$td/output"

    printf '%s\n' \
        '#!/bin/bash' \
        'out=""' \
        'headers=""' \
        'while [[ $# -gt 0 ]]; do' \
        '  case "$1" in -o) shift; out="$1" ;; -D) shift; headers="$1" ;; esac' \
        '  shift' \
        'done' \
        'printf "%s\n" '"'"'{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"partial"}],"stop_reason":"max_tokens","usage":{"input_tokens":5,"output_tokens":16384}}'"'"' > "$out"' \
        ': > "$headers"' \
        'printf 200' > "$fake_curl"
    chmod +x "$fake_curl"

    PATH="$td:$PATH" ANTHROPIC_API_KEY=test-key CLAUDE_API_MAX_TOKENS=16384 \
        MAX_RETRIES=1 run_api_mode_query Claude claude-opus-5 test "$output" 5 \
        >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "Anthropic max_tokens stop returns failure"
    assert_eq "false" "$([[ -s "$output" ]] && echo true || echo false)" \
        "truncated Anthropic text is not published as a successful answer"

    rc=0
    PATH="$td:$PATH" ANTHROPIC_API_KEY=test-key CLAUDE_API_MAX_TOKENS=invalid \
        MAX_RETRIES=1 run_api_mode_query Claude claude-opus-5 test "$output" 5 \
        >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "invalid Anthropic token budget fails before request"
    rm -rf "$td"
}

run_test "get_api_format: default mapping (back-compat gate)" test_format_defaults
run_test "build_openai_request: default body (back-compat gate)" test_openai_body_unchanged
run_test "get_api_format: \${AGENT}_FORMAT override" test_format_override
run_test "validate_reasoning_effort" test_effort_validation
run_test "build_openai_request: with reasoning_effort" test_openai_body_with_effort
run_test "build_google_ai_request: with thinking level" test_google_ai_body_with_thinking_level
run_test "Gemini API mode records API model" test_gemini_api_model_metadata
run_test "API provider model identity and GLM failure modes" test_api_provider_model_identity_and_glm_failures
run_test "Anthropic thinking blocks and request budget" test_anthropic_thinking_blocks_and_budget
run_test "Anthropic truncation fails closed" test_anthropic_max_tokens_is_failure

test_summary "api_transport"
