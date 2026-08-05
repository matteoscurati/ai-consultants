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

[[ -z "${AGY_ARGS_FILE:-}" ]] || printf '%s\n' "$@" > "$AGY_ARGS_FILE"
[[ -z "${AGY_REQUEST_FILE:-}" ]] || : > "$AGY_REQUEST_FILE"

# Structured envelope matching process_consultant_response expectations.
printf '%s\n' '{"response":{"summary":"Gemini answered","detailed":"CLI response under SSH isolation","approach":"Test","pros":[],"cons":[],"caveats":[]},"confidence":{"score":9,"reasoning":"stub","uncertainty_factors":[]}}'
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
        GEMINI_MODEL="Gemini 3.1 Pro (High)" \
        AGY_ARGS_FILE="$args_file" \
        MAX_RETRIES=1 \
        "$SCRIPT_DIR/query_gemini.sh" "Test SSH isolation" "" "$output_file" >/dev/null 2>&1; then
        assert_eq "success" "failure" "Gemini CLI consultation succeeds under exported SSH markers"
        return
    fi

    assert_eq "Gemini" "$(jq -r '.consultant' "$output_file")" "response is from Gemini"
    assert_eq "Gemini 3.1 Pro (High)" "$(jq -r '.model' "$output_file")" "response reports pinned model"
    assert_eq "Gemini answered" "$(jq -r '.response.summary' "$output_file")" "structured response is preserved"
    assert_match '(^|[[:space:]])--model[[:space:]]+Gemini 3\.1 Pro \(High\)($|[[:space:]])' \
        "$(tr '\n' ' ' < "$args_file")" "agy receives --model flag"
}

run_test "Test 1: agy_env strips SSH markers and passes args" test_agy_env_strips_ssh_markers
run_test "Test 2: CLI consultation succeeds under SSH markers" test_cli_consultation_under_ssh_markers
test_summary "query_gemini"
