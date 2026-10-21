#!/bin/bash
# test_all.sh - Master runner for the standalone test_*.sh scripts (v2.13+)
#
# Discovers every standalone test_*.sh suite, including test_suite.sh, so a
# single command exercises the full regression gate.
#
# Usage: ./scripts/test_all.sh
# Exit:  0 if all suites pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hermetic gate. A maintainer's real ~/.config/ai-consultants/.env, or a
# caller that already sourced config.sh (scripts/release.sh does), used to leak
# into every suite: tests then passed or failed depending on the machine
# (see the v2.23.0, v2.25.1 and v3.0.0 changelog entries). Isolate the user
# config directory and drop every documented configuration key plus the
# internal _AI_CONSULTANTS_* markers before any suite runs.
# Set AI_CONSULTANTS_TEST_REAL_CONFIG=1 to run against the ambient config.
_cleanup_dirs=()
trap 'rm -rf "${_cleanup_dirs[@]+"${_cleanup_dirs[@]}"}"' EXIT
if [[ "${AI_CONSULTANTS_TEST_REAL_CONFIG:-0}" != "1" ]]; then
    _hermetic_config_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-consultants-test-config.XXXXXX")
    _cleanup_dirs+=("$_hermetic_config_dir")
    while IFS= read -r _key; do
        [[ "$_key" =~ ^[A-Z][A-Z0-9_]*$ ]] && unset "$_key"
    done < <(bash "$SCRIPT_DIR/configure.sh" --show-parameters 2>/dev/null)
    while IFS='=' read -r _key _; do
        [[ "$_key" == _AI_CONSULTANTS_* ]] && unset "$_key"
    done < <(env)
    unset _key
    export AI_CONSULTANTS_CONFIG_DIR="$_hermetic_config_dir"
fi

# jq compile-error guard. Production code often runs jq with 2>/dev/null and a
# fallback, so a filter that does not compile degrades silently instead of
# failing (report.md never rendered the Coverage Union until 5.3.1). Every jq
# call the suites make goes through test_fixtures/jq_compile_guard.sh, which
# records compile errors even when stderr is discarded; any record fails the
# gate below. Set AI_CONSULTANTS_TEST_NO_JQ_GUARD=1 to run without it.
_jq_guard_log=""
if [[ "${AI_CONSULTANTS_TEST_NO_JQ_GUARD:-0}" != "1" ]] && _jq_real=$(command -v jq); then
    _jq_guard_dir=$(mktemp -d "${TMPDIR:-/tmp}/ai-consultants-jq-guard.XXXXXX")
    _cleanup_dirs+=("$_jq_guard_dir")
    cp "$SCRIPT_DIR/test_fixtures/jq_compile_guard.sh" "$_jq_guard_dir/jq"
    chmod +x "$_jq_guard_dir/jq"
    _jq_guard_log="$_jq_guard_dir/compile-errors.log"
    : > "$_jq_guard_log"
    export JQ_GUARD_REAL="$_jq_real" JQ_GUARD_LOG="$_jq_guard_log"
    export PATH="$_jq_guard_dir:$PATH"
fi

C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_BLUE="\033[34m"
C_DIM="\033[2m"

# Discover all test_*.sh scripts. Each runs in its own subprocess (via the
# loop below executing the script), so frameworks with different assert
# naming conventions don't collide.
# Excluded: test_all.sh itself.
suites=()
while IFS= read -r f; do
    suites+=("$f")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'test_*.sh' -type f \
    ! -name 'test_all.sh' \
    | sort)

failed_suites=()
total_pass=0
total_fail=0

echo -e "${C_BLUE}AI Consultants test suite${C_RESET}"
echo -e "${C_DIM}$(date)${C_RESET}"
echo ""

for suite in "${suites[@]}"; do
    name=$(basename "$suite")
    echo -e "─── ${C_BLUE}$name${C_RESET} ───────────────────────────────────────"
    if "$suite"; then
        ((total_pass++)) || true
    else
        ((total_fail++)) || true
        failed_suites+=("$name")
    fi
    echo ""
done

echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "Suites passed: ${C_GREEN}$total_pass${C_RESET} / ${#suites[@]}"
if [[ -n "$_jq_guard_log" && -s "$_jq_guard_log" ]]; then
    echo -e "${C_RED}jq compile errors during the run${C_RESET} (each is a filter that cannot work; callers that silence stderr hide it):"
    cat "$_jq_guard_log"
    failed_suites+=("jq compile-error guard")
    ((total_fail++)) || true
fi
if (( total_fail > 0 )); then
    echo -e "Suites failed: ${C_RED}$total_fail${C_RESET}"
    for s in "${failed_suites[@]}"; do
        echo -e "  ${C_RED}✗${C_RESET} $s"
    done
    exit 1
fi
echo -e "${C_GREEN}All test suites passed.${C_RESET}"
exit 0
