#!/usr/bin/env bash
# Regression tests for Grok Build CLI-first execution and API fallback.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_grok.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_grok_stub() {
    local path="$1" mode="$2"
    if [[ "$mode" == "success" ]]; then
        cat > "$path" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--tools --deny --verbatim --no-auto-update --reasoning-effort
  models  List available models
HELP
    exit 0
fi
if [[ "${1:-}" == "models" ]]; then
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * %s (default)\n' "${GROK_MODEL:-grok-4.5}"
    exit 0
fi
printf '%s\n' "$@" > "$GROK_ARGS_FILE"
[[ -z "${GROK_REQUEST_FILE:-}" ]] || : > "$GROK_REQUEST_FILE"
prompt_file=""
previous=""
for arg in "$@"; do
    if [[ "$previous" == "--prompt-file" ]]; then
        prompt_file="$arg"
        break
    fi
    previous="$arg"
done
if [[ -n "${GROK_PROMPT_CAPTURE_FILE:-}" && -n "$prompt_file" ]]; then
    cp "$prompt_file" "$GROK_PROMPT_CAPTURE_FILE"
fi
if [[ -n "${GROK_ENV_FILE:-}" ]]; then
    auth_present=false
    [[ -f "$GROK_HOME/auth.json" ]] && auth_present=true
    printf 'HOME=%s\nGROK_HOME=%s\nAUTH=%s\n' \
        "$HOME" "$GROK_HOME" "$auth_present" > "$GROK_ENV_FILE"
fi
printf '%s\n' '{"response":{"summary":"Grok CLI answered","detailed":"CLI response","approach":"CLI","pros":[],"cons":[],"caveats":[]},"confidence":{"score":9,"reasoning":"test"}}'
EOF
    elif [[ "$mode" == "auth_failure" ]]; then
        cat > "$path" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--tools --deny --verbatim --reasoning-effort
  models  List available models
HELP
    exit 0
fi
[[ "${1:-}" != "models" ]] || {
    echo "Authentication required. Run grok login." >&2
    exit 1
}
echo "Authentication required. Run grok login." >&2
exit 1
EOF
    elif [[ "$mode" == "auth_after_launch" ]]; then
        cat > "$path" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--tools --deny --verbatim --reasoning-effort
  models  List available models
HELP
    exit 0
fi
if [[ "${1:-}" == "models" ]]; then
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * %s (default)\n' "${GROK_MODEL:-grok-4.5}"
    exit 0
fi
[[ -z "${GROK_REQUEST_FILE:-}" ]] || : > "$GROK_REQUEST_FILE"
echo '401 Unauthorized after request launch' >&2
exit 42
EOF
    elif [[ "$mode" == "incompatible" ]]; then
        cat > "$path" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-incompatible}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--deny --verbatim
  models  List available models
HELP
    exit 0
fi
[[ -z "${GROK_REQUEST_FILE:-}" ]] || : > "$GROK_REQUEST_FILE"
exit 42
EOF
    else
        cat > "$path" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--tools --deny --verbatim --reasoning-effort
  models  List available models
HELP
    exit 0
fi
if [[ "${1:-}" == "models" ]]; then
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * %s (default)\n' "${GROK_MODEL:-grok-4.5}"
    exit 0
fi
[[ -z "${GROK_REQUEST_FILE:-}" ]] || : > "$GROK_REQUEST_FILE"
exit 42
EOF
    fi
    chmod +x "$path"
}

make_curl_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
if [[ -n "${CURL_CALLED_FILE:-}" ]]; then
    : > "$CURL_CALLED_FILE"
fi
out=""
headers=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -D) headers="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
cat > "$out" <<'JSON'
{"model":"grok-4.5","choices":[{"message":{"content":"{\"response\":{\"summary\":\"Grok API answered\",\"detailed\":\"API response\",\"approach\":\"API\",\"pros\":[],\"cons\":[],\"caveats\":[]},\"confidence\":{\"score\":8,\"reasoning\":\"test\"}}"}}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}
JSON
printf '200'
EOF
    chmod +x "$path"
}

test_cli_pins_model_and_headless_contract() {
    local fake_grok="$TMP_ROOT/grok-success"
    local args_file="$TMP_ROOT/cli-args"
    local prompt_capture="$TMP_ROOT/cli-prompt"
    local env_file="$TMP_ROOT/cli-env"
    local source_grok_home="$TMP_ROOT/source-grok-home"
    local output_file="$TMP_ROOT/cli-response.json"
    mkdir -p "$source_grok_home"
    printf '%s\n' '{"test":"credential"}' > "$source_grok_home/auth.json"
    make_grok_stub "$fake_grok" success

    if ! GROK_CMD="$fake_grok" \
        GROK_HOME="$source_grok_home" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_ARGS_FILE="$args_file" \
        GROK_PROMPT_CAPTURE_FILE="$prompt_capture" \
        GROK_ENV_FILE="$env_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test CLI" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Grok CLI path completes"
        return
    fi

    local args
    args=$(cat "$args_file")
    assert_match '(^|[[:space:]])--prompt-file($|[[:space:]])' "$args" "CLI reads the prompt from a file"
    assert_eq "0" "$(grep -c -x -- '-p' "$args_file" || true)" "CLI does not expose the prompt through -p argv"
    assert_match '(^|[[:space:]])grok-4\.5($|[[:space:]])' "$args" "CLI explicitly selects grok-4.5"
    assert_match '(^|[[:space:]])--no-auto-update($|[[:space:]])' "$args" "documented no-auto-update flag is used when supported"
    assert_match '(^|[[:space:]])dontAsk($|[[:space:]])' "$args" "CLI permissions fail closed"
    assert_match '(^|[[:space:]])strict($|[[:space:]])' "$args" "CLI uses the strict sandbox"
    assert_match '(^|[[:space:]])--tools($|[[:space:]])' "$args" "CLI removes all built-in tools"
    assert_match '(^|[[:space:]])MCPTool($|[[:space:]])' "$args" "CLI denies MCP tools"
    assert_match 'Test CLI' "$(cat "$prompt_capture")" "prompt-file contains the consultation"
    assert_match '^HOME=.*/ai-consultants-grok\.' "$(head -1 "$env_file")" "CLI uses an isolated HOME"
    assert_match '^GROK_HOME=.*/ai-consultants-grok\.' "$(sed -n '2p' "$env_file")" "CLI uses an isolated Grok home"
    assert_eq "AUTH=true" "$(sed -n '3p' "$env_file")" "isolated Grok home carries only the CLI credential"
    assert_eq "grok-4.5" "$(jq -r '.model' "$output_file")" "response records grok-4.5"
    assert_eq "cli" "$(jq -r '.metadata.transport' "$output_file")" "response records CLI transport"
    assert_eq "user-build-a" "$(jq -r '.metadata.cli_version' "$output_file")" "CLI version is recorded as provenance"
    assert_eq "capability-probed" "$(jq -r '.metadata.cli_compatibility' "$output_file")" "response records capability-based compatibility"
    assert_eq "capability-probed" "$(jq -r '.metadata.model_identity_source' "$output_file")" "CLI model identity comes from the inventory"
}

test_alternate_compatible_version_is_accepted() {
    local fake_grok="$TMP_ROOT/grok-alternate-version"
    local args_file="$TMP_ROOT/alternate-version-args"
    local output_file="$TMP_ROOT/alternate-version-response.json"
    make_grok_stub "$fake_grok" success

    if ! GROK_CMD="$fake_grok" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_FAKE_VERSION=user-build-b \
        GROK_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test alternate version" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "compatible alternate Grok version completes"
        return
    fi

    assert_eq "user-build-b" "$(jq -r '.metadata.cli_version' "$output_file")" "alternate version is provenance only"
    assert_eq "capability-probed" "$(jq -r '.metadata.cli_compatibility' "$output_file")" "alternate version passes the same capability gate"
}

test_incompatible_version_is_rejected_before_dispatch() {
    local fake_grok="$TMP_ROOT/grok-incompatible"
    local output_file="$TMP_ROOT/incompatible-response.json"
    local request_file="$TMP_ROOT/incompatible-request"
    make_grok_stub "$fake_grok" incompatible

    if GROK_CMD="$fake_grok" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_API_KEY="" \
        XAI_API_KEY="" \
        GROK_REQUEST_FILE="$request_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test incompatible version" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "capability-incompatible Grok CLI is rejected"
        return
    fi

    assert_eq "false" "$([[ -e "$request_file" ]] && echo true || echo false)" "incompatible CLI never starts a request"
    assert_eq "incompatible" "$(jq -r '.metadata.cli_compatibility' "$output_file")" "rejection records capability incompatibility"
}

test_post_launch_failure_does_not_fall_back() {
    local fake_bin="$TMP_ROOT/fallback-bin"
    local output_file="$TMP_ROOT/no-fallback-response.json"
    local curl_called="$TMP_ROOT/no-fallback-curl-called"
    mkdir -p "$fake_bin"
    make_grok_stub "$fake_bin/grok" failure
    make_curl_stub "$fake_bin/curl"

    if PATH="$fake_bin:$PATH" \
        GROK_CMD="$fake_bin/grok" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_API_KEY=test-key \
        CURL_CALLED_FILE="$curl_called" \
        RATE_LIMIT_DIR="$TMP_ROOT/rate-limit" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test no fallback" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "post-launch CLI failure is surfaced"
        return
    fi

    assert_eq "false" "$([[ -e "$curl_called" ]] && echo true || echo false)" "post-launch failure does not call the API"
    assert_eq "cli" "$(jq -r '.metadata.transport' "$output_file")" "failed response records the attempted CLI transport"
}

test_unavailable_cli_falls_back_to_api() {
    local fake_bin="$TMP_ROOT/unavailable-bin"
    local output_file="$TMP_ROOT/fallback-response.json"
    local curl_called="$TMP_ROOT/fallback-curl-called"
    mkdir -p "$fake_bin"
    make_grok_stub "$fake_bin/grok" auth_failure
    make_curl_stub "$fake_bin/curl"

    if ! PATH="$fake_bin:$PATH" \
        GROK_CMD="$fake_bin/grok" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_API_KEY=test-key \
        CURL_CALLED_FILE="$curl_called" \
        RATE_LIMIT_DIR="$TMP_ROOT/rate-limit" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test fallback" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "unavailable CLI falls back to API"
        return
    fi

    assert_eq "true" "$([[ -e "$curl_called" ]] && echo true || echo false)" "authentication failure calls the API fallback"
    assert_eq "Grok API answered" "$(jq -r '.response.summary' "$output_file")" "API fallback response is preserved"
    assert_eq "grok-4.5" "$(jq -r '.model' "$output_file")" "API fallback uses grok-4.5"
    assert_eq "api_fallback" "$(jq -r '.metadata.transport' "$output_file")" "response records API fallback transport"
    assert_eq "30" "$(jq -r '.metadata.tokens_used' "$output_file")" "API fallback preserves measured token usage"
    assert_eq "provider-reported" "$(jq -r '.metadata.model_identity_source' "$output_file")" "API fallback records provider-reported identity"
}

test_missing_cli_falls_back_to_api() {
    local fake_bin="$TMP_ROOT/missing-bin"
    local output_file="$TMP_ROOT/missing-response.json"
    local curl_called="$TMP_ROOT/missing-curl-called"
    mkdir -p "$fake_bin"
    make_curl_stub "$fake_bin/curl"

    if ! PATH="$fake_bin:$PATH" \
        GROK_CMD="$fake_bin/grok-not-installed" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_API_KEY=test-key \
        CURL_CALLED_FILE="$curl_called" \
        RATE_LIMIT_DIR="$TMP_ROOT/rate-limit" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test missing CLI" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "missing CLI falls back to API"
        return
    fi

    assert_eq "true" "$([[ -e "$curl_called" ]] && echo true || echo false)" "missing CLI calls the API fallback"
    assert_eq "api_fallback" "$(jq -r '.metadata.transport' "$output_file")" "missing CLI records API fallback transport"
}

test_large_context_uses_prompt_file() {
    local fake_grok="$TMP_ROOT/grok-large-context"
    local args_file="$TMP_ROOT/large-context-args"
    local prompt_capture="$TMP_ROOT/large-context-prompt"
    local context_file="$TMP_ROOT/large-context.txt"
    local output_file="$TMP_ROOT/large-context-response.json"
    make_grok_stub "$fake_grok" success
    dd if=/dev/zero bs=1024 count=1100 2>/dev/null | tr '\0' x > "$context_file"

    if ! GROK_CMD="$fake_grok" \
        GROK_USE_API=false \
        GROK_MODEL=grok-4.5 \
        GROK_ARGS_FILE="$args_file" \
        GROK_PROMPT_CAPTURE_FILE="$prompt_capture" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Large context" "$context_file" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "large context bypasses argv limits"
        return
    fi

    assert_eq "cli" "$(jq -r '.metadata.transport' "$output_file")" "large context remains on CLI transport"
    assert_eq "1" "$(grep -c 'Large context' "$prompt_capture" || true)" "large prompt reaches the CLI through prompt-file"
    assert_eq "0" "$(grep -c -x -- '-p' "$args_file" || true)" "large prompt is absent from argv"
}

test_cli_highest_reasoning_effort() {
    local fake_grok="$TMP_ROOT/grok-max-effort"
    local args_file="$TMP_ROOT/max-effort-args"
    local output_file="$TMP_ROOT/max-effort-response.json"
    make_grok_stub "$fake_grok" success

    if ! GROK_CMD="$fake_grok" GROK_USE_API=false GROK_MODEL=grok-4.6 \
        GROK_REASONING_EFFORT=xhigh GROK_ARGS_FILE="$args_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Test highest effort" "" "$output_file" >/dev/null 2>&1; then
        assert_eq success failure "Grok highest-effort CLI query completes"
        return
    fi

    assert_match '(^|[[:space:]])--reasoning-effort[[:space:]]+xhigh($|[[:space:]])' \
        "$(tr '\n' ' ' < "$args_file")" "Grok CLI receives its highest reasoning effort"
}

test_post_launch_auth_error_does_not_fall_back() {
    local fake_bin="$TMP_ROOT/post-launch-auth-bin"
    local fake_grok="$fake_bin/grok"
    local output_file="$TMP_ROOT/post-launch-auth-response.json"
    local request_file="$TMP_ROOT/post-launch-auth-request"
    local curl_called="$TMP_ROOT/post-launch-auth-curl-called"
    mkdir -p "$fake_bin"
    make_grok_stub "$fake_grok" auth_after_launch
    make_curl_stub "$fake_bin/curl"

    if PATH="$fake_bin:$PATH" GROK_CMD="$fake_grok" GROK_USE_API=false GROK_MODEL=grok-4.6 \
        GROK_REASONING_EFFORT=xhigh GROK_API_KEY=test-key XAI_API_KEY="" \
        GROK_REQUEST_FILE="$request_file" CURL_CALLED_FILE="$curl_called" \
        RATE_LIMIT_DIR="$TMP_ROOT/rate-post-launch-auth" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Auth-shaped failure after launch" "" "$output_file" >/dev/null 2>&1; then
        assert_eq failure success "post-launch auth-shaped failure is surfaced"
        return
    fi

    assert_eq true "$([[ -e "$request_file" ]] && echo true || echo false)" \
        "auth-shaped failure occurs after CLI request launch"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "post-launch auth-shaped failure cannot trigger API fallback"
    assert_eq cli "$(jq -r '.metadata.transport' "$output_file")" \
        "post-launch auth-shaped failure remains attributed to the CLI transport"
}

test_capability_incompatible_cli_with_key_does_not_fall_back() {
    local fake_bin="$TMP_ROOT/incompatible-with-key-bin"
    local output_file="$TMP_ROOT/incompatible-with-key-response.json"
    local request_file="$TMP_ROOT/incompatible-with-key-request"
    local curl_called="$TMP_ROOT/incompatible-with-key-curl-called"
    mkdir -p "$fake_bin"
    make_grok_stub "$fake_bin/grok" incompatible
    make_curl_stub "$fake_bin/curl"

    if PATH="$fake_bin:$PATH" GROK_CMD="$fake_bin/grok" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_API_KEY=test-key XAI_API_KEY="" \
        GROK_REQUEST_FILE="$request_file" CURL_CALLED_FILE="$curl_called" \
        RATE_LIMIT_DIR="$TMP_ROOT/rate-incompatible-with-key" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" "Capability mismatch" "" "$output_file" >/dev/null 2>&1; then
        assert_eq failure success "capability-incompatible CLI with key is surfaced"
        return
    fi

    assert_eq false "$([[ -e "$request_file" ]] && echo true || echo false)" \
        "capability-incompatible CLI never launches a request"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "capability-incompatible CLI cannot trigger API fallback"
    assert_eq incompatible "$(jq -r '.metadata.cli_compatibility' "$output_file")" \
        "capability mismatch remains visible on the CLI envelope"
}

run_test "Test 1: CLI headless contract and model pin" test_cli_pins_model_and_headless_contract
run_test "Test 2: alternate compatible version is accepted" test_alternate_compatible_version_is_accepted
run_test "Test 3: incompatible version is rejected before dispatch" test_incompatible_version_is_rejected_before_dispatch
run_test "Test 4: post-launch failure does not fall back" test_post_launch_failure_does_not_fall_back
run_test "Test 5: authentication-unavailable CLI falls back to xAI API" test_unavailable_cli_falls_back_to_api
run_test "Test 6: missing CLI falls back to xAI API" test_missing_cli_falls_back_to_api
run_test "Test 7: large context uses prompt-file" test_large_context_uses_prompt_file
run_test "Test 8: Grok CLI highest reasoning effort" test_cli_highest_reasoning_effort
run_test "Test 9: post-launch auth-shaped failure does not fall back" test_post_launch_auth_error_does_not_fall_back
run_test "Test 10: capability-incompatible CLI with key does not fall back" test_capability_incompatible_cli_with_key_does_not_fall_back
test_summary "query_grok"
