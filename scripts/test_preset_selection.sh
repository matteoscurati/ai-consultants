#!/bin/bash
# test_preset_selection.sh - Offline host-aware preset selection matrix.
#
# This suite exercises only the static selector: no adapter script, provider
# request, health ping, or full consultation is invoked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT=$(mktemp -d -t ai_consultants_preset_selection.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Source common/config only after isolating configuration and neutralizing any
# credentials, modes, or custom ENABLE_* flags inherited from the developer.
export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$TEST_ROOT/xdg/config"
export XDG_CACHE_HOME="$TEST_ROOT/xdg/cache"
export XDG_STATE_HOME="$TEST_ROOT/xdg/state"
export XDG_DATA_HOME="$TEST_ROOT/xdg/data"
export AI_CONSULTANTS_CONFIG_DIR="$TEST_ROOT/config"
while IFS='=' read -r _ambient_var _; do
    unset "$_ambient_var"
done < <(env | sed -n '/^ENABLE_[A-Z0-9_]*=/s/=.*//p; /^[A-Z0-9_]*_API_URL=/s/=.*//p')
unset GEMINI_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY MISTRAL_API_KEY QWEN3_API_KEY
unset GLM_API_KEY GROK_API_KEY XAI_API_KEY DEEPSEEK_API_KEY MINIMAX_API_KEY
unset GEMINI_USE_API CODEX_USE_API CLAUDE_USE_API MISTRAL_USE_API QWEN3_USE_API
unset GROK_USE_API MINIMAX_USE_API DEFAULT_PRESET

source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1

TMP="$TEST_ROOT"
STATIC_CLI="$TMP/static-cli"
STATIC_SENTINEL="$TMP/static-cli-invoked"
export STATIC_SENTINEL
printf '%s\n' '#!/bin/bash' 'printf invoked > "$STATIC_SENTINEL"' 'exit 99' > "$STATIC_CLI"
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
HOSTS="unknown codex claude gemini mistral kimi qwen3"

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
    local host preset selected raw effective self_name count
    for host in $HOSTS; do
        for preset in $PRESETS; do
            _set_all_static_transports
            INVOKING_AGENT="$host"
            apply_preset "$preset"
            selected=$(select_preset_consultants "$preset" | tr '\n' ' ' | sed 's/ *$//')
            count=$(printf '%s\n' "$selected" | awk '{print NF}')
            raw=$(get_preset_panel_size "$preset")
            effective=$(get_effective_preset_panel_size "$preset")
            assert_eq "$effective" "$count" "$host / $preset preserves effective preset capacity"
            if [[ "$preset" == "max_quality" || "$preset" == "max-quality" ]]; then
                if [[ "$host" == "unknown" ]]; then
                    assert_eq "$raw" "$effective" "$host / $preset keeps raw max_quality target"
                else
                    assert_eq "9" "$effective" "$host / $preset makes max_quality attainable after self-exclusion"
                fi
            fi

            self_name=$(get_self_consultant_name)
            if [[ -n "$self_name" ]]; then
                assert_exit_failure "$host / $preset never selects its self consultant" \
                    _contains_word "$selected" "$(to_title "$self_name")"
            fi
        done
    done
}

test_host_preset_matrix_with_insufficient_static_transports() {
    local host preset selected raw effective diagnostic
    for host in $HOSTS; do
        for preset in $PRESETS; do
            _set_one_static_transport
            INVOKING_AGENT="$host"
            apply_preset "$preset"
            selected=$(select_preset_consultants "$preset" | tr '\n' ' ' | sed 's/ *$//')
            assert_eq "MiniMax" "$selected" "$host / $preset selects only the configured fallback"
            raw=$(get_preset_panel_size "$preset")
            effective=$(get_effective_preset_panel_size "$preset")
            diagnostic=$(log_preset_capacity_diagnostic "$preset" "$raw" "$effective" 1 2>&1)
            assert_contains "promises $raw consultants" "$diagnostic" "$host / $preset reports raw promised capacity"
            assert_contains "effective target: $effective" "$diagnostic" "$host / $preset reports host-aware capacity"
            assert_contains "missing capacity: $((effective - 1))" "$diagnostic" "$host / $preset reports missing capacity"
        done
    done
}

test_static_selector_has_no_provider_side_effects() {
    _set_all_static_transports
    INVOKING_AGENT=codex
    apply_preset minimal
    assert_eq "Gemini Mistral" "$(select_preset_consultants minimal | tr '\n' ' ' | sed 's/ *$//')" \
        "static selection fills Codex host's excluded slot in canonical order"
    assert_eq "0" "$([[ -e "$STATIC_SENTINEL" ]] && echo 1 || echo 0)" \
        "static selection never invokes a configured CLI"
}

test_host_aliases_are_fail_closed() {
    local self_name
    INVOKING_AGENT=codex_cli; self_name=$(get_self_consultant_name)
    assert_eq "CODEX" "$self_name" "codex_cli alias remains self-excluded"
    INVOKING_AGENT=claude_code; self_name=$(get_self_consultant_name)
    assert_eq "CLAUDE" "$self_name" "claude_code alias remains self-excluded"
    INVOKING_AGENT=qwen_code; self_name=$(get_self_consultant_name)
    assert_eq "QWEN3" "$self_name" "qwen_code alias remains self-excluded"
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
    assert_contains "Preset 'minimal' promises 2 consultants (effective target: 2 after host self-exclusion), but static transport selection found 1; missing capacity: 1." \
        "$diagnostic" "insufficient preset capacity states promised, selected, and missing"
}

test_zero_static_transport_has_clean_capacity_diagnostic() {
    local output rc diagnostic
    output=$(HOME="$TMP/zero-home" \
        XDG_CACHE_HOME="$TMP/zero-xdg/cache" XDG_STATE_HOME="$TMP/zero-xdg/state" \
        XDG_DATA_HOME="$TMP/zero-xdg/data" AI_CONSULTANTS_CONFIG_DIR="$TMP/zero-config" \
        INVOKING_AGENT=unknown GEMINI_CMD=not-a-static-transport CODEX_CMD=not-a-static-transport \
        MISTRAL_CMD=not-a-static-transport KIMI_CMD=not-a-static-transport \
        CLAUDE_CMD=not-a-static-transport QWEN3_CMD=not-a-static-transport \
        GROK_CMD=not-a-static-transport MINIMAX_CMD=not-a-static-transport \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false QWEN3_USE_API=false \
        GROK_USE_API=false MINIMAX_USE_API=false GLM_API_KEY='' DEEPSEEK_API_KEY='' \
        ENABLE_SYNTHESIS=false ENABLE_SEMANTIC_CACHE=false ENABLE_HEALTH_GATE=false \
        ENABLE_SMART_ROUTING=false "$SCRIPT_DIR/consult_all.sh" --preset minimal \
        "Offline zero static capacity" 2>"$TMP/zero-capacity.err")
    rc=$?
    diagnostic=$(cat "$TMP/zero-capacity.err")

    assert_eq "1" "$rc" "zero static transports abort before consultation"
    assert_contains "static transport selection found 0; missing capacity: 2." "$diagnostic" \
        "zero static transports report clean capacity guidance"
    assert_not_contains "unbound variable" "$diagnostic" "zero static transports avoid empty-array nounset errors"
}

test_custom_agent_can_satisfy_preset_capacity() {
    local output rc output_dir diagnostic
    output=$(HOME="$TMP/custom-home" \
        XDG_CACHE_HOME="$TMP/custom-xdg/cache" XDG_STATE_HOME="$TMP/custom-xdg/state" \
        XDG_DATA_HOME="$TMP/custom-xdg/data" AI_CONSULTANTS_CONFIG_DIR="$TMP/custom-config" \
        INVOKING_AGENT=codex GEMINI_CMD="$STUB_CLI" CODEX_CMD=not-a-static-transport \
        MISTRAL_CMD=not-a-static-transport KIMI_CMD=not-a-static-transport \
        CLAUDE_CMD=not-a-static-transport QWEN3_CMD=not-a-static-transport \
        GROK_CMD=not-a-static-transport MINIMAX_CMD=not-a-static-transport \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false QWEN3_USE_API=false \
        GROK_USE_API=false MINIMAX_USE_API=false GLM_API_KEY='' DEEPSEEK_API_KEY='' \
        ENABLE_TESTCUSTOM=true TESTCUSTOM_API_URL=file:///dev/null MAX_RETRIES=1 RETRY_DELAY_SECONDS=0 \
        ENABLE_SYNTHESIS=false ENABLE_SEMANTIC_CACHE=false ENABLE_HEALTH_GATE=false \
        ENABLE_SMART_ROUTING=false "$SCRIPT_DIR/consult_all.sh" --preset minimal \
        "Offline custom capacity" 2>"$TMP/custom.err")
    rc=$?
    output_dir=$(printf '%s\n' "$output" | tail -n 1)
    diagnostic=$(cat "$TMP/custom.err")

    assert_eq "0" "$rc" "configured custom agent satisfies preset capacity"
    assert_not_contains "missing capacity" "$diagnostic" "custom agent is appended before preset capacity check"
    assert_eq "1" "$([[ -e "$output_dir/testcustom.err" ]] && echo 1 || echo 0)" \
        "configured custom agent remains part of the selected panel"
}

test_health_gate_rechecks_effective_preset_target() {
    local output rc diagnostic
    local health_fail="$TMP/mistral-health-fail"
    printf '%s\n' '#!/bin/bash' \
        'if [[ "${1:-}" == "--help" ]]; then' \
        '  echo "--prompt --output --agent --workdir --max-turns builtin: plan VIBE_*"' \
        'fi' \
        'exit 1' > "$health_fail"
    chmod +x "$health_fail"

    output=$(HOME="$TMP/health-home" \
        XDG_CACHE_HOME="$TMP/health-xdg/cache" XDG_STATE_HOME="$TMP/health-xdg/state" \
        XDG_DATA_HOME="$TMP/health-xdg/data" AI_CONSULTANTS_CONFIG_DIR="$TMP/health-config" \
        INVOKING_AGENT=codex GEMINI_CMD="$STUB_CLI" CODEX_CMD=not-a-static-transport \
        MISTRAL_CMD="$health_fail" KIMI_CMD=not-a-static-transport CLAUDE_CMD=not-a-static-transport \
        QWEN3_CMD=not-a-static-transport GROK_CMD=not-a-static-transport MINIMAX_CMD=not-a-static-transport \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false QWEN3_USE_API=false \
        GROK_USE_API=false MINIMAX_USE_API=false GLM_API_KEY='' DEEPSEEK_API_KEY='' \
        MAX_RETRIES=1 RETRY_DELAY_SECONDS=0 HEALTH_GATE_TIMEOUT=5 ENABLE_SYNTHESIS=false \
        ENABLE_SEMANTIC_CACHE=false ENABLE_HEALTH_GATE=true ENABLE_SMART_ROUTING=false \
        "$SCRIPT_DIR/consult_all.sh" --preset minimal "Offline health prune" 2>"$TMP/health.err")
    rc=$?
    diagnostic=$(cat "$TMP/health.err")

    assert_eq "1" "$rc" "health-pruned preset aborts before Round 1"
    assert_contains "static transport selection found 1; missing capacity: 1." "$diagnostic" \
        "health-pruned preset reuses actionable capacity diagnostic"
}

run_test "Test 1: host x preset x sufficient static transport matrix" test_host_preset_matrix_with_sufficient_static_transports
run_test "Test 2: host x preset x insufficient static transport matrix" test_host_preset_matrix_with_insufficient_static_transports
run_test "Test 3: static selector remains side-effect free" test_static_selector_has_no_provider_side_effects
run_test "Test 4: invoking-host aliases remain fail-closed" test_host_aliases_are_fail_closed
run_test "Test 5: preset integration refills before dispatch" test_preset_integration_refills_before_dispatch
run_test "Test 6: insufficient preset capacity aborts before dispatch" test_preset_integration_fails_before_provider_dispatch
run_test "Test 7: zero static capacity is nounset-safe" test_zero_static_transport_has_clean_capacity_diagnostic
run_test "Test 8: configured custom agent can satisfy capacity" test_custom_agent_can_satisfy_preset_capacity
run_test "Test 9: health gate rechecks preset capacity" test_health_gate_rechecks_effective_preset_target

test_summary "preset selection"
