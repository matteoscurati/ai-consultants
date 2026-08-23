#!/usr/bin/env bash
# Regression tests for Kimi capability-based CLI compatibility.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_kimi.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_kimi_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u

if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "${KIMI_FAKE_VERSION:-user-build-a}"
    exit 0
fi
if [[ " $* " == *" --help "* ]]; then
    if [[ "${KIMI_FAKE_MODE:-compatible}" == "incompatible" ]]; then
        printf '%s\n' '--model --prompt' '  provider  Manage providers'
    else
        printf '%s\n' '--model --prompt --output-format' '  provider  Manage providers'
    fi
    exit 0
fi
if [[ "${1:-}" == "provider" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
    if [[ "${KIMI_FAKE_MODE:-compatible}" == "missing_model" ]]; then
        printf '%s\n' '{"models":{}}'
    else
        printf '%s\n' '{"models":{"kimi-code/k3":{"model":"k3"}}}'
    fi
    exit 0
fi

[[ -z "${KIMI_REQUEST_FILE:-}" ]] || : > "$KIMI_REQUEST_FILE"
printf '%s\n' "$@" > "$KIMI_ARGS_FILE"
printf '%s\n' '{"role":"assistant","content":"{\"response\":{\"summary\":\"K3 selected\",\"detailed\":\"ok\",\"approach\":\"Test\",\"pros\":[],\"cons\":[],\"caveats\":[]},\"confidence\":{\"score\":9,\"reasoning\":\"stub\"}}"}'
EOF
    chmod +x "$path"
}

test_compatible_cli_pins_model() {
    local fake_kimi="$TMP_ROOT/kimi-compatible"
    local args_file="$TMP_ROOT/compatible-args"
    local output_file="$TMP_ROOT/compatible-response.json"
    make_kimi_stub "$fake_kimi"

    if ! KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3" \
        KIMI_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Test model selection" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "compatible Kimi CLI completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_file")
    assert_match '(^|[[:space:]])--model[[:space:]]+kimi-code/k3($|[[:space:]])' "$args" "Kimi explicitly selects kimi-code/k3"
    assert_match '(^|[[:space:]])--output-format[[:space:]]+stream-json($|[[:space:]])' "$args" "Kimi requests structured stream output"
    assert_eq "kimi-code/k3" "$(jq -r '.model' "$output_file")" "response metadata reports kimi-code/k3"
    assert_eq "user-build-a" "$(jq -r '.metadata.cli_version' "$output_file")" "CLI version is recorded as provenance"
    assert_eq "capability-probed" "$(jq -r '.metadata.cli_compatibility' "$output_file")" "response records capability-based compatibility"
    assert_eq "kimi-code/k3" "$(jq -r '.metadata.requested_model' "$output_file")" "response records the requested model"
    assert_eq "capability-probed" "$(jq -r '.metadata.model_identity_source' "$output_file")" "model identity comes from the provider inventory"
}

test_alternate_compatible_version_is_accepted() {
    local fake_kimi="$TMP_ROOT/kimi-alternate"
    local args_file="$TMP_ROOT/alternate-args"
    local output_file="$TMP_ROOT/alternate-response.json"
    make_kimi_stub "$fake_kimi"

    if ! KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3" \
        KIMI_FAKE_VERSION="user-build-b" \
        KIMI_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Test alternate version" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "compatible alternate Kimi version completes"
        return
    fi

    assert_eq "user-build-b" "$(jq -r '.metadata.cli_version' "$output_file")" "alternate Kimi version is provenance only"
}

test_incompatible_cli_is_rejected_before_dispatch() {
    local fake_kimi="$TMP_ROOT/kimi-incompatible"
    local args_file="$TMP_ROOT/incompatible-args"
    local output_file="$TMP_ROOT/incompatible-response.json"
    local request_file="$TMP_ROOT/incompatible-request"
    make_kimi_stub "$fake_kimi"

    if KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3" \
        KIMI_FAKE_MODE="incompatible" \
        KIMI_ARGS_FILE="$args_file" \
        KIMI_REQUEST_FILE="$request_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Test incompatible CLI" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "capability-incompatible Kimi CLI is rejected"
        return
    fi

    assert_eq "false" "$([[ -e "$request_file" ]] && echo true || echo false)" "incompatible Kimi CLI never starts a request"
}

test_missing_requested_model_is_rejected() {
    local fake_kimi="$TMP_ROOT/kimi-missing-model"
    local args_file="$TMP_ROOT/missing-model-args"
    local output_file="$TMP_ROOT/missing-model-response.json"
    local request_file="$TMP_ROOT/missing-model-request"
    make_kimi_stub "$fake_kimi"

    if KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3" \
        KIMI_FAKE_MODE="missing_model" \
        KIMI_ARGS_FILE="$args_file" \
        KIMI_REQUEST_FILE="$request_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Test missing model" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "Kimi CLI without the requested model is rejected"
        return
    fi

    assert_eq "false" "$([[ -e "$request_file" ]] && echo true || echo false)" "missing-model Kimi CLI never starts a request"
}

run_test "Test 1: compatible CLI pins model and structured output" test_compatible_cli_pins_model
run_test "Test 2: alternate compatible version is accepted" test_alternate_compatible_version_is_accepted
run_test "Test 3: incompatible CLI is rejected before dispatch" test_incompatible_cli_is_rejected_before_dispatch
run_test "Test 4: missing requested model is rejected" test_missing_requested_model_is_rejected
test_summary "query_kimi"
