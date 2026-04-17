#!/bin/bash
# test_suite.sh - Comprehensive test suite for AI Consultants
#
# Tests core library functions across common.sh, personas.sh, voting.sh,
# costs.sh, cache.sh, and routing.sh without external test frameworks.
#
# Usage: ./scripts/test_suite.sh
# Exit: 0 if all tests pass, 1 if any fail

set -euo pipefail

# =============================================================================
# SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Suppress log output during tests (redirect stderr to /dev/null for sourcing)
export LOG_LEVEL="ERROR"

# Source libraries under test
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"
source "$SCRIPT_DIR/lib/voting.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/cache.sh"
source "$SCRIPT_DIR/lib/routing.sh"

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Colors for test output
_C_RESET="\033[0m"
_C_GREEN="\033[32m"
_C_RED="\033[31m"
_C_YELLOW="\033[33m"
_C_BLUE="\033[34m"
_C_CYAN="\033[36m"
_C_DIM="\033[2m"

# Counters
_PASS_COUNT=0
_FAIL_COUNT=0
_SKIP_COUNT=0
_CURRENT_SUITE=""

# Temporary directory for test artifacts
TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/ai_consultants_test.XXXXXX")
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Begin a named test suite section
suite() {
    _CURRENT_SUITE="$1"
    echo -e "\n${_C_CYAN}--- $1 ---${_C_RESET}"
}

# Record a pass
_pass() {
    local msg="$1"
    ((_PASS_COUNT++)) || true
    echo -e "  ${_C_GREEN}PASS${_C_RESET}: $msg"
}

# Record a failure
_fail() {
    local msg="$1"
    shift
    ((_FAIL_COUNT++)) || true
    echo -e "  ${_C_RED}FAIL${_C_RESET}: $msg"
    for detail in "$@"; do
        echo -e "        ${_C_DIM}$detail${_C_RESET}"
    done
}

# Record a skip
_skip() {
    local msg="$1"
    local reason="${2:-}"
    ((_SKIP_COUNT++)) || true
    echo -e "  ${_C_YELLOW}SKIP${_C_RESET}: $msg${reason:+ ($reason)}"
}

# Assert two values are equal
# Usage: assert_equals <expected> <actual> <message>
assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$actual" == "$expected" ]]; then
        _pass "$msg"
    else
        _fail "$msg" "expected: '$expected'" "actual:   '$actual'"
    fi
}

# Assert two values are NOT equal
# Usage: assert_not_equals <not_expected> <actual> <message>
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$actual" != "$not_expected" ]]; then
        _pass "$msg"
    else
        _fail "$msg" "should NOT be: '$not_expected'" "but got:       '$actual'"
    fi
}

# Assert string contains substring
# Usage: assert_contains <substring> <haystack> <message>
assert_contains() {
    local substring="$1"
    local haystack="$2"
    local msg="$3"
    if [[ "$haystack" == *"$substring"* ]]; then
        _pass "$msg"
    else
        _fail "$msg" "expected to contain: '$substring'" "actual: '$haystack'"
    fi
}

# Assert string does NOT contain substring
# Usage: assert_not_contains <substring> <haystack> <message>
assert_not_contains() {
    local substring="$1"
    local haystack="$2"
    local msg="$3"
    if [[ "$haystack" != *"$substring"* ]]; then
        _pass "$msg"
    else
        _fail "$msg" "should NOT contain: '$substring'" "actual: '$haystack'"
    fi
}

# Assert a command exits with code 0
# Usage: assert_exit_code_success <message> <command...>
assert_exit_code_success() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        _pass "$msg"
    else
        _fail "$msg" "command exited non-zero: $*"
    fi
}

# Assert a command exits with non-zero code
# Usage: assert_exit_code_failure <message> <command...>
assert_exit_code_failure() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        _fail "$msg" "command should have failed: $*"
    else
        _pass "$msg"
    fi
}

# Assert a numeric value is greater than a threshold
# Usage: assert_greater_than <threshold> <actual> <message>
assert_greater_than() {
    local threshold="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$actual" -gt "$threshold" ]]; then
        _pass "$msg"
    else
        _fail "$msg" "expected > $threshold" "actual: $actual"
    fi
}

# Assert a numeric value is less than or equal to a threshold
# Usage: assert_less_than_or_equal <threshold> <actual> <message>
assert_less_than_or_equal() {
    local threshold="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$actual" -le "$threshold" ]]; then
        _pass "$msg"
    else
        _fail "$msg" "expected <= $threshold" "actual: $actual"
    fi
}

# Assert output is valid JSON
# Usage: assert_valid_json <json_string> <message>
assert_valid_json() {
    local json="$1"
    local msg="$2"
    if echo "$json" | jq . >/dev/null 2>&1; then
        _pass "$msg"
    else
        _fail "$msg" "not valid JSON: ${json:0:100}..."
    fi
}

# =============================================================================
# HELPER: Create mock consultant response files
# =============================================================================

# Create a mock JSON response file
# Usage: create_mock_response <dir> <filename> <consultant> <approach> <confidence> [model]
create_mock_response() {
    local dir="$1"
    local filename="$2"
    local consultant="$3"
    local approach="$4"
    local confidence="$5"
    local model="${6:-test-model}"

    mkdir -p "$dir"
    cat > "$dir/$filename" << MOCKEOF
{
  "consultant": "$consultant",
  "model": "$model",
  "persona": "Test Persona",
  "response": {
    "summary": "Test summary from $consultant",
    "detailed": "Detailed response from $consultant recommending $approach",
    "approach": "$approach",
    "pros": ["pro1"],
    "cons": ["con1"],
    "caveats": []
  },
  "confidence": {
    "score": $confidence,
    "reasoning": "Test reasoning"
  },
  "metadata": {
    "tokens_used": 500,
    "latency_ms": 1000,
    "timestamp": "2026-03-25T10:00:00Z"
  }
}
MOCKEOF
}


# =============================================================================
# TESTS: common.sh - Case conversion
# =============================================================================

test_case_conversion() {
    suite "common.sh: case conversion"

    local result
    result=$(to_upper "hello world")
    assert_equals "HELLOWORLD" "$result" "to_upper converts and strips spaces/hyphens"

    result=$(to_upper "gemini-pro")
    assert_equals "GEMINIPRO" "$result" "to_upper strips hyphens"

    result=$(to_lower "HELLO WORLD")
    assert_equals "hello_world" "$result" "to_lower converts and replaces spaces with underscores"

    result=$(to_lower "Gemini-Pro")
    assert_equals "gemini_pro" "$result" "to_lower replaces hyphens with underscores"

    result=$(to_title "HELLO")
    assert_equals "Hello" "$result" "to_title capitalizes first, lowercases rest"

    result=$(to_title "gemini")
    assert_equals "Gemini" "$result" "to_title works on lowercase input"
}

# =============================================================================
# TESTS: common.sh - Token estimation
# =============================================================================

test_token_estimation() {
    suite "common.sh: token estimation"

    local result
    result=$(estimate_tokens "Hello world")
    assert_equals "2" "$result" "simple text: 11 chars / 4 = 2 tokens"

    result=$(estimate_tokens "")
    assert_equals "0" "$result" "empty string: 0 tokens"

    result=$(estimate_tokens "The quick brown fox jumps over the lazy dog")
    # 43 chars / 4 = 10
    assert_equals "10" "$result" "longer text: 43 chars / 4 = 10 tokens"

    # Test from stdin
    result=$(echo -n "test data here" | estimate_tokens)
    assert_equals "3" "$result" "stdin mode: 14 chars / 4 = 3 tokens"
}

# =============================================================================
# TESTS: common.sh - File validation
# =============================================================================

test_file_validation() {
    suite "common.sh: file path validation"

    assert_exit_code_success "valid relative path accepted" validate_file_path "test.txt"
    assert_exit_code_success "path with spaces accepted" validate_file_path "test file.txt"
    assert_exit_code_failure "path traversal rejected" validate_file_path "../test.txt"
    assert_exit_code_failure "absolute path rejected by default" validate_file_path "/etc/passwd"
    assert_exit_code_success "absolute path allowed with flag" validate_file_path "/tmp/test.txt" true
    assert_exit_code_failure "sensitive path /etc rejected" validate_file_path "/etc/test" true
    assert_exit_code_failure "empty path rejected" validate_file_path ""
}

# =============================================================================
# TESTS: common.sh - Filename sanitization
# =============================================================================

test_sanitize_filename() {
    suite "common.sh: filename sanitization"

    local result
    result=$(sanitize_filename "Test File.txt")
    assert_equals "Test_File.txt" "$result" "spaces replaced with underscore"

    result=$(sanitize_filename "test@#file!.txt")
    assert_equals "test_file_.txt" "$result" "special characters replaced"

    # Long filename truncation
    local long_name
    long_name=$(printf 'a%.0s' {1..300})
    result=$(sanitize_filename "$long_name")
    local length=${#result}
    assert_equals "255" "$length" "filename truncated to 255 chars"

    result=$(sanitize_filename $'test\nfile\r.txt')
    assert_equals "testfile.txt" "$result" "control characters removed"
}

# =============================================================================
# TESTS: common.sh - Map functions (Bash 3.2 compatible associative arrays)
# =============================================================================

test_map_functions() {
    suite "common.sh: map functions"

    map_clear "TSMAP" 2>/dev/null || true

    # set and get
    map_set "TSMAP" "color" "blue"
    local result
    result=$(map_get "TSMAP" "color")
    assert_equals "blue" "$result" "map_set + map_get round-trip"

    # overwrite
    map_set "TSMAP" "color" "red"
    result=$(map_get "TSMAP" "color")
    assert_equals "red" "$result" "map_set overwrites existing key"

    # has
    assert_exit_code_success "map_has finds existing key" map_has "TSMAP" "color"
    assert_exit_code_failure "map_has returns 1 for missing key" map_has "TSMAP" "nonexistent"

    # multiple keys
    map_set "TSMAP" "size" "large"
    map_set "TSMAP" "shape" "round"
    local keys
    keys=$(map_keys "TSMAP")
    assert_contains "color" "$keys" "map_keys includes 'color'"
    assert_contains "size" "$keys" "map_keys includes 'size'"
    assert_contains "shape" "$keys" "map_keys includes 'shape'"

    # get missing key returns empty
    result=$(map_get "TSMAP" "missing")
    assert_equals "" "$result" "map_get returns empty for missing key"

    # clear
    map_clear "TSMAP"
    keys=$(map_keys "TSMAP")
    assert_equals "" "$keys" "map_clear removes all keys"
}

# =============================================================================
# TESTS: common.sh - Self-exclusion
# =============================================================================

test_self_exclusion() {
    suite "common.sh: self-exclusion logic"

    local result

    # Test mapping from invoking agent to consultant name
    INVOKING_AGENT="claude" result=$(get_self_consultant_name)
    assert_equals "CLAUDE" "$result" "claude maps to CLAUDE"

    INVOKING_AGENT="codex" result=$(get_self_consultant_name)
    assert_equals "CODEX" "$result" "codex maps to CODEX"

    INVOKING_AGENT="gemini_cli" result=$(get_self_consultant_name)
    assert_equals "GEMINI" "$result" "gemini_cli alias maps to GEMINI"

    INVOKING_AGENT="unknown" result=$(get_self_consultant_name)
    assert_equals "" "$result" "unknown agent maps to empty string"

    # Test should_skip_consultant
    INVOKING_AGENT="claude"
    assert_exit_code_success "should_skip_consultant returns true for self" should_skip_consultant "CLAUDE"
    assert_exit_code_failure "should_skip_consultant returns false for others" should_skip_consultant "GEMINI"

    INVOKING_AGENT="unknown"
    assert_exit_code_failure "no exclusion when agent is unknown" should_skip_consultant "CLAUDE"

    # Reset
    INVOKING_AGENT="unknown"
}

# =============================================================================
# TESTS: common.sh - Consultant validation
# =============================================================================

test_consultant_validation() {
    suite "common.sh: consultant name validation"

    assert_exit_code_success "Gemini is valid" validate_consultant_name "Gemini"
    assert_exit_code_success "CLAUDE is valid" validate_consultant_name "CLAUDE"
    assert_exit_code_success "MiniMax is valid" validate_consultant_name "MiniMax"
    assert_exit_code_success "Qwen3 is valid" validate_consultant_name "Qwen3"
    assert_exit_code_success "custom alphanumeric agent accepted" validate_consultant_name "CUSTOM_AGENT_1"
    assert_exit_code_failure "agent with special chars rejected" validate_consultant_name "bad;agent"
}

# =============================================================================
# TESTS: common.sh - API mode helpers
# =============================================================================

test_api_mode_helpers() {
    suite "common.sh: API mode helpers"

    # Default is CLI mode (all *_USE_API default to false)
    assert_exit_code_failure "Gemini defaults to CLI mode" is_api_mode "Gemini"
    assert_exit_code_failure "Claude defaults to CLI mode" is_api_mode "Claude"

    # Test get_api_key_var mapping
    local result
    result=$(get_api_key_var "gemini")
    assert_equals "GEMINI_API_KEY" "$result" "gemini API key var is GEMINI_API_KEY"

    result=$(get_api_key_var "codex")
    assert_equals "OPENAI_API_KEY" "$result" "codex API key var is OPENAI_API_KEY"

    result=$(get_api_key_var "claude")
    assert_equals "ANTHROPIC_API_KEY" "$result" "claude API key var is ANTHROPIC_API_KEY"

    result=$(get_api_key_var "minimax")
    assert_equals "MINIMAX_API_KEY" "$result" "minimax API key var is MINIMAX_API_KEY"

    result=$(get_api_key_var "unknown_agent")
    assert_equals "" "$result" "unknown agent returns empty API key var"

    # Test get_api_format mapping
    result=$(get_api_format "gemini")
    assert_equals "google_ai" "$result" "gemini uses google_ai format"

    result=$(get_api_format "claude")
    assert_equals "anthropic" "$result" "claude uses anthropic format"

    result=$(get_api_format "codex")
    assert_equals "openai" "$result" "codex uses openai format"

    result=$(get_api_format "grok")
    assert_equals "openai" "$result" "grok uses openai format"

    # Test get_api_url returns non-empty for known agents
    result=$(get_api_url "gemini")
    assert_contains "googleapis.com" "$result" "gemini URL contains googleapis.com"

    result=$(get_api_url "claude")
    assert_contains "anthropic.com" "$result" "claude URL contains anthropic.com"

    result=$(get_api_url "grok")
    assert_contains "x.ai" "$result" "grok URL contains x.ai"
}

# =============================================================================
# TESTS: common.sh - Query builder
# =============================================================================

test_build_full_query() {
    suite "common.sh: build_full_query"

    local result

    # Query only
    result=$(build_full_query "How to optimize SQL?" "")
    assert_equals "How to optimize SQL?" "$result" "query-only returns the query"

    # With context file
    local ctx_file="$TEST_TMPDIR/context.txt"
    echo "SELECT * FROM users WHERE id = 1;" > "$ctx_file"
    result=$(build_full_query "Optimize this" "$ctx_file")
    assert_contains "SELECT * FROM users" "$result" "context file content included"
    assert_contains "Optimize this" "$result" "query appended after context"
    assert_contains "Additional Question" "$result" "separator present"

    # Empty query with context file
    result=$(build_full_query "" "$ctx_file")
    assert_contains "SELECT * FROM users" "$result" "context only: file content returned"

    # Both empty
    result=$(build_full_query "" "")
    assert_equals "" "$result" "both empty returns empty"
}

# =============================================================================
# TESTS: common.sh - Known agent registry
# =============================================================================

test_known_agents() {
    suite "common.sh: known agent registry"

    assert_exit_code_success "GEMINI is a known agent" is_known_agent "GEMINI"
    assert_exit_code_success "CLAUDE is a known agent" is_known_agent "CLAUDE"
    assert_exit_code_success "MINIMAX is a known agent" is_known_agent "MINIMAX"
    assert_exit_code_success "DEEPSEEK is a known agent" is_known_agent "DEEPSEEK"
    assert_exit_code_failure "RANDOM is not a known agent" is_known_agent "RANDOM"
}

# =============================================================================
# TESTS: personas.sh - Persona catalog
# =============================================================================

test_persona_catalog() {
    suite "personas.sh: catalog functions"

    # get_persona_by_id - known IDs
    local result
    result=$(get_persona_by_id 1 "name")
    assert_equals "The Architect" "$result" "ID 1 is The Architect"

    result=$(get_persona_by_id 2 "name")
    assert_equals "The Pragmatist" "$result" "ID 2 is The Pragmatist"

    result=$(get_persona_by_id 3 "name")
    assert_equals "The Devil's Advocate" "$result" "ID 3 is The Devil's Advocate"

    result=$(get_persona_by_id 1 "var")
    assert_equals "PERSONA_GEMINI" "$result" "ID 1 variable is PERSONA_GEMINI"

    result=$(get_persona_by_id 21 "name")
    assert_equals "The Pragmatic Optimizer" "$result" "ID 21 is The Pragmatic Optimizer"

    # get_persona_by_id - invalid ID
    assert_exit_code_failure "invalid persona ID returns 1" get_persona_by_id 999

    # get_persona_id_by_name
    result=$(get_persona_id_by_name "The Architect")
    assert_equals "1" "$result" "The Architect has ID 1"

    result=$(get_persona_id_by_name "The Synthesizer")
    assert_equals "18" "$result" "The Synthesizer has ID 18"

    assert_exit_code_failure "unknown persona name returns 1" get_persona_id_by_name "The Nonexistent"
}

# =============================================================================
# TESTS: personas.sh - Persona resolution
# =============================================================================

test_persona_resolution() {
    suite "personas.sh: persona resolution for consultants"

    local result

    # Default persona for Gemini (The Architect)
    result=$(get_persona "Gemini")
    assert_contains "Architect" "$result" "Gemini gets Architect persona by default"

    # Default persona for Mistral (The Devil's Advocate)
    result=$(get_persona "Mistral")
    assert_contains "Devil" "$result" "Mistral gets Devil's Advocate persona"

    # Default persona for Claude (The Synthesizer)
    result=$(get_persona "Claude")
    assert_contains "Synthesizer" "$result" "Claude gets Synthesizer persona"

    # Persona name resolution
    result=$(get_persona_name "Gemini")
    assert_equals "The Architect" "$result" "Gemini persona name is The Architect"

    result=$(get_persona_name "Codex")
    assert_equals "The Pragmatist" "$result" "Codex persona name is The Pragmatist"

    result=$(get_persona_name "MiniMax")
    assert_equals "The Pragmatic Optimizer" "$result" "MiniMax persona name is The Pragmatic Optimizer"

    # Unknown consultant gets fallback
    result=$(get_persona "TotallyUnknown")
    assert_contains "AI consultant" "$result" "unknown consultant gets generic fallback persona"
}

# =============================================================================
# TESTS: personas.sh - Persona content
# =============================================================================

test_persona_content() {
    suite "personas.sh: persona content by ID"

    local result

    result=$(get_persona_content_by_id 1)
    assert_contains "Architect" "$result" "persona ID 1 content mentions Architect"
    assert_contains "scalab" "$result" "Architect persona mentions scalability"

    result=$(get_persona_content_by_id 11)
    assert_contains "Security" "$result" "persona ID 11 content mentions Security"

    assert_exit_code_failure "invalid persona ID 999 returns 1" get_persona_content_by_id 999
}

# =============================================================================
# TESTS: personas.sh - System prompt builder
# =============================================================================

test_system_prompt_builder() {
    suite "personas.sh: build_system_prompt and build_query_with_persona"

    local result

    result=$(build_system_prompt "Gemini")
    assert_contains "Architect" "$result" "system prompt includes persona"
    assert_contains "JSON" "$result" "system prompt includes output format instruction"

    result=$(build_query_with_persona "Codex" "How to refactor?")
    assert_contains "Pragmatist" "$result" "query includes Codex persona"
    assert_contains "How to refactor?" "$result" "query includes user question"
    assert_contains "System Instructions" "$result" "query has system instructions header"
    assert_contains "User Query" "$result" "query has user query header"
}

# =============================================================================
# TESTS: personas.sh - Normalize name
# =============================================================================

test_normalize_name() {
    suite "personas.sh: _normalize_name"

    local result
    result=$(_normalize_name "gemini")
    assert_equals "GEMINI" "$result" "lowercase to uppercase"

    result=$(_normalize_name "mini-max")
    assert_equals "MINIMAX" "$result" "hyphens stripped"

    result=$(_normalize_name "Qwen3")
    assert_equals "QWEN3" "$result" "mixed case normalized"
}

# =============================================================================
# TESTS: voting.sh - Consensus level thresholds
# =============================================================================

test_consensus_levels() {
    suite "voting.sh: get_consensus_level thresholds"

    assert_equals "unanimous" "$(get_consensus_level 100)" "score 100 = unanimous"
    assert_equals "high"      "$(get_consensus_level 75)"  "score 75 = high"
    assert_equals "high"      "$(get_consensus_level 99)"  "score 99 = high"
    assert_equals "medium"    "$(get_consensus_level 50)"  "score 50 = medium"
    assert_equals "medium"    "$(get_consensus_level 74)"  "score 74 = medium"
    assert_equals "low"       "$(get_consensus_level 25)"  "score 25 = low"
    assert_equals "low"       "$(get_consensus_level 49)"  "score 49 = low"
    assert_equals "none"      "$(get_consensus_level 0)"   "score 0 = none"
    assert_equals "none"      "$(get_consensus_level 24)"  "score 24 = none"
}

# =============================================================================
# TESTS: voting.sh - Weighted average
# =============================================================================

test_weighted_average() {
    suite "voting.sh: calculate_weighted_average"

    local dir="$TEST_TMPDIR/wavg"

    # All confidence 8 => average 8
    create_mock_response "$dir" "a.json" "Gemini" "approach-a" 8
    create_mock_response "$dir" "b.json" "Codex" "approach-b" 8
    create_mock_response "$dir" "c.json" "Mistral" "approach-c" 8
    local result
    result=$(calculate_weighted_average "$dir")
    assert_equals "8" "$result" "uniform confidence 8 averages to 8"
    rm -rf "$dir"

    # Mixed confidence: (6 + 8 + 10) / 3 = 8
    dir="$TEST_TMPDIR/wavg2"
    create_mock_response "$dir" "a.json" "Gemini" "approach-a" 6
    create_mock_response "$dir" "b.json" "Codex" "approach-b" 8
    create_mock_response "$dir" "c.json" "Mistral" "approach-c" 10
    result=$(calculate_weighted_average "$dir")
    assert_equals "8" "$result" "mixed (6,8,10) averages to 8"
    rm -rf "$dir"

    # Empty dir => default 5
    dir="$TEST_TMPDIR/wavg_empty"
    mkdir -p "$dir"
    result=$(calculate_weighted_average "$dir")
    assert_equals "5" "$result" "empty directory returns default 5"
    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Consensus score with same approaches
# =============================================================================

test_consensus_score() {
    suite "voting.sh: calculate_consensus_score"

    local dir="$TEST_TMPDIR/cons1"

    # All same approach => 100% consensus
    create_mock_response "$dir" "a.json" "Gemini" "JWT authentication" 8
    create_mock_response "$dir" "b.json" "Codex" "JWT authentication" 7
    create_mock_response "$dir" "c.json" "Mistral" "JWT authentication" 9
    local result
    result=$(calculate_consensus_score "$dir")
    assert_equals "100" "$result" "identical approaches yield 100% consensus"
    rm -rf "$dir"

    # Single response => 100
    dir="$TEST_TMPDIR/cons_single"
    create_mock_response "$dir" "a.json" "Gemini" "REST API" 8
    result=$(calculate_consensus_score "$dir")
    assert_equals "100" "$result" "single response yields 100% consensus"
    rm -rf "$dir"

    # All approaches are "unknown" => 0 (filtered out)
    dir="$TEST_TMPDIR/cons_unknown"
    create_mock_response "$dir" "a.json" "Gemini" "unknown" 5
    create_mock_response "$dir" "b.json" "Codex" "unknown" 5
    result=$(calculate_consensus_score "$dir")
    assert_equals "0" "$result" "all-unknown approaches yield 0 consensus"
    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Stemming
# =============================================================================

test_stemming() {
    suite "voting.sh: _stem_word"

    assert_equals "authentic"   "$(_stem_word "authentication")" "authentication => authentic (*ation stripped)"
    assert_equals "session"    "$(_stem_word "sessions")"       "sessions => session"
    assert_equals "cach"       "$(_stem_word "caching")"        "caching => cach"
    assert_equals "security"   "$(_stem_word "security")"       "security unchanged (no matching suffix)"
    assert_equals "deploy"     "$(_stem_word "deployment")"     "deployment => deploy"
    assert_equals "api"        "$(_stem_word "api")"            "short word unchanged (3 chars)"
}

# =============================================================================
# TESTS: voting.sh - Jaccard similarity
# =============================================================================

test_jaccard_similarity() {
    suite "voting.sh: _jaccard_similarity"

    local result

    # Identical sets => 100
    result=$(_jaccard_similarity "jwt auth token" "jwt auth token")
    assert_equals "100" "$result" "identical keyword sets score 100"

    # Completely disjoint => 0
    result=$(_jaccard_similarity "jwt auth" "sql database")
    assert_equals "0" "$result" "disjoint sets score 0"

    # Partial overlap: {jwt, auth, token} vs {jwt, token, session}
    # intersection = {jwt, token} = 2, union = {jwt, auth, token, session} = 4
    # 2/4 = 50
    result=$(_jaccard_similarity "auth jwt token" "jwt session token")
    assert_equals "50" "$result" "partial overlap (2/4) scores 50"

    # Both empty => 0
    result=$(_jaccard_similarity "" "")
    assert_equals "0" "$result" "both empty scores 0"
}

# =============================================================================
# TESTS: voting.sh - Confidence stddev
# =============================================================================

test_confidence_stddev() {
    suite "voting.sh: calculate_confidence_stddev"

    local dir="$TEST_TMPDIR/stddev1"

    # All same confidence => stddev 0
    create_mock_response "$dir" "a.json" "Gemini" "x" 7
    create_mock_response "$dir" "b.json" "Codex" "x" 7
    create_mock_response "$dir" "c.json" "Mistral" "x" 7
    local result
    result=$(calculate_confidence_stddev "$dir")
    assert_equals "0" "$result" "uniform confidence has stddev 0"
    rm -rf "$dir"

    # Single response => 0
    dir="$TEST_TMPDIR/stddev_single"
    create_mock_response "$dir" "a.json" "Gemini" "x" 8
    result=$(calculate_confidence_stddev "$dir")
    assert_equals "0" "$result" "single response has stddev 0"
    rm -rf "$dir"

    # Different confidences => stddev > 0
    dir="$TEST_TMPDIR/stddev2"
    create_mock_response "$dir" "a.json" "Gemini" "x" 2
    create_mock_response "$dir" "b.json" "Codex" "x" 8
    create_mock_response "$dir" "c.json" "Mistral" "x" 5
    result=$(calculate_confidence_stddev "$dir")
    assert_greater_than 0 "$result" "varied confidence has stddev > 0"
    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Confidence interval
# =============================================================================

test_confidence_interval() {
    suite "voting.sh: calculate_confidence_interval"

    local dir="$TEST_TMPDIR/ci"
    create_mock_response "$dir" "a.json" "Gemini" "x" 7
    create_mock_response "$dir" "b.json" "Codex" "x" 8
    create_mock_response "$dir" "c.json" "Mistral" "x" 9

    local result
    result=$(calculate_confidence_interval "$dir")
    assert_valid_json "$result" "confidence interval is valid JSON"
    assert_contains "mean" "$result" "result contains mean"
    assert_contains "stddev" "$result" "result contains stddev"
    assert_contains "interval" "$result" "result contains interval"
    assert_contains "display" "$result" "result contains display string"

    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Weighted recommendation
# =============================================================================

test_weighted_recommendation() {
    suite "voting.sh: calculate_weighted_recommendation"

    local dir="$TEST_TMPDIR/rec"
    # Two consultants agree on "Redis" with high confidence,
    # one dissents with low confidence.
    # Note: map keys are sanitized (spaces/special chars stripped), so use
    # single-word approach names to keep assertions predictable.
    create_mock_response "$dir" "a.json" "Gemini" "Redis" 9
    create_mock_response "$dir" "b.json" "Codex" "Redis" 8
    create_mock_response "$dir" "c.json" "Mistral" "Memcached" 3

    local result
    result=$(calculate_weighted_recommendation "$dir")
    assert_valid_json "$result" "recommendation is valid JSON"

    local recommended
    recommended=$(echo "$result" | jq -r '.recommended_approach')
    assert_equals "Redis" "$recommended" "Redis wins with higher weight"

    local total_weight
    total_weight=$(echo "$result" | jq -r '.total_weight')
    assert_equals "17" "$total_weight" "total weight = 9+8 = 17"

    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Dissenters
# =============================================================================

test_dissenters() {
    suite "voting.sh: get_dissenters"

    local dir="$TEST_TMPDIR/dissent"
    create_mock_response "$dir" "a.json" "Gemini" "Redis" 8
    create_mock_response "$dir" "b.json" "Codex" "Redis" 7
    create_mock_response "$dir" "c.json" "Mistral" "Memcached" 6

    local result
    result=$(get_dissenters "$dir" "Redis")
    assert_contains "Mistral" "$result" "Mistral is a dissenter against Redis"
    assert_not_contains "Gemini" "$result" "Gemini is not a dissenter"

    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Final score
# =============================================================================

test_final_score() {
    suite "voting.sh: calculate_final_score"

    local dir="$TEST_TMPDIR/fscore"
    # All agree with high confidence => max score
    create_mock_response "$dir" "a.json" "Gemini" "Microservices" 10
    create_mock_response "$dir" "b.json" "Codex" "Microservices" 10
    create_mock_response "$dir" "c.json" "Mistral" "Microservices" 10

    local result
    result=$(calculate_final_score "$dir" "Microservices")
    assert_equals "10" "$result" "all agree with max confidence => score 10"
    rm -rf "$dir"

    # All dissent => low score
    dir="$TEST_TMPDIR/fscore2"
    create_mock_response "$dir" "a.json" "Gemini" "Monolith" 5
    create_mock_response "$dir" "b.json" "Codex" "Monolith" 5
    local result2
    result2=$(calculate_final_score "$dir" "Microservices")
    assert_equals "2" "$result2" "all dissent with moderate confidence => score 2"
    rm -rf "$dir"
}

# =============================================================================
# TESTS: voting.sh - Simple majority vote
# =============================================================================

test_simple_majority_vote() {
    suite "voting.sh: simple_majority_vote"

    local dir="$TEST_TMPDIR/majority"
    create_mock_response "$dir" "a.json" "Gemini" "REST" 8
    create_mock_response "$dir" "b.json" "Codex" "REST" 6
    create_mock_response "$dir" "c.json" "Mistral" "GraphQL" 9

    local result
    result=$(simple_majority_vote "$dir")
    assert_equals "REST" "$result" "REST wins 2-1 in simple majority"
    rm -rf "$dir"
}

# =============================================================================
# TESTS: costs.sh - Input/output cost lookup
# =============================================================================

test_cost_rates() {
    suite "costs.sh: get_input_cost_per_1k / get_output_cost_per_1k"

    local result

    # Known model
    result=$(get_input_cost_per_1k "gpt-4o")
    assert_equals "0.005" "$result" "gpt-4o input rate is 0.005"

    result=$(get_output_cost_per_1k "gpt-4o")
    assert_equals "0.015" "$result" "gpt-4o output rate is 0.015"

    # Economy model
    result=$(get_input_cost_per_1k "gpt-4o-mini")
    assert_equals "0.00015" "$result" "gpt-4o-mini input rate is 0.00015"

    # Unknown model gets default
    result=$(get_input_cost_per_1k "totally-unknown-model-xyz")
    assert_equals "0.005" "$result" "unknown model gets default input rate 0.005"

    result=$(get_output_cost_per_1k "totally-unknown-model-xyz")
    assert_equals "0.015" "$result" "unknown model gets default output rate 0.015"
}

# =============================================================================
# TESTS: costs.sh - Cost estimation
# =============================================================================

test_cost_estimation() {
    suite "costs.sh: estimate_query_cost"

    local result
    # gpt-4o: input=0.005/1K, output=0.015/1K
    # 1000 input tokens, 500 output tokens
    # cost = (1000/1000)*0.005 + (500/1000)*0.015 = 0.005 + 0.0075 = 0.012500
    result=$(estimate_query_cost "gpt-4o" 1000 500)
    assert_equals ".012500" "$result" "gpt-4o 1000in+500out = 0.0125"

    # Zero tokens
    result=$(estimate_query_cost "gpt-4o" 0 0)
    assert_equals "0" "$result" "zero tokens = zero cost"
}

# =============================================================================
# TESTS: costs.sh - Cost formatting
# =============================================================================

test_cost_formatting() {
    suite "costs.sh: format_cost"

    local result
    result=$(format_cost "0.5000")
    assert_equals "\$0.5000" "$result" "0.50 formatted as dollar amount"

    result=$(format_cost "1.2345")
    assert_equals "\$1.2345" "$result" "1.2345 formatted correctly"

    # Small cost shows cents
    result=$(format_cost "0.005")
    assert_contains "." "$result" "small cost formatted with decimal"
}

# =============================================================================
# TESTS: costs.sh - Budget checking
# =============================================================================

test_budget_checking() {
    suite "costs.sh: check_budget / check_warning_threshold"

    # Within budget
    assert_exit_code_success "0.50 within 1.00 budget" check_budget "0.50" "1.00"

    # Over budget
    assert_exit_code_failure "1.50 exceeds 1.00 budget" check_budget "1.50" "1.00"

    # Exactly at budget
    assert_exit_code_success "1.00 equals 1.00 budget (not exceeded)" check_budget "1.00" "1.00"

    # Warning threshold
    local saved_warn="${WARN_AT_COST:-0.50}"
    WARN_AT_COST="0.50"
    assert_exit_code_success "0.60 exceeds 0.50 warning threshold" check_warning_threshold "0.60"
    assert_exit_code_failure "0.30 below 0.50 warning threshold" check_warning_threshold "0.30"
    WARN_AT_COST="$saved_warn"
}

# =============================================================================
# TESTS: costs.sh - Query complexity
# =============================================================================

test_query_complexity() {
    suite "costs.sh: calculate_query_complexity"

    local result

    # Short simple query with QUICK_SYNTAX category
    result=$(calculate_query_complexity "fix typo" 0 "QUICK_SYNTAX")
    assert_less_than_or_equal 3 "$result" "short fix-typo QUICK_SYNTAX is low complexity"

    # Long architecture query with files
    local long_query="Design a microservices architecture for a high-traffic e-commerce platform with distributed caching, event-driven messaging, and horizontal auto-scaling across multiple availability zones with security hardening"
    result=$(calculate_query_complexity "$long_query" 8 "ARCHITECTURE")
    assert_greater_than 6 "$result" "long architecture query with many files is high complexity"

    # Medium query
    result=$(calculate_query_complexity "Review this function for bugs" 2 "CODE_REVIEW")
    # Base 5, short query -1, 0 files from default, CODE_REVIEW +1, "bug" -1 => ~4-5
    # Actually: query_len < 50 => -1, num_files=2 (no modifier), CODE_REVIEW +1, "bug" -1 => 5-1+1-1 = 4
    assert_greater_than 0 "$result" "medium query returns positive score"
    assert_less_than_or_equal 10 "$result" "complexity is capped at 10"
}

# =============================================================================
# TESTS: costs.sh - Simple/complex query classification
# =============================================================================

test_query_classification() {
    suite "costs.sh: is_simple_query / is_complex_query"

    assert_exit_code_success "complexity 2 is simple (threshold 3)" is_simple_query 2
    assert_exit_code_success "complexity 3 is simple (threshold 3)" is_simple_query 3
    assert_exit_code_failure "complexity 5 is not simple" is_simple_query 5

    assert_exit_code_success "complexity 8 is complex (threshold 6)" is_complex_query 8
    assert_exit_code_failure "complexity 5 is not complex" is_complex_query 5
    assert_exit_code_failure "complexity 6 is not complex (threshold 6, need > 6)" is_complex_query 6
}

# =============================================================================
# TESTS: costs.sh - Model tier classification
# =============================================================================

test_model_tiers() {
    suite "costs.sh: get_model_tier"

    assert_equals "economy" "$(get_model_tier "gpt-4o-mini")" "gpt-4o-mini is economy"
    assert_equals "economy" "$(get_model_tier "claude-3-haiku")" "claude-3-haiku is economy"
    assert_equals "economy" "$(get_model_tier "gemini-2.0-flash")" "gemini-2.0-flash is economy"
    assert_equals "premium" "$(get_model_tier "gpt-4")" "gpt-4 is premium"
    assert_equals "premium" "$(get_model_tier "claude-3-opus")" "claude-3-opus is premium"
    assert_equals "standard" "$(get_model_tier "gpt-4o")" "gpt-4o is standard (default)"
    assert_equals "standard" "$(get_model_tier "some-random-model")" "unknown model is standard"
}

# =============================================================================
# TESTS: costs.sh - Economic model mapping
# =============================================================================

test_economic_models() {
    suite "costs.sh: get_economic_model"

    assert_equals "gemini-2.0-flash" "$(get_economic_model "gemini")" "gemini economy is gemini-2.0-flash"
    assert_equals "gpt-4o-mini"      "$(get_economic_model "codex")"  "codex economy is gpt-4o-mini"
    assert_equals "haiku-4.5"        "$(get_economic_model "claude")" "claude economy is haiku-4.5"
    assert_equals "MiniMax-M2.5"     "$(get_economic_model "minimax")" "minimax economy is MiniMax-M2.5"
    assert_equals ""                 "$(get_economic_model "unknown")" "unknown consultant returns empty"
}

# =============================================================================
# TESTS: costs.sh - Response token limits
# =============================================================================

test_response_limits() {
    suite "costs.sh: get_max_response_tokens / is_response_limits_enabled"

    local result
    result=$(get_max_response_tokens "QUICK_SYNTAX")
    assert_equals "200" "$result" "QUICK_SYNTAX limit is 200"

    result=$(get_max_response_tokens "ARCHITECTURE")
    assert_equals "1000" "$result" "ARCHITECTURE limit is 1000"

    result=$(get_max_response_tokens "SECURITY")
    assert_equals "1000" "$result" "SECURITY limit is 1000"

    result=$(get_max_response_tokens "GENERAL")
    assert_equals "500" "$result" "GENERAL limit is 500"

    result=$(get_max_response_tokens "UNKNOWN_CATEGORY")
    assert_equals "500" "$result" "unknown category gets default 500"

    # is_response_limits_enabled defaults to false
    ENABLE_RESPONSE_LIMITS="false"
    assert_exit_code_failure "response limits disabled by default" is_response_limits_enabled

    ENABLE_RESPONSE_LIMITS="true"
    assert_exit_code_success "response limits enabled when set to true" is_response_limits_enabled

    # Reset
    ENABLE_RESPONSE_LIMITS="false"
}

# =============================================================================
# TESTS: costs.sh - Budget enforcement
# =============================================================================

test_budget_enforcement() {
    suite "costs.sh: is_budget_enabled / enforce_budget"

    # Default is disabled
    ENABLE_BUDGET_LIMIT="false"
    assert_exit_code_failure "budget disabled by default" is_budget_enabled

    ENABLE_BUDGET_LIMIT="true"
    assert_exit_code_success "budget enabled when set to true" is_budget_enabled

    # enforce_budget with budget disabled always returns 0 (proceed)
    ENABLE_BUDGET_LIMIT="false"
    assert_exit_code_success "enforce_budget passes when budget disabled" enforce_budget "5.00" "1.00" "test"

    # enforce_budget with budget enabled and stop action
    ENABLE_BUDGET_LIMIT="true"
    MAX_SESSION_COST="1.00"
    BUDGET_ACTION="stop"
    assert_exit_code_failure "enforce_budget stops when over budget" enforce_budget "0.80" "0.50" "test"

    # enforce_budget with warn action always returns 0
    BUDGET_ACTION="warn"
    assert_exit_code_success "enforce_budget warns but proceeds" enforce_budget "0.80" "0.50" "test"

    # Under budget always passes
    BUDGET_ACTION="stop"
    assert_exit_code_success "enforce_budget passes when under budget" enforce_budget "0.30" "0.20" "test"

    # Reset
    ENABLE_BUDGET_LIMIT="false"
    BUDGET_ACTION="warn"
}

# =============================================================================
# TESTS: cache.sh - Fingerprint generation
# =============================================================================

test_cache_fingerprint() {
    suite "cache.sh: generate_fingerprint"

    local fp1 fp2 fp3

    # Same query + category => same fingerprint
    fp1=$(generate_fingerprint "How to sort?" "GENERAL")
    fp2=$(generate_fingerprint "How to sort?" "GENERAL")
    assert_equals "$fp1" "$fp2" "same query+category produces same fingerprint"

    # Different category => different fingerprint
    fp3=$(generate_fingerprint "How to sort?" "ALGORITHM")
    assert_not_equals "$fp1" "$fp3" "different category produces different fingerprint"

    # Case-insensitive normalization
    fp1=$(generate_fingerprint "HOW TO SORT?" "GENERAL")
    fp2=$(generate_fingerprint "how to sort?" "GENERAL")
    assert_equals "$fp1" "$fp2" "fingerprint is case-insensitive"

    # Fingerprint is non-empty
    local fp_len=${#fp1}
    assert_greater_than 10 "$fp_len" "fingerprint length is > 10 chars"
}

# =============================================================================
# TESTS: cache.sh - Store and retrieve
# =============================================================================

test_cache_store_retrieve() {
    suite "cache.sh: store_cache / check_cache"

    # Use isolated cache dir
    local saved_cache_dir="$CACHE_DIR"
    CACHE_DIR="$TEST_TMPDIR/test_cache"
    ENABLE_SEMANTIC_CACHE="true"

    local test_response='{"response":{"summary":"test"},"confidence":{"score":8}}'

    # Store a response
    store_cache "test query" "GENERAL" "Gemini" "$test_response"

    # Retrieve it
    local result
    result=$(check_cache "test query" "GENERAL" "Gemini")
    local status=$?
    assert_equals "0" "$status" "check_cache finds stored entry"
    assert_contains "test" "$result" "cached response contains original data"

    # Different query => cache miss
    if check_cache "different query" "GENERAL" "Gemini" >/dev/null 2>&1; then
        _fail "different query should not hit cache"
    else
        _pass "different query correctly misses cache"
    fi

    # With cache disabled => miss
    ENABLE_SEMANTIC_CACHE="false"
    if check_cache "test query" "GENERAL" "Gemini" >/dev/null 2>&1; then
        _fail "cache should miss when disabled"
    else
        _pass "cache correctly misses when disabled"
    fi

    # Restore
    ENABLE_SEMANTIC_CACHE="true"
    CACHE_DIR="$saved_cache_dir"
}

# =============================================================================
# TESTS: cache.sh - Clear and cleanup
# =============================================================================

test_cache_clear() {
    suite "cache.sh: clear_cache / get_cache_stats"

    local saved_cache_dir="$CACHE_DIR"
    CACHE_DIR="$TEST_TMPDIR/test_cache_clear"
    ENABLE_SEMANTIC_CACHE="true"

    store_cache "q1" "GENERAL" "Gemini" '{"test":1}'
    store_cache "q2" "GENERAL" "Codex" '{"test":2}'

    local stats
    stats=$(get_cache_stats)
    assert_valid_json "$stats" "cache stats is valid JSON"

    local total
    total=$(echo "$stats" | jq '.total_entries')
    assert_greater_than 0 "$total" "cache has entries after storing"

    clear_cache

    stats=$(get_cache_stats)
    total=$(echo "$stats" | jq '.total_entries')
    assert_equals "0" "$total" "cache empty after clear_cache"

    CACHE_DIR="$saved_cache_dir"
}

# =============================================================================
# TESTS: cache.sh - mark_from_cache
# =============================================================================

test_mark_from_cache() {
    suite "cache.sh: mark_from_cache"

    local input='{"response":"test","cache_metadata":{"from_cache":false}}'
    local result
    result=$(mark_from_cache "$input")
    assert_valid_json "$result" "output is valid JSON"

    local from_cache
    from_cache=$(echo "$result" | jq -r '.cache_metadata.from_cache')
    assert_equals "true" "$from_cache" "from_cache set to true"
}

# =============================================================================
# TESTS: routing.sh - Affinity matrix
# =============================================================================

test_routing_affinity() {
    suite "routing.sh: get_affinity"

    local result

    # Gemini is The Architect => high affinity for ARCHITECTURE
    result=$(get_affinity "ARCHITECTURE" "Gemini")
    assert_equals "10" "$result" "Gemini has max affinity for ARCHITECTURE"

    # Codex is The Pragmatist => high affinity for CODE_REVIEW
    result=$(get_affinity "CODE_REVIEW" "Codex")
    assert_equals "10" "$result" "Codex has max affinity for CODE_REVIEW"

    # Mistral => high for SECURITY
    result=$(get_affinity "SECURITY" "Mistral")
    assert_equals "10" "$result" "Mistral has max affinity for SECURITY"

    # DeepSeek => high for ALGORITHM
    result=$(get_affinity "ALGORITHM" "DeepSeek")
    assert_equals "10" "$result" "DeepSeek has max affinity for ALGORITHM"

    # Unknown consultant gets 5
    result=$(get_affinity "CODE_REVIEW" "UnknownBot")
    assert_equals "5" "$result" "unknown consultant gets default affinity 5"

    # GENERAL category gives all known consultants 8
    result=$(get_affinity "GENERAL" "Claude")
    assert_equals "8" "$result" "Claude gets 8 for GENERAL"
}

# =============================================================================
# TESTS: routing.sh - Consultant selection
# =============================================================================

test_consultant_selection() {
    suite "routing.sh: select_consultants"

    local result

    # ARCHITECTURE with min_affinity 9 should include Gemini and Amp (score 10)
    result=$(select_consultants "ARCHITECTURE" 9 20)
    assert_contains "Gemini" "$result" "Gemini selected for ARCHITECTURE (affinity 10)"
    assert_contains "Amp" "$result" "Amp selected for ARCHITECTURE (affinity 10)"

    # QUICK_SYNTAX with min_affinity 9 should include Gemini (10) and DeepSeek (9)
    result=$(select_consultants "QUICK_SYNTAX" 9 20)
    assert_contains "Gemini" "$result" "Gemini selected for QUICK_SYNTAX (affinity 10)"
    assert_contains "DeepSeek" "$result" "DeepSeek selected for QUICK_SYNTAX (affinity 9)"

    # Limit max consultants
    result=$(select_consultants "GENERAL" 1 3)
    local count
    count=$(echo "$result" | wc -l | tr -d ' ')
    assert_less_than_or_equal 3 "$count" "max_consultants=3 respected"
}

# =============================================================================
# TESTS: routing.sh - Routing modes
# =============================================================================

test_routing_modes() {
    suite "routing.sh: get_routing_mode / get_recommended_count"

    assert_equals "full"      "$(get_routing_mode "SECURITY")"    "SECURITY uses full routing"
    assert_equals "single"    "$(get_routing_mode "QUICK_SYNTAX")" "QUICK_SYNTAX uses single routing"
    assert_equals "selective"  "$(get_routing_mode "CODE_REVIEW")" "CODE_REVIEW uses selective routing"
    assert_equals "selective"  "$(get_routing_mode "ARCHITECTURE")" "ARCHITECTURE uses selective routing"
    assert_equals "full"      "$(get_routing_mode "GENERAL")"     "GENERAL uses full routing"

    assert_equals "10" "$(get_recommended_count "SECURITY")"    "SECURITY recommends 10 consultants"
    assert_equals "1"  "$(get_recommended_count "QUICK_SYNTAX")" "QUICK_SYNTAX recommends 1 consultant"
    assert_equals "5"  "$(get_recommended_count "CODE_REVIEW")" "CODE_REVIEW recommends 5 consultants"
}

# =============================================================================
# TESTS: routing.sh - Category timeout
# =============================================================================

test_category_timeouts() {
    suite "routing.sh: get_category_timeout"

    assert_equals "60"  "$(get_category_timeout "QUICK_SYNTAX")" "QUICK_SYNTAX timeout is 60s"
    assert_equals "240" "$(get_category_timeout "ARCHITECTURE")" "ARCHITECTURE timeout is 240s"
    assert_equals "240" "$(get_category_timeout "SECURITY")"     "SECURITY timeout is 240s"
    assert_equals "180" "$(get_category_timeout "GENERAL")"      "GENERAL timeout is 180s"
    assert_equals "120" "$(get_category_timeout "DATABASE")"     "DATABASE timeout is 120s"
}

# =============================================================================
# TESTS: routing.sh - is_recommended
# =============================================================================

test_is_recommended() {
    suite "routing.sh: is_recommended"

    assert_exit_code_success "Gemini recommended for ARCHITECTURE (10 >= 7)" is_recommended "ARCHITECTURE" "Gemini"
    assert_exit_code_failure "Codex not recommended for ARCHITECTURE at threshold 9 (6 < 9)" is_recommended "ARCHITECTURE" "Codex" 9
    assert_exit_code_success "Mistral recommended for SECURITY (10 >= 7)" is_recommended "SECURITY" "Mistral"
}

# =============================================================================
# TESTS: routing.sh - Escalation
# =============================================================================

test_escalation() {
    suite "routing.sh: needs_escalation / get_escalation_summary"

    local dir="$TEST_TMPDIR/escalation"

    # Low confidence => needs escalation
    create_mock_response "$dir" "low.json" "Gemini" "approach" 3
    assert_exit_code_success "low confidence (3) needs escalation" needs_escalation "$dir/low.json"

    # High confidence => no escalation
    create_mock_response "$dir" "high.json" "Gemini" "approach" 9
    assert_exit_code_failure "high confidence (9) does not need escalation" needs_escalation "$dir/high.json"

    # Missing file => needs escalation
    assert_exit_code_success "missing file needs escalation" needs_escalation "$dir/nonexistent.json"

    # Escalation summary
    local summary
    summary=$(get_escalation_summary "$dir/low.json" "Gemini")
    assert_valid_json "$summary" "escalation summary is valid JSON"
    assert_contains '"needs_escalation": true' "$summary" "low confidence flagged for escalation"

    rm -rf "$dir"
}

# =============================================================================
# TESTS: config.sh - Model tier lookup
# =============================================================================

test_model_for_tier() {
    suite "config.sh: get_model_for_tier"

    assert_equals "opus-4.6"              "$(get_model_for_tier "claude" "premium")"  "claude premium is opus-4.6"
    assert_equals "sonnet-4.6"            "$(get_model_for_tier "claude" "standard")" "claude standard is sonnet-4.6"
    assert_equals "haiku-4.5"             "$(get_model_for_tier "claude" "economy")"  "claude economy is haiku-4.5"
    assert_equals "gemini-3.1-pro-preview" "$(get_model_for_tier "gemini" "premium")" "gemini premium is gemini-3.1-pro-preview"
    assert_equals "gemini-2.0-flash"       "$(get_model_for_tier "gemini" "economy")" "gemini economy is gemini-2.0-flash"
    assert_equals "MiniMax-M2.7"           "$(get_model_for_tier "minimax" "premium")" "minimax premium is MiniMax-M2.7"
    assert_equals "MiniMax-M2.5"           "$(get_model_for_tier "minimax" "economy")" "minimax economy is MiniMax-M2.5"
    assert_equals "auto"                  "$(get_model_for_tier "kilo" "premium")"   "kilo always returns auto"

    # Unknown tier returns empty
    assert_equals "" "$(get_model_for_tier "claude" "mythical")" "unknown tier returns empty"
}

# =============================================================================
# TESTS: Integration - Voting report end-to-end
# =============================================================================

test_voting_report_integration() {
    suite "integration: generate_voting_report"

    local dir="$TEST_TMPDIR/report"
    create_mock_response "$dir" "gemini.json"  "Gemini"  "Microservices" 8
    create_mock_response "$dir" "codex.json"   "Codex"   "Microservices" 7
    create_mock_response "$dir" "mistral.json" "Mistral" "Monolith"      6

    local report
    report=$(generate_voting_report "$dir")
    assert_valid_json "$report" "voting report is valid JSON"
    assert_contains "consensus" "$report" "report includes consensus"
    assert_contains "recommendation" "$report" "report includes recommendation"
    assert_contains "average_confidence" "$report" "report includes average_confidence"
    assert_contains "confidence_interval" "$report" "report includes confidence_interval"
    assert_contains "final_weighted_score" "$report" "report includes final_weighted_score"

    local level
    level=$(echo "$report" | jq -r '.voting_report.consensus.level')
    # Microservices vs Monolith have some keyword overlap ("micro" shares nothing with "mono")
    # so consensus depends on Jaccard sim. Either way it should be a valid level string.
    assert_contains "$level" "unanimous high medium low none" "consensus level is a valid string"

    rm -rf "$dir"
}

# =============================================================================
# TESTS: Integration - Consultant list completeness
# =============================================================================

test_consultant_list_completeness() {
    suite "integration: ALL_CONSULTANTS completeness"

    local count=${#ALL_CONSULTANTS[@]}
    assert_equals "15" "$count" "ALL_CONSULTANTS has 15 entries"

    # Verify key consultants are present
    local all_str="${ALL_CONSULTANTS[*]}"
    assert_contains "Gemini" "$all_str" "Gemini in ALL_CONSULTANTS"
    assert_contains "Claude" "$all_str" "Claude in ALL_CONSULTANTS"
    assert_contains "MiniMax" "$all_str" "MiniMax in ALL_CONSULTANTS"
    assert_contains "Kimi" "$all_str" "Kimi in ALL_CONSULTANTS"
    assert_contains "Amp" "$all_str" "Amp in ALL_CONSULTANTS"
    assert_contains "Ollama" "$all_str" "Ollama in ALL_CONSULTANTS"
}

# =============================================================================
# TESTS: Integration - Persona catalog completeness
# =============================================================================

test_persona_catalog_completeness() {
    suite "integration: persona catalog has 21 entries"

    local count=0
    while IFS='|' read -r id name var desc; do
        [[ -z "$id" ]] && continue
        ((count++)) || true
    done <<< "$(echo "$PERSONA_CATALOG" | grep -v '^$')"

    assert_equals "21" "$count" "PERSONA_CATALOG has 21 personas"

    # Verify all catalog entries have valid variable references
    local errors=0
    while IFS='|' read -r id name var desc; do
        [[ -z "$id" ]] && continue
        if [[ -z "${!var:-}" ]]; then
            _fail "persona var $var (ID $id, $name) is empty or undefined"
            ((errors++)) || true
        fi
    done <<< "$(echo "$PERSONA_CATALOG" | grep -v '^$')"

    if [[ $errors -eq 0 ]]; then
        _pass "all 21 persona variables are defined and non-empty"
    fi
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    echo -e "${_C_BLUE}============================================${_C_RESET}"
    echo -e "${_C_BLUE}  AI Consultants - Comprehensive Test Suite ${_C_RESET}"
    echo -e "${_C_BLUE}============================================${_C_RESET}"
    local start_ts
    start_ts=$(date +%s)

    # common.sh tests
    test_case_conversion
    test_token_estimation
    test_file_validation
    test_sanitize_filename
    test_map_functions
    test_self_exclusion
    test_consultant_validation
    test_api_mode_helpers
    test_build_full_query
    test_known_agents

    # personas.sh tests
    test_persona_catalog
    test_persona_resolution
    test_persona_content
    test_system_prompt_builder
    test_normalize_name

    # voting.sh tests
    test_consensus_levels
    test_weighted_average
    test_consensus_score
    test_stemming
    test_jaccard_similarity
    test_confidence_stddev
    test_confidence_interval
    test_weighted_recommendation
    test_dissenters
    test_final_score
    test_simple_majority_vote

    # costs.sh tests
    test_cost_rates
    test_cost_estimation
    test_cost_formatting
    test_budget_checking
    test_query_complexity
    test_query_classification
    test_model_tiers
    test_economic_models
    test_response_limits
    test_budget_enforcement

    # cache.sh tests
    test_cache_fingerprint
    test_cache_store_retrieve
    test_cache_clear
    test_mark_from_cache

    # routing.sh tests
    test_routing_affinity
    test_consultant_selection
    test_routing_modes
    test_category_timeouts
    test_is_recommended
    test_escalation

    # config.sh tests
    test_model_for_tier

    # Integration tests
    test_voting_report_integration
    test_consultant_list_completeness
    test_persona_catalog_completeness

    # Summary
    local end_ts
    end_ts=$(date +%s)
    local duration=$((end_ts - start_ts))
    local total=$((_PASS_COUNT + _FAIL_COUNT + _SKIP_COUNT))

    echo -e "\n${_C_BLUE}============================================${_C_RESET}"
    echo -e "${_C_BLUE}  Results${_C_RESET}"
    echo -e "${_C_BLUE}============================================${_C_RESET}"
    echo -e "  Total:   $total"
    echo -e "  ${_C_GREEN}Passed:  $_PASS_COUNT${_C_RESET}"
    echo -e "  ${_C_RED}Failed:  $_FAIL_COUNT${_C_RESET}"
    [[ $_SKIP_COUNT -gt 0 ]] && echo -e "  ${_C_YELLOW}Skipped: $_SKIP_COUNT${_C_RESET}"
    echo -e "  Time:    ${duration}s"

    if [[ $_FAIL_COUNT -gt 0 ]]; then
        echo -e "\n${_C_RED}FAILED: $_FAIL_COUNT test(s) did not pass.${_C_RESET}"
        return 1
    else
        echo -e "\n${_C_GREEN}ALL TESTS PASSED.${_C_RESET}"
        return 0
    fi
}

main
