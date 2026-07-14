#!/bin/bash
# shellcheck disable=SC2329
# (test_*/assert_eq are invoked indirectly via `run_test "$@"`)
#
# test_user_config.sh - Tests for the user-config loader (v2.12+)
#
# Covers:
#   - .env loading (KEY=value, exported)
#   - Existing env vars are NOT overridden by .env file
#   - config.sh is sourced (full bash, runs after .env)
#   - AI_CONSULTANTS_CONFIG_DIR override
#   - XDG_CONFIG_HOME fallback
#   - HOME/.config default fallback
#   - .env edge cases: comments, blanks, quoted values, leading `export`
#   - Invalid keys are silently rejected
#   - Missing files are silent (no error)
#
# Usage: ./scripts/test_user_config.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/user_config.sh
source "$SCRIPT_DIR/lib/user_config.sh"

# Reset cross-test state. run_test invokes this automatically via the
# _reset_state hook in lib/test_helpers.sh.
_reset_state() {
    unset _AI_CONSULTANTS_USER_CONFIG_LOADED
    unset SIMPLE QUOTED PREEXISTING WITH_EXPORT EXPORTED INDENTED_KEY \
          VALID FROM_ENV COMPUTED FROM_XDG WHO_WINS WIN_VAR COUNTER
    unset XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME 2>/dev/null || true
}

TMP=$(mktemp -d -t ai_consultants_user_config_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# -----------------------------------------------------------------------------
# Test 1: .env basic loading
# -----------------------------------------------------------------------------
test_env_basic() {
    local dir="$TMP/t1"
    mkdir -p "$dir"
    cat > "$dir/.env" <<'EOF'
SIMPLE=hello
QUOTED="quoted value"
EOF
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "hello" "$SIMPLE" ".env: SIMPLE=hello"
    assert_eq "quoted value" "$QUOTED" '.env: QUOTED="quoted value" (quotes stripped)'
}

# -----------------------------------------------------------------------------
# Test 2: existing env wins over .env
# -----------------------------------------------------------------------------
test_env_precedence() {
    local dir="$TMP/t2"
    mkdir -p "$dir"
    echo 'PREEXISTING=from_file' > "$dir/.env"
    PREEXISTING="from_env"
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "from_env" "$PREEXISTING" "existing env var preserved (file does NOT override)"
}

# -----------------------------------------------------------------------------
# Test 3: comments, blanks, leading `export`
# -----------------------------------------------------------------------------
test_env_edge_cases() {
    local dir="$TMP/t3"
    mkdir -p "$dir"
    cat > "$dir/.env" <<'EOF'
# This is a comment
   # indented comment

WITH_EXPORT=foo
export EXPORTED=bar
   INDENTED_KEY=baz
EOF
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "foo" "$WITH_EXPORT" ".env: plain assignment loaded"
    assert_eq "bar" "$EXPORTED" ".env: leading 'export' stripped, value loaded"
    assert_eq "baz" "$INDENTED_KEY" ".env: indented key loaded"
}

# -----------------------------------------------------------------------------
# Test 4: invalid keys rejected
# -----------------------------------------------------------------------------
test_env_invalid_keys() {
    local dir="$TMP/t4"
    mkdir -p "$dir"
    cat > "$dir/.env" <<'EOF'
1INVALID=should_skip
WITH-DASH=should_skip
VALID=ok
EOF
    # The two invalid names cannot be probed via parameter expansion (bash
    # syntax forbids `${1INVALID}`). Instead we check `env` directly: if
    # the loader had accepted them, they'd appear in the process environment.
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "ok" "$VALID" "valid key loaded"
    assert_eq "" "$(env | grep -E '^(1INVALID|WITH-DASH)=' || true)" \
        "invalid keys (digit prefix, dash) NOT exported"
}

# -----------------------------------------------------------------------------
# Test 5: config.sh sourced after .env
# -----------------------------------------------------------------------------
test_config_sourced() {
    local dir="$TMP/t5"
    mkdir -p "$dir"
    echo 'FROM_ENV=env_value' > "$dir/.env"
    cat > "$dir/config.sh" <<'EOF'
COMPUTED="prefix_${FROM_ENV}_suffix"
export COMPUTED
EOF
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "env_value" "$FROM_ENV" ".env loaded before config.sh"
    assert_eq "prefix_env_value_suffix" "$COMPUTED" "config.sh can reference .env-loaded vars"
}

# -----------------------------------------------------------------------------
# Test 6: XDG_CONFIG_HOME fallback
# -----------------------------------------------------------------------------
test_xdg_fallback() {
    local xdg="$TMP/xdg"
    mkdir -p "$xdg/ai-consultants"
    echo 'FROM_XDG=yes' > "$xdg/ai-consultants/.env"
    unset AI_CONSULTANTS_CONFIG_DIR
    XDG_CONFIG_HOME="$xdg" load_user_config
    assert_eq "yes" "$FROM_XDG" "XDG_CONFIG_HOME picked up when AI_CONSULTANTS_CONFIG_DIR unset"
    assert_eq "$xdg/ai-consultants" "$(XDG_CONFIG_HOME=$xdg get_user_config_dir)" "get_user_config_dir resolves XDG"
}

# -----------------------------------------------------------------------------
# Test 7: missing dir / files are silent
# -----------------------------------------------------------------------------
test_missing_files_silent() {
    local dir="$TMP/nonexistent"
    local rc=0 output
    output=$(AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config 2>&1) || rc=$?
    assert_eq "0" "$rc" "load_user_config does not error on missing dir"
    assert_eq "" "$output" "load_user_config produces no output on missing dir"
}

# -----------------------------------------------------------------------------
# Test 8: AI_CONSULTANTS_CONFIG_DIR overrides XDG and HOME
# -----------------------------------------------------------------------------
test_explicit_dir_priority() {
    local explicit="$TMP/explicit"
    local xdg="$TMP/xdg2"
    mkdir -p "$explicit" "$xdg/ai-consultants"
    echo 'WHO_WINS=explicit' > "$explicit/.env"
    echo 'WHO_WINS=xdg' > "$xdg/ai-consultants/.env"
    AI_CONSULTANTS_CONFIG_DIR="$explicit" XDG_CONFIG_HOME="$xdg" load_user_config
    assert_eq "explicit" "$WHO_WINS" "AI_CONSULTANTS_CONFIG_DIR wins over XDG_CONFIG_HOME"
}

# v2.12 fix: CR-LF line endings (Windows) must not corrupt values.
# Pre-fix: ENABLE_DEBATE=true\r\n loaded as 'true\r' breaking every comparison.
test_env_crlf_stripped() {
    local dir="$TMP/t9"
    mkdir -p "$dir"
    printf 'WIN_VAR=value_under_crlf\r\n' > "$dir/.env"
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "value_under_crlf" "$WIN_VAR" "CR-LF line endings stripped (no trailing \\r)"
}

# v2.12 fix: load_user_config is idempotent. config.sh is sourced 15-30 times
# per consultation via lib/common.sh and every query_*.sh; without a guard,
# non-idempotent user config (PATH-appends, counters, log-appends) would
# compound silently.
test_idempotency_guard() {
    local dir="$TMP/t10"
    mkdir -p "$dir"
    echo 'COUNTER=0' > "$dir/.env"
    cat > "$dir/config.sh" <<'EOF'
COUNTER=$((COUNTER+1))
export COUNTER
EOF
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    AI_CONSULTANTS_CONFIG_DIR="$dir" load_user_config
    assert_eq "1" "$COUNTER" "load_user_config called 3x, counter still 1 (idempotent)"
}

# v2.12 fix: get_user_config_dir returns empty + exit 1 when HOME and
# XDG_CONFIG_HOME are both unset (e.g. distroless container without HOME)
# instead of computing the broken path "/.config/ai-consultants".
test_home_unset_fallback() {
    local dir
    local rc=0
    dir=$(unset HOME XDG_CONFIG_HOME AI_CONSULTANTS_CONFIG_DIR; get_user_config_dir 2>/dev/null) || rc=$?
    assert_eq "" "$dir" "get_user_config_dir returns empty when HOME and XDG unset"
    assert_eq "1" "$rc" "get_user_config_dir exits 1 when HOME and XDG unset"
    # And load_user_config does not crash in that scenario
    rc=0
    (unset HOME XDG_CONFIG_HOME AI_CONSULTANTS_CONFIG_DIR _AI_CONSULTANTS_USER_CONFIG_LOADED; load_user_config) || rc=$?
    assert_eq "0" "$rc" "load_user_config degrades gracefully when HOME and XDG unset"
}

# -----------------------------------------------------------------------------
# Run all tests
# -----------------------------------------------------------------------------
run_test "Test 1: .env basic loading"          test_env_basic
run_test "Test 2: existing env precedence"     test_env_precedence
run_test "Test 3: .env edge cases"             test_env_edge_cases
run_test "Test 4: invalid keys rejected"       test_env_invalid_keys
run_test "Test 5: config.sh after .env"        test_config_sourced
run_test "Test 6: XDG_CONFIG_HOME fallback"    test_xdg_fallback
run_test "Test 7: missing files silent"        test_missing_files_silent
run_test "Test 8: explicit dir priority"       test_explicit_dir_priority
run_test "Test 9: CR-LF stripping (v2.12)"     test_env_crlf_stripped
run_test "Test 10: idempotency guard (v2.12)"  test_idempotency_guard
run_test "Test 11: HOME unset fallback (v2.12)" test_home_unset_fallback

# v2.13 fix: get_xdg_dir() helper resolves XDG cache/state/data with proper
# fallback chain (env -> $HOME/.{cache,local/state,local/share} -> /tmp).
test_xdg_dir_honors_env() {
    local got
    got=$(XDG_CACHE_HOME=/foo get_xdg_dir cache)
    assert_eq "/foo/ai-consultants" "$got" "XDG_CACHE_HOME respected"
    got=$(XDG_STATE_HOME=/bar get_xdg_dir state)
    assert_eq "/bar/ai-consultants" "$got" "XDG_STATE_HOME respected"
    got=$(XDG_DATA_HOME=/baz get_xdg_dir data)
    assert_eq "/baz/ai-consultants" "$got" "XDG_DATA_HOME respected"
}

test_xdg_dir_falls_back_to_home() {
    local got
    got=$(unset XDG_CACHE_HOME; HOME=/h get_xdg_dir cache)
    assert_eq "/h/.cache/ai-consultants" "$got" "cache falls back to ~/.cache"
    got=$(unset XDG_STATE_HOME; HOME=/h get_xdg_dir state)
    assert_eq "/h/.local/state/ai-consultants" "$got" "state falls back to ~/.local/state"
    got=$(unset XDG_DATA_HOME; HOME=/h get_xdg_dir data)
    assert_eq "/h/.local/share/ai-consultants" "$got" "data falls back to ~/.local/share"
}

test_xdg_dir_distroless_fallback() {
    local got rc=0
    got=$(unset HOME XDG_CACHE_HOME; get_xdg_dir cache)
    assert_eq "/tmp/ai-consultants-cache" "$got" "cache falls back to /tmp/ai-consultants-cache when HOME unset"
    got=$(unset HOME XDG_STATE_HOME; get_xdg_dir state)
    assert_eq "/tmp/ai-consultants-state" "$got" "state falls back to /tmp/ai-consultants-state when HOME unset"
}

test_xdg_dir_invalid_kind() {
    local got rc=0
    got=$(get_xdg_dir bogus 2>/dev/null) || rc=$?
    assert_eq "" "$got" "invalid kind returns empty"
    assert_eq "1" "$rc" "invalid kind exits 1"
}

# v2.13 contract: config.sh routes the 6 path defaults through get_xdg_dir
# unless the user pre-exports the var. Sourcing config.sh in a clean env
# under known XDG_*_HOME values must resolve to those locations.
test_config_sh_xdg_defaults() {
    local tmp
    tmp=$(mktemp -d)
    local out
    out=$(XDG_CACHE_HOME="$tmp/c" XDG_STATE_HOME="$tmp/s" XDG_DATA_HOME="$tmp/d" \
        bash -c '
            unset DEFAULT_OUTPUT_DIR_BASE CACHE_DIR SESSION_DIR COST_TRACKING_FILE \
                  RATE_LIMIT_DIR CHUNK_TEMP_DIR \
                  _AI_CONSULTANTS_XDG_CACHE _AI_CONSULTANTS_XDG_STATE _AI_CONSULTANTS_XDG_DATA
            source scripts/config.sh
            echo "$DEFAULT_OUTPUT_DIR_BASE"
            echo "$CACHE_DIR"
            echo "$SESSION_DIR"
            echo "$COST_TRACKING_FILE"
            echo "$RATE_LIMIT_DIR"
            echo "$CHUNK_TEMP_DIR"
        ')
    rm -rf "$tmp"
    local lines=()
    while IFS= read -r line; do lines+=("$line"); done <<<"$out"
    assert_eq "$tmp/c/ai-consultants/consultations" "${lines[0]}" "DEFAULT_OUTPUT_DIR_BASE -> XDG_CACHE_HOME"
    assert_eq "$tmp/c/ai-consultants/cache"         "${lines[1]}" "CACHE_DIR -> XDG_CACHE_HOME"
    assert_eq "$tmp/s/ai-consultants/sessions"      "${lines[2]}" "SESSION_DIR -> XDG_STATE_HOME"
    assert_eq "$tmp/d/ai-consultants/costs.json"    "${lines[3]}" "COST_TRACKING_FILE -> XDG_DATA_HOME"
    assert_eq "$tmp/c/ai-consultants/ratelimit"     "${lines[4]}" "RATE_LIMIT_DIR -> XDG_CACHE_HOME"
    assert_eq "$tmp/c/ai-consultants/chunks"        "${lines[5]}" "CHUNK_TEMP_DIR -> XDG_CACHE_HOME"
}

# Backward-compat: explicit env vars take precedence over XDG defaults.
test_config_sh_explicit_override_wins() {
    local out
    out=$(CACHE_DIR=/explicit/cache XDG_CACHE_HOME=/should/lose bash -c '
        source scripts/config.sh
        echo "$CACHE_DIR"
    ')
    assert_eq "/explicit/cache" "$out" "explicit CACHE_DIR wins over XDG_CACHE_HOME"
}

# v2.13 default flip: ENABLE_DEBATE_OPTIMIZATION promoted to true. A clean
# env (no override) should yield "true" so consensus questions skip debate.
test_debate_optimization_default_true() {
    local val
    val=$(unset ENABLE_DEBATE_OPTIMIZATION; bash -c '
        source scripts/config.sh
        echo "$ENABLE_DEBATE_OPTIMIZATION"
    ')
    assert_eq "true" "$val" "ENABLE_DEBATE_OPTIMIZATION default is true (v2.13 promotion)"
}

# v2.15.1 Gemini transport auto-resolution. With GEMINI_USE_API unset, config.sh
# picks API mode when a GEMINI_API_KEY is present (the npm-friendly path) and CLI
# mode otherwise. An explicit GEMINI_USE_API always wins (back-compat).
test_gemini_auto_api_with_key() {
    local val
    val=$(unset GEMINI_USE_API; GEMINI_API_KEY=AIzaTESTKEY bash -c '
        source scripts/config.sh
        echo "$GEMINI_USE_API"
    ')
    assert_eq "true" "$val" "GEMINI_USE_API auto-resolves to true when GEMINI_API_KEY is set"
}

test_gemini_auto_cli_without_key() {
    local val
    val=$(unset GEMINI_USE_API GEMINI_API_KEY; bash -c '
        source scripts/config.sh
        echo "$GEMINI_USE_API"
    ')
    assert_eq "false" "$val" "GEMINI_USE_API auto-resolves to false when no GEMINI_API_KEY"
}

test_gemini_explicit_false_wins_over_key() {
    local val
    val=$(GEMINI_USE_API=false GEMINI_API_KEY=AIzaTESTKEY bash -c '
        source scripts/config.sh
        echo "$GEMINI_USE_API"
    ')
    assert_eq "false" "$val" "explicit GEMINI_USE_API=false wins even with a key present"
}

test_gemini_explicit_true_without_key() {
    local val
    val=$(unset GEMINI_API_KEY; GEMINI_USE_API=true bash -c '
        source scripts/config.sh
        echo "$GEMINI_USE_API"
    ')
    assert_eq "true" "$val" "explicit GEMINI_USE_API=true is honored without a key"
}

# MiniMax transport auto-resolution (v2.21): back-compat for pre-v2.21 API-only
# users -- a set MINIMAX_API_KEY keeps them on the API path instead of the new
# mmx CLI default they never installed. Mirrors the Gemini resolution.
test_minimax_auto_api_with_key() {
    local val
    val=$(unset MINIMAX_USE_API; MINIMAX_API_KEY=mmxTESTKEY bash -c '
        source scripts/config.sh
        echo "$MINIMAX_USE_API"
    ')
    assert_eq "true" "$val" "MINIMAX_USE_API auto-resolves to true when MINIMAX_API_KEY is set (back-compat)"
}

test_minimax_auto_cli_without_key() {
    local val
    val=$(unset MINIMAX_USE_API MINIMAX_API_KEY; bash -c '
        source scripts/config.sh
        echo "$MINIMAX_USE_API"
    ')
    assert_eq "false" "$val" "MINIMAX_USE_API auto-resolves to false (mmx CLI) when no MINIMAX_API_KEY"
}

test_minimax_explicit_false_wins_over_key() {
    local val
    val=$(MINIMAX_USE_API=false MINIMAX_API_KEY=mmxTESTKEY bash -c '
        source scripts/config.sh
        echo "$MINIMAX_USE_API"
    ')
    assert_eq "false" "$val" "explicit MINIMAX_USE_API=false wins even with a key present"
}

test_minimax_explicit_true_without_key() {
    local val
    val=$(unset MINIMAX_API_KEY; MINIMAX_USE_API=true bash -c '
        source scripts/config.sh
        echo "$MINIMAX_USE_API"
    ')
    assert_eq "true" "$val" "explicit MINIMAX_USE_API=true is honored without a key"
}

run_test "Test 12: get_xdg_dir honors XDG_*_HOME"        test_xdg_dir_honors_env
run_test "Test 13: get_xdg_dir falls back to ~/.cache"   test_xdg_dir_falls_back_to_home
run_test "Test 14: get_xdg_dir distroless /tmp fallback" test_xdg_dir_distroless_fallback
run_test "Test 15: get_xdg_dir invalid kind"             test_xdg_dir_invalid_kind
run_test "Test 16: config.sh XDG defaults"               test_config_sh_xdg_defaults
run_test "Test 17: explicit env wins over XDG"           test_config_sh_explicit_override_wins
run_test "Test 18: ENABLE_DEBATE_OPTIMIZATION=true (v2.13)" test_debate_optimization_default_true
run_test "Test 19: Gemini auto-API with key (v2.15.1)"   test_gemini_auto_api_with_key
run_test "Test 20: Gemini auto-CLI without key (v2.15.1)" test_gemini_auto_cli_without_key
run_test "Test 21: Gemini explicit false wins (v2.15.1)" test_gemini_explicit_false_wins_over_key
run_test "Test 22: Gemini explicit true honored (v2.15.1)" test_gemini_explicit_true_without_key
run_test "Test 23: MiniMax auto-API with key (v2.21)"    test_minimax_auto_api_with_key
run_test "Test 24: MiniMax auto-CLI without key (v2.21)" test_minimax_auto_cli_without_key
run_test "Test 25: MiniMax explicit false wins (v2.21)"  test_minimax_explicit_false_wins_over_key
run_test "Test 26: MiniMax explicit true honored (v2.21)" test_minimax_explicit_true_without_key

test_summary "user_config"
