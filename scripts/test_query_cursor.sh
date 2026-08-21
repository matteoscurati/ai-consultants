#!/usr/bin/env bash
# Regression tests for the Cursor Agent identity, ask mode, and isolated workspace.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_cursor.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_cursor_stub() {
    local path="$1" identity="${2:-cursor}"
    cat > "$path" <<EOF
#!/bin/bash
set -u
if [[ "\${1:-}" == "--help" ]]; then
    [[ "$identity" == cursor ]] && printf '%s\n' 'Start the Cursor Agent --print --output-format --mode --model --list-models --workspace --trust' || printf '%s\n' 'Unrelated agent --model'
    exit 0
fi
if [[ "\${1:-}" == "--list-models" ]]; then
    [[ "\${CURSOR_FAKE_MODE:-success}" == missing_model ]] && printf '%s\n' 'gpt-5' || printf '%s\n' 'composer-2.5'
    exit 0
fi
printf '%s\n' "\$@" > "\$CURSOR_ARGS_FILE"
[[ -z "\${CURSOR_REQUEST_FILE:-}" ]] || : > "\$CURSOR_REQUEST_FILE"
case "\${CURSOR_FAKE_MODE:-success}" in
    success) printf '%s\n' '{"response":{"summary":"Cursor answered","detailed":"ok","approach":"test","pros":[],"cons":[],"caveats":[]},"confidence":{"score":8,"reasoning":"stub"}}' ;;
    empty) exit 0 ;;
    failure) echo 'post-launch failure' >&2; exit 42 ;;
esac
EOF
    chmod +x "$path"
}

test_cursor_ask_mode_and_workspace() {
    local fake="$TMP_ROOT/cursor-agent" args="$TMP_ROOT/args" output="$TMP_ROOT/output.json"
    make_cursor_stub "$fake"
    if ! CURSOR_CMD="$fake" CURSOR_MODEL=composer-2.5 CURSOR_ARGS_FILE="$args" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_cursor.sh" test "" "$output" >/dev/null 2>&1; then
        assert_eq success failure "Cursor query completes"
        return
    fi
    local flat workspace
    flat=$(tr '\n' ' ' < "$args")
    workspace=$(awk 'previous=="--workspace" {print; exit} {previous=$0}' "$args")
    assert_match '(^|[[:space:]])--mode[[:space:]]+ask($|[[:space:]])' "$flat" "Cursor uses read-only ask mode"
    assert_match '(^|[[:space:]])--trust($|[[:space:]])' "$flat" "Cursor trusts only the ephemeral workspace non-interactively"
    assert_eq 0 "$(grep -c -x -- '-f' "$args" || true)" "Cursor never force-allows tools"
    assert_match '/ai-consultants-cursor\..*/workspace$' "$workspace" "Cursor receives an isolated workspace"
    assert_eq false "$([[ -e "$workspace" ]] && echo true || echo false)" "temporary Cursor workspace is removed"
    assert_eq composer-2.5 "$(jq -r '.model' "$output")" "Cursor records Composer 2.5"
    assert_eq capability-probed "$(jq -r '.metadata.model_identity_source' "$output")" "Cursor model identity is capability-probed"
}

test_wrong_binary_and_missing_model_never_dispatch() {
    local fake mode request output
    for mode in wrong missing_model; do
        fake="$TMP_ROOT/cursor-$mode"
        request="$TMP_ROOT/$mode.request"
        output="$TMP_ROOT/$mode.json"
        [[ "$mode" == wrong ]] && make_cursor_stub "$fake" wrong || make_cursor_stub "$fake" cursor
        if CURSOR_CMD="$fake" CURSOR_MODEL=composer-2.5 CURSOR_FAKE_MODE="$mode" \
            CURSOR_ARGS_FILE="$TMP_ROOT/$mode.args" CURSOR_REQUEST_FILE="$request" MAX_RETRIES=1 \
            "$SCRIPT_DIR/query_cursor.sh" test "" "$output" >/dev/null 2>&1; then
            assert_eq failure success "Cursor $mode preflight is rejected"
        else
            assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" "Cursor $mode preflight never dispatches"
        fi
    done
}

test_cursor_empty_and_failure_are_not_success() {
    local fake="$TMP_ROOT/cursor-fail" mode output rc
    make_cursor_stub "$fake"
    for mode in empty failure; do
        output="$TMP_ROOT/$mode-output.json"
        rc=0
        CURSOR_CMD="$fake" CURSOR_MODEL=composer-2.5 CURSOR_FAKE_MODE="$mode" \
            CURSOR_ARGS_FILE="$TMP_ROOT/$mode-run.args" MAX_RETRIES=1 \
            "$SCRIPT_DIR/query_cursor.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
        assert_eq 1 "$rc" "Cursor $mode output returns failure"
        assert_eq error "$(jq -r '.response.approach' "$output")" "Cursor $mode output writes an error envelope"
    done
}

run_test "Cursor ask mode and isolated workspace" test_cursor_ask_mode_and_workspace
run_test "Cursor wrong binary/missing model fail before dispatch" test_wrong_binary_and_missing_model_never_dispatch
run_test "Cursor empty/post-launch failures fail closed" test_cursor_empty_and_failure_are_not_success
test_summary "query_cursor"
