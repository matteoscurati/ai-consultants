#!/usr/bin/env bash
# Regression tests for MiniMax CLI model selection and failure handling.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_minimax.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_mmx_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$MMX_ARGS_FILE"
case "${MMX_FAKE_MODE:-success}" in
  success) printf '%s\n' '{"response":{"summary":"MiniMax answered","detailed":"ok","approach":"test","pros":[],"cons":[],"caveats":[]},"confidence":{"score":8,"reasoning":"stub"}}' ;;
  truncated) printf '%s' '{"response":{"summary":"cut"}' ;;
  empty) exit 0 ;;
  failure) echo 'post-launch failure' >&2; exit 42 ;;
esac
EOF
    chmod +x "$path"
}

test_minimax_cli_model_and_identity() {
    local fake="$TMP_ROOT/mmx" args="$TMP_ROOT/args" output="$TMP_ROOT/output.json"
    make_mmx_stub "$fake"
    if ! MINIMAX_CMD="$fake" MINIMAX_USE_API=false MINIMAX_MODEL=MiniMax-M2.7 \
        MMX_ARGS_FILE="$args" MAX_RETRIES=1 "$SCRIPT_DIR/query_minimax.sh" test "" "$output" >/dev/null 2>&1; then
        assert_eq success failure "MiniMax CLI query completes"
        return
    fi
    assert_match '(^|[[:space:]])--model[[:space:]]+MiniMax-M2\.7($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "MiniMax pins M2.7"
    assert_match '(^|[[:space:]])--max-tokens[[:space:]]+4096($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "MiniMax pins the completion budget"
    assert_eq requested-only "$(jq -r '.metadata.model_identity_source' "$output")" "MiniMax does not claim unreported CLI identity"
    assert_match 'under 4000 characters' "$(tr '\n' ' ' < "$args")" "MiniMax receives the compact-response contract"
    assert_match 'Do not emit JSON' "$(tr '\n' ' ' < "$args")" "MiniMax uses the reliable prose contract"
    assert_match '(^|[[:space:]])--system($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "MiniMax uses the native system channel"
    assert_match '(^|[[:space:]])--messages-file[[:space:]]+-($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "MiniMax reads the user message from stdin"
    assert_eq 0 "$(grep -c -x -- '--message' "$args" || true)" "MiniMax does not expose the user prompt through --message argv"
}

test_minimax_invalid_token_budget_fails_before_dispatch() {
    local fake="$TMP_ROOT/mmx-invalid-budget" args="$TMP_ROOT/invalid-budget.args"
    local output="$TMP_ROOT/invalid-budget.json" rc=0
    make_mmx_stub "$fake"
    MINIMAX_CMD="$fake" MINIMAX_USE_API=false MINIMAX_MODEL=MiniMax-M2.7 \
        MINIMAX_MAX_TOKENS=invalid MMX_ARGS_FILE="$args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_minimax.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "invalid MiniMax token budget fails"
    assert_eq false "$([[ -e "$args" ]] && echo true || echo false)" \
        "invalid MiniMax token budget never dispatches"
}

test_minimax_empty_and_failure_are_not_success() {
    local fake="$TMP_ROOT/mmx-fail" mode output rc
    make_mmx_stub "$fake"
    for mode in empty failure truncated; do
        output="$TMP_ROOT/$mode.json"
        rc=0
        MINIMAX_CMD="$fake" MINIMAX_USE_API=false MINIMAX_MODEL=MiniMax-M2.7 \
            MMX_ARGS_FILE="$TMP_ROOT/$mode.args" MMX_FAKE_MODE="$mode" MAX_RETRIES=1 \
            "$SCRIPT_DIR/query_minimax.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
        assert_eq 1 "$rc" "MiniMax $mode output returns failure"
        assert_eq error "$(jq -r '.response.approach' "$output")" "MiniMax $mode output writes an error envelope"
    done
}

run_test "MiniMax CLI model and identity provenance" test_minimax_cli_model_and_identity
run_test "MiniMax empty/post-launch failures fail closed" test_minimax_empty_and_failure_are_not_success
run_test "MiniMax invalid token budget fails before dispatch" test_minimax_invalid_token_budget_fails_before_dispatch
test_summary "query_minimax"
