#!/usr/bin/env bash
# Regression tests for transport-specific Mistral IDs and the read-only Vibe boundary.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_mistral.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_vibe_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u
if [[ " $* " == *" --help "* ]]; then
    if [[ "${VIBE_FAKE_MODE:-success}" == incompatible ]]; then
        printf '%s\n' '--prompt --output'
    else
        printf '%s\n' '--prompt --output --agent --workdir --max-turns' 'builtin: default, plan, accept-edits' 'VIBE_* Override any config field'
    fi
    exit 0
fi
printf '%s\n' "$@" > "$VIBE_ARGS_FILE"
printf '%s\n' "${VIBE_ACTIVE_MODEL:-}" > "$VIBE_MODEL_FILE"
workspace=""
previous=""
for arg in "$@"; do
    [[ "$previous" != "--workdir" ]] || workspace="$arg"
    previous="$arg"
done
printf '%s\n' "$workspace" > "$VIBE_WORKSPACE_FILE"
[[ -z "${VIBE_REQUEST_FILE:-}" ]] || : > "$VIBE_REQUEST_FILE"
case "${VIBE_FAKE_MODE:-success}" in
    success) printf '%s\n' '{"response":{"summary":"Vibe answered","detailed":"ok","approach":"test","pros":[],"cons":[],"caveats":[]},"confidence":{"score":8,"reasoning":"stub"}}' ;;
    prose) printf '%s\n' 'Concrete Vibe recommendation' 'More detail' ;;
    empty) exit 0 ;;
    failure) echo 'post-launch failure' >&2; exit 42 ;;
esac
EOF
    chmod +x "$path"
}

test_cli_prose_is_explicit_usable_fallback() {
    local fake="$TMP_ROOT/vibe-prose" output="$TMP_ROOT/prose.json"
    make_vibe_stub "$fake"
    if ! MISTRAL_CMD="$fake" MISTRAL_USE_API=false MISTRAL_CLI_MODEL=mistral-medium-3.5 \
        VIBE_ARGS_FILE="$TMP_ROOT/prose.args" VIBE_MODEL_FILE="$TMP_ROOT/prose.model" \
        VIBE_WORKSPACE_FILE="$TMP_ROOT/prose.workspace" VIBE_FAKE_MODE=prose MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_mistral.sh" test "" "$output" >/dev/null 2>&1; then
        assert_eq success failure "Mistral prose fallback completes"
        return
    fi
    assert_eq fallback "$(jq -r '.metadata.response_quality' "$output")" \
        "Mistral prose is explicitly marked fallback"
    assert_eq "Concrete Vibe recommendation" "$(jq -r '.response.summary' "$output")" \
        "Mistral prose contributes a meaningful summary"
}

test_cli_uses_separate_model_and_isolated_plan_workspace() {
    local fake="$TMP_ROOT/vibe" args="$TMP_ROOT/args" model="$TMP_ROOT/model"
    local workspace_file="$TMP_ROOT/workspace" output="$TMP_ROOT/output.json"
    make_vibe_stub "$fake"

    if ! MISTRAL_CMD="$fake" MISTRAL_USE_API=false \
        MISTRAL_MODEL=mistral-medium-3-5 MISTRAL_CLI_MODEL=mistral-medium-3.5 \
        VIBE_ARGS_FILE="$args" VIBE_MODEL_FILE="$model" VIBE_WORKSPACE_FILE="$workspace_file" \
        MAX_RETRIES=1 "$SCRIPT_DIR/query_mistral.sh" test "" "$output" >/dev/null 2>&1; then
        assert_eq success failure "Mistral Vibe query completes"
        return
    fi

    assert_eq "mistral-medium-3.5" "$(cat "$model")" "Vibe receives its CLI-specific model alias"
    assert_eq "mistral-medium-3.5" "$(jq -r '.model' "$output")" "response records the CLI model, not the API slug"
    assert_eq "requested-only" "$(jq -r '.metadata.model_identity_source' "$output")" "Vibe does not claim provider identity without an inventory"
    assert_match '(^|[[:space:]])--agent[[:space:]]+plan($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "Vibe uses the read-only plan agent"
    assert_match '(^|[[:space:]])--max-turns[[:space:]]+4($|[[:space:]])' "$(tr '\n' ' ' < "$args")" "Vibe receives the smoke-tested advisory turn budget"
    local workspace
    workspace=$(cat "$workspace_file")
    assert_match '/ai-consultants-mistral\..*/workspace$' "$workspace" "Vibe receives an isolated temporary workspace"
    assert_eq false "$([[ -e "$workspace" ]] && echo true || echo false)" "temporary Vibe workspace is removed after dispatch"
}

test_cli_empty_and_failure_are_not_success() {
    local fake="$TMP_ROOT/vibe-fail" mode output rc
    make_vibe_stub "$fake"
    for mode in empty failure; do
        output="$TMP_ROOT/$mode.json"
        rc=0
        MISTRAL_CMD="$fake" MISTRAL_USE_API=false MISTRAL_CLI_MODEL=mistral-medium-3.5 \
            VIBE_ARGS_FILE="$TMP_ROOT/$mode.args" VIBE_MODEL_FILE="$TMP_ROOT/$mode.model" \
            VIBE_WORKSPACE_FILE="$TMP_ROOT/$mode.workspace" VIBE_FAKE_MODE="$mode" \
            MAX_RETRIES=1 "$SCRIPT_DIR/query_mistral.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
        assert_eq 1 "$rc" "Mistral $mode output returns failure"
        assert_eq error "$(jq -r '.response.approach' "$output")" "Mistral $mode output writes an error envelope"
    done
}

test_incompatible_cli_never_dispatches() {
    local fake="$TMP_ROOT/vibe-incompatible" request="$TMP_ROOT/incompatible.request"
    local output="$TMP_ROOT/incompatible.json"
    make_vibe_stub "$fake"
    if MISTRAL_CMD="$fake" MISTRAL_USE_API=false MISTRAL_CLI_MODEL=mistral-medium-3.5 \
        VIBE_ARGS_FILE="$TMP_ROOT/incompatible.args" VIBE_MODEL_FILE="$TMP_ROOT/incompatible.model" \
        VIBE_WORKSPACE_FILE="$TMP_ROOT/incompatible.workspace" VIBE_REQUEST_FILE="$request" \
        VIBE_FAKE_MODE=incompatible MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_mistral.sh" test "" "$output" >/dev/null 2>&1; then
        assert_eq failure success "incompatible Mistral CLI is rejected"
        return
    fi
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" "incompatible Mistral CLI never dispatches"
}

test_invalid_turn_budget_never_dispatches() {
    local fake="$TMP_ROOT/vibe-invalid-turns" request="$TMP_ROOT/invalid-turns.request"
    local output="$TMP_ROOT/invalid-turns.json" rc=0
    make_vibe_stub "$fake"
    MISTRAL_CMD="$fake" MISTRAL_USE_API=false MISTRAL_CLI_MODEL=mistral-medium-3.5 \
        MISTRAL_MAX_TURNS=0 VIBE_ARGS_FILE="$TMP_ROOT/invalid-turns.args" \
        VIBE_MODEL_FILE="$TMP_ROOT/invalid-turns.model" VIBE_WORKSPACE_FILE="$TMP_ROOT/invalid-turns.workspace" \
        VIBE_REQUEST_FILE="$request" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_mistral.sh" test "" "$output" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "invalid Mistral turn budget fails"
    assert_eq false "$([[ -e "$request" ]] && echo true || echo false)" \
        "invalid Mistral turn budget never dispatches"
}

run_test "Mistral CLI model and read-only isolation" test_cli_uses_separate_model_and_isolated_plan_workspace
run_test "Mistral prose remains a usable explicit fallback" test_cli_prose_is_explicit_usable_fallback
run_test "Mistral empty/post-launch failures fail closed" test_cli_empty_and_failure_are_not_success
run_test "Mistral capability-incompatible CLI fails before dispatch" test_incompatible_cli_never_dispatches
run_test "Mistral invalid turn budget fails before dispatch" test_invalid_turn_budget_never_dispatches
test_summary "query_mistral"
