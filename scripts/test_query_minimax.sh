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
    assert_eq requested-only "$(jq -r '.metadata.model_identity_source' "$output")" "MiniMax does not claim unreported CLI identity"
}

test_minimax_empty_and_failure_are_not_success() {
    local fake="$TMP_ROOT/mmx-fail" mode output rc
    make_mmx_stub "$fake"
    for mode in empty failure; do
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
test_summary "query_minimax"
