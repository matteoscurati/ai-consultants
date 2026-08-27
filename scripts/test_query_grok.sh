#!/usr/bin/env bash
# Regression tests for Grok Build CLI-first execution and API fallback.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/grok_oauth.sh
source "$SCRIPT_DIR/lib/grok_oauth.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_grok.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export XDG_DATA_HOME="$TMP_ROOT/xdg-data"
export _AI_CONSULTANTS_XDG_DATA="$XDG_DATA_HOME/ai-consultants"
export GROK_HOME="$TMP_ROOT/default-grok-home"
mkdir -p "$GROK_HOME"

write_oauth() {
    local path="$1" access="$2" refresh="$3"
    jq -n --arg access "$access" --arg refresh "$refresh" '
        {"https://auth.x.ai::test":{
          key:$access,refresh_token:$refresh,
          expires_at:"2099-01-01T00:00:00Z"}}
    ' > "$path"
    chmod 600 "$path"
}

write_oauth "$GROK_HOME/auth.json" default-access default-refresh

make_grok_stub() {
    local path="$1" mode="$2"
    if [[ "$mode" == "success" ]]; then
        cat > "$path" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
    printf 'grok %s\n' "${GROK_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    if [[ -n "${GROK_FAKE_CAPABILITY_GUARD_DIR:-}" ]]; then
        mkdir -p "$GROK_FAKE_CAPABILITY_GUARD_DIR"
        if ! mkdir "$GROK_FAKE_CAPABILITY_GUARD_DIR/running" 2>/dev/null; then
            printf 'concurrent capability initialization failed\n' >&2
            exit 1
        fi
        sleep 0.1
        rmdir "$GROK_FAKE_CAPABILITY_GUARD_DIR/running"
    fi
    cat <<'HELP'
--prompt-file --model --cwd --output-format --no-plan --no-subagents
--no-memory --disable-web-search --max-turns --permission-mode --sandbox
--tools --deny --verbatim --no-auto-update --reasoning-effort
  models  List available models
HELP
    exit 0
fi
if [[ "${1:-}" == "models" ]]; then
    if [[ -n "${GROK_FAKE_INIT_GUARD_DIR:-}" && ! -e "$GROK_FAKE_INIT_GUARD_DIR/ready" ]]; then
        mkdir -p "$GROK_FAKE_INIT_GUARD_DIR"
        if ! mkdir "$GROK_FAKE_INIT_GUARD_DIR/initializing" 2>/dev/null; then
            printf 'Authentication unavailable during concurrent home initialization\n' >&2
            exit 1
        fi
        sleep 0.2
        : > "$GROK_FAKE_INIT_GUARD_DIR/ready"
        rmdir "$GROK_FAKE_INIT_GUARD_DIR/initializing"
    fi
    if [[ -n "${GROK_FAKE_PROBE_GUARD_DIR:-}" ]]; then
        mkdir -p "$GROK_FAKE_PROBE_GUARD_DIR"
        if ! mkdir "$GROK_FAKE_PROBE_GUARD_DIR/running" 2>/dev/null; then
            printf 'Authentication unavailable during concurrent inventory probe\n' >&2
            exit 1
        fi
        sleep 0.1
        rmdir "$GROK_FAKE_PROBE_GUARD_DIR/running"
    fi
    printf 'You are logged in with grok.com.\n\nAvailable models:\n  * %s (default)\n' "${GROK_MODEL:-grok-4.5}"
    exit 0
fi
if [[ -n "${GROK_ARGS_FILE:-}" ]]; then
    printf '%s\n' "$@" > "$GROK_ARGS_FILE"
fi
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
prompt_text=""
[[ -z "$prompt_file" ]] || prompt_text=$(<"$prompt_file")
case "$prompt_text" in
    *WAIT_FOR_PEER_A*|*WAIT_FOR_PEER_B*)
        sync_dir="${GROK_FAKE_SYNC_DIR:?sync directory required}"
        mkdir -p "$sync_dir"
        if [[ "$prompt_text" == *WAIT_FOR_PEER_A* ]]; then
            own=peer-a; peer=peer-b
        else
            own=peer-b; peer=peer-a
        fi
        : > "$sync_dir/$own"
        for _ in $(seq 1 100); do
            [[ -e "$sync_dir/$peer" ]] && break
            sleep 0.02
        done
        [[ -e "$sync_dir/$peer" ]] || exit 92
        ;;
    *ROTATE_OAUTH*)
        jq -n '{"https://auth.x.ai::test":{key:"rotated-access",refresh_token:"rotated-refresh",expires_at:"2099-02-01T00:00:00Z"}}' > "$GROK_HOME/auth.json"
        ;;
    *REQUIRE_ROTATED_OAUTH*)
        jq -e '.[].key == "rotated-access" and .[].refresh_token == "rotated-refresh"' "$GROK_HOME/auth.json" >/dev/null
        ;;
    *CONCURRENT_LOGIN*)
        jq -n '{"https://auth.x.ai::test":{key:"isolated-access",refresh_token:"isolated-refresh",expires_at:"2099-02-01T00:00:00Z"}}' > "$GROK_HOME/auth.json"
        jq -n '{"https://auth.x.ai::test":{key:"external-access",refresh_token:"external-refresh",expires_at:"2099-03-01T00:00:00Z"}}' > "${GROK_FAKE_AMBIENT_AUTH:?ambient auth required}"
        ;;
    *REQUIRE_EXTERNAL_OAUTH*)
        jq -e '.[].key == "external-access" and .[].refresh_token == "external-refresh"' "$GROK_HOME/auth.json" >/dev/null
        ;;
    *CORRUPT_OAUTH*)
        printf '{}\n' > "$GROK_HOME/auth.json"
        ;;
    *LEAK_TOKEN*)
        printf 'provider failure access=%s refresh=%s\n' \
            "${GROK_FAKE_ACCESS_TOKEN:?}" "${GROK_FAKE_REFRESH_TOKEN:?}" >&2
        exit 42
        ;;
esac
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
    write_oauth "$source_grok_home/auth.json" source-access source-refresh
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
    assert_match '(^|[[:space:]])--max-turns[[:space:]]+4($|[[:space:]])' "$args" "CLI receives the smoke-tested advisory turn budget"
    assert_match '(^|[[:space:]])--tools($|[[:space:]])' "$args" "CLI removes all built-in tools"
    assert_match '(^|[[:space:]])MCPTool($|[[:space:]])' "$args" "CLI denies MCP tools"
    assert_match 'Test CLI' "$(cat "$prompt_capture")" "prompt-file contains the consultation"
    assert_match '^HOME=.*/ai-consultants-grok\.' "$(head -1 "$env_file")" "CLI uses an isolated HOME"
    assert_match '^GROK_HOME=.*/ai-consultants/grok-shared-oauth/gen-' "$(sed -n '2p' "$env_file")" "CLI uses the shared runner-owned Grok home"
    assert_eq "AUTH=true" "$(sed -n '3p' "$env_file")" "shared Grok home carries the CLI credential"
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

test_shared_oauth_allows_concurrent_dispatch() {
    local fake_grok="$TMP_ROOT/grok-shared-concurrent"
    local source_home="$TMP_ROOT/shared-concurrent-home"
    local sync_dir="$TMP_ROOT/shared-concurrent-sync"
    local init_guard="$TMP_ROOT/shared-concurrent-init"
    local probe_guard="$TMP_ROOT/shared-concurrent-probe"
    local capability_guard="$TMP_ROOT/shared-concurrent-capability"
    local output_a="$TMP_ROOT/shared-concurrent-a.json" output_b="$TMP_ROOT/shared-concurrent-b.json"
    local env_a="$TMP_ROOT/shared-concurrent-a.env" env_b="$TMP_ROOT/shared-concurrent-b.env"
    local rc_a=0 rc_b=0 pid_a pid_b home_a home_b grok_home_a grok_home_b
    mkdir -p "$source_home" "$sync_dir"
    write_oauth "$source_home/auth.json" concurrent-access concurrent-refresh
    make_grok_stub "$fake_grok" success

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-a.args" \
        GROK_ENV_FILE="$env_a" GROK_FAKE_SYNC_DIR="$sync_dir" \
        GROK_FAKE_INIT_GUARD_DIR="$init_guard" \
        GROK_FAKE_PROBE_GUARD_DIR="$probe_guard" \
        GROK_FAKE_CAPABILITY_GUARD_DIR="$capability_guard" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" WAIT_FOR_PEER_A "" "$output_a" \
        >"$TMP_ROOT/shared-a.stdout" 2>"$TMP_ROOT/shared-a.stderr" &
    pid_a=$!
    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-b.args" \
        GROK_ENV_FILE="$env_b" GROK_FAKE_SYNC_DIR="$sync_dir" \
        GROK_FAKE_INIT_GUARD_DIR="$init_guard" \
        GROK_FAKE_PROBE_GUARD_DIR="$probe_guard" \
        GROK_FAKE_CAPABILITY_GUARD_DIR="$capability_guard" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" WAIT_FOR_PEER_B "" "$output_b" \
        >"$TMP_ROOT/shared-b.stdout" 2>"$TMP_ROOT/shared-b.stderr" &
    pid_b=$!
    wait "$pid_a" || rc_a=$?
    wait "$pid_b" || rc_b=$?

    assert_eq 0 "$rc_a" "concurrent shared Grok run A completes"
    assert_eq 0 "$rc_b" "concurrent shared Grok run B completes"
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$output_a")" \
        "concurrent shared Grok run A publishes its response"
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$output_b")" \
        "concurrent shared Grok run B publishes its response"
    home_a=$(sed -n '1s/^HOME=//p' "$env_a")
    home_b=$(sed -n '1s/^HOME=//p' "$env_b")
    grok_home_a=$(sed -n '2s/^GROK_HOME=//p' "$env_a")
    grok_home_b=$(sed -n '2s/^GROK_HOME=//p' "$env_b")
    assert_eq false "$([[ "$home_a" == "$home_b" ]] && echo true || echo false)" \
        "concurrent Grok runs keep distinct HOME directories"
    assert_eq "$grok_home_a" "$grok_home_b" \
        "concurrent Grok runs share only the runner-owned GROK_HOME"
    assert_eq true "$([[ -f "$grok_home_a/.ai-consultants-ready.json" ]] && echo true || echo false)" \
        "new shared Grok home is bootstrapped once before concurrent dispatch"
}

test_shared_oauth_rotation_is_published_and_reused() {
    local fake_grok="$TMP_ROOT/grok-shared-rotation"
    local source_home="$TMP_ROOT/shared-rotation-home"
    local first="$TMP_ROOT/shared-rotation-first.json" second="$TMP_ROOT/shared-rotation-second.json"
    local marker generation shared_root
    mkdir -p "$source_home"
    write_oauth "$source_home/auth.json" initial-access initial-refresh
    make_grok_stub "$fake_grok" success

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-rotation.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" ROTATE_OAUTH "" "$first" >/dev/null 2>&1
    assert_eq rotated-access "$(jq -r '.[].key' "$source_home/auth.json")" \
        "shared OAuth rotation is published to the ambient session"
    shared_root="$XDG_DATA_HOME/ai-consultants/grok-shared-oauth"
    marker="$shared_root/sync-marker.json"
    generation=$(jq -r '.generation' "$marker")
    assert_eq rotated-access "$(jq -r '.[].key' "$shared_root/$generation/auth.json")" \
        "shared generation retains the rotated credential"

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-rotation-next.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" REQUIRE_ROTATED_OAUTH "" "$second" >/dev/null 2>&1
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$second")" \
        "the next shared run reuses the rotated OAuth generation"
}

test_external_login_wins_shared_oauth_cas() {
    local fake_bin="$TMP_ROOT/shared-login-bin"
    local fake_grok="$fake_bin/grok"
    local source_home="$TMP_ROOT/shared-login-home" output="$TMP_ROOT/shared-login.json"
    local next="$TMP_ROOT/shared-login-next.json" curl_called="$TMP_ROOT/shared-login-curl" rc=0
    mkdir -p "$fake_bin" "$source_home"
    write_oauth "$source_home/auth.json" login-initial login-initial-refresh
    make_grok_stub "$fake_grok" success
    make_curl_stub "$fake_bin/curl"

    PATH="$fake_bin:$PATH" GROK_CMD="$fake_grok" GROK_HOME="$source_home" \
        GROK_USE_API=false GROK_MODEL=grok-4.6 GROK_API_KEY=test-key \
        CURL_CALLED_FILE="$curl_called" GROK_ARGS_FILE="$TMP_ROOT/shared-login.args" \
        GROK_FAKE_AMBIENT_AUTH="$source_home/auth.json" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" CONCURRENT_LOGIN "" "$output" \
        >"$TMP_ROOT/shared-login.stdout" 2>"$TMP_ROOT/shared-login.stderr" || rc=$?
    assert_eq 75 "$rc" "external Grok login makes the involved run fail temporarily"
    assert_eq external-access "$(jq -r '.[].key' "$source_home/auth.json")" \
        "external Grok login wins the OAuth CAS"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "OAuth CAS conflict never triggers API fallback"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "OAuth CAS conflict publishes only a sanitized error envelope"

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-login-next.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" REQUIRE_EXTERNAL_OAUTH "" "$next" >/dev/null 2>&1
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$next")" \
        "the next run adopts the external login as a fresh generation"
}

test_corrupt_refresh_never_replaces_ambient_oauth() {
    local fake_grok="$TMP_ROOT/grok-shared-corrupt"
    local source_home="$TMP_ROOT/shared-corrupt-home"
    local output="$TMP_ROOT/shared-corrupt.json" healed="$TMP_ROOT/shared-corrupt-healed.json"
    local before="$TMP_ROOT/shared-corrupt-before.json" rc=0
    mkdir -p "$source_home"
    write_oauth "$source_home/auth.json" safe-access safe-refresh
    cp "$source_home/auth.json" "$before"
    make_grok_stub "$fake_grok" success

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-corrupt.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" CORRUPT_OAUTH "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 70 "$rc" "malformed refreshed OAuth fails closed"
    assert_eq true "$(cmp -s "$before" "$source_home/auth.json" && echo true || echo false)" \
        "malformed refreshed OAuth never replaces the ambient credential"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "malformed refreshed OAuth publishes no successful consultant response"

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/shared-corrupt-heal.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" healed "" "$healed" >/dev/null 2>&1
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$healed")" \
        "a later run heals by reseeding from the valid ambient credential"
}

test_dead_runner_lock_is_recovered() {
    local fake_grok="$TMP_ROOT/grok-dead-lock"
    local source_home="$TMP_ROOT/dead-lock-home" output="$TMP_ROOT/dead-lock.json"
    local lock_dir
    mkdir -p "$source_home"
    write_oauth "$source_home/auth.json" lock-access lock-refresh
    lock_dir="$source_home/.ai-consultants-oauth.lock.d"
    mkdir "$lock_dir"
    printf '999999\n' > "$lock_dir/owner"
    make_grok_stub "$fake_grok" success

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/dead-lock.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" recover "" "$output" >/dev/null 2>&1
    assert_eq "Grok CLI answered" "$(jq -r '.response.summary' "$output")" \
        "a dead runner lock does not block the next invocation"
    assert_eq false "$([[ -e "$lock_dir" ]] && echo true || echo false)" \
        "dead runner lock is removed after recovery"
}

test_shared_configuration_is_reconciled_atomically() {
    local fake_grok="$TMP_ROOT/grok-config-reconcile"
    local source_home="$TMP_ROOT/config-reconcile-home" output="$TMP_ROOT/config-reconcile.json"
    local next="$TMP_ROOT/config-reconcile-next.json" shared_root generation config
    mkdir -p "$source_home"
    write_oauth "$source_home/auth.json" config-access config-refresh
    make_grok_stub "$fake_grok" success
    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/config-reconcile.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" initial "" "$output" >/dev/null 2>&1
    shared_root="$XDG_DATA_HOME/ai-consultants/grok-shared-oauth"
    generation=$(jq -r '.generation' "$shared_root/sync-marker.json")
    config="$shared_root/$generation/config.toml"
    printf '%s\n' 'hooks = ["stale-hook"]' > "$config"

    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_MODEL=grok-4.6 GROK_ARGS_FILE="$TMP_ROOT/config-reconcile-next.args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" reconcile "" "$next" >/dev/null 2>&1
    assert_eq 0 "$(grep -c 'stale-hook' "$config" || true)" \
        "shared Grok configuration is reconciled after a runner upgrade"
    assert_eq 1 "$(grep -c '^enabled = false$' "$config")" \
        "reconciled shared Grok configuration disables workflows"
    assert_eq 0 "$(find "$shared_root/$generation" -maxdepth 1 -name '.config.toml.ai-consultants.*' | wc -l | tr -d ' ')" \
        "atomic config reconciliation leaves no candidate file"
}

test_tokens_never_leave_credential_files() {
    local fake_bin="$TMP_ROOT/token-leak-bin"
    local fake_grok="$fake_bin/grok"
    local source_home="$TMP_ROOT/token-leak-home" output="$TMP_ROOT/token-leak.json"
    local stdout="$TMP_ROOT/token-leak.stdout" stderr="$TMP_ROOT/token-leak.stderr"
    local args="$TMP_ROOT/token-leak.args" curl_called="$TMP_ROOT/token-leak-curl" rc=0
    local access='super-secret-access-token' refresh='super-secret-refresh-token'
    mkdir -p "$fake_bin" "$source_home"
    write_oauth "$source_home/auth.json" "$access" "$refresh"
    make_grok_stub "$fake_grok" success
    make_curl_stub "$fake_bin/curl"

    PATH="$fake_bin:$PATH" GROK_CMD="$fake_grok" GROK_HOME="$source_home" \
        GROK_USE_API=false GROK_MODEL=grok-4.6 GROK_API_KEY=test-key \
        GROK_FAKE_ACCESS_TOKEN="$access" GROK_FAKE_REFRESH_TOKEN="$refresh" \
        GROK_ARGS_FILE="$args" CURL_CALLED_FILE="$curl_called" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" LEAK_TOKEN "" "$output" >"$stdout" 2>"$stderr" || rc=$?
    assert_eq 1 "$rc" "token-shaped provider failure remains a failed CLI run"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "token-shaped post-dispatch failure never calls the API"
    assert_eq 0 "$(rg -l -F "$access" "$stdout" "$stderr" "$output" "$args" 2>/dev/null | wc -l | tr -d ' ')" \
        "access token is absent from argv capture, stdout, logs, and error envelope"
    assert_eq 0 "$(rg -l -F "$refresh" "$stdout" "$stderr" "$output" "$args" 2>/dev/null | wc -l | tr -d ' ')" \
        "refresh token is absent from argv capture, stdout, logs, and error envelope"
}

test_serialized_mode_remains_available() {
    local fake_grok="$TMP_ROOT/grok-serialized"
    local source_home="$TMP_ROOT/serialized-home" output="$TMP_ROOT/serialized.json"
    local env_file="$TMP_ROOT/serialized.env"
    mkdir -p "$source_home"
    write_oauth "$source_home/auth.json" serialized-access serialized-refresh
    make_grok_stub "$fake_grok" success
    GROK_CMD="$fake_grok" GROK_HOME="$source_home" GROK_USE_API=false \
        GROK_OAUTH_MODE=serialized GROK_MODEL=grok-4.6 \
        GROK_ARGS_FILE="$TMP_ROOT/serialized.args" GROK_ENV_FILE="$env_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" serialized "" "$output" >/dev/null 2>&1
    assert_match '^GROK_HOME=.*/ai-consultants-grok\..*/home/\.grok$' \
        "$(sed -n '2p' "$env_file")" "serialized mode retains a per-run Grok home"
}

test_forced_api_mode_is_stateless() {
    local fake_bin="$TMP_ROOT/api-stateless-bin" output="$TMP_ROOT/api-stateless.json"
    local data_root="$TMP_ROOT/api-stateless-data"
    mkdir -p "$fake_bin"
    make_curl_stub "$fake_bin/curl"
    PATH="$fake_bin:$PATH" _AI_CONSULTANTS_XDG_DATA="$data_root" \
        GROK_USE_API=true GROK_MODEL=grok-4.5 GROK_API_KEY=test-key \
        RATE_LIMIT_DIR="$TMP_ROOT/api-stateless-rate" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" api "" "$output" >/dev/null 2>&1
    assert_eq api "$(jq -r '.metadata.transport' "$output")" \
        "forced Grok API mode keeps the existing API transport"
    assert_eq false "$([[ -e "$data_root/grok-shared-oauth" ]] && echo true || echo false)" \
        "forced Grok API mode creates no OAuth generation"
}

test_unpersistable_refresh_fails_closed() {
    local source_home="$TMP_ROOT/unpersistable-home"
    local isolated_home="$TMP_ROOT/unpersistable-isolated"
    local before="$TMP_ROOT/unpersistable-before.json" rc=0
    mkdir -p "$source_home" "$isolated_home"
    write_oauth "$source_home/auth.json" persist-access persist-refresh
    cp "$source_home/auth.json" "$before"
    GROK_OAUTH_MODE=shared
    GROK_OAUTH_LOCK_WAIT_SECONDS=0
    grok_oauth_init "$source_home"
    grok_oauth_prepare "$isolated_home"
    write_oauth "$GROK_OAUTH_ACTIVE_HOME/auth.json" rotated-but-unpublished rotated-but-unpublished-refresh
    chmod 500 "$source_home"
    grok_oauth_sync || rc=$?
    chmod 700 "$source_home"
    GROK_OAUTH_LOCK_WAIT_SECONDS=25
    assert_eq 3 "$rc" "unpersistable OAuth refresh fails closed on the publication lock"
    assert_eq lock_busy "$GROK_OAUTH_SYNC_STATUS" \
        "unpersistable OAuth refresh records a non-success sync status"
    assert_eq true "$(cmp -s "$before" "$source_home/auth.json" && echo true || echo false)" \
        "unpersistable OAuth refresh leaves the ambient credential unchanged"
}

test_invalid_oauth_mode_never_dispatches_or_falls_back() {
    local fake_bin="$TMP_ROOT/invalid-oauth-bin" output="$TMP_ROOT/invalid-oauth.json"
    local request="$TMP_ROOT/invalid-oauth-request" curl_called="$TMP_ROOT/invalid-oauth-curl"
    mkdir -p "$fake_bin"
    make_grok_stub "$fake_bin/grok" success
    make_curl_stub "$fake_bin/curl"
    PATH="$fake_bin:$PATH" GROK_CMD="$fake_bin/grok" GROK_USE_API=false \
        GROK_OAUTH_MODE=bogus GROK_MODEL=grok-4.6 GROK_API_KEY=test-key \
        GROK_ARGS_FILE="$TMP_ROOT/invalid-oauth.args" GROK_REQUEST_FILE="$request" \
        CURL_CALLED_FILE="$curl_called" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" invalid "" "$output" >/dev/null 2>&1 || true
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "invalid OAuth mode fails before Grok dispatch"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "invalid OAuth mode never falls back to the API"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "invalid OAuth mode produces only an error envelope"
}

test_malformed_ambient_oauth_fails_before_dispatch() {
    local fake_bin="$TMP_ROOT/malformed-ambient-bin" output="$TMP_ROOT/malformed-ambient.json"
    local source_home="$TMP_ROOT/malformed-ambient-home"
    local request="$TMP_ROOT/malformed-ambient-request" curl_called="$TMP_ROOT/malformed-ambient-curl"
    mkdir -p "$fake_bin" "$source_home"
    printf '{}\n' > "$source_home/auth.json"
    chmod 600 "$source_home/auth.json"
    make_grok_stub "$fake_bin/grok" success
    make_curl_stub "$fake_bin/curl"
    PATH="$fake_bin:$PATH" GROK_CMD="$fake_bin/grok" GROK_HOME="$source_home" \
        GROK_USE_API=false GROK_MODEL=grok-4.6 GROK_API_KEY=test-key \
        GROK_ARGS_FILE="$TMP_ROOT/malformed-ambient.args" GROK_REQUEST_FILE="$request" \
        CURL_CALLED_FILE="$curl_called" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" malformed "" "$output" >/dev/null 2>&1 || true
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "malformed ambient OAuth fails before Grok dispatch"
    assert_eq false "$([[ -e "$curl_called" ]] && echo true || echo false)" \
        "malformed ambient OAuth never falls back to the API"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "malformed ambient OAuth produces only an error envelope"
}

test_invalid_turn_budget_never_dispatches() {
    local fake="$TMP_ROOT/grok-invalid-turns" request="$TMP_ROOT/grok-invalid-turns.request"
    local output="$TMP_ROOT/grok-invalid-turns.json" rc=0
    make_grok_stub "$fake" success
    GROK_CMD="$fake" GROK_USE_API=false GROK_MODEL=grok-4.6 GROK_MAX_TURNS=0 \
        GROK_ARGS_FILE="$TMP_ROOT/grok-invalid-turns.args" GROK_REQUEST_FILE="$request" \
        GROK_API_KEY="" XAI_API_KEY="" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_grok.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "invalid Grok turn budget fails"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "invalid Grok turn budget never dispatches"
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
run_test "Test 11: shared OAuth allows concurrent dispatch" test_shared_oauth_allows_concurrent_dispatch
run_test "Test 12: shared OAuth rotation is published and reused" test_shared_oauth_rotation_is_published_and_reused
run_test "Test 13: external login wins the shared OAuth CAS" test_external_login_wins_shared_oauth_cas
run_test "Test 14: corrupt refresh never replaces ambient OAuth" test_corrupt_refresh_never_replaces_ambient_oauth
run_test "Test 15: dead runner lock is recovered" test_dead_runner_lock_is_recovered
run_test "Test 16: shared configuration is reconciled atomically" test_shared_configuration_is_reconciled_atomically
run_test "Test 17: tokens never leave credential files" test_tokens_never_leave_credential_files
run_test "Test 18: serialized OAuth mode remains available" test_serialized_mode_remains_available
run_test "Test 19: forced API mode stays stateless" test_forced_api_mode_is_stateless
run_test "Test 20: unpersistable refresh fails closed" test_unpersistable_refresh_fails_closed
run_test "Test 21: invalid OAuth mode never dispatches or falls back" test_invalid_oauth_mode_never_dispatches_or_falls_back
run_test "Test 22: malformed ambient OAuth fails before dispatch" test_malformed_ambient_oauth_fails_before_dispatch
run_test "Test 23: invalid Grok turn budget does not dispatch" test_invalid_turn_budget_never_dispatches
test_summary "query_grok"
