#!/bin/bash
# Offline contract tests for the public mode/preset/strategy registry.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$SCRIPT_DIR/public_registry.sh"
CONSULT="$SCRIPT_DIR/consult_all.sh"
BIN="$REPO_ROOT/bin/ai-consultants"
DOCS="$SCRIPT_DIR/generate_public_docs.sh"

source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$REGISTRY"

TMP=$(mktemp -d -t ai_consultants_public_registry.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

make_adapter_sentinels() {
    local dir="$TMP/no-adapter-bin" name
    mkdir -p "$dir"
    for name in agy codex vibe kimi claude qwen grok mmx curl; do
        printf '#!/bin/bash\nprintf "adapter sentinel invoked: %%s\\n" "$0" >> "%s"\nexit 97\n' \
            "$TMP/adapter-invoked" > "$dir/$name"
        chmod +x "$dir/$name"
    done
    printf '%s\n' "$dir"
}

test_registry_names_are_unique_and_closed() {
    local names aliases name alias preset strategy mode default_count alias_names strategy_names mode_names
    names=$(registry_preset_rows | cut -d'|' -f1)
    assert_eq "$(printf '%s\n' "$names" | sort -u | wc -l | tr -d ' ')" \
        "$(printf '%s\n' "$names" | wc -l | tr -d ' ')" "canonical preset names are unique"
    while IFS='|' read -r name aliases _; do
        assert_eq "$name" "$(registry_canonical_preset "$name")" "$name resolves to itself"
        for alias in $aliases; do
            assert_eq "$name" "$(registry_canonical_preset "$alias")" "$alias resolves to $name"
        done
    done < <(registry_preset_rows)
    alias_names=$(registry_preset_rows | awk -F'|' '{ print $1; if ($2 != "") print $2 }' | tr ' ' '\n' | sed '/^$/d')
    assert_eq "$(printf '%s\n' "$alias_names" | sort -u | wc -l | tr -d ' ')" \
        "$(printf '%s\n' "$alias_names" | wc -l | tr -d ' ')" \
        "canonical preset names and aliases have no cross-collision"
    strategy_names=$(registry_strategy_rows | cut -d'|' -f1)
    assert_eq "$(printf '%s\n' "$strategy_names" | sort -u | wc -l | tr -d ' ')" \
        "$(printf '%s\n' "$strategy_names" | wc -l | tr -d ' ')" "strategy names are unique"
    mode_names=$(registry_mode_rows | cut -d'|' -f1)
    assert_eq "$(printf '%s\n' "$mode_names" | sort -u | wc -l | tr -d ' ')" \
        "$(printf '%s\n' "$mode_names" | wc -l | tr -d ' ')" "mode names are unique"
    assert_exit_failure "unknown preset is closed" registry_canonical_preset unknown
    assert_exit_failure "unknown strategy is closed" registry_strategy_metadata unknown
    assert_exit_failure "unknown mode is closed" registry_mode_metadata unknown
    default_count=$(registry_strategy_rows | awk -F'|' '$3 == "true" { count++ } END { print count + 0 }')
    assert_eq "1" "$default_count" "registry has exactly one default strategy"
    assert_eq "coverage" "$(registry_default_strategy)" "coverage remains the registry default"
}

test_mode_mappings_and_config_default_parity() {
    local mode preset strategy
    while IFS='|' read -r mode preset strategy _; do
        assert_eq "$preset" "$(registry_canonical_preset "$preset")" "$mode references a canonical preset"
        assert_eq "$strategy" "$(registry_strategy_metadata "$strategy" | cut -d'|' -f1)" "$mode references a registered strategy"
        assert_eq "$preset" "$(registry_mode_preset "$mode")" "$mode maps to its documented preset"
        assert_eq "$strategy" "$(registry_mode_strategy "$mode")" "$mode maps to its documented strategy"
        assert_eq "coverage" "$strategy" "$mode defaults to coverage"
    done < <(registry_mode_rows)
    assert_eq "coverage" "$(HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" AI_CONSULTANTS_CONFIG_DIR="$TMP/config" bash -c "source '$SCRIPT_DIR/config.sh'; printf '%s' \"\$DEFAULT_STRATEGY\"")" \
        "config.sh default strategy matches registry"
}

test_registry_only_paths_skip_user_config() {
    local cfg="$TMP/poison-config" sentinel="$TMP/user-config-ran" out adapter_bin
    mkdir -p "$cfg"
    printf 'touch "%s"\n' "$sentinel" > "$cfg/config.sh"
    adapter_bin=$(make_adapter_sentinels)
    out=$(PATH="$adapter_bin:$PATH" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$REGISTRY" --list-presets)
    assert_contains "Available presets:" "$out" "registry listing works without configuration"
    assert_eq "0" "$([[ -e "$sentinel" ]] && echo 1 || echo 0)" "registry listing does not source user config"
    out=$(PATH="$adapter_bin:$PATH" HOME="$TMP/isolated-home" XDG_CONFIG_HOME="$TMP/isolated-xdg/config" \
        XDG_CACHE_HOME="$TMP/isolated-xdg/cache" XDG_STATE_HOME="$TMP/isolated-xdg/state" \
        XDG_DATA_HOME="$TMP/isolated-xdg/data" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$CONSULT" --list-modes)
    assert_contains "fast-check" "$out" "consult CLI routes mode listing through registry"
    assert_eq "0" "$([[ -e "$sentinel" ]] && echo 1 || echo 0)" "consult mode listing does not source user config"
    assert_eq "0" "$([[ -e "$TMP/adapter-invoked" ]] && echo 1 || echo 0)" \
        "registry-only paths never invoke a consultant or network adapter sentinel"
}

test_cli_mode_diagnostics_and_bin_passthrough() {
    local out rc=0
    out=$("$CONSULT" --mode fast-check --preset balanced question 2>&1) || rc=$?
    assert_eq "1" "$rc" "mode/preset conflict exits before consultation"
    assert_contains "cannot be used together" "$out" "mode/preset conflict is clear"
    rc=0; out=$("$CONSULT" --mode 2>&1) || rc=$?
    assert_eq "1" "$rc" "missing mode value fails"
    assert_contains "--mode requires a value" "$out" "missing mode diagnostic is clear"
    rc=0; out=$("$CONSULT" --mode unknown question 2>&1) || rc=$?
    assert_eq "1" "$rc" "unknown mode fails"
    assert_contains "unknown mode 'unknown'" "$out" "unknown mode names the invalid value"
    out=$("$BIN" --list-modes)
    assert_contains "max-coverage" "$out" "npm/bin pass-through exposes registry mode listing"
    out=$("$BIN" help)
    assert_contains "--mode <name>" "$out" "npm/bin help advertises modes"
}

test_early_help_and_value_diagnostics_are_standalone() {
    local out rc=0 option version
    version=$(grep -E '^AI_CONSULTANTS_VERSION=' "$SCRIPT_DIR/config.sh" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    out=$(AI_CONSULTANTS_CONFIG_DIR="$TMP/no-config" "$CONSULT" --help)
    assert_contains "--mode <name>" "$out" "consult help expands registry options instead of printing a literal substitution"
    assert_contains "AI Consultants v$version" "$out" "consult help reads the current release version without sourcing config"
    for option in --preset --strategy --query-file --context-root; do
        rc=0; out=$(AI_CONSULTANTS_CONFIG_DIR="$TMP/no-config" "$CONSULT" "$option" 2>&1) || rc=$?
        assert_eq "1" "$rc" "$option missing value exits cleanly before runtime libraries"
        assert_not_contains "log_error: command not found" "$out" "$option missing value does not call log_error before common.sh"
        assert_contains "requires" "$out" "$option missing value explains the required argument"
    done
}

test_mode_resolution_and_docs_are_deterministic() {
    local before after drift docs_root rc
    assert_eq "fast|coverage" "$(registry_resolve_mode fast-check)" \
        "mode resolution maps fast-check to fast plus coverage"
    assert_eq "fast|compare_only" "$(registry_resolve_mode fast-check compare_only)" \
        "explicit strategy overrides the mode default without runtime dispatch"
    assert_exit_failure "mode resolution rejects unknown explicit strategy" \
        registry_resolve_mode fast-check unknown
    "$DOCS" --check
    before=$(cksum "$REPO_ROOT/README.md" "$REPO_ROOT/references/details.md" "$REPO_ROOT/SKILL.md")
    "$DOCS" --check
    after=$(cksum "$REPO_ROOT/README.md" "$REPO_ROOT/references/details.md" "$REPO_ROOT/SKILL.md")
    assert_eq "$before" "$after" "documentation check is read-only"
    docs_root="$TMP/docs-root"
    mkdir -p "$docs_root/references"
    cp "$REPO_ROOT/README.md" "$docs_root/README.md"
    cp "$REPO_ROOT/references/details.md" "$docs_root/references/details.md"
    cp "$REPO_ROOT/SKILL.md" "$docs_root/SKILL.md"
    sed 's/`fast-check`/`fast-check-drift`/' "$docs_root/README.md" > "$TMP/README-drift"
    mv "$TMP/README-drift" "$docs_root/README.md"
    rc=0; drift=$(AI_CONSULTANTS_DOC_ROOT="$docs_root" "$DOCS" --check 2>&1) || rc=$?
    assert_eq "1" "$rc" "documentation check fails on generated snapshot drift"
    assert_contains "Generated public registry documentation is stale" "$drift" "drift check names stale generated docs"
}

make_doc_fixture() {
    local root="$1"
    mkdir -p "$root/references"
    cp "$REPO_ROOT/README.md" "$root/README.md"
    cp "$REPO_ROOT/references/details.md" "$root/references/details.md"
    cp "$REPO_ROOT/SKILL.md" "$root/SKILL.md"
}

test_doc_marker_ordering_is_fail_closed() {
    local root out rc=0
    root="$TMP/docs-order"
    make_doc_fixture "$root"
    sed -e 's/public-registry:start/public-registry:swap/' \
        -e 's/public-registry:end/public-registry:start/' \
        -e 's/public-registry:swap/public-registry:end/' \
        "$root/README.md" > "$TMP/README-order"
    mv "$TMP/README-order" "$root/README.md"
    out=$(AI_CONSULTANTS_DOC_ROOT="$root" "$DOCS" --check 2>&1) || rc=$?
    assert_eq "1" "$rc" "doc generator rejects an end marker before its start"
    assert_contains "marker ordering invalid" "$out" "marker-order diagnostic is explicit"

    root="$TMP/docs-unterminated"
    make_doc_fixture "$root"
    sed 's/public-registry:end/public-registry:missing-end/' "$root/README.md" > "$TMP/README-unterminated"
    mv "$TMP/README-unterminated" "$root/README.md"
    rc=0; out=$(AI_CONSULTANTS_DOC_ROOT="$root" "$DOCS" --check 2>&1) || rc=$?
    assert_eq "1" "$rc" "doc generator rejects an unterminated generated section"
    assert_contains "Documentation markers invalid" "$out" "unterminated-section diagnostic is explicit"
}

test_explicit_opt_outs_survive_presets_and_fallback() {
    local out adapter_bin
    adapter_bin=$(make_adapter_sentinels)
    out=$(PATH="$adapter_bin:$PATH" HOME="$TMP/optout-home" XDG_CONFIG_HOME="$TMP/optout-xdg/config" \
        XDG_CACHE_HOME="$TMP/optout-xdg/cache" XDG_STATE_HOME="$TMP/optout-xdg/state" \
        XDG_DATA_HOME="$TMP/optout-xdg/data" AI_CONSULTANTS_CONFIG_DIR="$TMP/optout-config" \
        ENABLE_GLM=false GLM_API_KEY=test-key GEMINI_CMD=missing-gemini CODEX_CMD=missing-codex \
        MISTRAL_CMD=missing-mistral KIMI_CMD=missing-kimi CLAUDE_CMD=missing-claude \
        QWEN3_CMD=missing-qwen GROK_CMD=missing-grok MINIMAX_CMD=missing-minimax \
        bash -c "source '$SCRIPT_DIR/lib/common.sh'; apply_preset max_quality; printf '%s|%s|%s' \"\$ENABLE_GLM\" \"\${_AI_CONSULTANTS_PRESET_OPTOUT_ENABLE_GLM:-false}\" \"\$(select_preset_consultants max_quality | tr '\\n' ' ')\"")
    assert_match '^false\|true\|[[:space:]]*$' "$out" \
        "explicit GLM opt-out survives max_quality and is excluded from static fallback"
    assert_eq "0" "$([[ -e "$TMP/adapter-invoked" ]] && echo 1 || echo 0)" \
        "opt-out contract test does not invoke an adapter sentinel"
}

run_test "Test 1: registry uniqueness and closed mappings" test_registry_names_are_unique_and_closed
run_test "Test 2: mode mappings and config default parity" test_mode_mappings_and_config_default_parity
run_test "Test 3: registry-only commands avoid user config" test_registry_only_paths_skip_user_config
run_test "Test 4: mode diagnostics and npm/bin pass-through" test_cli_mode_diagnostics_and_bin_passthrough
run_test "Test 5: early help and diagnostics are standalone" test_early_help_and_value_diagnostics_are_standalone
run_test "Test 6: mode resolution and generated-doc determinism" test_mode_resolution_and_docs_are_deterministic
run_test "Test 7: explicit opt-outs survive presets and fallback" test_explicit_opt_outs_survive_presets_and_fallback
run_test "Test 8: generated-doc marker ordering is fail-closed" test_doc_marker_ordering_is_fail_closed

test_summary "public registry"
