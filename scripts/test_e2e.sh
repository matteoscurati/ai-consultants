#!/bin/bash
# test_e2e.sh - Offline end-to-end integration test for the full consult_all.sh
# pipeline (classify -> route -> collect -> vote/consensus -> report).
#
# Drives consult_all.sh with real CLI-based consultants (Claude, Codex,
# Gemini, Mistral) whose CLI_CMD env vars are pointed at a stub "CLI"
# (test_fixtures/stub_cli.sh) that ignores its args/stdin and prints a valid
# consultant JSON envelope. Everything runs in an isolated temp HOME/XDG tree
# so nothing touches the real config, cache, or session state, and no
# network calls happen.
#
# Usage: ./scripts/test_e2e.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

STUB_CLI="$SCRIPT_DIR/test_fixtures/stub_cli.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

test_full_pipeline() {
    local run_out rc output_dir

    run_out=$(
        HOME="$TEST_TMPDIR/home" \
        XDG_CACHE_HOME="$TEST_TMPDIR/xdg/cache" \
        XDG_STATE_HOME="$TEST_TMPDIR/xdg/state" \
        XDG_DATA_HOME="$TEST_TMPDIR/xdg/data" \
        INVOKING_AGENT=none \
        ENABLE_CLAUDE=true ENABLE_CODEX=true ENABLE_GEMINI=true ENABLE_MISTRAL=true \
        ENABLE_CURSOR=false \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CLAUDE_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" GEMINI_CMD="$STUB_CLI" MISTRAL_CMD="$STUB_CLI" \
        ENABLE_SEMANTIC_CACHE=false \
        ENABLE_SYNTHESIS=false \
        ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false \
        "$SCRIPT_DIR/consult_all.sh" "How should I structure a small web service?" \
        2>"$TEST_TMPDIR/run.err"
    )
    rc=$?

    assert_eq "0" "$rc" "consult_all.sh exits 0"

    # The output directory is printed as the LAST line of stdout.
    output_dir=$(echo "$run_out" | tail -n 1)

    assert_eq "1" "$([[ -d "$output_dir" ]] && echo 1 || echo 0)" \
        "output directory exists ($output_dir)"

    local consultant_json_count=0 f
    while IFS= read -r -d '' f; do
        if jq -e 'has("consultant")' "$f" >/dev/null 2>&1; then
            ((consultant_json_count++)) || true
        fi
    done < <(find "$output_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null)
    assert_eq "1" "$([[ "$consultant_json_count" -ge 3 ]] && echo 1 || echo 0)" \
        "at least 3 consultant response files present (found $consultant_json_count)"

    local report_file=""
    [[ -f "$output_dir/report.md" ]] && report_file="$output_dir/report.md"
    assert_eq "1" "$([[ -n "$report_file" ]] && echo 1 || echo 0)" \
        "report.md exists"

    assert_eq "1" "$([[ -f "$output_dir/optimization_metrics.json" ]] && echo 1 || echo 0)" \
        "optimization_metrics.json exists"

    local success_responses
    success_responses=$(jq -r '.quality_metrics.successful_responses // "MISSING"' \
        "$output_dir/optimization_metrics.json" 2>/dev/null)
    assert_eq "1" "$([[ "$success_responses" != "MISSING" && "$success_responses" != "null" ]] && echo 1 || echo 0)" \
        "optimization_metrics.json records successful_responses (got: $success_responses)"
}

run_test "Test 1: full offline consult_all.sh pipeline with stubbed CLIs" test_full_pipeline

test_summary "test_e2e"
