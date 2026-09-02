#!/usr/bin/env bash
# test_query_claude.sh - Claude CLI JSON usage/cost regression tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/costs.sh" >/dev/null 2>&1

TMP=$(mktemp -d -t ai_consultants_query_claude_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

test_cli_json_usage_and_cost() {
    local fake="$TMP/claude" output="$TMP/response.json" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode' '  auth  Manage authentication'
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  printf '%s\n' '{"loggedIn":true}'
  exit 0
fi
[[ " $* " == *" --output-format json "* ]] || exit 19
printf '%s\n' "$@" > "$CLAUDE_ARGS_FILE"
prompt=$(cat)
[[ -z "${CLAUDE_PROMPT_FILE:-}" ]] || printf '%s' "$prompt" > "$CLAUDE_PROMPT_FILE"
printf '%s\n' '{"type":"result","subtype":"success","model":"claude-fable-5-1","result":"hello","stop_reason":"end_turn","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40},"modelUsage":{"claude-fable-5-1":{"inputTokens":10,"outputTokens":40,"cacheReadInputTokens":30,"cacheCreationInputTokens":20,"costUSD":0.42}}}'
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" \
        CLAUDE_MODEL=claude-fable-5-1 CLAUDE_USE_API=false \
        CLAUDE_PROMPT_FILE="$TMP/prompt" CLAUDE_ARGS_FILE="$TMP/args" ENABLE_PERSONA=true \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 0 "$rc" "Claude CLI JSON query completes"
    assert_eq hello "$(jq -r '.response.detailed' "$output")" \
        "visible result is extracted from the CLI envelope"
    assert_eq 100 "$(jq -r '.metadata.tokens_used' "$output")" \
        "CLI usage includes regular, cache, and thinking/output tokens"
    assert_eq measured "$(jq -r '.metadata.tokens_source' "$output")" \
        "CLI provider usage is marked measured"
    assert_eq 0.42 "$(jq -r '.metadata.provider_cost_usd' "$output")" \
        "CLI provider cost is persisted"
    assert_eq claude-fable-5-1 "$(jq -r '.metadata.requested_model' "$output")" \
        "Claude records the requested content model separately"
    assert_eq claude-fable-5-1 "$(jq -r '.model' "$output")" \
        "CLI provider attestation supplies the effective content model"
    assert_eq provider-reported "$(jq -r '.metadata.model_identity_source' "$output")" \
        "top-level provider model is distinguished from billing participants"
    assert_eq 0.420000 "$(calculate_session_cost "$TMP")" \
        "session cost uses Claude CLI costUSD exactly"
    assert_match 'under 5000 characters' "$(cat "$TMP/prompt")" \
        "Claude receives the compact-response contract"
    assert_match '--no-session-persistence' "$(tr '\n' ' ' < "$TMP/args")" \
        "Claude consultation disables session persistence"
    assert_match '--setting-sources' "$(tr '\n' ' ' < "$TMP/args")" \
        "Claude consultation excludes ambient setting sources"
    assert_match '--tools' "$(tr '\n' ' ' < "$TMP/args")" \
        "Claude consultation disables tools"
    assert_match '--model claude-fable-5-1' "$(tr '\n' ' ' < "$TMP/args")" \
        "Claude CLI request selects Fable 5.1"
}

test_cli_safety_route_uses_provider_identity() {
    local fake="$TMP/claude-safety-route" output="$TMP/safety-route.json" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode' '  auth  Manage authentication'
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  printf '%s\n' '{"loggedIn":true}'
  exit 0
fi
cat >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","model":"claude-opus-5","result":"hello","usage":{"input_tokens":1,"output_tokens":1},"modelUsage":{"claude-opus-5":{"inputTokens":1,"outputTokens":1,"costUSD":0.01}}}'
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" \
        CLAUDE_MODEL=claude-fable-5-1 CLAUDE_USE_API=false ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 0 "$rc" "safety-routed Claude response completes"
    assert_eq claude-fable-5-1 "$(jq -r '.metadata.requested_model' "$output")" \
        "safety route preserves requested Fable 5.1"
    assert_eq claude-opus-5 "$(jq -r '.model' "$output")" \
        "safety route is never labeled as Fable 5.1"
    assert_eq provider-reported "$(jq -r '.metadata.model_identity_source' "$output")" \
        "safety route records provider-reported identity"
    assert_eq 0.01 "$(jq -r '.metadata.provider_cost_usd' "$output")" \
        "safety route preserves exact provider cost"
}

test_api_safety_route_uses_provider_identity() {
    local fake="$TMP/curl" output="$TMP/api-safety-route.json" request="$TMP/api-request.json" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
out="" headers="" body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift; out="$1" ;;
    -D) shift; headers="$1" ;;
    -d) shift; body="$1" ;;
  esac
  shift
done
printf '%s' "$body" > "$CLAUDE_API_REQUEST_FILE"
printf '%s\n' '{"model":"claude-opus-5","content":[{"type":"text","text":"hello"}],"stop_reason":"end_turn","usage":{"input_tokens":2,"output_tokens":3}}' > "$out"
: > "$headers"
printf 200
EOF
    chmod +x "$fake"

    PATH="$TMP:$PATH" AI_CONSULTANTS_CONFIG_DIR="$TMP/config" \
        ANTHROPIC_API_KEY=test-key CLAUDE_API_REQUEST_FILE="$request" \
        CLAUDE_MODEL=claude-fable-5-1 CLAUDE_USE_API=true ENABLE_PERSONA=false \
        MAX_RETRIES=1 RATE_LIMIT_DIR="$TMP/rate-api-safety" \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 0 "$rc" "safety-routed Claude API response completes"
    assert_eq claude-fable-5-1 "$(jq -r '.model' "$request")" \
        "Claude API request selects Fable 5.1"
    assert_eq claude-fable-5-1 "$(jq -r '.metadata.requested_model' "$output")" \
        "API safety route preserves requested Fable 5.1"
    assert_eq claude-opus-5 "$(jq -r '.model' "$output")" \
        "API safety route is never labeled as Fable 5.1"
    assert_eq provider-reported "$(jq -r '.metadata.model_identity_source' "$output")" \
        "API safety route records provider-reported identity"
}

test_cli_truncated_json_fails_closed_with_cost() {
    local fake="$TMP/claude-truncated" output="$TMP/truncated.json" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode' '  auth  Manage authentication'
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  printf '%s\n' '{"loggedIn":true}'
  exit 0
fi
cat >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","result":"{\"response\":{\"summary\":\"cut\"}","usage":{"input_tokens":10,"output_tokens":40},"modelUsage":{"claude-opus-5":{"inputTokens":10,"outputTokens":40,"costUSD":0.50}}}'
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" \
        CLAUDE_MODEL=claude-opus-5 CLAUDE_USE_API=false ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 1 "$rc" "truncated Claude JSON returns failure"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "truncated Claude JSON is not downgraded to fallback"
    assert_eq 0.50 "$(jq -r '.metadata.provider_cost_usd' "$output")" \
        "failed structured output retains measured provider cost"
}

test_cli_incompatible_or_logged_out_fails_before_dispatch() {
    local fake="$TMP/claude-unready" output="$TMP/unready.json" request="$TMP/unready.request" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model'
  exit 0
fi
[[ -z "${CLAUDE_REQUEST_FILE:-}" ]] || : > "$CLAUDE_REQUEST_FILE"
exit 42
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_USE_API=false CLAUDE_REQUEST_FILE="$request" ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 1 "$rc" "Claude without stateless advisory capabilities fails"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "Claude readiness failure never dispatches a request"
    assert_eq error "$(jq -r '.metadata.response_quality' "$output")" \
        "Claude readiness failure writes an error envelope"
}

test_cli_logged_out_fails_before_dispatch() {
    local fake="$TMP/claude-logged-out" output="$TMP/logged-out.json" request="$TMP/logged-out.request" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode' '  auth  Manage authentication'
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  printf '%s\n' '{"loggedIn":false}'
  exit 0
fi
[[ -z "${CLAUDE_REQUEST_FILE:-}" ]] || : > "$CLAUDE_REQUEST_FILE"
exit 42
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_USE_API=false CLAUDE_REQUEST_FILE="$request" ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 1 "$rc" "logged-out Claude fails"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "logged-out Claude never dispatches"
}

test_cli_without_auth_subcommand_uses_dispatch_as_auth_check() {
    local fake="$TMP/claude-no-auth-command" output="$TMP/no-auth-command.json" request="$TMP/no-auth-command.request" rc=0
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode'
  exit 0
fi
[[ -z "${CLAUDE_REQUEST_FILE:-}" ]] || : > "$CLAUDE_REQUEST_FILE"
cat >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","result":"hello","usage":{"input_tokens":1,"output_tokens":1},"modelUsage":{"claude-opus-5":{"inputTokens":1,"outputTokens":1,"costUSD":0.01}}}'
EOF
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" CLAUDE_CMD="$fake" CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_USE_API=false CLAUDE_REQUEST_FILE="$request" ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" test "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq 0 "$rc" "Claude without auth subcommand can dispatch"
    assert_eq true "$([[ -e "$request" ]] && echo true || echo false)" \
        "dispatch becomes the auth check when auth status is unavailable"
}

run_test "Claude CLI JSON usage and provider cost" test_cli_json_usage_and_cost
run_test "Claude CLI safety-route model identity" test_cli_safety_route_uses_provider_identity
run_test "Claude API safety-route model identity" test_api_safety_route_uses_provider_identity
run_test "Claude truncated JSON fails closed with measured cost" test_cli_truncated_json_fails_closed_with_cost
run_test "Claude readiness probe fails before dispatch" test_cli_incompatible_or_logged_out_fails_before_dispatch
run_test "Claude logged-out probe fails before dispatch" test_cli_logged_out_fails_before_dispatch
run_test "Claude without auth subcommand dispatches" test_cli_without_auth_subcommand_uses_dispatch_as_auth_check
test_summary "query_claude"
