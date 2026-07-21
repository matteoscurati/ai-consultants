#!/bin/bash
# test_api_transport.sh - API transport resolution: format selection, request
# body construction, reasoning-effort validation.
#
# The back-compat assertions here are the gate for two shared code paths:
#   - get_api_format() resolves the wire format for all 11 consultants.
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

# Every *_FORMAT var must be unset for the back-compat block: config.sh is not
# sourced here, but a caller's environment could still carry one.
_reset_state() {
    unset QWEN3_FORMAT GLM_FORMAT GROK_FORMAT DEEPSEEK_FORMAT MINIMAX_FORMAT
    unset GEMINI_FORMAT CODEX_FORMAT CLAUDE_FORMAT MISTRAL_FORMAT CURSOR_FORMAT KIMI_FORMAT
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
    assert_eq "openai" "$(get_api_format CURSOR)"      "CURSOR (no explicit arm) -> openai"
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
    # public write-ups claiming qwen3.8-max-preview takes only low|high|xhigh.
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
    body=$(build_openai_request "hello" "qwen3.8-max-preview" 4096 "xhigh")
    assert_eq "xhigh" "$(jq -r '.reasoning_effort' <<<"$body")" "reasoning_effort present"
    assert_eq "qwen3.8-max-preview" "$(jq -r '.model' <<<"$body")" "model preserved"
    assert_eq "hello" "$(jq -r '.messages[0].content' <<<"$body")" "prompt preserved"
    assert_eq "4096"  "$(jq -r '.max_tokens' <<<"$body")" "max_tokens preserved"
    assert_eq "4" "$(jq -r '. | keys | length' <<<"$body")" "exactly one key added"
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
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -D) shift; headers="$1" ;;
    esac
    shift
done
printf '%s\n' '{"candidates":[{"content":{"parts":[{"text":"{\"response\":{\"summary\":\"ok\",\"approach\":\"API\"},\"confidence\":{\"score\":8}}"}]}}],"usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":1000}}' > "$out"
: > "$headers"
printf '200'
EOF
    chmod +x "$fake_curl"

    if ! PATH="$td:$PATH" \
        GEMINI_USE_API=true \
        GEMINI_API_KEY=test-key \
        GEMINI_API_MODEL=gemini-api-test-model \
        GEMINI_MODEL="Gemini CLI Display Model" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "test API metadata" "" "$output_file" \
        >/dev/null 2>&1; then
        rm -rf "$td"
        assert_eq "0" "1" "Gemini API-mode query completes with the stub transport"
        return
    fi

    assert_eq "gemini-api-test-model" "$(jq -r '.model' "$output_file")" \
        "Gemini API response records the API model used for billing"
    rm -rf "$td"
}

run_test "get_api_format: default mapping (back-compat gate)" test_format_defaults
run_test "build_openai_request: default body (back-compat gate)" test_openai_body_unchanged
run_test "get_api_format: \${AGENT}_FORMAT override" test_format_override
run_test "validate_reasoning_effort" test_effort_validation
run_test "build_openai_request: with reasoning_effort" test_openai_body_with_effort
run_test "Gemini API mode records API model" test_gemini_api_model_metadata

test_summary "api_transport"
