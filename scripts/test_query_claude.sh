#!/usr/bin/env bash
# test_query_claude.sh - Claude CLI JSON usage/cost regression tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
# shellcheck source=lib/costs.sh
source "$SCRIPT_DIR/lib/costs.sh" >/dev/null 2>&1

TMP=$(mktemp -d -t ai_consultants_query_claude_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

test_cli_json_usage_and_cost() {
    local fake="$TMP/claude" output="$TMP/response.json" rc=0
    printf '%s\n' \
        '#!/bin/bash' \
        '[[ " $* " == *" --output-format json "* ]] || exit 19' \
        'printf "%s\n" '"'"'{"type":"result","subtype":"success","result":"hello","stop_reason":"end_turn","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40},"modelUsage":{"claude-opus-5":{"inputTokens":10,"outputTokens":40,"cacheReadInputTokens":30,"cacheCreationInputTokens":20,"costUSD":0.42}}}'"'" \
        > "$fake"
    chmod +x "$fake"

    AI_CONSULTANTS_CONFIG_DIR="$TMP/config" \
        CLAUDE_CMD="$fake" \
        CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_USE_API=false \
        ENABLE_PERSONA=false \
        "$SCRIPT_DIR/query_claude.sh" "test" "" "$output" >/dev/null 2>&1 || rc=$?

    assert_eq "0" "$rc" "Claude CLI JSON query completes"
    assert_eq "hello" "$(jq -r '.response.detailed' "$output")" \
        "visible result is extracted from the CLI envelope"
    assert_eq "100" "$(jq -r '.metadata.tokens_used' "$output")" \
        "CLI usage includes regular, cache, and thinking/output tokens"
    assert_eq "measured" "$(jq -r '.metadata.tokens_source' "$output")" \
        "CLI provider usage is marked measured"
    assert_eq "0.42" "$(jq -r '.metadata.provider_cost_usd' "$output")" \
        "CLI provider cost is persisted"
    assert_eq "claude-opus-5" "$(jq -r '.metadata.requested_model' "$output")" \
        "Claude records the requested content model separately"
    assert_eq "requested-only" "$(jq -r '.metadata.model_identity_source' "$output")" \
        "modelUsage billing participants are not misreported as content identity"
    assert_eq "0.420000" "$(calculate_session_cost "$TMP")" \
        "session cost uses Claude CLI costUSD exactly"
}

run_test "Claude CLI JSON usage and provider cost" test_cli_json_usage_and_cost
test_summary "query_claude"
