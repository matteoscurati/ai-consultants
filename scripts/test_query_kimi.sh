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
        printf '%s\n' '{"models":{"kimi-code/k3.1-pro":{"model":"k3.1-pro"}}}'
    fi
    exit 0
fi

[[ -z "${KIMI_REQUEST_FILE:-}" ]] || : > "$KIMI_REQUEST_FILE"
printf '%s\n' "$@" > "$KIMI_ARGS_FILE"
[[ -z "${KIMI_CWD_FILE:-}" ]] || pwd -P > "$KIMI_CWD_FILE"
[[ -z "${KIMI_EFFORT_FILE:-}" ]] || printf '%s\n' "${KIMI_MODEL_THINKING_EFFORT-<unset>}" > "$KIMI_EFFORT_FILE"
printf '%s\n' '{"role":"assistant","content":"{\"response\":{\"summary\":\"K3.1 Pro selected\",\"detailed\":\"ok\",\"approach\":\"Test\",\"pros\":[],\"cons\":[],\"caveats\":[]},\"confidence\":{\"score\":9,\"reasoning\":\"stub\"}}"}'
EOF
    chmod +x "$path"
}

test_compatible_cli_pins_model() {
    local fake_kimi="$TMP_ROOT/kimi-compatible"
    local args_file="$TMP_ROOT/compatible-args"
    local output_file="$TMP_ROOT/compatible-response.json"
    make_kimi_stub "$fake_kimi"

    if ! KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3.1-pro" \
        KIMI_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Test model selection" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "compatible Kimi CLI completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_file")
    assert_match '(^|[[:space:]])--model[[:space:]]+kimi-code/k3\.1-pro($|[[:space:]])' "$args" "Kimi explicitly selects kimi-code/k3.1-pro"
    assert_match '(^|[[:space:]])--output-format[[:space:]]+stream-json($|[[:space:]])' "$args" "Kimi requests structured stream output"
    assert_eq "kimi-code/k3.1-pro" "$(jq -r '.model' "$output_file")" "response metadata reports kimi-code/k3.1-pro"
    assert_eq "user-build-a" "$(jq -r '.metadata.cli_version' "$output_file")" "CLI version is recorded as provenance"
    assert_eq "capability-probed" "$(jq -r '.metadata.cli_compatibility' "$output_file")" "response records capability-based compatibility"
    assert_eq "kimi-code/k3.1-pro" "$(jq -r '.metadata.requested_model' "$output_file")" "response records the requested model"
    assert_eq "capability-probed" "$(jq -r '.metadata.model_identity_source' "$output_file")" "model identity comes from the provider inventory"
}

test_alternate_compatible_version_is_accepted() {
    local fake_kimi="$TMP_ROOT/kimi-alternate"
    local args_file="$TMP_ROOT/alternate-args"
    local output_file="$TMP_ROOT/alternate-response.json"
    make_kimi_stub "$fake_kimi"

    if ! KIMI_CMD="$fake_kimi" \
        KIMI_MODEL="kimi-code/k3.1-pro" \
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
        KIMI_MODEL="kimi-code/k3.1-pro" \
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
        KIMI_MODEL="kimi-code/k3.1-pro" \
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

test_thinking_effort_reaches_cli() {
    local fake_kimi="$TMP_ROOT/kimi-effort"
    local effort_file="$TMP_ROOT/effort" request_file="$TMP_ROOT/effort-request"
    local output_file="$TMP_ROOT/effort-response.json"
    make_kimi_stub "$fake_kimi"

    # Unset: config.sh supplies max, which the CLI receives as its
    # documented [thinking] override.
    env -u KIMI_REASONING_EFFORT -u KIMI_MODEL_THINKING_EFFORT \
        KIMI_CMD="$fake_kimi" KIMI_ARGS_FILE="$TMP_ROOT/effort-args" KIMI_EFFORT_FILE="$effort_file" \
        MAX_RETRIES=1 "$SCRIPT_DIR/query_kimi.sh" "Effort default" "" "$output_file" >/dev/null 2>&1
    assert_eq "max" "$(cat "$effort_file" 2>/dev/null)" "default Kimi thinking effort is max"

    KIMI_REASONING_EFFORT=HIGH KIMI_CMD="$fake_kimi" KIMI_ARGS_FILE="$TMP_ROOT/effort-args" \
        KIMI_EFFORT_FILE="$effort_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Effort explicit" "" "$output_file" >/dev/null 2>&1
    assert_eq "high" "$(cat "$effort_file" 2>/dev/null)" "an explicit effort is validated and normalized"

    env -u KIMI_MODEL_THINKING_EFFORT KIMI_REASONING_EFFORT="" KIMI_CMD="$fake_kimi" \
        KIMI_ARGS_FILE="$TMP_ROOT/effort-args" KIMI_EFFORT_FILE="$effort_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Effort opt-out" "" "$output_file" >/dev/null 2>&1
    assert_eq "<unset>" "$(cat "$effort_file" 2>/dev/null)" "an empty effort leaves the CLI's own setting"

    if KIMI_REASONING_EFFORT=extreme KIMI_CMD="$fake_kimi" KIMI_ARGS_FILE="$TMP_ROOT/effort-args" \
        KIMI_REQUEST_FILE="$request_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "Effort invalid" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "an invalid Kimi effort fails"
    else
        assert_eq "1" "1" "an invalid Kimi effort fails"
    fi
    assert_eq "no" "$([[ -e "$request_file" ]] && echo yes || echo no)" "an invalid effort is rejected before dispatch"
}

run_test "Test 1: compatible CLI pins model and structured output" test_compatible_cli_pins_model
# M8 + M3: Kimi runs from a private empty workspace (never the caller's or the
# skill's directory), and a prompt too large for one argv element fails
# before dispatch instead of exec failing with E2BIG.
test_kimi_workspace_isolation_and_argv_guard() {
    local fake_kimi="$TMP_ROOT/kimi-isolated" cwd_file="$TMP_ROOT/kimi-cwd"
    local output_file="$TMP_ROOT/isolated.json" request="$TMP_ROOT/kimi-dispatched" rc=0 ran_in
    make_kimi_stub "$fake_kimi"
    mkdir -p "$TMP_ROOT/runtime" "$TMP_ROOT/caller"
    (cd "$TMP_ROOT/caller" && TMPDIR="$TMP_ROOT/runtime" KIMI_CMD="$fake_kimi" KIMI_MODEL="kimi-code/k3.1-pro" \
        KIMI_ARGS_FILE="$TMP_ROOT/isolated-args" KIMI_CWD_FILE="$cwd_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "isolation" "" "$output_file" >/dev/null 2>&1) || rc=$?
    ran_in=$(cat "$cwd_file" 2>/dev/null)
    assert_eq 0 "$rc" "isolated Kimi query completes"
    assert_match "/ai-consultants-kimi\\." "$ran_in" "Kimi runs from a private workspace"
    assert_eq 0 "$(find "$TMP_ROOT/runtime" -maxdepth 1 -name 'ai-consultants-kimi.*' | wc -l | tr -d ' ')" \
        "Kimi workspace is removed afterwards"

    rc=0
    ARGV_PROMPT_MAX_BYTES=64 KIMI_CMD="$fake_kimi" KIMI_MODEL="kimi-code/k3.1-pro" \
        KIMI_ARGS_FILE="$TMP_ROOT/guard-args" KIMI_REQUEST_FILE="$request" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_kimi.sh" "$(printf 'x%.0s' {1..200})" "" "$TMP_ROOT/guard.json" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$([[ $rc -ne 0 ]] && echo 1 || echo 0)" "oversized argv prompt fails"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" "oversized argv prompt never dispatches"
    assert_eq error "$(jq -r '.response.approach' "$TMP_ROOT/guard.json")" "oversized prompt writes an error envelope"
}

run_test "Test 2: alternate compatible version is accepted" test_alternate_compatible_version_is_accepted
run_test "Test 3: incompatible CLI is rejected before dispatch" test_incompatible_cli_is_rejected_before_dispatch
run_test "Test 4: missing requested model is rejected" test_missing_requested_model_is_rejected
run_test "Test 5: workspace isolation and argv guard" test_kimi_workspace_isolation_and_argv_guard
run_test "Test 6: thinking effort reaches the CLI" test_thinking_effort_reaches_cli
test_summary "query_kimi"
