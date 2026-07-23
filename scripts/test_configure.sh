#!/usr/bin/env bash
# test_configure.sh - Public configurator and configuration-contract tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin/ai-consultants"

# No test here may inherit an ambient transport switch. config.sh auto-resolves
# GEMINI_USE_API / MINIMAX_USE_API and *exports* them, and configure reads any
# ambient value as a deliberate user pin (has_explicit_value) — so a caller that
# sourced config.sh first would pin every transport and defeat auto-detection.
# scripts/release.sh does exactly that: it sources lib/common.sh (-> config.sh)
# before running `npm test`, so without this the suite passes from a clean shell
# and fails only under the release gate. Unset here rather than per-invocation:
# these are the only two parameters config.sh exports that configure consumes,
# but the whole switchable set is cleared so a future auto-resolution (as
# MINIMAX gained in v2.21) cannot silently reintroduce the hole. Same class as
# the v2.21.0 test_user_config.sh hermeticity fix.
unset GEMINI_USE_API CODEX_USE_API CLAUDE_USE_API \
      MISTRAL_USE_API QWEN3_USE_API MINIMAX_USE_API

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP=$(mktemp -d -t ai_consultants_configure_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    ((checked++)) || true
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: $message"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: $message"
        echo "         missing: '$needle'"
        ((failed++)) || true
    fi
}

read_env() {
    local file="$1" key="$2"
    sed -nE "s/^${key}=(.*)$/\\1/p" "$file" \
        | sed 's/[[:space:]]# ai-consultants:auto$//' | tail -1
}

clean_path() {
    printf '%s' "$TMP/bin:/usr/bin:/bin"
}

make_stub() {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$1"
    chmod +x "$TMP/bin/$1"
}

# Scrub the whole accepted-parameter surface, not just the secrets.
# configure's has_explicit_value reads ANY ambient value as a deliberate user
# pin, so every setting config.sh exports leaks into the invocations below. The
# nine API keys were scrubbed but the settings were not, so with config.sh
# sourced first -- scripts/release.sh does exactly that before `npm test` --
# an exported DEFAULT_PRESET overrode the value the preservation tests write
# into the file they are asserting on (Tests 6 and 10). Derived from configure's
# own `--show-parameters` contract so the scrub set tracks the template rather
# than drifting into the same staleness.
CLEAN_ENV_ARGS=()
while IFS= read -r _param; do
    [[ -n "$_param" ]] && CLEAN_ENV_ARGS+=(-u "$_param")
done < <("$BIN" configure --show-parameters)
if [[ ${#CLEAN_ENV_ARGS[@]} -eq 0 ]]; then
    echo "FATAL: could not read configure --show-parameters; env scrub would be a no-op" >&2
    exit 1
fi

run_clean_configure() {
    env "${CLEAN_ENV_ARGS[@]}" \
        PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$1" \
        "$BIN" configure "${@:2}"
}

test_public_route_and_help() {
    local out
    out=$($BIN help)
    assert_contains "$out" "ai-consultants configure [options]" \
        "public help exposes configure"
    out=$($BIN configure --help)
    assert_contains "$out" "--set KEY=VALUE" \
        "configure subcommand routes to the maintained configurator"
}

test_template_covers_config_contract() {
    local declared="$TMP/declared" runtime="$TMP/runtime" supported="$TMP/supported" missing file
    sed -nE \
        -e 's/^[A-Z][A-Z0-9_]*="\$\{([A-Z][A-Z0-9_]*):-.*/\1/p' \
        -e 's/^([A-Z][A-Z0-9_]*)=.*/\1/p' \
        "$SCRIPT_DIR/config.sh" \
        | grep -Ev '^(AI_CONSULTANTS_VERSION|ALL_CONSULTANTS|CLI_CONSULTANTS|API_CONSULTANTS)$' \
        | sort -u > "$declared"
    : > "$runtime"
    while IFS= read -r file; do
        grep -Eho '\$\{[A-Z][A-Z0-9_]*:[-=]' "$file" 2>/dev/null || true
    done < <(find "$SCRIPT_DIR" -type f -name '*.sh' \
        ! -name 'test_*.sh' ! -path '*/test_fixtures/*' ! -path '*/experiment/*' | sort) \
        | sed -E 's/^\$\{//; s/:[-=]$//' \
        | grep -Ev '^(AFFINITY_DEFAULT|AI_CONSULTANTS_CONFIG_DIR|AI_CONSULTANTS_DIR|AI_CONSULTANTS_INSTALL_DEFINE_ONLY|AI_CONSULTANTS_REPO|AI_CONSULTANTS_VERSION|CONTEXT_SIZE|CURRENT_COST|FORCE|HOME|ORCH_SHAPE|ORCHESTRATION_SELECT_WINNER|PIP_PKG|PRESET|QUERY_COMPLEXITY|QUERY_INTENT|QUESTION|QUESTION_CATEGORY|QUORUM_ATTEMPTED|QUORUM_MIN_EFF|QUORUM_OUTCOME|ROOT|SKIP_GATE|STANCE_OPTIONS_PROMPT|SUCCESS_COUNT|SYNTHESIS_STRATEGY|TMPDIR|VAR|XDG_CONFIG_HOME)$' \
        | sort -u > "$runtime"
    sort -u "$declared" "$runtime" -o "$declared"
    $BIN configure --show-parameters | sort -u > "$supported"
    missing=$(comm -23 "$declared" "$supported")
    assert_eq "" "$missing" \
        "every persistent config.sh parameter is accepted by configure --set"
    assert_contains "$(cat "$supported")" "GEMINI_API_KEY" \
        "runtime Gemini credential is covered"
    if grep -q '^GOOGLE_API_KEY$' "$supported"; then
        assert_eq "absent" "present" "obsolete GOOGLE_API_KEY must not be advertised"
    else
        assert_eq "absent" "absent" "obsolete GOOGLE_API_KEY is not advertised"
    fi
}

test_set_drives_detection_with_last_value_winning() {
    local cfg="$TMP/set-detection"
    run_clean_configure "$cfg" --force \
        --set GEMINI_USE_API=false \
        --set GEMINI_USE_API=true \
        --set GEMINI_API_KEY=secret-gemini \
        --set GLM_API_KEY=secret-glm \
        --set CODEX_CMD=missing-codex-command \
        --set ENABLE_GLM=false >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" GEMINI_USE_API)" "last transport --set wins"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "transport and key enable Gemini coherently"
    assert_eq "secret-gemini" "$(read_env "$cfg/.env" GEMINI_API_KEY)" "transport key is persisted"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_CODEX)" "CLI command override participates in detection"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GLM)" "final ENABLE override wins over API-only detection"

    cfg="$TMP/set-empty"
    run_clean_configure "$cfg" --force --set GEMINI_USE_API=true --set GEMINI_API_KEY= >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" GEMINI_USE_API)" "forced API transport remains selected"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "empty forced API key disables Gemini"
}

test_export_values_are_preserved() {
    local cfg="$TMP/export-preserve"
    mkdir -p "$cfg"
    printf '%s\n' 'export DEFAULT_PRESET=security' > "$cfg/.env"
    run_clean_configure "$cfg" >/dev/null
    assert_eq "security" "$(read_env "$cfg/.env" DEFAULT_PRESET)" "export-prefixed value survives configure"
}

test_auto_transport_provenance_and_pins() {
    local cfg="$TMP/provenance" cli_dir="$TMP/provenance-bin"
    mkdir -p "$cli_dir"
    printf '#!/bin/sh\nexit 0\n' > "$cli_dir/agy"
    chmod +x "$cli_dir/agy"
    env -u GEMINI_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY \
        -u MISTRAL_API_KEY -u QWEN3_API_KEY -u MINIMAX_API_KEY \
        -u GLM_API_KEY -u GROK_API_KEY -u DEEPSEEK_API_KEY \
        PATH="$cli_dir:/usr/bin:/bin" AI_CONSULTANTS_CONFIG_DIR="$cfg" \
        "$BIN" configure --force >/dev/null
    assert_eq "false" "$(read_env "$cfg/.env" GEMINI_USE_API)" "installed CLI initially selects CLI mode"
    assert_contains "$(grep '^GEMINI_USE_API=' "$cfg/.env")" "# ai-consultants:auto" \
        "auto-detected transport records provenance"
    GEMINI_API_KEY=added-later PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" \
        "$BIN" configure >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" GEMINI_USE_API | sed 's/[[:space:]]#.*//')" \
        "managed transport adapts when the CLI disappears and a key is added"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "adapted API transport enables Gemini"

    cfg="$TMP/user-pin"
    mkdir -p "$cfg"
    printf '%s\n' 'GEMINI_USE_API=false' 'GEMINI_API_KEY=present' > "$cfg/.env"
    run_clean_configure "$cfg" >/dev/null
    assert_eq "false" "$(read_env "$cfg/.env" GEMINI_USE_API)" "unmarked user transport remains pinned"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "pinned CLI mode without CLI remains disabled"
}

test_metadata_and_dry_run_are_side_effect_free() {
    local cfg="$TMP/not-created" out
    out=$(env -u HOME -u XDG_CONFIG_HOME -u AI_CONSULTANTS_CONFIG_DIR "$BIN" configure --show-parameters)
    assert_contains "$out" "DEFAULT_PRESET" "parameter listing does not require an output directory"
    out=$(GEMINI_API_KEY=never-print-this PATH="$(clean_path)" \
        AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" configure --dry-run)
    assert_contains "$out" "GEMINI_API_KEY=<redacted>" "dry-run redacts credentials"
    if [[ "$out" == *"never-print-this"* ]]; then
        assert_eq "redacted" "leaked" "dry-run never exposes credential values"
    else
        assert_eq "redacted" "redacted" "dry-run never exposes credential values"
    fi
    assert_eq "false" "$([[ -e "$cfg" ]] && echo true || echo false)" "dry-run creates no config directory"
}

test_symlinks_and_noninteractive_aliases() {
    local cfg="$TMP/symlink" target="$TMP/target" rc=0 out
    mkdir -p "$cfg"
    printf '%s\n' 'DEFAULT_PRESET=balanced' > "$target"
    ln -s "$target" "$cfg/.env"
    out=$(run_clean_configure "$cfg" 2>&1) || rc=$?
    assert_eq "1" "$rc" "configure refuses a symlinked output file"
    assert_contains "$out" "symlink" "symlink refusal is explained"
    run_clean_configure "$TMP/noninteractive" --force --non-interactive </dev/null >/dev/null
    assert_eq "true" "$([[ -f "$TMP/noninteractive/.env" ]] && echo true || echo false)" \
        "non-interactive alias completes without reading stdin"
}

test_auto_detects_complete_roster_truthfully() {
    make_stub codex
    make_stub kimi
    local cfg="$TMP/auto"
    run_clean_configure "$cfg" --force >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_CODEX)" "installed Codex is enabled"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_KIMI)" "installed Kimi is enabled"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "missing Gemini is disabled"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_MINIMAX)" "missing MiniMax is disabled"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GROK)" "keyless Grok is disabled"
}

test_auto_selects_api_when_cli_is_missing() {
    local cfg="$TMP/api"
    GEMINI_API_KEY="secret-gemini" PATH="$(clean_path)" \
        AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" configure --force >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_GEMINI)" \
        "Gemini key enables Gemini without agy"
    assert_eq "true" "$(read_env "$cfg/.env" GEMINI_USE_API)" \
        "Gemini key selects API transport when agy is missing"
    assert_eq "secret-gemini" "$(read_env "$cfg/.env" GEMINI_API_KEY)" \
        "Gemini key is persisted"
}

test_set_covers_advanced_parameters() {
    local cfg="$TMP/set"
    run_clean_configure "$cfg" --force \
        --set ENABLE_SYNTHESIS=false \
        --set ENABLE_SMART_ROUTING=true \
        --set CHUNK_OVERLAP_LINES=9 >/dev/null
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_SYNTHESIS)" "--set overrides a core feature"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_SMART_ROUTING)" "--set overrides routing"
    assert_eq "9" "$(read_env "$cfg/.env" CHUNK_OVERLAP_LINES)" "--set overrides an advanced knob"
}

test_existing_values_are_preserved_and_backed_up() {
    local cfg="$TMP/preserve" perms
    mkdir -p "$cfg"
    printf '%s\n' 'GROK_API_KEY=keep-secret' 'DEFAULT_PRESET=security' > "$cfg/.env"
    chmod 600 "$cfg/.env"
    run_clean_configure "$cfg" >/dev/null
    assert_eq "keep-secret" "$(read_env "$cfg/.env" GROK_API_KEY)" "existing secret is preserved"
    assert_eq "security" "$(read_env "$cfg/.env" DEFAULT_PRESET)" "existing setting is preserved"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_GROK)" "preserved API key enables its consultant"
    local backups
    backups=$(find "$cfg" -maxdepth 1 -name '.env.backup.*' | wc -l | tr -d ' ')
    assert_eq "1" "$backups" "existing config receives a timestamped backup"
    perms=$(stat -c '%a' "$cfg/.env" 2>/dev/null || stat -f '%Lp' "$cfg/.env" 2>/dev/null || echo "?")
    assert_eq "600" "$perms" "generated config remains private"
}

test_unknown_parameter_is_rejected() {
    local rc=0 out
    out=$(run_clean_configure "$TMP/reject" --set OLLAMA_MODEL=obsolete 2>&1) || rc=$?
    assert_eq "1" "$rc" "unknown or removed parameters fail closed"
    assert_contains "$out" "unsupported parameter: OLLAMA_MODEL" "rejection explains the invalid parameter"
}

test_advanced_defaults_match_runtime() {
    local cfg="$TMP/defaults"
    run_clean_configure "$cfg" --force >/dev/null
    assert_eq "10" "$(read_env "$cfg/.env" SYNTH_MAX)" \
        "synthesis collection limit matches synthesize.sh"
    assert_eq "8" "$(read_env "$cfg/.env" MIN_IDENTIFIER_LENGTH)" \
        "symbol compression threshold matches symbol_map.sh"
    assert_eq "" "$(read_env "$cfg/.env" TASTE_JUDGE_CMD)" \
        "external taste judge remains opt-in"
    assert_eq "claude" "$(read_env "$cfg/.env" JUDGE_CLI)" \
        "built-in taste judge defaults to Claude"
}

test_interactive_keeps_values() {
    local cfg="$TMP/interactive-keep" out rc=0
    make_stub codex
    out=$({ printf 'n\n'; printf '\n%.0s' {1..30}; } | env -u GEMINI_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY \
        -u MISTRAL_API_KEY -u QWEN3_API_KEY -u MINIMAX_API_KEY -u GLM_API_KEY -u GROK_API_KEY -u DEEPSEEK_API_KEY \
        PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" configure --interactive --force 2>&1) || rc=$?
    assert_eq "0" "$rc" "all-Enter interactive input exits 0 (BUG 1 regression)"
    assert_eq "true" "$([[ -f "$cfg/.env" ]] && echo true || echo false)" "interactive mode writes the config file"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_CODEX)" \
        "detected value (installed codex stub) survives Enter-only input"
}

test_interactive_accepts_input() {
    local cfg="$TMP/interactive-input" rc=0
    { printf 'n\nfalse\n'; printf '\n%.0s' {1..30}; } | env -u GEMINI_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY \
        -u MISTRAL_API_KEY -u QWEN3_API_KEY -u MINIMAX_API_KEY -u GLM_API_KEY -u GROK_API_KEY -u DEEPSEEK_API_KEY \
        PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" configure --interactive --force >/dev/null 2>&1 || rc=$?
    assert_eq "0" "$rc" "interactive mode with a typed value still exits 0"
    assert_eq "false" "$(read_env "$cfg/.env" ENABLE_GEMINI)" "typed value overrides the prompted key"
}

test_init_then_configure_regression() {
    local cfg="$TMP/init-then-configure" out="$TMP/init-then-configure.out"
    env -u GEMINI_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u MISTRAL_API_KEY -u QWEN3_API_KEY -u MINIMAX_API_KEY \
        -u GLM_API_KEY -u GROK_API_KEY -u DEEPSEEK_API_KEY \
        PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init >/dev/null
    OPENAI_API_KEY=sk-test CODEX_CMD=not-installed PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" \
        "$BIN" configure --dry-run > "$out" 2>/dev/null
    assert_eq "true" "$(read_env "$out" ENABLE_CODEX)" \
        "init then configure still enables Codex when only an API key is available (BUG 2 regression)"
    assert_eq "true" "$(read_env "$out" CODEX_USE_API)" \
        "init then configure still resolves Codex to API when its CLI is absent (BUG 2 regression)"
}

test_explicit_pin_survives_init() {
    local cfg="$TMP/pin-survives-init"
    env -u GEMINI_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u MISTRAL_API_KEY -u QWEN3_API_KEY -u MINIMAX_API_KEY \
        -u GLM_API_KEY -u GROK_API_KEY -u DEEPSEEK_API_KEY \
        PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init >/dev/null
    printf '\nCODEX_USE_API=true\n' >> "$cfg/.env"
    OPENAI_API_KEY=sk-test CODEX_CMD=not-installed PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" \
        "$BIN" configure --force >/dev/null
    assert_eq "true" "$(read_env "$cfg/.env" CODEX_USE_API)" \
        "an explicit uncommented pin in the user .env still wins after init"
}

test_cli_first_preserved() {
    local cfg="$TMP/cli-first"
    make_stub codex
    OPENAI_API_KEY=sk-test PATH="$(clean_path)" AI_CONSULTANTS_CONFIG_DIR="$cfg" \
        "$BIN" configure --force >/dev/null
    assert_eq "false" "$(read_env "$cfg/.env" CODEX_USE_API)" \
        "installed CLI wins over API transport even when an API key is present (CLI-first invariant)"
    assert_eq "true" "$(read_env "$cfg/.env" ENABLE_CODEX)" "CLI-selected Codex is enabled"
}

test_backups_are_unique_within_one_second() {
    local cfg="$TMP/backup-collision"
    mkdir -p "$cfg" "$TMP/bin"
    printf 'DEFAULT_PRESET=original\n' > "$cfg/.env"

    # Freeze the clock so both runs resolve to the same second. Without this the
    # collision is unreachable from a test: a real configure run takes longer
    # than the backup name's one-second granularity, so sequential runs never
    # share a timestamp. The backup line is the only date caller in this path.
    printf '#!/bin/sh\nprintf "20260101_000000"\n' > "$TMP/bin/date"
    chmod +x "$TMP/bin/date"

    run_clean_configure "$cfg" --set DEFAULT_PRESET=run_a >/dev/null 2>&1
    run_clean_configure "$cfg" --set DEFAULT_PRESET=run_b >/dev/null 2>&1

    rm -f "$TMP/bin/date"

    local backups originals
    backups=$(find "$cfg" -maxdepth 1 -name '.env.backup.*' | wc -l | tr -d ' ')
    assert_eq "2" "$backups" "two runs in the same second produce two distinct backups"
    originals=$(grep -l 'DEFAULT_PRESET=original' "$cfg"/.env.backup.* 2>/dev/null | wc -l | tr -d ' ')
    assert_eq "1" "$originals" "the pre-existing config survives in its own backup"
}

run_test "Test 1: public configure route and help" test_public_route_and_help
run_test "Test 2: complete parameter contract" test_template_covers_config_contract
run_test "Test 3: truthful full-roster auto-detection" test_auto_detects_complete_roster_truthfully
run_test "Test 4: API transport auto-selection" test_auto_selects_api_when_cli_is_missing
run_test "Test 5: advanced --set coverage" test_set_covers_advanced_parameters
run_test "Test 6: preservation, backup, and permissions" test_existing_values_are_preserved_and_backed_up
run_test "Test 7: removed parameter rejection" test_unknown_parameter_is_rejected
run_test "Test 8: advanced defaults match runtime" test_advanced_defaults_match_runtime
run_test "Test 9: --set participates in detection" test_set_drives_detection_with_last_value_winning
run_test "Test 10: export preservation" test_export_values_are_preserved
run_test "Test 11: transport provenance and pins" test_auto_transport_provenance_and_pins
run_test "Test 12: side-effect-free metadata and dry-run" test_metadata_and_dry_run_are_side_effect_free
run_test "Test 13: symlinks and non-interactive aliases" test_symlinks_and_noninteractive_aliases
run_test "Test 14: interactive keeps values on Enter" test_interactive_keeps_values
run_test "Test 15: interactive accepts a typed value" test_interactive_accepts_input
run_test "Test 16: init then configure (BUG 2 regression)" test_init_then_configure_regression
run_test "Test 17: explicit pin survives init" test_explicit_pin_survives_init
run_test "Test 18: CLI-first preserved with a key present" test_cli_first_preserved
run_test "Test 19: backup names are unique within one second" test_backups_are_unique_within_one_second

test_summary "configure"
