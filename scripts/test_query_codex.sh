#!/usr/bin/env bash
# Regression tests for isolated Codex CLI execution and CLI reasoning effort.

set -uo pipefail

# Pin log level so assertions on warning text are hermetic (see CLAUDE.md).
export LOG_LEVEL=INFO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_codex.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

# Controlled temp root so isolation cleanup assertions are reliable.
export TMPDIR="$TMP_ROOT/tmp"
mkdir -p "$TMPDIR"

make_codex_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u

printf '%s\n' "$@" > "${CODEX_ARGS_FILE}"
if [[ -n "${CODEX_STDIN_FILE:-}" ]]; then
    cat > "${CODEX_STDIN_FILE}"
else
    cat >/dev/null
fi
if [[ -n "${CODEX_ENV_FILE:-}" ]]; then
    printf 'HOME=%s\nCODEX_HOME=%s\n' "$HOME" "${CODEX_HOME:-}" > "${CODEX_ENV_FILE}"
fi

payload=""
previous=""
for arg in "$@"; do
    if [[ "$previous" == "-o" ]]; then
        payload="$arg"
        break
    fi
    previous="$arg"
done

mode="${CODEX_STUB_MODE:-success}"
case "$mode" in
    empty_payload)
        [[ -z "$payload" ]] || : > "$payload"
        printf '%s\n' "session chatter only"
        exit 0
        ;;
    fail_with_payload)
        # Non-empty -o payload after a real CLI failure must NOT become success.
        if [[ -n "$payload" ]]; then
            printf '%s\n' '{"response":{"summary":"partial payload must not win","detailed":"truncated","approach":"partial","pros":[],"cons":[],"caveats":[]},"confidence":{"score":1,"reasoning":"fail"}}' > "$payload"
        fi
        printf '%s\n' 'authentication failed'
        exit 42
        ;;
    *)
        if [[ -n "$payload" ]]; then
            printf '%s\n' '{"response":{"summary":"Codex payload answered","detailed":"from payload file","approach":"payload","pros":[],"cons":[],"caveats":[]},"confidence":{"score":9,"reasoning":"test"}}' > "$payload"
        fi
        # Plausible stdout chatter that must NOT be treated as the answer.
        printf '%s\n' 'hook noise: session started'
        printf '%s\n' '{"response":{"summary":"stdout chatter must not win","detailed":"wrong","approach":"stdout","pros":[],"cons":[],"caveats":[]},"confidence":{"score":1,"reasoning":"noise"}}'
        exit 0
        ;;
esac
EOF
    chmod +x "$path"
}

make_claude_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u
printf '%s\n' "$@" > "${CLAUDE_ARGS_FILE}"
cat >/dev/null
printf '%s\n' '{"type":"result","result":"{\"response\":{\"summary\":\"Claude answered\",\"detailed\":\"ok\",\"approach\":\"cli\",\"pros\":[],\"cons\":[],\"caveats\":[]},\"confidence\":{\"score\":9,\"reasoning\":\"test\"}}","usage":{"input_tokens":1,"output_tokens":1},"modelUsage":{"claude":{"inputTokens":1,"outputTokens":1,"costUSD":0.0}}}'
EOF
    chmod +x "$path"
}

make_gemini_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u
printf '%s\n' "$@" > "${GEMINI_ARGS_FILE}"
printf '%s\n' '{"response":{"summary":"Gemini answered","detailed":"ok","approach":"cli","pros":[],"cons":[],"caveats":[]},"confidence":{"score":9,"reasoning":"test"}}'
EOF
    chmod +x "$path"
}

test_cli_isolation_contract() {
    local fake_codex="$TMP_ROOT/codex-success"
    local args_file="$TMP_ROOT/cli-args"
    local env_file="$TMP_ROOT/cli-env"
    local stdin_file="$TMP_ROOT/cli-stdin"
    local user_home="$TMP_ROOT/user-home"
    local output_file="$TMP_ROOT/cli-response.json"
    mkdir -p "$user_home/.codex"
    make_codex_stub "$fake_codex"

    if ! HOME="$user_home" \
        CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_ARGS_FILE="$args_file" \
        CODEX_ENV_FILE="$env_file" \
        CODEX_STDIN_FILE="$stdin_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Test CLI isolation" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Codex CLI path completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_file")
    assert_match '(^|[[:space:]])exec($|[[:space:]])' "$args" "CLI uses codex exec"
    assert_match '(^|[[:space:]])--ephemeral($|[[:space:]])' "$args" "CLI uses --ephemeral"
    assert_match '(^|[[:space:]])--ignore-user-config($|[[:space:]])' "$args" "CLI ignores ambient user config"
    assert_match '(^|[[:space:]])--ignore-rules($|[[:space:]])' "$args" "CLI ignores project rules"
    assert_match '(^|[[:space:]])--skip-git-repo-check($|[[:space:]])' "$args" "CLI skips git-repo check"
    assert_match '(^|[[:space:]])-m[[:space:]]+gpt-5\.6-sol($|[[:space:]])' "$args" "CLI pins the model"
    assert_match '(^|[[:space:]])-s[[:space:]]+read-only($|[[:space:]])' "$args" "CLI sandbox is read-only"
    assert_match '(^|[[:space:]])-C($|[[:space:]])' "$args" "CLI pins an isolated CWD"
    assert_match '(^|[[:space:]])-o($|[[:space:]])' "$args" "CLI writes the final message to -o"
    assert_match '(^|[[:space:]])-($|[[:space:]])' "$args" "CLI reads the prompt from stdin via trailing -"
    assert_eq "0" "$(grep -c -x -- '-p' "$args_file" || true)" "CLI never passes -p (profile)"
    assert_match 'Test CLI isolation' "$(cat "$stdin_file")" "prompt reaches Codex on stdin"
    assert_eq "0" "$(grep -c 'Test CLI isolation' "$args_file" || true)" "prompt is absent from argv"
    assert_match '^HOME=.*/ai-consultants-codex\.' "$(head -1 "$env_file")" "CLI uses an isolated HOME"
    assert_eq "CODEX_HOME=${user_home}/.codex" "$(sed -n '2p' "$env_file")" "CODEX_HOME stays on the real Codex home"
    assert_eq "Codex payload answered" "$(jq -r '.response.summary' "$output_file")" "answer is taken from the -o payload"
    assert_eq "payload" "$(jq -r '.response.approach' "$output_file")" "stdout chatter did not win"
}

test_explicit_codex_home_preserved() {
    local fake_codex="$TMP_ROOT/codex-explicit-home"
    local env_file="$TMP_ROOT/explicit-env"
    local user_home="$TMP_ROOT/user-home-2"
    local real_codex_home="$TMP_ROOT/real-codex-home"
    local output_file="$TMP_ROOT/explicit-home-response.json"
    mkdir -p "$user_home" "$real_codex_home"
    make_codex_stub "$fake_codex"

    if ! HOME="$user_home" \
        CODEX_HOME="$real_codex_home" \
        CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_ARGS_FILE="$TMP_ROOT/explicit-args" \
        CODEX_ENV_FILE="$env_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Preserve CODEX_HOME" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "explicit CODEX_HOME path completes"
        return
    fi

    assert_eq "CODEX_HOME=${real_codex_home}" "$(sed -n '2p' "$env_file")" "explicit CODEX_HOME is preserved under isolation"
    assert_match '^HOME=.*/ai-consultants-codex\.' "$(head -1 "$env_file")" "HOME is still isolated when CODEX_HOME is set"
}

test_large_context_uses_stdin() {
    local fake_codex="$TMP_ROOT/codex-large"
    local args_file="$TMP_ROOT/large-args"
    local stdin_file="$TMP_ROOT/large-stdin"
    local context_file="$TMP_ROOT/large-context.txt"
    local output_file="$TMP_ROOT/large-response.json"
    make_codex_stub "$fake_codex"
    dd if=/dev/zero bs=1024 count=1100 2>/dev/null | tr '\0' x > "$context_file"

    if ! CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_ARGS_FILE="$args_file" \
        CODEX_STDIN_FILE="$stdin_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Large context" "$context_file" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "large context bypasses argv limits"
        return
    fi

    assert_eq "1" "$(grep -c 'Large context' "$stdin_file" || true)" "large prompt reaches Codex on stdin"
    assert_eq "0" "$(grep -c 'Large context' "$args_file" || true)" "large prompt is absent from argv"
    assert_match '(^|[[:space:]])-($|[[:space:]])' "$(tr '\n' ' ' < "$args_file")" "large-context path still uses stdin sentinel"
    assert_eq "Codex payload answered" "$(jq -r '.response.summary' "$output_file")" "large context still reads the payload"
}

test_empty_payload_is_failure() {
    local fake_codex="$TMP_ROOT/codex-empty"
    local output_file="$TMP_ROOT/empty-payload-response.json"
    make_codex_stub "$fake_codex"

    if CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_STUB_MODE=empty_payload \
        CODEX_ARGS_FILE="$TMP_ROOT/empty-args" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Empty payload" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "exit 0 with empty payload is a failure"
        return
    fi

    assert_eq "ERROR: Consultation failed" "$(jq -r '.response.summary' "$output_file")" \
        "empty payload produces an error envelope rather than a successful empty answer"
    assert_eq "error" "$(jq -r '.response.approach' "$output_file")" \
        "empty payload is not reported as a successful approach"
}

test_failed_run_with_payload_is_failure() {
    local fake_codex="$TMP_ROOT/codex-fail-payload"
    local output_file="$TMP_ROOT/fail-payload-response.json"
    make_codex_stub "$fake_codex"

    if CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_STUB_MODE=fail_with_payload \
        CODEX_ARGS_FILE="$TMP_ROOT/fail-payload-args" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Failed with payload" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "non-zero exit with non-empty payload is still a failure"
        return
    fi

    assert_eq "ERROR: Consultation failed" "$(jq -r '.response.summary' "$output_file")" \
        "failed run with payload produces an error envelope, not a success"
    assert_eq "error" "$(jq -r '.response.approach' "$output_file")" \
        "partial -o payload is not promoted to a successful approach"
    assert_eq "false" "$(jq -r '(.response.summary == "partial payload must not win")' "$output_file")" \
        "partial payload content does not enter the response envelope"
}

test_runtime_dirs_cleaned_up() {
    local fake_codex="$TMP_ROOT/codex-cleanup"
    local output_file="$TMP_ROOT/cleanup-response.json"
    make_codex_stub "$fake_codex"

    if ! CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_ARGS_FILE="$TMP_ROOT/cleanup-args" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Cleanup check" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "cleanup path completes"
        return
    fi

    local leftover
    leftover=$(find "$TMPDIR" -maxdepth 1 -type d -name 'ai-consultants-codex.*' 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "0" "$leftover" "temp HOME/CWD runtime dir is removed after the run"
}

test_codex_effort_flag() {
    local fake_codex="$TMP_ROOT/codex-effort"
    local args_with="$TMP_ROOT/effort-args-set"
    local args_without="$TMP_ROOT/effort-args-unset"
    local output_file="$TMP_ROOT/effort-response.json"
    local stderr_file="$TMP_ROOT/effort-stderr"
    make_codex_stub "$fake_codex"

    if ! CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_REASONING_EFFORT=high \
        CODEX_ARGS_FILE="$args_with" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_codex.sh" "Effort set" "" "$output_file" \
        >"$TMP_ROOT/effort-stdout" 2>"$stderr_file"; then
        assert_eq "success" "failure" "Codex with effort completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_with")
    assert_match 'model_reasoning_effort=high' "$args" "Codex CLI pins model_reasoning_effort when set"
    assert_eq "0" "$(grep -c 'ignored in CLI mode' "$stderr_file" || true)" "warn_effort_ignored_in_cli is silent for Codex"

    if ! CODEX_CMD="$fake_codex" \
        CODEX_USE_API=false \
        CODEX_MODEL=gpt-5.6-sol \
        CODEX_ARGS_FILE="$args_without" \
        MAX_RETRIES=1 \
        env -u CODEX_REASONING_EFFORT \
        "$SCRIPT_DIR/query_codex.sh" "Effort unset" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Codex without effort completes"
        return
    fi

    assert_eq "0" "$(grep -c 'model_reasoning_effort' "$args_without" || true)" "Codex omits effort when unset"
}

test_claude_effort_flag() {
    local fake_claude="$TMP_ROOT/claude-effort"
    local args_with="$TMP_ROOT/claude-args-set"
    local args_without="$TMP_ROOT/claude-args-unset"
    local output_file="$TMP_ROOT/claude-effort-response.json"
    local stderr_file="$TMP_ROOT/claude-effort-stderr"
    make_claude_stub "$fake_claude"

    if ! CLAUDE_CMD="$fake_claude" \
        CLAUDE_USE_API=false \
        CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_REASONING_EFFORT=high \
        CLAUDE_ARGS_FILE="$args_with" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_claude.sh" "Claude effort" "" "$output_file" \
        >"$TMP_ROOT/claude-stdout" 2>"$stderr_file"; then
        assert_eq "success" "failure" "Claude with effort completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_with")
    assert_match '(^|[[:space:]])--effort[[:space:]]+high($|[[:space:]])' "$args" "Claude CLI passes --effort when set"
    assert_eq "0" "$(grep -c 'ignored in CLI mode' "$stderr_file" || true)" "warn_effort_ignored_in_cli is silent for Claude"

    if ! CLAUDE_CMD="$fake_claude" \
        CLAUDE_USE_API=false \
        CLAUDE_MODEL=claude-opus-5 \
        CLAUDE_ARGS_FILE="$args_without" \
        MAX_RETRIES=1 \
        env -u CLAUDE_REASONING_EFFORT \
        "$SCRIPT_DIR/query_claude.sh" "Claude effort unset" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Claude without effort completes"
        return
    fi

    assert_eq "0" "$(grep -c -- '--effort' "$args_without" || true)" "Claude omits --effort when unset"
}

test_gemini_effort_flag() {
    local fake_gemini="$TMP_ROOT/gemini-effort"
    local args_with="$TMP_ROOT/gemini-args-set"
    local args_without="$TMP_ROOT/gemini-args-unset"
    local output_file="$TMP_ROOT/gemini-effort-response.json"
    local stderr_file="$TMP_ROOT/gemini-effort-stderr"
    make_gemini_stub "$fake_gemini"

    if ! GEMINI_CMD="$fake_gemini" \
        GEMINI_USE_API=false \
        GEMINI_MODEL="Gemini 3.1 Pro (High)" \
        GEMINI_REASONING_EFFORT=medium \
        GEMINI_ARGS_FILE="$args_with" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "Gemini effort" "" "$output_file" \
        >"$TMP_ROOT/gemini-stdout" 2>"$stderr_file"; then
        assert_eq "success" "failure" "Gemini with effort completes"
        return
    fi

    local args
    args=$(tr '\n' ' ' < "$args_with")
    assert_match '(^|[[:space:]])--effort[[:space:]]+medium($|[[:space:]])' "$args" "Gemini CLI passes --effort when set"
    assert_eq "0" "$(grep -c 'ignored in CLI mode' "$stderr_file" || true)" "warn_effort_ignored_in_cli is silent for Gemini"

    if ! GEMINI_CMD="$fake_gemini" \
        GEMINI_USE_API=false \
        GEMINI_MODEL="Gemini 3.1 Pro (High)" \
        GEMINI_ARGS_FILE="$args_without" \
        MAX_RETRIES=1 \
        env -u GEMINI_REASONING_EFFORT \
        "$SCRIPT_DIR/query_gemini.sh" "Gemini effort unset" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Gemini without effort completes"
        return
    fi

    assert_eq "0" "$(grep -c -- '--effort' "$args_without" || true)" "Gemini omits --effort when unset"
}

test_warn_effort_still_fires_for_unsupported_cli() {
    local out
    out=$(
        KIMI_REASONING_EFFORT=high \
        bash -c '
            set -euo pipefail
            source "'"$SCRIPT_DIR"'/lib/common.sh" >/dev/null 2>&1
            warn_effort_ignored_in_cli "Kimi"
        ' 2>&1
    )
    assert_match 'ignored in CLI mode' "$out" "warn_effort_ignored_in_cli still warns for CLIs without effort control"
}

run_test "Test 1: CLI isolation contract and payload preference" test_cli_isolation_contract
run_test "Test 2: explicit CODEX_HOME is preserved" test_explicit_codex_home_preserved
run_test "Test 3: large context uses stdin" test_large_context_uses_stdin
run_test "Test 4: empty payload is a failure" test_empty_payload_is_failure
run_test "Test 5: non-zero exit with payload is still a failure" test_failed_run_with_payload_is_failure
run_test "Test 6: runtime dirs cleaned up" test_runtime_dirs_cleaned_up
run_test "Test 7: Codex effort flag" test_codex_effort_flag
run_test "Test 8: Claude effort flag" test_claude_effort_flag
run_test "Test 9: Gemini effort flag" test_gemini_effort_flag
run_test "Test 10: warn still fires for unsupported CLI" test_warn_effort_still_fires_for_unsupported_cli
test_summary "query_codex"
