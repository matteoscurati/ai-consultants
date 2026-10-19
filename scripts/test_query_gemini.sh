#!/usr/bin/env bash
# Regression tests for Gemini/agy SSH credential-store isolation.
#
# The Antigravity CLI switches to a file-based token store when it sees any of
# SSH_CLIENT, SSH_CONNECTION, or SSH_TTY, and then never consults the macOS
# Keychain. query_gemini.sh (and other agy call sites) must strip those markers
# via agy_env before launching the CLI. This suite exports all three markers
# and makes the stub exit 90 if any of them leaks through — removing the fix
# must fail the suite.

set -uo pipefail

# Pin log level so assertions that ever match log output are hermetic
# (lib/common.sh::_log filters by LOG_LEVEL).
export LOG_LEVEL=INFO

# Simulate an SSH session for the whole suite. The real fix must strip these
# before they reach agy; the stub enforces that contract.
export SSH_CLIENT="10.0.0.1 54321 22"
export SSH_CONNECTION="10.0.0.1 54321 10.0.0.2 22"
export SSH_TTY="/dev/pts/9"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_gemini.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

make_agy_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
set -u

# Non-vacuous contract: if any SSH credential-store marker reaches this
# process, fail with a distinctive exit code so the suite cannot pass by
# accident when agy_env is removed.
if [[ -n "${SSH_CLIENT+x}" || -n "${SSH_CONNECTION+x}" || -n "${SSH_TTY+x}" ]]; then
    echo "SSH markers leaked into agy environment" >&2
    exit 90
fi

if [[ "${1:-}" == "--version" ]]; then
    printf 'agy 1.0.0-test\n'
    exit 0
fi

if [[ "${1:-}" == "models" ]]; then
    if [[ "${AGY_FAKE_MODE:-compatible}" == "inventory_bind_error" ]]; then
        # What agy prints inside a sandbox that forbids its local server.
        printf '%s\n' 'Error: (1) attached stack trace' '  | third_party/jetski/language_server/server.go:1777' \
            'Wraps: (4) operation not permitted' 'Error types: (1) *withstack.withStack (2) *net.OpError' \
            'Failed to start: listen tcp 127.0.0.1:0: bind: operation not permitted' >&2
        exit 1
    fi
    if [[ "${AGY_FAKE_MODE:-compatible}" == "missing_model" ]]; then
        printf '%s\n' 'Gemini 3.7 Flash (High)'
    else
        printf '%s\n' 'Gemini 3.1 Pro (High)' 'Gemini 3.8 Flash (High)' 'Gemini 3.8 Flash (Low)'
    fi
    exit 0
fi

[[ -z "${AGY_ARGS_FILE:-}" ]] || printf '%s\n' "$@" > "$AGY_ARGS_FILE"
[[ -z "${AGY_REQUEST_FILE:-}" ]] || : > "$AGY_REQUEST_FILE"

# Structured envelope matching process_consultant_response expectations.
case "${AGY_FAKE_MODE:-compatible}" in
    prose_then_hang) printf '%s\n' 'Still thinking about the cache...' ;;
    *) printf '%s\n' '{"response":{"summary":"Gemini answered","detailed":"CLI response under SSH isolation","approach":"Test","pros":[],"cons":[],"caveats":[]},"confidence":{"score":9,"reasoning":"stub","uncertainty_factors":[]}}' ;;
esac
# agy 1.4 can print its whole answer and then never exit.
if [[ "${AGY_FAKE_MODE:-}" == *hang* ]]; then
    sleep 600 &
    printf '%s %s\n' "$$" "$!" > "$AGY_PID_FILE"
    wait
fi
EOF
    chmod +x "$path"
}

test_agy_env_strips_ssh_markers() {
    # shellcheck source=lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"

    local leaked
    leaked=$(agy_env env | grep -E '^(SSH_CLIENT|SSH_CONNECTION|SSH_TTY)=' || true)
    assert_eq "" "$leaked" "agy_env strips SSH_CLIENT, SSH_CONNECTION, and SSH_TTY"

    leaked=$("${AGY_ENV_PREFIX[@]}" env | grep -E '^(SSH_CLIENT|SSH_CONNECTION|SSH_TTY)=' || true)
    assert_eq "" "$leaked" "AGY_ENV_PREFIX strips the same three SSH markers"

    local out
    out=$(agy_env printf '%s|%s\n' "alpha" "beta gamma")
    assert_eq "alpha|beta gamma" "$out" "agy_env passes arguments through unchanged"
}

test_cli_consultation_under_ssh_markers() {
    local fake_agy="$TMP_ROOT/agy-ssh-safe"
    local args_file="$TMP_ROOT/agy-args"
    local output_file="$TMP_ROOT/gemini-response.json"
    make_agy_stub "$fake_agy"

    # Force CLI mode even if a GEMINI_API_KEY is present in the ambient env.
    if ! GEMINI_CMD="$fake_agy" \
        GEMINI_USE_API=false \
        GEMINI_MODEL="Gemini 3.8 Flash (High)" \
        AGY_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "Test SSH isolation" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Gemini CLI consultation succeeds under exported SSH markers"
        return
    fi

    assert_eq "Gemini" "$(jq -r '.consultant' "$output_file")" "response is from Gemini"
    assert_eq "Gemini 3.8 Flash (High)" "$(jq -r '.model' "$output_file")" "response reports promoted model"
    assert_eq "Gemini answered" "$(jq -r '.response.summary' "$output_file")" "structured response is preserved"
    assert_eq "Gemini 3.8 Flash (High)" "$(jq -r '.metadata.requested_model' "$output_file")" \
        "metadata records requested CLI model"
    assert_eq "capability-probed" "$(jq -r '.metadata.model_identity_source' "$output_file")" \
        "Gemini CLI identity comes from the model inventory"
    assert_match '(^|[[:space:]])--model[[:space:]]+Gemini 3\.8 Flash \(High\)($|[[:space:]])' \
        "$(tr '\n' ' ' < "$args_file")" "agy receives --model flag"
}

test_missing_model_is_rejected_before_dispatch() {
    local fake_agy="$TMP_ROOT/agy-missing-model"
    local request_file="$TMP_ROOT/missing-model-request"
    local output_file="$TMP_ROOT/missing-model-response.json"
    make_agy_stub "$fake_agy"

    if GEMINI_CMD="$fake_agy" GEMINI_USE_API=false \
        GEMINI_MODEL="Gemini 3.8 Flash (High)" AGY_FAKE_MODE=missing_model \
        AGY_REQUEST_FILE="$request_file" MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "Test missing model" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "failure" "success" "missing Gemini model is rejected"
        return
    fi
    assert_eq "false" "$([[ -e "$request_file" ]] && echo true || echo false)" \
        "missing Gemini model never starts a request"
}

test_inventory_failure_names_its_cause() {
    local fake_agy="$TMP_ROOT/agy-bind-error" output_file="$TMP_ROOT/bind-error.json" err_file="$TMP_ROOT/bind-error.err"
    make_agy_stub "$fake_agy"
    GEMINI_CMD="$fake_agy" GEMINI_USE_API=false GEMINI_MODEL="Gemini 3.8 Flash (High)" \
        AGY_FAKE_MODE=inventory_bind_error MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "Test sandbox" "" "$output_file" >/dev/null 2>"$err_file" </dev/null || true
    # shellcheck source=lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    assert_eq "Antigravity model inventory failed: Failed to start: listen tcp 127.0.0.1:0: bind: operation not permitted" \
        "$(get_consultant_error_reason "$err_file")" "the inventory failure states agy's own cause, not a login guess"
}

# Start query_gemini.sh in the background with a stub agy. Sets RUN_PID.
start_gemini_query() {
    local fake_agy="$1" output_file="$2"; shift 2
    env GEMINI_CMD="$fake_agy" GEMINI_USE_API=false GEMINI_MODEL="Gemini 3.8 Flash (High)" \
        MAX_RETRIES=1 "$@" \
        "$SCRIPT_DIR/query_gemini.sh" "Is the cache thread-safe?" "" "$output_file" \
        >/dev/null 2>"$output_file.log" </dev/null &
    RUN_PID=$!
}

# Usage: finishes_within <seconds> <pid>
finishes_within() {
    local deadline=$(( $(date +%s) + $1 ))
    while kill -0 "$2" 2>/dev/null; do
        (( $(date +%s) < deadline )) || return 1
        sleep 0.2
    done
}

stub_alive() {
    local p alive=0
    for p in $(cat "$1" 2>/dev/null); do
        kill -0 "$p" 2>/dev/null && alive=$((alive + 1))
    done
    printf '%s' "$alive"
}

# Stop what the query is waiting for (the guard and agy), as a host stop
# would, and let the adapter itself exit: Bash 3.2 reports a job killed by a
# signal on stderr even when its wait is redirected.
stop_query_tree() {
    local child
    for child in $(pgrep -P "$1"); do
        ( source "$SCRIPT_DIR/lib/common.sh" && kill_process_tree "$child" ) >/dev/null 2>&1
    done
    wait "$1" 2>/dev/null || true
}

test_complete_answer_survives_agy_that_never_exits() {
    local fake_agy="$TMP_ROOT/agy-hangs" output_file="$TMP_ROOT/hang-response.json" pid_file="$TMP_ROOT/hang.pids"
    make_agy_stub "$fake_agy"
    start_gemini_query "$fake_agy" "$output_file" AGY_FAKE_MODE=hang_after_answer \
        AGY_PID_FILE="$pid_file" AGY_EXIT_GRACE_SECONDS=2
    if ! finishes_within 30 "$RUN_PID"; then
        stop_query_tree "$RUN_PID"
        assert_eq finished hung "a complete answer from an agy that never exits ends the query"
        return
    fi
    local rc=0
    wait "$RUN_PID" || rc=$?
    assert_eq 0 "$rc" "the query succeeds with the answer agy printed"
    assert_eq "Gemini answered" "$(jq -r '.response.summary' "$output_file" 2>/dev/null)" "the structured answer is kept"
    assert_eq 0 "$(stub_alive "$pid_file")" "the agy process that never exited is gone"
}

test_partial_answer_keeps_waiting_for_agy() {
    local fake_agy="$TMP_ROOT/agy-prose-hangs" output_file="$TMP_ROOT/prose-response.json" pid_file="$TMP_ROOT/prose.pids"
    make_agy_stub "$fake_agy"
    start_gemini_query "$fake_agy" "$output_file" AGY_FAKE_MODE=prose_then_hang \
        AGY_PID_FILE="$pid_file" AGY_EXIT_GRACE_SECONDS=1
    if finishes_within 5 "$RUN_PID"; then
        assert_eq waiting ended "output that is not a complete answer keeps waiting for agy"
        return
    fi
    assert_eq 1 1 "output that is not a complete answer keeps waiting for agy"
    stop_query_tree "$RUN_PID"
    assert_eq 0 "$(stub_alive "$pid_file")" "stopping the query also ends the guarded agy"
}

test_exit_guard_passes_status_and_stdin_through() {
    local guard="$SCRIPT_DIR/lib/agy_exit_guard.sh" out rc
    rc=0
    out=$(printf 'from stdin' | "$guard" 5 bash -c 'cat; exit 3') || rc=$?
    assert_eq "from stdin" "$out" "the guarded command reads stdin and its output is returned"
    assert_eq 3 "$rc" "the guarded command's exit status is returned"
    rc=0
    out=$(printf 'direct' | "$guard" 0 bash -c 'cat; exit 4') || rc=$?
    assert_eq "direct|4" "$out|$rc" "grace 0 runs the command directly"
    # shellcheck source=lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    build_synthesis_args gemini "Synthesize" ""
    assert_contains "agy_exit_guard.sh" "${SYNTHESIS_ARGS[*]}" "agy synthesis runs under the exit guard"
}

run_test "Test 1: agy_env strips SSH markers and passes args" test_agy_env_strips_ssh_markers
run_test "Test 2: CLI consultation succeeds under SSH markers" test_cli_consultation_under_ssh_markers
run_test "Test 3: missing requested model is rejected before dispatch" test_missing_model_is_rejected_before_dispatch
run_test "Test 4: a complete answer survives an agy that never exits" test_complete_answer_survives_agy_that_never_exits
run_test "Test 5: a partial answer keeps waiting for agy" test_partial_answer_keeps_waiting_for_agy
run_test "Test 6: the exit guard passes status and stdin through" test_exit_guard_passes_status_and_stdin_through
run_test "Test 7: a model inventory failure names its cause" test_inventory_failure_names_its_cause
test_summary "query_gemini"
