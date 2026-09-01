#!/bin/bash
# test_preset_selection.sh - Offline host-aware preset selection matrix.
#
# This suite exercises only the static selector: no adapter script, provider
# request, health ping, or full consultation is invoked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1

TMP=$(mktemp -d -t ai_consultants_preset_selection.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
STATIC_CLI="$TMP/static-cli"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$STATIC_CLI"
chmod +x "$STATIC_CLI"
STUB_CLI="$SCRIPT_DIR/test_fixtures/stub_cli.sh"
MISTRAL_STUB="$TMP/mistral-stub"
printf '%s\n' '#!/bin/bash' \
    'if [[ "${1:-}" == "--help" ]]; then' \
    '  echo "--prompt --output --agent --workdir --max-turns builtin: plan VIBE_*"' \
    'else' \
    '  echo '\''{"response":{"summary":"offline"},"confidence":{"score":8}}'\''' \
    'fi' > "$MISTRAL_STUB"
chmod +x "$MISTRAL_STUB"

PRESETS="minimal balanced thorough high-stakes security cost-capped max_quality max-quality medium fast"
HOSTS="unknown codex claude gemini"

_set_all_static_transports() {
    GEMINI_CMD="$STATIC_CLI" CODEX_CMD="$STATIC_CLI" MISTRAL_CMD="$STATIC_CLI"
    KIMI_CMD="$STATIC_CLI" CLAUDE_CMD="$STATIC_CLI" QWEN3_CMD="$STATIC_CLI"
    GROK_CMD="$STATIC_CLI" MINIMAX_CMD="$STATIC_CLI"
    GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false
    QWEN3_USE_API=false GROK_USE_API=false MINIMAX_USE_API=false
    GLM_API_KEY=test-glm DEEPSEEK_API_KEY=test-deepseek
}

_set_one_static_transport() {
    GEMINI_CMD=not-a-static-transport CODEX_CMD=not-a-static-transport
    MISTRAL_CMD=not-a-static-transport KIMI_CMD=not-a-static-transport
    CLAUDE_CMD=not-a-static-transport QWEN3_CMD=not-a-static-transport
    GROK_CMD=not-a-static-transport MINIMAX_CMD="$STATIC_CLI"
    GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false
    QWEN3_USE_API=false GROK_USE_API=false MINIMAX_USE_API=false
    GLM_API_KEY='' DEEPSEEK_API_KEY=''
}

_contains_word() {
    case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

test_host_preset_matrix_with_sufficient_static_transports() {
    local host preset selected promised expected self_name count
    for host in $HOSTS; do
        for preset in $PRESETS; do
            _set_all_static_transports
            INVOKING_AGENT="$host"
            apply_preset "$preset"
            selected=$(select_preset_consultants "$preset" | tr '\n' ' ' | sed 's/ *$//')
            count=$(printf '%s\n' "$selected" | awk '{print NF}')
            promised=$(get_preset_panel_size "$preset")
            expected="$promised"
            # A known host can never fill max_quality's tenth slot because the
            # canonical roster contains only ten consultants and self is barred.
            if [[ "$preset" == "max_quality" || "$preset" == "max-quality" ]]; then
                [[ "$host" != "unknown" ]] && expected=9
            fi
            assert_eq "$expected" "$count" "$host / $preset preserves available preset capacity"

            self_name=$(get_self_consultant_name)
            if [[ -n "$self_name" ]]; then
                assert_exit_failure "$host / $preset never selects its self consultant" \
                    _contains_word "$selected" "$(to_title "$self_name")"
            fi
        done
    done
}

test_host_preset_matrix_with_insufficient_static_transports() {
    local host preset selected promised diagnostic
    for host in $HOSTS; do
        for preset in $PRESETS; do
            _set_one_static_transport
            INVOKING_AGENT="$host"
            apply_preset "$preset"
            selected=$(select_preset_consultants "$preset" | tr '\n' ' ' | sed 's/ *$//')
            assert_eq "MiniMax" "$selected" "$host / $preset selects only the configured fallback"
            promised=$(get_preset_panel_size "$preset")
            diagnostic=$(log_preset_capacity_diagnostic "$preset" "$promised" 1 2>&1)
            assert_contains "promises $promised consultants" "$diagnostic" "$host / $preset reports promised capacity"
            assert_contains "missing capacity: $((promised - 1))" "$diagnostic" "$host / $preset reports missing capacity"
        done
    done
}

test_static_selector_has_no_provider_side_effects() {
    _set_all_static_transports
    INVOKING_AGENT=codex
    apply_preset minimal
    assert_eq "Gemini Mistral" "$(select_preset_consultants minimal | tr '\n' ' ' | sed 's/ *$//')" \
        "static selection fills Codex host's excluded slot in canonical order"
}

test_preset_integration_refills_before_dispatch() {
    local output rc output_dir
    output=$(HOME="$TMP/home" \
        XDG_CACHE_HOME="$TMP/xdg/cache" \
        XDG_STATE_HOME="$TMP/xdg/state" \
        XDG_DATA_HOME="$TMP/xdg/data" \
        INVOKING_AGENT=codex \
        GEMINI_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" MISTRAL_CMD="$MISTRAL_STUB" \
        KIMI_CMD=not-a-static-transport CLAUDE_CMD=not-a-static-transport \
        QWEN3_CMD=not-a-static-transport GROK_CMD=not-a-static-transport \
        MINIMAX_CMD=not-a-static-transport \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false \
        QWEN3_USE_API=false GROK_USE_API=false MINIMAX_USE_API=false \
        GLM_API_KEY='' DEEPSEEK_API_KEY='' \
        ENABLE_SYNTHESIS=false ENABLE_SEMANTIC_CACHE=false ENABLE_HEALTH_GATE=false \
        ENABLE_SMART_ROUTING=false "$SCRIPT_DIR/consult_all.sh" --preset minimal \
        "Offline host-aware preset selection" 2>"$TMP/integration.err")
    rc=$?
    output_dir=$(printf '%s\n' "$output" | tail -n 1)

    assert_eq "0" "$rc" "preset integration exits successfully with static fallback"
    assert_eq "1" "$([[ -s "$output_dir/gemini.json" && -s "$output_dir/mistral.json" ]] && echo 1 || echo 0)" \
        "Codex-hosted minimal preset dispatches primary plus canonical fallback"
    assert_eq "0" "$([[ -e "$output_dir/codex.json" || -e "$output_dir/codex.err" ]] && echo 1 || echo 0)" \
        "Codex host is never dispatched by a preset"
}

test_preset_integration_fails_before_provider_dispatch() {
    local output rc diagnostic
    output=$(HOME="$TMP/capacity-home" \
        XDG_CACHE_HOME="$TMP/capacity-xdg/cache" \
        XDG_STATE_HOME="$TMP/capacity-xdg/state" \
        XDG_DATA_HOME="$TMP/capacity-xdg/data" \
        INVOKING_AGENT=unknown \
        GEMINI_CMD=not-a-static-transport CODEX_CMD=not-a-static-transport \
        MISTRAL_CMD=not-a-static-transport KIMI_CMD=not-a-static-transport \
        CLAUDE_CMD=not-a-static-transport QWEN3_CMD=not-a-static-transport \
        GROK_CMD=not-a-static-transport MINIMAX_CMD="$STATIC_CLI" \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false \
        QWEN3_USE_API=false GROK_USE_API=false MINIMAX_USE_API=false \
        GLM_API_KEY='' DEEPSEEK_API_KEY='' \
        ENABLE_SYNTHESIS=false ENABLE_SEMANTIC_CACHE=false ENABLE_HEALTH_GATE=false \
        ENABLE_SMART_ROUTING=false "$SCRIPT_DIR/consult_all.sh" --preset minimal \
        "Offline insufficient capacity" 2>"$TMP/capacity.err")
    rc=$?
    diagnostic=$(cat "$TMP/capacity.err")

    assert_eq "1" "$rc" "insufficient preset capacity exits before consultation"
    assert_contains "Preset 'minimal' promises 2 consultants, but static transport selection found 1; missing capacity: 1." \
        "$diagnostic" "insufficient preset capacity states promised, selected, and missing"
}

run_test "Test 1: host x preset x sufficient static transport matrix" test_host_preset_matrix_with_sufficient_static_transports
run_test "Test 2: host x preset x insufficient static transport matrix" test_host_preset_matrix_with_insufficient_static_transports
run_test "Test 3: static selector remains side-effect free" test_static_selector_has_no_provider_side_effects
run_test "Test 4: preset integration refills before dispatch" test_preset_integration_refills_before_dispatch
run_test "Test 5: insufficient preset capacity aborts before dispatch" test_preset_integration_fails_before_provider_dispatch

test_summary "preset selection"
